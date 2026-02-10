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
@export var cam_rotation_speed: float = 18.0   ## Rotation follow speed
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
@export var fov_boost: float = 85.0
@export var fov_cruise: float = 95.0

@export_group("Cockpit")
@export var cockpit_offset: Vector3 = Vector3(0.0, 3.0, -5.0)

var camera_mode: CameraMode = CameraMode.THIRD_PERSON
var target_distance: float = 50.0
var current_distance: float = 50.0
var _current_fov: float = 75.0

var _ship: ShipController = null
var _targeting: TargetingSystem = null
var _weapon_manager: WeaponManager = null

var _shake_intensity: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _fov_spike: float = 0.0  # Temporary FOV burst (decays) — cruise punch/exit effects
const FOV_SPIKE_DECAY: float = 3.5

## Micro-vibration: subtle camera oscillation for immersive flight feel
var vibration_enabled: bool = false
var _vibration_time: float = 0.0
const VIBRATION_AMP_IDLE: float = 0.003    # Very subtle at idle
const VIBRATION_AMP_SPEED: float = 0.015   # Stronger at high speed
const VIBRATION_FREQ_X: float = 7.3
const VIBRATION_FREQ_Y: float = 5.1
const VIBRATION_FREQ_Z: float = 9.7


func _ready() -> void:
	_ship = get_parent() as ShipController
	if _ship == null:
		_ship = get_parent().get_parent() as ShipController
	set_as_top_level(true)

	# Sync runtime vars from export defaults
	target_distance = cam_distance_default
	current_distance = cam_distance_default
	_current_fov = fov_base

	# Initialize camera position immediately behind and above ship
	if _ship:
		var ship_basis: Basis = _ship.global_transform.basis
		var center: Vector3 = _ship.global_position + ship_basis * _ship.center_offset
		global_position = center + ship_basis * Vector3(0.0, cam_height, cam_distance_default)
		look_at(center, ship_basis.y)

	# Camera is top_level so floating origin shifts don't move it automatically.
	# We must shift it manually to avoid the camera lagging behind after each shift.
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)

	# Find combat systems after scene is ready
	_find_combat_systems.call_deferred()


func _find_combat_systems() -> void:
	if _ship == null:
		return
	_targeting = _ship.get_node_or_null("TargetingSystem") as TargetingSystem
	_weapon_manager = _ship.get_node_or_null("WeaponManager") as WeaponManager
	if _weapon_manager and not _weapon_manager.weapon_fired.is_connected(_on_weapon_fired):
		_weapon_manager.weapon_fired.connect(_on_weapon_fired)
	# Cruise VFX signals
	if not _ship.cruise_punch_triggered.is_connected(_on_cruise_punch):
		_ship.cruise_punch_triggered.connect(_on_cruise_punch)
	if not _ship.cruise_exit_triggered.is_connected(_on_cruise_exit):
		_ship.cruise_exit_triggered.connect(_on_cruise_exit)


func _on_weapon_fired(_hardpoint_id: int, _weapon_name: StringName) -> void:
	_shake_intensity = maxf(_shake_intensity, cam_shake_fire)


func _on_cruise_punch() -> void:
	_fov_spike = 18.0           # Big FOV burst outward
	_shake_intensity = maxf(_shake_intensity, 0.6)


func _on_cruise_exit() -> void:
	_fov_spike = -14.0          # FOV slams inward (deceleration punch)
	_shake_intensity = maxf(_shake_intensity, 0.45)


func _input(event: InputEvent) -> void:
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
	# DYNAMIC DISTANCE (speed pull-back only)
	# =========================================================================
	var speed_pull: float = minf(_ship.current_speed * cam_speed_pull, 10.0)
	var effective_distance: float = target_distance + speed_pull
	current_distance = lerpf(current_distance, effective_distance, 3.0 * delta)

	# =========================================================================
	# CAMERA POSITION (behind and above the ship)
	# =========================================================================
	var cam_offset: Vector3 = Vector3(0.0, cam_height, current_distance)
	var desired_pos: Vector3 = ship_pos + ship_basis * cam_offset

	# Weapon fire shake
	if _shake_intensity > 0.005:
		_shake_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.5, 0.5),
			randf_range(-0.3, 0.3)
		) * _shake_intensity
		desired_pos += ship_basis * _shake_offset
		_shake_intensity *= maxf(0.0, 1.0 - cam_shake_decay * delta)
	else:
		_shake_intensity = 0.0

	# Micro-vibration (subtle engine hum feel)
	if vibration_enabled:
		_vibration_time += delta
		var speed_ratio: float = clampf(_ship.current_speed / Constants.MAX_SPEED_CRUISE, 0.0, 1.0)
		var amp: float = lerpf(VIBRATION_AMP_IDLE, VIBRATION_AMP_SPEED, speed_ratio)
		var vib := Vector3(
			sin(_vibration_time * VIBRATION_FREQ_X * TAU) * amp,
			sin(_vibration_time * VIBRATION_FREQ_Y * TAU) * amp * 0.7,
			sin(_vibration_time * VIBRATION_FREQ_Z * TAU) * amp * 0.3
		)
		desired_pos += ship_basis * vib

	# Smooth position follow
	var follow: float = cam_follow_speed * delta
	global_position = global_position.lerp(desired_pos, follow)

	# =========================================================================
	# LOOK TARGET (far ahead along ship forward to minimize aim offset)
	# Ship appears in the lower portion of the screen; crosshair area is clear.
	# =========================================================================
	var look_ahead: float = 50.0 + minf(_ship.current_speed * 0.1, 100.0)
	var look_target: Vector3 = ship_pos + ship_basis * Vector3(0.0, cam_look_ahead_y, -look_ahead)

	# =========================================================================
	# SMOOTH ROTATION
	# =========================================================================
	var rot_follow: float = cam_rotation_speed * delta
	var current_forward: Vector3 = -global_transform.basis.z
	var desired_forward: Vector3 = (look_target - global_position).normalized()
	var smooth_forward: Vector3 = current_forward.lerp(desired_forward, rot_follow).normalized()

	if smooth_forward.length_squared() > 0.001:
		var up_hint := ship_basis.y.lerp(Vector3.UP, 0.05)
		# Gram-Schmidt orthogonalization: strip the forward component → guaranteed perpendicular
		var up_vec := (up_hint - smooth_forward * smooth_forward.dot(up_hint)).normalized()
		look_at(global_position + smooth_forward, up_vec)

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
		Constants.SpeedMode.CRUISE:
			# Phase 1 (spool): FOV gradually increases from base toward boost+
			if _ship and _ship.cruise_time < _ship.CRUISE_SPOOL_DURATION:
				var t := _ship.cruise_time / _ship.CRUISE_SPOOL_DURATION
				return lerpf(fov_base, fov_boost + 2.0, t * t)
			# Phase 2 (punch active): full cruise FOV
			return fov_cruise
	return fov_base


func _on_origin_shifted(delta: Vector3) -> void:
	# Camera is top_level — it doesn't shift with the parent.
	# Apply the same shift so camera stays in sync with the ship.
	global_position -= delta
