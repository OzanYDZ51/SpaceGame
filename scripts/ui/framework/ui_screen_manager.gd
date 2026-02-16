class_name UIScreenManager
extends Control

# =============================================================================
# UI Screen Manager - Screen stack, transitions, input routing
# Added to the UI CanvasLayer by GameManager.
# Rules: One FULLSCREEN at a time. OVERLAYs stack on top.
# Owns the shared blur background.
# Post-process lives in its own CanvasLayer above the UI layer so that
# hint_screen_texture captures all UI content (not just the 3D scene).
# =============================================================================

var _screens: Dictionary = {}  # name -> UIScreen
var _screen_stack: Array[UIScreen] = []
var _blur_rect: ColorRect = null
var _post_process: UIPostProcessOverlay = null
var _post_process_layer: CanvasLayer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full rect
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)

	# Blur background (index 0 — behind all screens)
	_blur_rect = ColorRect.new()
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.color = Color(0, 0, 0, 0)
	_blur_rect.material = UIShaderCache.create_blur_material()
	_blur_rect.visible = false
	add_child(_blur_rect)

	# Post-process overlay in its own CanvasLayer (above UI layer).
	# hint_screen_texture only captures content from layers rendered BEFORE it,
	# so the post-process must be in a higher layer to see the UI screens.
	var ui_layer_num: int = 10  # Default UI layer
	var parent_layer := _find_parent_canvas_layer()
	if parent_layer:
		ui_layer_num = parent_layer.layer

	_post_process_layer = CanvasLayer.new()
	_post_process_layer.layer = ui_layer_num + 1
	_post_process_layer.name = "UIPostProcessLayer"
	add_child(_post_process_layer)

	_post_process = UIPostProcessOverlay.new()
	_post_process_layer.add_child(_post_process)


## Find the parent CanvasLayer to match its layer number.
func _find_parent_canvas_layer() -> CanvasLayer:
	var node := get_parent()
	while node:
		if node is CanvasLayer:
			return node
		node = node.get_parent()
	return null


## Register a screen instance under a name.
func register_screen(screen_name: String, screen: UIScreen) -> void:
	_screens[screen_name] = screen
	screen.closed.connect(_on_screen_closed.bind(screen))
	add_child(screen)


## Open a screen by name. Returns true if opened.
func open_screen(screen_name: String) -> bool:
	var screen: UIScreen = _screens.get(screen_name)
	if screen == null:
		push_warning("UIScreenManager: Unknown screen '%s'" % screen_name)
		return false

	# Already open?
	if screen in _screen_stack:
		return false

	# If fullscreen, close existing fullscreen first
	if screen.screen_mode == UIScreen.ScreenMode.FULLSCREEN:
		for i in range(_screen_stack.size() - 1, -1, -1):
			if _screen_stack[i].screen_mode == UIScreen.ScreenMode.FULLSCREEN:
				_screen_stack[i].close()
				break

	_screen_stack.append(screen)
	screen.open()

	# Blur only for OVERLAY screens (frosted glass behind panels).
	# FULLSCREEN screens draw their own opaque background — no blur needed.
	_update_blur()
	if _post_process:
		_post_process.activate()

	# Show mouse cursor when a screen is open
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return true


## Close the topmost screen.
func close_top() -> void:
	if _screen_stack.is_empty():
		return
	_screen_stack.back().close()


## Close a specific screen by name.
func close_screen(screen_name: String) -> void:
	var screen: UIScreen = _screens.get(screen_name)
	if screen and screen in _screen_stack:
		screen.close()


## Toggle a screen open/closed.
func toggle_screen(screen_name: String) -> void:
	var screen: UIScreen = _screens.get(screen_name)
	if screen == null:
		return
	if screen in _screen_stack:
		screen.close()
	else:
		open_screen(screen_name)


## Returns true if any screen is currently open.
func is_any_screen_open() -> bool:
	return not _screen_stack.is_empty()


## Returns the topmost open screen, or null.
func get_top_screen() -> UIScreen:
	if _screen_stack.is_empty():
		return null
	return _screen_stack.back()


func _on_screen_closed(screen: UIScreen) -> void:
	_screen_stack.erase(screen)

	if _screen_stack.is_empty():
		_blur_rect.visible = false
		if _post_process:
			_post_process.deactivate()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		_update_blur()


## Show blur only when an OVERLAY screen is in the stack.
func _update_blur() -> void:
	var needs_blur := false
	for s in _screen_stack:
		if s.screen_mode == UIScreen.ScreenMode.OVERLAY:
			needs_blur = true
			break
	_blur_rect.visible = needs_blur


func _input(event: InputEvent) -> void:
	if _screen_stack.is_empty():
		return

	# Escape closes top screen (unless top screen is in key-listening mode)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		var top: UIScreen = _screen_stack.back()
		if top.get("_listening"):
			return  # Let the screen handle ESC internally
		close_top()
		get_viewport().set_input_as_handled()
		return
