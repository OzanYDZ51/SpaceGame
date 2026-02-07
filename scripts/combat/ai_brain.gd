class_name AIBrain
extends Node

# =============================================================================
# AI Brain - High-level behavior state machine for NPC ships
# States: IDLE, PATROL, PURSUE, ATTACK, EVADE, FLEE, FORMATION, DEAD
# Ticks at 10Hz for performance.
# =============================================================================

enum State { IDLE, PATROL, PURSUE, ATTACK, EVADE, FLEE, FORMATION, DEAD }

var current_state: State = State.PATROL
var target: Node3D = null
var formation_leader: Node3D = null
var formation_offset: Vector3 = Vector3.ZERO

# Behavior profile
var aggression: float = 0.5
var preferred_range: float = 500.0
var evasion_frequency: float = 2.0
var evasion_amplitude: float = 30.0
var flee_threshold: float = 0.2
var accuracy: float = 0.7
var formation_discipline: float = 0.8
var weapons_enabled: bool = true  # LOD1 ships: move + evade but don't fire

# Detection
const DETECTION_RANGE: float = 3000.0
const ENGAGEMENT_RANGE: float = 1500.0
const DISENGAGE_RANGE: float = 4000.0

# Patrol
var _waypoints: Array[Vector3] = []
var _current_waypoint: int = 0
var _patrol_center: Vector3 = Vector3.ZERO
var _patrol_radius: float = 300.0

# AI tick
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = 0.1  # 10Hz

var _ship: ShipController = null
var _pilot: AIPilot = null
var _health: HealthSystem = null
var _evade_timer: float = 0.0
var _debug_timer: float = 0.0


func setup(behavior_name: StringName) -> void:
	match behavior_name:
		&"aggressive":
			aggression = 0.8; preferred_range = 300.0; evasion_frequency = 1.5
			evasion_amplitude = 25.0; flee_threshold = 0.1; accuracy = 0.8
		&"defensive":
			aggression = 0.3; preferred_range = 800.0; evasion_frequency = 3.0
			evasion_amplitude = 40.0; flee_threshold = 0.3; accuracy = 0.6
		&"balanced", &"hostile":
			aggression = 0.5; preferred_range = 500.0; evasion_frequency = 2.0
			evasion_amplitude = 30.0; flee_threshold = 0.2; accuracy = 0.7
		_:
			pass  # Use defaults


func _ready() -> void:
	_ship = get_parent() as ShipController
	# Defer pilot/health lookup since they may not exist yet
	await get_tree().process_frame
	_pilot = _ship.get_node_or_null("AIPilot") as AIPilot if _ship else null
	_health = _ship.get_node_or_null("HealthSystem") as HealthSystem if _ship else null

	# React to damage: if patrolling/idle and get shot, immediately pursue the attacker
	if _health:
		_health.damage_taken.connect(_on_damage_taken)

	# Generate initial patrol waypoints
	if _ship:
		_patrol_center = _ship.global_position
		_generate_patrol_waypoints()


func _process(delta: float) -> void:
	if _ship == null or _pilot == null:
		return
	if current_state == State.DEAD:
		return

	_tick_timer -= delta
	if _tick_timer > 0.0:
		return

	# AI LOD: reduce tick rate based on distance to player
	var tick_rate := TICK_INTERVAL
	var player := GameManager.player_ship
	if player and is_instance_valid(player):
		var dist: float = _ship.global_position.distance_to(player.global_position)
		if dist > 5000.0:
			tick_rate = TICK_INTERVAL * 10.0  # ~1Hz when very far
		elif dist > 2000.0:
			tick_rate = TICK_INTERVAL * 3.0  # ~3Hz when medium distance
	_tick_timer = tick_rate

	# Check death
	if _health and _health.is_dead():
		current_state = State.DEAD
		_ship.set_throttle(Vector3.ZERO)
		_ship.set_rotation_target(0.0, 0.0, 0.0)
		return

	match current_state:
		State.IDLE:
			_tick_idle()
		State.PATROL:
			_tick_patrol()
		State.PURSUE:
			_tick_pursue()
		State.ATTACK:
			_tick_attack(delta)
		State.EVADE:
			_tick_evade(delta)
		State.FLEE:
			_tick_flee()
		State.FORMATION:
			_tick_formation()

	# DEBUG: periodic state report
	_debug_timer -= TICK_INTERVAL


func _tick_idle() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE


func _tick_patrol() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE
		return

	# Move to current waypoint
	if _waypoints.is_empty():
		return

	var wp: Vector3 = _waypoints[_current_waypoint]
	_pilot.fly_toward(wp, 80.0)

	# Check if reached waypoint
	if _pilot.get_distance_to(wp) < 80.0:
		_current_waypoint = (_current_waypoint + 1) % _waypoints.size()


func _tick_pursue() -> void:
	if not _is_target_valid():
		current_state = State.PATROL
		target = null
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	# Disengage if too far
	if dist > DISENGAGE_RANGE:
		current_state = State.PATROL
		target = null
		return

	# Engage when in range
	if dist <= preferred_range * 1.5:
		current_state = State.ATTACK
		return

	_pilot.fly_intercept(target, preferred_range)

	# Start shooting while pursuing if close enough
	if dist < ENGAGEMENT_RANGE and weapons_enabled:
		_pilot.fire_at_target(target, accuracy * 0.6)


