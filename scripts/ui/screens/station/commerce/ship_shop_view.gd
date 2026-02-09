class_name ShipShopView
extends Control

# =============================================================================
# Ship Shop View - Browse ships with 3D preview + stats panel
# Left: Ship list, Center: 3D preview, Right: Stats + price + configure button
# =============================================================================

signal ship_purchased(ship_id: StringName)

var _commerce_manager: CommerceManager = null
var _station_type: int = 0
var _available_ships: Array[StringName] = []
var _selected_index: int = 0

# 3D Viewer
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _viewer_camera: Camera3D = null
var _ship_model_node: ShipModel = null
var _orbit_yaw: float = 30.0
var _orbit_pitch: float = -15.0
var _orbit_distance: float = 8.0
var _orbit_min_dist: float = 3.0
var _orbit_max_dist: float = 60.0
var _orbit_dragging: bool = false
var _last_input_time: float = 0.0

# UI
var _ship_list: UIScrollList = null
var _configure_btn: UIButton = null

const LIST_W := 160.0
const STATS_W := 220.0
const ROW_H := 36.0
const SIZE_LABELS := { "S": "Petit", "M": "Moyen", "L": "Grand" }


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)

	_ship_list = UIScrollList.new()
	_ship_list.row_height = ROW_H
	_ship_list.item_draw_callback = _draw_ship_row
	_ship_list.item_selected.connect(_on_ship_selected)
	_ship_list.visible = false
	add_child(_ship_list)

	_configure_btn = UIButton.new()
	_configure_btn.text = "ACHETER"
	_configure_btn.visible = false
	_configure_btn.pressed.connect(_on_buy_pressed)
	add_child(_configure_btn)


func setup(mgr: CommerceManager, stype: int) -> void:
	_commerce_manager = mgr
	_station_type = stype


func refresh() -> void:
	_available_ships = StationStock.get_available_ships(_station_type)
	if _selected_index >= _available_ships.size():
		_selected_index = 0
	var list_items: Array = []
	for sid in _available_ships:
		list_items.append(sid)
	_ship_list.items = list_items
	_ship_list.selected_index = _selected_index
	_ship_list.visible = true
	_configure_btn.visible = true
	_setup_3d_viewer()
	_layout()
	_update_preview()


func _layout() -> void:
	var s := size
	# Ship list on left
	_ship_list.position = Vector2(0, 0)
	_ship_list.size = Vector2(LIST_W, s.y)
	# 3D viewer in center
	if _viewport_container:
		var vx: float = LIST_W + 5.0
		var vw: float = s.x - LIST_W - STATS_W - 10.0
		_viewport_container.position = Vector2(vx, 0)
		_viewport_container.size = Vector2(vw, s.y - 50.0)
	# Configure button
	_configure_btn.position = Vector2(s.x - STATS_W, s.y - 42.0)
	_configure_btn.size = Vector2(STATS_W - 5.0, 34.0)


func _on_ship_selected(idx: int) -> void:
	if idx < 0 or idx >= _available_ships.size(): return
	_selected_index = idx
	_update_preview()
	queue_redraw()


func _on_resized() -> void:
	_layout()


func _on_buy_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _available_ships.size():
		return
	if _commerce_manager == null:
		return
	var ship_id: StringName = _available_ships[_selected_index]
	if _commerce_manager.buy_ship(ship_id):
		ship_purchased.emit(ship_id)
		queue_redraw()


func _get_selected_ship_data() -> ShipData:
	if _selected_index < 0 or _selected_index >= _available_ships.size():
		return null
	return ShipRegistry.get_ship_data(_available_ships[_selected_index])


# =========================================================================
# 3D VIEWER
# =========================================================================
func _setup_3d_viewer() -> void:
	_cleanup_3d_viewer()
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_viewport_container)
	move_child(_viewport_container, 0)  # Behind UI elements

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

	_viewer_camera = Camera3D.new()
	_viewer_camera.fov = 40.0
	_viewer_camera.near = 0.1
	_viewer_camera.far = 500.0
	_viewport.add_child(_viewer_camera)


func _cleanup_3d_viewer() -> void:
	if _ship_model_node and is_instance_valid(_ship_model_node):
		_ship_model_node.queue_free()
		_ship_model_node = null
	if _viewport_container and is_instance_valid(_viewport_container):
		_viewport_container.queue_free()
		_viewport_container = null
		_viewport = null
		_viewer_camera = null


