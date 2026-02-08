class_name UIScrollList
extends UIComponent

# =============================================================================
# UI Scroll List - Virtual-scrolled list with selection and hover
# Uses a callback for custom row rendering.
# =============================================================================

signal item_selected(index: int)
signal item_double_clicked(index: int)

var items: Array = []
var row_height: float = UITheme.ROW_HEIGHT
var selected_index: int = -1

## Callback: func(ctrl: Control, index: int, rect: Rect2, item: Variant) -> void
var item_draw_callback: Callable = Callable()

var _scroll_offset: float = 0.0
var _hovered_index: int = -1
var _max_scroll: float = 0.0
var _last_click_index: int = -1
var _last_click_time: float = 0.0
const DOUBLE_CLICK_TIME := 0.4


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(func(): _hovered_index = -1; queue_redraw())


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_LABEL

	if items.is_empty():
		draw_string(font, Vector2(UITheme.MARGIN_PANEL, size.y * 0.5), "No items", HORIZONTAL_ALIGNMENT_CENTER, size.x, fsize, UITheme.TEXT_DIM)
		return

	_max_scroll = maxf(0.0, items.size() * row_height - size.y)
	_scroll_offset = clampf(_scroll_offset, 0.0, _max_scroll)

	var first_visible: int = int(_scroll_offset / row_height)
	var last_visible: int = mini(first_visible + ceili(size.y / row_height) + 1, items.size())

	for i in range(first_visible, last_visible):
		var y: float = i * row_height - _scroll_offset
		var row_rect := Rect2(0, y, size.x - 6, row_height)

		# Alternating background
		if i % 2 == 1:
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))

		# Hover
		if i == _hovered_index:
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))

		# Selection (pulsing border)
		if i == selected_index:
			var pulse: float = UITheme.get_pulse(1.0)
			var sel_alpha: float = lerpf(0.08, 0.15, pulse)
			draw_rect(row_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_alpha))
			draw_rect(row_rect, UITheme.BORDER_ACTIVE, false, 1.0)

		# Custom draw callback or default text
		if item_draw_callback.is_valid():
			item_draw_callback.call(self, i, row_rect, items[i])
		else:
			draw_string(font, Vector2(8, y + row_height - 4), str(items[i]), HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 16, fsize, UITheme.TEXT)

	# Scrollbar
	if _max_scroll > 0:
		_draw_scrollbar()


func _draw_scrollbar() -> void:
	var track_x: float = size.x - 4
	var track_h: float = size.y
	var thumb_ratio: float = size.y / (items.size() * row_height)
	var thumb_h: float = maxf(20.0, track_h * thumb_ratio)
	var thumb_y: float = (_scroll_offset / _max_scroll) * (track_h - thumb_h)

	# Track
	draw_rect(Rect2(track_x, 0, 4, track_h), Color(UITheme.BG_DARK.r, UITheme.BG_DARK.g, UITheme.BG_DARK.b, 0.5))
	# Thumb
	draw_rect(Rect2(track_x, thumb_y, 4, thumb_h), UITheme.PRIMARY_DIM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - row_height * 3)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_offset = minf(_max_scroll, _scroll_offset + row_height * 3)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var idx: int = int((event.position.y + _scroll_offset) / row_height)
			if idx >= 0 and idx < items.size():
				var now := Time.get_ticks_msec() / 1000.0
				if idx == _last_click_index and (now - _last_click_time) < DOUBLE_CLICK_TIME:
					# Double-click
					selected_index = idx
					item_double_clicked.emit(idx)
					_last_click_index = -1
				else:
					# Single click
					selected_index = idx
					item_selected.emit(idx)
					_last_click_index = idx
					_last_click_time = now
				queue_redraw()
			accept_event()

	if event is InputEventMouseMotion:
		var idx: int = int((event.position.y + _scroll_offset) / row_height)
		if idx >= 0 and idx < items.size():
			if idx != _hovered_index:
				_hovered_index = idx
				queue_redraw()
		elif _hovered_index != -1:
			_hovered_index = -1
			queue_redraw()
