class_name UnifiedMapScreen
extends UIScreen

# =============================================================================
# Unified Map Screen - Single screen with SYSTEM and GALAXY view modes
# SYSTEM: Delegates to existing StellarMap (ship, stations, planets, orbits)
# GALAXY: Draws all ~120 star systems, jump gate connections, spectral colors
# Tab/M/G switch between views. Immediate close (no transition).
# =============================================================================

enum ViewMode { SYSTEM, GALAXY }

var stellar_map: StellarMap = null
var galaxy: GalaxyData = null
var system_transition: SystemTransition = null

var current_view: ViewMode = ViewMode.SYSTEM
var _requested_view: ViewMode = ViewMode.SYSTEM

# --- Galaxy camera ---
var _cam_center: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.0
var _cam_target_zoom: float = 1.0
var _is_panning: bool = false

# --- Galaxy selection ---
var _selected_system: int = -1
var _hovered_system: int = -1
var _info_visible: bool = false
var _info_system: Dictionary = {}
var _galaxy_dirty: bool = true

# --- Constants ---
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 8.0
const ZOOM_STEP: float = 1.2
const ZOOM_SMOOTH: float = 8.0

const DOT_RADIUS: float = 5.0
const DOT_HOVER_RADIUS: float = 7.0
const DOT_SELECTED_RADIUS: float = 8.0
const CONNECTION_WIDTH: float = 1.0
const HIT_RADIUS: float = 12.0

const SPECTRAL_COLORS := {
	"O": Color(0.6, 0.7, 1.0),
	"B": Color(0.7, 0.8, 1.0),
	"A": Color(0.85, 0.88, 1.0),
	"F": Color(0.95, 0.95, 0.9),
	"G": Color(1.0, 0.95, 0.7),
	"K": Color(1.0, 0.8, 0.5),
	"M": Color(1.0, 0.6, 0.4),
}

const FACTION_COLORS := {
	&"neutral": Color(0.3, 0.5, 0.7, 0.08),
	&"hostile": Color(0.7, 0.2, 0.2, 0.08),
	&"friendly": Color(0.2, 0.7, 0.3, 0.08),
	&"lawless": Color(0.6, 0.4, 0.1, 0.08),
}


func _ready() -> void:
	screen_title = "MAP"
	screen_mode = ScreenMode.FULLSCREEN
	super._ready()
	# In SYSTEM mode, StellarMap handles input/rendering; we're just an overlay for the indicator
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the initial view before opening.
func set_initial_view(view: int) -> void:
	_requested_view = view as ViewMode


## Switch views while already open.
func switch_to_view(view: int) -> void:
	if current_view == view:
		return
	current_view = view as ViewMode
	if current_view == ViewMode.SYSTEM:
		_activate_system_view()
	else:
		_activate_galaxy_view()


func _on_opened() -> void:
	current_view = _requested_view
	if current_view == ViewMode.SYSTEM:
		_activate_system_view()
	else:
		_activate_galaxy_view()


func _activate_system_view() -> void:
	current_view = ViewMode.SYSTEM
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_panning = false
	if stellar_map:
		if not stellar_map._is_open:
			stellar_map.open()


func _activate_galaxy_view() -> void:
	current_view = ViewMode.GALAXY
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Close stellar map if open
	if stellar_map and stellar_map._is_open:
		stellar_map.close()
	# Reset galaxy selection
	_selected_system = -1
	_hovered_system = -1
	_info_visible = false
	_is_panning = false
	# Center on current system
	_center_galaxy_on_current()
	# Fit galaxy in view
	if galaxy and size.x > 0:
		var fit: float = (size.x * 0.35) / Constants.GALAXY_RADIUS
		_cam_zoom = clampf(fit, ZOOM_MIN, ZOOM_MAX)
		_cam_target_zoom = _cam_zoom


func _center_galaxy_on_current() -> void:
	if galaxy and system_transition and system_transition.current_system_id >= 0:
		var sys: Dictionary = galaxy.get_system(system_transition.current_system_id)
		if not sys.is_empty():
			_cam_center = Vector2(sys["x"], sys["y"])
			_galaxy_dirty = true


## Override: immediate close (no transition), closes StellarMap too.
func close() -> void:
	if not _is_open:
		return
	if stellar_map and stellar_map._is_open:
		stellar_map.close()
	_is_panning = false
	_is_open = false
	visible = false
	_on_closed()
	closed.emit()


func _on_closed() -> void:
	_is_panning = false


