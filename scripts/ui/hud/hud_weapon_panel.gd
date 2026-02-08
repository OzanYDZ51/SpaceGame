class_name HudWeaponPanel
extends Control

# =============================================================================
# HUD Weapon Panel — Ship silhouette with hardpoints + weapon list (BSG style)
# =============================================================================

var ship: ShipController = null
var weapon_manager: WeaponManager = null
var energy_system: EnergySystem = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _sil_verts: PackedVector3Array = PackedVector3Array()
var _silhouette_ship: Node3D = null
var _cached_hull: PackedVector2Array = PackedVector2Array()
var _cached_hp_screen: Array[Vector2] = []
var _cached_hp_label_dirs: Array[Vector2] = []
var _cached_wp_size: Vector2 = Vector2.ZERO

var _weapon_panel: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_weapon_panel = HudDrawHelpers.make_ctrl(0.5, 1.0, 0.5, 1.0, 140, -195, 390, -10)
	_weapon_panel.draw.connect(_draw_weapon_panel.bind(_weapon_panel))
	add_child(_weapon_panel)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_weapon_panel.visible = not is_cockpit


func redraw_slow() -> void:
	_weapon_panel.queue_redraw()


func invalidate_cache() -> void:
	_silhouette_ship = null
	_cached_wp_size = Vector2.ZERO


# =============================================================================
# SILHOUETTE + CACHE
# =============================================================================
func _rebuild_silhouette() -> void:
	_silhouette_ship = ship
	_sil_verts = PackedVector3Array()
	_cached_hull = PackedVector2Array()
	_cached_hp_screen = []
	_cached_hp_label_dirs = []
	_cached_wp_size = Vector2.ZERO
	if ship == null:
		return
	var model := ship.get_node_or_null("ShipModel") as ShipModel
	if model:
		_sil_verts = model.get_silhouette_points()


