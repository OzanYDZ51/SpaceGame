class_name AINavigation
extends Node

# =============================================================================
# AI Navigation — Translates AI commands into ShipController inputs.
# Replaces AIPilot. Low-level flight control: fly toward, face, combat maneuvers.
# Obstacle avoidance via ObstacleSensor. Null-safe: no-op if no ship (stations).
# =============================================================================

# --- Navigation tuning ---
const DECEL_START_FACTOR: float = 3.0
const AVOIDANCE_BRAKE_THRESHOLD: float = 300.0
const APPROACH_OFFSET_AMOUNT: float = 150.0
const ORBIT_ANGULAR_SPEED: float = 0.8

# --- Cruise mode ---
var cruise_engage_dist: float = 5000.0
var cruise_disengage_dist: float = 5000.0
const CRUISE_ALIGN_THRESHOLD: float = 0.95

var _ship = null
var _obstacle_sensor = null

# Combat maneuver state
var _maneuver_dir: Vector3 = Vector3.ZERO
var _maneuver_timer: float = 0.0

# Intercept approach offset
var _approach_offset_dir: Vector3 = Vector3.ZERO
var _approach_offset_set: bool = false

# Orbit angle for combat circling
var _orbit_angle: float = 0.0

# PD controller derivative terms
var _prev_yaw_error: float = 0.0
var _prev_pitch_error: float = 0.0
var _last_face_time_ms: float = 0.0

# Obstacle sensor cache (avoid double update per frame)
var _obstacle_cache_frame: int = -1
var _cached_avoidance: Vector3 = Vector3.ZERO

# LOS check mask
const LOS_COLLISION_MASK: int = 7


func _ready() -> void:
	_ship = get_parent()
	if _ship:
		_cache_refs.call_deferred()
		if _ship.ship_data:
			cruise_engage_dist = _ship.ship_data.sensor_range * 1.5
			cruise_disengage_dist = clampf(_ship.ship_data.max_speed_cruise * 0.006, 5000.0, 15000.0)


func _cache_refs() -> void:
	_obstacle_sensor = _ship.get_node_or_null("ObstacleSensor")


func _get_avoidance() -> Vector3:
	var frame: int = Engine.get_process_frames()
	if frame != _obstacle_cache_frame:
		_obstacle_cache_frame = frame
		_obstacle_sensor.update()
		_cached_avoidance = _obstacle_sensor.avoidance_vector
	return _cached_avoidance


# =============================================================================
# NAVIGATION
# =============================================================================
func fly_intercept(target: Node3D, arrival_dist: float = 50.0) -> void:
	if _ship == null or target == null or not is_instance_valid(target):
		return

	var target_pos: Vector3 = target.global_position
	var target_vel: Vector3 = Vector3.ZERO
	if target is RigidBody3D:
		target_vel = (target as RigidBody3D).linear_velocity

	var to_target: Vector3 = target_pos - _ship.global_position
	var dist: float = to_target.length()

	var relative_vel: Vector3 = _ship.linear_velocity - target_vel
	var closing_speed: float = maxf(-relative_vel.dot(to_target.normalized()), 10.0)
	var time_to_intercept: float = clampf(dist / closing_speed, 0.0, 5.0)

	var intercept_pos: Vector3 = target_pos + target_vel * time_to_intercept

	if dist > 1200.0:
		if not _approach_offset_set:
			var fwd := to_target.normalized()
			var up := Vector3.UP
			var right := fwd.cross(up).normalized()
			if right.length_squared() < 0.5:
				right = fwd.cross(Vector3.RIGHT).normalized()
			_approach_offset_dir = (right * (1.0 if randf() > 0.5 else -1.0) + up * randf_range(-0.3, 0.3)).normalized()
			_approach_offset_set = true
		intercept_pos += _approach_offset_dir * APPROACH_OFFSET_AMOUNT
	elif dist < arrival_dist * DECEL_START_FACTOR:
		_approach_offset_set = false
	else:
		if _approach_offset_set:
			var fade := clampf((dist - arrival_dist * DECEL_START_FACTOR) / (1200.0 - arrival_dist * DECEL_START_FACTOR), 0.0, 1.0)
			intercept_pos += _approach_offset_dir * APPROACH_OFFSET_AMOUNT * fade

	fly_toward(intercept_pos, arrival_dist)