func _update_preview() -> void:
	var data := _get_selected_ship_data()
	if data == null or _viewport == null: return

	# Remove old model + old lights
	if _ship_model_node and is_instance_valid(_ship_model_node):
		_ship_model_node.queue_free()
		_ship_model_node = null
	# Remove existing omni lights (fill + rim) from previous preview
	for child in _viewport.get_children():
		if child is OmniLight3D:
			child.queue_free()

	# Scale lights to model size so all ships are well-lit
	var scene_scale := ShipFactory.get_scene_model_scale(_available_ships[_selected_index])
	var light_scale := maxf(1.0, scene_scale)
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

	_ship_model_node = ShipModel.new()
	_ship_model_node.model_path = data.model_path
	_ship_model_node.model_scale = scene_scale
	_ship_model_node.model_rotation_degrees = ShipFactory.get_model_rotation(_available_ships[_selected_index])
	_ship_model_node.skip_centering = false
	_ship_model_node.engine_light_color = Color(0.3, 0.5, 1.0)
	_viewport.add_child(_ship_model_node)

	_orbit_yaw = 30.0
	_orbit_pitch = -15.0
	_auto_fit_camera()
	_update_orbit_camera()
	_layout()


func _update_orbit_camera() -> void:
	if _viewer_camera == null: return
	var yaw_rad := deg_to_rad(_orbit_yaw)
	var pitch_rad := deg_to_rad(_orbit_pitch)
	var pos := Vector3(
		_orbit_distance * cos(pitch_rad) * sin(yaw_rad),
		_orbit_distance * sin(pitch_rad),
		_orbit_distance * cos(pitch_rad) * cos(yaw_rad),
	)
	_viewer_camera.position = pos
	_viewer_camera.look_at(Vector3.ZERO, Vector3.UP)


func _auto_fit_camera() -> void:
	var max_radius: float = 2.0
	if _ship_model_node:
		var aabb := _ship_model_node.get_visual_aabb()
		for i in 8:
			var corner: Vector3 = aabb.get_endpoint(i) + _ship_model_node.position
			max_radius = maxf(max_radius, corner.length())
	var half_fov := deg_to_rad(_viewer_camera.fov * 0.5) if _viewer_camera else deg_to_rad(20.0)
	var ideal := max_radius / tan(half_fov) * 1.3
	_orbit_distance = ideal
	_orbit_min_dist = ideal * 0.4
	_orbit_max_dist = ideal * 3.0
	if _viewer_camera:
		_viewer_camera.far = maxf(500.0, _orbit_max_dist + max_radius * 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = mb.pressed
			_last_input_time = 0.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(_orbit_min_dist, _orbit_distance * 0.9)
			_update_orbit_camera()
			_last_input_time = 0.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(_orbit_max_dist, _orbit_distance * 1.1)
			_update_orbit_camera()
			_last_input_time = 0.0
	elif event is InputEventMouseMotion and _orbit_dragging:
		var mm := event as InputEventMouseMotion
		_orbit_yaw += mm.relative.x * 0.3
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.3, -80.0, 80.0)
		_update_orbit_camera()
		_last_input_time = 0.0


func _process(delta: float) -> void:
	_last_input_time += delta
	if _last_input_time > 3.0:
		_orbit_yaw += delta * 6.0
		_update_orbit_camera()
	if visible:
		queue_redraw()


