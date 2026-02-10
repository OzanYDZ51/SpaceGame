class_name EquipmentScreen
extends UIScreen

# =============================================================================
# Equipment Screen - 3D Ship Viewer + 4 Category Tabs + Sidebar Arsenal
# Holographic AAA-style (Star Citizen / Elite Dangerous)
# Left: SubViewport with orbiting 3D ship model + hardpoint/slot markers
# Right: Category tabs (ARMEMENT/MODULES/BOUCLIERS/MOTEURS), arsenal list,
#         comparison panel, action buttons
# =============================================================================

signal equipment_closed

var player_inventory: PlayerInventory = null
var weapon_manager: WeaponManager = null
var equipment_manager: EquipmentManager = null
var player_fleet: PlayerFleet = null

# --- Station mode (set externally before opening) ---
var station_equip_adapter: StationEquipAdapter = null

# --- Adapter (abstracts LIVE vs DATA mode, or StationEquipAdapter) ---
var _adapter: RefCounted = null
var _selected_fleet_index: int = 0
var _fleet_scroll_offset: float = 0.0
var _fleet_hovered_index: int = -1

# --- 3D Viewer ---
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _viewer_camera: Camera3D = null
var _ship_model: ShipModel = null
var _ship_model_path: String = "res://assets/models/tie.glb"
var _ship_model_scale: float = 1.0
var _ship_model_rotation: Vector3 = Vector3.ZERO
var _ship_center_offset: Vector3 = Vector3.ZERO
var _ship_root_basis: Basis = Basis.IDENTITY
var _hp_markers: Array[Dictionary] = []  # {mesh: MeshInstance3D, body: StaticBody3D, index: int}

# --- Orbit Camera ---
var orbit_yaw: float = 30.0
var orbit_pitch: float = -15.0
var orbit_distance: float = 8.0
var _orbit_min_dist: float = 3.0
var _orbit_max_dist: float = 60.0
const ORBIT_PITCH_MIN := -80.0
const ORBIT_PITCH_MAX := 80.0
const ORBIT_SENSITIVITY := 0.3
const AUTO_ROTATE_SPEED := 6.0
const AUTO_ROTATE_DELAY := 3.0
var _orbit_dragging: bool = false
var _last_input_time: float = 0.0

# --- Selection State ---
var _selected_hardpoint: int = -1
var _selected_weapon: StringName = &""
var _selected_shield: StringName = &""
var _selected_engine: StringName = &""
var _selected_module: StringName = &""
var _selected_module_slot: int = -1
var _hp_hovered_index: int = -1
var _module_hovered_index: int = -1
var _pulse_time: float = 0.0

# --- Category Tabs ---
var _tab_bar: UITabBar = null
var _current_tab: int = 0
const TAB_NAMES: Array[String] = ["ARMEMENT", "MODULES", "BOUCLIERS", "MOTEURS"]
const TAB_NAMES_STATION: Array[String] = ["ARMEMENT", "MODULES", "BOUCLIERS"]

# --- UI Controls ---
var _arsenal_list: UIScrollList = null
var _arsenal_items: Array[StringName] = []
var _equip_btn: UIButton = null
var _remove_btn: UIButton = null
var _back_btn: UIButton = null

# --- Layout constants ---
const VIEWER_RATIO := 0.55
const SIDEBAR_RATIO := 0.45
const CONTENT_TOP := 140.0
const FLEET_STRIP_TOP := 52.0
const FLEET_STRIP_H := 88.0
const FLEET_CARD_W := 156.0
const FLEET_CARD_H := 66.0
const FLEET_CARD_GAP := 6.0
const TAB_H := 30.0
const HP_STRIP_H := 94.0
const COMPARE_H := 170.0
const BTN_W := 140.0
const BTN_H := 38.0
const ARSENAL_ROW_H := 56.0
const SIZE_BADGE_W := 30.0
const SIZE_BADGE_H := 22.0

# Weapon type colors
const TYPE_COLORS := {
	0: Color(0.3, 0.7, 1.0, 0.9),    # LASER
	1: Color(1.0, 0.45, 0.15, 0.9),   # PLASMA
	2: Color(1.0, 0.3, 0.3, 0.9),     # MISSILE
	3: Color(0.85, 0.85, 1.0, 0.9),   # RAILGUN
	4: Color(0.7, 1.0, 0.3, 0.9),     # MINE
	5: Color(1.0, 0.8, 0.3, 0.9),     # TURRET
}
const TYPE_NAMES := ["LASER", "PLASMA", "MISSILE", "RAILGUN", "MINE", "TURRET"]

# Equipment type colors
const SHIELD_COLOR := Color(0.3, 0.6, 1.0, 0.9)
const ENGINE_COLOR := Color(1.0, 0.6, 0.2, 0.9)
const MODULE_COLORS := {
	0: Color(0.7, 0.5, 0.3, 0.9),   # COQUE
	1: Color(1.0, 0.85, 0.2, 0.9),  # ENERGIE
	2: Color(0.3, 0.6, 1.0, 0.9),   # BOUCLIER
	3: Color(1.0, 0.3, 0.3, 0.9),   # ARME
	4: Color(0.3, 1.0, 0.6, 0.9),   # SCANNER
	5: Color(1.0, 0.6, 0.2, 0.9),   # MOTEUR
}


func _ready() -> void:
	screen_title = "FLOTTE — EQUIPEMENT"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Tab bar
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
	_arsenal_list.item_double_clicked.connect(_on_arsenal_double_clicked)
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


func setup_ship_viewer(model_path: String, model_scale: float, center_offset: Vector3 = Vector3.ZERO, model_rotation: Vector3 = Vector3.ZERO, root_basis: Basis = Basis.IDENTITY) -> void:
	_ship_model_path = model_path
	_ship_model_scale = model_scale
	_ship_model_rotation = model_rotation
	_ship_center_offset = center_offset
	_ship_root_basis = root_basis


# =============================================================================
# OPEN / CLOSE
# =============================================================================
func _on_opened() -> void:
	_selected_hardpoint = -1
	_selected_weapon = &""
	_selected_shield = &""
	_selected_engine = &""
	_selected_module = &""
	_selected_module_slot = -1
	_current_tab = 0
	_last_input_time = 0.0
	orbit_yaw = 30.0
	orbit_pitch = -15.0

	if _tab_bar:
		_tab_bar.tabs = TAB_NAMES_STATION if _is_station_mode() else TAB_NAMES
		_tab_bar.current_tab = 0

	if _is_station_mode():
		screen_title = "STATION — EQUIPEMENT"
		# Station mode: use station model
		setup_ship_viewer("res://assets/models/space_station.glb", 0.08, Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY)
	else:
		screen_title = "FLOTTE — EQUIPEMENT"

	# Select active ship by default (skip in station mode)
	_selected_fleet_index = player_fleet.active_index if player_fleet and not _is_station_mode() else 0
	_fleet_scroll_offset = 0.0
	_fleet_hovered_index = -1
	_hp_hovered_index = -1
	_module_hovered_index = -1
	_create_adapter()

	_setup_3d_viewer()
	_auto_select_slot()
	_refresh_arsenal()
	_layout_controls()

	_tab_bar.visible = true
	_arsenal_list.visible = true
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
	if _adapter and _adapter.loadout_changed.is_connected(_on_adapter_loadout_changed):
		_adapter.loadout_changed.disconnect(_on_adapter_loadout_changed)
	_adapter = null
	station_equip_adapter = null
	equipment_closed.emit()


# =============================================================================
# 3D VIEWER SETUP
# =============================================================================
func _setup_3d_viewer() -> void:
	_cleanup_3d_viewer()

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_viewport_container.show_behind_parent = true
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_color = Color(0.15, 0.2, 0.25)
	env.ambient_light_energy = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.95, 0.9)
	key_light.light_energy = 1.2
	key_light.rotation_degrees = Vector3(-45, 30, 0)
	_viewport.add_child(key_light)

	# Scale light positions and range to model size so all ships are well-lit
	var light_scale := maxf(1.0, _ship_model_scale)
	var fill_light := OmniLight3D.new()
	fill_light.light_color = Color(0.8, 0.85, 0.9)
	fill_light.light_energy = 0.6
	fill_light.omni_range = 30.0 * light_scale
	fill_light.position = Vector3(-6, 2, -4) * light_scale
	_viewport.add_child(fill_light)

	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b)
	rim_light.light_energy = 0.4
	rim_light.omni_range = 30.0 * light_scale
	rim_light.position = Vector3(5, 1, 5) * light_scale
	_viewport.add_child(rim_light)

	_viewer_camera = Camera3D.new()
	_viewer_camera.fov = 40.0
	_viewer_camera.near = 0.1
	_viewer_camera.far = 500.0
	_viewport.add_child(_viewer_camera)

	_ship_model = ShipModel.new()
	_ship_model.model_path = _ship_model_path
	_ship_model.model_scale = _ship_model_scale
	_ship_model.model_rotation_degrees = _ship_model_rotation
	_ship_model.skip_centering = true
	_ship_model.engine_light_color = Color(0.3, 0.5, 1.0)
	# Ship stays at origin — camera orbits around center_offset instead
	_viewport.add_child(_ship_model)

	# Show equipped weapon meshes on the 3D model
	_refresh_viewer_weapons()

	_create_hardpoint_markers()
	_auto_fit_camera()
	_update_orbit_camera()



func _auto_fit_camera() -> void:
	# Compute bounding sphere radius from _ship_center_offset (camera look-at point)
	# to the farthest visible point. Ship stays at origin, camera orbits center_offset.
	var max_radius: float = 2.0

	if _ship_model:
		var aabb := _ship_model.get_visual_aabb()
		for i in 8:
			var corner: Vector3 = aabb.get_endpoint(i) - _ship_center_offset
			max_radius = maxf(max_radius, corner.length())

	# Also consider hardpoint positions (they may extend beyond the mesh)
	if weapon_manager and _is_live_mode():
		for hp in weapon_manager.hardpoints:
			var pos: Vector3 = _ship_root_basis * hp.position - _ship_center_offset
			max_radius = maxf(max_radius, pos.length())

	# Distance = radius / tan(half_fov), with padding for readability
	var half_fov := deg_to_rad(_viewer_camera.fov * 0.5) if _viewer_camera else deg_to_rad(20.0)
	var ideal := max_radius / tan(half_fov) * 1.3
	orbit_distance = ideal
	_orbit_min_dist = ideal * 0.4
	_orbit_max_dist = ideal * 3.0

	# Ensure camera far plane covers the full zoom range
	if _viewer_camera:
		_viewer_camera.far = maxf(500.0, _orbit_max_dist + max_radius * 2.0)


