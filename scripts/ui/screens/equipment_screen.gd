class_name EquipmentScreen
extends UIScreen

# =============================================================================
# Equipment Screen - 3D Ship Viewer + Category Tabs + Sidebar Arsenal
# Holographic AAA-style (Star Citizen / Elite Dangerous)
# Left: SubViewport with orbiting 3D ship model + hardpoint markers
# Right: Category tabs, arsenal list, comparison panel, action buttons
# =============================================================================

signal equipment_closed

var player_inventory: PlayerInventory = null
var weapon_manager: WeaponManager = null

# --- 3D Viewer ---
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _viewer_camera: Camera3D = null
var _ship_model: ShipModel = null
var _ship_model_path: String = "res://assets/models/tie.glb"
var _ship_model_scale: float = 1.0
var _hp_markers: Array[Dictionary] = []  # {mesh: MeshInstance3D, body: StaticBody3D, index: int}

# --- Orbit Camera ---
var orbit_yaw: float = 30.0
var orbit_pitch: float = -15.0
var orbit_distance: float = 8.0
const ORBIT_MIN_DIST := 3.0
const ORBIT_MAX_DIST := 15.0
const ORBIT_PITCH_MIN := -80.0
const ORBIT_PITCH_MAX := 80.0
const ORBIT_SENSITIVITY := 0.3
const AUTO_ROTATE_SPEED := 6.0  # degrees/sec
const AUTO_ROTATE_DELAY := 3.0  # seconds before auto-rotate starts
var _orbit_dragging: bool = false
var _last_input_time: float = 0.0

# --- Selection State ---
var _selected_hardpoint: int = -1
var _selected_weapon: StringName = &""
var _pulse_time: float = 0.0

# --- Category Tabs ---
var _tab_bar: UITabBar = null
var _current_tab: int = 0
const TAB_NAMES: Array[String] = ["ARMEMENT", "MODULES", "BOUCLIERS", "MOTEURS"]

# --- UI Controls ---
var _arsenal_list: UIScrollList = null
var _arsenal_items: Array[StringName] = []
var _equip_btn: UIButton = null
var _remove_btn: UIButton = null
var _back_btn: UIButton = null

# --- Layout constants ---
const VIEWER_RATIO := 0.55
const SIDEBAR_RATIO := 0.45
const CONTENT_TOP := 65.0
const TAB_H := 30.0
const HP_STRIP_H := 60.0
const COMPARE_H := 170.0
const BTN_W := 140.0
const BTN_H := 38.0
const ARSENAL_ROW_H := 56.0
const SIZE_BADGE_W := 30.0
const SIZE_BADGE_H := 22.0

# Weapon type colors
const TYPE_COLORS := {
	0: Color(0.3, 0.7, 1.0, 0.9),    # LASER - cyan blue
	1: Color(1.0, 0.45, 0.15, 0.9),   # PLASMA - orange
	2: Color(1.0, 0.3, 0.3, 0.9),     # MISSILE - red
	3: Color(0.85, 0.85, 1.0, 0.9),   # RAILGUN - white-blue
	4: Color(0.7, 1.0, 0.3, 0.9),     # MINE - green-yellow
}
const TYPE_NAMES := ["LASER", "PLASMA", "MISSILE", "RAILGUN", "MINE"]


func _ready() -> void:
	screen_title = "EQUIPEMENT DU VAISSEAU"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Tab bar (created early, positioned in _layout_controls)
	_tab_bar = UITabBar.new()
	_tab_bar.tabs = TAB_NAMES
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.visible = false
	add_child(_tab_bar)

	# Arsenal scroll list
	_arsenal_list = UIScrollList.new()
	_arsenal_list.row_height = ARSENAL_ROW_H
	_arsenal_list.item_draw_callback = _draw_arsenal_row
	_arsenal_list.item_selected.connect(_on_arsenal_selected)
	_arsenal_list.visible = false
	add_child(_arsenal_list)

	# Action buttons
	_equip_btn = UIButton.new()
	_equip_btn.text = "EQUIPER"
	_equip_btn.enabled = false
	_equip_btn.visible = false
	_equip_btn.pressed.connect(_on_equip_pressed)
	add_child(_equip_btn)

	_remove_btn = UIButton.new()
	_remove_btn.text = "RETIRER"
	_remove_btn.enabled = false
	_remove_btn.visible = false
	_remove_btn.pressed.connect(_on_remove_pressed)
	add_child(_remove_btn)

	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.WARNING
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)


func setup_ship_viewer(model_path: String, model_scale: float) -> void:
	_ship_model_path = model_path
	_ship_model_scale = model_scale


# =============================================================================
# OPEN / CLOSE
# =============================================================================
func _on_opened() -> void:
	_selected_hardpoint = -1
	_selected_weapon = &""
	_current_tab = 0
	_last_input_time = 0.0
	orbit_yaw = 30.0
	orbit_pitch = -15.0
	orbit_distance = 8.0

	if _tab_bar:
		_tab_bar.current_tab = 0

	_setup_3d_viewer()
	_refresh_arsenal()
	_layout_controls()

	_tab_bar.visible = true
	_arsenal_list.visible = (_current_tab == 0)
	_equip_btn.visible = true
	_remove_btn.visible = true
	_back_btn.visible = true
	_update_button_states()


