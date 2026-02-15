class_name MapRenderer
extends Control

# =============================================================================
# Map Renderer - Background, adaptive grid, orbit lines, scale bar, scanline
# + Interactive toolbar (replaces keyboard-only filter legend)
# All custom-drawn for holographic aesthetic
# =============================================================================

signal filter_toggled(key: int)
signal follow_toggled

var camera = null
var filters: Dictionary = {}  # EntityType -> bool (true = hidden)
var follow_enabled: bool = true
var preview_entities: Dictionary = {}  # When non-empty, overrides EntityRegistry
var _scan_line_y: float = 0.0
var _pulse_t: float = 0.0
var _system_name: String = "SYSTÈME INCONNU"

# Cache for asteroid belt dot positions (universe coords)
# Key: entity id, Value: Array of [ux, uz] pairs
var _belt_dot_cache: Dictionary = {}

# --- Toolbar ---
var TOOLBAR_BUTTONS: Array = []  # populated in _ready
const TOOLBAR_BTN_H: float = 20.0
const TOOLBAR_BTN_PAD: float = 8.0
const TOOLBAR_BTN_INNER_PAD: float = 10.0
var _toolbar_hovered: int = -1  # index into TOOLBAR_BUTTONS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	TOOLBAR_BUTTONS = [
		{"label": "Orbites", "key": -1},
		{"label": "Planetes", "key": EntityRegistrySystem.EntityType.PLANET},
		{"label": "Stations", "key": EntityRegistrySystem.EntityType.STATION},
		{"label": "PNJ", "key": EntityRegistrySystem.EntityType.SHIP_NPC},
		{"label": "Suivre", "key": -99},
	]


func _process(delta: float) -> void:
	_scan_line_y = fmod(_scan_line_y + delta * 60.0, size.y)
	_pulse_t += delta


func _draw() -> void:
	if camera == null:
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), MapColors.BG)

	_draw_grid()
	_draw_orbit_lines()
	_draw_asteroid_belts()
	_draw_scanline()
	_draw_header()
	_draw_toolbar()
	_draw_scale_bar()


