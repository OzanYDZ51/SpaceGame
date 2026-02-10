class_name UIPostProcessOverlay
extends ColorRect

# =============================================================================
# UI Post-Process Overlay - Full-screen scanlines + vignette
# Added as last child of UIScreenManager, toggled with screen open/close.
# =============================================================================

var _shader_mat: ShaderMaterial = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Transparent base color — shader does all the work
	color = Color(0, 0, 0, 0)
	_shader_mat = UIShaderCache.get_post_process_material()
	material = _shader_mat


func activate() -> void:
	visible = true


func deactivate() -> void:
	visible = false
