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
var route_priority: bool = false  # Convoy freighters: keep following route during combat

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
const MIN_SAFE_DIST: float = 50.0            # Emergency breakaway distance
const STATION_MODEL_RADIUS: float = 3000.0   # Station model ~2500m + margin
const OBSTACLE_CACHE_RANGE: float = 10000.0  # Cache obstacles within 10km (+ their own radius)
const ENV_UPDATE_INTERVAL: float = 2.0       # Refresh environment every 2s

var _in_asteroid_belt: bool = false
var _near_obstacle: bool = false
var _obstacle_zones: Array = []  # Array of { "pos": Vector3, "radius": float }
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
		var can_fire: bool = current_state in [State.ATTACK, State.PURSUE, State.EVADE] or (route_priority and current_state == State.PATROL)
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

	# Cache nearby obstacle zones from all large entities (stations, planets, stars)
	_obstacle_zones.clear()
	_near_obstacle = false
	var ship_pos: Vector3 = _ship.global_position

	# Stations (model ~2500m → exclusion radius 3000m)
	var stations = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for st in stations:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		var excl_r: float = STATION_MODEL_RADIUS
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			_obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Planets (physical radius from registry + margin)
	var planets = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET)
	for pl in planets:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([pl["pos_x"], pl["pos_y"], pl["pos_z"]])
		var planet_r: float = pl.get("radius", 5000.0)
		var excl_r: float = maxf(planet_r * 1.2 + 500.0, 5000.0)
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			_obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Stars (very large exclusion)
	var stars = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR)
	for star in stars:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([star["pos_x"], star["pos_y"], star["pos_z"]])
		var star_r: float = star.get("radius", 50000.0)
		var excl_r: float = maxf(star_r * 1.5, 50000.0)
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			_obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Check if inside any obstacle zone → regenerate patrol waypoints
	for zone in _obstacle_zones:
		var d: float = ship_pos.distance_to(zone["pos"])
		if d < zone["radius"]:
			_near_obstacle = true
			if current_state == State.PATROL:
				_generate_patrol_waypoints()
			break


func _push_away_from_obstacles(pos: Vector3) -> Vector3:
	## Pushes a waypoint outside all obstacle exclusion zones. Returns adjusted position.
	for zone in _obstacle_zones:
		var to_wp: Vector3 = pos - zone["pos"]
		var dist: float = to_wp.length()
		var excl_r: float = zone["radius"]
		if dist < excl_r:
			if dist < 1.0:
				to_wp = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_wp = to_wp.normalized()
			pos = zone["pos"] + to_wp * (excl_r + 50.0)
	return pos


func _deflect_from_obstacles(target_pos: Vector3) -> Vector3:
	## Real-time flight path deflection: if flying toward an obstacle, steer around it.
	## Runs every AI tick during patrol flight for active obstacle avoidance.
	if _ship == null or _obstacle_zones.is_empty():
		return target_pos
	var ship_pos: Vector3 = _ship.global_position
	var to_target: Vector3 = target_pos - ship_pos
	var flight_dist: float = to_target.length()
	if flight_dist < 1.0:
		return target_pos
	var flight_dir: Vector3 = to_target / flight_dist
	for zone in _obstacle_zones:
		var obs_pos: Vector3 = zone["pos"]
		var excl_r: float = zone["radius"]
		var to_obs: Vector3 = obs_pos - ship_pos
		# Only care about obstacles between us and the waypoint
		var proj: float = to_obs.dot(flight_dir)
		if proj < 0.0 or proj > flight_dist:
			continue
		# Perpendicular distance from flight line to obstacle center
		var closest_on_line: Vector3 = ship_pos + flight_dir * proj
		var perp_dist: float = (obs_pos - closest_on_line).length()
		if perp_dist < excl_r:
			# We'd fly through the obstacle — deflect perpendicular
			var deflect_dir: Vector3 = (closest_on_line - obs_pos).normalized()
			if deflect_dir.length_squared() < 0.01:
				deflect_dir = flight_dir.cross(Vector3.UP).normalized()
			var urgency: float = 1.0 - clampf(perp_dist / excl_r, 0.0, 1.0)
			var deflect_amount: float = (excl_r + 200.0) * urgency
			target_pos = target_pos + deflect_dir * deflect_amount
	return target_pos


func _check_obstacle_emergency() -> bool:
	## If the ship is inside any obstacle exclusion zone, steer away immediately.
	## Returns true if emergency steering was applied (caller should skip normal logic).
	if _ship == null or _obstacle_zones.is_empty():
		return false
	var ship_pos: Vector3 = _ship.global_position
	for zone in _obstacle_zones:
		var obs_pos: Vector3 = zone["pos"]
		var excl_r: float = zone["radius"]
		var to_ship: Vector3 = ship_pos - obs_pos
		var dist: float = to_ship.length()
		if dist < excl_r * 0.8:
			var escape_dir: Vector3 = to_ship.normalized() if dist > 1.0 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			var escape_pos: Vector3 = obs_pos + escape_dir * (excl_r + 500.0)
			_pilot.fly_toward(escape_pos, 50.0)
			return true
	return false


