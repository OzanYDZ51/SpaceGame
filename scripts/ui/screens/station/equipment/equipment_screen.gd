class_name EquipmentScreen
extends UIScreen

# =============================================================================
# Equipment Screen — Orchestrator
# Wires EquipmentViewer, EquipmentStrip, EquipmentSidebar, EquipmentActions
# =============================================================================

signal equipment_closed

const EC =preload("res://scripts/ui/screens/station/equipment/equipment_constants.gd")

var player_inventory = null
var weapon_manager = null
var equipment_manager = null
var player_fleet = null

# --- Station mode (set externally before opening) ---
var station_equip_adapter = null

# --- Adapter ---
var _adapter: RefCounted = null
var _selected_fleet_index: int = 0

# --- Selection state ---
var _selected_hardpoint: int = -1
var _selected_weapon: StringName = &""
var _selected_shield: StringName = &""
var _selected_engine: StringName = &""
var _selected_module: StringName = &""
var _selected_module_slot: int = -1
var _current_tab: int = 0

# --- Ship viewer config ---
var _ship_model_path: String = "res://assets/models/tie.glb"
var _ship_model_scale: float = 1.0
var _ship_model_rotation: Vector3 = Vector3.ZERO
var _ship_center_offset: Vector3 = Vector3.ZERO
var _ship_root_basis: Basis = Basis.IDENTITY

# --- Sub-views ---
var _viewer: EquipmentViewer = null
var _strip: EquipmentStrip = null
var _sidebar: EquipmentSidebar = null
var _actions: EquipmentActions = null

# --- UI controls ---
var _tab_bar: UITabBar = null
var _equip_btn: UIButton = null
var _remove_btn: UIButton = null
var _back_btn: UIButton = null


func _ready() -> void:
	screen_title = "FLOTTE — EQUIPEMENT"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Sub-views (persistent children)
	_viewer = EquipmentViewer.new()
	_viewer.name = "EquipmentViewer"
	_viewer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewer.visible = false
	add_child(_viewer)

	_strip = EquipmentStrip.new()
	_strip.name = "EquipmentStrip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.visible = false
	add_child(_strip)

	_sidebar = EquipmentSidebar.new()
	_sidebar.name = "EquipmentSidebar"
	_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.visible = false
	add_child(_sidebar)

	# Tab bar
	_tab_bar = UITabBar.new()
	_tab_bar.tabs = EC.TAB_NAMES
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.visible = false
	add_child(_tab_bar)

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

	# Wire sub-view signals
	_viewer.hardpoint_selected.connect(_on_viewer_hardpoint_selected)
	_strip.fleet_ship_selected.connect(_on_fleet_ship_selected)
	_strip.hardpoint_clicked.connect(_on_strip_hardpoint_clicked)
	_strip.module_slot_clicked.connect(_on_strip_module_slot_clicked)
	_strip.shield_remove_requested.connect(_on_shield_remove)
	_strip.engine_remove_requested.connect(_on_engine_remove)
	_strip.weapon_remove_requested.connect(_on_strip_weapon_remove)
	_strip.module_remove_requested.connect(_on_strip_module_remove)
	_sidebar.arsenal_selected.connect(_on_arsenal_selected)
	_sidebar.arsenal_double_clicked.connect(_on_arsenal_double_clicked)


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

	if _tab_bar:
		_tab_bar.tabs = EC.TAB_NAMES_STATION if _is_station_mode() else EC.TAB_NAMES
		_tab_bar.current_tab = 0

	if _is_station_mode():
		screen_title = "STATION — EQUIPEMENT"
		var station_center =StationHardpointConfig.get_station_center()
		setup_ship_viewer("res://assets/models/babbage_station.glb", 0.01, station_center, Vector3.ZERO, Basis.IDENTITY)
	else:
		screen_title = "FLOTTE — EQUIPEMENT"

	if player_fleet and not _is_station_mode():
		_selected_fleet_index = player_fleet.active_index
	else:
		_selected_fleet_index = 0
	_create_adapter()

	_viewer.setup(_adapter, _ship_model_path, _ship_model_scale, _ship_center_offset,
		_ship_model_rotation, _ship_root_basis, weapon_manager,
		_is_live_mode(), _is_station_mode())

	_strip.setup(_adapter, player_fleet, _selected_fleet_index, _is_station_mode())
	_sidebar.setup(_adapter, player_inventory)
	_sidebar.set_tab(_current_tab)
	_auto_select_slot()
	_sidebar.set_selected_hardpoint(_selected_hardpoint)
	_sidebar.set_selected_module_slot(_selected_module_slot)

	_layout_controls()

	_tab_bar.visible = true
	_equip_btn.visible = true
	_remove_btn.visible = true
	_back_btn.visible = true
	_viewer.visible = true
	_strip.visible = true
	_sidebar.visible = true
	_sidebar.show_list()
	_update_button_states()