func _on_closed() -> void:
	_cleanup_3d_viewer()
	_tab_bar.visible = false
	_arsenal_list.visible = false
	_equip_btn.visible = false
	_remove_btn.visible = false
	_back_btn.visible = false
	equipment_closed.emit()


# =============================================================================
# 3D VIEWER SETUP
# =============================================================================
func _setup_3d_viewer() -> void:
	_cleanup_3d_viewer()

	# SubViewportContainer (left portion of the screen)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_viewport_container)

	# SubViewport
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	# WorldEnvironment for the viewer
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_color = Color(0.15, 0.2, 0.25)
	env.ambient_light_energy = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	# 3-point lighting
	# Key light: warm white, 45 degrees down-right
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.95, 0.9)
	key_light.light_energy = 1.2
	key_light.rotation_degrees = Vector3(-45, 30, 0)
	_viewport.add_child(key_light)

	# Fill light: soft cool, positioned left-front
	var fill_light := OmniLight3D.new()
	fill_light.light_color = Color(0.8, 0.85, 0.9)
	fill_light.light_energy = 0.6
	fill_light.omni_range = 30.0
	fill_light.position = Vector3(-6, 2, -4)
	_viewport.add_child(fill_light)

	# Rim light: cyan holographic tint, behind-right
	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b)
	rim_light.light_energy = 0.4
	rim_light.omni_range = 30.0
	rim_light.position = Vector3(5, 1, 5)
	_viewport.add_child(rim_light)

	# Camera
	_viewer_camera = Camera3D.new()
	_viewer_camera.fov = 40.0
	_viewer_camera.near = 0.1
	_viewer_camera.far = 100.0
	_viewport.add_child(_viewer_camera)

	# Ship model
	_ship_model = ShipModel.new()
	_ship_model.model_path = _ship_model_path
	_ship_model.model_scale = _ship_model_scale
	_ship_model.engine_light_color = Color(0.3, 0.5, 1.0)
	_viewport.add_child(_ship_model)

	# Create hardpoint markers
	_create_hardpoint_markers()

	# Update camera position
	_update_orbit_camera()


func _cleanup_3d_viewer() -> void:
	_hp_markers.clear()
	if _viewport_container:
		_viewport_container.queue_free()
		_viewport_container = null
		_viewport = null
		_viewer_camera = null
		_ship_model = null


func _create_hardpoint_markers() -> void:
	_hp_markers.clear()
	if weapon_manager == null or _viewport == null:
		return

	for i in weapon_manager.hardpoints.size():
		var hp := weapon_manager.hardpoints[i]

		# Visual sphere
		var mesh_inst := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.15 * _ship_model_scale
		sphere.height = 0.3 * _ship_model_scale
		sphere.radial_segments = 12
		sphere.rings = 6
		mesh_inst.mesh = sphere

		# Material (will be updated in _update_marker_visuals)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.3)
		mat.emission_enabled = false
		mesh_inst.material_override = mat
		mesh_inst.position = hp.position * _ship_model_scale
		_viewport.add_child(mesh_inst)

		# Collision body for raycasting
		var body := StaticBody3D.new()
		body.position = hp.position * _ship_model_scale
		var col_shape := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3 * _ship_model_scale
		col_shape.shape = shape
		body.add_child(col_shape)
		body.set_meta("hp_index", i)
		_viewport.add_child(body)

		_hp_markers.append({mesh = mesh_inst, body = body, index = i})

	_update_marker_visuals()


func _update_marker_visuals() -> void:
	for marker in _hp_markers:
		var idx: int = marker.index
		var mesh: MeshInstance3D = marker.mesh
		var mat: StandardMaterial3D = mesh.material_override

		if idx >= weapon_manager.hardpoints.size():
			continue

		var hp := weapon_manager.hardpoints[idx]

		if idx == _selected_hardpoint:
			# Selected: pulsing emission
			var type_col := _get_hp_marker_color(hp)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			var pulse := 1.0 + sin(_pulse_time * 4.0) * 0.5
			mat.emission_energy_multiplier = pulse
		elif hp.mounted_weapon:
			# Equipped: weapon type color, subtle emission
			var type_col := _get_hp_marker_color(hp)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			mat.emission_energy_multiplier = 0.5
		else:
			# Empty: dim gray
			mat.albedo_color = Color(0.3, 0.3, 0.3)
			mat.emission_enabled = false


func _get_hp_marker_color(hp: Hardpoint) -> Color:
	if hp.mounted_weapon:
		return TYPE_COLORS.get(hp.mounted_weapon.weapon_type, UITheme.PRIMARY)
	return UITheme.PRIMARY


# =============================================================================
# ORBIT CAMERA
# =============================================================================
func _update_orbit_camera() -> void:
	if _viewer_camera == null:
		return
	var yaw_rad := deg_to_rad(orbit_yaw)
	var pitch_rad := deg_to_rad(orbit_pitch)
	var pos := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * orbit_distance
	_viewer_camera.position = pos
	_viewer_camera.look_at(Vector3.ZERO)


