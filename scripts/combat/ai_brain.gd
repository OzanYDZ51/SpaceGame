class_name AIBrain
extends Node

# =============================================================================
# AI Brain - High-level behavior state machine for NPC ships
# States: IDLE, PATROL, PURSUE, ATTACK, EVADE, FLEE, FORMATION, MINING, LOOT_PICKUP, DEAD
# Ticks at 10Hz for performance.
# Environment-aware: adapts to asteroid belts, stations, nearby obstacles.
# =============================================================================

enum State { IDLE, PATROL, PURSUE, ATTACK, EVADE, FLEE, FORMATION, MINING, LOOT_PICKUP, DEAD }

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
var ignore_threats: bool = false  # Fleet mission ships: don't react to enemies at all
var guard_station: Node3D = null  # Station this NPC is guarding (null = free roam)

# Detection — per-ship from ShipData, fallback to Constants
var detection_range: float = Constants.AI_DETECTION_RANGE
var engagement_range: float = Constants.AI_ENGAGEMENT_RANGE
var disengage_range: float = Constants.AI_DISENGAGE_RANGE

# Patrol
var _waypoints: Array[Vector3] = []
var _current_waypoint: int = 0
var _patrol_center: Vector3 = Vector3.ZERO
var _patrol_radius: float = 300.0

# Environment awareness
const MIN_SAFE_DIST: float = 50.0           # Emergency breakaway distance
const STATION_EXCLUSION_RADIUS: float = 400.0  # Waypoints must be outside this
const STATION_CACHE_RANGE: float = 2000.0   # Only cache stations within 2km
const ENV_UPDATE_INTERVAL: float = 2.0      # Refresh environment every 2s

var _in_asteroid_belt: bool = false
var _near_station: bool = false
var _station_scene_positions: Array[Vector3] = []
var _env_timer: float = 0.0
var _cached_asteroid_mgr = null

# AI tick
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL

var _ship = null
var _pilot = null
var _health = null
var _loot_pickup = null  # LootPickupSystem (same component as player)
var _evade_timer: float = 0.0
var _debug_timer: float = 0.0
var _cached_lod_mgr = null
var _cached_target_health = null
var _cached_target_ref: Node3D = null

# Threat table: tracks accumulated damage from each attacker
# Key = attacker instance_id, Value = { "node": Node3D, "threat": float, "last_hit": float }
var _threat_table: Dictionary = {}
const THREAT_DECAY_RATE: float = 5.0  # threat points lost per second
const THREAT_SWITCH_RATIO: float = 1.5  # new attacker must have 1.5x threat to force switch
const THREAT_CLEANUP_TIME: float = 10.0  # remove entries older than 10s


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
	_ship = get_parent()
	# Defer pilot/health lookup since they may not exist yet
	await get_tree().process_frame
	_pilot = _ship.get_node_or_null("AIPilot") if _ship else null
	_health = _ship.get_node_or_null("HealthSystem") if _ship else null
	_loot_pickup = _ship.get_node_or_null("LootPickupSystem") if _ship else null

	# Read per-ship AI ranges from ShipData (same data for player & NPC)
	if _ship and _ship.ship_data:
		detection_range = _ship.ship_data.sensor_range
		engagement_range = _ship.ship_data.engagement_range
		disengage_range = _ship.ship_data.disengage_range

	# React to damage: if patrolling/idle and get shot, immediately pursue the attacker
	if _health:
		_health.damage_taken.connect(_on_damage_taken)

	# Cache LOD manager (autoload child, never changes)
	_cached_lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	_cached_asteroid_mgr = GameManager.get_node_or_null("AsteroidFieldManager")

	# Generate initial patrol waypoints
	if _ship:
		_patrol_center = _ship.global_position
		_update_environment()
		_generate_patrol_waypoints()


func _process(delta: float) -> void:
	if _ship == null or _pilot == null:
		return
	if current_state == State.DEAD:
		return

	# Turrets track + auto-fire every frame, return to rest when no target
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm:
		if target and is_instance_valid(target) and weapons_enabled and current_state in [State.ATTACK, State.PURSUE, State.EVADE]:
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

	# Decay and cleanup threat table
	_update_threat_table(tick_rate)

	# Periodic environment scan (cheap: O(1) belt check + O(k) station filter)
	_env_timer -= tick_rate
	if _env_timer <= 0.0:
		_env_timer = ENV_UPDATE_INTERVAL
		_update_environment()

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
		State.MINING:
			_tick_mining()
		State.LOOT_PICKUP:
			_tick_loot_pickup()

	_debug_timer -= TICK_INTERVAL


