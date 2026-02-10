class_name StellarMap
extends Control

# =============================================================================
# Stellar Map - Main controller
# Full-screen overlay map. Toggle with M key.
# Manages camera, children layers, input consumption.
# Fleet: sidebar select + right-click-to-move + hold for context menu.
# =============================================================================

var _camera: MapCamera = null
var _renderer: MapRenderer = null
var _entity_layer: MapEntities = null
var _info_panel: MapInfoPanel = null
var _fleet_panel: MapFleetPanel = null
var _search: MapSearch = null

var _is_open: bool = false
var _player_id: String = ""
var _was_mouse_captured: bool = false

## When true, this map is managed by UnifiedMapScreen.
var managed_externally: bool = false
signal view_switch_requested
signal navigate_to_requested(entity_id: String)
signal fleet_order_requested(fleet_index: int, order_id: StringName, params: Dictionary)
signal fleet_recall_requested(fleet_index: int)

## Preview mode: shows static entities from StarSystemData instead of live EntityRegistry
var _preview_entities: Dictionary = {}
var _preview_system_name: String = ""
var _saved_system_name: String = ""

# Pan state
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO

# Double-click detection
var _last_click_time: float = 0.0
var _last_click_id: String = ""

# Fleet move mode
var _fleet_selected_index: int = -1

# Right-click hold detection for context menu
var _right_hold_start: float = 0.0
var _right_hold_pos: Vector2 = Vector2.ZERO
var _right_hold_triggered: bool = false
const RIGHT_HOLD_DURATION: float = 0.4
const RIGHT_HOLD_MAX_MOVE: float = 20.0

# Context menu
var _context_menu: FleetContextMenu = null

# Waypoint flash
var _waypoint_pos: Vector2 = Vector2.ZERO
var _waypoint_timer: float = 0.0
const WAYPOINT_DURATION: float = 2.0

# Filters: EntityType (int) -> bool (true = hidden)
# Special key -1 = orbit lines
var _filters: Dictionary = {}

# Dirty flag for redraw optimization
var _dirty: bool = true


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_children()

	# Set full-screen anchors
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	# Connect EntityRegistry signals for dirty tracking
	EntityRegistry.entity_registered.connect(func(_id): _dirty = true)
	EntityRegistry.entity_unregistered.connect(func(_id): _dirty = true)


func _build_children() -> void:
	_camera = MapCamera.new()

	# Renderer (background, grid, orbits, toolbar)
	_renderer = MapRenderer.new()
	_renderer.name = "MapRenderer"
	_setup_full_rect(_renderer)
	_renderer.camera = _camera
	_renderer.filters = _filters
	_renderer.filter_toggled.connect(_on_toolbar_filter_toggled)
	_renderer.follow_toggled.connect(_on_toolbar_follow_toggled)
	add_child(_renderer)

	# Entity layer (icons, labels, selection)
	_entity_layer = MapEntities.new()
	_entity_layer.name = "MapEntityLayer"
	_setup_full_rect(_entity_layer)
	_entity_layer.camera = _camera
	_entity_layer.filters = _filters
	add_child(_entity_layer)

	# Info panel
	_info_panel = MapInfoPanel.new()
	_info_panel.name = "MapInfoPanel"
	_setup_full_rect(_info_panel)
	_info_panel.camera = _camera
	add_child(_info_panel)

	# Fleet panel (left side)
	_fleet_panel = MapFleetPanel.new()
	_fleet_panel.name = "MapFleetPanel"
	_setup_full_rect(_fleet_panel)
	_fleet_panel.ship_selected.connect(_on_fleet_ship_selected)
	_fleet_panel.ship_move_selected.connect(_on_fleet_move_selected)
	_fleet_panel.ship_recall_requested.connect(_on_fleet_recall_requested)
	add_child(_fleet_panel)

	# Search bar
	_search = MapSearch.new()
	_search.name = "MapSearch"
	_setup_full_rect(_search)
	_search.entity_selected.connect(_on_search_entity_selected)
	add_child(_search)


