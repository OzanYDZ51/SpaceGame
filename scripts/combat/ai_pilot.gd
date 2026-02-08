class_name AIPilot
extends Node

# =============================================================================
# AI Pilot - Translates AI commands into ShipController inputs
# Low-level flight control: fly toward, face target, combat maneuvers, fire
# =============================================================================

var _ship: ShipController = null
var _cached_wm: WeaponManager = null
var _cached_targeting: TargetingSystem = null

# Persistent combat maneuver (prevents jittery random-per-tick movement)
var _maneuver_dir: Vector3 = Vector3.ZERO
var _maneuver_timer: float = 0.0

# Evasion jink
var _jink_offset: Vector3 = Vector3.ZERO
var _jink_timer: float = 0.0


func _ready() -> void:
	_ship = get_parent() as ShipController
	if _ship:
		_cache_refs.call_deferred()


func _cache_refs() -> void:
	_cached_wm = _ship.get_node_or_null("WeaponManager") as WeaponManager
	_cached_targeting = _ship.get_node_or_null("TargetingSystem") as TargetingSystem


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
	fly_toward(intercept_pos, arrival_dist)


func fly_toward(target_pos: Vector3, arrival_dist: float = 50.0) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	var dist: float = to_target.length()

	if dist < arrival_dist:
		_ship.set_throttle(Vector3.ZERO)
		return

	face_target(target_pos)

	# Smooth throttle based on alignment with target
	var forward_dir: Vector3 = -_ship.global_transform.basis.z
	var alignment: float = forward_dir.dot(to_target.normalized())

	var fwd_throttle: float
	if alignment > 0.85:
		fwd_throttle = -1.0  # Well aligned: full burn
	elif alignment > 0.5:
		fwd_throttle = -lerpf(0.3, 1.0, (alignment - 0.5) / 0.35)
	elif alignment > 0.0:
		fwd_throttle = -0.15  # Barely aligned: creep while turning
	else:
		fwd_throttle = 0.0  # Facing away: just turn

	_ship.set_throttle(Vector3(0.0, 0.0, fwd_throttle))


func face_target(target_pos: Vector3) -> void:
	if _ship == null:
		return

	var to_target: Vector3 = target_pos - _ship.global_position
	if to_target.length_squared() < 1.0:
		return
	to_target = to_target.normalized()

	# Transform target direction into ship's LOCAL space
	# In local space: +X = right, +Y = up, -Z = forward
	var local_dir: Vector3 = _ship.global_transform.basis.inverse() * to_target

	# atan2 gives correct angles for ALL directions (including behind the ship)
	# Yaw: angle from forward (-Z) projected onto XZ plane
	# Negate local_dir.x because positive yaw_rate = turn LEFT (CCW from above)
	# and positive local_dir.x = target is to the RIGHT (need negative rate)
	var yaw_error: float = rad_to_deg(atan2(-local_dir.x, -local_dir.z))
	# Pitch: elevation angle — positive = target above = pitch UP
	var xz_len: float = sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	var pitch_error: float = rad_to_deg(atan2(local_dir.y, xz_len))

	var pitch_speed := _ship.ship_data.rotation_pitch_speed if _ship.ship_data else 30.0
	var yaw_speed := _ship.ship_data.rotation_yaw_speed if _ship.ship_data else 25.0

	# Proportional gain (4x) — combined with rotation_responsiveness=3.0 on the
	# ShipController, this gives the AI fast, smooth tracking.
	var pitch_rate: float = clampf(pitch_error * 4.0, -pitch_speed, pitch_speed)
	var yaw_rate: float = clampf(yaw_error * 4.0, -yaw_speed, yaw_speed)

	_ship.set_rotation_target(pitch_rate, yaw_rate, 0.0)


func update_combat_maneuver(delta: float) -> void:
	# Maintain a consistent strafe direction for 1-2.5 seconds before changing.
	# This prevents the jittery random-per-tick movement.
	_maneuver_timer -= delta
	if _maneuver_timer <= 0.0:
		_maneuver_timer = randf_range(1.0, 2.5)
		_maneuver_dir = Vector3(
			randf_range(-0.7, 0.7),
			randf_range(-0.3, 0.3),
			randf_range(-0.4, 0.1)  # Mostly forward-neutral
		)


func apply_attack_throttle(dist_to_target: float, preferred_range: float) -> void:
	if _ship == null:
		return

	var throttle: Vector3

	if dist_to_target > preferred_range * 1.3:
		# Too far: close in (fly_toward handles this case via AIBrain)
		return
	elif dist_to_target < preferred_range * 0.4:
		# Too close: back away while strafing
		throttle = Vector3(_maneuver_dir.x, _maneuver_dir.y, 0.6)
	elif dist_to_target < preferred_range * 0.7:
		# Slightly close: orbit/strafe
		throttle = Vector3(_maneuver_dir.x * 0.8, _maneuver_dir.y * 0.5, 0.0)
	else:
		# Sweet spot: slow approach with strafing
		throttle = Vector3(_maneuver_dir.x * 0.5, _maneuver_dir.y * 0.3, -0.25)

	_ship.set_throttle(throttle)


func fire_at_target(target: Node3D, accuracy_mod: float = 1.0) -> void:
	if _ship == null or target == null or not is_instance_valid(target):
		return

	if _cached_wm == null:
		return

	# Calculate lead position
	var target_pos: Vector3
	if _cached_targeting:
		_cached_targeting.current_target = target
		target_pos = _cached_targeting.get_lead_indicator_position()
	else:
		target_pos = target.global_position

	# Add inaccuracy based on accuracy_mod
	var inaccuracy := (1.0 - accuracy_mod) * 12.0
	target_pos += Vector3(
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy)
	)

	# Relaxed firing cone: ~41 degrees (was 25). AI can shoot while maneuvering.
	var to_target: Vector3 = (target_pos - _ship.global_position).normalized()
	var forward: Vector3 = -_ship.global_transform.basis.z
	var dot: float = forward.dot(to_target)
	if dot > 0.75:
		_cached_wm.fire_group(0, true, target_pos)


func evade_random(delta: float, amplitude: float = 30.0, frequency: float = 2.0) -> void:
	if _ship == null:
		return

	_jink_timer -= delta
	if _jink_timer <= 0.0:
		_jink_timer = 1.0 / frequency
		_jink_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-0.3, 0.3)
		).normalized() * amplitude

	_ship.set_throttle(Vector3(signf(_jink_offset.x), signf(_jink_offset.y), -1.0))


func get_distance_to(pos: Vector3) -> float:
	if _ship == null:
		return INF
	return _ship.global_position.distance_to(pos)