func _refresh_viewer_weapons() -> void:
	if _ship_model == null:
		return
	if _is_live_mode() and weapon_manager:
		var hp_configs: Array[Dictionary] = []
		var weapon_names: Array[StringName] = []
		for hp in weapon_manager.hardpoints:
			hp_configs.append({"position": hp.position, "rotation_degrees": hp.rotation_degrees, "id": hp.slot_id, "size": hp.slot_size, "is_turret": hp.is_turret})
			weapon_names.append(hp.mounted_weapon.weapon_name if hp.mounted_weapon else &"")
		_ship_model.apply_equipment(hp_configs, weapon_names, _ship_root_basis)
	elif _is_station_mode() and _adapter:
		# Station mode: use station hardpoint configs
		var sta: StationEquipAdapter = _adapter as StationEquipAdapter
		if sta:
			var hp_configs: Array[Dictionary] = sta._hp_configs
			var weapon_names: Array[StringName] = []
			for i in hp_configs.size():
				weapon_names.append(sta.get_mounted_weapon_name(i))
			_ship_model.apply_equipment(hp_configs, weapon_names, Basis.IDENTITY)
	elif _adapter:
		var sd: ShipData = _adapter.get_ship_data()
		if sd == null:
			return
		var hp_configs: Array[Dictionary] = []
		var weapon_names: Array[StringName] = []
		for i in sd.hardpoints.size():
			var cfg: Dictionary = sd.hardpoints[i]
			hp_configs.append(cfg)
			weapon_names.append(_adapter.get_mounted_weapon_name(i))
		_ship_model.apply_equipment(hp_configs, weapon_names, _ship_root_basis)


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
	if _viewport == null:
		return

	# In LIVE mode use weapon_manager hardpoints; in DATA mode use ShipData configs
	var hp_count: int = 0
	var hp_positions: Array[Vector3] = []
	var hp_turrets: Array[bool] = []
	if _is_live_mode() and weapon_manager:
		hp_count = weapon_manager.hardpoints.size()
		for hp in weapon_manager.hardpoints:
			hp_positions.append(hp.position)
			hp_turrets.append(hp.is_turret)
	elif _is_station_mode() and _adapter:
		# Station mode: use StationHardpointConfig for marker positions
		var sta: StationEquipAdapter = _adapter as StationEquipAdapter
		if sta:
			hp_count = sta.get_hardpoint_count()
			for j in hp_count:
				if j < sta._hp_configs.size():
					hp_positions.append(sta._hp_configs[j].get("position", Vector3.ZERO))
				else:
					hp_positions.append(Vector3.ZERO)
				hp_turrets.append(sta.is_hardpoint_turret(j))
	elif _adapter:
		var sd: ShipData = _adapter.get_ship_data()
		if sd:
			hp_count = sd.hardpoints.size()
			var configs := ShipFactory.get_hardpoint_configs(_adapter.fleet_ship.ship_id)
			for j in sd.hardpoints.size():
				if j < configs.size():
					hp_positions.append(configs[j].get("position", Vector3.ZERO))
				else:
					hp_positions.append(Vector3.ZERO)
				hp_turrets.append(sd.hardpoints[j].get("is_turret", false))

	for i in hp_count:
		var is_turret: bool = hp_turrets[i] if i < hp_turrets.size() else false
		var mesh_inst := MeshInstance3D.new()
		if is_turret:
			var box := BoxMesh.new()
			var s := 0.18 * _ship_model_scale
			box.size = Vector3(s, s, s)
			mesh_inst.mesh = box
			mesh_inst.rotation_degrees = Vector3(0, 45, 0)
		else:
			var sphere := SphereMesh.new()
			sphere.radius = 0.15 * _ship_model_scale
			sphere.height = 0.3 * _ship_model_scale
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh_inst.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.3)
		mat.emission_enabled = false
		mat.no_depth_test = true
		mat.render_priority = 10
		mesh_inst.material_override = mat
		var pos: Vector3 = hp_positions[i] if i < hp_positions.size() else Vector3.ZERO
		mesh_inst.position = _ship_root_basis * pos
		_viewport.add_child(mesh_inst)

		var body := StaticBody3D.new()
		body.position = _ship_root_basis * pos
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
	if _adapter == null:
		return
	var hp_count: int = _adapter.get_hardpoint_count()
	for marker in _hp_markers:
		var idx: int = marker.index
		var mesh: MeshInstance3D = marker.mesh
		var mat: StandardMaterial3D = mesh.material_override

		if idx >= hp_count:
			continue

		var mounted: WeaponResource = _adapter.get_mounted_weapon(idx)
		var has_weapon_model: bool = mounted != null and mounted.weapon_model_scene != ""

		if idx == _selected_hardpoint:
			mesh.visible = true
			var type_col := _get_marker_color_for(mounted)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			var pulse := 1.0 + sin(_pulse_time * 4.0) * 0.5
			mat.emission_energy_multiplier = pulse
		elif has_weapon_model:
			mesh.visible = false
		elif mounted:
			mesh.visible = true
			var type_col := _get_marker_color_for(mounted)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			mat.emission_energy_multiplier = 0.5
		else:
			mesh.visible = true
			mat.albedo_color = Color(0.3, 0.3, 0.3)
			mat.emission_enabled = false


func _get_marker_color_for(weapon: WeaponResource) -> Color:
	if weapon:
		return TYPE_COLORS.get(weapon.weapon_type, UITheme.PRIMARY)
	return UITheme.PRIMARY


# =============================================================================
# ORBIT CAMERA
# =============================================================================
func _update_orbit_camera() -> void:
	if _viewer_camera == null:
		return
	var yaw_rad := deg_to_rad(orbit_yaw)
	var pitch_rad := deg_to_rad(orbit_pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * orbit_distance
	_viewer_camera.position = _ship_center_offset + offset
	_viewer_camera.look_at(_ship_center_offset)


# =============================================================================
# PROCESS
# =============================================================================
func _process(delta: float) -> void:
	_pulse_time += delta
	_last_input_time += delta

	if not _is_open:
		return

	if not _orbit_dragging and _last_input_time > AUTO_ROTATE_DELAY:
		orbit_yaw += AUTO_ROTATE_SPEED * delta
		_update_orbit_camera()

	if _current_tab == 0 and _adapter:
		_update_marker_visuals()

	# Redraw every frame so projected labels track the orbiting camera
	queue_redraw()


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

	# --- Fleet strip interaction (disabled in station mode) ---
	var fleet_strip_bottom := FLEET_STRIP_TOP + FLEET_STRIP_H
	if not _is_station_mode() and event is InputEventMouseButton and event.pressed:
		if event.position.y >= FLEET_STRIP_TOP and event.position.y <= fleet_strip_bottom:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var idx := _get_fleet_card_at(event.position.x)
				if idx >= 0:
					_on_fleet_ship_selected(idx)
				accept_event()
				return
			# Scroll in fleet strip
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var card_step := FLEET_CARD_W + FLEET_CARD_GAP
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_fleet_scroll_offset = maxf(0.0, _fleet_scroll_offset - card_step)
				else:
					var total_w := card_step * player_fleet.ships.size() - FLEET_CARD_GAP
					var area_w := size.x - 40 - 16
					var max_scroll := maxf(0.0, total_w - area_w)
					_fleet_scroll_offset = minf(max_scroll, _fleet_scroll_offset + card_step)
				queue_redraw()
				accept_event()
				return

	if not _is_station_mode() and event is InputEventMouseMotion:
		if event.position.y >= FLEET_STRIP_TOP and event.position.y <= fleet_strip_bottom:
			var idx := _get_fleet_card_at(event.position.x)
			if idx != _fleet_hovered_index:
				_fleet_hovered_index = idx
				queue_redraw()
		elif _fleet_hovered_index >= 0:
			_fleet_hovered_index = -1
			queue_redraw()

	# Bottom strip hover tracking
	if event is InputEventMouseMotion:
		var hover_strip_y := size.y - HP_STRIP_H - 50
		var hover_viewer_w := size.x * VIEWER_RATIO
		if event.position.x < hover_viewer_w and event.position.y >= hover_strip_y and event.position.y <= hover_strip_y + HP_STRIP_H:
			var new_hover := _get_strip_card_at(event.position)
			if _current_tab == 0:
				if new_hover != _hp_hovered_index:
					_hp_hovered_index = new_hover
					queue_redraw()
			elif _current_tab == 1:
				if new_hover != _module_hovered_index:
					_module_hovered_index = new_hover
					queue_redraw()
		else:
			if _hp_hovered_index >= 0 or _module_hovered_index >= 0:
				_hp_hovered_index = -1
				_module_hovered_index = -1
				queue_redraw()

	var viewer_w := size.x * VIEWER_RATIO
	var strip_top := size.y - HP_STRIP_H - 50

	# --- Strip clicks FIRST (hardpoints, module slots, shield/engine remove) ---
	# Must be checked before viewer area, because the strip overlaps the viewer's x range.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _current_tab == 0:
			if _try_click_hp_strip(event.position):
				accept_event()
				return
		elif _current_tab == 1:
			if _try_click_module_strip(event.position):
				accept_event()
				return
		elif _current_tab == 2:
			if _try_click_shield_remove(event.position):
				accept_event()
				return
		elif _current_tab == 3:
			if _try_click_engine_remove(event.position):
				accept_event()
				return

	# --- 3D Viewer area (orbit camera) ---
	var in_viewer: bool = false
	if "position" in event:
		in_viewer = event.position.x < viewer_w and event.position.y > CONTENT_TOP and event.position.y < strip_top

	if event is InputEventMouseButton and in_viewer:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_orbit_dragging = true
				_last_input_time = 0.0
			else:
				if _orbit_dragging:
					_orbit_dragging = false
					if _current_tab == 0:
						_try_select_marker(event.position)
			accept_event()
			return

		var zoom_step := orbit_distance * 0.08  # 8% per scroll tick — consistent across ship sizes
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(_orbit_min_dist, orbit_distance - zoom_step)
			_last_input_time = 0.0
			_update_orbit_camera()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(_orbit_max_dist, orbit_distance + zoom_step)
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

	accept_event()


func _try_select_marker(mouse_pos: Vector2) -> void:
	if _viewport == null or _viewer_camera == null or _adapter == null:
		return

	var viewer_w := size.x * VIEWER_RATIO
	var viewer_h := size.y - CONTENT_TOP - HP_STRIP_H - 20
	if viewer_w <= 0 or viewer_h <= 0:
		return

	var local_x := mouse_pos.x / viewer_w
	var local_y := (mouse_pos.y - CONTENT_TOP) / viewer_h
	if local_x < 0 or local_x > 1 or local_y < 0 or local_y > 1:
		return

	var vp_size := _viewport.size
	var vp_pos := Vector2(local_x * vp_size.x, local_y * vp_size.y)
	var from := _viewer_camera.project_ray_origin(vp_pos)
	var dir := _viewer_camera.project_ray_normal(vp_pos)

	if _viewport.world_3d == null:
		return
	var space := _viewport.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result and result.collider:
		var collider := result.collider as Node3D
		if collider.has_meta("hp_index"):
			var idx: int = collider.get_meta("hp_index")
			_select_hardpoint(idx)
			return

	_select_hardpoint(-1)


func _try_click_hp_strip(mouse_pos: Vector2) -> bool:
	if _adapter == null:
		return false

	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	if not strip_rect.has_point(mouse_pos):
		return false

	var hp_count: int = _adapter.get_hardpoint_count()
	if hp_count == 0:
		return false

	var card_w := minf(140.0, (strip_rect.size.x - 16) / hp_count)
	var total_w := card_w * hp_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5

	var card_y := strip_rect.position.y + 20

	for i in hp_count:
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, card_y, card_w - 4, HP_STRIP_H - 24)
		if card_rect.has_point(mouse_pos):
			# Check if clicked on [X] remove button (bigger target, 18x18)
			if _adapter.get_mounted_weapon(i) != null:
				var xb_sz := 18.0
				var xb_rect := Rect2(card_x + card_w - 4 - xb_sz - 4, card_y + 4, xb_sz, xb_sz)
				if xb_rect.has_point(mouse_pos):
					_selected_hardpoint = i
					_remove_weapon()
					return true
			_select_hardpoint(i)
			return true

	return false


