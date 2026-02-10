class_name EngineHeatHaze
extends MeshInstance3D

# =============================================================================
# Engine Heat Haze - Screen-space distortion behind engine exhausts
# Child of ShipModel. Uses a spatial shader with hint_screen_texture.
# Intensity driven by throttle input.
# =============================================================================

var _shader_mat: ShaderMaterial = null
var _current_intensity: float = 0.0

const ENGINE_OFFSET := Vector3(0.0, 0.0, 7.0)  # Behind engines (+Z)
const QUAD_SIZE := Vector2(4.0, 3.0)


func setup(p_model_scale: float) -> void:
	# Position behind engines
	position = ENGINE_OFFSET * p_model_scale

	# Create quad mesh
	var quad := QuadMesh.new()
	quad.size = QUAD_SIZE * p_model_scale
	mesh = quad

	# Load shader
	var shader := load("res://shaders/heat_distortion.gdshader") as Shader
	if shader == null:
		push_warning("EngineHeatHaze: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("intensity", 0.0)
	_shader_mat.set_shader_parameter("distortion_scale", 0.015 * p_model_scale)
	material_override = _shader_mat

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func update_intensity(throttle: float) -> void:
	if _shader_mat == null:
		return
	_current_intensity = lerpf(_current_intensity, throttle, 0.1)
	_shader_mat.set_shader_parameter("intensity", _current_intensity)
