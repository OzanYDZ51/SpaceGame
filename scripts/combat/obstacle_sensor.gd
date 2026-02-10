class_name ObstacleSensor
extends Node

# =============================================================================
# ObstacleSensor — Two-layer obstacle avoidance for AI ships
# Layer 1: Omnidirectional proximity repulsion (intersect_shape sphere)
# Layer 2: Velocity-aligned raycast avoidance (5 rays along velocity vector)
# Output: avoidance_vector (world-space) consumed by AIPilot
# =============================================================================

# --- Proximity repulsion ---
const PROXIMITY_RADIUS: float = 600.0
const REPULSION_INNER: float = 80.0
const REPULSION_OUTER: float = 500.0
const REPULSION_MAX_FORCE: float = 400.0

# --- Velocity avoidance ---
const VEL_MIN_LOOK: float = 150.0
const VEL_MAX_LOOK: float = 800.0
const VEL_SPEED_SCALE: float = 2.0
const VEL_AVOID_WEIGHT: float = 300.0
const VEL_CONE_ANGLE: float = 0.3  # ~17° half-angle for lateral probes

# --- Shared ---
const COLLISION_MASK: int = 6  # LAYER_STATIONS(2) | LAYER_ASTEROIDS(4)
const TICK_INTERVAL_MS: int = 100
const MAX_SPHERE_RESULTS: int = 8

var avoidance_vector: Vector3 = Vector3.ZERO

var _ship: ShipController = null
var _query_shape: SphereShape3D = null
var _last_tick: int = 0


func _ready() -> void:
	_ship = get_parent() as ShipController
	_query_shape = SphereShape3D.new()
	_query_shape.radius = PROXIMITY_RADIUS


func update() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick < TICK_INTERVAL_MS:
		return
	_last_tick = now

	if _ship == null:
		avoidance_vector = Vector3.ZERO
		return

	var world := _ship.get_world_3d()
	if world == null:
		avoidance_vector = Vector3.ZERO
		return
	var space := world.direct_space_state
	if space == null:
		avoidance_vector = Vector3.ZERO
		return

	var repulsion := _proximity_repulsion(space)
	var vel_avoid := _velocity_avoidance(space)
	avoidance_vector = repulsion + vel_avoid


func _proximity_repulsion(space: PhysicsDirectSpaceState3D) -> Vector3:
	var origin := _ship.global_position
	var ship_rid := _ship.get_rid()

	# Sphere query for nearby obstacles
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _query_shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = COLLISION_MASK
	params.collide_with_areas = false
	params.exclude = [ship_rid]

	var hits := space.intersect_shape(params, MAX_SPHERE_RESULTS)
	if hits.is_empty():
		return Vector3.ZERO

	var total_force := Vector3.ZERO
	for hit in hits:
		var collider: Object = hit["collider"]
		if not is_instance_valid(collider) or not (collider is Node3D):
			continue

		# Raycast toward collider center to get surface distance
		var collider_pos: Vector3 = (collider as Node3D).global_position
		var to_obstacle := collider_pos - origin
		var dir := to_obstacle.normalized()
		if dir.length_squared() < 0.01:
			dir = Vector3.UP  # Fallback if exactly overlapping

		var dist := _ray_probe(space, origin, dir, PROXIMITY_RADIUS)

		# Quadratic falloff: full force at INNER, zero at OUTER
		if dist >= REPULSION_OUTER:
			continue
		var t := clampf((dist - REPULSION_INNER) / (REPULSION_OUTER - REPULSION_INNER), 0.0, 1.0)
		var force := (1.0 - t) * (1.0 - t) * REPULSION_MAX_FORCE

		# Repulse AWAY from obstacle
		total_force -= dir * force

	return total_force


func _velocity_avoidance(space: PhysicsDirectSpaceState3D) -> Vector3:
	var vel := _ship.linear_velocity
	var speed := vel.length()
	if speed < 5.0:
		return Vector3.ZERO

	var origin := _ship.global_position
	var vel_dir := vel / speed
	var look := clampf(speed * VEL_SPEED_SCALE, VEL_MIN_LOOK, VEL_MAX_LOOK)

	# Central ray along velocity
	var center_dist := _ray_probe(space, origin, vel_dir, look)
	if center_dist >= look:
		return Vector3.ZERO  # Path clear

	# Central blocked — probe 4 lateral directions
	var up := _ship.global_transform.basis.y
	var right := _ship.global_transform.basis.x
	var s := VEL_CONE_ANGLE

	var probes: Array[Vector3] = [
		(vel_dir + right * s).normalized(),
		(vel_dir - right * s).normalized(),
		(vel_dir + up * s).normalized(),
		(vel_dir - up * s).normalized(),
	]

	var best_dir := Vector3.ZERO
	var best_dist: float = 0.0
	for p in probes:
		var d := _ray_probe(space, origin, p, look)
		if d > best_dist:
			best_dist = d
			best_dir = p

	if best_dist < 10.0:
		# Boxed in — emergency perpendicular escape
		return up * VEL_AVOID_WEIGHT

	# Urgency: quadratic, closer = stronger
	var t := clampf(center_dist / look, 0.0, 1.0)
	var urgency := (1.0 - t) * (1.0 - t)

	# Lateral component only (perpendicular to velocity)
	var lateral := (best_dir - vel_dir * vel_dir.dot(best_dir)).normalized()
	return lateral * urgency * VEL_AVOID_WEIGHT


func _ray_probe(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.exclude = [_ship.get_rid()]
	query.collision_mask = COLLISION_MASK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return max_dist
	return origin.distance_to(hit["position"])