func _on_closed() -> void:
	_viewer.cleanup()
	_viewer.visible = false
	_strip.visible = false
	_sidebar.visible = false
	_sidebar.hide_list()
	_tab_bar.visible = false
	_equip_btn.visible = false
	_remove_btn.visible = false
	_back_btn.visible = false

	if _adapter and _adapter.loadout_changed.is_connected(_on_adapter_loadout_changed):
		_adapter.loadout_changed.disconnect(_on_adapter_loadout_changed)
	_adapter = null
	_actions = null
	station_equip_adapter = null
	equipment_closed.emit()


# =============================================================================
# PROCESS
# =============================================================================
func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _current_tab == 0 and _adapter:
		_viewer.update_marker_visuals(_selected_hardpoint)
	queue_redraw()


# =============================================================================
# INPUT
# =============================================================================
func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		accept_event()
		return

	# Close [X] button
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var close_x =size.x - UITheme.MARGIN_SCREEN - 28
		var close_y =UITheme.MARGIN_SCREEN
		var close_rect =Rect2(close_x, close_y, 32, 28)
		if close_rect.has_point(event.position):
			close()
			accept_event()
			return

	# Fleet strip
	if _strip.handle_fleet_input(event, size):
		accept_event()
		return

	# Bottom strip hover
	_strip.handle_strip_hover(event, size)

	# Strip clicks (before viewer, since strip overlaps viewer X range)
	if _strip.handle_strip_click(event, size):
		accept_event()
		return

	# 3D viewer area (orbit camera)
	var viewer_w =size.x * EC.VIEWER_RATIO
	var strip_top =size.y - EC.HP_STRIP_H - 50
	if _current_tab == 0:
		if _viewer.handle_input(event, viewer_w, strip_top):
			accept_event()
			return
	else:
		# Non-weapon tabs still need orbit
		if _viewer.handle_input(event, viewer_w, strip_top):
			accept_event()
			return

	accept_event()


# =============================================================================
# LAYOUT
# =============================================================================
func _layout_controls() -> void:
	var s =size
	var viewer_w =s.x * EC.VIEWER_RATIO
	var sidebar_x =viewer_w
	var sidebar_w =s.x * EC.SIDEBAR_RATIO
	var sidebar_pad =16.0

	# Viewer
	_viewer.layout(Vector2(0, EC.CONTENT_TOP), Vector2(viewer_w, s.y - EC.CONTENT_TOP - EC.HP_STRIP_H - 20))

	# Tab bar
	var tab_y =EC.CONTENT_TOP + 6.0
	_tab_bar.position = Vector2(sidebar_x + sidebar_pad, tab_y)
	_tab_bar.size = Vector2(sidebar_w - sidebar_pad * 2, EC.TAB_H)

	# Arsenal list
	var arsenal_top =tab_y + EC.TAB_H + 28.0
	var list_top =arsenal_top + 16.0
	var list_bottom =s.y - EC.COMPARE_H - 100
	_sidebar.layout_list(Vector2(sidebar_x + sidebar_pad + 4, list_top),
		Vector2(sidebar_w - sidebar_pad * 2 - 8, list_bottom - list_top))

	# Buttons
	var btn_y =s.y - 62
	var btn_total =EC.BTN_W * 3 + 20
	var btn_x =sidebar_x + (sidebar_w - btn_total) * 0.5
	_equip_btn.position = Vector2(btn_x, btn_y)
	_equip_btn.size = Vector2(EC.BTN_W, EC.BTN_H)
	_remove_btn.position = Vector2(btn_x + EC.BTN_W + 10, btn_y)
	_remove_btn.size = Vector2(EC.BTN_W, EC.BTN_H)
	_back_btn.position = Vector2(btn_x + (EC.BTN_W + 10) * 2, btn_y)
	_back_btn.size = Vector2(EC.BTN_W, EC.BTN_H)


