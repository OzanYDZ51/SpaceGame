class_name ObstacleSensor
extends Node

# =============================================================================
# ObstacleSensor — Velocity-aligned raycast avoidance for AI ships
# Only avoids static obstacles (stations) when flying fast toward them.
# Proximity repulsion and ship-to-ship repulsion removed: they caused mining
# ships to flee asteroids and players to repel each other.
# =============================================================================

# --- Velocity avoidance ---
const VEL_MIN_LOOK: float = 200.0
const VEL_MAX_LOOK: float = 1200.0
const VEL_SPEED_SCALE: float = 2.5
const VEL_AVOID_WEIGHT: float = 300.0
const VEL_CONE_ANGLE: float = 0.3   # ~17° half-angle for cardinal probes
const VEL_DIAG_ANGLE: float = 0.55  # ~31° half-angle for diagonal probes

# --- Forward-facing detection (works even at low speed / when stuck) ---
const FWD_LOOK_DIST: float = 300.0

# --- Shared ---
const COLLISION_MASK: int = 2  # LAYER_STATIONS(2) only — not asteroids
const TICK_INTERVAL_MS: int = 100

# --- Public outputs ---
var avoidance_vector: Vector3 = Vector3.ZERO
var nearest_obstacle_dist: float = INF
var obstacle_density: float = 0.0
var is_emergency: bool = false

var _ship = null
var _last_tick: int = 0


func _ready() -> void:
	_ship = get_parent()


func update() -> void:
	var now = Time.get_ticks_msec()
	if now - _last_tick < TICK_INTERVAL_MS:
		return
	_last_tick = now

	if _ship == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		is_emergency = false
		return

	var world = _ship.get_world_3d()
	if world == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		is_emergency = false
		return
	var space = world.direct_space_state
	if space == null:
		avoidance_vector = Vector3.ZERO
		nearest_obstacle_dist = INF
		is_emergency = false
		return

	nearest_obstacle_dist = INF
	avoidance_vector = _velocity_avoidance(space)


func _velocity_avoidance(space: PhysicsDirectSpaceState3D) -> Vector3:
	var vel: Vector3 = _ship.linear_velocity
	var speed: float = vel.length()
	var origin: Vector3 = _ship.global_position
	var ship_fwd: Vector3 = -_ship.global_transform.basis.z

	# Primary probe: velocity-aligned if moving, else ship forward
	var probe_dir: Vector3
	var look: float
	if speed >= 5.0:
		probe_dir = vel / speed
		look = clampf(speed * VEL_SPEED_SCALE, VEL_MIN_LOOK, VEL_MAX_LOOK)
	else:
		# Low speed / stuck: use ship facing direction
		probe_dir = ship_fwd
		look = FWD_LOOK_DIST

	# Always check ship forward direction (catches obstacles ship is turning toward)
	var fwd_look: float = maxf(look, FWD_LOOK_DIST)
	var fwd_dist: float = _ray_probe(space, origin, ship_fwd, fwd_look)
	if fwd_dist < nearest_obstacle_dist:
		nearest_obstacle_dist = fwd_dist

	# Central ray along primary direction
	var center_dist: float = _ray_probe(space, origin, probe_dir, look)
	if center_dist < nearest_obstacle_dist:
		nearest_obstacle_dist = center_dist

	# If both directions clear, no avoidance
	if center_dist >= look and fwd_dist >= fwd_look:
		is_emergency = false
		return Vector3.ZERO

	# Use whichever has the closer obstacle for avoidance computation
	var avoid_dir: Vector3 = probe_dir
	var avoid_dist: float = center_dist
	var avoid_look: float = look
	if fwd_dist < center_dist:
		avoid_dir = ship_fwd
		avoid_dist = fwd_dist
		avoid_look = fwd_look

	# Probe 8 lateral directions around the obstacle direction
	var up: Vector3 = _ship.global_transform.basis.y
	var right: Vector3 = _ship.global_transform.basis.x
	var s: float = VEL_CONE_ANGLE
	var d: float = VEL_DIAG_ANGLE

	var probes: Array[Vector3] = [
		# Cardinal (17°)
		(avoid_dir + right * s).normalized(),
		(avoid_dir - right * s).normalized(),
		(avoid_dir + up * s).normalized(),
		(avoid_dir - up * s).normalized(),
		# Diagonal (31°)
		(avoid_dir + (right + up).normalized() * d).normalized(),
		(avoid_dir + (right - up).normalized() * d).normalized(),
		(avoid_dir + (-right + up).normalized() * d).normalized(),
		(avoid_dir + (-right - up).normalized() * d).normalized(),
	]

	var best_dir: Vector3 = Vector3.ZERO
	var best_dist: float = 0.0
	var blocked_count: int = 0
	for p in probes:
		var p_dist: float = _ray_probe(space, origin, p, avoid_look)
		if p_dist < avoid_look * 0.3:
			blocked_count += 1
		if p_dist > best_dist:
			best_dist = p_dist
			best_dir = p

	if best_dist < 10.0:
		# Boxed in — pick clearest perpendicular direction
		is_emergency = true
		var escape_dirs: Array[Vector3] = [up, -up, right, -right]
		var best_escape: Vector3 = up
		var best_escape_dist: float = 0.0
		for esc in escape_dirs:
			var esc_dist: float = _ray_probe(space, origin, esc, VEL_MIN_LOOK)
			if esc_dist > best_escape_dist:
				best_escape_dist = esc_dist
				best_escape = esc
		return best_escape * VEL_AVOID_WEIGHT
	else:
		is_emergency = blocked_count >= 6

	var t: float = clampf(avoid_dist / avoid_look, 0.0, 1.0)
	var urgency: float = (1.0 - t) * (1.0 - t)
	var lateral: Vector3 = (best_dir - avoid_dir * avoid_dir.dot(best_dir)).normalized()
	return lateral * urgency * VEL_AVOID_WEIGHT


func _ray_probe(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	query.exclude = [_ship.get_rid()]
	query.collision_mask = COLLISION_MASK
	var hit = space.intersect_ray(query)
	if hit.is_empty():
		return max_dist
	return origin.distance_to(hit["position"])
