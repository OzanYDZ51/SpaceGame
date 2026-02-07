class_name UIDataTable
extends UIComponent

# =============================================================================
# UI Data Table - Sortable table with headers, virtual scroll
# =============================================================================

signal row_selected(index: int)
signal column_sort_requested(column: int)

## Column definitions: Array of { "label": String, "width_ratio": float }
var columns: Array[Dictionary] = []
## Row data: Array of Array[String] (one string per column)
var rows: Array = []
var selected_row: int = -1
var sort_column: int = -1
var sort_ascending: bool = true

var _scroll_offset: float = 0.0
var _hovered_row: int = -1
var _header_height: float = 24.0
var _row_height: float = UITheme.ROW_HEIGHT


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(func(): _hovered_row = -1; queue_redraw())


func _draw() -> void:
	var font: Font = UITheme.get_font()

	# Header row
	_draw_header(font)

	# Rows
	if rows.is_empty():
		draw_string(font, Vector2(UITheme.MARGIN_PANEL, _header_height + 30), "No data", HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
		return

	var max_scroll: float = maxf(0.0, rows.size() * _row_height - (size.y - _header_height))
	_scroll_offset = clampf(_scroll_offset, 0.0, max_scroll)

	var body_y: float = _header_height
	var first: int = int(_scroll_offset / _row_height)
	var last: int = mini(first + ceili((size.y - _header_height) / _row_height) + 1, rows.size())

	for i in range(first, last):
		var y: float = body_y + i * _row_height - _scroll_offset
		var row_rect := Rect2(0, y, size.x, _row_height)

		# Alternating bg
		if i % 2 == 1:
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))

		# Hover
		if i == _hovered_row:
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))

		# Selection
		if i == selected_row:
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12))
			draw_rect(row_rect, UITheme.BORDER_ACTIVE, false, 1.0)

		# Cell values
		var x_off: float = 0.0
		var row_data: Array = rows[i] if i < rows.size() else []
		for c in columns.size():
			var col_w: float = size.x * columns[c].get("width_ratio", 1.0 / columns.size())
			var val: String = row_data[c] if c < row_data.size() else ""
			draw_string(font, Vector2(x_off + 6, y + _row_height - 4), val, HORIZONTAL_ALIGNMENT_LEFT, col_w - 12, UITheme.FONT_SIZE_LABEL, UITheme.TEXT)
			x_off += col_w

	# Scrollbar
	if max_scroll > 0:
		var track_h: float = size.y - _header_height
		var thumb_ratio: float = track_h / (rows.size() * _row_height)
		var thumb_h: float = maxf(20.0, track_h * thumb_ratio)
		var thumb_y: float = _header_height + (_scroll_offset / max_scroll) * (track_h - thumb_h)
		draw_rect(Rect2(size.x - 4, _header_height, 4, track_h), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(size.x - 4, thumb_y, 4, thumb_h), UITheme.PRIMARY_DIM)


func _draw_header(font: Font) -> void:
	# Header background
	draw_rect(Rect2(0, 0, size.x, _header_height), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))

	var x_off: float = 0.0
	for c in columns.size():
		var col_w: float = size.x * columns[c].get("width_ratio", 1.0 / columns.size())
		var label: String = columns[c].get("label", "")

		# Sort indicator
		var suffix: String = ""
		if c == sort_column:
			suffix = " ▲" if sort_ascending else " ▼"

		draw_string(font, Vector2(x_off + 6, _header_height - 6), label.to_upper() + suffix, HORIZONTAL_ALIGNMENT_LEFT, col_w - 12, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_HEADER)

		# Column separator
		if c > 0:
			draw_line(Vector2(x_off, 4), Vector2(x_off, _header_height - 4), UITheme.BORDER, 1.0)

		x_off += col_w

	# Header bottom line
	draw_line(Vector2(0, _header_height), Vector2(size.x, _header_height), UITheme.BORDER, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - _row_height * 3)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var max_s: float = maxf(0.0, rows.size() * _row_height - (size.y - _header_height))
			_scroll_offset = minf(max_s, _scroll_offset + _row_height * 3)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.position.y < _header_height:
				# Header click → sort
				var x_off: float = 0.0
				for c in columns.size():
					var col_w: float = size.x * columns[c].get("width_ratio", 1.0 / columns.size())
					if event.position.x >= x_off and event.position.x < x_off + col_w:
						if sort_column == c:
							sort_ascending = not sort_ascending
						else:
							sort_column = c
							sort_ascending = true
						column_sort_requested.emit(c)
						queue_redraw()
						break
					x_off += col_w
			else:
				var idx: int = int((event.position.y - _header_height + _scroll_offset) / _row_height)
				if idx >= 0 and idx < rows.size():
					selected_row = idx
					row_selected.emit(idx)
					queue_redraw()
			accept_event()

	if event is InputEventMouseMotion:
		if event.position.y > _header_height:
			var idx: int = int((event.position.y - _header_height + _scroll_offset) / _row_height)
			if idx >= 0 and idx < rows.size() and idx != _hovered_row:
				_hovered_row = idx
				queue_redraw()
		elif _hovered_row != -1:
			_hovered_row = -1
			queue_redraw()