# =============================================================================
# DRAW
# =============================================================================
func _draw() -> void:
	var s =size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.55))
	draw_rect(Rect2(0, 0, s.x, 44), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 34, s.x, 34), Color(0.0, 0.0, 0.02, 0.5))

	_draw_title(s)

	if not _is_open:
		return

	var font: Font = UITheme.get_font()
	var viewer_w =s.x * EC.VIEWER_RATIO
	var sidebar_x =viewer_w
	var sidebar_w =s.x * EC.SIDEBAR_RATIO
	var sidebar_pad =16.0

	# Fleet strip
	_strip.draw_fleet_strip(self, font, s)

	# Viewer divider
	draw_line(Vector2(viewer_w, EC.CONTENT_TOP), Vector2(viewer_w, s.y - 40), UITheme.BORDER, 1.0)

	# Bottom strip
	_strip.draw_bottom_strip(self, font, s)

	# Projected labels (tab 0 only)
	if _current_tab == 0:
		_viewer.draw_projected_labels(self, font, viewer_w, s.y - EC.CONTENT_TOP - EC.HP_STRIP_H - 20, _selected_hardpoint)

	# Sidebar background
	var tab_y =EC.CONTENT_TOP + 6.0
	var arsenal_header_y =tab_y + EC.TAB_H + 8.0
	var sb_top =arsenal_header_y - 4.0
	var sb_bottom =s.y - 72.0
	var sb_rect =Rect2(sidebar_x + sidebar_pad - 2, sb_top,
		sidebar_w - sidebar_pad * 2 + 4, sb_bottom - sb_top)
	draw_panel_bg(sb_rect)

	# Arsenal header
	var header_names =["ARSENAL", "MODULES DISPO.", "BOUCLIERS DISPO.", "MOTEURS DISPO."]
	draw_section_header(sidebar_x + sidebar_pad + 4, arsenal_header_y, sidebar_w - sidebar_pad * 2 - 8, header_names[_current_tab])

	# Stock count
	if _actions:
		var total =_actions.get_current_stock_count(_current_tab)
		var inv_str ="%d en stock" % total
		draw_string(font, Vector2(sidebar_x + sidebar_w - sidebar_pad - 4, arsenal_header_y + 11),
			inv_str, HORIZONTAL_ALIGNMENT_RIGHT, sidebar_w * 0.4, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Comparison panel
	var compare_y =s.y - EC.COMPARE_H - 76
	var compare_rect =Rect2(sidebar_x + sidebar_pad - 2, compare_y,
		sidebar_w - sidebar_pad * 2 + 4, EC.COMPARE_H)
	draw_panel_bg(compare_rect)
	var cmp_header_y =draw_section_header(sidebar_x + sidebar_pad + 4, compare_y + 5,
		sidebar_w - sidebar_pad * 2 - 8, "COMPARAISON")
	_sidebar.draw_comparison(self, font, sidebar_x + sidebar_pad, cmp_header_y, sidebar_w - sidebar_pad * 2,
		_selected_weapon, _selected_shield, _selected_engine, _selected_module)

	# Button separator
	var btn_sep_y =s.y - 72
	draw_line(Vector2(sidebar_x + sidebar_pad, btn_sep_y),
		Vector2(sidebar_x + sidebar_w - sidebar_pad, btn_sep_y), UITheme.BORDER, 1.0)

	# Corner decorations
	var m =28.0
	var cl =28.0
	var cc =UITheme.CORNER
	draw_line(Vector2(m, m), Vector2(m + cl, m), cc, 1.5)
	draw_line(Vector2(m, m), Vector2(m, m + cl), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), cc, 1.5)

	# Scanline
	var scan_y =fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


