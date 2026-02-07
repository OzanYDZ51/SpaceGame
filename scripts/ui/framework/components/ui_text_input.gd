class_name UITextInput
extends UIComponent

# =============================================================================
# UI Text Input - LineEdit wrapper with holographic border and glow on focus
# =============================================================================

signal text_submitted(text: String)
signal text_changed(text: String)

@export var placeholder: String = "Type here..."

var _line_edit: LineEdit = null
var _focused: bool = false


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = placeholder
	_line_edit.flat = true
	_line_edit.anchor_left = 0.0
	_line_edit.anchor_top = 0.0
	_line_edit.anchor_right = 1.0
	_line_edit.anchor_bottom = 1.0
	_line_edit.offset_left = 8.0
	_line_edit.offset_top = 2.0
	_line_edit.offset_right = -8.0
	_line_edit.offset_bottom = -2.0
	_line_edit.add_theme_color_override("font_color", UITheme.TEXT)
	_line_edit.add_theme_color_override("font_placeholder_color", UITheme.TEXT_DIM)
	_line_edit.add_theme_color_override("caret_color", UITheme.PRIMARY)
	_line_edit.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_line_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_line_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_line_edit.text_submitted.connect(func(t): text_submitted.emit(t))
	_line_edit.text_changed.connect(func(t): text_changed.emit(t))
	_line_edit.focus_entered.connect(func(): _focused = true; queue_redraw())
	_line_edit.focus_exited.connect(func(): _focused = false; queue_redraw())

	add_child(_line_edit)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	# Background
	draw_rect(rect, UITheme.BG_DARK)

	# Border (brighter on focus)
	var border := UITheme.BORDER_ACTIVE if _focused else UITheme.BORDER
	draw_rect(rect, border, false, 1.0)

	# Focus glow
	if _focused:
		var glow := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15)
		draw_rect(Rect2(-1, -1, size.x + 2, size.y + 2), glow, false, 2.0)


## Get the current text.
func get_text() -> String:
	return _line_edit.text if _line_edit else ""


## Set the text.
func set_text(t: String) -> void:
	if _line_edit:
		_line_edit.text = t
