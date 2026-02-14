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
signal fleet_order_requested(fleet_index: int, order_id: StringName, params: Dictionary)
signal squadron_action_requested(action: StringName, data: Dictionary)
signal construction_marker_placed(marker: Dictionary)

## Preview mode: shows static entities from StarSystemData instead of live EntityRegistry
var _preview_entities: Dictionary = {}
var _preview_system_name: String = ""
var _saved_system_name: String = ""

# Pan state
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _pan_velocity: Vector2 = Vector2.ZERO  # screen px/sec, smooth WASD + inertia

# Pan tuning
const PAN_ACCEL: float = 5.0         # ease-in rate (higher = snappier)
const PAN_FRICTION: float = 4.5      # ease-out rate (higher = stops faster)
const PAN_BASE_SPEED: float = 900.0  # max WASD speed in screen px/sec

# Marquee selection
var _marquee: MarqueeSelect = MarqueeSelect.new()

# Trails
var _trails: MapTrails = MapTrails.new()

# Double-click detection
var _last_click_time: float = 0.0
var _last_click_id: String = ""

# Fleet move mode (multi-select)
var _fleet_selected_indices: Array[int] = []

# Right-click hold detection for context menu
var _right_hold_start: float = 0.0
var _right_hold_pos: Vector2 = Vector2.ZERO
var _right_hold_triggered: bool = false
const RIGHT_HOLD_DURATION: float = 0.8
const RIGHT_HOLD_MAX_MOVE: float = 20.0

# Context menu
var _context_menu: FleetContextMenu = null
var _squadron_mgr: SquadronManager = null

# Construction
var _construction_mgr: ConstructionManager = null

# Inline rename
var _rename_edit: LineEdit = null
var _rename_sq_id: int = -1


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
	_entity_layer.trails = _trails
	_entity_layer.marquee = _marquee
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
	_fleet_panel.selection_changed.connect(_on_fleet_selection_changed)
	_fleet_panel.ship_context_menu_requested.connect(_on_sidebar_context_menu)
	_fleet_panel.squadron_header_clicked.connect(_on_squadron_header_clicked)
	_fleet_panel.squadron_rename_requested.connect(_on_squadron_rename_requested)
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
	_renderer._system_name = system_name


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

	# Ensure fleet panel has the current fleet reference (may have been
	# replaced after backend state load or deserialization)
	var current_fleet: PlayerFleet = GameManager.player_fleet
	if current_fleet and _fleet_panel._fleet != current_fleet:
		_fleet_panel.set_fleet(current_fleet)

	# Release mouse for map interaction
	_was_mouse_captured = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_camera.screen_size = size
	_update_system_radius()

	if not _preview_entities.is_empty():
		# Preview mode: fit-all centered on star
		var fit_zoom: float = (size.x * 0.4) / _camera.system_radius
		fit_zoom = clampf(fit_zoom, MapCamera.ZOOM_MIN, MapCamera.PRESET_REGIONAL)
		_camera.center_x = 0.0
		_camera.center_z = 0.0
		_camera.follow_enabled = false
		_camera.zoom = fit_zoom
		_camera.target_zoom = fit_zoom
	else:
		# Normal mode: center on player, comfortable zoom (~1920km visible)
		var player_ent: Dictionary = EntityRegistry.get_entity(_player_id)
		if not player_ent.is_empty():
			_camera.center_x = player_ent["pos_x"]
			_camera.center_z = player_ent["pos_z"]
		else:
			_camera.center_x = 0.0
			_camera.center_z = 0.0
		_camera.follow_enabled = false
		_camera.zoom = 0.001
		_camera.target_zoom = 0.001

		# Reset filters so all entity types are visible on fresh open
		_filters.clear()
		_sync_filters()

	# Auto-select player's active ship so right-click move works immediately
	if _player_id != "" and _preview_entities.is_empty():
		_select_entity(_player_id)
		_sync_fleet_selection_from_entity(_player_id)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_is_panning = false
	_pan_velocity = Vector2.ZERO
	_fleet_selected_indices.clear()
	_fleet_panel.clear_selection()
	_close_context_menu()
	_cancel_rename()
	_clear_route_line()
	_entity_layer.show_hint = false
	_search.close()

	# Restore mouse capture (skip when managed — UIScreenManager handles it)
	if _was_mouse_captured and not managed_externally:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## GUI input fallback — ensures middle mouse pan works even if _input() doesn't catch it.
