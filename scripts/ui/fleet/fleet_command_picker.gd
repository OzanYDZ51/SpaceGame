class_name FleetCommandPicker
extends Control

# =============================================================================
# Fleet Command Picker — Modal for selecting a deployment command
# =============================================================================

signal command_selected(command_id: StringName)
signal cancelled

var _buttons: Array[Control] = []
var _bg_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


func _build_layout() -> void:
	var commands := FleetCommand.get_deployable_commands()
	var btn_w: float = 240.0
	var btn_h: float = 50.0
	var spacing: float = 8.0
	var total_h: float = commands.size() * (btn_h + spacing) + 60.0  # +header
	var total_w: float = btn_w + 40.0

	var center_x: float = 640.0  # Will be repositioned by parent
	var start_y: float = 300.0

	_bg_rect = Rect2(center_x - total_w * 0.5, start_y, total_w, total_h)

	var y: float = start_y + 50.0  # After header
	for cmd in commands:
		var btn_rect := Rect2(center_x - btn_w * 0.5, y, btn_w, btn_h)
		_buttons.append(_create_cmd_button(cmd, btn_rect))
		y += btn_h + spacing


func _create_cmd_button(cmd: Dictionary, rect: Rect2) -> Control:
	# Store as simple data for draw-based rendering
	var data := Control.new()
	data.set_meta("cmd_id", cmd["id"])
	data.set_meta("display_name", cmd.get("display_name", ""))
	data.set_meta("description", cmd.get("description", ""))
	data.set_meta("rect", rect)
	return data


func reposition(center: Vector2) -> void:
	var commands := FleetCommand.get_deployable_commands()
	var btn_w: float = 240.0
	var btn_h: float = 50.0
	var spacing: float = 8.0
	var total_h: float = commands.size() * (btn_h + spacing) + 60.0
	var total_w: float = btn_w + 40.0

	_bg_rect = Rect2(center.x - total_w * 0.5, center.y - total_h * 0.5, total_w, total_h)

	var y: float = _bg_rect.position.y + 50.0
	for i in _buttons.size():
		_buttons[i].set_meta("rect", Rect2(center.x - btn_w * 0.5, y, btn_w, btn_h))
		y += btn_h + spacing
	queue_redraw()


func _draw() -> void:
	var font: Font = UITheme.get_font()

	# Background
	draw_rect(_bg_rect, UITheme.BG_DARK)
	draw_rect(_bg_rect, UITheme.BORDER, false, 1.0)

	# Header
	var header_y: float = _bg_rect.position.y + 30.0
	draw_string(font, Vector2(_bg_rect.position.x + 20, header_y), "ORDRE DE DEPLOIEMENT", HORIZONTAL_ALIGNMENT_LEFT, _bg_rect.size.x - 40, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)

	# Buttons
	for btn in _buttons:
		var rect: Rect2 = btn.get_meta("rect")
		var display_name: String = btn.get_meta("display_name")
		var description: String = btn.get_meta("description")

		draw_rect(rect, Color(0.05, 0.15, 0.25, 0.8))
		draw_rect(rect, UITheme.BORDER, false, 1.0)

		draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 22), display_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, UITheme.FONT_SIZE_BODY, UITheme.TEXT_PRIMARY)
		draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 40), description, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for btn in _buttons:
			var rect: Rect2 = btn.get_meta("rect")
			if rect.has_point(event.position):
				command_selected.emit(btn.get_meta("cmd_id"))
				accept_event()
				return
		# Click outside buttons = cancel
		cancelled.emit()
		accept_event()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		cancelled.emit()
		accept_event()
	else:
		accept_event()