# =============================================================================
# PROCESS
# =============================================================================
func _process(delta: float) -> void:
	super._process(delta)
	_pulse_time += delta
	_last_input_time += delta

	if not _is_open:
		return

	# Auto-rotate when idle
	if not _orbit_dragging and _last_input_time > AUTO_ROTATE_DELAY:
		orbit_yaw += AUTO_ROTATE_SPEED * delta
		_update_orbit_camera()

	# Update hardpoint marker visuals (for pulse animation)
	if _selected_hardpoint >= 0 and weapon_manager:
		_update_marker_visuals()


# =============================================================================
# INPUT
# =============================================================================
func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		accept_event()
		return

	# Close button [X]
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var close_x := size.x - UITheme.MARGIN_SCREEN - 28
		var close_y := UITheme.MARGIN_SCREEN
		var close_rect := Rect2(close_x, close_y, 32, 28)
		if close_rect.has_point(event.position):
			close()
			accept_event()
			return

	var viewer_w := size.x * VIEWER_RATIO
	var in_viewer: bool = false
	if "position" in event:
		in_viewer = event.position.x < viewer_w and event.position.y > CONTENT_TOP

	# Mouse button events in viewer area
	if event is InputEventMouseButton and in_viewer:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_orbit_dragging = true
				_last_input_time = 0.0
			else:
				if _orbit_dragging:
					_orbit_dragging = false
					# Check for click (not drag) on hardpoint marker
					_try_select_marker(event.position)
			accept_event()
			return

		# Scroll wheel for zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(ORBIT_MIN_DIST, orbit_distance - 0.5)
			_last_input_time = 0.0
			_update_orbit_camera()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(ORBIT_MAX_DIST, orbit_distance + 0.5)
			_last_input_time = 0.0
			_update_orbit_camera()
			accept_event()
			return

	# Mouse motion for orbit drag
	if event is InputEventMouseMotion and _orbit_dragging:
		orbit_yaw += event.relative.x * ORBIT_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch - event.relative.y * ORBIT_SENSITIVITY, ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
		_last_input_time = 0.0
		_update_orbit_camera()
		accept_event()
		return

	# Hardpoint strip clicks
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _try_click_hp_strip(event.position):
			accept_event()
			return

	# Consume all input
	accept_event()


var _drag_start_pos: Vector2 = Vector2.ZERO

func _try_select_marker(mouse_pos: Vector2) -> void:
	if _viewport == null or _viewer_camera == null or weapon_manager == null:
		return

	# Convert screen position to viewport-local position
	var viewer_w := size.x * VIEWER_RATIO
	var viewer_h := size.y - CONTENT_TOP - HP_STRIP_H - 20
	if viewer_w <= 0 or viewer_h <= 0:
		return

	var local_x := mouse_pos.x / viewer_w
	var local_y := (mouse_pos.y - CONTENT_TOP) / viewer_h
	if local_x < 0 or local_x > 1 or local_y < 0 or local_y > 1:
		return

	# Raycast in the SubViewport's physics space
	var vp_size := _viewport.size
	var vp_pos := Vector2(local_x * vp_size.x, local_y * vp_size.y)
	var from := _viewer_camera.project_ray_origin(vp_pos)
	var dir := _viewer_camera.project_ray_normal(vp_pos)

	var space := _viewport.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result and result.collider:
		var collider := result.collider as Node3D
		if collider.has_meta("hp_index"):
			var idx: int = collider.get_meta("hp_index")
			_select_hardpoint(idx)
			return

	# Clicked empty space in viewer — deselect hardpoint
	_select_hardpoint(-1)


func _try_click_hp_strip(mouse_pos: Vector2) -> bool:
	if weapon_manager == null:
		return false

	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	if not strip_rect.has_point(mouse_pos):
		return false

	var hp_count := weapon_manager.hardpoints.size()
	if hp_count == 0:
		return false

	var card_w := minf(120.0, (strip_rect.size.x - 8) / hp_count)
	var total_w := card_w * hp_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5

	for i in hp_count:
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, strip_rect.position.y, card_w - 4, strip_rect.size.y)
		if card_rect.has_point(mouse_pos):
			_select_hardpoint(i)
			return true

	return false


func _select_hardpoint(idx: int) -> void:
	_selected_hardpoint = idx
	_selected_weapon = &""
	if _arsenal_list:
		_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	queue_redraw()


# =============================================================================
# LAYOUT
# =============================================================================
func _layout_controls() -> void:
	var s := size
	var viewer_w := s.x * VIEWER_RATIO
	var sidebar_x := viewer_w
	var sidebar_w := s.x * SIDEBAR_RATIO
	var sidebar_pad := 16.0

	# SubViewport container
	if _viewport_container:
		_viewport_container.position = Vector2(0, CONTENT_TOP)
		_viewport_container.size = Vector2(viewer_w, s.y - CONTENT_TOP - HP_STRIP_H - 20)
		if _viewport:
			_viewport.size = Vector2i(int(viewer_w), int(s.y - CONTENT_TOP - HP_STRIP_H - 20))

	# Tab bar
	_tab_bar.position = Vector2(sidebar_x + sidebar_pad, CONTENT_TOP + 4)
	_tab_bar.size = Vector2(sidebar_w - sidebar_pad * 2, TAB_H)

	# Arsenal list
	var list_top := CONTENT_TOP + TAB_H + 36
	var list_bottom := s.y - COMPARE_H - 90
	_arsenal_list.position = Vector2(sidebar_x + sidebar_pad + 4, list_top)
	_arsenal_list.size = Vector2(sidebar_w - sidebar_pad * 2 - 8, list_bottom - list_top)

	# Buttons
	var btn_y := s.y - 55
	var btn_total := BTN_W * 3 + 20
	var btn_x := sidebar_x + (sidebar_w - btn_total) * 0.5
	_equip_btn.position = Vector2(btn_x, btn_y)
	_equip_btn.size = Vector2(BTN_W, BTN_H)
	_remove_btn.position = Vector2(btn_x + BTN_W + 10, btn_y)
	_remove_btn.size = Vector2(BTN_W, BTN_H)
	_back_btn.position = Vector2(btn_x + (BTN_W + 10) * 2, btn_y)
	_back_btn.size = Vector2(BTN_W, BTN_H)