func _try_click_module_strip(mouse_pos: Vector2) -> bool:
	if _adapter == null:
		return false

	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	if not strip_rect.has_point(mouse_pos):
		return false

	var slot_count: int = _adapter.get_module_slot_count()
	if slot_count == 0:
		return false

	var card_w := minf(160.0, (strip_rect.size.x - 16) / slot_count)
	var total_w := card_w * slot_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5

	var card_y := strip_rect.position.y + 20

	for i in slot_count:
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, card_y, card_w - 4, HP_STRIP_H - 24)
		if card_rect.has_point(mouse_pos):
			# Check [X] remove button (18x18)
			var mod: ModuleResource = _adapter.get_equipped_module(i)
			if mod:
				var xb_sz := 18.0
				var xb_rect := Rect2(card_x + card_w - 4 - xb_sz - 4, card_y + 4, xb_sz, xb_sz)
				if xb_rect.has_point(mouse_pos):
					_selected_module_slot = i
					_remove_module()
					return true
			_selected_module_slot = i
			_selected_module = &""
			if _arsenal_list:
				_arsenal_list.selected_index = -1
			_refresh_arsenal()
			_update_button_states()
			queue_redraw()
			return true

	return false


func _try_click_shield_remove(mouse_pos: Vector2) -> bool:
	if _adapter == null or _adapter.get_equipped_shield() == null:
		return false
	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var y := strip_y + 24
	var xb_rect := Rect2(viewer_w - 52, y + 1, 18, 18)
	if xb_rect.has_point(mouse_pos):
		_remove_shield()
		return true
	return false


func _try_click_engine_remove(mouse_pos: Vector2) -> bool:
	if _adapter == null or _adapter.get_equipped_engine() == null:
		return false
	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var y := strip_y + 24
	var xb_rect := Rect2(viewer_w - 52, y + 1, 18, 18)
	if xb_rect.has_point(mouse_pos):
		_remove_engine()
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


## Auto-select the first empty compatible slot for the current tab.
func _auto_select_slot() -> void:
	if _adapter == null:
		return
	match _current_tab:
		0:  # Weapons — select first empty hardpoint
			if _selected_hardpoint < 0:
				for i in _adapter.get_hardpoint_count():
					if _adapter.get_mounted_weapon(i) == null:
						_selected_hardpoint = i
						return
				if _adapter.get_hardpoint_count() > 0:
					_selected_hardpoint = 0
		1:  # Modules — select first empty module slot
			if _selected_module_slot < 0:
				for i in _adapter.get_module_slot_count():
					if _adapter.get_equipped_module(i) == null:
						_selected_module_slot = i
						return
				if _adapter.get_module_slot_count() > 0:
					_selected_module_slot = 0


