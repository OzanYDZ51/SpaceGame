class_name AIController
extends Node

# =============================================================================
# AI Controller — Unified orchestrator for NPC ships AND stations.
# Replaces AIBrain. 2 levels: Mode (IDLE/BEHAVIOR/COMBAT/DEAD) + pluggable Behavior.
# Backward-compatible public API for EncounterManager, ShipLODManager, etc.
# =============================================================================

# --- Mode (top-level state) ---
enum Mode { IDLE, BEHAVIOR, COMBAT, DEAD }

# Legacy State enum for backward compatibility with external code
# (npc_state_broadcaster, ship_lod_data, etc. read current_state)
enum State { IDLE, PATROL, PURSUE, ATTACK, FORMATION, MINING, LOOT_PICKUP, DEAD }

var mode: Mode = Mode.BEHAVIOR

# --- Modules ---
var perception: AIPerception = null
var combat: AICombat = null
var navigation: AINavigation = null
var environment: AIEnvironment = null

# --- Behaviors ---
var _current_behavior: AIBehavior = null
var _combat_behavior: CombatBehavior = null
var _default_behavior: AIBehavior = null  # What to return to after combat

# --- Behavior profile ---
var aggression: float = 0.5
var preferred_range: float = 500.0
var accuracy: float = 0.7
var weapons_enabled: bool = true
var ignore_threats: bool = false
var guard_station: Node3D = null
var route_priority: bool = false
var idle_after_combat: bool = false
var can_move: bool = true

# --- Detection (per-ship from ShipData) ---
var detection_range: float = Constants.AI_DETECTION_RANGE
var disengage_range: float = Constants.AI_DISENGAGE_RANGE

# --- Refs ---
var _ship = null
var _loot_pickup = null
var _health = null

# --- AI LOD tick ---
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL

# --- Legacy compat: current_state property ---
# Many external systems read/write current_state directly.
# This property maps Mode+Behavior to the old State enum.
var current_state: State:
	get:
		match mode:
			Mode.DEAD:
				return State.DEAD
			Mode.IDLE:
				return State.IDLE
			Mode.COMBAT:
				if _combat_behavior:
					match _combat_behavior.sub_state:
						CombatBehavior.SubState.ENGAGE:
							return State.PURSUE
						CombatBehavior.SubState.ATTACK_RUN:
							return State.ATTACK
						CombatBehavior.SubState.BREAK_OFF:
							return State.PURSUE
						CombatBehavior.SubState.REPOSITION:
							return State.PURSUE
				return State.PURSUE
			Mode.BEHAVIOR:
				if _current_behavior == null:
					return State.IDLE
				var bname: StringName = _current_behavior.get_behavior_name()
				match bname:
					AIBehavior.NAME_PATROL:
						return State.PATROL
					AIBehavior.NAME_FORMATION:
						return State.FORMATION
					AIBehavior.NAME_GUARD:
						return State.PATROL  # Guard shows as PATROL externally
					AIBehavior.NAME_LOOT:
						return State.LOOT_PICKUP
					_:
						return State.PATROL
		return State.IDLE
	set(value):
		# Legacy setter for external code that writes current_state directly
		match value:
			State.DEAD:
				mode = Mode.DEAD
			State.IDLE:
				mode = Mode.IDLE
				if _current_behavior:
					_current_behavior.exit()
					_current_behavior = null
			State.PATROL:
				mode = Mode.BEHAVIOR
				if _current_behavior == null or _current_behavior.get_behavior_name() != AIBehavior.NAME_PATROL:
					_switch_to_patrol()
			State.PURSUE, State.ATTACK:
				if mode != Mode.COMBAT:
					mode = Mode.COMBAT
					if _combat_behavior == null:
						_combat_behavior = CombatBehavior.new()
						_combat_behavior.controller = self
					_combat_behavior.enter()
			State.FORMATION:
				mode = Mode.BEHAVIOR
				if _current_behavior == null or _current_behavior.get_behavior_name() != AIBehavior.NAME_FORMATION:
					var fb := FormationBehavior.new()
					fb.controller = self
					_set_behavior(fb)
			State.MINING:
				mode = Mode.BEHAVIOR
				# Mining is external (AIMiningBehavior), just set mode
			State.LOOT_PICKUP:
				mode = Mode.BEHAVIOR
				var lb := LootBehavior.new()
				lb.controller = self
				_set_behavior(lb)

