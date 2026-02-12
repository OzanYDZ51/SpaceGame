class_name ObstacleSensor
extends Node

# =============================================================================
# ObstacleSensor — Three-layer obstacle avoidance for AI ships
# Layer 1: Omnidirectional proximity repulsion (intersect_shape sphere)
# Layer 2: Velocity-aligned raycast avoidance (9 rays along velocity vector)
# Layer 3: Ship avoidance via spatial grid (soft repulsion, skip same faction)
# Output: avoidance_vector (world-space) consumed by AIPilot
# =============================================================================

# --- Proximity repulsion ---
const PROXIMITY_RADIUS: float = 600.0
const REPULSION_INNER: float = 80.0
const REPULSION_OUTER: float = 500.0
const REPULSION_MAX_FORCE: float = 400.0

# --- Velocity avoidance ---
const VEL_MIN_LOOK: float = 200.0
const VEL_MAX_LOOK: float = 1200.0
const VEL_SPEED_SCALE: float = 2.5
const VEL_AVOID_WEIGHT: float = 300.0
const VEL_CONE_ANGLE: float = 0.3   # ~17° half-angle for cardinal probes
const VEL_DIAG_ANGLE: float = 0.55  # ~31° half-angle for diagonal probes

# --- Ship avoidance ---
const SHIP_AVOID_RADIUS: float = 400.0
const SHIP_AVOID_MAX: int = 6
const SHIP_AVOID_FORCE: float = 150.0
const SHIP_AVOID_INNER: float = 30.0   # Full force below this
const SHIP_AVOID_OUTER: float = 350.0  # Zero force above this

# --- Shared ---
const COLLISION_MASK: int = 6  # LAYER_STATIONS(2) | LAYER_ASTEROIDS(4)
const TICK_INTERVAL_MS: int = 100
const MAX_SPHERE_RESULTS: int = 8

# --- Public outputs ---
var avoidance_vector: Vector3 = Vector3.ZERO
var nearest_obstacle_dist: float = INF
var obstacle_density: float = 0.0
var is_emergency: bool = false

var _ship: ShipController = null
var _query_shape: SphereShape3D = null
var _last_tick: int = 0
var _cached_lod_mgr: ShipLODManager = null


func _ready() -> void:
	_ship = get_parent() as ShipController
	_query_shape = SphereShape3D.new()
	_query_shape.radius = PROXIMITY_RADIUS
	_cached_lod_mgr = GameManager.get_node_or_null("ShipLODManager") as ShipLODManager


func update() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick < TICK_INTERVAL_MS:
		return
	_last_tick = now

	if _ship == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		obstacle_density = 0.0
		is_emergency = false
		return

	var world := _ship.get_world_3d()
	if world == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		obstacle_density = 0.0
		is_emergency = false
		return
	var space := world.direct_space_state
	if space == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		obstacle_density = 0.0
		is_emergency = false
		return

	# Reset per-tick tracking
	nearest_obstacle_dist = INF

	var repulsion := _proximity_repulsion(space)
	var vel_avoid := _velocity_avoidance(space)
	var ship_avoid := _ship_avoidance()

	avoidance_vector = repulsion + vel_avoid + ship_avoid


func _proximity_repulsion(space: PhysicsDirectSpaceState3D) -> Vector3:
	var origin := _ship.global_position
	var ship_rid := _ship.get_rid()

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _query_shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = COLLISION_MASK
	params.collide_with_areas = false
	params.exclude = [ship_rid]

	var hits := space.intersect_shape(params, MAX_SPHERE_RESULTS)
	if hits.is_empty():
		return Vector3.ZERO

	# Track density via hit count (passed back via side-effect on obstacle_density)
	obstacle_density = clampf(float(hits.size()) / float(MAX_SPHERE_RESULTS), 0.0, 1.0)

	var total_force := Vector3.ZERO
	for hit in hits:
		var collider: Object = hit["collider"]
		if not is_instance_valid(collider) or not (collider is Node3D):
			continue

		var collider_pos: Vector3 = (collider as Node3D).global_position
		var to_obstacle := collider_pos - origin
		var dir := to_obstacle.normalized()
		if dir.length_squared() < 0.01:
			dir = Vector3.UP

		var dist := _ray_probe(space, origin, dir, PROXIMITY_RADIUS)

		# Track nearest obstacle
		if dist < nearest_obstacle_dist:
			nearest_obstacle_dist = dist

		if dist >= REPULSION_OUTER:
			continue
		var t := clampf((dist - REPULSION_INNER) / (REPULSION_OUTER - REPULSION_INNER), 0.0, 1.0)
		var force := (1.0 - t) * (1.0 - t) * REPULSION_MAX_FORCE
		total_force -= dir * force

	return total_force