## Override: skip UIScreen transition. Handle galaxy zoom smoothing.
func _process(delta: float) -> void:
	if not _is_open:
		return

	if current_view == ViewMode.GALAXY:
		# Smooth zoom
		if not is_equal_approx(_cam_zoom, _cam_target_zoom):
			_cam_zoom = lerpf(_cam_zoom, _cam_target_zoom, delta * ZOOM_SMOOTH)
			if absf(_cam_zoom - _cam_target_zoom) < 0.001:
				_cam_zoom = _cam_target_zoom
			_galaxy_dirty = true

	# Full opacity, no transition
	modulate.a = 1.0
	if _galaxy_dirty:
		queue_redraw()
		_galaxy_dirty = false


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if not _is_open:
		return

	if current_view == ViewMode.GALAXY:
		_draw_galaxy()

	# Always draw the view mode indicator on top
	_draw_view_indicator()


func _draw_galaxy() -> void:
	if galaxy == null:
		return

	var s := size
	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5
	var cy: float = s.y * 0.5

	# Fully opaque background (no 3D scene bleed-through)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 1.0))

	# Title
	_draw_galaxy_title(s, font)

	# Connections
	_draw_connections(cx, cy)

	# Faction territory circles
	_draw_faction_territories(cx, cy)

	# System dots
	_draw_systems(s, cx, cy, font)

	# Current system highlight
	_draw_current_system_marker(cx, cy)

	# Info panel
	if _info_visible and not _info_system.is_empty():
		_draw_info_panel(s, font)

	# Legend
	_draw_galaxy_legend(s, font)

	# Current system label at bottom
	_draw_current_label(s, font)