# --- Legacy compat: target property ---
var target: Node3D:
	get:
		if _combat_behavior:
			return _combat_behavior.target
		return null
	set(value):
		if value == null:
			if _combat_behavior:
				_combat_behavior.target = null
		else:
			if _combat_behavior == null:
				_combat_behavior = CombatBehavior.new()
				_combat_behavior.controller = self
			_combat_behavior.set_target(value)

# --- Legacy compat: formation properties ---
var formation_leader: Node3D:
	get:
		if _current_behavior and _current_behavior is FormationBehavior:
			return (_current_behavior as FormationBehavior).leader
		return null
	set(value):
		if _current_behavior and _current_behavior is FormationBehavior:
			(_current_behavior as FormationBehavior).leader = value
		else:
			var fb := FormationBehavior.new()
			fb.controller = self
			fb.leader = value
			_set_behavior(fb)
			mode = Mode.BEHAVIOR

var formation_offset: Vector3:
	get:
		if _current_behavior and _current_behavior is FormationBehavior:
			return (_current_behavior as FormationBehavior).offset
		return Vector3.ZERO
	set(value):
		if _current_behavior and _current_behavior is FormationBehavior:
			(_current_behavior as FormationBehavior).offset = value

# --- Legacy compat: patrol properties ---
var patrol_center_compat: Vector3:
	get:
		if _current_behavior and _current_behavior is PatrolBehavior:
			return (_current_behavior as PatrolBehavior).patrol_center
		return Vector3.ZERO

var patrol_radius_compat: float:
	get:
		if _current_behavior and _current_behavior is PatrolBehavior:
			return (_current_behavior as PatrolBehavior).patrol_radius
		return 0.0

var waypoints_compat: Array[Vector3]:
	get:
		if _current_behavior and _current_behavior is PatrolBehavior:
			return (_current_behavior as PatrolBehavior).waypoints
		return []
	set(value):
		if _current_behavior and _current_behavior is PatrolBehavior:
			(_current_behavior as PatrolBehavior).waypoints = value
		else:
			var pb := PatrolBehavior.new()
			pb.controller = self
			pb.waypoints = value
			_set_behavior(pb)
			mode = Mode.BEHAVIOR

var current_waypoint_compat: int:
	get:
		if _current_behavior and _current_behavior is PatrolBehavior:
			return (_current_behavior as PatrolBehavior).current_waypoint
		return 0
	set(value):
		if _current_behavior and _current_behavior is PatrolBehavior:
			(_current_behavior as PatrolBehavior).current_waypoint = value


func setup(behavior_name: StringName) -> void:
	match behavior_name:
		&"aggressive":
			aggression = 0.8; accuracy = 0.8
		&"defensive":
			aggression = 0.3; accuracy = 0.6
		&"balanced", &"hostile":
			aggression = 0.5; accuracy = 0.7


func setup_as_station(station: Node3D, _wm = null) -> void:
	_ship = station
	can_move = false
	perception = AIPerception.new()
	perception.setup(station)
	combat = AICombat.new()
	combat.setup(station)
	_combat_behavior = CombatBehavior.new()
	_combat_behavior.controller = self
	# No navigation for stations
	# Set up guard behavior in turret-only mode
	var gb := GuardBehavior.new()
	gb.controller = self
	gb.turret_only = true
	gb.set_guard_target(station)
	guard_station = station
	_set_behavior(gb)
	_default_behavior = gb
	mode = Mode.BEHAVIOR
	# Set detection range for station
	detection_range = Constants.AI_DETECTION_RANGE
	# Connect structure damage so station reacts when attacked
	var sh = station.get_node_or_null("StructureHealth")
	if sh:
		sh.damage_taken.connect(_on_damage_taken)


func _ready() -> void:
	# Station mode: setup_as_station() was called before add_child(), skip ship init
	if _ship != null:
		_tick_timer = randf() * TICK_INTERVAL
		FloatingOrigin.origin_shifted.connect(_on_origin_shifted)
		return

	_ship = get_parent()

	# Create modules + combat behavior immediately (before await)
	perception = AIPerception.new()
	combat = AICombat.new()
	environment = AIEnvironment.new()
	_combat_behavior = CombatBehavior.new()
	_combat_behavior.controller = self

	# Random initial tick offset
	_tick_timer = randf() * TICK_INTERVAL

	await get_tree().process_frame

	if _ship:
		perception.setup(_ship)
		combat.setup(_ship)

		navigation = _ship.get_node_or_null("AINavigation")
		_health = _ship.get_node_or_null("HealthSystem")
		_loot_pickup = _ship.get_node_or_null("LootPickupSystem")

		if "ship_data" in _ship and _ship.ship_data:
			detection_range = _ship.ship_data.sensor_range
			preferred_range = _ship.ship_data.engagement_range
			disengage_range = _ship.ship_data.disengage_range

		if _health:
			_health.damage_taken.connect(_on_damage_taken)

		environment.setup(_ship, navigation)
		environment.update_environment()

	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)

	# Default to patrol behavior
	if _current_behavior == null:
		_switch_to_patrol()

	# If patrol center not set, use spawn position
	if _current_behavior and _current_behavior is PatrolBehavior:
		var pb := _current_behavior as PatrolBehavior
		if pb.patrol_center == Vector3.ZERO and _ship:
			pb.patrol_center = _ship.global_position
			pb._generate_patrol_waypoints()

	_default_behavior = _current_behavior