func _setup_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0


func set_player_id(id: String) -> void:
	_player_id = id
	_camera.follow_entity_id = id
	_entity_layer._player_id = id
	_info_panel._player_id = id


func set_system_name(sname: String) -> void:
	_renderer._system_name = sname


func set_preview(entities: Dictionary, system_name: String) -> void:
	_saved_system_name = _renderer._system_name
	_preview_entities = entities
	_preview_system_name = system_name
	_entity_layer.preview_entities = _preview_entities
	_renderer.preview_entities = _preview_entities
	_renderer._belt_dot_cache.clear()
	_info_panel.preview_entities = _preview_entities
	_renderer._system_name = "APERCU : " + system_name
	_entity_layer.selected_id = ""
	_info_panel.set_selected("")


func clear_preview() -> void:
	_preview_entities = {}
	_preview_system_name = ""
	_entity_layer.preview_entities = {}
	_renderer.preview_entities = {}
	_renderer._belt_dot_cache.clear()
	_info_panel.preview_entities = {}
	if not _saved_system_name.is_empty():
		_renderer._system_name = _saved_system_name
		_saved_system_name = ""
	_entity_layer.selected_id = ""
	_info_panel.set_selected("")


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_dirty = true

	# Release mouse for map interaction
	_was_mouse_captured = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Center on star (origin) for system overview
	_camera.screen_size = size

	# Compute system radius for pan limits + zoom calculation
	_update_system_radius()

	# Compute zoom to show the full system with some padding
	var fit_zoom: float = (size.x * 0.4) / _camera.system_radius
	fit_zoom = clampf(fit_zoom, MapCamera.ZOOM_MIN, MapCamera.PRESET_REGIONAL)

	# Start zoomed out showing full system, centered on star
	_camera.center_x = 0.0
	_camera.center_z = 0.0
	_camera.follow_enabled = false
	_camera.zoom = fit_zoom
	_camera.target_zoom = fit_zoom


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_is_panning = false
	_fleet_selected_index = -1
	_fleet_panel.clear_selection()
	_close_context_menu()
	_search.close()

	# Restore mouse capture (skip when managed — UIScreenManager handles it)
	if _was_mouse_captured and not managed_externally:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_system_radius() -> void:
	var max_r: float = Constants.SYSTEM_RADIUS
	var entities: Dictionary = _preview_entities if not _preview_entities.is_empty() else EntityRegistry.get_all()
	for ent in entities.values():
		var r: float = ent["orbital_radius"]
		if r > max_r:
			max_r = r
		var px: float = absf(ent["pos_x"])
		var pz: float = absf(ent["pos_z"])
		var pos_r: float = sqrt(px * px + pz * pz)
		if pos_r > max_r:
			max_r = pos_r
	_camera.system_radius = max_r


