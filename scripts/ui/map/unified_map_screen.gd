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
var galaxy = null
var system_transition = null

# Fleet panel for galaxy view (independent scroll state from system view)
var _galaxy_fleet_panel: MapFleetPanel = null

var current_view: ViewMode = ViewMode.SYSTEM
var _requested_view: ViewMode = ViewMode.SYSTEM

# --- Galaxy camera ---
var _cam_center: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.0
var _cam_target_zoom: float = 1.0
var _is_panning: bool = false
var _pan_velocity: Vector2 = Vector2.ZERO  # galaxy units/sec, smooth WASD + inertia
var _zoom_anchor_galaxy: Vector2 = Vector2.ZERO  # galaxy point that stays fixed during zoom
var _zoom_anchor_screen: Vector2 = Vector2.ZERO   # screen position of that anchor
var _zoom_anchored: bool = false

# Pan tuning
const PAN_ACCEL: float = 5.0         # ease-in rate
const PAN_FRICTION: float = 4.5      # ease-out rate
const PAN_BASE_SPEED: float = 900.0  # max WASD speed in screen px/sec (converted via zoom)

# --- Galaxy selection ---
var _selected_system: int = -1
var _hovered_system: int = -1
var _info_visible: bool = false
var _info_system: Dictionary = {}
var _galaxy_dirty: bool = true

# Resolved StarSystemData for the selected system (cached)
var _resolved_data: StarSystemData = null
var _resolved_system_id: int = -1

# Double-click detection for galaxy view
var _last_galaxy_click_time: float = 0.0
var _last_galaxy_click_id: int = -1

# Preview mode: showing another system's contents in system view
var _preview_system_id: int = -1

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

const SPECTRAL_COLORS ={
	"O": Color(0.6, 0.7, 1.0),
	"B": Color(0.7, 0.8, 1.0),
	"A": Color(0.85, 0.88, 1.0),
	"F": Color(0.95, 0.95, 0.9),
	"G": Color(1.0, 0.95, 0.7),
	"K": Color(1.0, 0.8, 0.5),
	"M": Color(1.0, 0.6, 0.4),
}

