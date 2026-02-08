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
@export var cam_height: float = 10.0           ## Height above ship
@export var cam_distance_default: float = 25.0 ## Default follow distance
@export var cam_distance_min: float = 8.0      ## Min zoom distance
@export var cam_distance_max: float = 250.0    ## Max zoom distance
@export var cam_follow_speed: float = 18.0     ## Position follow speed
@export var cam_rotation_speed: float = 18.0   ## Rotation follow speed
@export var cam_look_ahead_y: float = -2.0     ## Look below ship center
@export var cam_speed_pull: float = 0.02       ## Extra distance per m/s
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


func _on_weapon_fired(_hardpoint_id: int, _weapon_name: StringName) -> void:
	_shake_intensity = maxf(_shake_intensity, cam_shake_fire)


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
	var speed_pull: float = minf(_ship.current_speed * cam_speed_pull, 30.0)  # Cap pull-back at cruise speeds
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

	# Smooth position follow
	var follow: float = cam_follow_speed * delta
	global_position = global_position.lerp(desired_pos, follow)

	# =========================================================================
	# LOOK TARGET (well ahead of ship center, below camera plane)
	# Ship appears in the lower portion of the screen; crosshair area is clear.
	# =========================================================================
	var look_ahead: float = 15.0 + minf(_ship.current_speed * 0.05, 50.0)
	var look_target: Vector3 = ship_pos + ship_basis * Vector3(0.0, cam_look_ahead_y, -look_ahead)

	# =========================================================================
	# SMOOTH ROTATION
	# =========================================================================
	var rot_follow: float = cam_rotation_speed * delta
	var current_forward: Vector3 = -global_transform.basis.z
	var desired_forward: Vector3 = (look_target - global_position).normalized()
	var smooth_forward: Vector3 = current_forward.lerp(desired_forward, rot_follow).normalized()

	if smooth_forward.length() > 0.001:
		look_at(global_position + smooth_forward, ship_basis.y.lerp(Vector3.UP, 0.05))

	# =========================================================================
	# DYNAMIC FOV
	# =========================================================================
	var target_fov: float = _get_fov_for_mode(_ship.speed_mode)
	_current_fov = lerpf(_current_fov, target_fov, 2.0 * delta)
	fov = _current_fov


func _update_cockpit(delta: float) -> void:
	var ship_basis: Basis = _ship.global_transform.basis
	var ship_pos: Vector3 = _ship.global_position + ship_basis * _ship.center_offset

	global_position = ship_pos + ship_basis * cockpit_offset
	global_transform.basis = ship_basis

	# FOV in cockpit
	var target_fov: float = _get_fov_for_mode(_ship.speed_mode) + 5.0
	_current_fov = lerpf(_current_fov, target_fov, 2.0 * delta)
	fov = _current_fov


func _get_fov_for_mode(mode: int) -> float:
	match mode:
		Constants.SpeedMode.BOOST: return fov_boost
		Constants.SpeedMode.CRUISE: return fov_cruise
	return fov_base


func _on_origin_shifted(delta: Vector3) -> void:
	# Camera is top_level — it doesn't shift with the parent.
	# Apply the same shift so camera stays in sync with the ship.
	global_position -= delta