func _process(delta: float) -> void:
	if _ship == null:
		return
	if mode == Mode.DEAD:
		return
	if not can_move and navigation == null:
		# Station mode — skip nav checks
		pass
	elif navigation == null:
		return

	# Turrets track + auto-fire every frame
	if combat:
		var can_fire: bool = mode == Mode.COMBAT or (route_priority and _current_behavior and _current_behavior.get_behavior_name() == AIBehavior.NAME_PATROL)
		if _combat_behavior and _combat_behavior.target and is_instance_valid(_combat_behavior.target) and weapons_enabled and can_fire:
			combat.update_turrets(_combat_behavior.target)
		else:
			combat.update_turrets(null)

	_tick_timer -= delta
	if _tick_timer > 0.0:
		return

	# AI LOD: reduce tick rate based on distance to player
	var tick_rate := TICK_INTERVAL
	var player := GameManager.player_ship
	if player and is_instance_valid(player):
		var dist: float = _ship.global_position.distance_to(player.global_position)
		if dist > Constants.AI_LOD_TICK_FAR_DIST:
			tick_rate = TICK_INTERVAL * 10.0
		elif dist > Constants.AI_LOD_TICK_MID_DIST:
			tick_rate = TICK_INTERVAL * 3.0
	_tick_timer = tick_rate

	# Check death
	if _health and _health.is_dead():
		mode = Mode.DEAD
		if can_move and _ship:
			_ship.set_throttle(Vector3.ZERO)
			_ship.set_rotation_target(0.0, 0.0, 0.0)
		return

	# Decay threat table
	var now_ms: float = Time.get_ticks_msec()
	var real_dt: float = (now_ms - perception.last_threat_update_ms) * 0.001 if perception.last_threat_update_ms > 0.0 else tick_rate
	perception.last_threat_update_ms = now_ms
	perception.update(real_dt)

	# Periodic environment scan (ships only)
	if environment:
		environment.tick(tick_rate)

	match mode:
		Mode.IDLE:
			_tick_idle()
		Mode.BEHAVIOR:
			_tick_behavior(tick_rate)
		Mode.COMBAT:
			_tick_combat(tick_rate)


func _tick_idle() -> void:
	# Check for threats
	if not ignore_threats and weapons_enabled:
		var threat = perception.detect_nearest_hostile(detection_range)
		if threat == null:
			threat = perception.get_highest_threat()
		if threat:
			_enter_combat(threat)
			return
	# Check for loot
	if _loot_pickup and _loot_pickup.can_pickup and _loot_pickup.nearest_crate:
		var lb := LootBehavior.new()
		lb.controller = self
		_set_behavior(lb)
		mode = Mode.BEHAVIOR


func _tick_behavior(dt: float) -> void:
	if _current_behavior == null:
		mode = Mode.IDLE
		return

	# Detect threats (unless ignoring)
	if not ignore_threats and weapons_enabled:
		if route_priority and _current_behavior.get_behavior_name() == AIBehavior.NAME_PATROL:
			# Route priority = DEFENSIVE: only engage threats from threat table (damage received)
			# Do NOT proactively scan for hostiles — convoys should not attack on sight
			var best_threat = perception.get_highest_threat()
			if best_threat:
				if _ship and _ship.speed_mode == Constants.SpeedMode.CRUISE:
					_ship._exit_cruise()
				if combat:
					combat.try_fire_forward(best_threat, accuracy, guard_station)
				_combat_behavior.set_target(best_threat)
				_alert_formation_group(best_threat)
				# Abandon route if hull critically low
				if _health and _health.get_hull_ratio() < 0.5:
					_enter_combat(best_threat)
				# Don't return — let patrol behavior continue ticking (keep moving)
			# Fall through to behavior tick below
		else:
			var threat = perception.detect_nearest_hostile(detection_range)
			if threat:
				_enter_combat(threat)
				return
			# Fallback: check threat table for attackers that faction check missed
			# (e.g. same-faction player attacking guards/station)
			var table_threat = perception.get_highest_threat()
			if table_threat:
				_enter_combat(table_threat)
				return

	# Check for loot during patrol
	if _current_behavior.get_behavior_name() == AIBehavior.NAME_PATROL:
		if _loot_pickup and _loot_pickup.can_pickup and _loot_pickup.nearest_crate:
			var lb := LootBehavior.new()
			lb.controller = self
			_set_behavior(lb)
			return

	_current_behavior.tick(dt)


