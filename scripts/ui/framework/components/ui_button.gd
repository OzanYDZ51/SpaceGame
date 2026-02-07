class_name UIButton
extends UIComponent

# =============================================================================
# UI Button - Holographic button with accent bar, hover glow, click flash
# =============================================================================

signal pressed

@export var text: String = "BUTTON"
@export var accent_color: Color = UITheme.PRIMARY

var _hovered: bool = false
var _pressed_flash: float = 0.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_BODY

	# Background
	var bg := UITheme.BG
	if not enabled:
		bg = Color(UITheme.BG.r, UITheme.BG.g, UITheme.BG.b, 0.2)
	elif _hovered:
		bg = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08)
	draw_rect(rect, bg)

	# Click flash overlay
	if _pressed_flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, _pressed_flash * 0.25))

	# Border
	var border_col := UITheme.BORDER
	if _hovered and enabled:
		border_col = UITheme.BORDER_HOVER
	draw_rect(rect, border_col, false, 1.0)

	# Left accent bar (3px)
	var accent := accent_color if enabled else UITheme.PRIMARY_DIM
	draw_rect(Rect2(0, 2, 3, size.y - 4), accent)

	# Hover glow on left bar
	if _hovered and enabled:
		draw_rect(Rect2(0, 0, 6, size.y), Color(accent.r, accent.g, accent.b, 0.15))

	# Text
	var text_col := UITheme.TEXT if enabled else UITheme.TEXT_DIM
	var text_y: float = (size.y + fsize) * 0.5 - 1
	draw_string(font, Vector2(12, text_y), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, fsize, text_col)


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed_flash = 1.0
		pressed.emit()
		accept_event()


func _process(delta: float) -> void:
	if _pressed_flash > 0.0:
		_pressed_flash = maxf(0.0, _pressed_flash - delta / 0.1)
		queue_redraw()