func _process(delta: float) -> void:
	if not _is_open:
		return

	_camera.screen_size = size
	var zoom_before: float = _camera.zoom
	_camera.update(delta)

	if _camera.zoom != zoom_before:
		_dirty = true

	# Right-click hold detection (context menu)
	if _right_hold_start > 0.0 and not _right_hold_triggered:
		var now: float = Time.get_ticks_msec() / 1000.0
		var elapsed: float = now - _right_hold_start
		if elapsed >= RIGHT_HOLD_DURATION:
			_right_hold_triggered = true
			_open_fleet_context_menu(_right_hold_pos)

	# Waypoint flash countdown
	if _waypoint_timer > 0.0:
		_waypoint_timer -= delta

	# Sync follow state to renderer toolbar
	_renderer.follow_enabled = _camera.follow_enabled

	# Always redraw while open so entity positions update in real-time
	_renderer.queue_redraw()
	_entity_layer.queue_redraw()
	_fleet_panel.queue_redraw()
	# Redraw self for waypoint flash + fleet hint overlay
	if _waypoint_timer > 0.0 or _fleet_selected_index >= 0:
		queue_redraw()
	if _dirty:
		_info_panel.queue_redraw()
		_dirty = false


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	# If context menu is open, let it handle input
	if _context_menu and _context_menu.visible:
		return

	# If search bar is open, let it handle input first
	if _search.visible:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return

	# Consume ALL input so the ship doesn't move
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_ESCAPE:
			# If fleet ship is selected, deselect first
			if _fleet_selected_index >= 0:
				_fleet_selected_index = -1
				_fleet_panel.clear_selection()
				get_viewport().set_input_as_handled()
				return
			if managed_externally:
				return
			close()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_M:
			if managed_externally:
				return
			close()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_TAB and managed_externally:
			view_switch_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_G and managed_externally:
			view_switch_requested.emit()
			get_viewport().set_input_as_handled()
			return
		# Zoom presets 1-5
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			var idx: int = event.physical_keycode - KEY_1 + 1
			_camera.set_preset(idx)
			_dirty = true
			get_viewport().set_input_as_handled()
			return
		# F = toggle follow
		if event.physical_keycode == KEY_F:
			_camera.follow_enabled = not _camera.follow_enabled
			_dirty = true
			get_viewport().set_input_as_handled()
			return

		# --- Filter toggles ---
		if event.physical_keycode == KEY_O:
			_toggle_filter(-1)
			_filters[EntityRegistrySystem.EntityType.ASTEROID_BELT] = _filters.get(-1, false)
			_sync_filters()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_N:
			_toggle_filter(EntityRegistrySystem.EntityType.SHIP_NPC)
			_sync_filters()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_P:
			_toggle_filter(EntityRegistrySystem.EntityType.PLANET)
			_sync_filters()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_T:
			_toggle_filter(EntityRegistrySystem.EntityType.STATION)
			_sync_filters()
			get_viewport().set_input_as_handled()
			return

		# / = search
		if event.physical_keycode == KEY_SLASH:
			_search.open()
			get_viewport().set_input_as_handled()
			return

		# Consume all other key presses
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.pressed:
		get_viewport().set_input_as_handled()
		return

	# Mouse wheel = zoom (route through panels first)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _fleet_panel.handle_scroll(event.position, 1):
				get_viewport().set_input_as_handled()
				return
			_camera.zoom_at(event.position, MapCamera.ZOOM_STEP)
			_dirty = true
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _fleet_panel.handle_scroll(event.position, -1):
				get_viewport().set_input_as_handled()
				return
			_camera.zoom_at(event.position, 1.0 / MapCamera.ZOOM_STEP)
			_dirty = true
			get_viewport().set_input_as_handled()
			return

		# Middle mouse = pan
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			if event.pressed:
				_pan_start = event.position
			get_viewport().set_input_as_handled()
			return

		# Left click = route through panels, toolbar, then select entity
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Fleet panel gets first priority (left side)
				if _fleet_panel.handle_click(event.position):
					get_viewport().set_input_as_handled()
					return
				# Toolbar buttons
				if _renderer.handle_toolbar_click(event.position):
					get_viewport().set_input_as_handled()
					return

				# Click on empty space with fleet selected -> deselect
				var hit_id: String = _entity_layer.get_entity_at(event.position)
				if hit_id == "" and _fleet_selected_index >= 0:
					_fleet_selected_index = -1
					_fleet_panel.clear_selection()
					get_viewport().set_input_as_handled()
					return

				var now: float = Time.get_ticks_msec() / 1000.0

				# Double-click on entity -> navigate
				if hit_id != "" and hit_id == _last_click_id and (now - _last_click_time) < 0.4:
					navigate_to_requested.emit(hit_id)
					_last_click_id = ""
				else:
					_select_entity(hit_id)
					_last_click_id = hit_id
					_last_click_time = now

			get_viewport().set_input_as_handled()
			return

		# Right click
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Fleet panel right-click (recall)
				if _fleet_panel.handle_right_click(event.position):
					get_viewport().set_input_as_handled()
					return

				# If fleet ship is selected, start right-hold detection
				if _fleet_selected_index >= 0:
					_right_hold_start = Time.get_ticks_msec() / 1000.0
					_right_hold_pos = event.position
					_right_hold_triggered = false
					get_viewport().set_input_as_handled()
					return

				# No fleet selection: recenter on player
				_camera.recenter_on_player()
				_dirty = true
			else:
				# Right click released
				if _fleet_selected_index >= 0 and _right_hold_start > 0.0 and not _right_hold_triggered:
					# Quick right-click: default move_to
					var universe_x: float = _camera.screen_to_universe_x(event.position.x)
					var universe_z: float = _camera.screen_to_universe_z(event.position.y)
					var params := {"target_x": universe_x, "target_z": universe_z}
					fleet_order_requested.emit(_fleet_selected_index, &"move_to", params)
					_show_waypoint(event.position)
					_fleet_selected_index = -1
					_fleet_panel.clear_selection()
				_right_hold_start = 0.0

			get_viewport().set_input_as_handled()
			return

	# Mouse motion
	if event is InputEventMouseMotion:
		# Cancel right-hold if mouse moved too far
		if _right_hold_start > 0.0 and not _right_hold_triggered:
			if event.position.distance_to(_right_hold_pos) > RIGHT_HOLD_MAX_MOVE:
				_right_hold_start = 0.0
		if _is_panning:
			_camera.pan(event.relative)
			_dirty = true
		else:
			_renderer.update_toolbar_hover(event.position)
			if _entity_layer.update_hover(event.position):
				_dirty = true
		get_viewport().set_input_as_handled()
		return