# =============================================================================
# DRAW
# =============================================================================
func _draw() -> void:
	var s := size
	# Semi-transparent bg (hangar visible)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.55))

	# Top/bottom vignette bars
	draw_rect(Rect2(0, 0, s.x, 44), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 34, s.x, 34), Color(0.0, 0.0, 0.02, 0.5))

	_draw_title(s)

	if not _is_open:
		return

	var font: Font = UITheme.get_font()
	var viewer_w := s.x * VIEWER_RATIO
	var sidebar_x := viewer_w
	var sidebar_w := s.x * SIDEBAR_RATIO
	var sidebar_pad := 16.0

	# --- Viewer divider line ---
	draw_line(Vector2(viewer_w, CONTENT_TOP), Vector2(viewer_w, s.y - 40), UITheme.BORDER, 1.0)

	# --- Hardpoint strip (below 3D viewer) ---
	_draw_hardpoint_strip(font, s)

	# --- 2D projected labels on viewer ---
	_draw_projected_labels(font, viewer_w, s.y - CONTENT_TOP - HP_STRIP_H - 20)

	# --- Sidebar background ---
	var sb_rect := Rect2(sidebar_x + sidebar_pad - 2, CONTENT_TOP + TAB_H + 32,
		sidebar_w - sidebar_pad * 2 + 4, s.y - CONTENT_TOP - TAB_H - 32 - 70)
	draw_panel_bg(sb_rect)

	# --- Arsenal header ---
	var header_y := CONTENT_TOP + TAB_H + 10
	if _current_tab == 0:
		draw_section_header(sidebar_x + sidebar_pad + 4, header_y, sidebar_w - sidebar_pad * 2 - 8, "ARSENAL")
		# Inventory count
		if player_inventory:
			var total := 0
			for wn in player_inventory.get_all_weapons():
				total += player_inventory.get_weapon_count(wn)
			var inv_str := "%d en stock" % total
			draw_string(font, Vector2(sidebar_x + sidebar_w - sidebar_pad - 4, header_y + 11),
				inv_str, HORIZONTAL_ALIGNMENT_RIGHT, sidebar_w * 0.4, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	else:
		draw_section_header(sidebar_x + sidebar_pad + 4, header_y, sidebar_w - sidebar_pad * 2 - 8, TAB_NAMES[_current_tab])

	# --- Placeholder for non-weapon tabs ---
	if _current_tab != 0:
		_draw_placeholder(font, sidebar_x, sidebar_w, s)

	# --- Comparison panel ---
	var compare_y := s.y - COMPARE_H - 65
	var compare_rect := Rect2(sidebar_x + sidebar_pad - 2, compare_y,
		sidebar_w - sidebar_pad * 2 + 4, COMPARE_H)
	draw_panel_bg(compare_rect)
	var cmp_header_y := draw_section_header(sidebar_x + sidebar_pad + 4, compare_y + 5,
		sidebar_w - sidebar_pad * 2 - 8, "COMPARAISON")
	_draw_comparison(font, sidebar_x + sidebar_pad, cmp_header_y, sidebar_w - sidebar_pad * 2)

	# --- Button separator ---
	var btn_sep_y := s.y - 68
	draw_line(Vector2(sidebar_x + sidebar_pad, btn_sep_y),
		Vector2(sidebar_x + sidebar_w - sidebar_pad, btn_sep_y), UITheme.BORDER, 1.0)

	# --- Corner decorations (outer frame) ---
	var m := 28.0
	var cl := 28.0
	var cc := UITheme.CORNER
	draw_line(Vector2(m, m), Vector2(m + cl, m), cc, 1.5)
	draw_line(Vector2(m, m), Vector2(m, m + cl), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), cc, 1.5)

	# Scanline
	var scan_y := fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


