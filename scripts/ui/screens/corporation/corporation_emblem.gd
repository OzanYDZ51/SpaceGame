class_name CorporationEmblem
extends UIComponent

# =============================================================================
# Corporation Emblem - Procedural geometric emblem with double ring, inner glow,
# rotating dashes, and pulsing shape
# =============================================================================

var corporation_color: Color = Color(0.15, 0.85, 1.0)
var emblem_id: int = 0
var _glow_phase: float = 0.0


func _process(delta: float) -> void:
	_glow_phase += delta * 1.5
	queue_redraw()


func _draw() -> void:
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var r: float = minf(cx, cy) - 4.0
	var center := Vector2(cx, cy)
	var glow: float = (sin(_glow_phase) + 1.0) * 0.5

	# Outer ring (faint)
	var outer_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.15 + glow * 0.1)
	_draw_circle_outline(center, r, outer_col, 1.0)

	# Rotating dashes around outer ring
	var dash_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.25 + glow * 0.15)
	var rot_offset := _glow_phase * 0.3
	for i in 12:
		var angle: float = (float(i) / 12.0) * TAU + rot_offset
		var a1: float = angle - 0.08
		var a2: float = angle + 0.08
		var p1 := center + Vector2(cos(a1), sin(a1)) * (r + 3)
		var p2 := center + Vector2(cos(a2), sin(a2)) * (r + 3)
		draw_line(p1, p2, dash_col, 1.5)

	# Middle ring (brighter, thicker)
	var mid_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.35 + glow * 0.2)
	_draw_circle_outline(center, r * 0.82, mid_col, 2.0)

	# Inner glow fill (radial approximation)
	var fill_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.04 + glow * 0.03)
	_draw_filled_circle(center, r * 0.8, fill_col)
	var fill_col2 := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.06 + glow * 0.04)
	_draw_filled_circle(center, r * 0.5, fill_col2)

	# Inner shape (pulsing alpha)
	var shape_idx: int = emblem_id % 16
	var shape_alpha: float = 0.85 + glow * 0.15
	var shape_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, shape_alpha)
	var ir: float = r * 0.5
	_draw_shape(center, ir, shape_idx, shape_col)

	# Shape outline glow
	var outline_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.1 + glow * 0.1)
	_draw_shape(center, ir * 1.1, shape_idx, outline_col)

	# Inner ring (thin, close to shape)
	var inner_col := Color(corporation_color.r, corporation_color.g, corporation_color.b, 0.2 + glow * 0.1)
	_draw_circle_outline(center, r * 0.35, inner_col, 0.8)


func _draw_shape(center: Vector2, radius: float, idx: int, col: Color) -> void:
	match idx:
		0: _draw_star(center, radius, 5, col)
		1: _draw_polygon_n(center, radius, 6, col)
		2: _draw_diamond(center, radius, col)
		3: _draw_shield(center, radius, col)
		4: _draw_crossed_swords(center, radius, col)
		5: _draw_crescent(center, radius, col)
		6: _draw_arrow_up(center, radius, col)
		7: _draw_triple_bars(center, radius, col)
		8: _draw_ring(center, radius, col)
		9: _draw_lightning(center, radius, col)
		10: _draw_atom(center, radius, col)
		11: _draw_spiral(center, radius, col)
		12: _draw_crown(center, radius, col)
		13: _draw_anchor(center, radius, col)
		14: _draw_skull(center, radius, col)
		15: _draw_wing(center, radius, col)


func _draw_star(center: Vector2, radius: float, points: int, col: Color) -> void:
	var verts := PackedVector2Array()
	for i in points * 2:
		var angle: float = (float(i) / float(points * 2)) * TAU - PI * 0.5
		var rv: float = radius if i % 2 == 0 else radius * 0.4
		verts.append(center + Vector2(cos(angle), sin(angle)) * rv)
	draw_colored_polygon(verts, col)


func _draw_polygon_n(center: Vector2, radius: float, sides: int, col: Color) -> void:
	var verts := PackedVector2Array()
	for i in sides:
		var angle: float = (float(i) / float(sides)) * TAU - PI * 0.5
		verts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(verts, col)


func _draw_diamond(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius * 0.6, 0),
		center + Vector2(0, radius), center + Vector2(-radius * 0.6, 0)]), col)


func _draw_shield(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.7, -radius * 0.8), center + Vector2(radius * 0.7, -radius * 0.8),
		center + Vector2(radius * 0.7, 0), center + Vector2(0, radius),
		center + Vector2(-radius * 0.7, 0)]), col)


func _draw_crossed_swords(center: Vector2, radius: float, col: Color) -> void:
	var w: float = 2.5
	draw_line(center + Vector2(-radius * 0.7, -radius * 0.7), center + Vector2(radius * 0.7, radius * 0.7), col, w)
	draw_line(center + Vector2(radius * 0.7, -radius * 0.7), center + Vector2(-radius * 0.7, radius * 0.7), col, w)
	draw_line(center + Vector2(-radius * 0.15, -radius * 0.4), center + Vector2(radius * 0.15, -radius * 0.1), col, w)
	draw_line(center + Vector2(-radius * 0.15, -radius * 0.1), center + Vector2(radius * 0.15, -radius * 0.4), col, w)


