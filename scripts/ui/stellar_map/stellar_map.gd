class_name StellarMap
extends Control

# =============================================================================
# Stellar Map - Main controller
# Full-screen overlay map. Toggle with M key.
# Manages camera, children layers, input consumption.
# =============================================================================

var _camera: MapCamera = null
var _renderer: MapRenderer = null
var _entity_layer: MapEntities = null
var _info_panel: MapInfoPanel = null
var _fleet_panel: MapFleetPanel = null
var _station_detail: MapStationDetail = null
var _search: MapSearch = null

var _is_open: bool = false
var _player_id: String = ""
var _was_mouse_captured: bool = false

## When true, this map is managed by UnifiedMapScreen.
## Escape/M/G are NOT consumed — they propagate to UIScreenManager/GameManager.
## Tab emits view_switch_requested instead of being consumed silently.
var managed_externally: bool = false
signal view_switch_requested
signal navigate_to_requested(entity_id: String)
signal station_long_pressed(station_id: String)
signal fleet_deploy_requested(fleet_index: int, command: StringName, params: Dictionary)
signal fleet_retrieve_requested(fleet_index: int)
signal fleet_command_change_requested(fleet_index: int, command: StringName, params: Dictionary)

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

# Hold-click detection for fleet management
var _hold_start_time: float = 0.0
var _hold_entity_id: String = ""
var _hold_start_pos: Vector2 = Vector2.ZERO
var _hold_triggered: bool = false
var _hold_progress: float = 0.0  # 0..1, for visual feedback
const HOLD_DURATION: float = 0.6
const HOLD_MAX_MOVE: float = 30.0

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
	add_child(_fleet_panel)

	# Station detail panel (right side, replaces info panel)
	_station_detail = MapStationDetail.new()
	_station_detail.name = "MapStationDetail"
	_setup_full_rect(_station_detail)
	_station_detail.visible = false
	_station_detail.deploy_requested.connect(func(fi, cmd, params): fleet_deploy_requested.emit(fi, cmd, params))
	_station_detail.retrieve_requested.connect(func(fi): fleet_retrieve_requested.emit(fi))
	_station_detail.command_change_requested.connect(func(fi, cmd, params): fleet_command_change_requested.emit(fi, cmd, params))
	_station_detail.closed.connect(_on_station_detail_closed)
	add_child(_station_detail)

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
	_renderer._system_name = "APERÇU : " + system_name
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
	# zoom = pixels / meters → to fit system_radius in half the screen width
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
	_search.close()
	if _station_detail.is_active():
		_station_detail.close()

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
		# Also check absolute positions (jump gates)
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

	# Keep dirty while zoom is animating so all layers stay in sync
	if _camera.zoom != zoom_before:
		_dirty = true

	# Hold-click detection for fleet management (station long press)
	if _hold_entity_id != "" and not _hold_triggered:
		var now: float = Time.get_ticks_msec() / 1000.0
		var elapsed: float = now - _hold_start_time
		_hold_progress = clampf(elapsed / HOLD_DURATION, 0.0, 1.0)
		if elapsed >= HOLD_DURATION:
			# Check if held entity is a station
			var ent := EntityRegistry.get_entity(_hold_entity_id)
			if not ent.is_empty() and ent.get("type") == EntityRegistrySystem.EntityType.STATION:
				_hold_triggered = true
				station_long_pressed.emit(_hold_entity_id)
			_hold_entity_id = ""
			_hold_progress = 0.0
	else:
		_hold_progress = 0.0

	# Pass hold state to entity layer for visual feedback
	_entity_layer.hold_entity_id = _hold_entity_id
	_entity_layer.hold_progress = _hold_progress

	# Sync follow state to renderer toolbar
	_renderer.follow_enabled = _camera.follow_enabled

	# Always redraw while open so entity positions update in real-time
	_renderer.queue_redraw()
	_entity_layer.queue_redraw()
	_fleet_panel.queue_redraw()
	if _station_detail.is_active():
		_station_detail.queue_redraw()
	if _dirty:
		_info_panel.queue_redraw()
		_dirty = false


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	# If search bar is open, let it handle input first
	if _search.visible:
		# Search handles its own input; we just consume everything else
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return

	# Consume ALL input so the ship doesn't move
	if event is InputEventKey and event.pressed:
		# Close on Escape or M (unless managed externally)
		if event.physical_keycode == KEY_ESCAPE:
			# If station detail is open, close it first
			if _station_detail.is_active():
				_station_detail.close()
				get_viewport().set_input_as_handled()
				return
			if managed_externally:
				# Don't consume — let UIScreenManager handle close via close_top()
				return
			close()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_M:
			if managed_externally:
				# GameManager already consumed this (autoload fires first)
				return
			close()
			get_viewport().set_input_as_handled()
			return
		# Tab switches to galaxy view when managed
		if event.physical_keycode == KEY_TAB and managed_externally:
			view_switch_requested.emit()
			get_viewport().set_input_as_handled()
			return
		# G switches to galaxy view when managed
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
			_toggle_filter(-1)  # orbits (special key)
			# Also toggle asteroid belts with orbits
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
			if _station_detail.handle_scroll(event.position, 1):
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
			if _station_detail.handle_scroll(event.position, -1):
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
				# Station detail gets second priority (right side)
				if _station_detail.is_active() and _station_detail.handle_click(event.position):
					get_viewport().set_input_as_handled()
					return
				# Toolbar buttons
				if _renderer.handle_toolbar_click(event.position):
					get_viewport().set_input_as_handled()
					return

				var hit_id: String = _entity_layer.get_entity_at(event.position)
				var now: float = Time.get_ticks_msec() / 1000.0

				# Start hold tracking
				_hold_start_time = now
				_hold_entity_id = hit_id
				_hold_start_pos = event.position
				_hold_triggered = false

				# Second click on same station -> open station detail
				if hit_id != "" and hit_id == _last_click_id and (now - _last_click_time) < 0.4:
					var ent := EntityRegistry.get_entity(hit_id)
					if not ent.is_empty() and ent.get("type") == EntityRegistrySystem.EntityType.STATION:
						_open_station_detail(hit_id)
						_last_click_id = ""
					else:
						navigate_to_requested.emit(hit_id)
						_last_click_id = ""
				else:
					# Close station detail if clicking elsewhere
					if _station_detail.is_active():
						_station_detail.close()
					_select_entity(hit_id)
					_last_click_id = hit_id
					_last_click_time = now
			else:
				# Release: clear hold tracking
				_hold_entity_id = ""

			get_viewport().set_input_as_handled()
			return

		# Right click = recenter on player
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_camera.recenter_on_player()
			_dirty = true
			get_viewport().set_input_as_handled()
			return

	# Mouse motion
	if event is InputEventMouseMotion:
		# Cancel hold if mouse moved too far
		if _hold_entity_id != "" and event.position.distance_to(_hold_start_pos) > HOLD_MAX_MOVE:
			_hold_entity_id = ""
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
	# Entity layer and renderer share the same dict reference, but update dirty
	_entity_layer.filters = _filters
	_renderer.filters = _filters
	_dirty = true