# =============================================================================
# ENVIRONMENT AWARENESS
# =============================================================================
func _update_environment() -> void:
	if _ship == null:
		return

	# Check if inside asteroid belt (uses universe coords)
	_in_asteroid_belt = false
	if _cached_asteroid_mgr:
		var pos = _ship.global_position
		var ux: float = FloatingOrigin.origin_offset_x + float(pos.x)
		var uz: float = FloatingOrigin.origin_offset_z + float(pos.z)
		var belt_name = _cached_asteroid_mgr.get_belt_at_position(ux, uz)
		_in_asteroid_belt = belt_name != ""

	# Cache nearby station scene positions (universe → scene coords)
	_station_scene_positions.clear()
	_near_station = false
	var stations =EntityRegistry.get_by_type(EntityRegistry.EntityType.STATION)
	var ship_pos = _ship.global_position
	for st in stations:
		var scene_pos =FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		var dist = ship_pos.distance_to(scene_pos)
		if dist < STATION_CACHE_RANGE:
			_station_scene_positions.append(scene_pos)
			if dist < 800.0:
				_near_station = true


func _push_away_from_stations(pos: Vector3) -> Vector3:
	## Pushes a waypoint outside station exclusion zones. Returns adjusted position.
	for st_pos in _station_scene_positions:
		var to_wp =pos - st_pos
		var dist =to_wp.length()
		if dist < STATION_EXCLUSION_RADIUS:
			if dist < 1.0:
				# Overlapping — push in random horizontal direction
				to_wp = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_wp = to_wp.normalized()
			pos = st_pos + to_wp * (STATION_EXCLUSION_RADIUS + 50.0)
	return pos


func _compute_safe_flee_direction(desired_dir: Vector3) -> Vector3:
	## Adjusts flee direction to avoid stations and incorporate obstacle avoidance.
	var result =desired_dir

	# Deviate if fleeing toward a station
	for st_pos in _station_scene_positions:
		var to_station =st_pos - _ship.global_position
		var station_dist =to_station.length()
		if station_dist > STATION_CACHE_RANGE:
			continue
		var station_dir =to_station.normalized()
		var dot =desired_dir.dot(station_dir)
		if dot > 0.5 and station_dist < 1200.0:
			# Fleeing toward station — deflect perpendicular
			var perp =desired_dir.cross(Vector3.UP).normalized()
			if perp.length_squared() < 0.5:
				perp = desired_dir.cross(Vector3.RIGHT).normalized()
			result = (result + perp * 0.8).normalized()

	# Blend in obstacle sensor avoidance if available
	var sensor = _ship.get_node_or_null("ObstacleSensor")
	if sensor and sensor.avoidance_vector.length_squared() > 100.0:
		result = (result + sensor.avoidance_vector.normalized() * 0.5).normalized()

	return result


# =============================================================================
# STATE TICKS
# =============================================================================
func _tick_idle() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE


func _tick_patrol() -> void:
	_detect_threats()
	if target:
		current_state = State.PURSUE
		return

	# Loot pickup: if a crate is in range, go grab it (same system as player)
	if _loot_pickup and _loot_pickup.can_pickup and _loot_pickup.nearest_crate:
		current_state = State.LOOT_PICKUP
		return

	# Guard ships: recenter patrol if too far from station
	if guard_station and is_instance_valid(guard_station) and _ship:
		var dist_to_station: float = _ship.global_position.distance_to(guard_station.global_position)
		if dist_to_station > _patrol_radius * 2.0:
			set_patrol_area(guard_station.global_position, _patrol_radius)

	if _waypoints.is_empty():
		return

	# Wider arrival distance in asteroid belt to avoid getting stuck
	# Cap to patrol radius so waypoints don't overlap in small patrol areas
	var arrival =150.0 if _in_asteroid_belt else 80.0
	if _patrol_radius < arrival:
		arrival = maxf(_patrol_radius * 0.6, 15.0)

	var wp: Vector3 = _waypoints[_current_waypoint]
	_pilot.fly_toward(wp, arrival)

	if _pilot.get_distance_to(wp) < arrival:
		_current_waypoint = (_current_waypoint + 1) % _waypoints.size()


func _tick_pursue() -> void:
	if not _is_target_valid():
		target = _get_highest_threat()
		if target == null:
			current_state = State.PATROL
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	# Emergency breakaway if dangerously close
	if dist < MIN_SAFE_DIST:
		var away =(_ship.global_position - target.global_position).normalized()
		_pilot.fly_toward(_ship.global_position + away * 300.0, 10.0)
		return

	# Disengage if too far
	if dist > disengage_range:
		target = _get_highest_threat()
		if target == null:
			current_state = State.PATROL
		return

	# Engage when in range (wider threshold in belt)
	var engage_mult =2.0 if _in_asteroid_belt else 1.5
	if dist <= preferred_range * engage_mult:
		current_state = State.ATTACK
		return

	_pilot.fly_intercept(target, preferred_range)

	# Start shooting while pursuing if close enough
	if dist < engagement_range and weapons_enabled:
		_pilot.fire_at_target(target, accuracy * 0.6)


