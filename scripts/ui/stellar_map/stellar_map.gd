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
var _search: MapSearch = null
var _legend: MapLegend = null

var _is_open: bool = false
var _player_id: String = ""
var _was_mouse_captured: bool = false

## When true, this map is managed by UnifiedMapScreen.
## Escape/M/G are NOT consumed — they propagate to UIScreenManager/GameManager.
## Tab emits view_switch_requested instead of being consumed silently.
var managed_externally: bool = false
signal view_switch_requested
signal navigate_to_requested(entity_id: String)

# Pan state
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO

# Double-click detection
var _last_click_time: float = 0.0
var _last_click_id: String = ""

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

	# Renderer (background, grid, orbits)
	_renderer = MapRenderer.new()
	_renderer.name = "MapRenderer"
	_setup_full_rect(_renderer)
	_renderer.camera = _camera
	_renderer.filters = _filters
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

	# Search bar
	_search = MapSearch.new()
	_search.name = "MapSearch"
	_setup_full_rect(_search)
	_search.entity_selected.connect(_on_search_entity_selected)
	add_child(_search)

	# Legend overlay
	_legend = MapLegend.new()
	_legend.name = "MapLegend"
	_setup_full_rect(_legend)
	add_child(_legend)


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

	# Show legend on first open (brief help)
	_legend.show_legend()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_is_panning = false
	_search.close()

	# Restore mouse capture (skip when managed — UIScreenManager handles it)
	if _was_mouse_captured and not managed_externally:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_system_radius() -> void:
	var max_r: float = Constants.SYSTEM_RADIUS
	for ent in EntityRegistry.get_all().values():
		var r: float = ent["orbital_radius"]
		if r > max_r:
			max_r = r
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

	if _dirty:
		_renderer.queue_redraw()
		_entity_layer.queue_redraw()
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

		# H = legend
		if event.physical_keycode == KEY_H:
			_legend.toggle()
			get_viewport().set_input_as_handled()
			return

		# Consume all other key presses
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.pressed:
		get_viewport().set_input_as_handled()
		return

	# Mouse wheel = zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom_at(event.position, MapCamera.ZOOM_STEP)
			_dirty = true
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
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

		# Left click = select entity (+ double-click detection)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit_id: String = _entity_layer.get_entity_at(event.position)
			var now: float = Time.get_ticks_msec() / 1000.0

			# Double-click: same entity within 0.4s -> navigate to it
			if hit_id != "" and hit_id == _last_click_id and (now - _last_click_time) < 0.4:
				navigate_to_requested.emit(hit_id)
				_last_click_id = ""
			else:
				_select_entity(hit_id)
				_last_click_id = hit_id
				_last_click_time = now

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
		if _is_panning:
			_camera.pan(event.relative)
			_dirty = true
		else:
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


func _on_search_entity_selected(id: String) -> void:
	_center_on_entity(id)