func _select_entity(id: String) -> void:
	_entity_layer.selected_id = id
	_info_panel.set_selected(id)
	_dirty = true


func _center_on_entity(id: String) -> void:
	var ent: Dictionary = EntityRegistry.get_entity(id)
	if ent.is_empty():
		return
	_camera.center_x = ent["pos_x"]
	_camera.center_z = ent["pos_z"]
	_camera.follow_enabled = false
	_camera.target_zoom = clampf(_camera.zoom * 3.0, MapCamera.ZOOM_MIN, MapCamera.ZOOM_MAX)
	_select_entity(id)


func _toggle_filter(key: int) -> void:
	_filters[key] = not _filters.get(key, false)
	_dirty = true


func _sync_filters() -> void:
	_entity_layer.filters = _filters
	_renderer.filters = _filters
	_dirty = true


func set_fleet(fleet: PlayerFleet, galaxy: GalaxyData) -> void:
	_fleet_panel.set_fleet(fleet)
	_fleet_panel.set_galaxy(galaxy)


func _on_fleet_ship_selected(fleet_index: int, _system_id: int) -> void:
	# Center map on the entity if in current system
	if _fleet_panel._fleet == null:
		return
	var fs := _fleet_panel._fleet.ships[fleet_index]
	# If ship is docked at a station, try to center on that station
	if fs.docked_station_id != "":
		var ent := EntityRegistry.get_entity(fs.docked_station_id)
		if not ent.is_empty():
			_center_on_entity(fs.docked_station_id)
			return
	# For deployed ships, try to find their NPC in EntityRegistry
	if fs.deployed_npc_id != &"":
		var ent := EntityRegistry.get_entity(String(fs.deployed_npc_id))
		if not ent.is_empty():
			_center_on_entity(String(fs.deployed_npc_id))
			return


func _on_fleet_move_selected(fleet_index: int) -> void:
	_fleet_selected_index = fleet_index


func _on_fleet_recall_requested(fleet_index: int) -> void:
	fleet_recall_requested.emit(fleet_index)