func _tick_attack(_delta: float) -> void:
	if not _is_target_valid():
		target = _get_highest_threat()
		if target == null:
			current_state = State.PATROL
		else:
			current_state = State.PURSUE
		return

	var dist: float = _pilot.get_distance_to(target.global_position)

	# Emergency breakaway if dangerously close
	if dist < MIN_SAFE_DIST:
		var away =(_ship.global_position - target.global_position).normalized()
		_pilot.fly_toward(_ship.global_position + away * 300.0, 10.0)
		return

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
	if dist > disengage_range:
		target = _get_highest_threat()
		if target == null:
			current_state = State.PATROL
		else:
			current_state = State.PURSUE
		return

	# Update persistent maneuver direction (changes every 1-2.5s, not every tick)
	_pilot.update_combat_maneuver(TICK_INTERVAL)

	# Navigate: maintain preferred range with smooth maneuvers
	if dist > preferred_range * 1.3:
		_pilot.fly_intercept(target, preferred_range)
	else:
		# Face lead position for aiming
		var lead_pos =target.global_position
		if target is RigidBody3D:
			var tvel: Vector3 = (target as RigidBody3D).linear_velocity
			var closing =maxf(-(_ship.linear_velocity - tvel).dot((target.global_position - _ship.global_position).normalized()), 10.0)
			var tti =clampf(dist / closing, 0.0, 3.0)
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

	# Compute safe flee direction (avoids stations)
	var away_dir: Vector3 = (_ship.global_position - target.global_position).normalized()
	away_dir = _compute_safe_flee_direction(away_dir)
	var flee_pos: Vector3 = _ship.global_position + away_dir * 2000.0
	_pilot.fly_toward(flee_pos, 100.0)

	# If we get far enough, re-engage or patrol
	var dist: float = _pilot.get_distance_to(target.global_position)
	if dist > disengage_range:
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

	# If leader is attacking, we attack too (only if we have weapons)
	if weapons_enabled and formation_leader.has_node("AIBrain"):
		var leader_brain = formation_leader.get_node("AIBrain")
		if leader_brain and leader_brain.current_state == State.ATTACK and leader_brain.target:
			target = leader_brain.target
			current_state = State.ATTACK


func _tick_mining() -> void:
	# Mining behavior is handled by AIMiningBehavior node (attached to fleet NPCs).
	# This state just keeps the ship idle — AIMiningBehavior drives AIPilot directly.
	pass


func _tick_loot_pickup() -> void:
	# Combat always takes priority over looting
	_detect_threats()
	if target:
		current_state = State.PURSUE
		return

	# Crate gone or out of range? Back to patrol
	if _loot_pickup == null or not _loot_pickup.can_pickup:
		current_state = State.PATROL
		return

	var crate: CargoCrate = _loot_pickup.nearest_crate
	if crate == null or not is_instance_valid(crate):
		current_state = State.PATROL
		return

	var crate_pos: Vector3 = crate.global_position
	_pilot.fly_toward(crate_pos, 30.0)

	# Collect when close — uses pickup_range fraction, no hardcoded distance
	if _pilot.get_distance_to(crate_pos) < _loot_pickup.pickup_range * 0.15:
		crate.collect()
		current_state = State.PATROL


# =============================================================================
# THREAT DETECTION
# =============================================================================
func _detect_threats() -> void:
	if _ship == null or ignore_threats or not weapons_enabled:
		return

	# Use spatial grid via LOD manager if available (O(k) instead of O(n))
	if _cached_lod_mgr:
		var self_id =StringName(_ship.name)
		var results = _cached_lod_mgr.get_nearest_ships(_ship.global_position, detection_range, 5, self_id)
		var nearest_threat: Node3D = null
		var nearest_dist: float = detection_range
		for entry in results:
			var data = _cached_lod_mgr.get_ship_data(entry["id"])
			if data == null or data.is_dead:
				continue
			if data.faction == _ship.faction:
				continue
			# Never target fleet ships or player if we ARE fleet
			if _ship.faction == &"player_fleet" and data.faction == &"player_fleet":
				continue
			if _ship.faction == &"player_fleet" and entry["id"] == &"player_ship":
				continue
			if data.faction == &"player_fleet" and _ship.faction != &"hostile":
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
	var all_ships =get_tree().get_nodes_in_group("ships")
	var fallback_threat: Node3D = null
	var fallback_dist: float = detection_range

	for node in all_ships:
		if node == _ship:
			continue
		if node.get("ship_data") != null:
			var other = node
			if other.faction == _ship.faction:
				continue
			# Fleet ships and player don't target each other
			if _ship.faction == &"player_fleet" and (other.faction == &"player_fleet" or other.faction == &"neutral"):
				continue
			if other.faction == &"player_fleet" and _ship.faction != &"hostile":
				continue
			var dist: float = _ship.global_position.distance_to(other.global_position)
			if dist < fallback_dist:
				var other_health = other.get_node_or_null("HealthSystem")
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
	# Cache target's HealthSystem (refresh when target changes)
	if _cached_target_ref != target:
		_cached_target_ref = target
		_cached_target_health = target.get_node_or_null("HealthSystem")
	if _cached_target_health and _cached_target_health.is_dead():
		return false
	return true


