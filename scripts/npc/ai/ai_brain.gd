class_name AIBrain
extends Node

# =============================================================================
# AI Brain - High-level behavior state machine for NPC ships
# States: IDLE, PATROL, PURSUE, ATTACK, FORMATION, MINING, LOOT_PICKUP, DEAD
# Ticks at 10Hz for performance.
# Environment + threats delegated to AIBrainEnvironment / AIBrainThreats.
# =============================================================================

enum State { IDLE, PATROL, PURSUE, ATTACK, FORMATION, MINING, LOOT_PICKUP, DEAD }

var current_state: State = State.PATROL
var target: Node3D = null
var formation_leader: Node3D = null
var formation_offset: Vector3 = Vector3.ZERO

# Behavior profile
var aggression: float = 0.5
var preferred_range: float = 500.0
var accuracy: float = 0.7
var formation_discipline: float = 0.8
var weapons_enabled: bool = true
var ignore_threats: bool = false
var guard_station: Node3D = null
var route_priority: bool = false
var idle_after_combat: bool = false

# Detection — per-ship from ShipData, fallback to Constants
var detection_range: float = Constants.AI_DETECTION_RANGE
var disengage_range: float = Constants.AI_DISENGAGE_RANGE

# Patrol
var _waypoints: Array[Vector3] = []
var _current_waypoint: int = 0
var _patrol_center: Vector3 = Vector3.ZERO
var _patrol_radius: float = 300.0

# Sub-objects
var _env: AIBrainEnvironment = null
var _threats: AIBrainThreats = null

# AI tick
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL
const MIN_SAFE_DIST: float = 50.0
const STATION_MODEL_RADIUS: float = 2000.0

var _ship = null
var _pilot = null
var _health = null
var _loot_pickup = null
var _debug_timer: float = 0.0
var _cached_target_health = null
var _cached_target_ref: Node3D = null


func setup(behavior_name: StringName) -> void:
	match behavior_name:
		&"aggressive":
			aggression = 0.8; accuracy = 0.8
		&"defensive":
			aggression = 0.3; accuracy = 0.6
		&"balanced", &"hostile":
			aggression = 0.5; accuracy = 0.7
		_:
			pass


func _ready() -> void:
	_ship = get_parent()
	# Create sub-objects
	_env = AIBrainEnvironment.new()
	_threats = AIBrainThreats.new()

	await get_tree().process_frame
	_pilot = _ship.get_node_or_null("AIPilot") if _ship else null
	_health = _ship.get_node_or_null("HealthSystem") if _ship else null
	_loot_pickup = _ship.get_node_or_null("LootPickupSystem") if _ship else null

	if _ship and _ship.ship_data:
		detection_range = _ship.ship_data.sensor_range
		preferred_range = _ship.ship_data.engagement_range
		disengage_range = _ship.ship_data.disengage_range

	if _health:
		_health.damage_taken.connect(_on_damage_taken)

	# Initialize sub-objects
	if _ship:
		_env.setup(_ship, _pilot)
		_threats.setup(_ship)

	if _ship:
		if _patrol_center == Vector3.ZERO:
			_patrol_center = _ship.global_position
		_env.update_environment()
		_generate_patrol_waypoints()


func _process(delta: float) -> void:
	if _ship == null or _pilot == null:
		return
	if current_state == State.DEAD:
		return

	# Turrets track + auto-fire every frame
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm:
		var can_fire: bool = current_state in [State.ATTACK, State.PURSUE] or (route_priority and current_state == State.PATROL)
		if target and is_instance_valid(target) and weapons_enabled and can_fire:
			wm.update_turrets(target)
		else:
			wm.update_turrets(null)

	_tick_timer -= delta
	if _tick_timer > 0.0:
		return

	# AI LOD: reduce tick rate based on distance to player
	var tick_rate =TICK_INTERVAL
	var player =GameManager.player_ship
	if player and is_instance_valid(player):
		var dist: float = _ship.global_position.distance_to(player.global_position)
		if dist > 5000.0:
			tick_rate = TICK_INTERVAL * 10.0
		elif dist > 2000.0:
			tick_rate = TICK_INTERVAL * 3.0
	_tick_timer = tick_rate

	# Check death
	if _health and _health.is_dead():
		current_state = State.DEAD
		_ship.set_throttle(Vector3.ZERO)
		_ship.set_rotation_target(0.0, 0.0, 0.0)
		return

	# Decay and cleanup threat table (real elapsed time)
	var now_ms: float = Time.get_ticks_msec()
	var real_dt: float = (now_ms - _threats._last_threat_update_ms) * 0.001 if _threats._last_threat_update_ms > 0.0 else tick_rate
	_threats._last_threat_update_ms = now_ms
	_threats.update_threat_table(real_dt)

	# Periodic environment scan
	_env.tick(tick_rate)
	# Regenerate waypoints if inside obstacle zone
	if _env.near_obstacle and current_state == State.PATROL:
		_generate_patrol_waypoints()

	match current_state:
		State.IDLE:
			_tick_idle()
		State.PATROL:
			_tick_patrol()
		State.PURSUE:
			_tick_pursue()
		State.ATTACK:
			_tick_attack(delta)
		State.FORMATION:
			_tick_formation()
		State.MINING:
			_tick_mining()
		State.LOOT_PICKUP:
			_tick_loot_pickup()

	_debug_timer -= TICK_INTERVAL


