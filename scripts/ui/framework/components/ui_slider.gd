class_name UISlider
extends UIComponent

# =============================================================================
# UI Slider - Horizontal slider with track, fill, and draggable thumb
# =============================================================================

signal value_changed(new_value: float)

var value: float = 1.0
var label_text: String = ""
var show_percentage: bool = true

var _dragging: bool = false
var _hovered: bool = false


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_LABEL

	# Label (left) + percentage (right)
	var text_h: float = fsize + 4
	if label_text != "":
		draw_string(font, Vector2(0, fsize), label_text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, fsize, UITheme.TEXT_DIM)
	if show_percentage:
		draw_string(font, Vector2(0, fsize), "%d%%" % int(value * 100), HORIZONTAL_ALIGNMENT_RIGHT, size.x, fsize, UITheme.TEXT)

	# Track
	var track_y: float = text_h + 2
	var track_h: float = size.y - track_y
	var track_rect := Rect2(0, track_y, size.x, track_h)

	# Track background
	draw_rect(track_rect, UITheme.BG_DARK)

	# Filled portion
	var fw: float = size.x * clampf(value, 0.0, 1.0)
	if fw > 0:
		draw_rect(Rect2(0, track_y, fw, track_h), UITheme.PRIMARY)
		# Bright edge
		if fw > 2:
			draw_rect(Rect2(fw - 2, track_y, 2, track_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 1.0))
		# Glow halo
		if fw > 4:
			var halo := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3)
			draw_rect(Rect2(fw - 4, track_y, 3, track_h), halo)

	# Thumb
	var thumb_w: float = 8.0
	var thumb_x: float = clampf(fw - thumb_w * 0.5, 0, size.x - thumb_w)
	var thumb_col := UITheme.TEXT if (_hovered or _dragging) else UITheme.TEXT_DIM
	draw_rect(Rect2(thumb_x, track_y - 2, thumb_w, track_h + 4), thumb_col)

	# Track border
	var border_col := UITheme.BORDER_HOVER if (_hovered or _dragging) else UITheme.BORDER
	draw_rect(track_rect, border_col, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_update_value_from_mouse(event.position.x)
		else:
			_dragging = false
			queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_update_value_from_mouse(event.position.x)
		accept_event()


func _update_value_from_mouse(mx: float) -> void:
	var new_val: float = clampf(mx / maxf(size.x, 1.0), 0.0, 1.0)
	if absf(new_val - value) > 0.001:
		value = new_val
		value_changed.emit(value)
		queue_redraw()
