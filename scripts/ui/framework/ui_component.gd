class_name UIComponent
extends Control

# =============================================================================
# UI Component - Base class for all holographic UI components
# Provides shared draw helpers for the unified design system.
# =============================================================================

var enabled: bool = true

## Set to true to enable the hologram panel shader on this component.
## Best suited for large panel backgrounds. Small widgets (buttons, bars) should leave this off.
var use_panel_shader: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if use_panel_shader:
		material = UIShaderCache.get_panel_material()


## Draw a panel background with border, top glow, gradient overlay, corners, and scanline.
func draw_panel_bg(rect: Rect2, bg_color: Color = UITheme.BG) -> void:
	# Background fill
	draw_rect(rect, bg_color)

	# Gradient overlay — darker at bottom for depth
	var grad_top := Color(1.0, 1.0, 1.0, 0.02)
	var grad_bot := Color(0.0, 0.0, 0.0, 0.06)
	var grad_h := rect.size.y
	if grad_h > 4.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, grad_h * 0.5)), grad_top)
		draw_rect(Rect2(rect.position + Vector2(0, grad_h * 0.5), Vector2(rect.size.x, grad_h * 0.5)), grad_bot)

	# Border
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Top glow line (bright, thicker for premium look)
	var glow_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.35)
	draw_line(Vector2(rect.position.x + 1, rect.position.y), Vector2(rect.end.x - 1, rect.position.y), glow_col, 2.0)

	# Inner glow line (subtle 2nd line below top edge)
	var inner_glow := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08)
	draw_line(Vector2(rect.position.x + 2, rect.position.y + 2), Vector2(rect.end.x - 2, rect.position.y + 2), inner_glow, 1.0)

	# Corner accents
	draw_corners(rect, UITheme.CORNER_LENGTH, UITheme.CORNER)

	# Scanline
	draw_scanline(rect)


## Draw 8 L-shaped accent lines at the 4 corners of a rect.
func draw_corners(rect: Rect2, length: float, col: Color) -> void:
	var x1: float = rect.position.x
	var y1: float = rect.position.y
	var x2: float = rect.end.x
	var y2: float = rect.end.y
	var l: float = minf(length, minf(rect.size.x * 0.3, rect.size.y * 0.3))

	# Top-left
	draw_line(Vector2(x1, y1), Vector2(x1 + l, y1), col, 1.5)
	draw_line(Vector2(x1, y1), Vector2(x1, y1 + l), col, 1.5)
	# Top-right
	draw_line(Vector2(x2, y1), Vector2(x2 - l, y1), col, 1.5)
	draw_line(Vector2(x2, y1), Vector2(x2, y1 + l), col, 1.5)
	# Bottom-left
	draw_line(Vector2(x1, y2), Vector2(x1 + l, y2), col, 1.5)
	draw_line(Vector2(x1, y2), Vector2(x1, y2 - l), col, 1.5)
	# Bottom-right
	draw_line(Vector2(x2, y2), Vector2(x2 - l, y2), col, 1.5)
	draw_line(Vector2(x2, y2), Vector2(x2, y2 - l), col, 1.5)


## Draw a faint horizontal scanline that scrolls down through the rect.
func draw_scanline(rect: Rect2) -> void:
	var local_y: float = fmod(UITheme.scanline_y, rect.size.y)
	var sy: float = rect.position.y + local_y
	draw_line(Vector2(rect.position.x, sy), Vector2(rect.end.x, sy), UITheme.SCANLINE, 1.0)


## Draw a section header: accent bar + text + horizontal line. Returns the Y after the header.
func draw_section_header(x: float, y: float, w: float, text: String) -> float:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_LABEL

	# Accent bar (small vertical bar on the left)
	draw_rect(Rect2(x, y + 2, 3, fsize), UITheme.PRIMARY)

	# Header text
	draw_string(font, Vector2(x + 8, y + fsize), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 8, fsize, UITheme.TEXT_HEADER)

	# Horizontal line under the text
	var line_y: float = y + fsize + 4
	draw_line(Vector2(x, line_y), Vector2(x + w, line_y), UITheme.BORDER, 1.0)

	return line_y + UITheme.MARGIN_SECTION


## Draw a status bar with optional label and percentage text.
func draw_status_bar(rect: Rect2, ratio: float, col: Color, label_text: String = "", show_pct: bool = false) -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_TINY

	# Background
	draw_rect(rect, UITheme.BG_DARK)

	# Filled portion
	if ratio > 0.0:
		var fw: float = rect.size.x * clampf(ratio, 0.0, 1.0)
		draw_rect(Rect2(rect.position, Vector2(fw, rect.size.y)), col)
		# Bright edge at the fill end
		draw_rect(Rect2(rect.position + Vector2(fw - 2, 0), Vector2(2, rect.size.y)), Color(col.r, col.g, col.b, 1.0))
		# Glow halo at leading edge
		if fw > 4.0:
			var halo_col := Color(col.r, col.g, col.b, 0.3)
			draw_rect(Rect2(rect.position + Vector2(fw - 4, 0), Vector2(3, rect.size.y)), halo_col)

	# Center tick
	var cx: float = rect.position.x + rect.size.x * 0.5
	draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.end.y), Color(0.0, 0.05, 0.1, 0.5), 1.0)

	# Bottom edge
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), UITheme.BORDER, 1.0)

	# Label (left)
	if label_text != "":
		draw_string(font, Vector2(rect.position.x + 3, rect.position.y + rect.size.y - 2), label_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.5, fsize, UITheme.TEXT_DIM)

	# Percentage (right)
	if show_pct:
		var pct_str: String = "%d%%" % int(ratio * 100)
		draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y - 2), pct_str, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 3, fsize, UITheme.TEXT)


## Draw a key: value line. Returns the Y for the next line.
func draw_key_value(x: float, y: float, w: float, key: String, value: String) -> float:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_LABEL
	var text_y: float = y + fsize

	# Key (left-aligned, dim)
	draw_string(font, Vector2(x, text_y), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5, fsize, UITheme.LABEL_KEY)

	# Value (right-aligned, bright)
	draw_string(font, Vector2(x, text_y), value, HORIZONTAL_ALIGNMENT_RIGHT, w, fsize, UITheme.LABEL_VALUE)

	return y + UITheme.ROW_HEIGHT