# =============================================================================
# LAYOUT
# =============================================================================
func _layout_controls() -> void:
	var s := size
	var viewer_w := s.x * VIEWER_RATIO
	var sidebar_x := viewer_w
	var sidebar_w := s.x * SIDEBAR_RATIO
	var sidebar_pad := 16.0

	if _viewport_container:
		_viewport_container.position = Vector2(0, CONTENT_TOP)
		_viewport_container.size = Vector2(viewer_w, s.y - CONTENT_TOP - HP_STRIP_H - 20)

	var tab_y := CONTENT_TOP + 6.0
	_tab_bar.position = Vector2(sidebar_x + sidebar_pad, tab_y)
	_tab_bar.size = Vector2(sidebar_w - sidebar_pad * 2, TAB_H)

	# Arsenal header sits below tabs with some padding
	var arsenal_top := tab_y + TAB_H + 28.0
	var list_top := arsenal_top + 16.0
	var list_bottom := s.y - COMPARE_H - 100
	_arsenal_list.position = Vector2(sidebar_x + sidebar_pad + 4, list_top)
	_arsenal_list.size = Vector2(sidebar_w - sidebar_pad * 2 - 8, list_bottom - list_top)

	var btn_y := s.y - 62
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
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.55))
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

	# Fleet strip (hidden in station mode)
	if not _is_station_mode():
		_draw_fleet_strip(font, s)

	# Viewer divider
	draw_line(Vector2(viewer_w, CONTENT_TOP), Vector2(viewer_w, s.y - 40), UITheme.BORDER, 1.0)

	# Bottom strip (below 3D viewer) — depends on tab
	match _current_tab:
		0:
			_draw_hardpoint_strip(font, s)
			_draw_projected_labels(font, viewer_w, s.y - CONTENT_TOP - HP_STRIP_H - 20)
		1:
			_draw_module_slot_strip(font, s)
		2:
			_draw_shield_status_panel(font, s)
		3:
			_draw_engine_status_panel(font, s)

	# Sidebar — compute Y positions matching _layout_controls
	var tab_y := CONTENT_TOP + 6.0
	var arsenal_header_y := tab_y + TAB_H + 8.0

	# Sidebar background (covers arsenal area + comparison)
	var sb_top := arsenal_header_y - 4.0
	var sb_bottom := s.y - 72.0
	var sb_rect := Rect2(sidebar_x + sidebar_pad - 2, sb_top,
		sidebar_w - sidebar_pad * 2 + 4, sb_bottom - sb_top)
	draw_panel_bg(sb_rect)

	# Arsenal header
	var header_names := ["ARSENAL", "MODULES DISPO.", "BOUCLIERS DISPO.", "MOTEURS DISPO."]
	draw_section_header(sidebar_x + sidebar_pad + 4, arsenal_header_y, sidebar_w - sidebar_pad * 2 - 8, header_names[_current_tab])

	# Stock count
	if player_inventory:
		var total := _get_current_stock_count()
		var inv_str := "%d en stock" % total
		draw_string(font, Vector2(sidebar_x + sidebar_w - sidebar_pad - 4, arsenal_header_y + 11),
			inv_str, HORIZONTAL_ALIGNMENT_RIGHT, sidebar_w * 0.4, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Comparison panel
	var compare_y := s.y - COMPARE_H - 76
	var compare_rect := Rect2(sidebar_x + sidebar_pad - 2, compare_y,
		sidebar_w - sidebar_pad * 2 + 4, COMPARE_H)
	draw_panel_bg(compare_rect)
	var cmp_header_y := draw_section_header(sidebar_x + sidebar_pad + 4, compare_y + 5,
		sidebar_w - sidebar_pad * 2 - 8, "COMPARAISON")
	_draw_comparison(font, sidebar_x + sidebar_pad, cmp_header_y, sidebar_w - sidebar_pad * 2)

	# Button separator
	var btn_sep_y := s.y - 72
	draw_line(Vector2(sidebar_x + sidebar_pad, btn_sep_y),
		Vector2(sidebar_x + sidebar_w - sidebar_pad, btn_sep_y), UITheme.BORDER, 1.0)

	# Corner decorations
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
# FLEET STRIP (top of screen, full width)
# =============================================================================
func _draw_fleet_strip(font: Font, s: Vector2) -> void:
	if player_fleet == null or player_fleet.ships.is_empty():
		return

	var strip_rect := Rect2(20, FLEET_STRIP_TOP, s.x - 40, FLEET_STRIP_H)
	draw_panel_bg(strip_rect)

	# Header
	var ship_count := player_fleet.ships.size()
	draw_section_header(28, FLEET_STRIP_TOP + 2, 120, "FLOTTE")
	draw_string(font, Vector2(152, FLEET_STRIP_TOP + 14),
		"%d vaisseau%s" % [ship_count, "x" if ship_count > 1 else ""],
		HORIZONTAL_ALIGNMENT_LEFT, 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Compute card layout
	var cards_area_x := strip_rect.position.x + 8.0
	var cards_area_w := strip_rect.size.x - 16.0
	var card_step := FLEET_CARD_W + FLEET_CARD_GAP
	var total_cards_w := card_step * ship_count - FLEET_CARD_GAP
	var card_y := FLEET_STRIP_TOP + 20.0

	# Center if fits, otherwise allow scroll
	var base_x: float
	if total_cards_w <= cards_area_w:
		base_x = cards_area_x + (cards_area_w - total_cards_w) * 0.5
	else:
		base_x = cards_area_x - _fleet_scroll_offset

	# Clip region
	var clip_left := cards_area_x
	var clip_right := cards_area_x + cards_area_w

	for i in ship_count:
		var cx := base_x + i * card_step
		# Skip if completely outside clip
		if cx + FLEET_CARD_W < clip_left or cx > clip_right:
			continue
		var fs: FleetShip = player_fleet.ships[i]
		var sd := ShipRegistry.get_ship_data(fs.ship_id)
		_draw_fleet_card(font, cx, card_y, i, fs, sd)

	# Scroll arrows if content overflows
	if total_cards_w > cards_area_w:
		var arrow_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.6)
		if _fleet_scroll_offset > 0:
			# Left arrow
			var ax := cards_area_x + 2
			var ay := card_y + FLEET_CARD_H * 0.5
			draw_line(Vector2(ax + 8, ay - 8), Vector2(ax, ay), arrow_col, 2.0)
			draw_line(Vector2(ax, ay), Vector2(ax + 8, ay + 8), arrow_col, 2.0)
		var max_scroll := total_cards_w - cards_area_w
		if _fleet_scroll_offset < max_scroll:
			# Right arrow
			var ax := clip_right - 10
			var ay := card_y + FLEET_CARD_H * 0.5
			draw_line(Vector2(ax - 8, ay - 8), Vector2(ax, ay), arrow_col, 2.0)
			draw_line(Vector2(ax, ay), Vector2(ax - 8, ay + 8), arrow_col, 2.0)


func _draw_fleet_card(font: Font, cx: float, cy: float, index: int, fs: FleetShip, sd: ShipData) -> void:
	var card_rect := Rect2(cx, cy, FLEET_CARD_W, FLEET_CARD_H)
	var is_selected := index == _selected_fleet_index
	var is_hovered := index == _fleet_hovered_index
	var is_active := player_fleet != null and index == player_fleet.active_index

	# Background
	if is_selected:
		var pulse := UITheme.get_pulse(1.0)
		var sel_a := lerpf(0.08, 0.2, pulse)
		draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
		draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
		# Left accent bar
		draw_rect(Rect2(cx, cy, 3, FLEET_CARD_H), UITheme.PRIMARY)
	elif is_hovered:
		draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
		draw_rect(card_rect, UITheme.BORDER, false, 1.0)
	else:
		draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
		draw_rect(card_rect, UITheme.BORDER, false, 1.0)

	if sd == null:
		draw_string(font, Vector2(cx + 6, cy + 14), String(fs.ship_id),
			HORIZONTAL_ALIGNMENT_LEFT, FLEET_CARD_W - 12, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		return

	# Ship name (line 1)
	var display_name: String = fs.custom_name if fs.custom_name != "" else String(sd.ship_name)
	var name_col := UITheme.TEXT if not is_selected else UITheme.PRIMARY
	draw_string(font, Vector2(cx + 6, cy + 13), display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, FLEET_CARD_W - 46, UITheme.FONT_SIZE_BODY, name_col)

	# Ship class (line 2, dim)
	draw_string(font, Vector2(cx + 6, cy + 25), String(sd.ship_class).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Weapon dots (line 2, right side) — filled = equipped, empty = vacant
	var hp_count := sd.hardpoints.size()
	var dot_r := 3.0
	var dot_spacing := 9.0
	var dots_x := cx + FLEET_CARD_W - 10 - hp_count * dot_spacing
	for i in hp_count:
		var dot_cx := dots_x + i * dot_spacing + dot_r
		var dot_cy := cy + 22.0
		var weapon_name: StringName = fs.weapons[i] if i < fs.weapons.size() else &""
		if weapon_name != &"":
			var w := WeaponRegistry.get_weapon(weapon_name)
			var wcol: Color = TYPE_COLORS.get(w.weapon_type, UITheme.PRIMARY) if w else UITheme.PRIMARY
			draw_circle(Vector2(dot_cx, dot_cy), dot_r, wcol)
		else:
			draw_arc(Vector2(dot_cx, dot_cy), dot_r, 0, TAU, 8,
				Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.4), 1.0)

	# Hull bar (line 3) — mini bar showing hull HP relative to largest ship
	var bar_x := cx + 6
	var bar_y := cy + 31
	var bar_w := FLEET_CARD_W - 12
	var bar_h := 3.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.15, 0.2, 0.5))
	var hull_ratio := clampf(sd.hull_hp / 5000.0, 0.05, 1.0)  # normalize to 5000 HP max
	var hull_col := UITheme.ACCENT
	draw_rect(Rect2(bar_x, bar_y, bar_w * hull_ratio, bar_h), hull_col)

	# Slot summary (line 4): "2/4W 1S 1E 1/2M"
	var equipped_w := 0
	for wn in fs.weapons:
		if wn != &"":
			equipped_w += 1
	var has_shield := 1 if fs.shield_name != &"" else 0
	var has_engine := 1 if fs.engine_name != &"" else 0
	var equipped_m := 0
	for mn in fs.modules:
		if mn != &"":
			equipped_m += 1
	var slot_str := "%d/%dW %dS %dE %d/%dM" % [equipped_w, hp_count, has_shield, has_engine, equipped_m, sd.module_slots.size()]
	draw_string(font, Vector2(cx + 6, cy + 44), slot_str,
		HORIZONTAL_ALIGNMENT_LEFT, FLEET_CARD_W - 12, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Equipment fill bar (line 5)
	var total_slots := hp_count + 1 + 1 + sd.module_slots.size()  # weapons + shield + engine + modules
	var filled_slots := equipped_w + has_shield + has_engine + equipped_m
	var fill_x := cx + 6
	var fill_y := cy + 50
	var fill_w := FLEET_CARD_W - 12
	var fill_h := 4.0
	draw_rect(Rect2(fill_x, fill_y, fill_w, fill_h), Color(0.1, 0.15, 0.2, 0.5))
	if total_slots > 0:
		var fill_ratio := float(filled_slots) / float(total_slots)
		var fill_col := UITheme.PRIMARY if fill_ratio < 1.0 else UITheme.ACCENT
		draw_rect(Rect2(fill_x, fill_y, fill_w * fill_ratio, fill_h), fill_col)

	# [ACTIF] badge
	if is_active:
		var badge_text := "ACTIF"
		var badge_w := 36.0
		var badge_h := 13.0
		var badge_x := cx + FLEET_CARD_W - badge_w - 4
		var badge_y := cy + FLEET_CARD_H - badge_h - 4
		var badge_col := UITheme.ACCENT
		draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), badge_col, false, 1.0)
		draw_string(font, Vector2(badge_x + 2, badge_y + 10), badge_text,
			HORIZONTAL_ALIGNMENT_CENTER, badge_w - 4, UITheme.FONT_SIZE_TINY, badge_col)