func _rebuild_weapon_panel_cache(s: Vector2) -> void:
	_cached_wp_size = s
	_cached_hull = PackedVector2Array()
	_cached_hp_screen = []
	_cached_hp_label_dirs = []

	if weapon_manager == null or ship == null or ship.ship_data == null:
		return
	var hp_count := weapon_manager.get_hardpoint_count()
	if hp_count == 0:
		return

	var sil_area_w := 140.0
	var header_h := 20.0
	var footer_h := 22.0
	var a_l := 10.0
	var a_t := header_h + 2.0
	var a_r := sil_area_w - 6.0
	var a_b := s.y - footer_h - 2.0
	var a_w := a_r - a_l
	var a_h := a_b - a_t
	var a_cx := (a_l + a_r) * 0.5
	var a_cy := (a_t + a_b) * 0.5
	const Y_FOLD := 0.3

	var sil_2d := PackedVector2Array()
	for v in _sil_verts:
		sil_2d.append(Vector2(v.x, -v.z + v.y * Y_FOLD))

	var hp_2d: Array[Vector2] = []
	for i in hp_count:
		var p: Vector3 = weapon_manager.hardpoints[i].position
		hp_2d.append(Vector2(p.x, -p.z + p.y * Y_FOLD))

	if sil_2d.size() >= 3:
		_cached_hull = Geometry2D.convex_hull(sil_2d)

	var sil_min := Vector2(INF, INF)
	var sil_max := Vector2(-INF, -INF)
	if _cached_hull.size() >= 3:
		for pt in _cached_hull:
			sil_min = Vector2(minf(sil_min.x, pt.x), minf(sil_min.y, pt.y))
			sil_max = Vector2(maxf(sil_max.x, pt.x), maxf(sil_max.y, pt.y))
	for pt in hp_2d:
		sil_min = Vector2(minf(sil_min.x, pt.x - 5.0), minf(sil_min.y, pt.y - 5.0))
		sil_max = Vector2(maxf(sil_max.x, pt.x + 5.0), maxf(sil_max.y, pt.y + 5.0))

	var sil_w := maxf(sil_max.x - sil_min.x, 1.0)
	var sil_h := maxf(sil_max.y - sil_min.y, 1.0)
	var sil_cx := (sil_min.x + sil_max.x) * 0.5
	var sil_cy := (sil_min.y + sil_max.y) * 0.5
	var sc := minf(a_w / sil_w, a_h / sil_h) * 0.82

	var hp_count_actual := mini(hp_count, hp_2d.size())
	for i in hp_count_actual:
		_cached_hp_screen.append(Vector2(
			a_cx + (hp_2d[i].x - sil_cx) * sc,
			a_cy + (hp_2d[i].y - sil_cy) * sc
		))

	# Separate overlapping hardpoints
	var min_dist := 16.0
	for _iter in 6:
		var moved := false
		for i in _cached_hp_screen.size():
			for j in range(i + 1, _cached_hp_screen.size()):
				var diff := _cached_hp_screen[i] - _cached_hp_screen[j]
				var dist := diff.length()
				if dist < min_dist:
					moved = true
					if dist < 0.1:
						diff = Vector2(1.0, 0.0) if (i % 2 == 0) else Vector2(-1.0, 0.0)
						dist = 0.1
					var push := diff.normalized() * (min_dist - dist) * 0.55
					_cached_hp_screen[i] += push
					_cached_hp_screen[j] -= push
		if not moved:
			break

	for i in _cached_hp_screen.size():
		_cached_hp_screen[i].x = clampf(_cached_hp_screen[i].x, a_l + 8.0, a_r - 8.0)
		_cached_hp_screen[i].y = clampf(_cached_hp_screen[i].y, a_t + 8.0, a_b - 8.0)

	# Label directions
	for i in _cached_hp_screen.size():
		var away := Vector2.ZERO
		for j in _cached_hp_screen.size():
			if i == j:
				continue
			var diff := _cached_hp_screen[i] - _cached_hp_screen[j]
			var d := diff.length()
			if d < 30.0 and d > 0.01:
				away += diff.normalized() / d
		if away.length() < 0.01:
			away = Vector2(-1, -1)
		_cached_hp_label_dirs.append(away.normalized())


# =============================================================================
# TYPE HELPERS
# =============================================================================
func _get_weapon_type_color(wtype: int) -> Color:
	match wtype:
		0: return Color(0.0, 0.9, 1.0)   # LASER
		1: return Color(0.2, 1.0, 0.3)   # PLASMA
		2: return Color(1.0, 0.6, 0.1)   # MISSILE
		3: return Color(1.0, 1.0, 0.2)   # RAILGUN
		4: return Color(1.0, 0.2, 0.2)   # MINE
	return UITheme.PRIMARY


func _get_weapon_type_abbr(wtype: int) -> String:
	match wtype:
		0: return "LASE"
		1: return "PLAS"
		2: return "MISS"
		3: return "RAIL"
		4: return "MINE"
	return "----"


