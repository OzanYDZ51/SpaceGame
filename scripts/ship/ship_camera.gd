class_name ShipCamera
extends Camera3D

# =============================================================================
# Ship Camera - Cinematic combat camera system
# Elevated "over the ship" view so the crosshair area is clear above the ship.
# Dynamic combat tightening, weapon fire shake, target-look bias.
# Inspired by Star Citizen / Elite Dangerous third-person cameras.
# =============================================================================

enum CameraMode { THIRD_PERSON, COCKPIT }

@export_group("Third Person")
@export var cam_height: float = 8.0            ## Height above ship
@export var cam_distance_default: float = 25.0 ## Default follow distance
@export var cam_distance_min: float = 8.0      ## Min zoom distance
@export var cam_distance_max: float = 250.0    ## Max zoom distance
@export var cam_follow_speed: float = 18.0     ## Position follow speed
@export var cam_rotation_speed: float = 10.0   ## Rotation follow speed (low = cinematic lag)
@export var cam_look_ahead_y: float = 0.0      ## Vertical offset for look target
@export var cam_speed_pull: float = 0.008      ## Extra distance per m/s
@export var cam_zoom_step: float = 10.0        ## Distance per scroll tick

@export_group("Combat")
@export var cam_combat_pull: float = 0.0       ## No distance change on target lock
@export var cam_combat_follow: float = 1.0     ## Same follow speed in/out combat
@export var cam_shake_fire: float = 0.10       ## Weapon fire shake intensity
@export var cam_shake_decay: float = 12.0      ## Shake decay speed

@export_group("FOV")
@export var fov_base: float = 75.0
@export var fov_boost: float = 78.0
@export var fov_cruise: float = 75.0  # No FOV change in cruise — shader handles speed feel

@export_group("Cockpit")
@export var cockpit_offset: Vector3 = Vector3(0.0, 3.0, -5.0)

var camera_mode: CameraMode = CameraMode.THIRD_PERSON
var target_distance: float = 50.0
var current_distance: float = 50.0
var _current_fov: float = 75.0

var _ship = null
var _targeting = null
var _weapon_manager = null

var _fov_spike: float = 0.0  # Temporary FOV burst (decays) — cruise punch/exit effects

## Spring-damper position follow (replaces lerp for cinematic inertia + overshoot)
var _spring_velocity: Vector3 = Vector3.ZERO
const SPRING_STIFFNESS: float = 120.0
const SPRING_DAMPING: float = 18.0

## G-force camera sway (visual inertia feedback on acceleration)
var _prev_velocity: Vector3 = Vector3.ZERO
var _gforce_offset: Vector3 = Vector3.ZERO
const GFORCE_STRENGTH: float = 0.015  # Meters of offset per m/s²
const GFORCE_MAX: float = 0.8
const GFORCE_DECAY: float = 4.0

## Layered camera shake (sin-based, replaces flat randf jitter)
var _shake_layers: Array[Dictionary] = []

## Public free-look state (readable by HUD)
var is_free_looking: bool = false
const FOV_SPIKE_DECAY: float = 3.5

## Planetary mode: when set, camera uses planet surface as "up" reference
var planetary_up: Vector3 = Vector3.ZERO  ## Non-zero when near planet surface
var planetary_up_blend: float = 0.0       ## 0 = space mode, 1 = full planetary up

## Micro-vibration: subtle camera oscillation for immersive flight feel
var vibration_enabled: bool = false
var _vibration_time: float = 0.0
const VIBRATION_AMP_IDLE: float = 0.003    # Very subtle at idle
const VIBRATION_AMP_SPEED: float = 0.015   # Stronger at high speed
const VIBRATION_FREQ_X: float = 7.3
const VIBRATION_FREQ_Y: float = 5.1
const VIBRATION_FREQ_Z: float = 9.7

## Free look: orbit camera around ship during cruise (mouse redirected from ship rotation)
var _free_look_yaw: float = 0.0
var _free_look_pitch: float = 0.0
const FREE_LOOK_SENSITIVITY: float = 0.15
const FREE_LOOK_PITCH_MAX: float = 80.0
const FREE_LOOK_RETURN_SPEED: float = 4.0

## Ship-size camera scaling — base values saved from @export defaults
const CAMERA_REF_SCALE: float = 2.0  ## Reference model_scale (fighters)
var _base_distance_default: float
var _base_distance_min: float
var _base_distance_max: float
var _base_height: float
var _base_zoom_step: float
var _base_cockpit_offset: Vector3