func _tick_combat(dt: float) -> void:
	if _combat_behavior == null:
		_end_combat()
		return
	_combat_behavior.tick(dt)


# =============================================================================
# COMBAT TRANSITIONS
# =============================================================================
func _enter_combat(threat: Node3D) -> void:
	if mode == Mode.COMBAT:
		_combat_behavior.set_target(threat)
		return
	# Save current behavior as default to return to (only if not already in combat)
	if _current_behavior and mode != Mode.COMBAT:
		_default_behavior = _current_behavior
		_current_behavior = null
	mode = Mode.COMBAT
	_combat_behavior.set_target(threat)
	_combat_behavior.enter()
	# Exit cruise
	if can_move and _ship and _ship.speed_mode == Constants.SpeedMode.CRUISE:
		_ship._exit_cruise()


func _end_combat() -> void:
	_combat_behavior.exit()
	_return_to_default_behavior()


func _return_to_default_behavior() -> void:
	if _default_behavior:
		_set_behavior(_default_behavior)
		mode = Mode.BEHAVIOR
	else:
		mode = Mode.IDLE if idle_after_combat else Mode.BEHAVIOR
		if mode == Mode.BEHAVIOR:
			_switch_to_patrol()


# =============================================================================
# BEHAVIOR MANAGEMENT
# =============================================================================
func _set_behavior(behavior: AIBehavior) -> void:
	if _current_behavior:
		_current_behavior.exit()
	_current_behavior = behavior
	if behavior:
		behavior.controller = self
		behavior.enter()


func _switch_to_patrol() -> void:
	var pb := PatrolBehavior.new()
	pb.controller = self
	_set_behavior(pb)
	_default_behavior = pb


# =============================================================================
# PUBLIC API (backward-compatible with AIBrain)
# =============================================================================
func set_patrol_area(center: Vector3, radius: float) -> void:
	var pb: PatrolBehavior
	if _current_behavior and _current_behavior is PatrolBehavior:
		pb = _current_behavior as PatrolBehavior
	else:
		pb = PatrolBehavior.new()
		pb.controller = self
		_set_behavior(pb)
		mode = Mode.BEHAVIOR
	pb.set_patrol_area(center, radius)
	_default_behavior = pb


func shift_patrol_waypoints(new_center: Vector3, new_radius: float) -> void:
	if _current_behavior and _current_behavior is PatrolBehavior:
		(_current_behavior as PatrolBehavior).shift_patrol_waypoints(new_center, new_radius)


func set_route(waypoints: Array[Vector3]) -> void:
	var pb: PatrolBehavior
	if _current_behavior and _current_behavior is PatrolBehavior:
		pb = _current_behavior as PatrolBehavior
	else:
		pb = PatrolBehavior.new()
		pb.controller = self
		_set_behavior(pb)
		mode = Mode.BEHAVIOR
	pb.set_route(waypoints)
	_default_behavior = pb


func alert_to_threat(attacker: Node3D) -> void:
	if mode == Mode.DEAD or ignore_threats or not weapons_enabled:
		return
	perception.alert_to_threat(attacker)
	if mode in [Mode.IDLE, Mode.BEHAVIOR]:
		if _current_behavior == null or _current_behavior.get_behavior_name() != AIBehavior.NAME_COMBAT:
			_enter_combat(attacker)
	elif mode == Mode.COMBAT:
		# Already fighting — evaluate if the new threat is more dangerous than current target
		var at_target: Node3D = _combat_behavior.target
		if at_target and is_instance_valid(at_target):
			var switch_to = perception.maybe_switch_target(at_target)
			if switch_to:
				_combat_behavior.set_target(switch_to)


