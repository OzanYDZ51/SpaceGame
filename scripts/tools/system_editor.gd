@tool
extends Control

# =============================================================================
# System Editor — 2D visual placement tool for StarSystemData .tres files
# Open scenes/tools/system_editor.tscn → press F6 to run
#
# Controls:
#   Left-click ........... Select element
#   Drag ................. Move selected element
#   Scroll wheel ......... Zoom (around cursor)
#   Right-click drag ..... Pan view
#   A / Left arrow ....... Previous system
#   D / Right arrow ...... Next system
#   S .................... Save current system
#   F .................... Fit view (reset zoom/pan)
#   Escape ............... Deselect
# =============================================================================

# --- Colors (holographic theme, matching in-game maps) ---
const C_BG := Color(0.04, 0.04, 0.08)
const C_GRID := Color(0.08, 0.2, 0.35, 0.12)
const C_ORBIT := Color(0.1, 0.3, 0.5, 0.15)
const C_STAR := Color(1.0, 0.9, 0.4)
const C_BELT := Color(0.7, 0.55, 0.35, 0.3)
const C_GATE := Color(0.15, 0.6, 1.0)
const C_STATION := Color(0.1, 0.9, 0.6)
const C_SEL := Color(0.2, 0.9, 1.0, 0.8)
const C_TEXT := Color(0.65, 0.75, 0.85)
const C_HEADER := Color(0.5, 0.85, 1.0)
const C_DIM := Color(0.4, 0.5, 0.6, 0.6)
const C_BAR := Color(0.06, 0.06, 0.12, 0.92)
const C_SAVE_OK := Color(0.2, 0.8, 0.4)
const C_SAVE_DIRTY := Color(1.0, 0.7, 0.2)

const PLANET_COL := {
	0: Color(0.65, 0.45, 0.3),   # ROCKY
	1: Color(1.0, 0.35, 0.15),   # LAVA
	2: Color(0.2, 0.45, 0.85),   # OCEAN
	3: Color(0.85, 0.7, 0.3),    # GAS_GIANT
	4: Color(0.5, 0.75, 1.0),    # ICE
}
const PLANET_R := { 0: 6.0, 1: 5.0, 2: 7.0, 3: 11.0, 4: 6.0 }

# --- Layout ---
const HIT_RADIUS := 14.0
const ZOOM_MIN := 0.02
const ZOOM_MAX := 100.0
const ZOOM_STEP := 1.15
const TOP_BAR_H := 42.0
const INFO_W := 230.0
const NAV_CLICK_W := 90.0

# --- System data ---
var _data: StarSystemData = null
var _system_id: int = 0
var _system_count: int = 0

# --- View transform ---
var _offset := Vector2.ZERO       # Pan in world units
var _ppu: float = 0.000005        # Pixels per world unit (base)
var _zoom: float = 1.0

# --- Selection & interaction ---
enum El { NONE, STAR, PLANET, STATION, BELT, GATE }
var _sel: El = El.NONE
var _sel_idx: int = -1
var _dragging := false
var _drag_world_offset := Vector2.ZERO  # Offset: element center - cursor at drag start
var _panning := false
var _pan_mouse := Vector2.ZERO
var _pan_offset := Vector2.ZERO
var _dirty := false
var _save_flash: float = 0.0      # Brief green flash after save
var _editor_font: Font = null


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = FOCUS_ALL
	_editor_font = load("res://assets/fonts/Rajdhani-Medium.ttf")
	if not Engine.is_editor_hint():
		_scan_systems()
		if _system_count > 0:
			_load_system(0)
		grab_focus()


func _process(delta: float) -> void:
	if _save_flash > 0.0:
		_save_flash -= delta
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# =============================================================================
# System navigation
# =============================================================================

func _scan_systems() -> void:
	_system_count = 0
	while ResourceLoader.exists("res://data/systems/system_%d.tres" % _system_count):
		_system_count += 1


func _load_system(id: int) -> void:
	if _system_count <= 0:
		return
	id = posmod(id, _system_count)
	_save_if_dirty()
	var path := "res://data/systems/system_%d.tres" % id
	_data = load(path) as StarSystemData
	_system_id = id
	_sel = El.NONE
	_sel_idx = -1
	_dirty = false
	_fit_view()
	queue_redraw()


func _save_if_dirty() -> void:
	if not _dirty or _data == null:
		return
	ResourceSaver.save(_data, "res://data/systems/system_%d.tres" % _system_id)
	_dirty = false