func _generate_patrol_waypoints() -> void:
	_waypoints.clear()
	for i in 4:
		var angle: float = (float(i) / 4.0) * TAU
		var wp =_patrol_center + Vector3(
			cos(angle) * _patrol_radius,
			randf_range(-50.0, 50.0),
			sin(angle) * _patrol_radius,
		)
		# Push waypoint away from stations
		wp = _push_away_from_stations(wp)
		_waypoints.append(wp)


func set_patrol_area(center: Vector3, radius: float) -> void:
	_patrol_center = center
	_patrol_radius = radius
	_current_waypoint = 0
	_update_environment()
	_generate_patrol_waypoints()


# =============================================================================
# THREAT TABLE
# =============================================================================
func _on_damage_taken(attacker: Node3D, amount: float = 0.0) -> void:
	if current_state == State.DEAD or ignore_threats or not weapons_enabled:
		return
	if attacker == null or not is_instance_valid(attacker) or attacker == _ship:
		return

	# Accumulate threat from this attacker
	var aid: int = attacker.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if _threat_table.has(aid):
		_threat_table[aid]["threat"] += amount
		_threat_table[aid]["last_hit"] = now
		_threat_table[aid]["node"] = attacker
	else:
		_threat_table[aid] = { "node": attacker, "threat": amount, "last_hit": now }

	# Propagate aggro to station and fellow guards
	if guard_station and is_instance_valid(guard_station):
		var defense_ai = guard_station.get_node_or_null("StationDefenseAI")
		if defense_ai:
			defense_ai.alert_guards(attacker)

	# If idle or patrolling, immediately engage
	if current_state == State.IDLE or current_state == State.PATROL:
		target = attacker
		current_state = State.PURSUE
		return

	# If already in combat, check if we should switch to a higher-threat attacker
	if current_state in [State.PURSUE, State.ATTACK, State.EVADE]:
		_maybe_switch_target()


func _update_threat_table(dt: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []
	for aid: int in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		# Decay threat over time
		entry["threat"] -= THREAT_DECAY_RATE * dt
		# Remove stale or dead entries
		var raw_node = entry["node"]
		if entry["threat"] <= 0.0 or (now - entry["last_hit"]) > THREAT_CLEANUP_TIME:
			to_remove.append(aid)
		elif raw_node == null or not is_instance_valid(raw_node) or not raw_node.is_inside_tree():
			to_remove.append(aid)
	for aid: int in to_remove:
		_threat_table.erase(aid)


func _maybe_switch_target() -> void:
	if target == null or not is_instance_valid(target):
		var best =_get_highest_threat()
		if best:
			target = best
		return

	var current_tid: int = target.get_instance_id()
	var current_threat: float = 0.0
	if _threat_table.has(current_tid):
		current_threat = _threat_table[current_tid]["threat"]

	var best_node: Node3D = null
	var best_threat: float = 0.0
	for aid: int in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		if entry["threat"] > best_threat:
			var node: Node3D = entry["node"] as Node3D
			if node and is_instance_valid(node) and node.is_inside_tree():
				best_threat = entry["threat"]
				best_node = node

	if best_node and best_node != target and best_threat > current_threat * THREAT_SWITCH_RATIO:
		target = best_node
		if current_state == State.EVADE:
			current_state = State.PURSUE


func _get_highest_threat() -> Node3D:
	var best_node: Node3D = null
	var best_threat: float = 0.0
	for aid: int in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		if entry["threat"] > best_threat:
			var node: Node3D = entry["node"] as Node3D
			if node and is_instance_valid(node) and node.is_inside_tree():
				best_threat = entry["threat"]
				best_node = node
	return best_node


func alert_to_threat(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker == _ship:
		return
	if current_state == State.DEAD or ignore_threats or not weapons_enabled:
		return
	# Add threat from station alert
	var aid: int = attacker.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if _threat_table.has(aid):
		_threat_table[aid]["threat"] += 50.0
		_threat_table[aid]["last_hit"] = now
		_threat_table[aid]["node"] = attacker
	else:
		_threat_table[aid] = { "node": attacker, "threat": 50.0, "last_hit": now }
	# Engage if idle/patrolling/formation
	if current_state in [State.IDLE, State.PATROL, State.FORMATION]:
		target = attacker
		current_state = State.PURSUE