# =============================================================================
# DAMAGE HANDLING
# =============================================================================
func _on_damage_taken(attacker: Node3D, amount: float = 0.0) -> void:
	if mode == Mode.DEAD or not weapons_enabled:
		return
	if ignore_threats:
		return

	var effective_attacker: Node3D = attacker

	var result: Dictionary = perception.on_damage_taken(attacker, amount)
	if result.is_empty():
		var threat = perception.detect_nearest_hostile(detection_range)
		if threat:
			effective_attacker = threat
		else:
			return

	# Propagate aggro to station and fellow guards
	if guard_station and is_instance_valid(guard_station) and effective_attacker and is_instance_valid(effective_attacker):
		# Station alert: find guard behavior on station's AIController
		var station_ctrl = guard_station.get_node_or_null("AIController")
		if station_ctrl:
			# Alert station turrets
			station_ctrl.perception.alert_to_threat(effective_attacker)
			# Alert guards via guard behavior
			if station_ctrl._current_behavior and station_ctrl._current_behavior is GuardBehavior:
				(station_ctrl._current_behavior as GuardBehavior)._alert_nearby_guards(effective_attacker)

	# Alert formation group
	if effective_attacker and is_instance_valid(effective_attacker):
		_alert_formation_group(effective_attacker)

	# Route-priority leaders: fire but keep patrolling unless badly hurt
	if mode == Mode.BEHAVIOR and route_priority and _current_behavior and _current_behavior.get_behavior_name() == AIBehavior.NAME_PATROL:
		_combat_behavior.set_target(effective_attacker)
		if _health and _health.get_hull_ratio() < 0.5:
			_enter_combat(effective_attacker)
		return

	if mode in [Mode.IDLE, Mode.BEHAVIOR]:
		_enter_combat(effective_attacker)
		return

	if mode == Mode.COMBAT:
		var cur_target: Node3D = _combat_behavior.target
		if effective_attacker != cur_target and cur_target and is_instance_valid(cur_target):
			# Switch immediately if:
			# 1. Current target is a structure (station) — mobile attacker is always priority
			# 2. Current target hasn't hit us recently — it's no longer a real threat
			var force_switch: bool = false
			if cur_target.is_in_group("structures"):
				force_switch = true
			elif not perception.has_recent_threat(cur_target):
				force_switch = true
			if force_switch:
				_combat_behavior.set_target(effective_attacker)
				return
		var dmg_target: Node3D = _combat_behavior.target
		if dmg_target and is_instance_valid(dmg_target):
			var switch_to = perception.maybe_switch_target(dmg_target)
			if switch_to:
				_combat_behavior.set_target(switch_to)


func _alert_formation_group(attacker: Node3D) -> void:
	if not is_instance_valid(attacker):
		return

	# Alert our formation leader
	var leader: Node3D = null
	if _current_behavior and _current_behavior is FormationBehavior:
		leader = (_current_behavior as FormationBehavior).leader
	if leader and is_instance_valid(leader):
		var leader_ctrl = leader.get_node_or_null("AIController")
		if leader_ctrl:
			leader_ctrl.alert_to_threat(attacker)

	# Alert all ships in our formation group
	if not _ship.is_inside_tree():
		return
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == _ship or not is_instance_valid(ship):
			continue
		var ctrl = ship.get_node_or_null("AIController")
		if ctrl == null:
			continue
		# Our wingmen (ships whose leader == _ship)
		if ctrl._current_behavior and ctrl._current_behavior is FormationBehavior:
			var fb := ctrl._current_behavior as FormationBehavior
			if fb.leader == _ship:
				ctrl.alert_to_threat(attacker)
			elif leader and fb.leader == leader:
				ctrl.alert_to_threat(attacker)


# =============================================================================
# ORIGIN SHIFT
# =============================================================================
func _on_origin_shifted(shift: Vector3) -> void:
	# Shift patrol waypoints in active behavior
	if _current_behavior and _current_behavior is PatrolBehavior:
		(_current_behavior as PatrolBehavior).apply_origin_shift(shift)
	# Also shift the saved default behavior if it's a different PatrolBehavior
	if _default_behavior and _default_behavior is PatrolBehavior and _default_behavior != _current_behavior:
		(_default_behavior as PatrolBehavior).apply_origin_shift(shift)
	# Shift combat behavior's reposition point
	if _combat_behavior and _combat_behavior._reposition_point != Vector3.ZERO:
		_combat_behavior._reposition_point += shift
	# Shift guard behavior's internal patrol if active behavior is GuardBehavior
	if _current_behavior and _current_behavior is GuardBehavior:
		var gb := _current_behavior as GuardBehavior
		if gb._patrol:
			gb._patrol.apply_origin_shift(shift)
