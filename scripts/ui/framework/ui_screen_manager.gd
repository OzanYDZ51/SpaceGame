class_name UIScreenManager
extends Control

# =============================================================================
# UI Screen Manager - Screen stack, transitions, input routing
# Added to the UI CanvasLayer by GameManager.
# Rules: One FULLSCREEN at a time. OVERLAYs stack on top.
# =============================================================================

var _screens: Dictionary = {}  # name -> UIScreen
var _screen_stack: Array[UIScreen] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full rect
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)


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

	# Restore mouse capture when all screens are closed
	if _screen_stack.is_empty():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if _screen_stack.is_empty():
		return

	# Escape closes top screen
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		close_top()
		get_viewport().set_input_as_handled()
		return
