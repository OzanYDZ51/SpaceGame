class_name AIPilot
extends Node

# =============================================================================
# AI Pilot - Translates AI commands into ShipController inputs
# Low-level flight control: fly toward, face target, combat maneuvers, fire
# Obstacle avoidance delegated to ObstacleSensor component
# =============================================================================

# --- Navigation tuning ---
const DECEL_START_FACTOR: float = 3.0          # Start braking at 3x arrival distance
const AVOIDANCE_BRAKE_THRESHOLD: float = 300.0 # Brake if obstacle closer than 300m
const APPROACH_OFFSET_AMOUNT: float = 150.0    # Lateral offset for intercept approach
const ORBIT_ANGULAR_SPEED: float = 0.8         # Orbit speed in combat (rad/s)

# --- Cruise mode for long-distance travel ---
var cruise_engage_dist: float = 5000.0          # Overridden per-ship in _ready()
var cruise_disengage_dist: float = 5000.0       # Fixed decel distance (like player autopilot)
const CRUISE_ALIGN_THRESHOLD: float = 0.95     # Dot product to engage cruise

var _ship = null
var _cached_wm = null
var _cached_targeting = null
var _obstacle_sensor = null

# Persistent combat maneuver (prevents jittery random-per-tick movement)
var _maneuver_dir: Vector3 = Vector3.ZERO
var _maneuver_timer: float = 0.0

# Intercept approach offset (persistent until close)
var _approach_offset_dir: Vector3 = Vector3.ZERO
var _approach_offset_set: bool = false

# Orbit angle for combat circling
var _orbit_angle: float = 0.0

# Previous yaw/pitch errors for derivative dampening (reduces steering oscillation)
var _prev_yaw_error: float = 0.0
var _prev_pitch_error: float = 0.0

# LOS check mask for fire_at_target (stations + asteroids + ships)
const LOS_COLLISION_MASK: int = 7  # LAYER_SHIPS(1) | LAYER_STATIONS(2) | LAYER_ASTEROIDS(4)


func _ready() -> void:
	_ship = get_parent()
	if _ship:
		_cache_refs.call_deferred()
		if _ship.ship_data:
			cruise_engage_dist = _ship.ship_data.sensor_range * 1.5
			# Fixed decel distance: proportional to max cruise speed but capped
			# Player autopilot uses 5km for gates — AI uses similar approach
			cruise_disengage_dist = clampf(_ship.ship_data.max_speed_cruise * 0.006, 5000.0, 15000.0)


func _cache_refs() -> void:
	_cached_wm = _ship.get_node_or_null("WeaponManager")
	_cached_targeting = _ship.get_node_or_null("TargetingSystem")
	_obstacle_sensor = _ship.get_node_or_null("ObstacleSensor")


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

	# Closing speed: how fast we approach
	var relative_vel: Vector3 = _ship.linear_velocity - target_vel
	var closing_speed: float = maxf(-relative_vel.dot(to_target.normalized()), 10.0)
	var time_to_intercept: float = clampf(dist / closing_speed, 0.0, 5.0)

	var intercept_pos: Vector3 = target_pos + target_vel * time_to_intercept

	# Lateral offset approach: at long range, don't fly straight at the target
	if dist > 1200.0:
		if not _approach_offset_set:
			# Generate a persistent lateral offset direction (perpendicular to approach)
			var fwd =to_target.normalized()
			var up =Vector3.UP
			var right =fwd.cross(up).normalized()
			if right.length_squared() < 0.5:
				right = fwd.cross(Vector3.RIGHT).normalized()
			# Random: left or right, slight vertical
			_approach_offset_dir = (right * (1.0 if randf() > 0.5 else -1.0) + up * randf_range(-0.3, 0.3)).normalized()
			_approach_offset_set = true
		intercept_pos += _approach_offset_dir * APPROACH_OFFSET_AMOUNT
	elif dist < arrival_dist * DECEL_START_FACTOR:
		# Close enough: clear offset for final convergence
		_approach_offset_set = false
	else:
		# Medium range: fade offset linearly
		if _approach_offset_set:
			var fade =clampf((dist - arrival_dist * DECEL_START_FACTOR) / (1200.0 - arrival_dist * DECEL_START_FACTOR), 0.0, 1.0)
			intercept_pos += _approach_offset_dir * APPROACH_OFFSET_AMOUNT * fade

	fly_toward(intercept_pos, arrival_dist)