func fly_toward(target_pos: Vector3, arrival_dist: float = 50.0) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	var dist: float = to_target.length()

	if dist < arrival_dist:
		var closing: float = _ship.linear_velocity.dot(to_target.normalized()) if to_target.length_squared() > 0.1 else 0.0
		if closing > 10.0:
			var brake_z: float = clampf(closing / 50.0, 0.2, 1.0)
			_ship.set_throttle(Vector3(0, 0, brake_z))
		else:
			_ship.set_throttle(Vector3.ZERO)
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_ship._exit_cruise()
		return

	# Obstacle avoidance
	var avoid := Vector3.ZERO
	if _obstacle_sensor:
		avoid = _get_avoidance()

	var effective_target := target_pos
	if avoid.length_squared() > 1.0:
		var look_ahead: float = minf(dist, 500.0)
		effective_target = _ship.global_position + to_target.normalized() * look_ahead + avoid

	face_target(effective_target)

	var forward_dir: Vector3 = -_ship.global_transform.basis.z
	var aim_dir: Vector3 = (effective_target - _ship.global_position).normalized()
	var alignment: float = forward_dir.dot(aim_dir)

	var fwd_throttle: float
	if alignment > 0.85:
		fwd_throttle = -1.0
	elif alignment > 0.5:
		fwd_throttle = -lerpf(0.3, 1.0, (alignment - 0.5) / 0.35)
	elif alignment > 0.0:
		fwd_throttle = -0.15
	else:
		fwd_throttle = 0.0

	# Progressive deceleration
	var speed = _ship.linear_velocity.length()
	var decel_zone := maxf(arrival_dist * DECEL_START_FACTOR, speed * 1.5)
	if dist < decel_zone:
		var decel_t := clampf(dist / decel_zone, 0.0, 1.0)
		fwd_throttle *= decel_t

	# Obstacle braking
	if _obstacle_sensor:
		var obs_dist = _obstacle_sensor.nearest_obstacle_dist
		if obs_dist < AVOIDANCE_BRAKE_THRESHOLD:
			var brake_factor := clampf(obs_dist / AVOIDANCE_BRAKE_THRESHOLD, 0.1, 1.0)
			fwd_throttle *= brake_factor
		if _obstacle_sensor.is_emergency:
			fwd_throttle = 1.0

	# Lateral strafe for avoidance
	var strafe := Vector3.ZERO
	if avoid.length_squared() > 100.0:
		var local_avoid: Vector3 = _ship.global_transform.basis.inverse() * avoid.normalized()
		strafe.x = clampf(local_avoid.x * 0.6, -0.6, 0.6)
		strafe.y = clampf(local_avoid.y * 0.4, -0.4, 0.4)

	# Active braking
	if dist < decel_zone:
		var approach_vel: float = _ship.linear_velocity.dot(to_target.normalized())
		if approach_vel > 10.0:
			var coast_dist: float = approach_vel * 1.2
			if coast_dist > dist:
				var brake := clampf(1.0 - dist / coast_dist, 0.0, 0.8)
				fwd_throttle = maxf(fwd_throttle, brake)

	_ship.set_throttle(Vector3(strafe.x, strafe.y, fwd_throttle))
	_update_cruise(dist, alignment)