func _velocity_avoidance(space: PhysicsDirectSpaceState3D) -> Vector3:
	var vel := _ship.linear_velocity
	var speed := vel.length()
	if speed < 5.0:
		is_emergency = false
		return Vector3.ZERO

	var origin := _ship.global_position
	var vel_dir := vel / speed
	var look := clampf(speed * VEL_SPEED_SCALE, VEL_MIN_LOOK, VEL_MAX_LOOK)

	# Central ray along velocity
	var center_dist := _ray_probe(space, origin, vel_dir, look)

	# Track nearest
	if center_dist < nearest_obstacle_dist:
		nearest_obstacle_dist = center_dist

	if center_dist >= look:
		is_emergency = false
		return Vector3.ZERO  # Path clear

	# Central blocked — probe 8 lateral directions (4 cardinal + 4 diagonal)
	var up := _ship.global_transform.basis.y
	var right := _ship.global_transform.basis.x
	var s := VEL_CONE_ANGLE
	var d := VEL_DIAG_ANGLE

	var probes: Array[Vector3] = [
		# Cardinal (17°)
		(vel_dir + right * s).normalized(),
		(vel_dir - right * s).normalized(),
		(vel_dir + up * s).normalized(),
		(vel_dir - up * s).normalized(),
		# Diagonal (31°)
		(vel_dir + (right + up).normalized() * d).normalized(),
		(vel_dir + (right - up).normalized() * d).normalized(),
		(vel_dir + (-right + up).normalized() * d).normalized(),
		(vel_dir + (-right - up).normalized() * d).normalized(),
	]

	var best_dir := Vector3.ZERO
	var best_dist: float = 0.0
	var blocked_count: int = 0
	for p in probes:
		var probe_dist := _ray_probe(space, origin, p, look)
		if probe_dist < look * 0.3:
			blocked_count += 1
		if probe_dist > best_dist:
			best_dist = probe_dist
			best_dir = p

	if best_dist < 10.0:
		# Boxed in — smart emergency: test 4 perpendicular directions, pick clearest
		is_emergency = true
		var escape_dirs: Array[Vector3] = [up, -up, right, -right]
		var best_escape := up
		var best_escape_dist: float = 0.0
		for esc in escape_dirs:
			var esc_dist := _ray_probe(space, origin, esc, PROXIMITY_RADIUS)
			if esc_dist > best_escape_dist:
				best_escape_dist = esc_dist
				best_escape = esc
		return best_escape * VEL_AVOID_WEIGHT
	else:
		# Emergency if 6+ of 8 probes are blocked
		is_emergency = blocked_count >= 6

	# Urgency: quadratic, closer = stronger
	var t := clampf(center_dist / look, 0.0, 1.0)
	var urgency := (1.0 - t) * (1.0 - t)

	# Lateral component only (perpendicular to velocity)
	var lateral := (best_dir - vel_dir * vel_dir.dot(best_dir)).normalized()
	return lateral * urgency * VEL_AVOID_WEIGHT


func _ship_avoidance() -> Vector3:
	if _cached_lod_mgr == null or _ship == null:
		return Vector3.ZERO

	var self_id := StringName(_ship.name)
	var results := _cached_lod_mgr.get_nearest_ships(
		_ship.global_position, SHIP_AVOID_RADIUS, SHIP_AVOID_MAX, self_id)

	if results.is_empty():
		return Vector3.ZERO

	var total_force := Vector3.ZERO
	var origin := _ship.global_position
	var my_faction: StringName = _ship.faction

	for entry in results:
		var data := _cached_lod_mgr.get_ship_data(entry["id"])
		if data == null:
			continue

		# Skip same faction (so formations work)
		if data.faction == my_faction:
			continue

		var other_pos: Vector3
		if data.node_ref and is_instance_valid(data.node_ref):
			other_pos = data.node_ref.global_position
		else:
			other_pos = _cached_lod_mgr.get_ship_position(entry["id"])

		var to_other := other_pos - origin
		var dist := to_other.length()
		if dist < 0.1:
			continue

		# Linear falloff from INNER to OUTER
		if dist >= SHIP_AVOID_OUTER:
			continue
		var t := clampf((dist - SHIP_AVOID_INNER) / (SHIP_AVOID_OUTER - SHIP_AVOID_INNER), 0.0, 1.0)
		var force := (1.0 - t) * SHIP_AVOID_FORCE

		# Repulse away
		total_force -= (to_other / dist) * force

	return total_force


func _ray_probe(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.exclude = [_ship.get_rid()]
	query.collision_mask = COLLISION_MASK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return max_dist
	return origin.distance_to(hit["position"])