func fly_toward(target_pos: Vector3, arrival_dist: float = 50.0) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	var dist: float = to_target.length()

	if dist < arrival_dist:
		# Apply reverse braking if still moving toward target (prevents coasting past)
		var closing: float = _ship.linear_velocity.dot(to_target.normalized()) if to_target.length_squared() > 0.1 else 0.0
		if closing > 10.0:
			var brake_z: float = clampf(closing / 50.0, 0.2, 1.0)
			_ship.set_throttle(Vector3(0, 0, brake_z))
		else:
			_ship.set_throttle(Vector3.ZERO)
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_ship._exit_cruise()
		return

	# --- Obstacle avoidance ---
	var avoid =Vector3.ZERO
	if _obstacle_sensor:
		_obstacle_sensor.update()
		avoid = _obstacle_sensor.avoidance_vector

	var effective_target =target_pos
	if avoid.length_squared() > 1.0:
		var look_ahead: float = minf(dist, 500.0)
		effective_target = _ship.global_position + to_target.normalized() * look_ahead + avoid

	face_target(effective_target)

	# Smooth throttle based on alignment with effective target
	var forward_dir: Vector3 = -_ship.global_transform.basis.z
	var aim_dir: Vector3 = (effective_target - _ship.global_position).normalized()
	var alignment: float = forward_dir.dot(aim_dir)

	var fwd_throttle: float
	if alignment > 0.85:
		fwd_throttle = -1.0  # Well aligned: full burn
	elif alignment > 0.5:
		fwd_throttle = -lerpf(0.3, 1.0, (alignment - 0.5) / 0.35)
	elif alignment > 0.0:
		fwd_throttle = -0.15  # Barely aligned: creep while turning
	else:
		fwd_throttle = 0.0  # Facing away: just turn

	# --- Progressive deceleration near target ---
	# Scale decel zone with speed: at high post-cruise speeds, need more room to brake
	var speed = _ship.linear_velocity.length()
	var decel_zone =maxf(arrival_dist * DECEL_START_FACTOR, speed * 1.5)
	if dist < decel_zone:
		var decel_t =clampf(dist / decel_zone, 0.0, 1.0)
		fwd_throttle *= decel_t  # Linear ramp-down to zero at arrival

	# --- Obstacle braking ---
	if _obstacle_sensor:
		var obs_dist = _obstacle_sensor.nearest_obstacle_dist
		if obs_dist < AVOIDANCE_BRAKE_THRESHOLD:
			var brake_factor =clampf(obs_dist / AVOIDANCE_BRAKE_THRESHOLD, 0.1, 1.0)
			fwd_throttle *= brake_factor

		# Emergency: full reverse
		if _obstacle_sensor.is_emergency:
			fwd_throttle = 1.0  # Positive Z = reverse thrust

	# If actively avoiding, add lateral strafe thrust for faster clearance
	var strafe =Vector3.ZERO
	if avoid.length_squared() > 100.0:
		var local_avoid: Vector3 = _ship.global_transform.basis.inverse() * avoid.normalized()
		strafe.x = clampf(local_avoid.x * 0.6, -0.6, 0.6)
		strafe.y = clampf(local_avoid.y * 0.4, -0.4, 0.4)

	# --- Active braking: apply reverse thrust when coasting would overshoot ---
	# FA_LINEAR_BRAKE ≈ 1.0 → coast distance ≈ speed meters.
	# If that exceeds remaining distance, reverse thrust triggers FA_COUNTER_BRAKE (2.5x).
	if dist < decel_zone:
		var approach_vel: float = _ship.linear_velocity.dot(to_target.normalized())
		if approach_vel > 10.0:
			var coast_dist: float = approach_vel * 1.2  # Pessimistic FA coast estimate
			if coast_dist > dist:
				var brake =clampf(1.0 - dist / coast_dist, 0.0, 0.8)
				fwd_throttle = maxf(fwd_throttle, brake)

	_ship.set_throttle(Vector3(strafe.x, strafe.y, fwd_throttle))

	# --- Cruise mode for long-distance travel ---
	_update_cruise(dist, alignment)


func face_target(target_pos: Vector3) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	if to_target.length_squared() < 1.0:
		return
	to_target = to_target.normalized()

	var local_dir: Vector3 = _ship.global_transform.basis.inverse() * to_target

	var yaw_error: float = rad_to_deg(atan2(-local_dir.x, -local_dir.z))
	var xz_len: float = sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	var pitch_error: float = rad_to_deg(atan2(local_dir.y, xz_len))

	var pitch_speed = _ship.ship_data.rotation_pitch_speed if _ship.ship_data else 30.0
	var yaw_speed = _ship.ship_data.rotation_yaw_speed if _ship.ship_data else 25.0

	# PD controller: proportional + derivative dampening to prevent oscillation.
	# The derivative term resists rapid error changes, smoothing out steering.
	var yaw_deriv: float = yaw_error - _prev_yaw_error
	var pitch_deriv: float = pitch_error - _prev_pitch_error
	_prev_yaw_error = yaw_error
	_prev_pitch_error = pitch_error

	var pitch_rate: float = clampf(pitch_error * 3.0 - pitch_deriv * 1.5, -pitch_speed, pitch_speed)
	var yaw_rate: float = clampf(yaw_error * 3.0 - yaw_deriv * 1.5, -yaw_speed, yaw_speed)

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
		# Exit cruise at fixed distance (like player autopilot, NOT speed-dependent)
		# Old formula "speed * 3.0" caused premature exit at cruise phase 2 speeds
		# (e.g. 50km/s → disengage at 150km, ship crawls for minutes)
		if dist < cruise_disengage_dist or alignment < 0.5:
			_ship._exit_cruise()
	else:
		# Engage cruise: far away, well aligned, not in combat
		# Check _last_combat_time directly (combat_locked is only updated for player ships)
		var in_combat =(Time.get_ticks_msec() * 0.001 - _ship._last_combat_time) < ShipController.COMBAT_LOCK_DURATION
		if dist > cruise_engage_dist and alignment > CRUISE_ALIGN_THRESHOLD and not in_combat:
			_ship.speed_mode = Constants.SpeedMode.CRUISE
			_ship.cruise_time = 0.0
			_ship._cruise_punched = false