func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not _fleet_panel.handle_scroll(event.position, 1):
				_camera.zoom_at(event.position, MapCamera.ZOOM_STEP)
				_dirty = true
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not _fleet_panel.handle_scroll(event.position, -1):
				_camera.zoom_at(event.position, 1.0 / MapCamera.ZOOM_STEP)
				_dirty = true
			accept_event()
			return
	if event is InputEventMouseMotion and _is_panning:
		_camera.pan(event.relative)
		_dirty = true
		accept_event()
		return
	accept_event()


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

	# --- Smooth WASD pan with acceleration / inertia ---
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("strafe_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("strafe_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1.0

	if input_dir != Vector2.ZERO:
		var target_vel := input_dir.normalized() * PAN_BASE_SPEED
		_pan_velocity = _pan_velocity.lerp(target_vel, 1.0 - exp(-PAN_ACCEL * delta))
	else:
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, 1.0 - exp(-PAN_FRICTION * delta))
		if _pan_velocity.length_squared() < 1.0:
			_pan_velocity = Vector2.ZERO

	_camera.screen_size = size
	var zoom_before: float = _camera.zoom
	_camera.update(delta)

	# Apply WASD pan AFTER camera.update() so zoom anchor doesn't overwrite it
	if _pan_velocity != Vector2.ZERO:
		# Break zoom anchor so pan and zoom can coexist
		_camera._anchored = false
		# velocity is in screen px/sec → convert to universe coords via zoom
		_camera.center_x += _pan_velocity.x * delta / maxf(_camera.zoom, 1e-10)
		_camera.center_z += _pan_velocity.y * delta / maxf(_camera.zoom, 1e-10)
		_camera.follow_enabled = false
		_camera.clamp_center()
		_dirty = true

	if _camera.zoom != zoom_before:
		_dirty = true

	# Right-click hold detection (context menu)
	if _right_hold_start > 0.0 and not _right_hold_triggered:
		var now: float = Time.get_ticks_msec() / 1000.0
		var elapsed: float = now - _right_hold_start
		if elapsed >= RIGHT_HOLD_DURATION:
			_right_hold_triggered = true
			_open_fleet_context_menu(_right_hold_pos)

	# Waypoint flash countdown (on entity layer)
	if _entity_layer.waypoint_timer > 0.0:
		_entity_layer.waypoint_timer -= delta

	# Keep hint text visible
	_entity_layer.show_hint = true

	# Update trails
	var trail_entities: Dictionary = _preview_entities if not _preview_entities.is_empty() else EntityRegistry.get_all()
	_trails.update(trail_entities, Time.get_ticks_msec() / 1000.0)

	# Sync follow state to renderer toolbar
	_renderer.follow_enabled = _camera.follow_enabled

	# Always redraw while open so entity positions update in real-time
	_renderer.queue_redraw()
	_entity_layer.queue_redraw()
	_fleet_panel.queue_redraw()
	# Redraw self for marquee only
	if _marquee.active:
		queue_redraw()
	if _dirty:
		_info_panel.queue_redraw()
		_dirty = false


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	# If context menu is open, right-click closes it and continues processing
	if _context_menu and _context_menu.visible:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_close_context_menu()
			# Fall through — process this right-click press normally (start hold timer)
		else:
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
			if not _fleet_selected_indices.is_empty():
				_fleet_selected_indices.clear()
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

		# Left click = route through panels, toolbar, then select entity / marquee
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Fleet panel gets first priority (left side)
				if _fleet_panel.handle_click(event.position, event.ctrl_pressed):
					get_viewport().set_input_as_handled()
					return
				# Toolbar buttons
				if _renderer.handle_toolbar_click(event.position):
					get_viewport().set_input_as_handled()
					return

				var hit_id: String = _entity_layer.get_entity_at(event.position)

				# Click on empty space with fleet selected -> deselect everything
				if hit_id == "" and not _fleet_selected_indices.is_empty():
					_fleet_selected_indices.clear()
					_fleet_panel.clear_selection()
					_select_entity("")
					get_viewport().set_input_as_handled()
					return

				if hit_id != "":
					# Ctrl+click = toggle in multi-select
					if event.ctrl_pressed:
						_toggle_multi_select(hit_id)
					else:
						var now: float = Time.get_ticks_msec() / 1000.0
						if hit_id == _last_click_id and (now - _last_click_time) < 0.4:
							# Double-click = move selected ships to this entity
							var effective_indices := _get_effective_fleet_indices()
							var ent := EntityRegistry.get_entity(hit_id)
							if not effective_indices.is_empty() and not ent.is_empty():
								var ux: float = ent["pos_x"]
								var uz: float = ent["pos_z"]
								var params := {"target_x": ux, "target_z": uz}
								for idx in effective_indices:
									fleet_order_requested.emit(idx, &"move_to", params)
								_show_waypoint(ux, uz)
								_set_route_lines(effective_indices, ux, uz)
							_last_click_id = ""
						else:
							_select_entity(hit_id)
							_sync_fleet_selection_from_entity(hit_id)
							# Follow moving entities (fleet ships, player)
							var hit_ent := EntityRegistry.get_entity(hit_id)
							var hit_type: int = hit_ent.get("type", -1)
							if hit_id == _player_id or hit_type == EntityRegistrySystem.EntityType.SHIP_FLEET:
								_camera.follow_entity_id = hit_id
								_camera.follow_enabled = true
							_last_click_id = hit_id
							_last_click_time = now
				else:
					# Click on empty space: start marquee drag
					_marquee.begin(event.position)
			else:
				# Left button released
				if _marquee.active:
					if _marquee.is_drag():
						var rect := _marquee.get_rect()
						var ids := _entity_layer.get_entities_in_rect(rect)
						_entity_layer.selected_ids.assign(ids)
						if ids.size() > 0:
							_entity_layer.selected_id = ids[0]
							_info_panel.set_selected(ids[0])
							_dirty = true
							# Extract fleet indices from marquee-selected entities
							var fleet_ids: Array[int] = []
							for eid in ids:
								if eid == _player_id and _fleet_panel._fleet:
									fleet_ids.append(_fleet_panel._fleet.active_index)
								else:
									var ent := EntityRegistry.get_entity(eid)
									if ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_FLEET:
										var extra: Dictionary = ent.get("extra", {})
										if extra.has("fleet_index"):
											fleet_ids.append(extra["fleet_index"])
							if not fleet_ids.is_empty():
								_fleet_selected_indices = fleet_ids
								_fleet_panel.set_selected_fleet_indices(fleet_ids)
								_restore_route_for_fleet_selection()
						else:
							_select_entity("")
					else:
						# Tap on empty = clear selection
						_select_entity("")
						_entity_layer.selected_ids.clear()
					_marquee.end()

			get_viewport().set_input_as_handled()
			return

		# Right click = move ship to destination
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Fleet panel right-click (recall deployed ship)
				if _fleet_panel.handle_right_click(event.position):
					get_viewport().set_input_as_handled()
					return

				# Start right-hold detection (always — defaults to active ship)
				_right_hold_start = Time.get_ticks_msec() / 1000.0
				_right_hold_pos = event.position
				_right_hold_triggered = false
			else:
				# Right click released — quick release = move_to or attack
				var effective_indices := _get_effective_fleet_indices()
				if not effective_indices.is_empty() and _right_hold_start > 0.0 and not _right_hold_triggered:
					# Check construction marker first
					var cm := _entity_layer.get_construction_marker_at(event.position)
					if not cm.is_empty():
						var params := {
							"target_x": cm["pos_x"],
							"target_z": cm["pos_z"],
							"marker_id": cm.get("id", ""),
						}
						for idx in effective_indices:
							fleet_order_requested.emit(idx, &"construction", params)
						_show_waypoint(cm["pos_x"], cm["pos_z"])
						_set_route_lines(effective_indices, cm["pos_x"], cm["pos_z"])
						_right_hold_start = 0.0
						get_viewport().set_input_as_handled()
						return

					var target_id := _entity_layer.get_entity_at(event.position)
					var target_ent := EntityRegistry.get_entity(target_id) if target_id != "" else {}
					if not target_ent.is_empty() and target_ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_NPC:
						# Attack enemy NPC
						var params := {
							"target_entity_id": target_id,
							"target_x": target_ent["pos_x"],
							"target_z": target_ent["pos_z"],
						}
						for idx in effective_indices:
							fleet_order_requested.emit(idx, &"attack", params)
						_show_waypoint(target_ent["pos_x"], target_ent["pos_z"])
						_set_route_lines(effective_indices, target_ent["pos_x"], target_ent["pos_z"])
						_entity_layer.route_target_entity_id = target_id
					elif not target_ent.is_empty() and target_ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_FLEET and _fleet_panel._fleet:
						# Right-click on fleet ship with squadron → join squadron
						var target_extra: Dictionary = target_ent.get("extra", {})
						var target_fi: int = target_extra.get("fleet_index", -1)
						if target_fi >= 0:
							var target_sq := _fleet_panel._fleet.get_ship_squadron(target_fi)
							if target_sq:
								var joined: int = 0
								for idx in effective_indices:
									if _fleet_panel._fleet.get_ship_squadron(idx) == null:
										squadron_action_requested.emit(&"add_member", {"squadron_id": target_sq.squadron_id, "fleet_index": idx})
										joined += 1
								if joined > 0:
									# Toast handled by GameManager; no waypoint needed
									pass
							else:
								# Target has no squadron — treat as move
								var universe_x: float = _camera.screen_to_universe_x(event.position.x)
								var universe_z: float = _camera.screen_to_universe_z(event.position.y)
								var params := {"target_x": universe_x, "target_z": universe_z}
								for idx in effective_indices:
									fleet_order_requested.emit(idx, &"move_to", params)
								_show_waypoint(universe_x, universe_z)
								_set_route_lines(effective_indices, universe_x, universe_z)
						else:
							# No fleet_index on target — move to position
							var universe_x: float = _camera.screen_to_universe_x(event.position.x)
							var universe_z: float = _camera.screen_to_universe_z(event.position.y)
							var params := {"target_x": universe_x, "target_z": universe_z}
							for idx in effective_indices:
								fleet_order_requested.emit(idx, &"move_to", params)
							_show_waypoint(universe_x, universe_z)
							_set_route_lines(effective_indices, universe_x, universe_z)
					elif not target_ent.is_empty() and target_ent.get("type", -1) == EntityRegistrySystem.EntityType.STATION:
						# Right-click on a station → dock at that station
						_select_entity(target_id)
						var params := {"station_id": target_id}
						for idx in effective_indices:
							fleet_order_requested.emit(idx, &"return_to_station", params)
						_show_waypoint(target_ent["pos_x"], target_ent["pos_z"])
						_set_route_lines(effective_indices, target_ent["pos_x"], target_ent["pos_z"])
					elif not target_ent.is_empty():
						# Right-click on a known entity (gate, planet...) → move to it
						_select_entity(target_id)
						var params := {"target_x": target_ent["pos_x"], "target_z": target_ent["pos_z"], "entity_id": target_id}
						for idx in effective_indices:
							fleet_order_requested.emit(idx, &"move_to", params)
						_show_waypoint(target_ent["pos_x"], target_ent["pos_z"])
						_set_route_lines(effective_indices, target_ent["pos_x"], target_ent["pos_z"])
					else:
						# Move to empty space
						var universe_x: float = _camera.screen_to_universe_x(event.position.x)
						var universe_z: float = _camera.screen_to_universe_z(event.position.y)
						var params := {"target_x": universe_x, "target_z": universe_z}
						for idx in effective_indices:
							fleet_order_requested.emit(idx, &"move_to", params)
						_show_waypoint(universe_x, universe_z)
						_set_route_lines(effective_indices, universe_x, universe_z)
				_right_hold_start = 0.0

			get_viewport().set_input_as_handled()
			return

	# Mouse motion
	if event is InputEventMouseMotion:
		# Cancel right-hold if mouse moved too far
		if _right_hold_start > 0.0 and not _right_hold_triggered:
			if event.position.distance_to(_right_hold_pos) > RIGHT_HOLD_MAX_MOVE:
				_right_hold_start = 0.0
		if _marquee.active:
			_marquee.update_pos(event.position)
			queue_redraw()
		elif _is_panning:
			_camera.pan(event.relative)
			_dirty = true
		else:
			_renderer.update_toolbar_hover(event.position)
			if _entity_layer.update_hover(event.position):
				_dirty = true
			_fleet_panel.handle_mouse_move(event.position)
		get_viewport().set_input_as_handled()
		return


