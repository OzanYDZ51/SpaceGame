class_name UIDropdown
extends UIComponent

# =============================================================================
# UI Dropdown - Closed selector that opens a list below.
# When expanded, resizes to contain options and captures outside clicks.
# =============================================================================

signal option_selected(index: int)

var options: Array[String] = []
var selected_index: int = 0

var _expanded: bool = false
var _hovered_option: int = -1
var _option_height: float = UITheme.ROW_HEIGHT + 4
var _collapsed_height: float = 0.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _hovered_option = -1; queue_redraw())
	z_index = 10
	clip_contents = false


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_BODY
	var btn_h: float = _collapsed_height if _expanded else size.y
	var btn_rect := Rect2(Vector2.ZERO, Vector2(size.x, btn_h))

	# Main button area
	draw_rect(btn_rect, UITheme.BG_DARK)
	draw_rect(btn_rect, UITheme.BORDER_ACTIVE if _expanded else UITheme.BORDER, false, 1.0)

	# Current selection text
	var label: String = options[selected_index] if selected_index >= 0 and selected_index < options.size() else ""
	draw_string(font, Vector2(8, (btn_h + fsize) * 0.5 - 1), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, fsize, UITheme.TEXT)

	# Arrow triangle
	var ax: float = size.x - 16
	var ay: float = btn_h * 0.5
	var arrow: PackedVector2Array
	if _expanded:
		arrow = PackedVector2Array([Vector2(ax - 4, ay + 2), Vector2(ax + 4, ay + 2), Vector2(ax, ay - 3)])
	else:
		arrow = PackedVector2Array([Vector2(ax - 4, ay - 2), Vector2(ax + 4, ay - 2), Vector2(ax, ay + 3)])
	draw_colored_polygon(arrow, UITheme.TEXT_DIM)

	# Expanded options list
	if _expanded:
		var list_y: float = btn_h
		var list_h: float = options.size() * _option_height
		var list_rect := Rect2(0, list_y, size.x, list_h)

		draw_rect(list_rect, UITheme.BG_MODAL)
		draw_rect(list_rect, UITheme.BORDER, false, 1.0)

		for i in options.size():
			var oy: float = list_y + i * _option_height
			var opt_rect := Rect2(0, oy, size.x, _option_height)

			if i == _hovered_option:
				draw_rect(opt_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

			if i == selected_index:
				draw_rect(Rect2(0, oy, 3, _option_height), UITheme.PRIMARY)

			draw_string(font, Vector2(8, oy + _option_height - 5), options[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, fsize, UITheme.TEXT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _expanded:
			_expand()
		else:
			# Collapsed button area click → just close
			_collapse()
		accept_event()

	if event is InputEventMouseMotion and _expanded:
		var click_y: float = event.position.y
		if click_y > _collapsed_height:
			var idx: int = int((click_y - _collapsed_height) / _option_height)
			if idx >= 0 and idx < options.size() and idx != _hovered_option:
				_hovered_option = idx
				queue_redraw()
		elif _hovered_option != -1:
			_hovered_option = -1
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not _expanded or not is_visible_in_tree():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_pos := get_local_mouse_position()
		var full_rect := Rect2(Vector2.ZERO, size)

		if full_rect.has_point(local_pos):
			# Click is inside the expanded dropdown — check if on an option
			if local_pos.y > _collapsed_height:
				var idx: int = int((local_pos.y - _collapsed_height) / _option_height)
				if idx >= 0 and idx < options.size():
					selected_index = idx
					option_selected.emit(idx)
			_collapse()
			get_viewport().set_input_as_handled()
		else:
			# Click outside — close
			_collapse()

	elif event is InputEventMouseMotion and _expanded:
		var local_pos := get_local_mouse_position()
		if local_pos.y > _collapsed_height and local_pos.x >= 0 and local_pos.x <= size.x:
			var idx: int = int((local_pos.y - _collapsed_height) / _option_height)
			if idx >= 0 and idx < options.size() and idx != _hovered_option:
				_hovered_option = idx
				queue_redraw()
		elif _hovered_option != -1:
			_hovered_option = -1
			queue_redraw()


func _expand() -> void:
	if options.is_empty():
		return
	_collapsed_height = size.y
	_expanded = true
	size.y = _collapsed_height + options.size() * _option_height
	queue_redraw()


func _collapse() -> void:
	_expanded = false
	_hovered_option = -1
	if _collapsed_height > 0:
		size.y = _collapsed_height
	queue_redraw()
