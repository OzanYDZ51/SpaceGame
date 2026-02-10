class_name UIShaderCache
extends RefCounted

# =============================================================================
# UI Shader Cache - Preloads and caches ShaderMaterial instances
# Avoids creating duplicate materials for each UIComponent.
# =============================================================================

static var _panel_shader: Shader = null
static var _panel_material: ShaderMaterial = null
static var _blur_shader: Shader = null
static var _glow_shader: Shader = null
static var _post_process_shader: Shader = null
static var _post_process_material: ShaderMaterial = null
static var _data_stream_shader: Shader = null
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_panel_shader = load("res://shaders/ui/ui_hologram_panel.gdshader")
	_blur_shader = load("res://shaders/ui/ui_blur.gdshader")
	_glow_shader = load("res://shaders/ui/ui_glow_border.gdshader")
	_post_process_shader = load("res://shaders/ui/ui_post_process.gdshader")
	_data_stream_shader = load("res://shaders/ui/ui_data_stream.gdshader")


## Returns a shared panel hologram material (scanlines + grain + flicker + edge glow).
static func get_panel_material() -> ShaderMaterial:
	_ensure_init()
	if _panel_material == null:
		_panel_material = ShaderMaterial.new()
		_panel_material.shader = _panel_shader
	return _panel_material


## Returns a NEW blur material (each screen may need its own instance).
static func create_blur_material() -> ShaderMaterial:
	_ensure_init()
	var mat := ShaderMaterial.new()
	mat.shader = _blur_shader
	return mat


## Returns a NEW glow border material (per-component instance for independent pulse).
static func create_glow_material() -> ShaderMaterial:
	_ensure_init()
	var mat := ShaderMaterial.new()
	mat.shader = _glow_shader
	return mat


## Returns a shared post-process material.
static func get_post_process_material() -> ShaderMaterial:
	_ensure_init()
	if _post_process_material == null:
		_post_process_material = ShaderMaterial.new()
		_post_process_material.shader = _post_process_shader
	return _post_process_material


## Returns a NEW data stream material.
static func create_data_stream_material() -> ShaderMaterial:
	_ensure_init()
	var mat := ShaderMaterial.new()
	mat.shader = _data_stream_shader
	return mat