## Resolves all effective fleet indices from sidebar, entity selection, or defaults to active ship.
func _get_effective_fleet_indices() -> Array[int]:
	# 1. Fleet panel sidebar multi-selection takes priority
	if not _fleet_selected_indices.is_empty():
		return _fleet_selected_indices
	# 2. Check entity selected on the map
	var sel_id := _entity_layer.selected_id
	if sel_id != "":
		# Player ship → active fleet index
		if sel_id == _player_id and _fleet_panel._fleet:
			return [_fleet_panel._fleet.active_index]
		# Fleet NPC → fleet_index from entity extra
		var ent := EntityRegistry.get_entity(sel_id)
		if ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_FLEET:
			var extra: Dictionary = ent.get("extra", {})
			if extra.has("fleet_index"):
				return [extra["fleet_index"]]
	# 3. Nothing selected — no implicit default (user must select a ship first)
	return []


## Convenience: returns first effective fleet index or -1.
func _get_effective_fleet_index() -> int:
	var indices := _get_effective_fleet_indices()
	return indices[0] if not indices.is_empty() else -1


func _select_entity(id: String) -> void:
	_entity_layer.selected_id = id
	if id != "":
		_entity_layer.selected_ids.assign([id])
	else:
		_entity_layer.selected_ids.clear()
	_info_panel.set_selected(id)
	_dirty = true