func _on_search_entity_selected(id: String) -> void:
	_center_on_entity(id)


func _on_toolbar_filter_toggled(key: int) -> void:
	_toggle_filter(key)
	if key == -1:
		_filters[EntityRegistrySystem.EntityType.ASTEROID_BELT] = _filters.get(-1, false)
	_sync_filters()


func _on_toolbar_follow_toggled() -> void:
	_camera.follow_enabled = not _camera.follow_enabled
	_dirty = true


# =============================================================================
# FLEET CONTEXT MENU
# =============================================================================
func _open_fleet_context_menu(screen_pos: Vector2) -> void:
	if _fleet_selected_index < 0 or _fleet_panel._fleet == null:
		return
	if _fleet_selected_index >= _fleet_panel._fleet.ships.size():
		return

	var fs := _fleet_panel._fleet.ships[_fleet_selected_index]
	var universe_x: float = _camera.screen_to_universe_x(screen_pos.x)
	var universe_z: float = _camera.screen_to_universe_z(screen_pos.y)

	# Build context
	var context := {
		"fleet_index": _fleet_selected_index,
		"fleet_ship": fs,
		"is_deployed": fs.deployment_state == FleetShip.DeploymentState.DEPLOYED,
		"universe_x": universe_x,
		"universe_z": universe_z,
		"target_entity_id": _entity_layer.get_entity_at(screen_pos),
	}

	var orders := FleetOrderRegistry.get_available_orders(context)
	if orders.is_empty():
		return

	_close_context_menu()
	_context_menu = FleetContextMenu.new()
	_context_menu.name = "FleetContextMenu"
	add_child(_context_menu)
	_context_menu.order_selected.connect(_on_context_menu_order)
	_context_menu.cancelled.connect(_close_context_menu)
	_context_menu.show_menu(screen_pos, orders, context)


func _close_context_menu() -> void:
	if _context_menu:
		_context_menu.queue_free()
		_context_menu = null


func _on_context_menu_order(order_id: StringName, params: Dictionary) -> void:
	if _fleet_selected_index >= 0:
		fleet_order_requested.emit(_fleet_selected_index, order_id, params)
		if order_id != &"return_to_station":
			_show_waypoint(_right_hold_pos)
	_fleet_selected_index = -1
	_fleet_panel.clear_selection()
	_close_context_menu()


# =============================================================================
# WAYPOINT FLASH
# =============================================================================
func _show_waypoint(screen_pos: Vector2) -> void:
	_waypoint_pos = screen_pos
	_waypoint_timer = WAYPOINT_DURATION
	_dirty = true


func _draw() -> void:
	# Waypoint flash
	if _waypoint_timer > 0.0:
		var alpha: float = _waypoint_timer / WAYPOINT_DURATION
		var pulse: float = sin(Time.get_ticks_msec() / 200.0) * 0.3 + 0.7
		var radius: float = 8.0 + (1.0 - alpha) * 20.0
		var col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, alpha * pulse * 0.6)
		draw_arc(_waypoint_pos, radius, 0, TAU, 24, col, 2.0, true)
		# Inner dot
		draw_circle(_waypoint_pos, 3.0, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, alpha * 0.8))

	# Hint text when fleet ship is selected
	if _fleet_selected_index >= 0:
		var font: Font = UITheme.get_font()
		var hint := "Clic droit = Deplacer | Maintenir = Ordres | Echap = Annuler"
		var hint_y: float = size.y - 60.0
		var hint_x: float = size.x * 0.5
		var tw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
		draw_rect(Rect2(hint_x - tw * 0.5 - 8, hint_y - 14, tw + 16, 20), Color(0.0, 0.02, 0.05, 0.8))
		var pulse: float = sin(Time.get_ticks_msec() / 400.0) * 0.15 + 0.85
		draw_string(font, Vector2(hint_x - tw * 0.5, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, pulse))