func _ready() -> void:
	_ship = get_parent()
	if _ship == null or not _ship.has_method("set_throttle"):
		_ship = get_parent().get_parent()

	# Server-side ships are plain Node3D — no camera needed
	if _ship == null or not ("center_offset" in _ship):
		set_process(false)
		set_process_unhandled_input(false)
		return

	set_as_top_level(true)

	# Snapshot @export defaults as base reference for ship-size scaling
	_base_distance_default = cam_distance_default
	_base_distance_min = cam_distance_min
	_base_distance_max = cam_distance_max
	_base_height = cam_height
	_base_zoom_step = cam_zoom_step
	_base_cockpit_offset = cockpit_offset

	# Auto-scale camera params to ship size
	adapt_to_ship_size()

	# Sync runtime vars from export defaults
	target_distance = cam_distance_default
	current_distance = cam_distance_default
	_current_fov = fov_base

	# Initialize camera position immediately behind and above ship
	var ship_basis: Basis = _ship.global_transform.basis
	var center: Vector3 = _ship.global_position + ship_basis * _ship.center_offset
	global_position = center + ship_basis * Vector3(0.0, cam_height, cam_distance_default)
	look_at(center, ship_basis.y)

	# Camera is top_level so floating origin shifts don't move it automatically.
	# We must shift it manually to avoid the camera lagging behind after each shift.
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)

	# Re-adapt camera when player switches ships
	GameManager.player_ship_rebuilt.connect(_on_ship_rebuilt)

	# Find combat systems after scene is ready
	_find_combat_systems.call_deferred()


func _find_combat_systems() -> void:
	if _ship == null:
		return
	_targeting = _ship.get_node_or_null("TargetingSystem")
	_weapon_manager = _ship.get_node_or_null("WeaponManager")
	if _weapon_manager and not _weapon_manager.weapon_fired.is_connected(_on_weapon_fired):
		_weapon_manager.weapon_fired.connect(_on_weapon_fired)
	# Cruise VFX signals (may not exist on server-side ships)
	if _ship.has_signal("cruise_punch_triggered") and not _ship.cruise_punch_triggered.is_connected(_on_cruise_punch):
		_ship.cruise_punch_triggered.connect(_on_cruise_punch)
	if _ship.has_signal("cruise_exit_triggered") and not _ship.cruise_exit_triggered.is_connected(_on_cruise_exit):
		_ship.cruise_exit_triggered.connect(_on_cruise_exit)


## Auto-scale camera distance, height, zoom bounds to match ship visual size.
## Uses model_scale from ShipData — larger ships get proportionally farther camera.
## All values are derived from the saved @export base values × a sub-linear factor.
func adapt_to_ship_size() -> void:
	if _ship == null:
		return
	var ship_data = _ship.get("ship_data")
	if ship_data == null:
		return
	var model_scale: float = ship_data.model_scale
	if model_scale <= 0.0:
		return
	var ratio: float = model_scale / CAMERA_REF_SCALE
	# Sub-linear curve: pow(ratio, 0.7) prevents absurd distances on huge ships
	var factor: float = pow(maxf(ratio, 1.0), 0.7)
	cam_distance_default = _base_distance_default * factor
	cam_distance_min = _base_distance_min * factor
	cam_distance_max = _base_distance_max * factor
	cam_height = _base_height * factor
	cam_zoom_step = _base_zoom_step * maxf(factor * 0.6, 1.0)
	cockpit_offset = _base_cockpit_offset * factor


func _on_ship_rebuilt(_ship_ref) -> void:
	adapt_to_ship_size()
	# Smoothly transition to new default distance
	target_distance = cam_distance_default
	_find_combat_systems()


func _on_weapon_fired(_hardpoint_id: int, _weapon_name: StringName) -> void:
	_shake_layers.append({"intensity": cam_shake_fire, "decay": 15.0, "frequency": 2.0, "time": 0.0})


func _on_cruise_punch() -> void:
	_shake_layers.append({"intensity": 0.20, "decay": 6.0, "frequency": 0.5, "time": 0.0})


func _on_cruise_exit() -> void:
	_shake_layers.append({"intensity": 0.12, "decay": 8.0, "frequency": 0.8, "time": 0.0})


func _unhandled_input(event: InputEvent) -> void:
	if camera_mode == CameraMode.THIRD_PERSON:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_distance = max(cam_distance_min, target_distance - cam_zoom_step)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_distance = min(cam_distance_max, target_distance + cam_zoom_step)

	if event.is_action_pressed("toggle_camera"):
		camera_mode = CameraMode.COCKPIT if camera_mode == CameraMode.THIRD_PERSON else CameraMode.THIRD_PERSON