func _save_current() -> void:
	if _data == null:
		return
	ResourceSaver.save(_data, "res://data/systems/system_%d.tres" % _system_id)
	_dirty = false
	_save_flash = 1.5
	queue_redraw()


# =============================================================================
# View transforms
# =============================================================================

func _fit_view() -> void:
	if _data == null or size.x < 1.0:
		return
	var max_r := 1.0
	for p in _data.planets:
		max_r = maxf(max_r, p.orbital_radius)
	for s in _data.stations:
		max_r = maxf(max_r, s.orbital_radius)
	for b in _data.asteroid_belts:
		max_r = maxf(max_r, b.orbital_radius + b.width * 0.5)
	for g in _data.jump_gates:
		max_r = maxf(max_r, sqrt(g.pos_x * g.pos_x + g.pos_z * g.pos_z))
	var view_h := size.y - TOP_BAR_H
	_ppu = minf(size.x, view_h) * 0.38 / max_r
	_zoom = 1.0
	_offset = Vector2.ZERO


func _center_y() -> float:
	return TOP_BAR_H + (size.y - TOP_BAR_H) * 0.5


func _w2s(wx: float, wz: float) -> Vector2:
	return Vector2(
		size.x * 0.5 + (wx - _offset.x) * _ppu * _zoom,
		_center_y() + (wz - _offset.y) * _ppu * _zoom,
	)


func _s2w(sx: float, sy: float) -> Vector2:
	return Vector2(
		(sx - size.x * 0.5) / (_ppu * _zoom) + _offset.x,
		(sy - _center_y()) / (_ppu * _zoom) + _offset.y,
	)


func _orbit_screen(radius: float, angle: float) -> Vector2:
	return _w2s(cos(angle) * radius, sin(angle) * radius)


# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)

	if _data == null:
		draw_string(_editor_font, Vector2(size.x * 0.5 - 100, size.y * 0.5), "No system data loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		return

	var f := _editor_font
	var sc := _w2s(0, 0)

	_draw_grid(f, sc)
	_draw_belts(f, sc)
	_draw_orbit_rings(sc)
	_draw_star(f, sc)
	_draw_planets(f)
	_draw_stations(f)
	_draw_gates(f)
	_draw_top_bar(f)
	if _sel != El.NONE:
		_draw_info_panel(f)
	_draw_help(f)


func _draw_grid(f: Font, sc: Vector2) -> void:
	var max_r_px := maxf(size.x, size.y) * 0.6
	var target_world := 80.0 / (_ppu * _zoom)
	var e: float = floor(log(target_world) / log(10.0))
	var base: float = pow(10.0, e)
	var spacing: float = base
	if target_world > base * 5.0:
		spacing = base * 5.0
	elif target_world > base * 2.0:
		spacing = base * 2.0
	var r_w := spacing
	while r_w * _ppu * _zoom < max_r_px:
		var r_px := r_w * _ppu * _zoom
		draw_arc(sc, r_px, 0, TAU, 48, C_GRID, 1.0)
		draw_string(f, sc + Vector2(r_px + 3, -3), _fmt_dist(r_w), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
		r_w += spacing


func _draw_belts(f: Font, sc: Vector2) -> void:
	for i in _data.asteroid_belts.size():
		var b: AsteroidBeltData = _data.asteroid_belts[i]
		var r_px := b.orbital_radius * _ppu * _zoom
		var w_px := maxf(b.width * _ppu * _zoom, 4.0)
		var is_sel := _sel == El.BELT and _sel_idx == i
		var col := C_SEL if is_sel else C_BELT
		draw_arc(sc, r_px, 0, TAU, 64, col, w_px)
		var lp := sc + Vector2(0, -(r_px + w_px * 0.5 + 6))
		draw_string(f, lp + Vector2(-40, 0), _short(b.belt_name), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, col.lightened(0.4))


func _draw_orbit_rings(sc: Vector2) -> void:
	for p in _data.planets:
		draw_arc(sc, p.orbital_radius * _ppu * _zoom, 0, TAU, 64, C_ORBIT, 1.0)
	for s in _data.stations:
		draw_arc(sc, s.orbital_radius * _ppu * _zoom, 0, TAU, 48, C_ORBIT.darkened(0.2), 1.0)


func _draw_star(f: Font, sc: Vector2) -> void:
	var is_sel := _sel == El.STAR
	if is_sel:
		draw_circle(sc, 17.0, C_SEL)
	draw_circle(sc, 12.0, C_STAR)
	draw_string(f, sc + Vector2(-50, -20), _data.star_name, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, C_STAR)
	draw_string(f, sc + Vector2(-15, 24), _data.star_spectral_class, HORIZONTAL_ALIGNMENT_CENTER, 30, 13, C_DIM)


func _draw_planets(f: Font) -> void:
	for i in _data.planets.size():
		var p: PlanetData = _data.planets[i]
		var pos := _orbit_screen(p.orbital_radius, p.orbital_angle)
		var r: float = PLANET_R.get(p.type, 6.0)
		var col: Color = PLANET_COL.get(p.type, Color.GRAY)
		var is_sel := _sel == El.PLANET and _sel_idx == i
		if is_sel:
			draw_circle(pos, r + 4.0, C_SEL)
		draw_circle(pos, r, col)
		if p.has_rings:
			draw_arc(pos, r + 4.0, -0.3, PI + 0.3, 12, col.lightened(0.3), 1.5)
		draw_string(f, pos + Vector2(-20, r + 14), _short(p.planet_name), HORIZONTAL_ALIGNMENT_CENTER, 40, 13, C_TEXT)


func _draw_stations(f: Font) -> void:
	for i in _data.stations.size():
		var s: StationData = _data.stations[i]
		var pos := _orbit_screen(s.orbital_radius, s.orbital_angle)
		var is_sel := _sel == El.STATION and _sel_idx == i
		if is_sel:
			draw_rect(Rect2(pos - Vector2(9, 9), Vector2(18, 18)), C_SEL, false, 2.0)
		draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), C_STATION)
		draw_string(f, pos + Vector2(-40, 19), s.station_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, C_STATION)