# =============================================================================
# STATE TICKS
# =============================================================================
func _default_state() -> State:
	if formation_leader and is_instance_valid(formation_leader):
		return State.FORMATION
	return State.IDLE if idle_after_combat else State.PATROL


func _tick_idle() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE


func _tick_patrol() -> void:
	_detect_threats()
	if target:
		if route_priority:
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if weapons_enabled:
				_pilot.fire_at_target(target, accuracy * 0.7)
		else:
			current_state = State.PURSUE
			return

	if _loot_pickup and _loot_pickup.can_pickup and _loot_pickup.nearest_crate:
		current_state = State.LOOT_PICKUP
		return

	# Guard ships: recenter patrol if too far from station
	if guard_station and is_instance_valid(guard_station) and _ship:
		var dist_to_station: float = _ship.global_position.distance_to(guard_station.global_position)
		if dist_to_station > _patrol_radius * 2.0:
			var dir_from_station: Vector3 = (_ship.global_position - guard_station.global_position)
			if dir_from_station.length_squared() > 1.0:
				dir_from_station = dir_from_station.normalized()
			else:
				dir_from_station = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var offset_center: Vector3 = guard_station.global_position + dir_from_station * (STATION_MODEL_RADIUS + 500.0)
			set_patrol_area(offset_center, _patrol_radius)

	if _waypoints.is_empty():
		return

	var arrival: float
	if _patrol_radius <= 0.0:
		arrival = 80.0
	elif _env.in_asteroid_belt:
		arrival = 150.0 if _patrol_radius >= 150.0 else maxf(_patrol_radius * 0.6, 15.0)
	else:
		arrival = 80.0 if _patrol_radius >= 80.0 else maxf(_patrol_radius * 0.6, 15.0)

	var wp: Vector3 = _waypoints[_current_waypoint]
	wp = _env.deflect_from_obstacles(wp)
	_pilot.fly_toward(wp, arrival)

	if _pilot.get_distance_to(_waypoints[_current_waypoint]) < arrival:
		_current_waypoint = (_current_waypoint + 1) % _waypoints.size()


func _tick_pursue() -> void:
	if not _is_target_valid():
		target = _threats.get_highest_threat()
		if target == null:
			current_state = _default_state()
		return

	if _env.check_obstacle_emergency():
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	if dist < MIN_SAFE_DIST:
		var away =(_ship.global_position - target.global_position).normalized()
		_pilot.fly_toward(_ship.global_position + away * 300.0, 10.0)
		return

	if dist > disengage_range:
		target = _threats.get_highest_threat()
		if target == null:
			current_state = _default_state()
		return

	var engage_mult =2.0 if _env.in_asteroid_belt else 1.5
	if dist <= preferred_range * engage_mult:
		current_state = State.ATTACK
		return

	_pilot.fly_intercept(target, preferred_range)

	if dist < preferred_range and weapons_enabled:
		_pilot.fire_at_target(target, accuracy * 0.6)


func _tick_attack(_delta: float) -> void:
	if not _is_target_valid():
		target = _threats.get_highest_threat()
		if target == null:
			current_state = _default_state()
		else:
			current_state = State.PURSUE
		return

	if _env.check_obstacle_emergency():
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	if dist < MIN_SAFE_DIST:
		var away =(_ship.global_position - target.global_position).normalized()
		_pilot.fly_toward(_ship.global_position + away * 300.0, 10.0)
		return

	if dist > disengage_range:
		target = _threats.get_highest_threat()
		if target == null:
			current_state = _default_state()
		else:
			current_state = State.PURSUE
		return

	_pilot.update_combat_maneuver(TICK_INTERVAL)

	if dist > preferred_range * 1.3:
		_pilot.fly_intercept(target, preferred_range)
	else:
		var lead_pos =target.global_position
		if target is RigidBody3D:
			var tvel: Vector3 = (target as RigidBody3D).linear_velocity
			var closing =maxf(-(_ship.linear_velocity - tvel).dot((target.global_position - _ship.global_position).normalized()), 10.0)
			var tti =clampf(dist / closing, 0.0, 3.0)
			lead_pos += tvel * tti
		_pilot.face_target(lead_pos)
		_pilot.apply_attack_throttle(dist, preferred_range)

	if weapons_enabled:
		_pilot.fire_at_target(target, accuracy)


