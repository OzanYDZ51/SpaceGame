class_name SpeedEffects
extends CanvasLayer

# =============================================================================
# Speed Effects - Fullscreen cinematic post-processing
# Radial motion blur, animated speed streaks, vignette, chromatic aberration,
# boost flash, damage flash. All driven by ship speed.
# Rendered on CanvasLayer 0 (before UI) so HUD stays crisp.
# =============================================================================

var _rect: ColorRect = null
var _shader_mat: ShaderMaterial = null
var _ship: ShipController = null

var _boost_flash: float = 0.0
var _damage_flash: float = 0.0
var _prev_speed_mode: int = 0


func _ready() -> void:
	layer = 0

	var shader := load("res://shaders/speed_lines.gdshader") as Shader
	if shader == null:
		push_warning("SpeedEffects: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _shader_mat
	_rect.visible = false
	add_child(_rect)


func set_ship(ship: ShipController) -> void:
	_ship = ship
	_prev_speed_mode = ship.speed_mode


func trigger_damage_flash() -> void:
	_damage_flash = 0.7


func _process(delta: float) -> void:
	if _shader_mat == null or _ship == null:
		return

	var ratio: float = clampf(_ship.current_speed / Constants.MAX_SPEED_CRUISE, 0.0, 1.0)

	# Detect speed mode transitions
	if _ship.speed_mode != _prev_speed_mode:
		if _ship.speed_mode == Constants.SpeedMode.BOOST:
			_boost_flash = 0.6
		elif _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_boost_flash = 1.0
		_prev_speed_mode = _ship.speed_mode

	# Decay flashes
	_boost_flash = maxf(0.0, _boost_flash - delta * 3.0)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.0)

	# Hide when no effect active (zero GPU cost)
	var any_effect: bool = ratio > 0.01 or _boost_flash > 0.01 or _damage_flash > 0.01
	_rect.visible = any_effect
	if not any_effect:
		return

	_shader_mat.set_shader_parameter("speed_ratio", ratio)
	_shader_mat.set_shader_parameter("boost_flash", _boost_flash)
	_shader_mat.set_shader_parameter("damage_flash", _damage_flash)
