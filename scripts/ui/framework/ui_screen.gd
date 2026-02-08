class_name UIScreen
extends UIComponent

# =============================================================================
# UI Screen - Base class for game screens (fullscreen overlays, panels)
# Handles open/close transitions, title drawing, close button.
# =============================================================================

enum ScreenMode { FULLSCREEN, OVERLAY }

@export var screen_title: String = "SCREEN"
@export var screen_mode: ScreenMode = ScreenMode.FULLSCREEN

var _transition_alpha: float = 0.0
var _is_open: bool = false
var _closing: bool = false

signal opened
signal closed


func _ready() -> void:
	super._ready()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Full rect anchors
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)


## Called by UIScreenManager to open this screen.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_closing = false
	_transition_alpha = 0.0
	visible = true
	_on_opened()
	opened.emit()


## Called by UIScreenManager to close this screen.
func close() -> void:
	if not _is_open:
		return
	_closing = true


## Override in subclasses for setup when screen opens.
func _on_opened() -> void:
	pass


## Override in subclasses for cleanup when screen closes.
func _on_closed() -> void:
	pass


func _process(delta: float) -> void:
	if not visible:
		return

	if _closing:
		_transition_alpha = maxf(0.0, _transition_alpha - delta / UITheme.TRANSITION_SPEED)
		if _transition_alpha <= 0.0:
			_closing = false
			_is_open = false
			visible = false
			_on_closed()
			closed.emit()
			return
	else:
		_transition_alpha = minf(1.0, _transition_alpha + delta / UITheme.TRANSITION_SPEED)

	modulate.a = _transition_alpha
	# Only redraw during transitions (alpha changing), not when fully open
	if _transition_alpha < 1.0 or _closing:
		queue_redraw()


func _draw() -> void:
	var s := size

	# Dark background
	if screen_mode == ScreenMode.FULLSCREEN:
		draw_rect(Rect2(Vector2.ZERO, s), UITheme.BG_DARK)
	else:
		draw_rect(Rect2(Vector2.ZERO, s), UITheme.BG_MODAL)

	# Title area
	_draw_title(s)


func _draw_title(s: Vector2) -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_TITLE
	var title_y: float = UITheme.MARGIN_SCREEN + fsize
	var cx: float = s.x * 0.5

	# Title text (centered)
	draw_string(font, Vector2(0, title_y), screen_title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize, UITheme.TEXT_HEADER)

	# Decorative lines on both sides of the title
	var title_w: float = font.get_string_size(screen_title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	var line_y: float = title_y - fsize * 0.35
	var half: float = title_w * 0.5 + 20
	var line_len: float = 120.0

	draw_line(Vector2(cx - half - line_len, line_y), Vector2(cx - half, line_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(cx + half, line_y), Vector2(cx + half + line_len, line_y), UITheme.BORDER, 1.0)

	# Separator
	var sep_y: float = title_y + 10
	draw_line(Vector2(UITheme.MARGIN_SCREEN, sep_y), Vector2(s.x - UITheme.MARGIN_SCREEN, sep_y), UITheme.BORDER, 1.0)

	# Close button [X] in top-right
	var close_x: float = s.x - UITheme.MARGIN_SCREEN - 24
	var close_y: float = UITheme.MARGIN_SCREEN
	draw_string(font, Vector2(close_x, close_y + fsize * 0.6), "X", HORIZONTAL_ALIGNMENT_LEFT, 24, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
	draw_rect(Rect2(close_x - 4, close_y, 28, 24), UITheme.BORDER, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Check close button hit
		var close_x: float = size.x - UITheme.MARGIN_SCREEN - 28
		var close_y: float = UITheme.MARGIN_SCREEN
		var close_rect := Rect2(close_x, close_y, 32, 28)
		if close_rect.has_point(event.position):
			close()
			accept_event()
			return
	# Consume all input to prevent it reaching the game
	accept_event()