# =============================================================================
# SIGNAL HANDLERS — Sub-views → Orchestrator
# =============================================================================
func _on_tab_changed(index: int) -> void:
	_current_tab = index
	_selected_hardpoint = -1
	_selected_weapon = &""
	_selected_shield = &""
	_selected_engine = &""
	_selected_module = &""
	_selected_module_slot = -1

	_strip.set_tab(_current_tab)
	_sidebar.set_tab(_current_tab)

	_auto_select_slot()
	_strip.set_selected_hardpoint(_selected_hardpoint)
	_strip.set_selected_module_slot(_selected_module_slot)
	_sidebar.set_selected_hardpoint(_selected_hardpoint)
	_sidebar.set_selected_module_slot(_selected_module_slot)

	_viewer.update_marker_visuals(_selected_hardpoint)
	_update_button_states()
	queue_redraw()


func _on_viewer_hardpoint_selected(idx: int) -> void:
	_selected_hardpoint = idx
	_selected_weapon = &""
	_strip.set_selected_hardpoint(idx)
	_sidebar.set_selected_hardpoint(idx)
	_viewer.update_marker_visuals(idx)
	_update_button_states()
	queue_redraw()


func _on_strip_hardpoint_clicked(idx: int) -> void:
	_selected_hardpoint = idx
	_selected_weapon = &""
	_strip.set_selected_hardpoint(idx)
	_sidebar.set_selected_hardpoint(idx)
	_viewer.update_marker_visuals(idx)
	_update_button_states()
	queue_redraw()


func _on_strip_module_slot_clicked(idx: int) -> void:
	_selected_module_slot = idx
	_selected_module = &""
	_strip.set_selected_module_slot(idx)
	_sidebar.set_selected_module_slot(idx)
	_update_button_states()
	queue_redraw()


func _on_strip_weapon_remove(idx: int) -> void:
	_selected_hardpoint = idx
	if _actions:
		_actions.remove_weapon(idx)
	_post_loadout_change()


func _on_strip_module_remove(idx: int) -> void:
	_selected_module_slot = idx
	if _actions:
		_actions.remove_module(idx)
	_post_loadout_change()


func _on_shield_remove() -> void:
	if _actions:
		_actions.remove_shield()
	_post_loadout_change()


func _on_engine_remove() -> void:
	if _actions:
		_actions.remove_engine()
	_post_loadout_change()


func _on_arsenal_selected(item_name: StringName) -> void:
	match _current_tab:
		0: _selected_weapon = item_name
		1: _selected_module = item_name
		2: _selected_shield = item_name
		3: _selected_engine = item_name
	_update_button_states()
	queue_redraw()


func _on_arsenal_double_clicked(item_name: StringName) -> void:
	match _current_tab:
		0: _selected_weapon = item_name
		1: _selected_module = item_name
		2: _selected_shield = item_name
		3: _selected_engine = item_name
	_on_equip_pressed()


func _on_equip_pressed() -> void:
	if _actions == null:
		return
	match _current_tab:
		0: _actions.equip_weapon(_selected_hardpoint, _selected_weapon)
		1: _actions.equip_module(_selected_module_slot, _selected_module)
		2: _actions.equip_shield(_selected_shield)
		3: _actions.equip_engine(_selected_engine)
	# Reset selection after equip
	match _current_tab:
		0: _selected_weapon = &""
		1: _selected_module = &""
		2: _selected_shield = &""
		3: _selected_engine = &""
	_post_loadout_change()


func _on_remove_pressed() -> void:
	if _actions == null:
		return
	match _current_tab:
		0: _actions.remove_weapon(_selected_hardpoint)
		1: _actions.remove_module(_selected_module_slot)
		2: _actions.remove_shield()
		3: _actions.remove_engine()
	match _current_tab:
		0: _selected_weapon = &""
		1: _selected_module = &""
		2: _selected_shield = &""
		3: _selected_engine = &""
	_post_loadout_change()


func _on_back_pressed() -> void:
	close()


func _on_adapter_loadout_changed() -> void:
	_post_loadout_change()


