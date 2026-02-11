class_name SpeedEffects
extends CanvasLayer

# =============================================================================
# Speed Effects - Quantum travel post-processing (Star Citizen style)
# Radial scene stretch, blue quantum vignette, chromatic aberration.
# Rendered on CanvasLayer 0 (before UI) so HUD stays crisp.
#
# Two intensity drivers sent to shader:
#   flight_ratio  = speed / boost_max → subtle effects for normal/boost flight
#   cruise_spool  = cruise_time / spool_duration → 0→1 over 10s, main quantum ramp
# =============================================================================

var _rect: ColorRect = null
var _shader_mat: ShaderMaterial = null
var _ship: ShipController = null

var _damage_flash: float = 0.0
var _cruise_warp: float = 0.0
var _cruise_spool: float = 0.0    # Smooth spool-up visual intensity
var _quantum_engage: float = 0.0  # Brief pulse when cruise activates
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


func trigger_damage_flash(_attacker: Node3D = null, _amount: float = 0.0) -> void:
	_damage_flash = 1.0


func _process(delta: float) -> void:
	if _shader_mat == null or _ship == null:
		return

	# Flight ratio: speed relative to boost max (visible during normal/boost flight)
	var flight_ratio: float = clampf(_ship.current_speed / maxf(Constants.MAX_SPEED_BOOST, 1.0), 0.0, 1.0)

	# Cruise spool: 0→1 based on cruise_time, independent of actual speed
	var target_spool: float = 0.0
	if _ship.speed_mode == Constants.SpeedMode.CRUISE:
		target_spool = clampf(_ship.cruise_time / _ship.CRUISE_SPOOL_DURATION, 0.0, 1.0)
	_cruise_spool = lerpf(_cruise_spool, target_spool, delta * 3.0)

	# Detect speed mode transitions — quantum engage pulse
	if _ship.speed_mode != _prev_speed_mode:
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_quantum_engage = 1.0
		_prev_speed_mode = _ship.speed_mode

	# Cruise warp (phase 2) — smooth ramp
	var target_warp: float = 1.0 if _ship.cruise_warp_active else 0.0
	_cruise_warp = lerpf(_cruise_warp, target_warp, delta * (2.5 if target_warp > _cruise_warp else 4.0))

	# Decay flashes
	_damage_flash = maxf(0.0, _damage_flash - delta * 3.5)
	_quantum_engage = maxf(0.0, _quantum_engage - delta * 2.5)

	# Hide when no effect active (zero GPU cost)
	var any_effect: bool = flight_ratio > 0.01 or _cruise_spool > 0.01 or _damage_flash > 0.01 or _cruise_warp > 0.01 or _quantum_engage > 0.01
	_rect.visible = any_effect
	if not any_effect:
		return

	_shader_mat.set_shader_parameter("flight_ratio", flight_ratio)
	_shader_mat.set_shader_parameter("cruise_spool", _cruise_spool)
	_shader_mat.set_shader_parameter("damage_flash", _damage_flash)
	_shader_mat.set_shader_parameter("cruise_warp", _cruise_warp)
	_shader_mat.set_shader_parameter("quantum_engage", _quantum_engage)