# =============================================================================
# HARDPOINT STRIP (below 3D viewer)
# =============================================================================
func _draw_hardpoint_strip(font: Font, s: Vector2) -> void:
	if weapon_manager == null:
		return

	var viewer_w := s.x * VIEWER_RATIO
	var strip_y := s.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	# Strip background
	draw_panel_bg(strip_rect)
	draw_section_header(28, strip_y + 2, viewer_w - 56, "POINTS D'EMPORT")

	var hp_count := weapon_manager.hardpoints.size()
	if hp_count == 0:
		return

	var card_w := minf(120.0, (strip_rect.size.x - 16) / hp_count)
	var total_w := card_w * hp_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y := strip_y + 20

	for i in hp_count:
		var hp := weapon_manager.hardpoints[i]
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, card_y, card_w - 4, HP_STRIP_H - 24)

		# Card background
		if i == _selected_hardpoint:
			var pulse := UITheme.get_pulse(1.0)
			var sel_a := lerpf(0.08, 0.18, pulse)
			draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
			draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
		else:
			draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
			draw_rect(card_rect, UITheme.BORDER, false, 1.0)

		# Slot size badge
		var badge_col := _slot_size_color(hp.slot_size)
		var badge_text := "%s%d" % [hp.slot_size, i + 1]
		draw_string(font, Vector2(card_x + 6, card_y + 14), badge_text,
			HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_BODY, badge_col)

		# Weapon name or VIDE
		var name_x := card_x + 36
		if hp.mounted_weapon:
			var type_col: Color = TYPE_COLORS.get(hp.mounted_weapon.weapon_type, UITheme.PRIMARY)
			draw_string(font, Vector2(name_x, card_y + 14), str(hp.mounted_weapon.weapon_name),
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 44, UITheme.FONT_SIZE_SMALL, type_col)
			# Small weapon icon
			_draw_weapon_icon(Vector2(name_x + 4, card_y + 26), 5.0, hp.mounted_weapon.weapon_type, type_col)
		else:
			draw_string(font, Vector2(name_x, card_y + 14), "VIDE",
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 44, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


# =============================================================================
# 2D PROJECTED LABELS (overlaid on 3D viewer)
# =============================================================================
func _draw_projected_labels(font: Font, viewer_w: float, viewer_h: float) -> void:
	if _viewer_camera == null or weapon_manager == null or _viewport == null:
		return

	var cam_fwd := -_viewer_camera.global_transform.basis.z

	for i in weapon_manager.hardpoints.size():
		var hp := weapon_manager.hardpoints[i]
		var world_pos := hp.position * _ship_model_scale

		# Check if marker is facing camera (dot product)
		var to_marker := (world_pos - _viewer_camera.global_position).normalized()
		if cam_fwd.dot(to_marker) < 0.1:
			continue

		# Check if behind camera
		if not _viewer_camera.is_position_behind(world_pos):
			var screen_pos := _viewer_camera.unproject_position(world_pos)
			# Scale from viewport coords to our viewer area
			var vp_size := Vector2(_viewport.size)
			if vp_size.x <= 0 or vp_size.y <= 0:
				continue
			var label_x := screen_pos.x / vp_size.x * viewer_w
			var label_y := screen_pos.y / vp_size.y * viewer_h + CONTENT_TOP

			# Clamp to viewer bounds
			label_x = clampf(label_x, 10.0, viewer_w - 80.0)
			label_y = clampf(label_y, CONTENT_TOP + 10, CONTENT_TOP + viewer_h - 20)

			# Label text
			var label_text := "%s%d" % [hp.slot_size, i + 1]
			if hp.mounted_weapon:
				label_text += ": " + str(hp.mounted_weapon.weapon_name)

			var col := UITheme.TEXT_DIM
			if i == _selected_hardpoint:
				col = UITheme.PRIMARY
			elif hp.mounted_weapon:
				col = TYPE_COLORS.get(hp.mounted_weapon.weapon_type, UITheme.TEXT_DIM)

			# Dark pill background
			var tw := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
			draw_rect(Rect2(label_x + 8, label_y - 10, tw + 8, 14), Color(0, 0, 0, 0.5))
			draw_string(font, Vector2(label_x + 12, label_y), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, 150, UITheme.FONT_SIZE_SMALL, col)

			# Line from marker to label
			draw_line(Vector2(label_x, label_y - 3), Vector2(label_x + 8, label_y - 3), Color(col.r, col.g, col.b, 0.4), 1.0)


# =============================================================================
# PLACEHOLDER (for non-weapon tabs)
# =============================================================================
func _draw_placeholder(font: Font, sidebar_x: float, sidebar_w: float, s: Vector2) -> void:
	var cx := sidebar_x + sidebar_w * 0.5
	var cy := (CONTENT_TOP + TAB_H + 60 + s.y - COMPARE_H - 90) * 0.5

	# Decorative hexagon
	var hex_r := 24.0
	for seg in 6:
		var a1 := TAU * seg / 6.0 - PI / 6.0
		var a2 := TAU * (seg + 1) / 6.0 - PI / 6.0
		draw_line(
			Vector2(cx + cos(a1) * hex_r, cy + sin(a1) * hex_r),
			Vector2(cx + cos(a2) * hex_r, cy + sin(a2) * hex_r),
			UITheme.PRIMARY_DIM, 1.5)

	# Lock icon inside hexagon
	draw_rect(Rect2(cx - 6, cy - 1, 12, 9), Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.5))
	draw_arc(Vector2(cx, cy - 3), 5.0, PI, TAU, 8, UITheme.TEXT_DIM, 1.5)

	draw_string(font, Vector2(sidebar_x + 16, cy + 44), "BIENTOT DISPONIBLE",
		HORIZONTAL_ALIGNMENT_CENTER, sidebar_w - 32, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
	draw_string(font, Vector2(sidebar_x + 16, cy + 62), "Ce module est en developpement",
		HORIZONTAL_ALIGNMENT_CENTER, sidebar_w - 32, UITheme.FONT_SIZE_SMALL,
		Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.5))