# =========================================================================
# DRAWING
# =========================================================================
func _draw() -> void:
	var s := size
	var font: Font = UITheme.get_font()

	# Stats panel background (right side)
	var stats_x: float = s.x - STATS_W
	draw_rect(Rect2(stats_x, 0, STATS_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(stats_x, 0), Vector2(stats_x, s.y), UITheme.BORDER, 1.0)

	# List separator
	draw_line(Vector2(LIST_W + 2, 0), Vector2(LIST_W + 2, s.y), UITheme.BORDER, 1.0)

	var data := _get_selected_ship_data()
	if data == null: return

	# Ship name + class
	var y: float = 12.0
	draw_string(font, Vector2(stats_x + 10, y + 10), String(data.ship_name).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, STATS_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 22.0
	draw_string(font, Vector2(stats_x + 10, y + 10), "Classe: " + String(data.ship_class),
		HORIZONTAL_ALIGNMENT_LEFT, STATS_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	y += 24.0

	# Section: COQUE
	y = _draw_stat_section(font, stats_x, y, "COQUE", [
		["PV", "%.0f" % data.hull_hp],
		["Blindage", "%.0f" % data.armor_rating],
	])

	# Section: BOUCLIER
	y = _draw_stat_section(font, stats_x, y, "BOUCLIER", [
		["PV/face", "%.0f" % data.shield_hp],
		["Regen", "%.0f/s" % data.shield_regen_rate],
	])

	# Section: VOL
	y = _draw_stat_section(font, stats_x, y, "VOL", [
		["Vitesse", "%.0f m/s" % data.max_speed_normal],
		["Boost", "%.0f m/s" % data.max_speed_boost],
		["Accel", "%.0f" % data.accel_forward],
	])

	# Section: SLOTS
	var hp_sizes: Dictionary = {}
	for hp in data.hardpoints:
		var sz: String = hp.get("size", "S")
		hp_sizes[sz] = hp_sizes.get(sz, 0) + 1
	var hp_text := ""
	for sz_key in ["S", "M", "L"]:
		if hp_sizes.has(sz_key):
			hp_text += "%dx %s  " % [hp_sizes[sz_key], sz_key]

	var slot_lines: Array = [["Hardpoints", hp_text.strip_edges()]]
	slot_lines.append(["Bouclier", data.shield_slot_size])
	slot_lines.append(["Moteur", data.engine_slot_size])
	var mod_sizes: Dictionary = {}
	for ms in data.module_slots:
		mod_sizes[ms] = mod_sizes.get(ms, 0) + 1
	var mod_text := ""
	for sz_key in ["S", "M", "L"]:
		if mod_sizes.has(sz_key):
			mod_text += "%dx %s  " % [mod_sizes[sz_key], sz_key]
	if mod_text != "":
		slot_lines.append(["Modules", mod_text.strip_edges()])
	y = _draw_stat_section(font, stats_x, y, "SLOTS", slot_lines)

	# Price
	y += 8.0
	var price_text := PriceCatalog.format_price(data.price)
	draw_rect(Rect2(stats_x + 10, y, STATS_W - 20, 30),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.1))
	draw_rect(Rect2(stats_x + 10, y, STATS_W - 20, 30),
		UITheme.PRIMARY, false, 1.0)
	draw_string(font, Vector2(stats_x + 10, y + 20), price_text,
		HORIZONTAL_ALIGNMENT_CENTER, STATS_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)

	# Afford indicator + button state
	if _commerce_manager and _commerce_manager.player_economy:
		var can_buy: bool = _commerce_manager.player_economy.credits >= data.price
		if _configure_btn:
			_configure_btn.enabled = can_buy
		if not can_buy:
			draw_string(font, Vector2(stats_x + 10, y + 44), "CREDITS INSUFFISANTS",
				HORIZONTAL_ALIGNMENT_CENTER, STATS_W - 20, UITheme.FONT_SIZE_TINY, UITheme.DANGER)


func _draw_stat_section(font: Font, x: float, y: float, title: String, rows: Array) -> float:
	# Section title
	draw_rect(Rect2(x + 10, y, 2, 10), UITheme.PRIMARY)
	draw_string(font, Vector2(x + 16, y + 9), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_HEADER)
	y += 16.0
	# Rows
	for row in rows:
		draw_string(font, Vector2(x + 16, y + 10), row[0],
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
		draw_string(font, Vector2(x + 100, y + 10), row[1],
			HORIZONTAL_ALIGNMENT_LEFT, STATS_W - 110, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
		y += 16.0
	y += 6.0
	return y


func _draw_ship_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _available_ships.size(): return
	var data := ShipRegistry.get_ship_data(_available_ships[idx])
	if data == null: return

	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _ship_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

	# Ship name
	ci.draw_string(font, Vector2(rect.position.x + 8, rect.position.y + 16),
		String(data.ship_name), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Class + price
	var info := String(data.ship_class) + " — " + PriceCatalog.format_price(data.price)
	ci.draw_string(font, Vector2(rect.position.x + 8, rect.position.y + 30),
		info, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16,
		UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