func _tick_formation() -> void:
	if formation_leader == null or not is_instance_valid(formation_leader):
		current_state = _default_state()
		return

	var leader_basis: Basis = formation_leader.global_transform.basis
	var target_pos: Vector3 = formation_leader.global_position + leader_basis * formation_offset
	_pilot.fly_toward(target_pos, 20.0)

	if weapons_enabled and formation_leader.has_node("AIBrain"):
		var leader_brain = formation_leader.get_node("AIBrain")
		if leader_brain and leader_brain.target:
			target = leader_brain.target
			current_state = State.ATTACK


func _tick_mining() -> void:
	pass


func _tick_loot_pickup() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE
		return

	if _loot_pickup == null or not _loot_pickup.can_pickup:
		current_state = _default_state()
		return

	var crate: CargoCrate = _loot_pickup.nearest_crate
	if crate == null or not is_instance_valid(crate):
		current_state = _default_state()
		return

	var crate_pos: Vector3 = crate.global_position
	_pilot.fly_toward(crate_pos, 30.0)

	if _pilot.get_distance_to(crate_pos) < _loot_pickup.pickup_range * 0.15:
		crate.collect()
		current_state = _default_state()


# =============================================================================
# THREAT DETECTION (delegates to AIBrainThreats)
# =============================================================================
func _detect_threats() -> void:
	var threat = _threats.detect_threats(detection_range, weapons_enabled, ignore_threats)
	if threat:
		target = threat


func _is_target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree():
		return false
	if _cached_target_ref != target:
		_cached_target_ref = target
		_cached_target_health = target.get_node_or_null("HealthSystem")
	if _cached_target_health and _cached_target_health.is_dead():
		return false
	return true


func _is_faction_allied(target_faction: StringName, target_id: StringName = &"") -> bool:
	return _threats.is_faction_allied(target_faction, target_id)


# =============================================================================
# PATROL WAYPOINTS
# =============================================================================
func _generate_patrol_waypoints() -> void:
	_waypoints.clear()
	if _patrol_radius <= 0.0:
		_waypoints.append(_patrol_center)
		return
	for i in 4:
		var angle: float = (float(i) / 4.0) * TAU
		var wp =_patrol_center + Vector3(
			cos(angle) * _patrol_radius,
			randf_range(-50.0, 50.0),
			sin(angle) * _patrol_radius,
		)
		wp = _env.push_away_from_obstacles(wp)
		_waypoints.append(wp)


func set_patrol_area(center: Vector3, radius: float) -> void:
	_patrol_center = center
	_patrol_radius = radius
	_current_waypoint = 0
	_env.update_environment()
	_generate_patrol_waypoints()


func shift_patrol_waypoints(new_center: Vector3, new_radius: float) -> void:
	var shift: Vector3 = new_center - _patrol_center
	_patrol_center = new_center
	_patrol_radius = new_radius
	for i in range(_waypoints.size()):
		_waypoints[i] += shift


func set_route(waypoints: Array[Vector3]) -> void:
	_waypoints = waypoints
	_current_waypoint = 0
	if not waypoints.is_empty():
		_patrol_center = waypoints[0]
		var max_dist: float = 0.0
		for wp in waypoints:
			max_dist = maxf(max_dist, _patrol_center.distance_to(wp))
		_patrol_radius = max_dist + 5000.0


# =============================================================================
# DAMAGE / THREAT TABLE (delegates to AIBrainThreats)
# =============================================================================
func _on_damage_taken(attacker: Node3D, amount: float = 0.0) -> void:
	if current_state == State.DEAD or not weapons_enabled:
		return
	if ignore_threats:
		return

	var result: Dictionary = _threats.on_damage_taken(attacker, amount)
	if result.is_empty():
		return

	# Propagate aggro to station and fellow guards
	if guard_station and is_instance_valid(guard_station):
		var defense_ai = guard_station.get_node_or_null("StationDefenseAI")
		if defense_ai:
			defense_ai.alert_guards(attacker)

	if current_state == State.IDLE or (current_state == State.PATROL and not route_priority):
		target = attacker
		current_state = State.PURSUE
		return

	if current_state in [State.PURSUE, State.ATTACK]:
		var switch_to = _threats.maybe_switch_target(target)
		if switch_to:
			target = switch_to


func alert_to_threat(attacker: Node3D) -> void:
	if current_state == State.DEAD or ignore_threats or not weapons_enabled:
		return
	_threats.alert_to_threat(attacker)
	if current_state in [State.IDLE, State.PATROL, State.FORMATION]:
		target = attacker
		current_state = State.PURSUE