func _on_fleet_ship_selected(idx: int) -> void:
	if idx == _selected_fleet_index:
		return
	_selected_fleet_index = idx

	if _adapter and _adapter.loadout_changed.is_connected(_on_adapter_loadout_changed):
		_adapter.loadout_changed.disconnect(_on_adapter_loadout_changed)

	_create_adapter()
	screen_title = "FLOTTE — EQUIPEMENT"

	_reload_ship_viewer_for_fleet_ship()

	_selected_hardpoint = -1
	_selected_weapon = &""
	_selected_shield = &""
	_selected_engine = &""
	_selected_module = &""
	_selected_module_slot = -1
	_current_tab = 0
	if _tab_bar:
		_tab_bar.current_tab = 0

	_strip.setup(_adapter, player_fleet, _selected_fleet_index, _is_station_mode())
	_strip.set_tab(0)
	_sidebar.setup(_adapter, player_inventory)
	_sidebar.set_tab(0)

	_auto_select_slot()
	_strip.set_selected_hardpoint(_selected_hardpoint)
	_sidebar.set_selected_hardpoint(_selected_hardpoint)
	_sidebar.set_selected_module_slot(_selected_module_slot)

	_update_button_states()
	queue_redraw()


# =============================================================================
# HELPERS
# =============================================================================
func _post_loadout_change() -> void:
	_viewer.refresh_weapons()
	_viewer.update_marker_visuals(_selected_hardpoint)
	_sidebar.refresh()
	_strip.refresh()
	_update_button_states()
	queue_redraw()


func _update_button_states() -> void:
	if _actions == null:
		_equip_btn.enabled = false
		_remove_btn.enabled = false
		return
	_equip_btn.enabled = _actions.get_equip_enabled(_current_tab, _selected_weapon, _selected_shield,
		_selected_engine, _selected_module, _selected_hardpoint, _selected_module_slot)
	_remove_btn.enabled = _actions.get_remove_enabled(_current_tab, _selected_hardpoint, _selected_module_slot)


func _auto_select_slot() -> void:
	if _adapter == null:
		return
	match _current_tab:
		0:
			if _selected_hardpoint < 0:
				for i in _adapter.get_hardpoint_count():
					if _adapter.get_mounted_weapon(i) == null:
						_selected_hardpoint = i
						return
				if _adapter.get_hardpoint_count() > 0:
					_selected_hardpoint = 0
		1:
			if _selected_module_slot < 0:
				for i in _adapter.get_module_slot_count():
					if _adapter.get_equipped_module(i) == null:
						_selected_module_slot = i
						return
				if _adapter.get_module_slot_count() > 0:
					_selected_module_slot = 0


func _is_live_mode() -> bool:
	return player_fleet != null and _selected_fleet_index == player_fleet.active_index


func _is_station_mode() -> bool:
	return station_equip_adapter != null


func _create_adapter() -> void:
	if _is_station_mode() and station_equip_adapter:
		_adapter = station_equip_adapter
		_adapter.loadout_changed.connect(_on_adapter_loadout_changed)
		_actions = EquipmentActions.create(_adapter, player_inventory)
		return

	if player_fleet == null:
		return
	var fs = player_fleet.ships[_selected_fleet_index] if _selected_fleet_index < player_fleet.ships.size() else null
	if fs == null:
		return
	if _is_live_mode() and weapon_manager and equipment_manager:
		_adapter = FleetShipEquipAdapter.create_live(weapon_manager, equipment_manager, fs, player_inventory)
	else:
		_adapter = FleetShipEquipAdapter.create_data(fs, player_inventory)
	_adapter.loadout_changed.connect(_on_adapter_loadout_changed)
	_actions = EquipmentActions.create(_adapter, player_inventory)


func _reload_ship_viewer_for_fleet_ship() -> void:
	if player_fleet == null or _selected_fleet_index >= player_fleet.ships.size():
		return
	var fs = player_fleet.ships[_selected_fleet_index]
	var sd =ShipRegistry.get_ship_data(fs.ship_id)
	if sd == null:
		return

	_ship_model_path = sd.model_path
	_ship_model_scale = ShipFactory.get_scene_model_scale(fs.ship_id)
	_ship_model_rotation = ShipFactory.get_model_rotation(fs.ship_id)
	_ship_center_offset = ShipFactory.get_center_offset(fs.ship_id)
	_ship_root_basis = ShipFactory.get_root_basis(fs.ship_id)

	_viewer.setup(_adapter, _ship_model_path, _ship_model_scale, _ship_center_offset,
		_ship_model_rotation, _ship_root_basis, weapon_manager,
		_is_live_mode(), _is_station_mode())
	_layout_controls()