# =============================================================================
# DRAW WEAPON PANEL
# =============================================================================
func _draw_weapon_panel(ctrl: Control) -> void:
	var font := ThemeDB.fallback_font
	var s := ctrl.size

	ctrl.draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.02, 0.06, 0.45))
	ctrl.draw_line(Vector2(0, 0), Vector2(s.x, 0), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 12), UITheme.PRIMARY, 1.5)
	ctrl.draw_line(Vector2(s.x, 0), Vector2(s.x, 12), UITheme.PRIMARY, 1.5)
	var sly: float = fmod(scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), UITheme.SCANLINE, 1.0)

	if weapon_manager == null or ship == null or ship.ship_data == null:
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "---", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 11, UITheme.TEXT_DIM)
		return

	var hp_count := weapon_manager.get_hardpoint_count()
	if hp_count == 0:
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "AUCUNE ARME", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 10, UITheme.TEXT_DIM)
		return

	if ship != _silhouette_ship:
		_rebuild_silhouette()

	if _cached_wp_size != s or _cached_hp_screen.is_empty():
		_rebuild_weapon_panel_cache(s)

	# Header
	ctrl.draw_string(font, Vector2(8, 13), "ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.HEADER)
	var hdr_w := font.get_string_size("ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	ctrl.draw_line(Vector2(8 + hdr_w + 6, 7), Vector2(s.x - 8, 7), UITheme.PRIMARY_DIM, 1.0)
	var class_str: String = ship.ship_data.ship_class
	if class_str == "":
		class_str = "---"
	var csw := font.get_string_size(class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	ctrl.draw_string(font, Vector2(s.x - csw - 8, 13), class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT_DIM)

	var sil_area_w := 140.0
	var list_x := sil_area_w + 4.0
	var list_w := s.x - list_x - 6.0
	var header_h := 20.0
	var footer_h := 22.0

	ctrl.draw_line(Vector2(sil_area_w, header_h), Vector2(sil_area_w, s.y - footer_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), 1.0)

	# Silhouette
	var a_l := 10.0
	var a_t := header_h + 2.0
	var a_r := sil_area_w - 6.0
	var a_b := s.y - footer_h - 2.0
	var a_w := a_r - a_l
	var a_h := a_b - a_t
	var a_cx := (a_l + a_r) * 0.5
	var a_cy := (a_t + a_b) * 0.5

	if _cached_hull.size() >= 3:
		var sil_min := Vector2(INF, INF)
		var sil_max := Vector2(-INF, -INF)
		for pt in _cached_hull:
			sil_min = Vector2(minf(sil_min.x, pt.x), minf(sil_min.y, pt.y))
			sil_max = Vector2(maxf(sil_max.x, pt.x), maxf(sil_max.y, pt.y))
		var s_w := maxf(sil_max.x - sil_min.x, 1.0)
		var s_h := maxf(sil_max.y - sil_min.y, 1.0)
		var s_cx := (sil_min.x + sil_max.x) * 0.5
		var s_cy := (sil_min.y + sil_max.y) * 0.5
		var sc := minf(a_w / s_w, a_h / s_h) * 0.82
		var screen_poly := PackedVector2Array()
		for pt in _cached_hull:
			screen_poly.append(Vector2(
				a_cx + (pt.x - s_cx) * sc,
				a_cy + (pt.y - s_cy) * sc
			))
		ctrl.draw_colored_polygon(screen_poly, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.04))
		var closed := PackedVector2Array(screen_poly)
		closed.append(screen_poly[0])
		ctrl.draw_polyline(closed, UITheme.PRIMARY_DIM, 1.0)
		var top_y := a_cy + (sil_min.y - s_cy) * sc
		var bot_y := a_cy + (sil_max.y - s_cy) * sc
		ctrl.draw_line(Vector2(a_cx, top_y), Vector2(a_cx, bot_y), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.1), 1.0)
		HudDrawHelpers.draw_diamond(ctrl, Vector2(a_cx, top_y), 2.5, UITheme.PRIMARY_DIM)
	else:
		var tri := PackedVector2Array([
			Vector2(a_cx, a_cy - a_h * 0.4),
			Vector2(a_cx + a_w * 0.3, a_cy + a_h * 0.3),
			Vector2(a_cx - a_w * 0.3, a_cy + a_h * 0.3),
		])
		ctrl.draw_colored_polygon(tri, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.04))
		tri.append(tri[0])
		ctrl.draw_polyline(tri, UITheme.PRIMARY_DIM, 1.0)

	for i in _cached_hp_screen.size():
		var status := weapon_manager.get_hardpoint_status(i)
		var label_dir := _cached_hp_label_dirs[i] if i < _cached_hp_label_dirs.size() else Vector2(-1, -1)
		_draw_hardpoint_marker(ctrl, font, _cached_hp_screen[i], i, status, label_dir)

	_draw_weapon_list(ctrl, font, list_x, header_h + 4.0, list_w, hp_count)
	_draw_weapon_footer(ctrl, font, s, footer_h)