const FACTION_COLORS ={
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

	# Galaxy fleet panel (visible only in galaxy view)
	_galaxy_fleet_panel = MapFleetPanel.new()
	_galaxy_fleet_panel.name = "GalaxyFleetPanel"
	_galaxy_fleet_panel.anchor_left = 0.0
	_galaxy_fleet_panel.anchor_top = 0.0
	_galaxy_fleet_panel.anchor_right = 1.0
	_galaxy_fleet_panel.anchor_bottom = 1.0
	_galaxy_fleet_panel.visible = false
	_galaxy_fleet_panel.ship_selected.connect(_on_galaxy_fleet_ship_selected)
	add_child(_galaxy_fleet_panel)


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
	# Ensure galaxy fleet panel has the current fleet reference (may have been
	# replaced after backend state load or deserialization)
	if _galaxy_fleet_panel:
		var current_fleet = GameManager.player_fleet
		if current_fleet and _galaxy_fleet_panel._fleet != current_fleet:
			_galaxy_fleet_panel.set_fleet(current_fleet)
	current_view = _requested_view
	if current_view == ViewMode.SYSTEM:
		_activate_system_view()
	else:
		_activate_galaxy_view()


func _activate_system_view() -> void:
	current_view = ViewMode.SYSTEM
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_panning = false
	_pan_velocity = Vector2.ZERO
	if _galaxy_fleet_panel:
		_galaxy_fleet_panel.visible = false
	# Force redraw to clear stale galaxy rendering (opaque background)
	queue_redraw()
	if stellar_map:
		# Clear preview if switching to system view via Tab/M (not via double-click)
		if _preview_system_id < 0 and not stellar_map._preview_entities.is_empty():
			stellar_map.clear_preview()
		if not stellar_map._is_open:
			stellar_map.open()


func _activate_galaxy_view() -> void:
	current_view = ViewMode.GALAXY
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _galaxy_fleet_panel:
		_galaxy_fleet_panel.visible = true
	# Remember previewed system before clearing
	var was_previewing: int = _preview_system_id
	# Clear preview mode if active
	if stellar_map and _preview_system_id >= 0:
		stellar_map.clear_preview()
	_preview_system_id = -1
	# Close stellar map if open
	if stellar_map and stellar_map._is_open:
		stellar_map.close()
	# Reset galaxy selection
	_hovered_system = -1
	_is_panning = false
	_pan_velocity = Vector2.ZERO
	# If returning from preview, keep that system selected and center on it
	if was_previewing >= 0 and galaxy:
		_selected_system = was_previewing
		_info_system = galaxy.get_system(was_previewing)
		_info_visible = true
		_resolve_system_data(was_previewing)
		var sys: Dictionary = galaxy.get_system(was_previewing)
		if not sys.is_empty():
			_cam_center = Vector2(sys["x"], sys["y"])
	else:
		_selected_system = -1
		_info_visible = false
		_resolved_data = null
		_resolved_system_id = -1
		_center_galaxy_on_current()
	_galaxy_dirty = true
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
	if stellar_map:
		if _preview_system_id >= 0:
			stellar_map.clear_preview()
		if stellar_map._is_open:
			stellar_map.close()
	_preview_system_id = -1
	_is_panning = false
	_pan_velocity = Vector2.ZERO
	_is_open = false
	visible = false
	_on_closed()
	closed.emit()


func _on_closed() -> void:
	_is_panning = false
	_pan_velocity = Vector2.ZERO


## GUI input fallback — ensures middle mouse pan works even if _input() doesn't catch it.
func _gui_input(event: InputEvent) -> void:
	if current_view != ViewMode.GALAXY:
		super._gui_input(event)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not (_galaxy_fleet_panel and _galaxy_fleet_panel.handle_scroll(event.position, 1)):
				_zoom_at(event.position, ZOOM_STEP)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not (_galaxy_fleet_panel and _galaxy_fleet_panel.handle_scroll(event.position, -1)):
				_zoom_at(event.position, 1.0 / ZOOM_STEP)
			accept_event()
			return
	if event is InputEventMouseMotion and _is_panning:
		_zoom_anchored = false  # Break anchor so drag + zoom coexist
		_cam_center -= event.relative / _cam_zoom
		_galaxy_dirty = true
		accept_event()
		return
	# Consume all other events to prevent game input
	accept_event()


## Override: skip UIScreen transition. Handle galaxy zoom smoothing.
func _process(delta: float) -> void:
	if not _is_open:
		return

	if current_view == ViewMode.GALAXY:
		# --- Smooth WASD pan with acceleration / inertia ---
		var input_dir =Vector2.ZERO
		if Input.is_action_pressed("strafe_right"):
			input_dir.x += 1.0
		if Input.is_action_pressed("strafe_left"):
			input_dir.x -= 1.0
		if Input.is_action_pressed("move_backward"):
			input_dir.y += 1.0
		if Input.is_action_pressed("move_forward"):
			input_dir.y -= 1.0

		if input_dir != Vector2.ZERO:
			var target_vel =input_dir.normalized() * PAN_BASE_SPEED
			_pan_velocity = _pan_velocity.lerp(target_vel, 1.0 - exp(-PAN_ACCEL * delta))
		else:
			_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, 1.0 - exp(-PAN_FRICTION * delta))
			if _pan_velocity.length_squared() < 1.0:
				_pan_velocity = Vector2.ZERO

		if _pan_velocity != Vector2.ZERO:
			# Break zoom anchor so pan + zoom coexist
			_zoom_anchored = false
			# velocity is in screen px/sec → convert to galaxy coords via zoom
			_cam_center += _pan_velocity * delta / maxf(_cam_zoom, 0.01)
			_galaxy_dirty = true

		# Smooth zoom with anchor (keeps point under cursor fixed)
		if not is_equal_approx(_cam_zoom, _cam_target_zoom):
			_cam_zoom = lerpf(_cam_zoom, _cam_target_zoom, delta * ZOOM_SMOOTH)
			if absf(_cam_zoom - _cam_target_zoom) < 0.001:
				_cam_zoom = _cam_target_zoom
			# Recalculate center to keep anchor fixed at its screen position
			if _zoom_anchored:
				var cx: float = size.x * 0.5
				var cy: float = size.y * 0.5
				_cam_center.x = _zoom_anchor_galaxy.x - (_zoom_anchor_screen.x - cx) / _cam_zoom
				_cam_center.y = _zoom_anchor_galaxy.y - (_zoom_anchor_screen.y - cy) / _cam_zoom
			_galaxy_dirty = true
		else:
			_zoom_anchored = false

	# Full opacity, no transition
	modulate.a = 1.0
	# Always redraw while open for real-time updates
	queue_redraw()
	if _galaxy_fleet_panel and _galaxy_fleet_panel.visible:
		_galaxy_fleet_panel.queue_redraw()
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

	var s =size
	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5
	var cy: float = s.y * 0.5

	# Fully opaque background (no 3D scene bleed-through)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 1.0))

	# Title
	_draw_galaxy_title(s, font)

	# Connections
	_draw_connections(cx, cy)

	# Route overlay (on top of connections, below dots)
	_draw_route_path(cx, cy)

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
	var title_text ="GALAXY MAP"
	var vp_left: float = MapLayout.viewport_left()
	var vp_right: float = MapLayout.viewport_right(s.x)
	var vp_w: float = vp_right - vp_left
	var vp_cx: float = vp_left + vp_w * 0.5

	draw_string(font, Vector2(vp_left, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, vp_w, fsize, UITheme.TEXT_HEADER)

	# Decorative lines
	var title_w: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	var line_y: float = title_y - fsize * 0.35
	var half: float = title_w * 0.5 + 20
	var line_len: float = 120.0
	draw_line(Vector2(vp_cx - half - line_len, line_y), Vector2(vp_cx - half, line_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(vp_cx + half, line_y), Vector2(vp_cx + half + line_len, line_y), UITheme.BORDER, 1.0)

	# Separator — spans viewport zone only
	var sep_y: float = title_y + 10
	draw_line(Vector2(vp_left, sep_y), Vector2(vp_right, sep_y), UITheme.BORDER, 1.0)


func _draw_view_indicator() -> void:
	var font =UITheme.get_font()
	var s =size
	var y: float = s.y - 24.0
	var cx: float = s.x * 0.5

	# Background bar
	var bar_w: float = 300.0
	var bar_h: float = 30.0
	var bar_rect =Rect2(cx - bar_w * 0.5, y - bar_h * 0.5, bar_w, bar_h)
	draw_rect(bar_rect, Color(0.0, 0.02, 0.05, 0.85))
	draw_rect(bar_rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cl: float = 8.0
	var cc =UITheme.PRIMARY
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
	var sys_label: String = "SYSTEM"
	var sys_col: Color = UITheme.PRIMARY if current_view == ViewMode.SYSTEM else UITheme.TEXT_DIM
	draw_string(font, Vector2(cx - 75, text_y), sys_label, HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_BODY, sys_col)
	# Underline active
	if current_view == ViewMode.SYSTEM:
		draw_line(Vector2(cx - 75, text_y + 3), Vector2(cx - 10, text_y + 3), sys_col, 2.0)

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
		var a_pos =_galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		for b_id in sys["connections"]:
			var key: String = "%d_%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
			if drawn.has(key):
				continue
			drawn[key] = true
			var b_sys: Dictionary = galaxy.get_system(b_id)
			if b_sys.is_empty():
				continue
			var b_pos =_galaxy_to_screen(b_sys["x"], b_sys["y"], cx, cy)
			var line_color =Color(0.15, 0.4, 0.6, 0.2)
			if a_id == _selected_system or b_id == _selected_system:
				line_color = Color(0.2, 0.7, 1.0, 0.5)
			draw_line(a_pos, b_pos, line_color, CONNECTION_WIDTH)


func _draw_faction_territories(cx: float, cy: float) -> void:
	for sys in galaxy.systems:
		var faction: StringName = sys["faction"]
		var col: Color = FACTION_COLORS.get(faction, FACTION_COLORS[&"neutral"])
		var pos =_galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		var radius: float = 30.0 * _cam_zoom
		draw_circle(pos, radius, col)


func _draw_systems(s: Vector2, cx: float, cy: float, font: Font) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	for sys in galaxy.systems:
		var pos =_galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		# Cull off-screen
		if pos.x < -20 or pos.x > s.x + 20 or pos.y < -20 or pos.y > s.y + 20:
			continue

		var sys_id: int = sys["id"]
		var spectral: String = sys["spectral_class"]
		var base_color: Color = SPECTRAL_COLORS.get(spectral, Color.WHITE)
		var radius: float = DOT_RADIUS
		var draw_col =base_color

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
			var name_col =Color(0.6, 0.8, 0.9, 0.6)
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
	var pos =_galaxy_to_screen(sys["x"], sys["y"], cx, cy)

	# Pulsing ring
	var pulse: float = UITheme.get_pulse(0.8)
	var ring_radius: float = DOT_SELECTED_RADIUS + 4.0 + pulse * 3.0
	var ring_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.5 + pulse * 0.3)
	draw_arc(pos, ring_radius, 0, TAU, 24, ring_col, 2.0)

	# "ICI" marker
	var font: Font = UITheme.get_font()
	draw_string(font, pos + Vector2(-15, -ring_radius - 6), "ICI", HORIZONTAL_ALIGNMENT_CENTER, 30, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


func _draw_route_path(cx: float, cy: float) -> void:
	var rm = GameManager._route_manager
	if rm == null or rm.route.is_empty():
		return

	var pulse: float = UITheme.get_pulse(0.6)
	var route_col =Color(0.0, 0.9, 1.0, 0.6 + pulse * 0.3)
	var completed_col =Color(0.0, 0.6, 0.8, 0.25)

	for i in rm.route.size() - 1:
		var a_id: int = rm.route[i]
		var b_id: int = rm.route[i + 1]
		var a_sys: Dictionary = galaxy.get_system(a_id)
		var b_sys: Dictionary = galaxy.get_system(b_id)
		if a_sys.is_empty() or b_sys.is_empty():
			continue
		var a_pos =_galaxy_to_screen(a_sys["x"], a_sys["y"], cx, cy)
		var b_pos =_galaxy_to_screen(b_sys["x"], b_sys["y"], cx, cy)

		var col: Color = completed_col if i < rm.route_index else route_col
		draw_line(a_pos, b_pos, col, 3.0)

	# Destination marker (pulsing ring on final system)
	if rm.route.size() > 0:
		var dest_id: int = rm.route[rm.route.size() - 1]
		var dest_sys: Dictionary = galaxy.get_system(dest_id)
		if not dest_sys.is_empty():
			var dest_pos =_galaxy_to_screen(dest_sys["x"], dest_sys["y"], cx, cy)
			var ring_r: float = DOT_SELECTED_RADIUS + 6.0 + pulse * 3.0
			draw_arc(dest_pos, ring_r, 0, TAU, 24, Color(1.0, 0.8, 0.0, 0.5 + pulse * 0.3), 2.0)


func _draw_info_panel(s: Vector2, font: Font) -> void:
	var current_id: int = system_transition.current_system_id if system_transition else -1
	var panel_w: float = MapLayout.INFO_PANEL_W
	var panel_x: float = s.x - panel_w - MapLayout.INFO_PANEL_MARGIN
	var panel_y: float = UITheme.MARGIN_SCREEN + 50
	var line_h: float = UITheme.ROW_HEIGHT
	var kv_w: float = panel_w - 28

	# --- Calculate dynamic panel height ---
	var row_count: int = 7  # name + class + faction + danger + station + portals + visited
	var connections: Array = _info_system.get("connections", [])
	if connections.size() > 0 and _cam_zoom > 1.0:
		row_count += 1 + connections.size()  # header + each connection
	# Resolved data rows
	if _resolved_data:
		row_count += 1  # separator
		if _resolved_data.planets.size() > 0:
			row_count += 1  # planet count
		if _resolved_data.stations.size() > 0:
			row_count += _resolved_data.stations.size()  # each station
		if _resolved_data.asteroid_belts.size() > 0:
			row_count += 1  # belt header
			row_count += mini(_resolved_data.asteroid_belts.size(), 5)  # each belt (cap at 5)
	var sys_id: int = _info_system.get("id", -1)
	if sys_id != current_id and sys_id >= 0 and current_id >= 0:
		var cur_sys: Dictionary = galaxy.get_system(current_id)
		if not cur_sys.is_empty() and sys_id in cur_sys["connections"]:
			row_count += 1
		row_count += 1  # Autopilot hint

	var panel_h: float = 50.0 + row_count * line_h
	var rect =Rect2(panel_x, panel_y, panel_w, panel_h)

	# Background + border
	draw_rect(rect, UITheme.BG_PANEL)
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cl: float = 10.0
	var cc =MapColors.CORNER
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x + cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x, panel_y + cl), cc, 1.5)
	draw_line(Vector2(panel_x + panel_w, panel_y), Vector2(panel_x + panel_w - cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x + panel_w, panel_y), Vector2(panel_x + panel_w, panel_y + cl), cc, 1.5)

	var x: float = panel_x + 14
	var y: float = panel_y + 24

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
	_draw_kv(font, x, y, kv_w, "PORTAILS", str(connections.size()))
	y += line_h

	# Visited
	var visited: bool = system_transition != null and system_transition.has_visited(sys_id)
	_draw_kv(font, x, y, kv_w, "VISITE", "Oui" if visited or sys_id == current_id else "Non")
	y += line_h

	# Fleet ships in this system
	if GameManager.player_fleet:
		var fleet_indices =GameManager.player_fleet.get_ships_in_system(sys_id)
		if not fleet_indices.is_empty():
			var docked_count: int = 0
			var deployed_count: int = 0
			for fi in fleet_indices:
				var fs =GameManager.player_fleet.ships[fi]
				if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
					docked_count += 1
				elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
					deployed_count += 1
			var fleet_text: String = ""
			if docked_count > 0:
				fleet_text += "%d docke%s" % [docked_count, "s" if docked_count > 1 else ""]
			if deployed_count > 0:
				if fleet_text != "":
					fleet_text += ", "
				fleet_text += "%d deploye%s" % [deployed_count, "s" if deployed_count > 1 else ""]
			_draw_kv(font, x, y, kv_w, "FLOTTE", fleet_text)
			y += line_h

	# --- Resolved StarSystemData details ---
	if _resolved_data:
		y += 4
		draw_line(Vector2(x, y), Vector2(panel_x + panel_w - 14, y), UITheme.BORDER, 1.0)
		y += line_h

		# Planets
		if _resolved_data.planets.size() > 0:
			var planet_types: Dictionary = {}
			for pd in _resolved_data.planets:
				var pt: String = pd.get_type_string()
				planet_types[pt] = planet_types.get(pt, 0) + 1
			var parts: Array[String] = []
			for pt_name in planet_types:
				parts.append("%d %s" % [planet_types[pt_name], _planet_type_short(pt_name)])
			_draw_kv(font, x, y, kv_w, "PLANÈTES", "%d  (%s)" % [_resolved_data.planets.size(), ", ".join(parts)])
			y += line_h

		# Stations with types
		if _resolved_data.stations.size() > 0:
			for sd in _resolved_data.stations:
				var type_label: String = _station_type_label(sd.get_type_string())
				_draw_kv(font, x, y, kv_w, "STATION", "%s  [%s]" % [sd.station_name, type_label])
				y += line_h

		# Asteroid belts with resources
		if _resolved_data.asteroid_belts.size() > 0:
			draw_string(font, Vector2(x, y), "Ceintures d'astéroides: %d" % _resolved_data.asteroid_belts.size(), HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
			y += line_h - 2
			var belt_count: int = 0
			for bd in _resolved_data.asteroid_belts:
				if belt_count >= 5:
					break
				var res_label: String = _resource_short(String(bd.dominant_resource))
				if bd.secondary_resource != &"":
					res_label += " + " + _resource_short(String(bd.secondary_resource))
				draw_string(font, Vector2(x + 8, y), "%s  [%s]" % [bd.belt_name, res_label], HORIZONTAL_ALIGNMENT_LEFT, kv_w - 8, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
				y += line_h - 2
				belt_count += 1

	# Connected system names
	if connections.size() > 0 and _cam_zoom > 1.0:
		y += 4
		draw_string(font, Vector2(x, y), "Connexions:", HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		y += 14
		for conn_id in connections:
			var conn_name: String = galaxy.get_system_name(conn_id)
			if conn_name != "":
				var conn_col =UITheme.LABEL_VALUE
				if conn_id == current_id:
					conn_col = UITheme.PRIMARY
				draw_string(font, Vector2(x + 8, y), conn_name, HORIZONTAL_ALIGNMENT_LEFT, kv_w - 8, UITheme.FONT_SIZE_SMALL, conn_col)
				y += 13

	# Action hints
	if sys_id != current_id and sys_id >= 0 and current_id >= 0:
		var cur_sys: Dictionary = galaxy.get_system(current_id)
		if not cur_sys.is_empty() and sys_id in cur_sys["connections"]:
			y += 4
			draw_string(font, Vector2(x, y), "Rejoignez le portail pour sauter", HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)
			y += line_h
		# Autopilot hint
		y += 4
		draw_string(font, Vector2(x, y), "[ENTRER] = Autopilote", HORIZONTAL_ALIGNMENT_LEFT, kv_w, UITheme.FONT_SIZE_SMALL, UITheme.PRIMARY)


func _draw_kv(font: Font, x: float, y: float, w: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, UITheme.FONT_SIZE_BODY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(x + w * 0.4, y), value, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, UITheme.FONT_SIZE_BODY, UITheme.LABEL_VALUE)


func _planet_type_short(pt: String) -> String:
	match pt:
		"rocky": return "Roc."
		"lava": return "Volc."
		"ocean": return "Océan."
		"gas_giant": return "Géante"
		"ice": return "Glace"
	return pt


func _station_type_label(stype: String) -> String:
	match stype:
		"repair": return "Réparation"
		"trade": return "Commerce"
		"military": return "Militaire"
		"mining": return "Extraction"
	return stype.capitalize()


func _resource_short(res_id: String) -> String:
	match res_id:
		"ice": return "Glace"
		"iron": return "Fer"
		"copper": return "Cuivre"
		"titanium": return "Titane"
		"gold": return "Or"
		"crystal": return "Cristal"
		"uranium": return "Uranium"
		"platinum": return "Platine"
	return res_id.capitalize()


func _draw_galaxy_legend(s: Vector2, font: Font) -> void:
	var vp_left: float = MapLayout.viewport_left()
	var y: float = s.y - UITheme.MARGIN_SCREEN - 80

	draw_string(font, Vector2(vp_left, y), "Click = Selectionner | Double-clic = Voir systeme | Entrer = Autopilote | Scroll = Zoom | MMB = Deplacer", HORIZONTAL_ALIGNMENT_LEFT, 900, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	y += 14

	# Spectral class legend
	var legend_x: float = vp_left
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
	draw_string(font, Vector2(MapLayout.viewport_left(), s.y - UITheme.MARGIN_SCREEN - 50), label, HORIZONTAL_ALIGNMENT_LEFT, 500, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


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
		# Enter → start route to selected system
		if event.physical_keycode == KEY_ENTER and _selected_system >= 0:
			_start_route_to_selected()
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

	# Mouse zoom (route through fleet panel first)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _galaxy_fleet_panel and _galaxy_fleet_panel.handle_scroll(event.position, 1):
				get_viewport().set_input_as_handled()
				return
			_zoom_at(event.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _galaxy_fleet_panel and _galaxy_fleet_panel.handle_scroll(event.position, -1):
				get_viewport().set_input_as_handled()
				return
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return

		# Pan with middle mouse
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			get_viewport().set_input_as_handled()
			return

		# Click - route through fleet panel first, then galaxy selection
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _galaxy_fleet_panel and _galaxy_fleet_panel.handle_click(event.position):
				get_viewport().set_input_as_handled()
				return
			_handle_click(event.position)
			get_viewport().set_input_as_handled()
			return

		# Right-click on system → start galaxy route (autopilot gate-to-gate)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hit_sys: int = _get_system_at(event.position)
			if hit_sys >= 0:
				_selected_system = hit_sys
				_info_system = galaxy.get_system(hit_sys)
				_info_visible = true
				_resolve_system_data(hit_sys)
				_galaxy_dirty = true
				_start_route_to_selected()
			else:
				_center_galaxy_on_current()
			get_viewport().set_input_as_handled()
			return

	# Mouse motion
	if event is InputEventMouseMotion:
		if _is_panning:
			_zoom_anchored = false  # Break anchor so drag + zoom coexist
			_cam_center -= event.relative / _cam_zoom
			_galaxy_dirty = true
		else:
			var old_hover =_hovered_system
			_update_hover(event.position)
			if _hovered_system != old_hover:
				_galaxy_dirty = true
		get_viewport().set_input_as_handled()
		return


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	# Record anchor: galaxy point under cursor must stay fixed during smooth zoom
	_zoom_anchor_galaxy = _screen_to_galaxy(screen_pos.x, screen_pos.y, cx, cy)
	_zoom_anchor_screen = screen_pos
	_zoom_anchored = true
	_cam_target_zoom = clampf(_cam_target_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_galaxy_dirty = true


func _update_hover(screen_pos: Vector2) -> void:
	_hovered_system = _get_system_at(screen_pos)


func _handle_click(screen_pos: Vector2) -> void:
	var hit: int = _get_system_at(screen_pos)
	var now: float = Time.get_ticks_msec() / 1000.0

	if hit >= 0:
		# Double-click detection: same system within 0.4s → open preview
		if hit == _last_galaxy_click_id and (now - _last_galaxy_click_time) < 0.4:
			_last_galaxy_click_id = -1
			_open_system_preview(hit)
			return

		_last_galaxy_click_id = hit
		_last_galaxy_click_time = now
		_selected_system = hit
		_info_system = galaxy.get_system(hit)
		_info_visible = true
		_resolve_system_data(hit)
	else:
		_last_galaxy_click_id = -1
		_selected_system = -1
		_info_visible = false
		_resolved_data = null
		_resolved_system_id = -1
	_galaxy_dirty = true


func _resolve_system_data(system_id: int) -> void:
	if system_id == _resolved_system_id and _resolved_data != null:
		return
	# Check override first
	var override =SystemDataRegistry.get_override(system_id)
	if override:
		_resolved_data = override
		_resolved_system_id = system_id
		return
	# Generate from seed
	var sys: Dictionary = galaxy.get_system(system_id)
	if sys.is_empty():
		_resolved_data = null
		_resolved_system_id = -1
		return
	var origin_x: float = sys.get("x", 0.0)
	var origin_y: float = sys.get("y", 0.0)
	var connections: Array[Dictionary] = []
	for conn_id in sys["connections"]:
		var conn_sys: Dictionary = galaxy.get_system(conn_id)
		if not conn_sys.is_empty():
			connections.append({
				"target_id": conn_id,
				"target_name": conn_sys["name"],
				"origin_x": origin_x,
				"origin_y": origin_y,
				"target_x": conn_sys.get("x", 0.0),
				"target_y": conn_sys.get("y", 0.0),
			})
	_resolved_data = SystemGenerator.generate(sys["seed"], connections)
	_resolved_data.system_name = sys["name"]
	_resolved_data.star_name = sys["name"]
	_resolved_system_id = system_id


func _open_system_preview(system_id: int) -> void:
	# Resolve data if not already cached
	_resolve_system_data(system_id)
	if _resolved_data == null:
		return
	var sys: Dictionary = galaxy.get_system(system_id)
	if sys.is_empty():
		return

	_preview_system_id = system_id
	var preview_ents: Dictionary = _build_preview_entities(_resolved_data, sys)
	var sys_name: String = sys.get("name", "Unknown")

	if stellar_map:
		stellar_map.set_preview(preview_ents, sys_name)

	# Switch to system view
	switch_to_view(ViewMode.SYSTEM)


func _build_preview_entities(data: StarSystemData, _sys: Dictionary) -> Dictionary:
	var entities: Dictionary = {}

	# Star at origin
	var star_id ="star_0"
	entities[star_id] = {
		"id": star_id,
		"name": data.star_name,
		"type": EntityRegistrySystem.EntityType.STAR,
		"pos_x": 0.0, "pos_y": 0.0, "pos_z": 0.0,
		"vel_x": 0.0, "vel_y": 0.0, "vel_z": 0.0,
		"node": null,
		"orbital_radius": 0.0,
		"orbital_period": 0.0,
		"orbital_angle": 0.0,
		"orbital_parent": "",
		"radius": data.star_radius,
		"color": data.star_color,
		"extra": {
			"spectral_class": data.star_spectral_class,
			"temperature": data.star_temperature,
			"luminosity": data.star_luminosity,
		},
	}

	# Planets
	for i in data.planets.size():
		var pd: PlanetData = data.planets[i]
		var ent_id ="planet_%d" % i
		var angle: float = EntityRegistrySystem.compute_orbital_angle(pd.orbital_angle, pd.orbital_period)
		var px: float = cos(angle) * pd.orbital_radius
		var pz: float = sin(angle) * pd.orbital_radius
		entities[ent_id] = {
			"id": ent_id,
			"name": pd.planet_name,
			"type": EntityRegistrySystem.EntityType.PLANET,
			"pos_x": px, "pos_y": 0.0, "pos_z": pz,
			"vel_x": 0.0, "vel_y": 0.0, "vel_z": 0.0,
			"node": null,
			"orbital_radius": pd.orbital_radius,
			"orbital_period": pd.orbital_period,
			"orbital_angle": angle,
			"orbital_parent": star_id,
			"radius": pd.radius,
			"color": pd.color,
			"extra": {
				"planet_type": pd.get_type_string(),
				"has_rings": pd.has_rings,
			},
		}

	# Stations
	for i in data.stations.size():
		var sd: StationData = data.stations[i]
		var ent_id ="station_%d" % i
		var angle: float = EntityRegistrySystem.compute_orbital_angle(sd.orbital_angle, sd.orbital_period)
		var sx: float = cos(angle) * sd.orbital_radius
		var sz: float = sin(angle) * sd.orbital_radius
		entities[ent_id] = {
			"id": ent_id,
			"name": sd.station_name,
			"type": EntityRegistrySystem.EntityType.STATION,
			"pos_x": sx, "pos_y": 0.0, "pos_z": sz,
			"vel_x": 0.0, "vel_y": 0.0, "vel_z": 0.0,
			"node": null,
			"orbital_radius": sd.orbital_radius,
			"orbital_period": sd.orbital_period,
			"orbital_angle": angle,
			"orbital_parent": star_id,
			"radius": 100.0,
			"color": MapColors.STATION_TEAL,
			"extra": {
				"station_type": sd.get_type_string(),
			},
		}

	# Asteroid belts
	for i in data.asteroid_belts.size():
		var bd: AsteroidBeltData = data.asteroid_belts[i]
		var ent_id ="asteroid_belt_%d" % i
		entities[ent_id] = {
			"id": ent_id,
			"name": bd.belt_name,
			"type": EntityRegistrySystem.EntityType.ASTEROID_BELT,
			"pos_x": 0.0, "pos_y": 0.0, "pos_z": 0.0,
			"vel_x": 0.0, "vel_y": 0.0, "vel_z": 0.0,
			"node": null,
			"orbital_radius": bd.orbital_radius,
			"orbital_period": 0.0,
			"orbital_angle": 0.0,
			"orbital_parent": star_id,
			"radius": bd.width,
			"color": MapColors.ASTEROID_BELT,
			"extra": {
				"width": bd.width,
				"dominant_resource": String(bd.dominant_resource),
				"secondary_resource": String(bd.secondary_resource),
				"rare_resource": String(bd.rare_resource),
				"zone": bd.zone,
				"asteroid_count": bd.asteroid_count,
			},
		}

	# Jump gates
	for i in data.jump_gates.size():
		var gd: JumpGateData = data.jump_gates[i]
		var ent_id ="jump_gate_%d" % i
		entities[ent_id] = {
			"id": ent_id,
			"name": gd.gate_name,
			"type": EntityRegistrySystem.EntityType.JUMP_GATE,
			"pos_x": gd.pos_x, "pos_y": gd.pos_y, "pos_z": gd.pos_z,
			"vel_x": 0.0, "vel_y": 0.0, "vel_z": 0.0,
			"node": null,
			"orbital_radius": 0.0,
			"orbital_period": 0.0,
			"orbital_angle": 0.0,
			"orbital_parent": "",
			"radius": 55.0,
			"color": Color(0.15, 0.6, 1.0, 0.9),
			"extra": {
				"target_system_id": gd.target_system_id,
				"target_system_name": gd.target_system_name,
			},
		}

	return entities


func _get_system_at(screen_pos: Vector2) -> int:
	if galaxy == null:
		return -1
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var best_id: int = -1
	var best_dist: float = HIT_RADIUS
	for sys in galaxy.systems:
		var pos =_galaxy_to_screen(sys["x"], sys["y"], cx, cy)
		var dist: float = screen_pos.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_id = sys["id"]
	return best_id


func _start_route_to_selected() -> void:
	if _selected_system < 0:
		return
	GameManager.start_galaxy_route(_selected_system)
	# Close the map
	close()


func set_fleet(fleet, gal) -> void:
	if _galaxy_fleet_panel:
		_galaxy_fleet_panel.set_fleet(fleet)
		_galaxy_fleet_panel.set_galaxy(gal)


func _on_galaxy_fleet_ship_selected(_fleet_index: int, system_id: int) -> void:
	# Center galaxy camera on the ship's system
	if galaxy == null or system_id < 0:
		return
	var sys: Dictionary = galaxy.get_system(system_id)
	if sys.is_empty():
		return
	_cam_center = Vector2(sys["x"], sys["y"])
	_selected_system = system_id
	_info_system = sys
	_info_visible = true
	_resolve_system_data(system_id)
	_galaxy_dirty = true