func set_fleet(fleet: PlayerFleet, galaxy: GalaxyData) -> void:
	_fleet_panel.set_fleet(fleet)
	_fleet_panel.set_galaxy(galaxy)
	_station_detail.set_fleet(fleet)


func _on_fleet_ship_selected(fleet_index: int, system_id: int) -> void:
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


func _on_station_detail_closed() -> void:
	_info_panel.visible = true
	_dirty = true


func _open_station_detail(station_id: String) -> void:
	var ent := EntityRegistry.get_entity(station_id)
	if ent.is_empty():
		return
	var station_name: String = ent.get("name", "STATION")
	var station_type: String = ent.get("extra", {}).get("station_type", "")
	var sys_id: int = GameManager.current_system_id_safe()
	_info_panel.visible = false
	_station_detail.open_station(station_id, station_name, station_type, sys_id)
	_dirty = true


func _on_search_entity_selected(id: String) -> void:
	_center_on_entity(id)


func _on_toolbar_filter_toggled(key: int) -> void:
	_toggle_filter(key)
	# Orbits toggle also controls asteroid belts
	if key == -1:
		_filters[EntityRegistrySystem.EntityType.ASTEROID_BELT] = _filters.get(-1, false)
	_sync_filters()


func _on_toolbar_follow_toggled() -> void:
	_camera.follow_enabled = not _camera.follow_enabled
	_dirty = true
