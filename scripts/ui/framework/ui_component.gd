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
	Locale.language_changed.connect(_on_language_changed)


## Called when language changes. Override for extra logic beyond redraw.
func _on_language_changed(_lang: String) -> void:
	queue_redraw()


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


# =============================================================================
# CARD / GRID HELPERS — shared by all card-grid-based views
# =============================================================================

## Draw a generic item card with icon area, name, subtitle, price, and states.
## icon_callable: Callable(center: Vector2, color: Color) — draws the icon.
## Returns nothing. The caller manages hover/flash on top.
func draw_item_card(rect: Rect2, icon_callable: Callable, item_name: String,
		subtitle: String, price_text: String, is_affordable: bool,
		is_locked: bool, is_hovered: bool, accent_color: Color) -> void:
	var font: Font = UITheme.get_font()
	# Background
	var bg: Color
	if is_locked:
		bg = Color(0.01, 0.015, 0.03, 0.5) if not is_hovered else Color(0.015, 0.025, 0.05, 0.62)
	else:
		bg = Color(0.015, 0.04, 0.08, 0.82) if not is_hovered else Color(0.025, 0.06, 0.12, 0.9)
	draw_rect(rect, bg)

	# Border
	var bcol: Color
	if is_locked:
		bcol = UITheme.BORDER_HOVER if is_hovered else UITheme.BORDER
	else:
		bcol = UITheme.BORDER_ACTIVE if is_hovered else Color(accent_color.r, accent_color.g, accent_color.b, 0.4)
	draw_rect(rect, bcol, false, 1.0)

	# Top glow
	if not is_locked:
		var ga: float = 0.25 if is_hovered else 0.1
		draw_line(Vector2(rect.position.x + 1, rect.position.y),
			Vector2(rect.end.x - 1, rect.position.y),
			Color(accent_color.r, accent_color.g, accent_color.b, ga), 2.0)

	# Mini corners
	draw_corners(rect, 6.0, bcol)

	# Icon (centered, upper area)
	var icon_cy: float = rect.position.y + 30.0
	if icon_callable.is_valid():
		var icol: Color = accent_color if not is_locked else Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.4)
		icon_callable.call(Vector2(rect.position.x + rect.size.x * 0.5, icon_cy), icol)

	# Name (centered)
	var name_col: Color = UITheme.TEXT if not is_locked else UITheme.TEXT_DIM
	var name_y: float = rect.position.y + 56.0
	draw_string(font, Vector2(rect.position.x + 4, name_y),
		item_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_SMALL, name_col)

	# Subtitle (centered, smaller)
	if subtitle != "":
		draw_string(font, Vector2(rect.position.x + 4, name_y + 16),
			subtitle, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Price (bottom)
	if price_text != "":
		var pcol: Color = PlayerEconomy.CREDITS_COLOR if is_affordable else UITheme.DANGER
		draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 8),
			price_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_TINY, pcol)

	# Lock overlay
	if is_locked:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.25))


## Draw a rarity badge as N stars at a position.
func draw_rarity_badge(pos: Vector2, rarity_level: int, col: Color) -> void:
	var star_count: int = clampi(rarity_level, 1, 5)
	var total_w: float = star_count * 8.0
	var sx: float = pos.x - total_w * 0.5 + 4.0
	for i in star_count:
		var cx: float = sx + i * 8.0
		var pts: PackedVector2Array = []
		for k in 5:
			var a_outer: float = -PI * 0.5 + TAU * float(k) / 5.0
			pts.append(Vector2(cx + cos(a_outer) * 3.5, pos.y + sin(a_outer) * 3.5))
			var a_inner: float = a_outer + TAU / 10.0
			pts.append(Vector2(cx + cos(a_inner) * 1.5, pos.y + sin(a_inner) * 1.5))
		draw_colored_polygon(pts, col)