# =============================================================================
# ARSENAL DRAW CALLBACK
# =============================================================================
func _draw_arsenal_row(ctrl: Control, index: int, rect: Rect2, _item: Variant) -> void:
	if index < 0 or index >= _arsenal_items.size():
		return
	var weapon_name: StringName = _arsenal_items[index]
	var weapon := WeaponRegistry.get_weapon(weapon_name)
	if weapon == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = player_inventory.get_weapon_count(weapon_name) if player_inventory else 0
	var slot_size_str: String = ["S", "M", "L"][weapon.slot_size]
	var compatible := true
	if _selected_hardpoint >= 0 and weapon_manager:
		var hp := weapon_manager.hardpoints[_selected_hardpoint]
		compatible = player_inventory.is_compatible(weapon_name, hp.slot_size) if player_inventory else false

	var alpha_mult: float = 1.0 if compatible else 0.3
	var type_col: Color = TYPE_COLORS.get(weapon.weapon_type, UITheme.PRIMARY)
	if not compatible:
		type_col = Color(type_col.r, type_col.g, type_col.b, 0.3)

	# Weapon icon (circle with type icon)
	var icon_cx := rect.position.x + 24.0
	var icon_cy := rect.position.y + rect.size.y * 0.5
	var icon_r := 16.0
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.15 * alpha_mult), icon_r * 0.7)
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.6 * alpha_mult), 1.5)
	_draw_weapon_icon_on(ctrl, Vector2(icon_cx, icon_cy), 8.0, weapon.weapon_type,
		Color(type_col.r, type_col.g, type_col.b, alpha_mult))

	# Name
	var text_col := Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x := rect.position.x + 48
	var name_y := rect.position.y + 20
	ctrl.draw_string(font, Vector2(name_x, name_y), str(weapon_name),
		HORIZONTAL_ALIGNMENT_LEFT, 160, UITheme.FONT_SIZE_BODY, text_col)

	# DPS stat below name
	var stat_y := name_y + 15
	var dim_col := Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var dps := weapon.damage_per_hit * weapon.fire_rate
	ctrl.draw_string(font, Vector2(name_x, stat_y), "%.0f DPS" % dps,
		HORIZONTAL_ALIGNMENT_LEFT, 70, UITheme.FONT_SIZE_SMALL, dim_col)

	# Quantity badge
	var qty_x := rect.position.x + rect.size.x - 80
	var qty_y := rect.position.y + (rect.size.y - 20) * 0.5
	var qty_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.8 * alpha_mult)
	ctrl.draw_rect(Rect2(qty_x, qty_y, 32, 20), Color(qty_col.r, qty_col.g, qty_col.b, 0.1))
	ctrl.draw_rect(Rect2(qty_x, qty_y, 32, 20), Color(qty_col.r, qty_col.g, qty_col.b, 0.4), false, 1.0)
	ctrl.draw_string(font, Vector2(qty_x + 2, qty_y + 15), "x%d" % count,
		HORIZONTAL_ALIGNMENT_CENTER, 28, UITheme.FONT_SIZE_BODY, qty_col)

	# Size badge
	var badge_col := _slot_size_color(slot_size_str)
	if not compatible:
		badge_col = Color(badge_col.r, badge_col.g, badge_col.b, 0.3)
	var badge_x := rect.position.x + rect.size.x - 40
	var badge_y := rect.position.y + (rect.size.y - SIZE_BADGE_H) * 0.5
	ctrl.draw_rect(Rect2(badge_x, badge_y, SIZE_BADGE_W, SIZE_BADGE_H),
		Color(badge_col.r, badge_col.g, badge_col.b, 0.12))
	ctrl.draw_rect(Rect2(badge_x, badge_y, SIZE_BADGE_W, SIZE_BADGE_H), badge_col, false, 1.0)
	ctrl.draw_string(font, Vector2(badge_x + 5, badge_y + 16), slot_size_str,
		HORIZONTAL_ALIGNMENT_LEFT, SIZE_BADGE_W, UITheme.FONT_SIZE_BODY, badge_col)

	# Lock icon for incompatible
	if not compatible:
		var lock_x := rect.end.x - 16
		var lock_y := rect.position.y + rect.size.y * 0.5
		ctrl.draw_rect(Rect2(lock_x - 5, lock_y - 2, 10, 8),
			Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5))
		ctrl.draw_arc(Vector2(lock_x, lock_y - 4), 4.0, PI, TAU, 8,
			Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)