func _draw_galaxy_title(s: Vector2, font: Font) -> void:
	var fsize: int = UITheme.FONT_SIZE_TITLE
	var title_y: float = UITheme.MARGIN_SCREEN + fsize
	var title_text := "GALAXY MAP"

	draw_string(font, Vector2(0, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize, UITheme.TEXT_HEADER)

	# Decorative lines
	var cx: float = s.x * 0.5
	var title_w: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	var line_y: float = title_y - fsize * 0.35
	var half: float = title_w * 0.5 + 20
	var line_len: float = 120.0
	draw_line(Vector2(cx - half - line_len, line_y), Vector2(cx - half, line_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(cx + half, line_y), Vector2(cx + half + line_len, line_y), UITheme.BORDER, 1.0)

	# Separator
	var sep_y: float = title_y + 10
	draw_line(Vector2(UITheme.MARGIN_SCREEN, sep_y), Vector2(s.x - UITheme.MARGIN_SCREEN, sep_y), UITheme.BORDER, 1.0)


func _draw_view_indicator() -> void:
	var font := UITheme.get_font()
	var s := size
	var y: float = s.y - 24.0
	var cx: float = s.x * 0.5

	# Background bar
	var bar_w: float = 300.0
	var bar_h: float = 30.0
	var bar_rect := Rect2(cx - bar_w * 0.5, y - bar_h * 0.5, bar_w, bar_h)
	draw_rect(bar_rect, Color(0.0, 0.02, 0.05, 0.85))
	draw_rect(bar_rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cl: float = 8.0
	var cc := UITheme.PRIMARY
	var bx: float = bar_rect.position.x
	var by: float = bar_rect.position.y
	var bw: float = bar_rect.size.x
	var bh: float = bar_rect.size.y
	draw_line(Vector2(bx, by), Vector2(bx + cl, by), cc, 1.5)
	draw_line(Vector2(bx, by), Vector2(bx, by + cl), cc, 1.5)
	draw_line(Vector2(bx + bw, by), Vector2(bx + bw - cl, by), cc, 1.5)
	draw_line(Vector2(bx + bw, by), Vector2(bx + bw, by + cl), cc, 1.5)
	draw_line(Vector2(bx, by + bh), Vector2(bx + cl, by + bh), cc, 1.5)
	draw_line(Vector2(bx, by + bh), Vector2(bx, by + bh - cl), cc, 1.5)
	draw_line(Vector2(bx + bw, by + bh), Vector2(bx + bw - cl, by + bh), cc, 1.5)
	draw_line(Vector2(bx + bw, by + bh), Vector2(bx + bw, by + bh - cl), cc, 1.5)

	var text_y: float = y + 5.0

	# Tab hint
	draw_string(font, Vector2(cx - 135, text_y), "[TAB]", HORIZONTAL_ALIGNMENT_LEFT, 50, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# SYSTEM label
	var sys_col: Color = UITheme.PRIMARY if current_view == ViewMode.SYSTEM else UITheme.TEXT_DIM
	draw_string(font, Vector2(cx - 75, text_y), "SYSTEM", HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_BODY, sys_col)
	# Underline active
	if current_view == ViewMode.SYSTEM:
		draw_line(Vector2(cx - 75, text_y + 3), Vector2(cx - 10, text_y + 3), UITheme.PRIMARY, 2.0)

	# Separator
	draw_string(font, Vector2(cx - 2, text_y), "|", HORIZONTAL_ALIGNMENT_CENTER, 10, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# GALAXY label
	var gal_col: Color = UITheme.PRIMARY if current_view == ViewMode.GALAXY else UITheme.TEXT_DIM
	draw_string(font, Vector2(cx + 15, text_y), "GALAXY", HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_BODY, gal_col)
	if current_view == ViewMode.GALAXY:
		draw_line(Vector2(cx + 15, text_y + 3), Vector2(cx + 80, text_y + 3), UITheme.PRIMARY, 2.0)

	# Key hints on the sides
	draw_string(font, Vector2(cx + 95, text_y), "[M]", HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM if current_view != ViewMode.SYSTEM else Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.15))
	draw_string(font, Vector2(cx + 118, text_y), "[G]", HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM if current_view != ViewMode.GALAXY else Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.15))


# =============================================================================
# GALAXY DRAWING HELPERS
# =============================================================================
func _galaxy_to_screen(gx: float, gy: float, cx: float, cy: float) -> Vector2:
	return Vector2(
		cx + (gx - _cam_center.x) * _cam_zoom,
		cy + (gy - _cam_center.y) * _cam_zoom,
	)


func _screen_to_galaxy(sx: float, sy: float, cx: float, cy: float) -> Vector2:
	return Vector2(
		(sx - cx) / _cam_zoom + _cam_center.x,
		(sy - cy) / _cam_zoom + _cam_center.y,
	)


func _draw_connections(cx: float, cy: float) -> void:
	var drawn: Dictionary = {}
	for sys in galaxy.systems:
		var a_id: int = sys["id"]
		var a_pos := _galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		for b_id in sys["connections"]:
			var key: String = "%d_%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
			if drawn.has(key):
				continue
			drawn[key] = true
			var b_sys: Dictionary = galaxy.get_system(b_id)
			if b_sys.is_empty():
				continue
			var b_pos := _galaxy_to_screen(b_sys["x"], b_sys["y"], cx, cy)
			var line_color := Color(0.15, 0.4, 0.6, 0.2)
			if a_id == _selected_system or b_id == _selected_system:
				line_color = Color(0.2, 0.7, 1.0, 0.5)
			draw_line(a_pos, b_pos, line_color, CONNECTION_WIDTH)


func _draw_faction_territories(cx: float, cy: float) -> void:
	for sys in galaxy.systems:
		var faction: StringName = sys["faction"]
		var col: Color = FACTION_COLORS.get(faction, FACTION_COLORS[&"neutral"])
		var pos := _galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		var radius: float = 30.0 * _cam_zoom
		draw_circle(pos, radius, col)


func _draw_systems(s: Vector2, cx: float, cy: float, font: Font) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	for sys in galaxy.systems:
		var pos := _galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		# Cull off-screen
		if pos.x < -20 or pos.x > s.x + 20 or pos.y < -20 or pos.y > s.y + 20:
			continue

		var sys_id: int = sys["id"]
		var spectral: String = sys["spectral_class"]
		var base_color: Color = SPECTRAL_COLORS.get(spectral, Color.WHITE)
		var radius: float = DOT_RADIUS
		var draw_col := base_color

		# Visited indicator
		var visited: bool = system_transition != null and system_transition.has_visited(sys_id)
		if not visited and sys_id != current_id:
			draw_col.a = 0.5

		# Hover
		if sys_id == _hovered_system:
			radius = DOT_HOVER_RADIUS
			draw_col.a = 1.0

		# Selected
		if sys_id == _selected_system:
			radius = DOT_SELECTED_RADIUS
			draw_col = UITheme.PRIMARY

		# Station indicator ring
		if sys["has_station"]:
			draw_arc(pos, radius + 3, 0, TAU, 16, MapColors.STATION_TEAL, 1.0)

		# Dot
		draw_circle(pos, radius, draw_col)

		# Name at sufficient zoom
		if _cam_zoom > 1.5:
			var name_col := Color(0.6, 0.8, 0.9, 0.6)
			if sys_id == _hovered_system or sys_id == _selected_system:
				name_col.a = 0.9
			draw_string(font, pos + Vector2(radius + 4, 4), sys["name"], HORIZONTAL_ALIGNMENT_LEFT, 200, UITheme.FONT_SIZE_SMALL, name_col)


func _draw_current_system_marker(cx: float, cy: float) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	if current_id < 0 or galaxy == null:
		return
	var sys: Dictionary = galaxy.get_system(current_id)
	if sys.is_empty():
		return
	var pos := _galaxy_to_screen(sys["x"], sys["y"], cx, cy)

	# Pulsing ring
	var pulse: float = UITheme.get_pulse(0.8)
	var ring_radius: float = DOT_SELECTED_RADIUS + 4.0 + pulse * 3.0
	var ring_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.5 + pulse * 0.3)
	draw_arc(pos, ring_radius, 0, TAU, 24, ring_col, 2.0)

	# "ICI" marker
	var font: Font = UITheme.get_font()
	draw_string(font, pos + Vector2(-15, -ring_radius - 6), "ICI", HORIZONTAL_ALIGNMENT_CENTER, 30, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


func _draw_info_panel(s: Vector2, font: Font) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	var panel_w: float = 280.0
	var panel_h: float = 240.0
	var panel_x: float = s.x - panel_w - UITheme.MARGIN_SCREEN
	var panel_y: float = UITheme.MARGIN_SCREEN + 50
	var rect := Rect2(panel_x, panel_y, panel_w, panel_h)

	# Background + border
	draw_rect(rect, UITheme.BG_PANEL)
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cl: float = 10.0
	var cc := MapColors.CORNER
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x + cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x, panel_y + cl), cc, 1.5)
	draw_line(Vector2(panel_x + panel_w, panel_y), Vector2(panel_x + panel_w - cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x + panel_w, panel_y), Vector2(panel_x + panel_w, panel_y + cl), cc, 1.5)

	var x: float = panel_x + 14
	var y: float = panel_y + 24
	var line_h: float = UITheme.ROW_HEIGHT
	var kv_w: float = panel_w - 28

	# System name
	draw_string(font, Vector2(x, y), _info_system.get("name", "Unknown"), HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)
	y += 6
	draw_line(Vector2(x, y), Vector2(panel_x + panel_w - 14, y), UITheme.BORDER, 1.0)
	y += line_h

	# Star type
	_draw_kv(font, x, y, kv_w, "CLASSE", _info_system.get("spectral_class", "?") + "-class")
	y += line_h

	# Faction
	var faction: String = str(_info_system.get("faction", &"neutral"))
	_draw_kv(font, x, y, kv_w, "FACTION", faction.capitalize())
	y += line_h

	# Danger
	var danger: int = _info_system.get("danger_level", 0)
	var danger_bar: String = ""
	for i in 5:
		danger_bar += "|" if i < danger else "."
	_draw_kv(font, x, y, kv_w, "DANGER", danger_bar + "  (%d/5)" % danger)
	y += line_h

	# Station
	var has_station: bool = _info_system.get("has_station", false)
	_draw_kv(font, x, y, kv_w, "STATION", "Oui" if has_station else "Non")
	y += line_h

	# Connections
	var connections: Array = _info_system.get("connections", [])
	_draw_kv(font, x, y, kv_w, "PORTAILS", str(connections.size()))
	y += line_h

	# Visited
	var sys_id: int = _info_system.get("id", -1)
	var visited: bool = system_transition != null and system_transition.has_visited(sys_id)
	_draw_kv(font, x, y, kv_w, "VISITE", "Oui" if visited or sys_id == current_id else "Non")
	y += line_h + 8

	# Connected system names
	if connections.size() > 0 and _cam_zoom > 1.0:
		draw_string(font, Vector2(x, y), "Connexions:", HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		y += 14
		for conn_id in connections:
			var conn_name: String = galaxy.get_system_name(conn_id)
			if conn_name != "":
				var conn_col := UITheme.LABEL_VALUE
				if conn_id == current_id:
					conn_col = UITheme.PRIMARY
				draw_string(font, Vector2(x + 8, y), conn_name, HORIZONTAL_ALIGNMENT_LEFT, kv_w - 8, UITheme.FONT_SIZE_SMALL, conn_col)
				y += 13

	# Jump instruction
	if sys_id != current_id and sys_id >= 0 and current_id >= 0:
		var cur_sys: Dictionary = galaxy.get_system(current_id)
		if not cur_sys.is_empty() and sys_id in cur_sys["connections"]:
			y += 4
			draw_string(font, Vector2(x, y), "Rejoignez le portail pour sauter", HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)


func _draw_kv(font: Font, x: float, y: float, w: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, UITheme.FONT_SIZE_BODY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(x + w * 0.4, y), value, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, UITheme.FONT_SIZE_BODY, UITheme.LABEL_VALUE)


func _draw_galaxy_legend(s: Vector2, font: Font) -> void:
	var x: float = UITheme.MARGIN_SCREEN
	var y: float = s.y - UITheme.MARGIN_SCREEN - 80

	draw_string(font, Vector2(x, y), "Click = Selectionner | Scroll = Zoom | MMB = Deplacer | Tab/M = Vue Systeme", HORIZONTAL_ALIGNMENT_LEFT, 600, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	y += 14

	# Spectral class legend
	var legend_x: float = x
	for spec_class in ["O", "B", "A", "F", "G", "K", "M"]:
		var col: Color = SPECTRAL_COLORS[spec_class]
		draw_circle(Vector2(legend_x + 4, y + 4), 3.0, col)
		draw_string(font, Vector2(legend_x + 10, y + 8), spec_class, HORIZONTAL_ALIGNMENT_LEFT, 20, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
		legend_x += 30


func _draw_current_label(s: Vector2, font: Font) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	if galaxy == null or current_id < 0:
		return
	var sys: Dictionary = galaxy.get_system(current_id)
	if sys.is_empty():
		return
	var label: String = "Systeme actuel: " + sys["name"] + " (" + sys["spectral_class"] + "-class)"
	draw_string(font, Vector2(UITheme.MARGIN_SCREEN, s.y - UITheme.MARGIN_SCREEN - 50), label, HORIZONTAL_ALIGNMENT_LEFT, 500, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


# =============================================================================
# INPUT — Galaxy view uses _input() (global), mirrors how StellarMap works
# =============================================================================
func _input(event: InputEvent) -> void:
	if not _is_open or current_view != ViewMode.GALAXY:
		return
	_handle_galaxy_input(event)


func _handle_galaxy_input(event: InputEvent) -> void:
	# Keys
	if event is InputEventKey and event.pressed:
		# Tab or M → switch to system view
		if event.physical_keycode == KEY_TAB:
			switch_to_view(ViewMode.SYSTEM)
			get_viewport().set_input_as_handled()
			return
		# M and G are handled by GameManager (fires first as autoload)
		# Escape is handled by UIScreenManager (fires before us in tree)
		# Consume all other keys to prevent ship movement
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.pressed:
		get_viewport().set_input_as_handled()
		return

	# Mouse zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		# Pan with middle mouse
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			get_viewport().set_input_as_handled()
			return

		# Click to select
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
			get_viewport().set_input_as_handled()
			return

		# Right-click recenter on current system
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_center_galaxy_on_current()
			get_viewport().set_input_as_handled()
			return

	# Mouse motion
	if event is InputEventMouseMotion:
		if _is_panning:
			_cam_center -= event.relative / _cam_zoom
			_galaxy_dirty = true
		else:
			var old_hover := _hovered_system
			_update_hover(event.position)
			if _hovered_system != old_hover:
				_galaxy_dirty = true
		get_viewport().set_input_as_handled()
		return


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var galaxy_pos := _screen_to_galaxy(screen_pos.x, screen_pos.y, cx, cy)
	_cam_target_zoom = clampf(_cam_target_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var new_screen_pos := _galaxy_to_screen(galaxy_pos.x, galaxy_pos.y, cx, cy)
	var diff := screen_pos - new_screen_pos
	_cam_center -= diff / _cam_target_zoom
	_galaxy_dirty = true


func _update_hover(screen_pos: Vector2) -> void:
	_hovered_system = _get_system_at(screen_pos)


func _handle_click(screen_pos: Vector2) -> void:
	var hit: int = _get_system_at(screen_pos)
	if hit >= 0:
		_selected_system = hit
		_info_system = galaxy.get_system(hit)
		_info_visible = true
	else:
		_selected_system = -1
		_info_visible = false
	_galaxy_dirty = true


func _get_system_at(screen_pos: Vector2) -> int:
	if galaxy == null:
		return -1
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var best_id: int = -1
	var best_dist: float = HIT_RADIUS
	for sys in galaxy.systems:
		var pos := _galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		var dist: float = screen_pos.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_id = sys["id"]
	return best_id


## Override _gui_input — galaxy uses _input() instead, system mode uses StellarMap.
func _gui_input(_event: InputEvent) -> void:
	if current_view == ViewMode.GALAXY:
		accept_event()