func _process(delta: float) -> void:
	if _ship == null:
		return

	# Lazy-connect combat systems if not found yet
	if _targeting == null or _weapon_manager == null:
		_find_combat_systems()

	match camera_mode:
		CameraMode.THIRD_PERSON:
			_update_third_person(delta)
		CameraMode.COCKPIT:
			_update_cockpit(delta)


func _update_third_person(delta: float) -> void:
	var ship_basis: Basis = _ship.global_transform.basis
	# Use ShipCenter offset as the visual center of the ship
	var ship_pos: Vector3 = _ship.global_position + ship_basis * _ship.center_offset

	# =========================================================================
	# FREE LOOK (Alt key or cruise: mouse orbits camera; otherwise smooth return)
	# =========================================================================
	if _ship.free_look_active:
		# Accumulate mouse delta while free look is held
		var md: Vector2 = _ship.cruise_look_delta
		if md.length_squared() > 0.01:
			_free_look_yaw += md.x * FREE_LOOK_SENSITIVITY
			_free_look_pitch += md.y * FREE_LOOK_SENSITIVITY
			_free_look_pitch = clampf(_free_look_pitch, -FREE_LOOK_PITCH_MAX, FREE_LOOK_PITCH_MAX)
		is_free_looking = true
	else:
		# Free look released — smoothly return camera behind ship
		_free_look_yaw = lerpf(_free_look_yaw, 0.0, FREE_LOOK_RETURN_SPEED * delta)
		_free_look_pitch = lerpf(_free_look_pitch, 0.0, FREE_LOOK_RETURN_SPEED * delta)
		if absf(_free_look_yaw) < 0.1:
			_free_look_yaw = 0.0
		if absf(_free_look_pitch) < 0.1:
			_free_look_pitch = 0.0
		is_free_looking = absf(_free_look_yaw) > 0.5 or absf(_free_look_pitch) > 0.5

	# =========================================================================
	# DYNAMIC DISTANCE (fixed — no speed pull-back in any mode)
	# =========================================================================
	current_distance = lerpf(current_distance, target_distance, 3.0 * delta)

	# =========================================================================
	# G-FORCE CAMERA SWAY (visual inertia: camera shifts opposite to acceleration)
	# =========================================================================
	var velocity: Vector3 = _ship.linear_velocity
	var accel_world: Vector3 = (velocity - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = velocity
	var accel_local: Vector3 = ship_basis.inverse() * accel_world
	var target_gforce: Vector3 = -accel_local * GFORCE_STRENGTH
	target_gforce = target_gforce.limit_length(GFORCE_MAX)
	_gforce_offset = _gforce_offset.lerp(target_gforce, GFORCE_DECAY * delta)

	# =========================================================================
	# CAMERA POSITION (behind and above the ship)
	# =========================================================================
	var cam_offset: Vector3 = Vector3(0.0, cam_height, current_distance)
	if is_free_looking:
		var fl_basis: Basis = Basis(Vector3.UP, deg_to_rad(-_free_look_yaw))
		fl_basis = fl_basis * Basis(Vector3.RIGHT, deg_to_rad(-_free_look_pitch))
		cam_offset = fl_basis * cam_offset
	var desired_pos: Vector3 = ship_pos + ship_basis * (cam_offset + _gforce_offset)

	# Camera shake (layered sin-based — each event adds a decaying layer)
	if not _shake_layers.is_empty():
		var shake_total: Vector3 = Vector3.ZERO
		var i: int = _shake_layers.size() - 1
		while i >= 0:
			var layer: Dictionary = _shake_layers[i]
			layer["time"] += delta
			layer["intensity"] *= maxf(0.0, 1.0 - layer["decay"] * delta)
			if layer["intensity"] < 0.002:
				_shake_layers.remove_at(i)
				i -= 1
				continue
			var t: float = layer["time"] * layer["frequency"] * TAU
			shake_total += Vector3(
				sin(t * 1.0),
				sin(t * 0.7 + 1.3),
				sin(t * 0.5 + 2.7)
			) * layer["intensity"]
			i -= 1
		desired_pos += ship_basis * shake_total

	# Micro-vibration (subtle engine hum feel)
	if vibration_enabled:
		_vibration_time += delta
		var speed_ratio: float = clampf(_ship.current_speed / Constants.MAX_SPEED_CRUISE, 0.0, 1.0)
		var amp: float = lerpf(VIBRATION_AMP_IDLE, VIBRATION_AMP_SPEED, speed_ratio)
		var vib: Vector3 = Vector3(
			sin(_vibration_time * VIBRATION_FREQ_X * TAU) * amp,
			sin(_vibration_time * VIBRATION_FREQ_Y * TAU) * amp * 0.7,
			sin(_vibration_time * VIBRATION_FREQ_Z * TAU) * amp * 0.3
		)
		desired_pos += ship_basis * vib

	# Position follow: spring-damper in normal/boost, snap in cruise
	if _ship.speed_mode == Constants.SpeedMode.CRUISE:
		# Snap in cruise — ship must not outrun camera at quantum speeds
		global_position = desired_pos
		_spring_velocity = Vector3.ZERO
	else:
		var spring_accel: Vector3 = (desired_pos - global_position) * SPRING_STIFFNESS - _spring_velocity * SPRING_DAMPING
		_spring_velocity += spring_accel * delta
		_spring_velocity = _spring_velocity.limit_length(5000.0)
		global_position += _spring_velocity * delta
		# Safety snap: if camera drifted too far (spawn/teleport), catch up immediately
		if (desired_pos - global_position).length_squared() > 10000.0:  # > 100m
			global_position = desired_pos
			_spring_velocity = Vector3.ZERO

	# =========================================================================
	# LOOK TARGET
	# Free look: look at the ship. Normal: look far ahead along ship forward.
	# =========================================================================
	var look_target: Vector3
	if is_free_looking:
		look_target = ship_pos
	else:
		var look_ahead: float = 50.0 + minf(_ship.current_speed * 0.1, 100.0)
		look_target = ship_pos + ship_basis * Vector3(0.0, cam_look_ahead_y, -look_ahead)

	# =========================================================================
	# SMOOTH ROTATION (combat boost: faster tracking when target-locked)
	# =========================================================================
	var rot_speed: float = cam_rotation_speed
	if _targeting and is_instance_valid(_targeting) and _targeting.current_target and is_instance_valid(_targeting.current_target):
		rot_speed = 12.0
	var rot_follow: float = rot_speed * delta
	var current_forward: Vector3 = -global_transform.basis.z
	var desired_forward: Vector3 = (look_target - global_position).normalized()
	var smooth_forward: Vector3 = current_forward.lerp(desired_forward, rot_follow).normalized()

	if smooth_forward.length_squared() > 0.001:
		var target_pos: Vector3 = global_position + smooth_forward
		if not global_position.is_equal_approx(target_pos):
			var up_hint: Vector3 = ship_basis.y.lerp(Vector3.UP, 0.05)
			# Planetary mode: blend toward planet surface normal as "up"
			if planetary_up_blend > 0.01 and planetary_up.length_squared() > 0.5:
				up_hint = up_hint.lerp(planetary_up, planetary_up_blend)
			# Gram-Schmidt orthogonalization: strip the forward component → guaranteed perpendicular
			var up_vec: Vector3 = (up_hint - smooth_forward * smooth_forward.dot(up_hint)).normalized()
			if up_vec.length_squared() > 0.001:
				look_at(target_pos, up_vec)

	# =========================================================================
	# DYNAMIC FOV (phase-aware cruise + spike effects)
	# =========================================================================
	var target_fov: float = _get_fov_for_mode(_ship.speed_mode)
	_current_fov = lerpf(_current_fov, target_fov, 2.0 * delta)
	# Cruise punch/exit spike (decays over time)
	_fov_spike = lerpf(_fov_spike, 0.0, FOV_SPIKE_DECAY * delta)
	fov = _current_fov + _fov_spike


func _update_cockpit(delta: float) -> void:
	var ship_basis: Basis = _ship.global_transform.basis
	var ship_pos: Vector3 = _ship.global_position + ship_basis * _ship.center_offset

	global_position = ship_pos + ship_basis * cockpit_offset
	global_transform.basis = ship_basis

	# FOV in cockpit
	var target_fov: float = _get_fov_for_mode(_ship.speed_mode) + 5.0
	_current_fov = lerpf(_current_fov, target_fov, 2.0 * delta)
	_fov_spike = lerpf(_fov_spike, 0.0, FOV_SPIKE_DECAY * delta)
	fov = _current_fov + _fov_spike


func _get_fov_for_mode(mode: int) -> float:
	match mode:
		Constants.SpeedMode.BOOST: return fov_boost
		Constants.SpeedMode.CRUISE: return fov_base  # Zero FOV change — no fisheye
	return fov_base


func _on_origin_shifted(shift: Vector3) -> void:
	# Camera is top_level — it doesn't shift with the parent.
	# Apply the same shift so camera stays in sync with the ship.
	global_position -= shift
	# Reset spring to avoid explosion from sudden position discontinuity
	_spring_velocity = Vector3.ZERO
	_prev_velocity = _ship.linear_velocity if _ship else Vector3.ZERO
