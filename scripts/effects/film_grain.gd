class_name FilmGrain
extends CanvasLayer

# =============================================================================
# Film Grain - Fullscreen subtle noise overlay to break color banding.
# Always active. Rendered on a high CanvasLayer so it composites after
# everything else (including post-process effects).
# =============================================================================

var _rect: ColorRect = null
var _shader_mat: ShaderMaterial = null


func _ready() -> void:
	layer = 10  # Above UI and other post-process layers

	var shader := load("res://shaders/film_grain.gdshader") as Shader
	if shader == null:
		push_warning("FilmGrain: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("grain_strength", 0.025)

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _shader_mat
	add_child(_rect)