func _compute_safe_flee_direction(desired_dir: Vector3) -> Vector3:
	## Adjusts flee direction to avoid obstacles and incorporate sensor avoidance.
	var result: Vector3 = desired_dir

	for zone in _obstacle_zones:
		var to_obs: Vector3 = zone["pos"] - _ship.global_position
		var obs_dist: float = to_obs.length()
		var excl_r: float = zone["radius"]
		if obs_dist > excl_r * 2.0:
			continue
		var obs_dir: Vector3 = to_obs.normalized()
		var dot: float = desired_dir.dot(obs_dir)
		if dot > 0.5 and obs_dist < excl_r * 1.2:
			# Fleeing toward obstacle — deflect perpendicular
			var perp: Vector3 = desired_dir.cross(Vector3.UP).normalized()
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
		if route_priority:
			# Convoy leader: stay on route, slow down, fire while moving
			# Exit cruise so we fly at normal speed during combat
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if weapons_enabled:
				_pilot.fire_at_target(target, accuracy * 0.7)
		else:
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
			# Offset patrol center OUTSIDE station model, not at station origin
			var dir_from_station: Vector3 = (_ship.global_position - guard_station.global_position)
			if dir_from_station.length_squared() > 1.0:
				dir_from_station = dir_from_station.normalized()
			else:
				dir_from_station = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var offset_center: Vector3 = guard_station.global_position + dir_from_station * (STATION_MODEL_RADIUS + 500.0)
			set_patrol_area(offset_center, _patrol_radius)

	if _waypoints.is_empty():
		return

	# Wider arrival distance in asteroid belt to avoid getting stuck
	# Cap to patrol radius so waypoints don't overlap in small patrol areas
	var arrival =150.0 if _in_asteroid_belt else 80.0
	if _patrol_radius < arrival:
		arrival = maxf(_patrol_radius * 0.6, 15.0)

	var wp: Vector3 = _waypoints[_current_waypoint]

	# Real-time obstacle avoidance: if our flight path crosses an obstacle, deflect
	wp = _deflect_from_obstacles(wp)

	_pilot.fly_toward(wp, arrival)

	if _pilot.get_distance_to(_waypoints[_current_waypoint]) < arrival:
		_current_waypoint = (_current_waypoint + 1) % _waypoints.size()


func _tick_pursue() -> void:
	if not _is_target_valid():
		target = _get_highest_threat()
		if target == null:
			current_state = State.PATROL
		return

	# Obstacle avoidance: if inside an exclusion zone, break off and steer out
	if _check_obstacle_emergency():
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

	# Obstacle avoidance: if inside an exclusion zone, break off and steer out
	if _check_obstacle_emergency():
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

	# Obstacle avoidance: if inside an exclusion zone, break off and steer out
	if _check_obstacle_emergency():
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
			if _is_faction_allied(data.faction, entry["id"]):
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
			var other_faction: StringName = other.faction
			if _is_faction_allied(other_faction, StringName(other.name)):
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


## Check if a target faction is allied (should NOT be attacked).
## Uses FactionManager for real faction hostility when available.
func _is_faction_allied(target_faction: StringName, target_id: StringName = &"") -> bool:
	var my_fac: StringName = _ship.faction

	# Same faction = always allied
	if target_faction == my_fac:
		return true

	# Fleet <-> fleet and fleet <-> player are always allied
	if my_fac == &"player_fleet":
		return target_faction == &"player_fleet" or target_id == &"player_ship"
	if target_faction == &"player_fleet" or target_id == &"player_ship":
		# Check if we share the player's real faction
		var gi = GameManager.get_node_or_null("GameplayIntegrator")
		var fm = gi.get_node_or_null("FactionManager") if gi else null
		if fm:
			# Allied to player's fleet if our faction matches the player's
			return my_fac == fm.player_faction
		return false

	# Generic 'hostile' and 'lawless' factions are hostile to everyone
	if my_fac == &"hostile" or my_fac == &"lawless":
		return false
	if target_faction == &"hostile" or target_faction == &"lawless":
		return false

	# Use FactionManager: not enemies = allied (includes neutral)
	var gi2 = GameManager.get_node_or_null("GameplayIntegrator")
	var fm2 = gi2.get_node_or_null("FactionManager") if gi2 else null
	if fm2:
		return not fm2.are_enemies(my_fac, target_faction)

	# Fallback: different faction = hostile
	return false


func _generate_patrol_waypoints() -> void:
	_waypoints.clear()
	for i in 4:
		var angle: float = (float(i) / 4.0) * TAU
		var wp =_patrol_center + Vector3(
			cos(angle) * _patrol_radius,
			randf_range(-50.0, 50.0),
			sin(angle) * _patrol_radius,
		)
		# Push waypoint away from obstacles (stations, planets, stars)
		wp = _push_away_from_obstacles(wp)
		_waypoints.append(wp)


func set_patrol_area(center: Vector3, radius: float) -> void:
	_patrol_center = center
	_patrol_radius = radius
	_current_waypoint = 0
	_update_environment()
	_generate_patrol_waypoints()


## Set explicit linear route waypoints (convoy travel, no circular generation).
func set_route(waypoints: Array[Vector3]) -> void:
	_waypoints = waypoints
	_current_waypoint = 0
	if not waypoints.is_empty():
		_patrol_center = waypoints[0]
		# Large radius so guard-station recenter never triggers
		var max_dist: float = 0.0
		for wp in waypoints:
			max_dist = maxf(max_dist, _patrol_center.distance_to(wp))
		_patrol_radius = max_dist + 5000.0


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