func face_target(target_pos: Vector3) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	if to_target.length_squared() < 1.0:
		return
	to_target = to_target.normalized()

	# Compute time delta for derivative normalization
	var now_ms: float = Time.get_ticks_msec()
	var dt: float = (now_ms - _last_face_time_ms) * 0.001 if _last_face_time_ms > 0.0 else 0.1
	_last_face_time_ms = now_ms
	dt = clampf(dt, 0.016, 2.0)

	var local_dir: Vector3 = _ship.global_transform.basis.inverse() * to_target
	var yaw_error: float = rad_to_deg(atan2(-local_dir.x, -local_dir.z))
	var xz_len: float = sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	var pitch_error: float = rad_to_deg(atan2(local_dir.y, xz_len))

	var pitch_speed = _ship.ship_data.rotation_pitch_speed if _ship.ship_data else 30.0
	var yaw_speed = _ship.ship_data.rotation_yaw_speed if _ship.ship_data else 25.0

	# Time-normalized derivatives (deg/sec) for consistent behavior across tick rates
	var yaw_deriv: float = (yaw_error - _prev_yaw_error) / dt
	var pitch_deriv: float = (pitch_error - _prev_pitch_error) / dt
	_prev_yaw_error = yaw_error
	_prev_pitch_error = pitch_error

	# Dead zone: well-aligned → stop rotating
	if absf(yaw_error) < 0.5 and absf(pitch_error) < 0.5:
		_ship.set_rotation_target(0.0, 0.0, 0.0)
		return

	# PD controller: P=2.0, D=0.5 (well-damped to prevent pitch/yaw oscillation)
	# Old: P=3.0, D=0.15 — ratio 20:1 caused continuous overshoot
	var pitch_rate: float = clampf(pitch_error * 2.0 - pitch_deriv * 0.5, -pitch_speed, pitch_speed)
	var yaw_rate: float = clampf(yaw_error * 2.0 - yaw_deriv * 0.5, -yaw_speed, yaw_speed)

	# Smooth ramp-down near alignment: avoids hard discontinuity at dead zone edge
	var max_error: float = maxf(absf(yaw_error), absf(pitch_error))
	if max_error < 5.0:
		var ramp: float = max_error / 5.0
		pitch_rate *= ramp
		yaw_rate *= ramp

	_ship.set_rotation_target(pitch_rate, yaw_rate, 0.0)


# =============================================================================
# CRUISE
# =============================================================================
func _update_cruise(dist: float, alignment: float) -> void:
	if _ship.cruise_disabled:
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_ship._exit_cruise()
		return
	if _ship.speed_mode == Constants.SpeedMode.CRUISE:
		if dist < cruise_disengage_dist or alignment < 0.5:
			_ship._exit_cruise()
	else:
		var in_combat: bool = (Time.get_ticks_msec() * 0.001 - _ship._last_combat_time) < ShipController.COMBAT_LOCK_DURATION
		if dist > cruise_engage_dist and alignment > CRUISE_ALIGN_THRESHOLD and not in_combat:
			_ship.speed_mode = Constants.SpeedMode.CRUISE
			_ship.cruise_time = 0.0
			_ship._cruise_punched = false


func disengage_cruise() -> void:
	if _ship and _ship.speed_mode == Constants.SpeedMode.CRUISE:
		_ship._exit_cruise()


# =============================================================================
# COMBAT MANEUVERS
# =============================================================================
func update_combat_maneuver(delta: float) -> void:
	_maneuver_timer -= delta
	if _maneuver_timer <= 0.0:
		_maneuver_timer = randf_range(1.0, 2.5)
		_maneuver_dir = Vector3(
			randf_range(-0.7, 0.7),
			randf_range(-0.5, 0.5),
			randf_range(-0.4, 0.1)
		)
	_orbit_angle = fmod(_orbit_angle + ORBIT_ANGULAR_SPEED * delta, TAU)


