class_name DamageScreenEffect
extends CanvasLayer

# =============================================================================
# Damage Screen Effect — Red vignette flash + directional hit indicator
# Activates when the player takes damage. Shows a red flash from the edges
# and a brighter arc pointing toward the attacker's direction.
# Follows the same pattern as GForceEffects (CanvasLayer + shader).
# =============================================================================

var _rect: ColorRect = null
var _shader_mat: ShaderMaterial = null
var _ship = null
var _camera: Camera3D = null
var _health_system = null

var _damage_intensity: float = 0.0
var _hit_angle: float = 0.0
var _hit_intensity: float = 0.0

const DAMAGE_DECAY: float = 3.0      # Red vignette fades in ~0.3s
const HIT_DIR_DECAY: float = 1.8     # Directional arc fades in ~0.55s
const MIN_FLASH: float = 0.15        # Minimum flash even for tiny hits
const DAMAGE_SCALE: float = 4.0      # amount / hull_max * this = intensity


func _ready() -> void:
	layer = 2  # Above G-force (layer 1)

	var shader = load("res://shaders/damage_overlay.gdshader") as Shader
	if shader == null:
		push_warning("DamageScreenEffect: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _shader_mat
	_rect.visible = false
	add_child(_rect)


func set_ship(ship) -> void:
	# Disconnect old health system
	if _health_system and is_instance_valid(_health_system):
		if _health_system.damage_taken.is_connected(_on_damage_taken):
			_health_system.damage_taken.disconnect(_on_damage_taken)

	_ship = ship
	_camera = null
	_health_system = null
	_damage_intensity = 0.0
	_hit_intensity = 0.0

	if _ship == null:
		return

	_camera = _ship.get_node_or_null("ShipCamera")

	# Connect to HealthSystem
	var health = _ship.get_node_or_null("HealthSystem")
	if health:
		_health_system = health
		if not health.damage_taken.is_connected(_on_damage_taken):
			health.damage_taken.connect(_on_damage_taken)


func _on_damage_taken(attacker: Node3D, amount: float) -> void:
	if _ship == null:
		return

	# Flash intensity proportional to damage vs hull
	var max_hp: float = 1000.0
	if _health_system:
		max_hp = maxf(_health_system.hull_max, 100.0)

	var intensity: float = clampf(amount / max_hp * DAMAGE_SCALE, MIN_FLASH, 1.0)
	_damage_intensity = clampf(_damage_intensity + intensity, 0.0, 1.0)

	# Directional indicator from attacker position
	if attacker and is_instance_valid(attacker) and _camera and is_instance_valid(_camera):
		var dir_to_attacker: Vector3 = (attacker.global_position - _ship.global_position).normalized()
		# Project into camera's local space
		var cam_basis: Basis = _camera.global_transform.basis
		var local_dir: Vector3 = cam_basis.inverse() * dir_to_attacker
		# Convert to screen angle (X=right, Y=up in camera → UV Y is flipped)
		var screen_angle: float = atan2(-local_dir.y, local_dir.x)
		_hit_angle = screen_angle
		_hit_intensity = clampf(_hit_intensity + intensity, 0.0, 1.0)


func _process(delta: float) -> void:
	if _shader_mat == null:
		return

	# Decay
	_damage_intensity = maxf(_damage_intensity - DAMAGE_DECAY * delta, 0.0)
	_hit_intensity = maxf(_hit_intensity - HIT_DIR_DECAY * delta, 0.0)

	var any_effect: bool = _damage_intensity > 0.005 or _hit_intensity > 0.005
	_rect.visible = any_effect
	if not any_effect:
		return

	_shader_mat.set_shader_parameter("damage_intensity", _damage_intensity)
	_shader_mat.set_shader_parameter("hit_angle", _hit_angle)
	_shader_mat.set_shader_parameter("hit_intensity", _hit_intensity)