# =============================================================================
# HARDPOINT STRIP (tab 0 — below 3D viewer)
# =============================================================================
func _draw_hardpoint_strip(font: Font, s: Vector2) -> void:
	if _adapter == null:
		return

	var viewer_w := s.x * VIEWER_RATIO
	var strip_y := s.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	draw_panel_bg(strip_rect)
	draw_section_header(28, strip_y + 2, viewer_w - 56, "POINTS D'EMPORT")

	var hp_count: int = _adapter.get_hardpoint_count()
	if hp_count == 0:
		return

	var card_w := minf(140.0, (strip_rect.size.x - 16) / hp_count)
	var total_w := card_w * hp_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y := strip_y + 20
	var card_h: float = HP_STRIP_H - 24

	for i in hp_count:
		var slot_size: String = _adapter.get_hardpoint_slot_size(i)
		var is_turret: bool = _adapter.is_hardpoint_turret(i)
		var mounted: WeaponResource = _adapter.get_mounted_weapon(i)
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, card_y, card_w - 4, card_h)
		var is_selected := i == _selected_hardpoint
		var is_hovered := i == _hp_hovered_index

		# Card background with hover/selection states
		if is_selected:
			var pulse := UITheme.get_pulse(1.0)
			var sel_a := lerpf(0.08, 0.2, pulse)
			draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
			draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
			draw_rect(Rect2(card_x, card_y, 3, card_h), UITheme.PRIMARY)
		elif is_hovered:
			draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
			draw_rect(card_rect, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.7), false, 1.0)
		else:
			draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
			draw_rect(card_rect, UITheme.BORDER, false, 1.0)

		# Row 1: Slot badge [S1] + turret indicator + [X] remove
		var badge_col := _slot_size_color(slot_size)
		var badge_text := "%s%d" % [slot_size, i + 1]
		var bdg_x := card_x + 6
		var bdg_y := card_y + 5
		var bdg_w := 28.0
		var bdg_h := 16.0
		draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), badge_col, false, 1.0)
		draw_string(font, Vector2(bdg_x + 3, bdg_y + 12), badge_text,
			HORIZONTAL_ALIGNMENT_LEFT, bdg_w - 4, UITheme.FONT_SIZE_SMALL, badge_col)

		if is_turret:
			var turret_col := Color(TYPE_COLORS[5].r, TYPE_COLORS[5].g, TYPE_COLORS[5].b, 0.7)
			draw_string(font, Vector2(bdg_x + bdg_w + 4, bdg_y + 12), "TUR",
				HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_TINY, turret_col)

		# [X] Remove button (bigger, easier to click)
		if mounted:
			var xb_sz := 18.0
			var xb_x := card_x + card_w - 4 - xb_sz - 4
			var xb_y := card_y + 4
			var xb_col := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
			draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
			draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
				HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)

		# Row 2: Weapon name
		if mounted:
			var type_col: Color = TYPE_COLORS.get(mounted.weapon_type, UITheme.PRIMARY)
			draw_string(font, Vector2(card_x + 8, card_y + 38), str(mounted.weapon_name),
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, UITheme.FONT_SIZE_BODY, type_col)

			# Row 3: Type icon + type name + DPS
			var stats_y := card_y + 54
			_draw_weapon_icon(Vector2(card_x + 14, stats_y - 2), 5.0, mounted.weapon_type, type_col)
			var type_name: String = TYPE_NAMES[mounted.weapon_type] if mounted.weapon_type < TYPE_NAMES.size() else ""
			var dps := mounted.damage_per_hit * mounted.fire_rate
			draw_string(font, Vector2(card_x + 24, stats_y), "%s  %.0f DPS" % [type_name, dps],
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 32, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		else:
			# Empty slot — clear visual indicator
			var empty_label := "TOURELLE" if is_turret else "VIDE"
			var empty_col := Color(TYPE_COLORS[5].r, TYPE_COLORS[5].g, TYPE_COLORS[5].b, 0.4) if is_turret else UITheme.TEXT_DIM
			draw_string(font, Vector2(card_x, card_y + card_h * 0.5 + 6), empty_label,
				HORIZONTAL_ALIGNMENT_CENTER, card_w - 4, UITheme.FONT_SIZE_BODY, empty_col)


# =============================================================================
# MODULE SLOT STRIP (tab 1 — below 3D viewer)
# =============================================================================
func _draw_module_slot_strip(font: Font, s: Vector2) -> void:
	if _adapter == null:
		return

	var viewer_w := s.x * VIEWER_RATIO
	var strip_y := s.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	draw_panel_bg(strip_rect)
	draw_section_header(28, strip_y + 2, viewer_w - 56, "SLOTS MODULES")

	var slot_count: int = _adapter.get_module_slot_count()
	if slot_count == 0:
		return

	var card_w := minf(160.0, (strip_rect.size.x - 16) / slot_count)
	var total_w := card_w * slot_count
	var start_x := strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y := strip_y + 20
	var card_h: float = HP_STRIP_H - 24

	for i in slot_count:
		var slot_size: String = _adapter.get_module_slot_size(i)
		var mod: ModuleResource = _adapter.get_equipped_module(i)
		var card_x := start_x + i * card_w
		var card_rect := Rect2(card_x, card_y, card_w - 4, card_h)
		var is_selected := i == _selected_module_slot
		var is_hovered := i == _module_hovered_index

		# Card background with hover/selection
		if is_selected:
			var pulse := UITheme.get_pulse(1.0)
			var sel_a := lerpf(0.08, 0.2, pulse)
			draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
			draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
			draw_rect(Rect2(card_x, card_y, 3, card_h), UITheme.PRIMARY)
		elif is_hovered:
			draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
			draw_rect(card_rect, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.7), false, 1.0)
		else:
			draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
			draw_rect(card_rect, UITheme.BORDER, false, 1.0)

		# Row 1: Slot badge [S1/M1]
		var badge_col := _slot_size_color(slot_size)
		var bdg_x := card_x + 6
		var bdg_y := card_y + 5
		var bdg_w := 28.0
		var bdg_h := 16.0
		draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), badge_col, false, 1.0)
		draw_string(font, Vector2(bdg_x + 3, bdg_y + 12), "%s%d" % [slot_size, i + 1],
			HORIZONTAL_ALIGNMENT_LEFT, bdg_w - 4, UITheme.FONT_SIZE_SMALL, badge_col)

		if mod:
			var mod_col: Color = MODULE_COLORS.get(mod.module_type, UITheme.PRIMARY)

			# [X] remove button (18x18)
			var xb_sz := 18.0
			var xb_x := card_x + card_w - 4 - xb_sz - 4
			var xb_y := card_y + 4
			var xb_col := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
			draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
			draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
				HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)

			# Row 2: Module name
			draw_string(font, Vector2(card_x + 8, card_y + 38), str(mod.module_name),
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, UITheme.FONT_SIZE_BODY, mod_col)

			# Row 3: First bonus
			var bonuses := mod.get_bonuses_text()
			if bonuses.size() > 0:
				draw_string(font, Vector2(card_x + 8, card_y + 54), bonuses[0],
					HORIZONTAL_ALIGNMENT_LEFT, card_w - 16, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		else:
			draw_string(font, Vector2(card_x, card_y + card_h * 0.5 + 6), "VIDE",
				HORIZONTAL_ALIGNMENT_CENTER, card_w - 4, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# SHIELD STATUS PANEL (tab 2 — below 3D viewer)
# =============================================================================
func _draw_shield_status_panel(font: Font, s: Vector2) -> void:
	var viewer_w := s.x * VIEWER_RATIO
	var strip_y := s.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	draw_panel_bg(strip_rect)
	draw_section_header(28, strip_y + 2, viewer_w - 56, "BOUCLIER EQUIPE")

	if _adapter == null:
		return

	var y := strip_y + 24
	var sh: ShieldResource = _adapter.get_equipped_shield()
	if sh:
		# Row 1: Shield name + size badge
		draw_string(font, Vector2(32, y + 10), str(sh.shield_name),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w * 0.5, UITheme.FONT_SIZE_BODY, SHIELD_COLOR)

		var slot_str: String = ["S", "M", "L"][sh.slot_size]
		var bdg_col := _slot_size_color(slot_str)
		var bdg_x := 32.0 + font.get_string_size(str(sh.shield_name), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY).x + 8
		bdg_x = minf(bdg_x, viewer_w * 0.45)
		draw_rect(Rect2(bdg_x, y + 1, 22, 14), Color(bdg_col.r, bdg_col.g, bdg_col.b, 0.15))
		draw_rect(Rect2(bdg_x, y + 1, 22, 14), bdg_col, false, 1.0)
		draw_string(font, Vector2(bdg_x + 5, y + 12), slot_str,
			HORIZONTAL_ALIGNMENT_LEFT, 16, UITheme.FONT_SIZE_SMALL, bdg_col)

		# Row 2: Stats on second line
		draw_string(font, Vector2(32, y + 30),
			"%d HP/face  |  %.0f HP/s regen  |  %.1fs delai  |  %.0f%% infiltration" % [
				int(sh.shield_hp_per_facing), sh.regen_rate, sh.regen_delay, sh.bleedthrough * 100],
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		# [X] remove button (bigger)
		var xb_sz := 18.0
		var xb_x := viewer_w - 52
		var xb_y := y + 1
		var xb_col := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
		draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
		draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
			HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)
	else:
		draw_string(font, Vector2(32, y + 20), "Aucun bouclier equipe",
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 60, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# ENGINE STATUS PANEL (tab 3 — below 3D viewer)
# =============================================================================
func _draw_engine_status_panel(font: Font, s: Vector2) -> void:
	var viewer_w := s.x * VIEWER_RATIO
	var strip_y := s.y - HP_STRIP_H - 50
	var strip_rect := Rect2(20, strip_y, viewer_w - 40, HP_STRIP_H)

	draw_panel_bg(strip_rect)
	draw_section_header(28, strip_y + 2, viewer_w - 56, "MOTEUR EQUIPE")

	if _adapter == null:
		return

	var y := strip_y + 24
	var en: EngineResource = _adapter.get_equipped_engine()
	if en:
		# Row 1: Engine name + size badge
		draw_string(font, Vector2(32, y + 10), str(en.engine_name),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w * 0.5, UITheme.FONT_SIZE_BODY, ENGINE_COLOR)

		var slot_str: String = ["S", "M", "L"][en.slot_size]
		var bdg_col := _slot_size_color(slot_str)
		var bdg_x := 32.0 + font.get_string_size(str(en.engine_name), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY).x + 8
		bdg_x = minf(bdg_x, viewer_w * 0.45)
		draw_rect(Rect2(bdg_x, y + 1, 22, 14), Color(bdg_col.r, bdg_col.g, bdg_col.b, 0.15))
		draw_rect(Rect2(bdg_x, y + 1, 22, 14), bdg_col, false, 1.0)
		draw_string(font, Vector2(bdg_x + 5, y + 12), slot_str,
			HORIZONTAL_ALIGNMENT_LEFT, 16, UITheme.FONT_SIZE_SMALL, bdg_col)

		# Row 2: Stats on second line
		draw_string(font, Vector2(32, y + 30),
			"Accel x%.2f  |  Vitesse x%.2f  |  Rotation x%.2f  |  Cruise x%.2f" % [
				en.accel_mult, en.speed_mult, en.rotation_mult, en.cruise_mult],
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		# [X] remove button (bigger)
		var xb_sz := 18.0
		var xb_x := viewer_w - 52
		var xb_y := y + 1
		var xb_col := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
		draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
		draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
			HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)
	else:
		draw_string(font, Vector2(32, y + 20), "Aucun moteur equipe",
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 60, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# 2D PROJECTED LABELS (tab 0 — overlaid on 3D viewer)
# =============================================================================
func _draw_projected_labels(font: Font, viewer_w: float, viewer_h: float) -> void:
	if _viewer_camera == null or _adapter == null or _viewport == null:
		return

	# In LIVE mode use actual hardpoint Node3D positions; in DATA mode use marker positions
	var cam_fwd := -_viewer_camera.global_transform.basis.z
	var hp_count: int = _adapter.get_hardpoint_count()

	for i in hp_count:
		var world_pos := Vector3.ZERO
		if _is_live_mode() and weapon_manager and i < weapon_manager.hardpoints.size():
			world_pos = _ship_root_basis * weapon_manager.hardpoints[i].position
		elif i < _hp_markers.size():
			world_pos = _hp_markers[i].mesh.position

		var to_marker := (world_pos - _viewer_camera.global_position).normalized()
		if cam_fwd.dot(to_marker) < 0.1:
			continue

		if not _viewer_camera.is_position_behind(world_pos):
			var screen_pos := _viewer_camera.unproject_position(world_pos)
			var vp_size := Vector2(_viewport.size)
			if vp_size.x <= 0 or vp_size.y <= 0:
				continue
			var label_x := screen_pos.x / vp_size.x * viewer_w
			var label_y := screen_pos.y / vp_size.y * viewer_h + CONTENT_TOP

			label_x = clampf(label_x, 10.0, viewer_w - 80.0)
			label_y = clampf(label_y, CONTENT_TOP + 10, CONTENT_TOP + viewer_h - 20)

			var slot_size: String = _adapter.get_hardpoint_slot_size(i)
			var is_turret: bool = _adapter.is_hardpoint_turret(i)
			var mounted: WeaponResource = _adapter.get_mounted_weapon(i)
			var label_text := "%s%d" % [slot_size, i + 1]
			if is_turret:
				label_text += " T"
			if mounted:
				label_text += ": " + str(mounted.weapon_name)

			var col := UITheme.TEXT_DIM
			if i == _selected_hardpoint:
				col = UITheme.PRIMARY
			elif mounted:
				col = TYPE_COLORS.get(mounted.weapon_type, UITheme.TEXT_DIM)

			var tw := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
			draw_rect(Rect2(label_x + 8, label_y - 10, tw + 8, 14), Color(0, 0, 0, 0.5))
			draw_string(font, Vector2(label_x + 12, label_y), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, 150, UITheme.FONT_SIZE_SMALL, col)

			draw_line(Vector2(label_x, label_y - 3), Vector2(label_x + 8, label_y - 3), Color(col.r, col.g, col.b, 0.4), 1.0)


# =============================================================================
# ARSENAL DRAW CALLBACK (dispatches by tab)
# =============================================================================
func _draw_arsenal_row(ctrl: Control, index: int, rect: Rect2, _item: Variant) -> void:
	if index < 0 or index >= _arsenal_items.size():
		return

	match _current_tab:
		0: _draw_weapon_row(ctrl, index, rect)
		1: _draw_module_row(ctrl, index, rect)
		2: _draw_shield_row(ctrl, index, rect)
		3: _draw_engine_row(ctrl, index, rect)


func _draw_weapon_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var weapon_name: StringName = _arsenal_items[index]
	var weapon := WeaponRegistry.get_weapon(weapon_name)
	if weapon == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = player_inventory.get_weapon_count(weapon_name) if player_inventory else 0
	var slot_size_str: String = ["S", "M", "L"][weapon.slot_size]
	var compatible := true
	if _selected_hardpoint >= 0 and _adapter:
		var hp_sz: String = _adapter.get_hardpoint_slot_size(_selected_hardpoint)
		var hp_turret: bool = _adapter.is_hardpoint_turret(_selected_hardpoint)
		compatible = player_inventory.is_compatible(weapon_name, hp_sz, hp_turret) if player_inventory else false

	var alpha_mult: float = 1.0 if compatible else 0.3
	var type_col: Color = TYPE_COLORS.get(weapon.weapon_type, UITheme.PRIMARY)
	if not compatible:
		type_col = Color(type_col.r, type_col.g, type_col.b, 0.3)

	var icon_cx := rect.position.x + 24.0
	var icon_cy := rect.position.y + rect.size.y * 0.5
	var icon_r := 16.0
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.15 * alpha_mult), icon_r * 0.7)
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.6 * alpha_mult), 1.5)
	_draw_weapon_icon_on(ctrl, Vector2(icon_cx, icon_cy), 8.0, weapon.weapon_type,
		Color(type_col.r, type_col.g, type_col.b, alpha_mult))

	var text_col := Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x := rect.position.x + 48
	var name_max_w := rect.size.x - 48 - 90  # leave room for badges
	var name_y := rect.position.y + 22
	ctrl.draw_string(font, Vector2(name_x, name_y), str(weapon_name),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var stat_y := name_y + 16
	var dim_col := Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var dps := weapon.damage_per_hit * weapon.fire_rate
	ctrl.draw_string(font, Vector2(name_x, stat_y), "%.0f DPS" % dps,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_shield_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var sn: StringName = _arsenal_items[index]
	var shield := ShieldRegistry.get_shield(sn)
	if shield == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = player_inventory.get_shield_count(sn) if player_inventory else 0
	var slot_size_str: String = ["S", "M", "L"][shield.slot_size]
	var compatible := true
	if _adapter:
		compatible = player_inventory.is_shield_compatible(sn, _adapter.get_shield_slot_size()) if player_inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var col := Color(SHIELD_COLOR.r, SHIELD_COLOR.g, SHIELD_COLOR.b, alpha_mult)

	# Hexagon icon
	var icon_cx := rect.position.x + 24.0
	var icon_cy := rect.position.y + rect.size.y * 0.5
	_draw_shield_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col := Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x := rect.position.x + 48
	var name_max_w := rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(sn),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col := Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38),
		"%d HP/f, %.0f HP/s" % [int(shield.shield_hp_per_facing), shield.regen_rate],
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_engine_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var en: StringName = _arsenal_items[index]
	var engine := EngineRegistry.get_engine(en)
	if engine == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = player_inventory.get_engine_count(en) if player_inventory else 0
	var slot_size_str: String = ["S", "M", "L"][engine.slot_size]
	var compatible := true
	if _adapter:
		compatible = player_inventory.is_engine_compatible(en, _adapter.get_engine_slot_size()) if player_inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var col := Color(ENGINE_COLOR.r, ENGINE_COLOR.g, ENGINE_COLOR.b, alpha_mult)

	# Flame icon
	var icon_cx := rect.position.x + 24.0
	var icon_cy := rect.position.y + rect.size.y * 0.5
	_draw_engine_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col := Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x := rect.position.x + 48
	var name_max_w := rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(en),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	# Key stat highlight
	var dim_col := Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var best_stat := _get_engine_best_stat(engine)
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38), best_stat,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_module_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var mn: StringName = _arsenal_items[index]
	var module := ModuleRegistry.get_module(mn)
	if module == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = player_inventory.get_module_count(mn) if player_inventory else 0
	var slot_size_str: String = ["S", "M", "L"][module.slot_size]
	var compatible := true
	if _selected_module_slot >= 0 and _adapter:
		var slot_sz: String = _adapter.get_module_slot_size(_selected_module_slot)
		compatible = player_inventory.is_module_compatible(mn, slot_sz) if player_inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var mod_col: Color = MODULE_COLORS.get(module.module_type, UITheme.PRIMARY)
	var col := Color(mod_col.r, mod_col.g, mod_col.b, alpha_mult)

	# Module icon
	var icon_cx := rect.position.x + 24.0
	var icon_cy := rect.position.y + rect.size.y * 0.5
	_draw_module_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col := Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x := rect.position.x + 48
	var name_max_w := rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(mn),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col := Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var bonuses := module.get_bonuses_text()
	var bonus_str := bonuses[0] if bonuses.size() > 0 else ""
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38), bonus_str,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


