class_name LensFlare
extends MeshInstance3D

# =============================================================================
# Lens Flare - Anamorphic flare on the sun.
# Created as a child of SystemStar. Uses dot product with camera forward
# for fade (no raycast needed — the star is always "visible" in space).
# =============================================================================

var _shader_mat: ShaderMaterial = null
var _base_scale: float = 800.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)

	var shader := load("res://shaders/lens_flare.gdshader") as Shader
	if shader == null:
		push_warning("LensFlare: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.render_priority = 50
	quad.material = _shader_mat
	mesh = quad

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16384.0


func setup(star_color: Color, star_luminosity: float) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("flare_color", Vector3(star_color.r, star_color.g, star_color.b))
		_shader_mat.set_shader_parameter("flare_intensity", clampf(0.5 + star_luminosity * 0.3, 0.3, 1.5))
	_base_scale = 600.0 + star_luminosity * 200.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		visible = false
		return

	# Fade based on angle between camera forward and direction to sun
	var to_flare := (global_position - cam.global_position).normalized()
	var cam_forward := -cam.global_basis.z
	var dot_val: float = cam_forward.dot(to_flare)

	# Only show when sun is roughly in front of camera
	if dot_val < 0.1:
		visible = false
		return

	visible = true
	# Smooth fade: strongest when looking directly at sun
	var fade: float = smoothstep(0.1, 0.6, dot_val)
	scale = Vector3.ONE * _base_scale * fade


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