func disengage_cruise() -> void:
	if _ship and _ship.speed_mode == Constants.SpeedMode.CRUISE:
		_ship._exit_cruise()


# =============================================================================
# COMBAT
# =============================================================================
func update_combat_maneuver(delta: float) -> void:
	_maneuver_timer -= delta
	if _maneuver_timer <= 0.0:
		_maneuver_timer = randf_range(1.0, 2.5)
		_maneuver_dir = Vector3(
			randf_range(-0.7, 0.7),
			randf_range(-0.3, 0.3),
			randf_range(-0.4, 0.1)
		)
	# Advance orbit angle (wrap to prevent unbounded growth)
	_orbit_angle = fmod(_orbit_angle + ORBIT_ANGULAR_SPEED * delta, TAU)


func apply_attack_throttle(dist_to_target: float, preferred_range: float) -> void:
	if _ship == null:
		return

	var avoid =Vector3.ZERO
	if _obstacle_sensor:
		_obstacle_sensor.update()
		avoid = _obstacle_sensor.avoidance_vector

	var throttle: Vector3

	if dist_to_target > preferred_range * 1.3:
		# Too far: close in (fly_toward handles this case via AIBrain)
		return
	elif dist_to_target < preferred_range * 0.4:
		# Too close: back away while strafing
		throttle = Vector3(_maneuver_dir.x, _maneuver_dir.y, 0.6)
	elif dist_to_target < preferred_range * 0.7:
		# Orbit zone: circular strafing around target
		var orbit_x =cos(_orbit_angle) * 0.8
		var orbit_z =sin(_orbit_angle) * 0.3  # Slight in-out oscillation
		throttle = Vector3(orbit_x, _maneuver_dir.y * 0.3, orbit_z)
	else:
		# Sweet spot: orbit + gentle approach
		var orbit_x =cos(_orbit_angle) * 0.5
		throttle = Vector3(orbit_x + _maneuver_dir.x * 0.3, _maneuver_dir.y * 0.2, -0.2)

	# --- Obstacle braking during combat ---
	if _obstacle_sensor:
		var obs_dist = _obstacle_sensor.nearest_obstacle_dist
		if obs_dist < AVOIDANCE_BRAKE_THRESHOLD:
			var brake_factor =clampf(obs_dist / AVOIDANCE_BRAKE_THRESHOLD, 0.1, 1.0)
			throttle.z *= brake_factor

		if _obstacle_sensor.is_emergency:
			throttle.z = 0.6  # Back away

	# Override strafe with avoidance if an obstacle is nearby
	if avoid.length_squared() > 100.0:
		var local_avoid: Vector3 = _ship.global_transform.basis.inverse() * avoid.normalized()
		throttle.x = clampf(local_avoid.x, -1.0, 1.0)
		throttle.y = clampf(local_avoid.y, -0.6, 0.6)
		throttle.z = maxf(throttle.z, 0.3)

	_ship.set_throttle(throttle)


func fire_at_target(target: Node3D, accuracy_mod: float = 1.0) -> void:
	if _ship == null or target == null or not is_instance_valid(target):
		return

	if _cached_wm == null:
		return

	var target_pos: Vector3
	if _cached_targeting:
		_cached_targeting.current_target = target
		target_pos = _cached_targeting.get_lead_indicator_position()
	else:
		target_pos = target.global_position

	var inaccuracy =(1.0 - accuracy_mod) * 12.0
	target_pos += Vector3(
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy)
	)

	var to_target: Vector3 = (target_pos - _ship.global_position).normalized()
	var forward: Vector3 = -_ship.global_transform.basis.z
	var dot: float = forward.dot(to_target)
	if dot > 0.6:
		var space = _ship.get_world_3d().direct_space_state
		if space:
			var los_query =PhysicsRayQueryParameters3D.create(
				_ship.global_position, target.global_position)
			los_query.collision_mask = LOS_COLLISION_MASK
			los_query.collide_with_areas = false
			var exclude_rids: Array[RID] = [_ship.get_rid()]
			if target is CollisionObject3D:
				exclude_rids.append(target.get_rid())
			# Exclude guard station to prevent station blocking guard's own shots
			var brain = _ship.get_node_or_null("AIBrain")
			if brain and brain.guard_station and is_instance_valid(brain.guard_station):
				if brain.guard_station is CollisionObject3D:
					exclude_rids.append(brain.guard_station.get_rid())
			los_query.exclude = exclude_rids
			var los_hit =space.intersect_ray(los_query)
			if not los_hit.is_empty():
				return
		_cached_wm.fire_group(0, true, target_pos)


func get_distance_to(pos: Vector3) -> float:
	if _ship == null:
		return INF
	return _ship.global_position.distance_to(pos)