# =============================================================================
# COMPARISON PANEL
# =============================================================================
func _draw_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	if _selected_hardpoint < 0 or _selected_weapon == &"":
		var center_x := px + pw * 0.5
		var center_y := start_y + 50
		# Crosshair icon
		var cr := 14.0
		draw_arc(Vector2(center_x, center_y), cr, 0, TAU, 24, UITheme.TEXT_DIM, 1.0)
		draw_line(Vector2(center_x - cr - 5, center_y), Vector2(center_x - cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
		draw_line(Vector2(center_x + cr - 5, center_y), Vector2(center_x + cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
		draw_line(Vector2(center_x, center_y - cr - 5), Vector2(center_x, center_y - cr + 5), UITheme.TEXT_DIM, 1.0)
		draw_line(Vector2(center_x, center_y + cr - 5), Vector2(center_x, center_y + cr + 5), UITheme.TEXT_DIM, 1.0)
		draw_string(font, Vector2(px, center_y + 26), "Selectionnez un point d'emport et une arme",
			HORIZONTAL_ALIGNMENT_CENTER, pw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var new_weapon := WeaponRegistry.get_weapon(_selected_weapon)
	if new_weapon == null:
		return

	var current_weapon: WeaponResource = null
	if weapon_manager and _selected_hardpoint < weapon_manager.hardpoints.size():
		current_weapon = weapon_manager.hardpoints[_selected_hardpoint].mounted_weapon

	var cur_dmg := current_weapon.damage_per_hit if current_weapon else 0.0
	var new_dmg := new_weapon.damage_per_hit
	var cur_rate := current_weapon.fire_rate if current_weapon else 0.0
	var new_rate := new_weapon.fire_rate
	var cur_dps := cur_dmg * cur_rate
	var new_dps := new_dmg * new_rate
	var cur_energy := current_weapon.energy_cost_per_shot if current_weapon else 0.0
	var new_energy := new_weapon.energy_cost_per_shot
	var cur_range := (current_weapon.projectile_speed * current_weapon.projectile_lifetime) if current_weapon else 0.0
	var new_range := new_weapon.projectile_speed * new_weapon.projectile_lifetime

	# [label, current, new, higher_is_better]
	var stats: Array = [
		["DEGATS", cur_dmg, new_dmg, true],
		["CADENCE", cur_rate, new_rate, true],
		["DPS", cur_dps, new_dps, true],
		["ENERGIE", cur_energy, new_energy, false],
		["PORTEE", cur_range, new_range, true],
	]

	var row_h := 24.0
	var label_x := px + 8
	var val_x := px + pw * 0.38
	var new_val_x := px + pw * 0.58
	var delta_x := px + pw - 8

	for row_i in stats.size():
		var stat: Array = stats[row_i]
		var label: String = stat[0]
		var cur_val: float = stat[1]
		var new_val: float = stat[2]
		var higher_better: bool = stat[3]
		var delta: float = new_val - cur_val
		var ry := start_y + row_i * row_h

		if row_i % 2 == 0:
			draw_rect(Rect2(px + 4, ry - 4, pw - 8, row_h), Color(0, 0.02, 0.05, 0.15))

		var is_better: bool = (delta > 0.01 and higher_better) or (delta < -0.01 and not higher_better)
		var is_worse: bool = (delta > 0.01 and not higher_better) or (delta < -0.01 and higher_better)

		# Label
		draw_string(font, Vector2(label_x, ry + 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, 70, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		# Current value
		draw_string(font, Vector2(val_x, ry + 10), _format_stat(cur_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

		# Arrow
		if absf(delta) > 0.01:
			var arr_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			draw_string(font, Vector2(new_val_x - 12, ry + 10), ">",
				HORIZONTAL_ALIGNMENT_LEFT, 10, UITheme.FONT_SIZE_SMALL, arr_col)

		# New value
		var new_text_col := UITheme.TEXT
		if is_better:
			new_text_col = UITheme.ACCENT
		elif is_worse:
			new_text_col = UITheme.DANGER
		draw_string(font, Vector2(new_val_x, ry + 10), _format_stat(new_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_SMALL, new_text_col)

		# Delta
		if absf(delta) > 0.01:
			var delta_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			var sign_str := "+" if delta > 0.0 else ""
			draw_string(font, Vector2(delta_x - 60, ry + 10), sign_str + _format_stat(delta, label),
				HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_SMALL, delta_col)


func _format_stat(val: float, label: String) -> String:
	match label:
		"CADENCE":
			return "%.1f/s" % val
		"PORTEE":
			if val >= 1000.0:
				return "%.1f km" % (val / 1000.0)
			return "%.0f m" % val
		"ENERGIE":
			return "%.1f" % val
	if absf(val) >= 100:
		return "%.0f" % val
	return "%.1f" % val


# =============================================================================
# PROCEDURAL ICONS
# =============================================================================
func _draw_weapon_icon(center: Vector2, r: float, weapon_type: int, col: Color) -> void:
	match weapon_type:
		0:  # LASER
			draw_line(center + Vector2(-r, -r * 0.6), center + Vector2(r, 0), col, 1.5)
			draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 1.5)
			draw_line(center + Vector2(-r, r * 0.6), center + Vector2(r, 0), col, 1.5)
			draw_circle(center + Vector2(r, 0), 2.0, col)
		1:  # PLASMA
			draw_circle(center, r * 0.65, Color(col.r, col.g, col.b, 0.4))
			draw_arc(center, r * 0.65, 0, TAU, 12, col, 1.5)
			draw_circle(center, r * 0.25, col)
		2:  # MISSILE
			var pts := PackedVector2Array([
				center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.5),
				center + Vector2(-r * 0.3, 0), center + Vector2(-r * 0.5, r * 0.5),
			])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.4))
			pts.append(pts[0])
			draw_polyline(pts, col, 1.5)
		3:  # RAILGUN
			draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 2.0)
			draw_circle(center + Vector2(-r, 0), 2.5, col)
			draw_circle(center + Vector2(r, 0), 2.5, col)
		4:  # MINE
			draw_arc(center, r * 0.45, 0, TAU, 12, col, 1.5)
			for spike_i in 6:
				var angle := TAU * spike_i / 6.0
				var inner_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.45
				var outer_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.9
				draw_line(inner_pt, outer_pt, col, 1.5)
				draw_circle(outer_pt, 1.5, col)


func _draw_weapon_icon_on(ctrl: Control, center: Vector2, r: float, weapon_type: int, col: Color) -> void:
	match weapon_type:
		0:  # LASER
			ctrl.draw_line(center + Vector2(-r, -r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_circle(center + Vector2(r, 0), 2.0, col)
		1:  # PLASMA
			ctrl.draw_circle(center, r * 0.65, Color(col.r, col.g, col.b, 0.4))
			ctrl.draw_arc(center, r * 0.65, 0, TAU, 12, col, 1.5)
			ctrl.draw_circle(center, r * 0.25, col)
		2:  # MISSILE
			var pts := PackedVector2Array([
				center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.5),
				center + Vector2(-r * 0.3, 0), center + Vector2(-r * 0.5, r * 0.5),
			])
			ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.4))
			pts.append(pts[0])
			ctrl.draw_polyline(pts, col, 1.5)
		3:  # RAILGUN
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 2.0)
			ctrl.draw_circle(center + Vector2(-r, 0), 2.5, col)
			ctrl.draw_circle(center + Vector2(r, 0), 2.5, col)
		4:  # MINE
			ctrl.draw_arc(center, r * 0.45, 0, TAU, 12, col, 1.5)
			for spike_i in 6:
				var angle := TAU * spike_i / 6.0
				var inner_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.45
				var outer_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.9
				ctrl.draw_line(inner_pt, outer_pt, col, 1.5)
				ctrl.draw_circle(outer_pt, 1.5, col)


# =============================================================================
# INTERACTION
# =============================================================================
func _on_tab_changed(index: int) -> void:
	_current_tab = index
	_arsenal_list.visible = (_current_tab == 0)
	_selected_weapon = &""
	if _arsenal_list:
		_arsenal_list.selected_index = -1
	_update_button_states()
	queue_redraw()


func _on_arsenal_selected(index: int) -> void:
	if index >= 0 and index < _arsenal_items.size():
		_selected_weapon = _arsenal_items[index]
	else:
		_selected_weapon = &""
	_update_button_states()
	queue_redraw()


func _on_equip_pressed() -> void:
	if _selected_hardpoint < 0 or _selected_weapon == &"" or weapon_manager == null or player_inventory == null:
		return
	var hp := weapon_manager.hardpoints[_selected_hardpoint]
	if not player_inventory.is_compatible(_selected_weapon, hp.slot_size):
		return
	if not player_inventory.has_weapon(_selected_weapon):
		return

	player_inventory.remove_weapon(_selected_weapon)
	var old_name := weapon_manager.swap_weapon(_selected_hardpoint, _selected_weapon)
	if old_name != &"":
		player_inventory.add_weapon(old_name)

	_selected_weapon = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	queue_redraw()


func _on_remove_pressed() -> void:
	if _selected_hardpoint < 0 or weapon_manager == null or player_inventory == null:
		return
	var old_name := weapon_manager.remove_weapon(_selected_hardpoint)
	if old_name != &"":
		player_inventory.add_weapon(old_name)

	_selected_weapon = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	queue_redraw()


func _on_back_pressed() -> void:
	close()


# =============================================================================
# HELPERS
# =============================================================================
func _refresh_arsenal() -> void:
	_arsenal_items.clear()
	if player_inventory == null:
		_arsenal_list.items = []
		_arsenal_list.queue_redraw()
		return

	if _selected_hardpoint >= 0 and weapon_manager:
		var hp := weapon_manager.hardpoints[_selected_hardpoint]
		_arsenal_items = player_inventory.get_weapons_for_slot(hp.slot_size)
	else:
		_arsenal_items = player_inventory.get_all_weapons()

	var list_items: Array = []
	for wn in _arsenal_items:
		list_items.append(wn)
	_arsenal_list.items = list_items
	_arsenal_list.selected_index = -1
	_arsenal_list._scroll_offset = 0.0
	_arsenal_list.queue_redraw()


func _update_button_states() -> void:
	var can_equip := false
	if _current_tab == 0 and _selected_hardpoint >= 0 and _selected_weapon != &"" and weapon_manager and player_inventory:
		var hp := weapon_manager.hardpoints[_selected_hardpoint]
		can_equip = player_inventory.is_compatible(_selected_weapon, hp.slot_size) and player_inventory.has_weapon(_selected_weapon)
	_equip_btn.enabled = can_equip

	var can_remove := false
	if _selected_hardpoint >= 0 and weapon_manager:
		can_remove = weapon_manager.hardpoints[_selected_hardpoint].mounted_weapon != null
	_remove_btn.enabled = can_remove


func _slot_size_color(s: String) -> Color:
	match s:
		"S": return UITheme.PRIMARY
		"M": return UITheme.WARNING
		"L": return Color(1.0, 0.5, 0.15, 0.9)
	return UITheme.TEXT_DIM