## Updates fleet panel highlight when a fleet-related entity is selected on the map.
func _sync_fleet_selection_from_entity(id: String) -> void:
	if _fleet_panel._fleet == null:
		return
	if id == "":
		return  # Don't clear fleet selection on empty — handled separately
	# Player ship → active index
	if id == _player_id:
		var idx: int = _fleet_panel._fleet.active_index
		_fleet_selected_indices = [idx]
		_fleet_panel.set_selected_fleet_indices(_fleet_selected_indices)
		_restore_route_for_fleet_selection()
		return
	# Fleet NPC → fleet_index from entity extra
	var ent := EntityRegistry.get_entity(id)
	if ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_FLEET:
		var extra: Dictionary = ent.get("extra", {})
		if extra.has("fleet_index"):
			var idx: int = extra["fleet_index"]
			_fleet_selected_indices = [idx]
			_fleet_panel.set_selected_fleet_indices(_fleet_selected_indices)
			_restore_route_for_fleet_selection()
			return
	# Non-fleet entity: clear fleet selection
	_fleet_selected_indices.clear()
	_fleet_panel.clear_selection()


func _toggle_multi_select(id: String) -> void:
	var idx: int = _entity_layer.selected_ids.find(id)
	if idx >= 0:
		_entity_layer.selected_ids.remove_at(idx)
	else:
		_entity_layer.selected_ids.append(id)
	var ids := _entity_layer.selected_ids
	_entity_layer.selected_id = ids[-1] if ids.size() > 0 else ""
	_info_panel.set_selected(_entity_layer.selected_id)
	_dirty = true