func _tick_attack(_delta: float) -> void:
	if not _is_target_valid():
		current_state = State.PATROL
		target = null
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	# Check flee condition
	if _health and _health.get_hull_ratio() < flee_threshold:
		current_state = State.FLEE
		return

	# Check evade condition (shields down + hull taking damage)
	if _health and _health.get_total_shield_ratio() < 0.15 and randf() < aggression * 0.3:
		current_state = State.EVADE
		_evade_timer = randf_range(1.5, 3.0)
		return

	# Disengage if too far
	if dist > DISENGAGE_RANGE:
		current_state = State.PATROL
		target = null
		return

	# Update persistent maneuver direction (changes every 1-2.5s, not every tick)
	_pilot.update_combat_maneuver(TICK_INTERVAL)

	# Navigate: maintain preferred range with smooth maneuvers
	if dist > preferred_range * 1.3:
		_pilot.fly_intercept(target, preferred_range)
	else:
		# Face lead position for aiming
		var lead_pos := target.global_position
		if target is RigidBody3D:
			var tvel: Vector3 = (target as RigidBody3D).linear_velocity
			var closing := maxf(-(_ship.linear_velocity - tvel).dot((target.global_position - _ship.global_position).normalized()), 10.0)
			var tti := clampf(dist / closing, 0.0, 3.0)
			lead_pos += tvel * tti
		_pilot.face_target(lead_pos)
		_pilot.apply_attack_throttle(dist, preferred_range)

	# Fire when in attack state (LOD1 ships move but don't fire)
	if weapons_enabled:
		_pilot.fire_at_target(target, accuracy)


func _tick_evade(_delta: float) -> void:
	_evade_timer -= TICK_INTERVAL
	if _evade_timer <= 0.0:
		current_state = State.ATTACK if _is_target_valid() else State.PATROL
		return

	_pilot.evade_random(TICK_INTERVAL, evasion_amplitude, evasion_frequency)

	# Still try to face target while evading
	if _is_target_valid():
		_pilot.face_target(target.global_position)


func _tick_flee() -> void:
	if not _is_target_valid():
		current_state = State.PATROL
		target = null
		return

	# Fly directly away from target
	var away_dir: Vector3 = (_ship.global_position - target.global_position).normalized()
	var flee_pos: Vector3 = _ship.global_position + away_dir * 2000.0
	_pilot.fly_toward(flee_pos, 100.0)

	# If we get far enough and hull regenerates, re-engage
	var dist: float = _pilot.get_distance_to(target.global_position)
	if dist > DISENGAGE_RANGE:
		current_state = State.PATROL
		target = null


func _tick_formation() -> void:
	if formation_leader == null or not is_instance_valid(formation_leader):
		current_state = State.PATROL
		return

	# Calculate formation position in leader's local space
	var leader_basis: Basis = formation_leader.global_transform.basis
	var target_pos: Vector3 = formation_leader.global_position + leader_basis * formation_offset
	_pilot.fly_toward(target_pos, 20.0)

	# If leader is attacking, we attack too
	if formation_leader.has_node("AIBrain"):
		var leader_brain := formation_leader.get_node("AIBrain") as AIBrain
		if leader_brain and leader_brain.current_state == State.ATTACK and leader_brain.target:
			target = leader_brain.target
			current_state = State.ATTACK


func _detect_threats() -> void:
	if _ship == null:
		return

	# Use spatial grid via LOD manager if available (O(k) instead of O(n))
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr:
		var self_id := StringName(_ship.name)
		var results := lod_mgr.get_nearest_ships(_ship.global_position, DETECTION_RANGE, 5, self_id)
		var nearest_threat: Node3D = null
		var nearest_dist: float = DETECTION_RANGE
		for entry in results:
			var data := lod_mgr.get_ship_data(entry["id"])
			if data == null or data.is_dead:
				continue
			if data.faction == _ship.faction:
				continue
			# Only target ships with a scene node (can't fight LOD2)
			if data.node_ref == null or not is_instance_valid(data.node_ref):
				continue
			var dist_sq: float = entry["dist_sq"]
			if dist_sq < nearest_dist * nearest_dist:
				nearest_dist = sqrt(dist_sq)
				nearest_threat = data.node_ref
		if nearest_threat:
			target = nearest_threat
		return

	# Legacy fallback
	var all_ships := get_tree().get_nodes_in_group("ships")
	var fallback_threat: Node3D = null
	var fallback_dist: float = DETECTION_RANGE

	for node in all_ships:
		if node == _ship:
			continue
		if node is ShipController:
			var other := node as ShipController
			if other.faction == _ship.faction:
				continue
			var dist: float = _ship.global_position.distance_to(other.global_position)
			if dist < fallback_dist:
				var other_health := other.get_node_or_null("HealthSystem") as HealthSystem
				if other_health and other_health.is_dead():
					continue
				fallback_dist = dist
				fallback_threat = other

	if fallback_threat:
		target = fallback_threat


func _is_target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree():
		return false
	var health := target.get_node_or_null("HealthSystem") as HealthSystem
	if health and health.is_dead():
		return false
	return true


func _generate_patrol_waypoints() -> void:
	_waypoints.clear()
	for i in 4:
		var angle: float = (float(i) / 4.0) * TAU
		var wp := _patrol_center + Vector3(
			cos(angle) * _patrol_radius,
			randf_range(-50.0, 50.0),
			sin(angle) * _patrol_radius,
		)
		_waypoints.append(wp)


func set_patrol_area(center: Vector3, radius: float) -> void:
	_patrol_center = center
	_patrol_radius = radius
	_generate_patrol_waypoints()


func _on_damage_taken(attacker: Node3D) -> void:
	if current_state == State.DEAD:
		return
	# If idle or patrolling, immediately engage the attacker
	if current_state == State.IDLE or current_state == State.PATROL:
		if attacker and is_instance_valid(attacker) and attacker != _ship:
			target = attacker
			current_state = State.PURSUE
