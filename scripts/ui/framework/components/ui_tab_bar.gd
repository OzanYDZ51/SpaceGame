class_name UITabBar
extends UIComponent

# =============================================================================
# UI Tab Bar - Horizontal tabs with active indicator
# =============================================================================

signal tab_changed(index: int)

var tabs: Array[String] = []
var current_tab: int = 0

var _hovered_tab: int = -1


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _hovered_tab = -1; queue_redraw())


func _draw() -> void:
	if tabs.is_empty():
		return

	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_BODY
	var tab_w: float = size.x / tabs.size()

	for i in tabs.size():
		var x: float = i * tab_w
		var tab_rect := Rect2(x, 0, tab_w, size.y)
		var is_active: bool = (i == current_tab)
		var is_hover: bool = (i == _hovered_tab)

		# Background
		if is_active:
			draw_rect(tab_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12))
		elif is_hover:
			draw_rect(tab_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.05))

		# Bottom accent line for active tab
		if is_active:
			draw_line(Vector2(x + 2, size.y - 1), Vector2(x + tab_w - 2, size.y - 1), UITheme.PRIMARY, 2.0)

		# Side separators
		if i > 0:
			draw_line(Vector2(x, 4), Vector2(x, size.y - 4), UITheme.BORDER, 1.0)

		# Text
		var text_col := UITheme.TEXT if is_active else UITheme.TEXT_DIM
		var text_y: float = (size.y + fsize) * 0.5 - 1
		draw_string(font, Vector2(x, text_y), tabs[i].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, tab_w, fsize, text_col)

	# Bottom border
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), UITheme.BORDER, 1.0)


func _gui_input(event: InputEvent) -> void:
	if tabs.is_empty():
		return

	var tab_w: float = size.x / tabs.size()

	if event is InputEventMouseMotion:
		var idx: int = int(event.position.x / tab_w)
		if idx >= 0 and idx < tabs.size() and idx != _hovered_tab:
			_hovered_tab = idx
			queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx: int = int(event.position.x / tab_w)
		if idx >= 0 and idx < tabs.size() and idx != current_tab:
			current_tab = idx
			tab_changed.emit(current_tab)
			queue_redraw()
		accept_event()