func _center_on_entity(id: String) -> void:
	var ent: Dictionary = EntityRegistry.get_entity(id)
	if ent.is_empty():
		return
	_camera.center_x = ent["pos_x"]
	_camera.center_z = ent["pos_z"]
	_camera.follow_enabled = false
	_camera.target_zoom = clampf(MapCamera.PRESET_LOCAL, MapCamera.ZOOM_MIN, MapCamera.ZOOM_MAX)
	_select_entity(id)


func _follow_entity(id: String) -> void:
	var ent: Dictionary = EntityRegistry.get_entity(id)
	if ent.is_empty():
		return
	_camera.center_x = ent["pos_x"]
	_camera.center_z = ent["pos_z"]
	_camera.follow_entity_id = id
	_camera.follow_enabled = true
	_camera.target_zoom = clampf(MapCamera.PRESET_LOCAL, MapCamera.ZOOM_MIN, MapCamera.ZOOM_MAX)
	_select_entity(id)


func _toggle_filter(key: int) -> void:
	_filters[key] = not _filters.get(key, false)
	_dirty = true


func _sync_filters() -> void:
	_entity_layer.filters = _filters
	_renderer.filters = _filters
	_dirty = true


func set_construction_manager(mgr: ConstructionManager) -> void:
	_construction_mgr = mgr


func set_squadron_manager(mgr: SquadronManager) -> void:
	_squadron_mgr = mgr
	if _squadron_mgr:
		_squadron_mgr.squadron_changed.connect(_on_squadron_changed)
	_sync_squadron_data()


func _on_squadron_changed() -> void:
	_sync_squadron_data()
	_fleet_panel.queue_redraw()


func _sync_squadron_data() -> void:
	if _fleet_panel._fleet:
		_entity_layer._squadron_fleet = _fleet_panel._fleet
		_entity_layer._squadron_list = _fleet_panel._fleet.squadrons
	else:
		_entity_layer._squadron_list = []
		_entity_layer._squadron_fleet = null


func set_fleet(fleet: PlayerFleet, galaxy: GalaxyData) -> void:
	_fleet_panel.set_fleet(fleet)
	_fleet_panel.set_galaxy(galaxy)
	_sync_squadron_data()


func _on_fleet_ship_selected(fleet_index: int, _system_id: int) -> void:
	# Center map on the ship entity and follow it
	if _fleet_panel._fleet == null:
		return
	var fs := _fleet_panel._fleet.ships[fleet_index]

	# Active ship = follow the player entity
	if fleet_index == _fleet_panel._fleet.active_index and _player_id != "":
		_follow_entity(_player_id)
		_restore_route_for_fleet_selection(fleet_index)
		return
	# Deployed ship = follow the NPC entity (moving target)
	if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.deployed_npc_id != &"":
		var ent := EntityRegistry.get_entity(String(fs.deployed_npc_id))
		if not ent.is_empty():
			_follow_entity(String(fs.deployed_npc_id))
			_restore_route_for_fleet_selection(fleet_index)
			return
	# Docked ship = center on its station (static, no follow needed)
	if fs.docked_station_id != "":
		var ent := EntityRegistry.get_entity(fs.docked_station_id)
		if not ent.is_empty():
			_center_on_entity(fs.docked_station_id)
			return


func _on_fleet_selection_changed(fleet_indices: Array) -> void:
	_fleet_selected_indices.clear()
	for idx in fleet_indices:
		_fleet_selected_indices.append(idx)
	_restore_route_for_fleet_selection()
	_dirty = true