# Shared badge drawing for all arsenal rows
func _draw_qty_and_size_badges(ctrl: Control, font: Font, rect: Rect2,
		count: int, slot_size_str: String, compatible: bool, alpha_mult: float) -> void:
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
# COMPARISON PANEL (dispatches by tab)
# =============================================================================
func _draw_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	match _current_tab:
		0: _draw_weapon_comparison(font, px, start_y, pw)
		1: _draw_module_comparison(font, px, start_y, pw)
		2: _draw_shield_comparison(font, px, start_y, pw)
		3: _draw_engine_comparison(font, px, start_y, pw)


func _draw_no_selection_msg(font: Font, px: float, start_y: float, pw: float, msg: String) -> void:
	var center_x := px + pw * 0.5
	var center_y := start_y + 40
	var cr := 14.0
	draw_arc(Vector2(center_x, center_y), cr, 0, TAU, 24, UITheme.TEXT_DIM, 1.0)
	draw_line(Vector2(center_x - cr - 5, center_y), Vector2(center_x - cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
	draw_line(Vector2(center_x + cr - 5, center_y), Vector2(center_x + cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
	draw_line(Vector2(center_x, center_y - cr - 5), Vector2(center_x, center_y - cr + 5), UITheme.TEXT_DIM, 1.0)
	draw_line(Vector2(center_x, center_y + cr - 5), Vector2(center_x, center_y + cr + 5), UITheme.TEXT_DIM, 1.0)
	draw_string(font, Vector2(px, center_y + 22), msg,
		HORIZONTAL_ALIGNMENT_CENTER, pw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	# Hint about double-click
	draw_string(font, Vector2(px, center_y + 38), "Double-clic = equipement rapide",
		HORIZONTAL_ALIGNMENT_CENTER, pw, UITheme.FONT_SIZE_TINY, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.35))


func _draw_weapon_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	if _selected_hardpoint < 0 or _selected_weapon == &"":
		_draw_no_selection_msg(font, px, start_y, pw, "Selectionnez un point d'emport et une arme")
		return

	var new_weapon := WeaponRegistry.get_weapon(_selected_weapon)
	if new_weapon == null:
		return

	var current_weapon: WeaponResource = null
	if _adapter:
		current_weapon = _adapter.get_mounted_weapon(_selected_hardpoint)

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

	var stats: Array = [
		["DEGATS", cur_dmg, new_dmg, true],
		["CADENCE", cur_rate, new_rate, true],
		["DPS", cur_dps, new_dps, true],
		["ENERGIE", cur_energy, new_energy, false],
		["PORTEE", cur_range, new_range, true],
	]
	_draw_stat_rows(font, px, start_y, pw, stats)


func _draw_shield_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	if _selected_shield == &"":
		_draw_no_selection_msg(font, px, start_y, pw, "Selectionnez un bouclier")
		return

	var new_shield := ShieldRegistry.get_shield(_selected_shield)
	if new_shield == null:
		return

	var cur: ShieldResource = _adapter.get_equipped_shield() if _adapter else null

	var cur_cap := cur.shield_hp_per_facing if cur else 0.0
	var new_cap := new_shield.shield_hp_per_facing
	var cur_regen := cur.regen_rate if cur else 0.0
	var new_regen := new_shield.regen_rate
	var cur_delay := cur.regen_delay if cur else 0.0
	var new_delay := new_shield.regen_delay
	var cur_bleed := (cur.bleedthrough * 100) if cur else 0.0
	var new_bleed := new_shield.bleedthrough * 100

	var stats: Array = [
		["CAPACITE", cur_cap, new_cap, true],
		["REGEN", cur_regen, new_regen, true],
		["DELAI", cur_delay, new_delay, false],
		["INFILTRATION", cur_bleed, new_bleed, false],
	]
	_draw_stat_rows(font, px, start_y, pw, stats)


func _draw_engine_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	if _selected_engine == &"":
		_draw_no_selection_msg(font, px, start_y, pw, "Selectionnez un moteur")
		return

	var new_engine := EngineRegistry.get_engine(_selected_engine)
	if new_engine == null:
		return

	var cur: EngineResource = _adapter.get_equipped_engine() if _adapter else null

	var stats: Array = [
		["ACCELERATION", cur.accel_mult if cur else 1.0, new_engine.accel_mult, true],
		["VITESSE", cur.speed_mult if cur else 1.0, new_engine.speed_mult, true],
		["CRUISE", cur.cruise_mult if cur else 1.0, new_engine.cruise_mult, true],
		["ROTATION", cur.rotation_mult if cur else 1.0, new_engine.rotation_mult, true],
		["CONSO BOOST", cur.boost_drain_mult if cur else 1.0, new_engine.boost_drain_mult, false],
	]
	_draw_stat_rows(font, px, start_y, pw, stats)


func _draw_module_comparison(font: Font, px: float, start_y: float, pw: float) -> void:
	if _selected_module_slot < 0 or _selected_module == &"":
		_draw_no_selection_msg(font, px, start_y, pw, "Selectionnez un slot et un module")
		return

	var new_mod := ModuleRegistry.get_module(_selected_module)
	if new_mod == null:
		return

	var cur: ModuleResource = null
	if _adapter:
		cur = _adapter.get_equipped_module(_selected_module_slot)

	var stats: Array = []
	# Show all non-zero stats from new module (and current if present)
	if new_mod.hull_bonus > 0 or (cur and cur.hull_bonus > 0):
		stats.append(["COQUE", cur.hull_bonus if cur else 0.0, new_mod.hull_bonus, true])
	if new_mod.armor_bonus > 0 or (cur and cur.armor_bonus > 0):
		stats.append(["BLINDAGE", cur.armor_bonus if cur else 0.0, new_mod.armor_bonus, true])
	if new_mod.energy_cap_bonus > 0 or (cur and cur.energy_cap_bonus > 0):
		stats.append(["ENERGIE MAX", cur.energy_cap_bonus if cur else 0.0, new_mod.energy_cap_bonus, true])
	if new_mod.energy_regen_bonus > 0 or (cur and cur.energy_regen_bonus > 0):
		stats.append(["REGEN ENERGIE", cur.energy_regen_bonus if cur else 0.0, new_mod.energy_regen_bonus, true])
	if new_mod.shield_regen_mult != 1.0 or (cur and cur.shield_regen_mult != 1.0):
		stats.append(["REGEN BOUCLIER", (cur.shield_regen_mult if cur else 1.0) * 100, new_mod.shield_regen_mult * 100, true])
	if new_mod.shield_cap_mult != 1.0 or (cur and cur.shield_cap_mult != 1.0):
		stats.append(["CAP BOUCLIER", (cur.shield_cap_mult if cur else 1.0) * 100, new_mod.shield_cap_mult * 100, true])
	if new_mod.weapon_energy_mult != 1.0 or (cur and cur.weapon_energy_mult != 1.0):
		stats.append(["CONSO ARMES", (cur.weapon_energy_mult if cur else 1.0) * 100, new_mod.weapon_energy_mult * 100, false])
	if new_mod.weapon_range_mult != 1.0 or (cur and cur.weapon_range_mult != 1.0):
		stats.append(["PORTEE ARMES", (cur.weapon_range_mult if cur else 1.0) * 100, new_mod.weapon_range_mult * 100, true])

	if stats.is_empty():
		_draw_no_selection_msg(font, px, start_y, pw, "Module sans bonus mesurable")
		return

	_draw_stat_rows(font, px, start_y, pw, stats)


# Shared stat row renderer
func _draw_stat_rows(font: Font, px: float, start_y: float, pw: float, stats: Array) -> void:
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

		draw_string(font, Vector2(label_x, ry + 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, 90, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)

		draw_string(font, Vector2(val_x, ry + 10), _format_stat(cur_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_LABEL, UITheme.TEXT)

		if absf(delta) > 0.01:
			var arr_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			draw_string(font, Vector2(new_val_x - 12, ry + 10), ">",
				HORIZONTAL_ALIGNMENT_LEFT, 10, UITheme.FONT_SIZE_LABEL, arr_col)

		var new_text_col := UITheme.TEXT
		if is_better:
			new_text_col = UITheme.ACCENT
		elif is_worse:
			new_text_col = UITheme.DANGER
		draw_string(font, Vector2(new_val_x, ry + 10), _format_stat(new_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_LABEL, new_text_col)

		if absf(delta) > 0.01:
			var delta_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			var sign_str := "+" if delta > 0.0 else ""
			draw_string(font, Vector2(delta_x - 60, ry + 10), sign_str + _format_stat(delta, label),
				HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_LABEL, delta_col)


func _format_stat(val: float, label: String) -> String:
	match label:
		"CADENCE":
			return "%.1f/s" % val
		"PORTEE":
			if val >= 1000.0:
				return "%.1f km" % (val / 1000.0)
			return "%.0f m" % val
		"ENERGIE", "DELAI":
			return "%.1f" % val
		"ACCELERATION", "VITESSE", "CRUISE", "ROTATION", "CONSO BOOST":
			return "x%.2f" % val
		"INFILTRATION":
			return "%.0f%%" % val
		"REGEN BOUCLIER", "CAP BOUCLIER", "CONSO ARMES", "PORTEE ARMES":
			return "%.0f%%" % val
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
		5:  # TURRET
			draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), Color(col.r, col.g, col.b, 0.4))
			draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), col, false, 1.5)
			draw_line(center + Vector2(0, 0), center + Vector2(0, -r * 0.6), col, 1.5)
			draw_circle(center + Vector2(0, -r * 0.6), r * 0.25, col)


func _draw_weapon_icon_on(ctrl: Control, center: Vector2, r: float, weapon_type: int, col: Color) -> void:
	match weapon_type:
		0:
			ctrl.draw_line(center + Vector2(-r, -r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_circle(center + Vector2(r, 0), 2.0, col)
		1:
			ctrl.draw_circle(center, r * 0.65, Color(col.r, col.g, col.b, 0.4))
			ctrl.draw_arc(center, r * 0.65, 0, TAU, 12, col, 1.5)
			ctrl.draw_circle(center, r * 0.25, col)
		2:
			var pts := PackedVector2Array([
				center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.5),
				center + Vector2(-r * 0.3, 0), center + Vector2(-r * 0.5, r * 0.5),
			])
			ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.4))
			pts.append(pts[0])
			ctrl.draw_polyline(pts, col, 1.5)
		3:
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 2.0)
			ctrl.draw_circle(center + Vector2(-r, 0), 2.5, col)
			ctrl.draw_circle(center + Vector2(r, 0), 2.5, col)
		4:
			ctrl.draw_arc(center, r * 0.45, 0, TAU, 12, col, 1.5)
			for spike_i in 6:
				var angle := TAU * spike_i / 6.0
				var inner_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.45
				var outer_pt := center + Vector2(cos(angle), sin(angle)) * r * 0.9
				ctrl.draw_line(inner_pt, outer_pt, col, 1.5)
				ctrl.draw_circle(outer_pt, 1.5, col)
		5:  # TURRET
			ctrl.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), Color(col.r, col.g, col.b, 0.4))
			ctrl.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), col, false, 1.5)
			ctrl.draw_line(center + Vector2(0, 0), center + Vector2(0, -r * 0.6), col, 1.5)
			ctrl.draw_circle(center + Vector2(0, -r * 0.6), r * 0.25, col)


