class_name HudDrawHelpers
extends RefCounted

# =============================================================================
# Shared drawing helpers for HUD components
# Static-style functions — call as HudDrawHelpers.draw_diamond(ctrl, ...)
# =============================================================================


static func draw_diamond(ctrl: Control, pos: Vector2, sz: float, col: Color) -> void:
	ctrl.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -sz), pos + Vector2(sz, 0),
		pos + Vector2(0, sz), pos + Vector2(-sz, 0),
	]), col)


static func draw_section_header(ctrl: Control, font: Font, x: float, y: float, w: float, text: String) -> float:
	ctrl.draw_rect(Rect2(x, y - 11, 3, 14), UITheme.PRIMARY)
	ctrl.draw_string(font, Vector2(x + 9, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.HEADER)
	var tw =font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
	var lx =x + 9 + tw + 8
	if lx < x + w:
		ctrl.draw_line(Vector2(lx, y - 4), Vector2(x + w, y - 4), UITheme.PRIMARY_DIM, 1.0)
	return y + 18


static func draw_panel_bg(ctrl: Control, scan_line_y: float, alpha: float = 1.0) -> void:
	if alpha < 0.001:
		return
	var bg =UITheme.BG
	ctrl.draw_rect(Rect2(Vector2.ZERO, ctrl.size), Color(bg.r, bg.g, bg.b, bg.a * alpha))
	var pd =UITheme.PRIMARY_DIM
	ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), Color(pd.r, pd.g, pd.b, pd.a * alpha), 1.5)
	var p =UITheme.PRIMARY
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 14), Color(p.r, p.g, p.b, p.a * alpha), 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x, 14), Color(p.r, p.g, p.b, p.a * alpha), 1.5)
	var sl =UITheme.SCANLINE
	var sy: float = fmod(scan_line_y, ctrl.size.y)
	ctrl.draw_line(Vector2(0, sy), Vector2(ctrl.size.x, sy), Color(sl.r, sl.g, sl.b, sl.a * alpha), 1.0)


static func draw_bar(ctrl: Control, pos: Vector2, width: float, ratio: float, col: Color) -> void:
	var h =8.0
	ctrl.draw_rect(Rect2(pos, Vector2(width, h)), UITheme.BG_DARK)
	if ratio > 0.0:
		var fw: float = width * clamp(ratio, 0.0, 1.0)
		ctrl.draw_rect(Rect2(pos, Vector2(fw, h)), col)
		ctrl.draw_rect(Rect2(pos + Vector2(fw - 2, 0), Vector2(2, h)), Color(col.r, col.g, col.b, 1.0))
	# Center tick + bottom edge
	ctrl.draw_line(Vector2(pos.x + width * 0.5, pos.y), Vector2(pos.x + width * 0.5, pos.y + h), Color(0.0, 0.05, 0.1, 0.5), 1.0)
	ctrl.draw_line(Vector2(pos.x, pos.y + h), Vector2(pos.x + width, pos.y + h), UITheme.BORDER, 1.0)


static func format_nav_distance(dist_m: float) -> String:
	if dist_m < 1000.0:
		return "%.0f m" % dist_m
	elif dist_m < 100_000.0:
		return "%.1f km" % (dist_m / 1000.0)
	elif dist_m < 1_000_000.0:
		return "%.0f km" % (dist_m / 1000.0)
	else:
		return "%.1f Mm" % (dist_m / 1_000_000.0)


static func get_mode_text(ship) -> String:
	if ship == null: return "---"
	match ship.speed_mode:
		Constants.SpeedMode.BOOST: return "TURBO"
		Constants.SpeedMode.CRUISE: return "CROISIÈRE"
	return "NORMAL"


static func get_mode_color(ship) -> Color:
	if ship == null: return UITheme.PRIMARY
	match ship.speed_mode:
		Constants.SpeedMode.BOOST: return UITheme.BOOST
		Constants.SpeedMode.CRUISE: return UITheme.CRUISE
	return UITheme.PRIMARY


static func make_ctrl(al: float, at: float, ar: float, ab: float, ol: float, ot: float, or_: float, ob: float) -> Control:
	var c =Control.new()
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = or_; c.offset_bottom = ob
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