func _on_sidebar_context_menu(fleet_index: int, screen_pos: Vector2) -> void:
	if _fleet_panel._fleet == null or fleet_index < 0 or fleet_index >= _fleet_panel._fleet.ships.size():
		return
	# Select the ship if not already selected
	if fleet_index not in _fleet_selected_indices:
		_fleet_selected_indices = [fleet_index]
		_fleet_panel.set_selected_fleet_indices(_fleet_selected_indices)

	var fs := _fleet_panel._fleet.ships[fleet_index]
	var context := {
		"fleet_index": fleet_index,
		"fleet_ship": fs,
		"is_deployed": fs.deployment_state == FleetShip.DeploymentState.DEPLOYED,
		"universe_x": 0.0,
		"universe_z": 0.0,
		"target_entity_id": "",
	}

	var orders := FleetOrderRegistry.get_available_orders(context)

	# Inject squadron orders
	var sq_orders := _build_squadron_context_orders(fleet_index)
	orders.append_array(sq_orders)

	# Add promote leader for squadron members
	var sq := _fleet_panel._fleet.get_ship_squadron(fleet_index)
	if sq and sq.is_member(fleet_index):
		orders.append({"id": &"sq_promote", "display_name": "PROMOUVOIR CHEF"})

	if orders.is_empty():
		return

	_close_context_menu()
	_context_menu = FleetContextMenu.new()
	_context_menu.name = "FleetContextMenu"
	add_child(_context_menu)
	_context_menu.order_selected.connect(_on_context_menu_order)
	_context_menu.cancelled.connect(_close_context_menu)
	# Convert panel-local pos to map-global pos
	var global_pos := _fleet_panel.global_position + screen_pos
	_context_menu.show_menu(global_pos, orders, context)


func _on_squadron_header_clicked(_squadron_id: int) -> void:
	# Fleet panel already handles multi-selection of squadron members
	# Just mark dirty for redraw
	_dirty = true


func _on_squadron_rename_requested(squadron_id: int, screen_pos: Vector2) -> void:
	_start_squadron_rename(squadron_id, _fleet_panel.global_position + screen_pos)


func _start_squadron_rename(squadron_id: int, screen_pos: Vector2) -> void:
	_cancel_rename()
	if _fleet_panel._fleet == null:
		return
	var sq := _fleet_panel._fleet.get_squadron(squadron_id)
	if sq == null:
		return

	_rename_sq_id = squadron_id
	_rename_edit = LineEdit.new()
	_rename_edit.text = sq.squadron_name
	_rename_edit.position = Vector2(screen_pos.x, screen_pos.y - 10)
	_rename_edit.custom_minimum_size = Vector2(180, 24)
	_rename_edit.select_all_on_focus = true
	_rename_edit.add_theme_font_size_override("font_size", 13)
	_rename_edit.add_theme_color_override("font_color", UITheme.PRIMARY)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.05, 0.1, 0.95)
	sb.border_color = UITheme.PRIMARY
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_rename_edit.add_theme_stylebox_override("normal", sb)
	_rename_edit.add_theme_stylebox_override("focus", sb)
	add_child(_rename_edit)
	_rename_edit.grab_focus()
	_rename_edit.select_all()
	_rename_edit.text_submitted.connect(_on_rename_submitted)
	_rename_edit.focus_exited.connect(_cancel_rename)


func _on_rename_submitted(new_name: String) -> void:
	if _rename_sq_id >= 0 and new_name.strip_edges() != "":
		squadron_action_requested.emit(&"rename", {"squadron_id": _rename_sq_id, "name": new_name.strip_edges()})
	_cancel_rename()


func _cancel_rename() -> void:
	if _rename_edit:
		_rename_edit.queue_free()
		_rename_edit = null
	_rename_sq_id = -1


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
	var universe_x: float = _camera.screen_to_universe_x(screen_pos.x)
	var universe_z: float = _camera.screen_to_universe_z(screen_pos.y)
	var all_orders: Array[Dictionary] = []

	# --- Fleet orders (only if a ship is selected) ---
	var effective_idx := _get_effective_fleet_index()
	var has_fleet: bool = effective_idx >= 0 and _fleet_panel._fleet != null and effective_idx < _fleet_panel._fleet.ships.size()
	var context: Dictionary = {
		"universe_x": universe_x,
		"universe_z": universe_z,
		"target_entity_id": _entity_layer.get_entity_at(screen_pos),
	}

	# Check if a construction marker is near the click position
	var cm := _entity_layer.get_construction_marker_at(screen_pos)
	if not cm.is_empty():
		context["construction_marker"] = cm

	if has_fleet:
		var fs := _fleet_panel._fleet.ships[effective_idx]
		context["fleet_index"] = effective_idx
		context["fleet_ship"] = fs
		context["is_deployed"] = fs.deployment_state == FleetShip.DeploymentState.DEPLOYED

		var fleet_orders := FleetOrderRegistry.get_available_orders(context)
		var sq_orders := _build_squadron_context_orders(effective_idx)
		fleet_orders.append_array(sq_orders)

		if not fleet_orders.is_empty():
			all_orders.append({"id": &"_header_fleet", "display_name": "ORDRES FLOTTE", "is_header": true})
			all_orders.append_array(fleet_orders)

	# --- Construction orders (always available) ---
	var build_orders := ConstructionOrderRegistry.get_available_orders()
	if not build_orders.is_empty():
		all_orders.append({"id": &"_header_construction", "display_name": "CONSTRUCTION", "is_header": true})
		all_orders.append_array(build_orders)

	if all_orders.is_empty():
		return

	_close_context_menu()
	_context_menu = FleetContextMenu.new()
	_context_menu.name = "FleetContextMenu"
	add_child(_context_menu)
	_context_menu.order_selected.connect(_on_context_menu_order)
	_context_menu.cancelled.connect(_close_context_menu)
	_context_menu.show_menu(screen_pos, all_orders, context)