## Draw a mini stat bar inline. Returns nothing.
func draw_stat_mini_bar(rect: Rect2, ratio: float, col: Color, label: String, value_text: String) -> void:
	var font: Font = UITheme.get_font()
	# Bar background
	draw_rect(rect, Color(0.0, 0.05, 0.1, 0.5))
	# Filled portion
	var fw: float = rect.size.x * clampf(ratio, 0.0, 1.0)
	if fw > 0.0:
		draw_rect(Rect2(rect.position, Vector2(fw, rect.size.y)), Color(col.r, col.g, col.b, 0.5))
	# Border
	draw_rect(rect, Color(col.r, col.g, col.b, 0.3), false, 1.0)
	# Label (left)
	if label != "":
		draw_string(font, Vector2(rect.position.x + 3, rect.end.y - 2),
			label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.5, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	# Value (right)
	if value_text != "":
		draw_string(font, Vector2(rect.position.x, rect.end.y - 2),
			value_text, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 3, UITheme.FONT_SIZE_TINY, UITheme.TEXT)


## Draw a price tag with colored background.
func draw_price_tag(pos: Vector2, price_text: String, affordable: bool, tag_width: float) -> void:
	var font: Font = UITheme.get_font()
	var h: float = 18.0
	var r: Rect2 = Rect2(pos.x, pos.y, tag_width, h)
	var col: Color = PlayerEconomy.CREDITS_COLOR if affordable else UITheme.DANGER
	draw_rect(r, Color(col.r, col.g, col.b, 0.12))
	draw_rect(r, Color(col.r, col.g, col.b, 0.3), false, 1.0)
	draw_string(font, Vector2(pos.x, pos.y + h - 3), price_text,
		HORIZONTAL_ALIGNMENT_CENTER, tag_width, UITheme.FONT_SIZE_TINY, col)


## Draw a procedural ore crystal icon.
func draw_ore_crystal(center: Vector2, radius: float, col: Color) -> void:
	# Diamond/crystal shape with inner facets
	var pts: PackedVector2Array = [
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.6, -radius * 0.2),
		center + Vector2(radius * 0.5, radius * 0.7),
		center + Vector2(0, radius),
		center + Vector2(-radius * 0.5, radius * 0.7),
		center + Vector2(-radius * 0.6, -radius * 0.2),
	]
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.3))
	pts.append(pts[0])  # close the loop
	draw_polyline(pts, col, 1.5)
	# Inner facet lines
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius),
		Color(col.r, col.g, col.b, 0.3), 1.0)
	draw_line(center + Vector2(-radius * 0.6, -radius * 0.2),
		center + Vector2(radius * 0.5, radius * 0.7),
		Color(col.r, col.g, col.b, 0.2), 1.0)


## Draw a size badge ([S], [M], [L]) — colored by size.
func draw_size_badge(pos: Vector2, size_str: String) -> void:
	var font: Font = UITheme.get_font()
	var badge_col: Color
	match size_str:
		"S": badge_col = UITheme.PRIMARY
		"M": badge_col = UITheme.WARNING
		"L": badge_col = Color(0.7, 0.5, 1.0)
		_: badge_col = UITheme.TEXT_DIM
	var bw: float = 22.0
	var bh: float = 14.0
	draw_rect(Rect2(pos.x, pos.y, bw, bh), Color(badge_col.r, badge_col.g, badge_col.b, 0.2))
	draw_rect(Rect2(pos.x, pos.y, bw, bh), Color(badge_col.r, badge_col.g, badge_col.b, 0.4), false, 1.0)
	draw_string(font, Vector2(pos.x, pos.y + bh - 1),
		size_str, HORIZONTAL_ALIGNMENT_CENTER, bw, UITheme.FONT_SIZE_TINY, badge_col)


## Compute a grid layout of cards within a given area. Returns Array[Rect2].
static func compute_card_grid(area: Rect2, card_w: float, card_h: float, gap: float, count: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0:
		return rects
	var cols: int = maxi(1, int((area.size.x + gap) / (card_w + gap)))
	for i in count:
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = area.position.x + col * (card_w + gap)
		var y: float = area.position.y + row * (card_h + gap)
		rects.append(Rect2(x, y, card_w, card_h))
	return rects


## Hit-test a point against an array of Rect2. Returns index or -1.
static func hit_test_rects(rects: Array[Rect2], point: Vector2) -> int:
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1