func _draw_gates(f: Font) -> void:
	for i in _data.jump_gates.size():
		var g: JumpGateData = _data.jump_gates[i]
		var pos := _w2s(g.pos_x, g.pos_z)
		var is_sel := _sel == El.GATE and _sel_idx == i
		var r := 8.0
		var pts := PackedVector2Array([
			pos + Vector2(0, -r), pos + Vector2(r, 0),
			pos + Vector2(0, r), pos + Vector2(-r, 0),
		])
		if is_sel:
			var big := PackedVector2Array([
				pos + Vector2(0, -r - 3), pos + Vector2(r + 3, 0),
				pos + Vector2(0, r + 3), pos + Vector2(-r - 3, 0),
			])
			draw_colored_polygon(big, C_SEL)
		draw_colored_polygon(pts, C_GATE)
		draw_string(f, pos + Vector2(-40, r + 14), g.gate_name.replace("Gate ", ""), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, C_GATE)


func _draw_top_bar(f: Font) -> void:
	draw_rect(Rect2(0, 0, size.x, TOP_BAR_H), C_BAR)
	draw_line(Vector2(0, TOP_BAR_H), Vector2(size.x, TOP_BAR_H), C_ORBIT.lightened(0.2), 1.0)

	# System name + index
	var title := "%s  [%d / %d]" % [_data.system_name, _system_id + 1, _system_count]
	draw_string(f, Vector2(size.x * 0.5 - 140, 27), title, HORIZONTAL_ALIGNMENT_CENTER, 280, 14, C_HEADER)

	# Nav arrows
	draw_string(f, Vector2(20, 27), "<  A", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
	draw_string(f, Vector2(size.x - 60, 27), "D  >", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)

	# Save indicator
	if _save_flash > 0.0:
		var alpha := minf(_save_flash, 1.0)
		draw_string(f, Vector2(size.x * 0.5 - 15, TOP_BAR_H - 3), "SAVED", HORIZONTAL_ALIGNMENT_CENTER, 50, 13, Color(C_SAVE_OK, alpha))
	elif _dirty:
		draw_circle(Vector2(size.x * 0.5 + 145, 22), 4, C_SAVE_DIRTY)


func _draw_info_panel(f: Font) -> void:
	var px := size.x - INFO_W - 12.0
	var py := TOP_BAR_H + 12.0
	var lines: Array[Array] = []

	match _sel:
		El.STAR:
			lines.append(["NOM", _data.star_name])
			lines.append(["CLASSE", _data.star_spectral_class])
			lines.append(["TEMP", "%d K" % int(_data.star_temperature)])
			lines.append(["RAYON", _fmt_dist(_data.star_radius)])
		El.PLANET:
			var p: PlanetData = _data.planets[_sel_idx]
			lines.append(["NOM", p.planet_name])
			lines.append(["TYPE", _planet_str(p.type)])
			lines.append(["ORBITE", _fmt_dist(p.orbital_radius)])
			lines.append(["ANGLE", "%.1f deg" % rad_to_deg(p.orbital_angle)])
			lines.append(["RAYON", _fmt_dist(p.radius)])
			if p.has_rings:
				lines.append(["ANNEAUX", "Oui"])
		El.STATION:
			var s: StationData = _data.stations[_sel_idx]
			lines.append(["NOM", s.station_name])
			lines.append(["SERVICE", _station_str(s.station_type)])
			lines.append(["ORBITE", _fmt_dist(s.orbital_radius)])
			lines.append(["ANGLE", "%.1f deg" % rad_to_deg(s.orbital_angle)])
		El.BELT:
			var b: AsteroidBeltData = _data.asteroid_belts[_sel_idx]
			lines.append(["NOM", b.belt_name])
			lines.append(["ORBITE", _fmt_dist(b.orbital_radius)])
			lines.append(["LARGEUR", _fmt_dist(b.width)])
			lines.append(["ZONE", b.zone.to_upper()])
			lines.append(["RESSOURCE", String(b.dominant_resource).to_upper()])
			if b.secondary_resource != &"":
				lines.append(["SECONDAIRE", String(b.secondary_resource).to_upper()])
			lines.append(["ASTEROIDES", str(b.asteroid_count)])
		El.GATE:
			var g: JumpGateData = _data.jump_gates[_sel_idx]
			lines.append(["NOM", g.gate_name])
			lines.append(["CIBLE", g.target_system_name])
			lines.append(["POS X", _fmt_dist(g.pos_x)])
			lines.append(["POS Z", _fmt_dist(g.pos_z)])

	var ph := 30.0 + lines.size() * 18.0
	draw_rect(Rect2(px, py, INFO_W, ph), C_BAR)
	draw_rect(Rect2(px, py, INFO_W, ph), C_ORBIT, false, 1.0)

	var y := py + 20.0
	for row in lines:
		draw_string(f, Vector2(px + 10, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, 80, 13, C_DIM)
		draw_string(f, Vector2(px + 85, y), row[1], HORIZONTAL_ALIGNMENT_LEFT, int(INFO_W - 95), 13, C_TEXT)
		y += 18.0


func _draw_help(f: Font) -> void:
	var y := size.y - 50.0
	draw_string(f, Vector2(12, y), "Clic: selection   Drag: deplacer   Molette: zoom   Clic droit: pan", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
	draw_string(f, Vector2(12, y + 14), "A/D: systeme precedent/suivant   S: sauvegarder   F: recentrer   Echap: deselection", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)


# =============================================================================
# Input
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if _data == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					# Top bar navigation clicks
					if mb.position.y < TOP_BAR_H:
						if mb.position.x < NAV_CLICK_W:
							_load_system(_system_id - 1)
						elif mb.position.x > size.x - NAV_CLICK_W:
							_load_system(_system_id + 1)
						accept_event()
						return
					# Selection + drag start
					var hit := _hit_test(mb.position)
					_sel = hit[0]
					_sel_idx = hit[1]
					if _sel != El.NONE and _sel != El.STAR:
						_dragging = true
						# Store offset so element doesn't snap to cursor
						var cursor_world := _s2w(mb.position.x, mb.position.y)
						var elem_world := _get_elem_world_pos(_sel, _sel_idx)
						_drag_world_offset = elem_world - cursor_world
					else:
						_dragging = false
					accept_event()
					queue_redraw()
				else:
					_dragging = false
					accept_event()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_panning = true
					_pan_mouse = mb.position
					_pan_offset = _offset
				else:
					_panning = false
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mb.position, ZOOM_STEP)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, 1.0 / ZOOM_STEP)
				accept_event()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and _sel != El.NONE:
			_apply_drag(mm.position)
			accept_event()
			queue_redraw()
		elif _panning:
			_offset = _pan_offset - (mm.position - _pan_mouse) / (_ppu * _zoom)
			accept_event()
			queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_A, KEY_LEFT:
			_load_system(_system_id - 1)
		KEY_D, KEY_RIGHT:
			_load_system(_system_id + 1)
		KEY_S:
			_save_current()
		KEY_F:
			_fit_view()
			queue_redraw()
		KEY_ESCAPE:
			_sel = El.NONE
			_sel_idx = -1
			queue_redraw()


func _zoom_at(pos: Vector2, factor: float) -> void:
	var wb := _s2w(pos.x, pos.y)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var wa := _s2w(pos.x, pos.y)
	_offset += wb - wa
	queue_redraw()


# =============================================================================
# Hit testing
# =============================================================================

func _hit_test(pos: Vector2) -> Array:
	# Reverse draw order: gates > stations > planets > belts > star
	for i in range(_data.jump_gates.size() - 1, -1, -1):
		var g: JumpGateData = _data.jump_gates[i]
		if _w2s(g.pos_x, g.pos_z).distance_to(pos) < HIT_RADIUS:
			return [El.GATE, i]

	for i in range(_data.stations.size() - 1, -1, -1):
		var s: StationData = _data.stations[i]
		if _orbit_screen(s.orbital_radius, s.orbital_angle).distance_to(pos) < HIT_RADIUS:
			return [El.STATION, i]

	for i in range(_data.planets.size() - 1, -1, -1):
		var p: PlanetData = _data.planets[i]
		var pr: float = PLANET_R.get(p.type, 6.0) + 4.0
		if _orbit_screen(p.orbital_radius, p.orbital_angle).distance_to(pos) < maxf(pr, HIT_RADIUS):
			return [El.PLANET, i]

	var sc := _w2s(0, 0)
	for i in range(_data.asteroid_belts.size() - 1, -1, -1):
		var b: AsteroidBeltData = _data.asteroid_belts[i]
		var r_px := b.orbital_radius * _ppu * _zoom
		var w_px := maxf(b.width * _ppu * _zoom * 0.5, 6.0)
		if absf(pos.distance_to(sc) - r_px) < w_px + 4.0:
			return [El.BELT, i]

	if sc.distance_to(pos) < 16.0:
		return [El.STAR, 0]

	return [El.NONE, -1]


# =============================================================================
# Drag
# =============================================================================

func _get_elem_world_pos(el: El, idx: int) -> Vector2:
	match el:
		El.PLANET:
			var p: PlanetData = _data.planets[idx]
			return Vector2(cos(p.orbital_angle) * p.orbital_radius, sin(p.orbital_angle) * p.orbital_radius)
		El.STATION:
			var s: StationData = _data.stations[idx]
			return Vector2(cos(s.orbital_angle) * s.orbital_radius, sin(s.orbital_angle) * s.orbital_radius)
		El.BELT:
			var b: AsteroidBeltData = _data.asteroid_belts[idx]
			return Vector2(b.orbital_radius, 0.0)
		El.GATE:
			var g: JumpGateData = _data.jump_gates[idx]
			return Vector2(g.pos_x, g.pos_z)
	return Vector2.ZERO


func _apply_drag(mouse_pos: Vector2) -> void:
	var wp := _s2w(mouse_pos.x, mouse_pos.y) + _drag_world_offset
	match _sel:
		El.PLANET:
			var p: PlanetData = _data.planets[_sel_idx]
			p.orbital_radius = maxf(wp.length(), 100.0)
			p.orbital_angle = atan2(wp.y, wp.x)
			_dirty = true
		El.STATION:
			var s: StationData = _data.stations[_sel_idx]
			s.orbital_radius = maxf(wp.length(), 100.0)
			s.orbital_angle = atan2(wp.y, wp.x)
			_dirty = true
		El.BELT:
			var b: AsteroidBeltData = _data.asteroid_belts[_sel_idx]
			b.orbital_radius = maxf(wp.length(), 100.0)
			_dirty = true
		El.GATE:
			var g: JumpGateData = _data.jump_gates[_sel_idx]
			g.pos_x = wp.x
			g.pos_z = wp.y
			_dirty = true


# =============================================================================
# Helpers
# =============================================================================

func _short(full_name: String) -> String:
	if _data and full_name.begins_with(_data.system_name):
		var s := full_name.substr(_data.system_name.length()).strip_edges()
		return s if s != "" else full_name
	return full_name


func _fmt_dist(d: float) -> String:
	var a := absf(d)
	var sign := "" if d >= 0 else "-"
	if a >= 1_000_000.0:
		return "%s%.1f Mm" % [sign, a / 1_000_000.0]
	if a >= 1000.0:
		return "%s%.1f km" % [sign, a / 1000.0]
	return "%s%.0f m" % [sign, a]


func _planet_str(t: int) -> String:
	match t:
		0: return "Rocheux"
		1: return "Volcanique"
		2: return "Oceanique"
		3: return "Geante gazeuse"
		4: return "Glace"
	return "Inconnu"


func _station_str(t: int) -> String:
	match t:
		0: return "Reparation"
		1: return "Commerce"
		2: return "Militaire"
		3: return "Extraction"
	return "Inconnu"