# =============================================================================
# HARDPOINT MARKER
# =============================================================================
func _draw_hardpoint_marker(ctrl: Control, font: Font, pos: Vector2, index: int, status: Dictionary, label_dir: Vector2 = Vector2(-1, -1)) -> void:
	if status.is_empty():
		return
	var is_on: bool = status["enabled"]
	var wname: String = str(status["weapon_name"])
	var ssize: String = status["slot_size"]
	var cd: float = float(status["cooldown_ratio"])
	var wtype: int = int(status.get("weapon_type", -1))
	var armed: bool = wname != ""

	var r := 6.0
	match ssize:
		"M": r = 8.0
		"L": r = 10.0

	var type_col: Color = _get_weapon_type_color(wtype) if armed else UITheme.PRIMARY
	var is_missile: bool = wtype == 2

	if is_on and armed:
		var ga := sin(pulse_t * 2.0 + float(index) * 1.5) * 0.12 + 0.2
		ctrl.draw_arc(pos, r + 3, 0, TAU, 16, Color(type_col.r, type_col.g, type_col.b, ga), 2.0, true)

		if is_missile:
			var d := r * 0.85
			var diamond := PackedVector2Array([
				pos + Vector2(0, -d), pos + Vector2(d, 0),
				pos + Vector2(0, d), pos + Vector2(-d, 0),
			])
			ctrl.draw_colored_polygon(diamond, Color(type_col.r, type_col.g, type_col.b, 0.15))
			diamond.append(diamond[0])
			if cd > 0.01:
				ctrl.draw_polyline(diamond, Color(type_col.r, type_col.g, type_col.b, 0.3), 1.5)
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r + 1, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_polyline(diamond, type_col, 2.0)
		else:
			ctrl.draw_circle(pos, r, Color(type_col.r, type_col.g, type_col.b, 0.12))
			if cd > 0.01:
				ctrl.draw_arc(pos, r, 0, TAU, 20, Color(type_col.r, type_col.g, type_col.b, 0.25), 1.5, true)
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_arc(pos, r, 0, TAU, 20, type_col, 2.0, true)
	elif is_on:
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.25), 1.0, true)
	else:
		ctrl.draw_circle(pos, r, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.08))
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.3), 1.5, true)
		var xsz := r * 0.5
		ctrl.draw_line(pos + Vector2(-xsz, -xsz), pos + Vector2(xsz, xsz), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)
		ctrl.draw_line(pos + Vector2(xsz, -xsz), pos + Vector2(-xsz, xsz), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)

	var num_col: Color = type_col if (is_on and armed) else (UITheme.PRIMARY if is_on else Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.4))
	var num_str := str(index + 1)
	var num_w := font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var label_offset := label_dir * (r + 6.0)
	var num_pos := pos + label_offset + Vector2(-num_w * 0.5, 3.0)
	ctrl.draw_string(font, num_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, num_col)