func _close_context_menu() -> void:
	if _context_menu:
		_context_menu.queue_free()
		_context_menu = null


func _on_context_menu_order(order_id: StringName, params: Dictionary) -> void:
	# Construction actions (prefixed with build_)
	if String(order_id).begins_with("build_"):
		_handle_construction_order(order_id)
		_close_context_menu()
		return

	# Squadron actions (prefixed with sq_)
	if String(order_id).begins_with("sq_"):
		_handle_squadron_context_order(order_id, params)
		_close_context_menu()
		return

	var effective_indices := _get_effective_fleet_indices()
	if not effective_indices.is_empty():
		for idx in effective_indices:
			fleet_order_requested.emit(idx, order_id, params)
		if order_id != &"return_to_station":
			var ux: float = params.get("target_x", params.get("center_x", 0.0))
			var uz: float = params.get("target_z", params.get("center_z", 0.0))
			_show_waypoint(ux, uz)
			_set_route_lines(effective_indices, ux, uz)
			if order_id == &"attack":
				_entity_layer.route_target_entity_id = params.get("target_entity_id", "")
	_close_context_menu()


# =============================================================================
# CONSTRUCTION ORDERS
# =============================================================================
func _handle_construction_order(order_id: StringName) -> void:
	if _context_menu == null or _construction_mgr == null:
		return
	var ctx := _context_menu._context
	var ux: float = ctx.get("universe_x", 0.0)
	var uz: float = ctx.get("universe_z", 0.0)

	var sys_id: int = -1
	if GameManager._system_transition:
		sys_id = GameManager._system_transition.current_system_id

	if order_id == &"build_station":
		var marker := _construction_mgr.add_marker(&"station", "Station spatiale", ux, uz, sys_id)
		_entity_layer.construction_markers = _construction_mgr.get_markers()
		_show_waypoint(ux, uz)
		construction_marker_placed.emit(marker)