func _draw_crescent(center: Vector2, radius: float, col: Color) -> void:
	_draw_filled_circle(center, radius, col)
	_draw_filled_circle(center + Vector2(radius * 0.35, 0), radius * 0.8, Color(0, 0, 0, 1))


func _draw_arrow_up(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius * 0.6, radius * 0.1),
		center + Vector2(radius * 0.2, radius * 0.1), center + Vector2(radius * 0.2, radius),
		center + Vector2(-radius * 0.2, radius), center + Vector2(-radius * 0.2, radius * 0.1),
		center + Vector2(-radius * 0.6, radius * 0.1)]), col)


func _draw_triple_bars(center: Vector2, radius: float, col: Color) -> void:
	for i in 3:
		var y: float = center.y + (i - 1) * radius * 0.35
		var w: float = radius * (1.0 - float(i) * 0.15)
		draw_rect(Rect2(center.x - w, y - radius * 0.1, w * 2, radius * 0.2), col)


func _draw_ring(center: Vector2, radius: float, col: Color) -> void:
	_draw_circle_outline(center, radius, col, 3.0)
	_draw_circle_outline(center, radius * 0.5, col, 2.0)


func _draw_lightning(center: Vector2, radius: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([
		center + Vector2(radius * 0.1, -radius), center + Vector2(-radius * 0.15, -radius * 0.1),
		center + Vector2(radius * 0.2, -radius * 0.1), center + Vector2(-radius * 0.1, radius),
		center + Vector2(radius * 0.15, radius * 0.1), center + Vector2(-radius * 0.2, radius * 0.1)]), col, 2.5)


func _draw_atom(center: Vector2, radius: float, col: Color) -> void:
	_draw_filled_circle(center, radius * 0.15, col)
	for i in 3:
		_draw_ellipse_outline(center, radius, radius * 0.35, float(i) * PI / 3.0, col)


func _draw_spiral(center: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 60:
		var t: float = float(i) / 60.0
		var angle: float = t * TAU * 2.0
		pts.append(center + Vector2(cos(angle), sin(angle)) * (radius * 0.15 + radius * 0.85 * t))
	draw_polyline(pts, col, 2.0)


func _draw_crown(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.8, radius * 0.5), center + Vector2(-radius * 0.8, -radius * 0.1),
		center + Vector2(-radius * 0.4, radius * 0.2), center + Vector2(0, -radius * 0.6),
		center + Vector2(radius * 0.4, radius * 0.2), center + Vector2(radius * 0.8, -radius * 0.1),
		center + Vector2(radius * 0.8, radius * 0.5)]), col)


func _draw_anchor(center: Vector2, radius: float, col: Color) -> void:
	draw_line(center + Vector2(0, -radius * 0.7), center + Vector2(0, radius * 0.8), col, 2.5)
	draw_line(center + Vector2(-radius * 0.4, -radius * 0.3), center + Vector2(radius * 0.4, -radius * 0.3), col, 2.5)
	draw_arc(center + Vector2(0, radius * 0.3), radius * 0.5, 0, PI, 12, col, 2.5)
	_draw_circle_outline(center + Vector2(0, -radius * 0.7), radius * 0.15, col, 2.0)


func _draw_skull(center: Vector2, radius: float, col: Color) -> void:
	_draw_filled_circle(center + Vector2(0, -radius * 0.15), radius * 0.7, col)
	draw_rect(Rect2(center.x - radius * 0.45, center.y + radius * 0.2, radius * 0.9, radius * 0.4), col)
	_draw_filled_circle(center + Vector2(-radius * 0.25, -radius * 0.2), radius * 0.15, Color(0, 0, 0, 1))
	_draw_filled_circle(center + Vector2(radius * 0.25, -radius * 0.2), radius * 0.15, Color(0, 0, 0, 1))


func _draw_wing(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center, center + Vector2(-radius * 0.4, -radius * 0.8),
		center + Vector2(-radius, -radius * 0.5), center + Vector2(-radius * 0.7, radius * 0.2)]), col)
	draw_colored_polygon(PackedVector2Array([center, center + Vector2(radius * 0.4, -radius * 0.8),
		center + Vector2(radius, -radius * 0.5), center + Vector2(radius * 0.7, radius * 0.2)]), col)


func _draw_circle_outline(center: Vector2, radius: float, col: Color, width: float = 1.0) -> void:
	draw_arc(center, radius, 0, TAU, 32, col, width)


func _draw_filled_circle(center: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		pts.append(center + Vector2(cos(float(i) / 32.0 * TAU), sin(float(i) / 32.0 * TAU)) * radius)
	draw_colored_polygon(pts, col)


func _draw_ellipse_outline(center: Vector2, rx: float, ry: float, rot_angle: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var cos_r := cos(rot_angle)
	var sin_r := sin(rot_angle)
	for i in 33:
		var angle: float = float(i) / 32.0 * TAU
		var px: float = cos(angle) * rx
		var py: float = sin(angle) * ry
		pts.append(center + Vector2(px * cos_r - py * sin_r, px * sin_r + py * cos_r))
	draw_polyline(pts, col, 1.5)