# =============================================================================
# WEAPON LIST
# =============================================================================
func _draw_weapon_list(ctrl: Control, font: Font, x: float, y: float, w: float, hp_count: int) -> void:
	var line_h := 16.0
	var grp_colors: Array[Color] = [UITheme.PRIMARY, Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 1.0)]

	for i in hp_count:
		var status := weapon_manager.get_hardpoint_status(i)
		if status.is_empty():
			continue
		var ly := y + i * line_h
		var is_on: bool = status["enabled"]
		var wname: String = str(status["weapon_name"])
		var wtype: int = int(status.get("weapon_type", -1))
		var cd: float = float(status["cooldown_ratio"])
		var fire_grp: int = int(status.get("fire_group", -1))
		var armed: bool = wname != ""

		var num_col: Color
		if is_on and armed:
			num_col = _get_weapon_type_color(wtype)
		elif is_on:
			num_col = UITheme.TEXT_DIM
		else:
			num_col = Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5)
		ctrl.draw_string(font, Vector2(x, ly + 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, num_col)

		if not armed:
			ctrl.draw_string(font, Vector2(x + 12, ly + 10), "---", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.3))
			continue

		var abbr := _get_weapon_type_abbr(wtype)
		var name_col: Color
		if not is_on:
			name_col = Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.4)
		else:
			name_col = Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, 0.8)
		ctrl.draw_string(font, Vector2(x + 12, ly + 10), abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, name_col)

		var short_name := wname.get_slice(" ", 0).left(4)
		ctrl.draw_string(font, Vector2(x + 44, ly + 10), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.6 if is_on else 0.3))

		if not is_on:
			var strike_y := ly + 6.0
			ctrl.draw_line(Vector2(x + 10, strike_y), Vector2(x + w - 18, strike_y), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.35), 1.0)
			continue

		var ind_x := x + w - 18.0
		if cd > 0.01:
			var bar_w := 14.0
			var bar_h := 4.0
			var bar_y := ly + 5.0
			ctrl.draw_rect(Rect2(ind_x, bar_y, bar_w, bar_h), Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.15))
			var fill := (1.0 - cd) * bar_w
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_rect(Rect2(ind_x, bar_y, fill, bar_h), Color(type_c.r, type_c.g, type_c.b, 0.7))
		else:
			var dot_pos := Vector2(ind_x + 7.0, ly + 7.0)
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_circle(dot_pos, 2.5, type_c)

		if fire_grp >= 0 and fire_grp < grp_colors.size():
			var grp_x := x + w - 32.0
			var grp_y := ly + 7.0
			ctrl.draw_circle(Vector2(grp_x, grp_y), 2.0, Color(grp_colors[fire_grp].r, grp_colors[fire_grp].g, grp_colors[fire_grp].b, 0.6))


# =============================================================================
# WEAPON FOOTER
# =============================================================================
func _draw_weapon_footer(ctrl: Control, font: Font, s: Vector2, footer_h: float) -> void:
	var fy := s.y - footer_h
	ctrl.draw_line(Vector2(6, fy), Vector2(s.x - 6, fy), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), 1.0)

	var grp_colors: Array[Color] = [UITheme.PRIMARY, Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 1.0)]
	var gx := 8.0
	for g in weapon_manager.weapon_groups.size():
		if weapon_manager.weapon_groups[g].is_empty():
			continue
		var label := "G" + str(g + 1)
		var gc: Color = grp_colors[g] if g < grp_colors.size() else UITheme.TEXT_DIM
		ctrl.draw_string(font, Vector2(gx, fy + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, gc)
		gx += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 2
		for hp_idx in weapon_manager.weapon_groups[g]:
			var st := weapon_manager.get_hardpoint_status(hp_idx)
			var dot_c: Color = gc if st.get("enabled", false) else Color(gc.r, gc.g, gc.b, 0.2)
			ctrl.draw_circle(Vector2(gx + 2, fy + 10), 2.5, dot_c)
			gx += 7.0
		gx += 6.0

	if energy_system:
		var bar_x := s.x - 90.0
		var bar_y := fy + 5.0
		var bar_w := 58.0
		var bar_h := 6.0
		var ratio := energy_system.get_energy_ratio()
		ctrl.draw_string(font, Vector2(bar_x - 26, fy + 14), "WEP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT_DIM)
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.15))
		var fill_w := ratio * bar_w
		var bar_col := UITheme.PRIMARY if ratio > 0.25 else UITheme.WARNING
		ctrl.draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), Color(bar_col.r, bar_col.g, bar_col.b, 0.7))
		var pct_str := str(int(ratio * 100.0)) + "%"
		ctrl.draw_string(font, Vector2(bar_x + bar_w + 4, fy + 14), pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UITheme.TEXT_DIM)