# =============================================================================
# TOOLBAR — Interactive filter buttons
# =============================================================================
func _get_toolbar_rects() -> Array[Rect2]:
	var font: Font = UITheme.get_font()
	var rects: Array[Rect2] = []
	var tx: float = MapLayout.viewport_left()
	var ty: float = MapLayout.TOOLBAR_Y

	for btn in TOOLBAR_BUTTONS:
		var tw: float = font.get_string_size(btn["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
		var btn_w: float = tw + TOOLBAR_BTN_INNER_PAD * 2
		rects.append(Rect2(tx, ty, btn_w, TOOLBAR_BTN_H))
		tx += btn_w + TOOLBAR_BTN_PAD

	return rects


func handle_toolbar_click(pos: Vector2) -> bool:
	var rects =_get_toolbar_rects()
	for i in rects.size():
		if rects[i].has_point(pos):
			var key: int = TOOLBAR_BUTTONS[i]["key"]
			if key == -99:
				follow_toggled.emit()
			else:
				filter_toggled.emit(key)
			return true
	return false


func update_toolbar_hover(pos: Vector2) -> void:
	var old =_toolbar_hovered
	_toolbar_hovered = -1
	var rects =_get_toolbar_rects()
	for i in rects.size():
		if rects[i].has_point(pos):
			_toolbar_hovered = i
			break
	if _toolbar_hovered != old:
		queue_redraw()


func _draw_toolbar() -> void:
	var font: Font = UITheme.get_font()
	var rects =_get_toolbar_rects()

	for i in rects.size():
		var r: Rect2 = rects[i]
		var btn: Dictionary = TOOLBAR_BUTTONS[i]
		var key: int = btn["key"]
		var is_active: bool
		if key == -99:
			is_active = follow_enabled
		else:
			is_active = not filters.get(key, false)

		var is_hovered: bool = i == _toolbar_hovered

		# Background
		var bg_col: Color
		if is_active:
			bg_col = Color(MapColors.PRIMARY.r, MapColors.PRIMARY.g, MapColors.PRIMARY.b, 0.15 if not is_hovered else 0.25)
		else:
			bg_col = Color(0.2, 0.2, 0.3, 0.1 if not is_hovered else 0.18)
		draw_rect(r, bg_col)

		# Border
		var border_col: Color
		if is_active:
			border_col = Color(MapColors.PRIMARY.r, MapColors.PRIMARY.g, MapColors.PRIMARY.b, 0.6 if not is_hovered else 0.8)
		else:
			border_col = Color(0.4, 0.4, 0.5, 0.3 if not is_hovered else 0.5)
		draw_rect(r, border_col, false, 1.0)

		# Text
		var text_col: Color
		if is_active:
			text_col = MapColors.PRIMARY if not is_hovered else Color(MapColors.PRIMARY.r, MapColors.PRIMARY.g, MapColors.PRIMARY.b, 1.0)
		else:
			text_col = MapColors.FILTER_INACTIVE if not is_hovered else Color(0.5, 0.5, 0.6, 0.6)

		draw_string(font, Vector2(r.position.x + TOOLBAR_BTN_INNER_PAD, r.position.y + TOOLBAR_BTN_H - 5), btn["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, text_col)


# =============================================================================
# ADAPTIVE GRID
# =============================================================================
func _draw_grid() -> void:
	var font: Font = UITheme.get_font()
	var visible_range: float = camera.get_visible_range()
	var vp_left: float = MapLayout.viewport_left()
	var vp_right: float = MapLayout.viewport_right(size.x)

	# Find grid spacing: choose a power so lines are ~100-200px apart
	var target_spacing_meters: float = visible_range / (size.x / 120.0)
	var grid_spacing: float = _snap_to_nice(target_spacing_meters)
	var major_every: int = 5  # every 5th line is major

	# Compute visible bounds in universe coords
	var left_u: float = camera.screen_to_universe_x(0.0)
	var right_u: float = camera.screen_to_universe_x(size.x)
	var top_u: float = camera.screen_to_universe_z(0.0)
	var bottom_u: float = camera.screen_to_universe_z(size.y)

	# Vertical lines
	var start_x: float = snappedf(left_u, grid_spacing)
	var x: float = start_x
	var count: int = 0
	while x <= right_u and count < 200:
		var sx: float = camera.universe_to_screen(x, 0.0).x
		var idx: int = roundi(x / grid_spacing)
		var is_major: bool = (idx % major_every) == 0
		var col: Color = MapColors.GRID_MAJOR if is_major else MapColors.GRID_MINOR
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), col, 1.0)
		# Label on major lines — clipped to viewport zone
		if is_major and sx > vp_left + 10 and sx < vp_right - 10:
			var label: String = camera.format_distance(absf(x))
			if x < 0: label = "-" + label
			draw_string(font, Vector2(sx + 4, MapLayout.TOOLBAR_Y + MapLayout.TOOLBAR_H + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, MapColors.GRID_LABEL)
		x += grid_spacing
		count += 1

	# Horizontal lines
	var start_z: float = snappedf(top_u, grid_spacing)
	var z: float = start_z
	count = 0
	while z <= bottom_u and count < 200:
		var sy: float = camera.universe_to_screen(0.0, z).y
		var idx_z: int = roundi(z / grid_spacing)
		var is_major: bool = (idx_z % major_every) == 0
		var col: Color = MapColors.GRID_MAJOR if is_major else MapColors.GRID_MINOR
		draw_line(Vector2(0, sy), Vector2(size.x, sy), col, 1.0)
		z += grid_spacing
		count += 1


func _snap_to_nice(value: float) -> float:
	if value <= 0.0:
		return 1.0
	var exp_val: float = floor(log(value) / log(10.0))
	var base: float = pow(10.0, exp_val)
	var ratio: float = value / base
	if ratio < 1.5:
		return base
	elif ratio < 3.5:
		return base * 2.0
	elif ratio < 7.5:
		return base * 5.0
	else:
		return base * 10.0


# =============================================================================
# ORBIT LINES
# =============================================================================
func _get_entities() -> Dictionary:
	return preview_entities if not preview_entities.is_empty() else EntityRegistry.get_all()


func _draw_orbit_lines() -> void:
	if filters.get(-1, false):
		return

	var entities: Dictionary = _get_entities()
	for ent in entities.values():
		var orbital_r: float = ent["orbital_radius"]
		if orbital_r <= 0.0:
			continue
		if ent["type"] == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue

		var parent_id: String = ent["orbital_parent"]
		var px: float = 0.0
		var pz: float = 0.0
		if parent_id != "" and entities.has(parent_id):
			px = entities[parent_id]["pos_x"]
			pz = entities[parent_id]["pos_z"]

		var center_screen: Vector2 = camera.universe_to_screen(px, pz)
		var radius_px: float = orbital_r * camera.zoom
		if radius_px < 2.0:
			continue
		if center_screen.x + radius_px < -50 or center_screen.x - radius_px > size.x + 50:
			continue
		if center_screen.y + radius_px < -50 or center_screen.y - radius_px > size.y + 50:
			continue

		var col: Color = MapColors.ORBIT_LINE
		var segments: int = clampi(int(radius_px * 0.3), 32, 256)
		var points: PackedVector2Array = PackedVector2Array()
		for i in segments + 1:
			var angle: float = TAU * float(i) / float(segments)
			var wx: float = px + cos(angle) * orbital_r
			var wz: float = pz + sin(angle) * orbital_r
			points.append(camera.universe_to_screen(wx, wz))
		if points.size() > 1:
			draw_polyline(points, col, 1.0, true)


# =============================================================================
# ASTEROID BELTS
# =============================================================================
func _draw_asteroid_belts() -> void:
	if filters.get(EntityRegistrySystem.EntityType.ASTEROID_BELT, false):
		return

	var font: Font = UITheme.get_font()
	var entities: Dictionary = _get_entities()
	for ent in entities.values():
		if ent["type"] != EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue

		var orbital_r: float = ent["orbital_radius"]
		if orbital_r <= 0.0:
			continue

		var parent_id: String = ent["orbital_parent"]
		var px: float = 0.0
		var pz: float = 0.0
		if parent_id != "" and entities.has(parent_id):
			px = entities[parent_id]["pos_x"]
			pz = entities[parent_id]["pos_z"]

		var _center_screen: Vector2 = camera.universe_to_screen(px, pz)
		var radius_px: float = orbital_r * camera.zoom
		if radius_px < 3.0:
			continue

		var belt_width: float = ent["extra"].get("width", orbital_r * 0.1)
		var inner_r: float = orbital_r - belt_width * 0.5
		var outer_r: float = orbital_r + belt_width * 0.5
		var segments: int = clampi(int(radius_px * 0.2), 24, 128)

		for ring_r in [inner_r, outer_r]:
			var points: PackedVector2Array = PackedVector2Array()
			for i in segments + 1:
				var angle: float = TAU * float(i) / float(segments)
				var wx: float = px + cos(angle) * ring_r
				var wz: float = pz + sin(angle) * ring_r
				points.append(camera.universe_to_screen(wx, wz))
			if points.size() > 1:
				draw_polyline(points, MapColors.ASTEROID_BELT, 1.5, true)

		# Scatter dots between rings (cached universe positions)
		if radius_px > 30:
			var ent_id: String = ent["id"]
			if not _belt_dot_cache.has(ent_id):
				var new_dots: Array = []
				var rng =RandomNumberGenerator.new()
				rng.seed = hash(ent_id)
				for i in 60:
					var a: float = rng.randf() * TAU
					var r: float = lerpf(inner_r, outer_r, rng.randf())
					new_dots.append([px + cos(a) * r, pz + sin(a) * r])
				_belt_dot_cache[ent_id] = new_dots

			var cached_dots: Array = _belt_dot_cache[ent_id]
			var dot_count: int = clampi(int(radius_px * 0.15), 8, cached_dots.size())
			for i in dot_count:
				var sp: Vector2 = camera.universe_to_screen(cached_dots[i][0], cached_dots[i][1])
				if sp.x > 0 and sp.x < size.x and sp.y > 0 and sp.y < size.y:
					draw_circle(sp, 1.5, MapColors.ASTEROID_BELT)

		# Belt label
		if radius_px > 20:
			var label_wx: float = px
			var label_wz: float = pz - orbital_r
			var label_sp: Vector2 = camera.universe_to_screen(label_wx, label_wz)
			if label_sp.x > 0 and label_sp.x < size.x and label_sp.y > 0 and label_sp.y < size.y:
				var belt_name: String = ent["name"]
				var tw: float = font.get_string_size(belt_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x
				var label_col =Color(MapColors.ASTEROID_BELT.r, MapColors.ASTEROID_BELT.g, MapColors.ASTEROID_BELT.b, 0.8)
				draw_string(font, Vector2(label_sp.x - tw * 0.5, label_sp.y - 6), belt_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, label_col)


# =============================================================================
# SCANLINE — clipped to viewport zone
# =============================================================================
func _draw_scanline() -> void:
	var vp_left: float = MapLayout.viewport_left()
	var vp_right: float = MapLayout.viewport_right(size.x)
	var alpha: float = 0.025 + sin(_pulse_t * 0.5) * 0.01
	var col =Color(MapColors.SCANLINE.r, MapColors.SCANLINE.g, MapColors.SCANLINE.b, alpha)
	draw_line(Vector2(vp_left, _scan_line_y), Vector2(vp_right, _scan_line_y), col, 1.0)
	for i in range(1, 4):
		var ty: float = _scan_line_y - float(i) * 3.0
		if ty > 0:
			draw_line(Vector2(vp_left, ty), Vector2(vp_right, ty), col * Color(1, 1, 1, 0.3), 1.0)


# =============================================================================
# HEADER — positioned after fleet panel
# =============================================================================
func _draw_header() -> void:
	var font: Font = UITheme.get_font()
	var hx: float = MapLayout.viewport_left()
	var vp_right: float = MapLayout.viewport_right(size.x)

	# System name
	draw_string(font, Vector2(hx, MapLayout.HEADER_Y), _system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_HEADER, MapColors.TEXT_HEADER)

	# Zoom level label
	var zoom_text: String = "ZOOM : " + camera.get_zoom_label()
	draw_string(font, Vector2(hx, MapLayout.HEADER_Y + 18), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, MapColors.TEXT_DIM)

	# Coordinates (right side of viewport)
	var coord_text: String = "X: %.0f  Z: %.0f" % [camera.center_x, camera.center_z]
	var coord_w: float = font.get_string_size(coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
	draw_string(font, Vector2(vp_right - coord_w, MapLayout.HEADER_Y), coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, MapColors.TEXT_DIM)


# =============================================================================
# SCALE BAR — positioned inside viewport zone
# =============================================================================
func _draw_scale_bar() -> void:
	var font: Font = UITheme.get_font()
	var target_px: float = 120.0
	var meters_for_bar: float = target_px / camera.zoom
	var nice_meters: float = _snap_to_nice(meters_for_bar)
	var bar_px: float = nice_meters * camera.zoom

	var bar_y: float = size.y - 30.0
	var bar_right: float = MapLayout.scale_bar_right(size.x)
	var bar_x: float = bar_right - bar_px

	# Bar line
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + bar_px, bar_y), MapColors.SCALE_BAR, 2.0)
	# End caps
	draw_line(Vector2(bar_x, bar_y - 5), Vector2(bar_x, bar_y + 5), MapColors.SCALE_BAR, 1.0)
	draw_line(Vector2(bar_x + bar_px, bar_y - 5), Vector2(bar_x + bar_px, bar_y + 5), MapColors.SCALE_BAR, 1.0)
	# Label
	var label: String = camera.format_distance(nice_meters)
	var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
	draw_string(font, Vector2(bar_x + bar_px * 0.5 - label_w * 0.5, bar_y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, MapColors.SCALE_BAR)
