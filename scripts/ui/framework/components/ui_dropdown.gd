class_name UIDropdown
extends UIComponent

# =============================================================================
# UI Dropdown - Closed selector that opens a list below
# =============================================================================

signal option_selected(index: int)

var options: Array[String] = []
var selected_index: int = 0

var _expanded: bool = false
var _hovered_option: int = -1
var _option_height: float = UITheme.ROW_HEIGHT + 4


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _hovered_option = -1; queue_redraw())
	# z_index for dropdown overlay
	z_index = 10


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_BODY
	var rect := Rect2(Vector2.ZERO, size)

	# Main button area
	draw_rect(rect, UITheme.BG_DARK)
	draw_rect(rect, UITheme.BORDER_ACTIVE if _expanded else UITheme.BORDER, false, 1.0)

	# Current selection text
	var label: String = options[selected_index] if selected_index >= 0 and selected_index < options.size() else ""
	draw_string(font, Vector2(8, (size.y + fsize) * 0.5 - 1), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, fsize, UITheme.TEXT)

	# Arrow triangle
	var ax: float = size.x - 16
	var ay: float = size.y * 0.5
	var arrow: PackedVector2Array
	if _expanded:
		arrow = PackedVector2Array([Vector2(ax - 4, ay + 2), Vector2(ax + 4, ay + 2), Vector2(ax, ay - 3)])
	else:
		arrow = PackedVector2Array([Vector2(ax - 4, ay - 2), Vector2(ax + 4, ay - 2), Vector2(ax, ay + 3)])
	draw_colored_polygon(arrow, UITheme.TEXT_DIM)

	# Expanded options list
	if _expanded:
		var list_y: float = size.y
		var list_h: float = options.size() * _option_height
		var list_rect := Rect2(0, list_y, size.x, list_h)

		draw_rect(list_rect, UITheme.BG_MODAL)
		draw_rect(list_rect, UITheme.BORDER, false, 1.0)

		for i in options.size():
			var oy: float = list_y + i * _option_height
			var opt_rect := Rect2(0, oy, size.x, _option_height)

			if i == _hovered_option:
				draw_rect(opt_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.1))

			if i == selected_index:
				draw_rect(Rect2(0, oy, 3, _option_height), UITheme.PRIMARY)

			draw_string(font, Vector2(8, oy + _option_height - 5), options[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, fsize, UITheme.TEXT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _expanded:
			_expanded = true
			# Temporarily grow size to contain dropdown
			custom_minimum_size.y = size.y + options.size() * _option_height
			queue_redraw()
		else:
			# Check if clicking on an option
			var click_y: float = event.position.y
			if click_y > size.y:
				var idx: int = int((click_y - size.y) / _option_height)
				if idx >= 0 and idx < options.size():
					selected_index = idx
					option_selected.emit(idx)
			_collapse()
		accept_event()

	if event is InputEventMouseMotion and _expanded:
		var click_y: float = event.position.y
		if click_y > size.y:
			var idx: int = int((click_y - size.y) / _option_height)
			if idx >= 0 and idx < options.size() and idx != _hovered_option:
				_hovered_option = idx
				queue_redraw()


func _collapse() -> void:
	_expanded = false
	_hovered_option = -1
	custom_minimum_size.y = 0
	queue_redraw()