# =============================================================================
# SQUADRON CONTEXT ORDERS
# =============================================================================
func _build_squadron_context_orders(fleet_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _fleet_panel._fleet == null:
		return result

	var fleet := _fleet_panel._fleet
	var sq := fleet.get_ship_squadron(fleet_index)

	# Multi-select: "CREATE SQUADRON" if 2+ selected and none are in a squadron
	var effective := _get_effective_fleet_indices()
	if effective.size() >= 2:
		var any_in_sq: bool = false
		for idx in effective:
			if fleet.get_ship_squadron(idx) != null:
				any_in_sq = true
				break
		if not any_in_sq:
			result.append({"id": &"sq_create", "display_name": "CREER ESCADRON"})

	if sq:
		# Ship is in a squadron
		if sq.is_leader(fleet_index) or (sq.leader_fleet_index == -1 and fleet_index == fleet.active_index):
			# Leader options
			result.append({"id": &"sq_disband", "display_name": "DISSOUDRE ESCADRON"})
			# Formation submenu (cycle through)
			var formations := SquadronFormation.get_available_formations()
			for f in formations:
				if f["id"] != sq.formation_type:
					result.append({"id": StringName("sq_formation_" + String(f["id"])), "display_name": "FORMATION: %s" % f["display"]})
		elif sq.is_member(fleet_index):
			# Member options: role change + leave
			result.append({"id": &"sq_leave", "display_name": "QUITTER ESCADRON"})
			for r in SquadronRoleRegistry.get_all_roles():
				if r["id"] != sq.get_role(fleet_index):
					result.append({"id": StringName("sq_role_" + String(r["id"])), "display_name": "ROLE: %s" % r["display"]})
	else:
		# Not in squadron — can join existing squadrons
		for s in fleet.squadrons:
			result.append({"id": StringName("sq_join_%d" % s.squadron_id), "display_name": "REJOINDRE: %s" % s.squadron_name})

	return result


func _handle_squadron_context_order(order_id: StringName, _params: Dictionary) -> void:
	var effective := _get_effective_fleet_indices()
	var order_str := String(order_id)

	if order_id == &"sq_create" and effective.size() >= 2:
		# First selected = leader, rest = members
		squadron_action_requested.emit(&"create", {
			"leader": effective[0],
			"members": effective.slice(1),
		})
	elif order_id == &"sq_disband":
		var idx := _get_effective_fleet_index()
		if idx >= 0 and _fleet_panel._fleet:
			var sq := _fleet_panel._fleet.get_ship_squadron(idx)
			if sq:
				squadron_action_requested.emit(&"disband", {"squadron_id": sq.squadron_id})
	elif order_id == &"sq_leave":
		var idx := _get_effective_fleet_index()
		if idx >= 0:
			squadron_action_requested.emit(&"remove_member", {"fleet_index": idx})
	elif order_str.begins_with("sq_formation_"):
		var formation := StringName(order_str.substr(13))
		var idx := _get_effective_fleet_index()
		if idx >= 0 and _fleet_panel._fleet:
			var sq := _fleet_panel._fleet.get_ship_squadron(idx)
			if sq:
				squadron_action_requested.emit(&"set_formation", {"squadron_id": sq.squadron_id, "formation": String(formation)})
	elif order_str.begins_with("sq_role_"):
		var role := StringName(order_str.substr(8))
		var idx := _get_effective_fleet_index()
		if idx >= 0:
			squadron_action_requested.emit(&"set_role", {"fleet_index": idx, "role": String(role)})
	elif order_id == &"sq_promote":
		var idx := _get_effective_fleet_index()
		if idx >= 0 and _fleet_panel._fleet:
			var sq := _fleet_panel._fleet.get_ship_squadron(idx)
			if sq:
				squadron_action_requested.emit(&"promote_leader", {"squadron_id": sq.squadron_id, "fleet_index": idx})
	elif order_str.begins_with("sq_join_"):
		var sq_id := int(order_str.substr(8))
		var idx := _get_effective_fleet_index()
		if idx >= 0:
			squadron_action_requested.emit(&"add_member", {"squadron_id": sq_id, "fleet_index": idx})


# =============================================================================
# WAYPOINT FLASH
# =============================================================================
func _show_waypoint(ux: float, uz: float) -> void:
	_entity_layer.waypoint_ux = ux
	_entity_layer.waypoint_uz = uz
	_entity_layer.waypoint_timer = MapEntities.WAYPOINT_DURATION
	_dirty = true


func _set_route_lines(fleet_indices: Array[int], dest_ux: float, dest_uz: float) -> void:
	_entity_layer.route_dest_ux = dest_ux
	_entity_layer.route_dest_uz = dest_uz
	_entity_layer.route_target_entity_id = ""  # Reset; caller sets for attack
	_entity_layer.route_ship_ids.clear()
	if _fleet_panel._fleet == null:
		return
	for fleet_index in fleet_indices:
		if fleet_index < 0 or fleet_index >= _fleet_panel._fleet.ships.size():
			continue
		if fleet_index == _fleet_panel._fleet.active_index:
			_entity_layer.route_ship_ids.append(_player_id)
		else:
			var fs := _fleet_panel._fleet.ships[fleet_index]
			if fs.deployed_npc_id != &"":
				_entity_layer.route_ship_ids.append(String(fs.deployed_npc_id))
	_dirty = true


func _clear_route_line() -> void:
	_entity_layer.route_ship_ids.clear()
	_entity_layer.route_target_entity_id = ""
	_dirty = true


## Restores route lines from fleet ship command data (e.g. after map reopen).
## If override_index >= 0, uses that index instead of _fleet_selected_indices
## (needed because ship_selected fires before selection_changed updates the array).
func _restore_route_for_fleet_selection(override_index: int = -1) -> void:
	if _fleet_panel._fleet == null:
		return
	var source_indices: Array[int] = []
	if override_index >= 0:
		source_indices = [override_index]
	else:
		source_indices = _fleet_selected_indices
	if source_indices.is_empty():
		return
	# Find first deployed ship with a target destination
	var first_fs: FleetShip = null
	var restore_indices: Array[int] = []
	for idx in source_indices:
		if idx < 0 or idx >= _fleet_panel._fleet.ships.size():
			continue
		var fs := _fleet_panel._fleet.ships[idx]
		if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.deployed_command != &"":
			restore_indices.append(idx)
			if first_fs == null:
				first_fs = fs
	if first_fs == null or restore_indices.is_empty():
		return
	var params := first_fs.deployed_command_params
	var tx: float = params.get("target_x", params.get("center_x", 0.0))
	var tz: float = params.get("target_z", params.get("center_z", 0.0))
	if tx == 0.0 and tz == 0.0:
		return
	_set_route_lines(restore_indices, tx, tz)
	if first_fs.deployed_command == &"attack":
		_entity_layer.route_target_entity_id = params.get("target_entity_id", "")