func apply_attack_throttle(dist_to_target: float, preferred_range: float) -> void:
	if _ship == null:
		return

	var avoid := Vector3.ZERO
	if _obstacle_sensor:
		avoid = _get_avoidance()

	var throttle: Vector3

	if dist_to_target > preferred_range * 1.3:
		return
	elif dist_to_target < preferred_range * 0.4:
		throttle = Vector3(_maneuver_dir.x, _maneuver_dir.y, 0.6)
	elif dist_to_target < preferred_range * 0.7:
		var orbit_x := cos(_orbit_angle) * 0.8
		var orbit_z := sin(_orbit_angle) * 0.3
		throttle = Vector3(orbit_x, _maneuver_dir.y * 0.3, orbit_z)
	else:
		var orbit_x := cos(_orbit_angle) * 0.5
		throttle = Vector3(orbit_x + _maneuver_dir.x * 0.3, _maneuver_dir.y * 0.2, -0.2)

	if _obstacle_sensor:
		var obs_dist = _obstacle_sensor.nearest_obstacle_dist
		if obs_dist < AVOIDANCE_BRAKE_THRESHOLD:
			var brake_factor := clampf(obs_dist / AVOIDANCE_BRAKE_THRESHOLD, 0.1, 1.0)
			throttle.z *= brake_factor
		if _obstacle_sensor.is_emergency:
			throttle.z = 0.6

	if avoid.length_squared() > 100.0:
		var local_avoid: Vector3 = _ship.global_transform.basis.inverse() * avoid.normalized()
		throttle.x = clampf(local_avoid.x, -1.0, 1.0)
		throttle.y = clampf(local_avoid.y, -0.6, 0.6)
		throttle.z = maxf(throttle.z, 0.3)

	_ship.set_throttle(throttle)


func apply_attack_run_throttle(dist_to_target: float, preferred_range: float, is_heavy: bool) -> void:
	if _ship == null:
		return

	var avoid := Vector3.ZERO
	if _obstacle_sensor:
		avoid = _get_avoidance()

	# Full forward with minimal jink — charging toward target
	var fwd_throttle: float
	var jink_amount: float = 0.1 if is_heavy else randf_range(0.15, 0.25)

	if dist_to_target > preferred_range * 0.8:
		# Closing: full speed
		fwd_throttle = -1.0 if not is_heavy else -0.7
	elif dist_to_target > preferred_range * 0.4:
		# Mid-range: sustained approach
		fwd_throttle = -0.8 if not is_heavy else -0.6
	else:
		# Close: maintain speed, commit to the pass
		fwd_throttle = -0.6 if not is_heavy else -0.5

	var throttle := Vector3(
		_maneuver_dir.x * jink_amount,
		_maneuver_dir.y * jink_amount * 0.5,
		fwd_throttle
	)

	# Obstacle handling
	if _obstacle_sensor:
		var obs_dist = _obstacle_sensor.nearest_obstacle_dist
		if obs_dist < AVOIDANCE_BRAKE_THRESHOLD:
			var brake_factor := clampf(obs_dist / AVOIDANCE_BRAKE_THRESHOLD, 0.1, 1.0)
			throttle.z *= brake_factor
		if _obstacle_sensor.is_emergency:
			throttle.z = 0.6

	if avoid.length_squared() > 100.0:
		var local_avoid: Vector3 = _ship.global_transform.basis.inverse() * avoid.normalized()
		throttle.x = clampf(local_avoid.x, -1.0, 1.0)
		throttle.y = clampf(local_avoid.y, -0.6, 0.6)
		throttle.z = maxf(throttle.z, 0.3)

	_ship.set_throttle(throttle)


func get_distance_to(pos: Vector3) -> float:
	if _ship == null:
		return INF
	return _ship.global_position.distance_to(pos)


# =============================================================================
# NAVIGATION BOOST (shared by FleetAICommand + AIMiningBehavior)
# =============================================================================
const NAV_BOOST_MIN_DIST: float = 500.0
const NAV_BOOST_RAMP_DIST: float = 5000.0
const NAV_BOOST_MIN_SPEED: float = 50.0


func update_nav_boost(target_pos: Vector3) -> void:
	if _ship == null:
		return
	var dist: float = _ship.global_position.distance_to(target_pos)
	_ship.ai_navigation_active = dist > NAV_BOOST_MIN_DIST
	if dist < NAV_BOOST_RAMP_DIST:
		var t: float = clampf(dist / NAV_BOOST_RAMP_DIST, 0.0, 1.0)
		_ship._gate_approach_speed_cap = lerpf(NAV_BOOST_MIN_SPEED, ShipController.AUTOPILOT_APPROACH_SPEED, t * t)
	else:
		_ship._gate_approach_speed_cap = 0.0


func clear_nav_boost() -> void:
	if _ship and is_instance_valid(_ship):
		_ship.ai_navigation_active = false
		_ship._gate_approach_speed_cap = 0.0
