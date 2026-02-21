class_name AIBrainEnvironment
extends RefCounted

# =============================================================================
# AI Brain Environment - Obstacle detection and avoidance for NPC AI.
# Extracted from AIBrain to keep the core state machine lean.
# Runs as a RefCounted sub-object owned by AIBrain.
# =============================================================================

const MIN_SAFE_DIST: float = 50.0
const STATION_MODEL_RADIUS: float = 2000.0
const OBSTACLE_CACHE_RANGE: float = 10000.0
const ENV_UPDATE_INTERVAL: float = 2.0

var in_asteroid_belt: bool = false
var near_obstacle: bool = false
var obstacle_zones: Array = []  # Array of { "pos": Vector3, "radius": float }

var _env_timer: float = 0.0
var _cached_asteroid_mgr = null
var _ship = null
var _pilot = null


func setup(ship: Node3D, pilot) -> void:
	_ship = ship
	_pilot = pilot
	_cached_asteroid_mgr = GameManager.get_node_or_null("AsteroidFieldManager")


func tick(dt: float) -> void:
	_env_timer -= dt
	if _env_timer <= 0.0:
		_env_timer = ENV_UPDATE_INTERVAL
		update_environment()


func update_environment() -> void:
	if _ship == null:
		return

	# Check if inside asteroid belt (uses universe coords)
	in_asteroid_belt = false
	if _cached_asteroid_mgr:
		var pos = _ship.global_position
		var ux: float = FloatingOrigin.origin_offset_x + float(pos.x)
		var uz: float = FloatingOrigin.origin_offset_z + float(pos.z)
		var belt_name = _cached_asteroid_mgr.get_belt_at_position(ux, uz)
		in_asteroid_belt = belt_name != ""

	# Cache nearby obstacle zones from all large entities (stations, planets, stars)
	obstacle_zones.clear()
	near_obstacle = false
	var ship_pos: Vector3 = _ship.global_position

	# Stations (model ~2500m → exclusion radius 3000m)
	var stations = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for st in stations:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		var excl_r: float = STATION_MODEL_RADIUS
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Planets (use render_radius which is the actual visual size in scene, NOT physical radius)
	var planets = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET)
	for pl in planets:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([pl["pos_x"], pl["pos_y"], pl["pos_z"]])
		var render_r: float = pl.get("extra", {}).get("render_radius", 100000.0)
		var excl_r: float = render_r + 2000.0
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Stars (use visual impostor size — star_radius is already in game meters ~300-700km)
	var stars = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR)
	for star in stars:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([star["pos_x"], star["pos_y"], star["pos_z"]])
		var star_r: float = star.get("radius", 696340.0)
		var excl_r: float = star_r * 1.5
		var dist: float = ship_pos.distance_to(scene_pos)
		if dist < excl_r + OBSTACLE_CACHE_RANGE:
			obstacle_zones.append({"pos": scene_pos, "radius": excl_r})

	# Check if inside any obstacle zone
	for zone in obstacle_zones:
		var d: float = ship_pos.distance_to(zone["pos"])
		if d < zone["radius"]:
			near_obstacle = true
			break


func push_away_from_obstacles(pos: Vector3) -> Vector3:
	for zone in obstacle_zones:
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


func deflect_from_obstacles(target_pos: Vector3) -> Vector3:
	if _ship == null or obstacle_zones.is_empty():
		return target_pos
	var ship_pos: Vector3 = _ship.global_position
	var to_target: Vector3 = target_pos - ship_pos
	var flight_dist: float = to_target.length()
	if flight_dist < 1.0:
		return target_pos
	var flight_dir: Vector3 = to_target / flight_dist
	for zone in obstacle_zones:
		var obs_pos: Vector3 = zone["pos"]
		var excl_r: float = zone["radius"]
		var to_obs: Vector3 = obs_pos - ship_pos
		var proj: float = to_obs.dot(flight_dir)
		if proj < 0.0 or proj > flight_dist:
			continue
		var closest_on_line: Vector3 = ship_pos + flight_dir * proj
		var perp_dist: float = (obs_pos - closest_on_line).length()
		if perp_dist < excl_r:
			var deflect_dir: Vector3 = (closest_on_line - obs_pos).normalized()
			if deflect_dir.length_squared() < 0.01:
				deflect_dir = flight_dir.cross(Vector3.UP).normalized()
			var urgency: float = 1.0 - clampf(perp_dist / excl_r, 0.0, 1.0)
			var deflect_amount: float = (excl_r + 200.0) * urgency
			target_pos = target_pos + deflect_dir * deflect_amount
	return target_pos


func check_obstacle_emergency() -> bool:
	if _ship == null or obstacle_zones.is_empty():
		return false
	var ship_pos: Vector3 = _ship.global_position
	for zone in obstacle_zones:
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