func _draw_shield_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	# Hexagon
	for seg in 6:
		var a1 := TAU * seg / 6.0 - PI / 6.0
		var a2 := TAU * (seg + 1) / 6.0 - PI / 6.0
		ctrl.draw_line(
			center + Vector2(cos(a1), sin(a1)) * r,
			center + Vector2(cos(a2), sin(a2)) * r,
			col, 1.5)
	# Inner arc
	ctrl.draw_arc(center, r * 0.5, -PI * 0.3, PI * 0.3, 8, col, 1.5)


func _draw_engine_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	# Flame/thrust shape
	var pts := PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r * 0.5, -r * 0.3),
		center + Vector2(r * 0.3, r * 0.5),
		center + Vector2(0, r * 0.2),
		center + Vector2(-r * 0.3, r * 0.5),
		center + Vector2(-r * 0.5, -r * 0.3),
	])
	ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5)
	# Exhaust lines
	ctrl.draw_line(center + Vector2(-r * 0.15, r * 0.5), center + Vector2(-r * 0.15, r), Color(col.r, col.g, col.b, 0.5), 1.0)
	ctrl.draw_line(center + Vector2(r * 0.15, r * 0.5), center + Vector2(r * 0.15, r), Color(col.r, col.g, col.b, 0.5), 1.0)


func _draw_module_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	# Chip/circuit shape
	ctrl.draw_rect(Rect2(center.x - r * 0.6, center.y - r * 0.6, r * 1.2, r * 1.2),
		Color(col.r, col.g, col.b, 0.2))
	ctrl.draw_rect(Rect2(center.x - r * 0.6, center.y - r * 0.6, r * 1.2, r * 1.2), col, false, 1.5)
	# Pin lines
	for i in 3:
		var offset := (i - 1) * r * 0.35
		ctrl.draw_line(center + Vector2(-r * 0.6, offset), center + Vector2(-r, offset), col, 1.0)
		ctrl.draw_line(center + Vector2(r * 0.6, offset), center + Vector2(r, offset), col, 1.0)
	# Inner dot
	ctrl.draw_circle(center, r * 0.15, col)


# =============================================================================
# INTERACTION
# =============================================================================
func _on_tab_changed(index: int) -> void:
	_current_tab = index
	# Reset all selections when switching tab
	_selected_hardpoint = -1
	_selected_weapon = &""
	_selected_shield = &""
	_selected_engine = &""
	_selected_module = &""
	_selected_module_slot = -1
	_hp_hovered_index = -1
	_module_hovered_index = -1
	_arsenal_list.visible = true
	if _arsenal_list:
		_arsenal_list.selected_index = -1
	# Auto-select first empty slot for the new tab
	_auto_select_slot()
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	queue_redraw()


func _on_arsenal_selected(index: int) -> void:
	if index >= 0 and index < _arsenal_items.size():
		var item_name: StringName = _arsenal_items[index]
		match _current_tab:
			0: _selected_weapon = item_name
			1: _selected_module = item_name
			2: _selected_shield = item_name
			3: _selected_engine = item_name
	else:
		match _current_tab:
			0: _selected_weapon = &""
			1: _selected_module = &""
			2: _selected_shield = &""
			3: _selected_engine = &""
	_update_button_states()
	queue_redraw()


func _on_arsenal_double_clicked(index: int) -> void:
	if index < 0 or index >= _arsenal_items.size():
		return
	# Select the item first
	_on_arsenal_selected(index)
	# Then immediately equip if possible
	_on_equip_pressed()


func _on_equip_pressed() -> void:
	match _current_tab:
		0: _equip_weapon()
		1: _equip_module()
		2: _equip_shield()
		3: _equip_engine()


func _on_remove_pressed() -> void:
	match _current_tab:
		0: _remove_weapon()
		1: _remove_module()
		2: _remove_shield()
		3: _remove_engine()


func _on_back_pressed() -> void:
	close()


# --- Equip/Remove per type ---

func _equip_weapon() -> void:
	if _selected_hardpoint < 0 or _selected_weapon == &"" or _adapter == null:
		return
	_adapter.equip_weapon(_selected_hardpoint, _selected_weapon)
	_selected_weapon = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	_refresh_viewer_weapons()
	queue_redraw()


func _remove_weapon() -> void:
	if _selected_hardpoint < 0 or _adapter == null:
		return
	_adapter.remove_weapon(_selected_hardpoint)
	_selected_weapon = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	_update_marker_visuals()
	_refresh_viewer_weapons()
	queue_redraw()


func _equip_shield() -> void:
	if _selected_shield == &"" or _adapter == null:
		return
	_adapter.equip_shield(_selected_shield)
	_selected_shield = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _remove_shield() -> void:
	if _adapter == null:
		return
	_adapter.remove_shield()
	_selected_shield = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _equip_engine() -> void:
	if _selected_engine == &"" or _adapter == null:
		return
	_adapter.equip_engine(_selected_engine)
	_selected_engine = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _remove_engine() -> void:
	if _adapter == null:
		return
	_adapter.remove_engine()
	_selected_engine = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _equip_module() -> void:
	if _selected_module_slot < 0 or _selected_module == &"" or _adapter == null:
		return
	_adapter.equip_module(_selected_module_slot, _selected_module)
	_selected_module = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _remove_module() -> void:
	if _selected_module_slot < 0 or _adapter == null:
		return
	_adapter.remove_module(_selected_module_slot)
	_selected_module = &""
	_arsenal_list.selected_index = -1
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


