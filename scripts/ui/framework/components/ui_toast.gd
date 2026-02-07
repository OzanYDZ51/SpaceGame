class_name UIToast
extends UIComponent

# =============================================================================
# UI Toast - Notification that slides in from top-right, auto-dismisses
# =============================================================================

enum ToastType { INFO, SUCCESS, WARNING, ERROR }

var message: String = ""
var toast_type: ToastType = ToastType.INFO
var lifetime: float = 4.0

var _elapsed: float = 0.0
var _slide_progress: float = 0.0  # 0 = off-screen, 1 = fully visible

const TOAST_WIDTH := 320.0
const TOAST_HEIGHT := 44.0
const SLIDE_SPEED := 6.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(TOAST_WIDTH, TOAST_HEIGHT)


func _process(delta: float) -> void:
	_elapsed += delta

	# Slide in
	if _elapsed < 0.3:
		_slide_progress = minf(1.0, _slide_progress + delta * SLIDE_SPEED)
	# Slide out before expire
	elif _elapsed > lifetime - 0.3:
		_slide_progress = maxf(0.0, _slide_progress - delta * SLIDE_SPEED)

	# Expire
	if _elapsed >= lifetime:
		queue_free()
		return

	modulate.a = _slide_progress
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_BODY

	# Background
	draw_rect(rect, UITheme.BG_MODAL)

	# Left accent bar colored by type
	var accent := _type_color()
	draw_rect(Rect2(0, 0, 3, size.y), accent)

	# Border
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Type icon (simple character)
	var icon: String = _type_icon()
	draw_string(font, Vector2(10, (size.y + fsize) * 0.5), icon, HORIZONTAL_ALIGNMENT_LEFT, 16, fsize, accent)

	# Message
	draw_string(font, Vector2(28, (size.y + fsize) * 0.5), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, fsize, UITheme.TEXT)


func _type_color() -> Color:
	match toast_type:
		ToastType.SUCCESS: return UITheme.ACCENT
		ToastType.WARNING: return UITheme.WARNING
		ToastType.ERROR: return UITheme.DANGER
		_: return UITheme.PRIMARY


func _type_icon() -> String:
	match toast_type:
		ToastType.SUCCESS: return "+"
		ToastType.WARNING: return "!"
		ToastType.ERROR: return "X"
		_: return "i"
