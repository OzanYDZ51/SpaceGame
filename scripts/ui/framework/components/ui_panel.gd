class_name UIPanel
extends UIComponent

# =============================================================================
# UI Panel - Bordered holographic panel with optional title
# =============================================================================

@export var title: String = ""
@export var show_scanline: bool = true
@export var bg_color: Color = UITheme.BG


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	# Background
	draw_rect(rect, bg_color)

	# Border + top glow
	draw_rect(rect, UITheme.BORDER, false, 1.0)
	var glow := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.25)
	draw_line(Vector2(1, 0), Vector2(size.x - 1, 0), glow, 1.5)

	# Corners
	draw_corners(rect, UITheme.CORNER_LENGTH, UITheme.CORNER)

	# Scanline
	if show_scanline:
		draw_scanline(rect)

	# Title
	if title != "":
		var font: Font = UITheme.get_font()
		var fsize: int = UITheme.FONT_SIZE_HEADER
		var title_y: float = UITheme.MARGIN_PANEL + fsize

		# Title background bar
		draw_rect(Rect2(0, 0, size.x, title_y + 6), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))

		# Title text
		draw_string(font, Vector2(UITheme.MARGIN_PANEL, title_y), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - UITheme.MARGIN_PANEL * 2, fsize, UITheme.TEXT_HEADER)

		# Separator line
		var sep_y: float = title_y + 8
		draw_line(Vector2(0, sep_y), Vector2(size.x, sep_y), UITheme.BORDER, 1.0)


func _process(_delta: float) -> void:
	if show_scanline:
		queue_redraw()