# =============================================================================
# HELPERS
# =============================================================================
func _refresh_arsenal() -> void:
	_arsenal_items.clear()
	if player_inventory == null:
		_arsenal_list.items = []
		_arsenal_list.queue_redraw()
		return

	match _current_tab:
		0:  # Weapons
			if _selected_hardpoint >= 0 and _adapter:
				var hp_sz: String = _adapter.get_hardpoint_slot_size(_selected_hardpoint)
				var hp_turret: bool = _adapter.is_hardpoint_turret(_selected_hardpoint)
				_arsenal_items = player_inventory.get_weapons_for_slot(hp_sz, hp_turret)
			else:
				_arsenal_items = player_inventory.get_all_weapons()
		1:  # Modules
			if _selected_module_slot >= 0 and _adapter:
				var slot_sz: String = _adapter.get_module_slot_size(_selected_module_slot)
				_arsenal_items = player_inventory.get_modules_for_slot(slot_sz)
			else:
				_arsenal_items = player_inventory.get_all_modules()
		2:  # Shields
			if _adapter:
				_arsenal_items = player_inventory.get_shields_for_slot(_adapter.get_shield_slot_size())
			else:
				_arsenal_items = player_inventory.get_all_shields()
		3:  # Engines
			if _adapter:
				_arsenal_items = player_inventory.get_engines_for_slot(_adapter.get_engine_slot_size())
			else:
				_arsenal_items = player_inventory.get_all_engines()

	var list_items: Array = []
	for item_name in _arsenal_items:
		list_items.append(item_name)
	_arsenal_list.items = list_items
	_arsenal_list.selected_index = -1
	_arsenal_list._scroll_offset = 0.0
	_arsenal_list.queue_redraw()


func _update_button_states() -> void:
	var can_equip := false
	var can_remove := false

	match _current_tab:
		0:  # Weapons
			if _selected_hardpoint >= 0 and _selected_weapon != &"" and _adapter and player_inventory:
				var hp_sz: String = _adapter.get_hardpoint_slot_size(_selected_hardpoint)
				var hp_turret: bool = _adapter.is_hardpoint_turret(_selected_hardpoint)
				can_equip = player_inventory.is_compatible(_selected_weapon, hp_sz, hp_turret) and player_inventory.has_weapon(_selected_weapon)
			if _selected_hardpoint >= 0 and _adapter:
				can_remove = _adapter.get_mounted_weapon(_selected_hardpoint) != null
		1:  # Modules
			if _selected_module_slot >= 0 and _selected_module != &"" and _adapter and player_inventory:
				var slot_sz: String = _adapter.get_module_slot_size(_selected_module_slot)
				can_equip = player_inventory.is_module_compatible(_selected_module, slot_sz) and player_inventory.has_module(_selected_module)
			if _selected_module_slot >= 0 and _adapter:
				can_remove = _adapter.get_equipped_module(_selected_module_slot) != null
		2:  # Shields
			if _selected_shield != &"" and _adapter and player_inventory:
				can_equip = player_inventory.is_shield_compatible(_selected_shield, _adapter.get_shield_slot_size()) and player_inventory.has_shield(_selected_shield)
			if _adapter:
				can_remove = _adapter.get_equipped_shield() != null
		3:  # Engines
			if _selected_engine != &"" and _adapter and player_inventory:
				can_equip = player_inventory.is_engine_compatible(_selected_engine, _adapter.get_engine_slot_size()) and player_inventory.has_engine(_selected_engine)
			if _adapter:
				can_remove = _adapter.get_equipped_engine() != null

	_equip_btn.enabled = can_equip
	_remove_btn.enabled = can_remove


func _get_current_stock_count() -> int:
	if player_inventory == null:
		return 0
	var total := 0
	match _current_tab:
		0:
			for wn in player_inventory.get_all_weapons():
				total += player_inventory.get_weapon_count(wn)
		1:
			for mn in player_inventory.get_all_modules():
				total += player_inventory.get_module_count(mn)
		2:
			for sn in player_inventory.get_all_shields():
				total += player_inventory.get_shield_count(sn)
		3:
			for en in player_inventory.get_all_engines():
				total += player_inventory.get_engine_count(en)
	return total


func _get_engine_best_stat(engine: EngineResource) -> String:
	var best := ""
	var best_val := 0.0
	if absf(engine.accel_mult - 1.0) > best_val:
		best_val = absf(engine.accel_mult - 1.0)
		best = "%+.0f%% ACCEL" % ((engine.accel_mult - 1.0) * 100)
	if absf(engine.speed_mult - 1.0) > best_val:
		best_val = absf(engine.speed_mult - 1.0)
		best = "%+.0f%% VITESSE" % ((engine.speed_mult - 1.0) * 100)
	if absf(engine.cruise_mult - 1.0) > best_val:
		best_val = absf(engine.cruise_mult - 1.0)
		best = "%+.0f%% CRUISE" % ((engine.cruise_mult - 1.0) * 100)
	if absf(engine.rotation_mult - 1.0) > best_val:
		best_val = absf(engine.rotation_mult - 1.0)
		best = "%+.0f%% ROTATION" % ((engine.rotation_mult - 1.0) * 100)
	if best == "":
		best = "Standard"
	return best


func _get_strip_card_at(mouse_pos: Vector2) -> int:
	if _adapter == null:
		return -1
	var viewer_w := size.x * VIEWER_RATIO
	var strip_y := size.y - HP_STRIP_H - 50
	var strip_w := viewer_w - 40
	var count: int = 0
	var max_cw: float = 140.0
	if _current_tab == 0:
		count = _adapter.get_hardpoint_count()
	elif _current_tab == 1:
		count = _adapter.get_module_slot_count()
		max_cw = 160.0
	if count == 0:
		return -1
	var card_w := minf(max_cw, (strip_w - 16) / count)
	var total_w := card_w * count
	var start_x := 20.0 + (strip_w - total_w) * 0.5
	var card_y := strip_y + 20
	var card_h: float = HP_STRIP_H - 24
	for i in count:
		var cx := start_x + i * card_w
		if Rect2(cx, card_y, card_w - 4, card_h).has_point(mouse_pos):
			return i
	return -1


func _slot_size_color(s: String) -> Color:
	match s:
		"S": return UITheme.PRIMARY
		"M": return UITheme.WARNING
		"L": return Color(1.0, 0.5, 0.15, 0.9)
	return UITheme.TEXT_DIM


# =============================================================================
# FLEET SHIP SELECTION
# =============================================================================
func _is_live_mode() -> bool:
	return player_fleet != null and _selected_fleet_index == player_fleet.active_index


func _is_station_mode() -> bool:
	return station_equip_adapter != null


func _get_fleet_card_at(mouse_x: float) -> int:
	if player_fleet == null or player_fleet.ships.is_empty():
		return -1
	var s := size
	var cards_area_x := 28.0
	var cards_area_w := s.x - 40 - 16
	var card_step := FLEET_CARD_W + FLEET_CARD_GAP
	var total_cards_w := card_step * player_fleet.ships.size() - FLEET_CARD_GAP

	var base_x: float
	if total_cards_w <= cards_area_w:
		base_x = cards_area_x + (cards_area_w - total_cards_w) * 0.5
	else:
		base_x = cards_area_x - _fleet_scroll_offset

	for i in player_fleet.ships.size():
		var cx := base_x + i * card_step
		if mouse_x >= cx and mouse_x <= cx + FLEET_CARD_W:
			return i
	return -1


func _create_adapter() -> void:
	# Station mode: use station adapter directly
	if _is_station_mode() and station_equip_adapter:
		_adapter = station_equip_adapter
		_adapter.loadout_changed.connect(_on_adapter_loadout_changed)
		return

	if player_fleet == null:
		return
	var fs: FleetShip = player_fleet.ships[_selected_fleet_index] if _selected_fleet_index < player_fleet.ships.size() else null
	if fs == null:
		return
	if _is_live_mode() and weapon_manager and equipment_manager:
		_adapter = FleetShipEquipAdapter.create_live(weapon_manager, equipment_manager, fs, player_inventory)
	else:
		_adapter = FleetShipEquipAdapter.create_data(fs, player_inventory)
	_adapter.loadout_changed.connect(_on_adapter_loadout_changed)


func _on_adapter_loadout_changed() -> void:
	_refresh_viewer_weapons()
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _on_fleet_ship_selected(idx: int) -> void:
	if idx == _selected_fleet_index:
		return
	_selected_fleet_index = idx

	# Disconnect old adapter signal
	if _adapter and _adapter.loadout_changed.is_connected(_on_adapter_loadout_changed):
		_adapter.loadout_changed.disconnect(_on_adapter_loadout_changed)

	_create_adapter()

	# Update title
	screen_title = "FLOTTE — EQUIPEMENT"

	# Reload 3D viewer for selected ship
	_reload_ship_viewer_for_fleet_ship()

	# Reset selections
	_selected_hardpoint = -1
	_selected_weapon = &""
	_selected_shield = &""
	_selected_engine = &""
	_selected_module = &""
	_selected_module_slot = -1
	_hp_hovered_index = -1
	_module_hovered_index = -1
	_current_tab = 0
	if _tab_bar:
		_tab_bar.current_tab = 0

	_auto_select_slot()
	_refresh_arsenal()
	_update_button_states()
	queue_redraw()


func _reload_ship_viewer_for_fleet_ship() -> void:
	if player_fleet == null or _selected_fleet_index >= player_fleet.ships.size():
		return
	var fs: FleetShip = player_fleet.ships[_selected_fleet_index]
	var sd := ShipRegistry.get_ship_data(fs.ship_id)
	if sd == null:
		return

	_ship_model_path = sd.model_path
	_ship_model_scale = ShipFactory.get_scene_model_scale(fs.ship_id)
	_ship_model_rotation = ShipFactory.get_model_rotation(fs.ship_id)
	_ship_center_offset = ShipFactory.get_center_offset(fs.ship_id)
	_ship_root_basis = ShipFactory.get_root_basis(fs.ship_id)

	# Recreate the 3D viewer with new model
	_setup_3d_viewer()
	_layout_controls()
