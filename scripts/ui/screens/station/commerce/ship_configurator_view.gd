class_name ShipConfiguratorView
extends Control

# =============================================================================
# Ship Configurator View - Configure loadout before purchasing a ship
# Reuses same UX patterns as EquipmentScreen (tabs, double-click equip, slots)
# but works on a temporary FleetShip + StationStock items with prices
# =============================================================================

signal purchase_completed
signal back_requested

var _commerce_manager: CommerceManager = null
var _station_type: int = 0
var _ship_id: StringName = &""
var _ship_data: ShipData = null
var _fleet_ship: FleetShip = null

# 3D viewer
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _viewer_camera: Camera3D = null
var _model_node: ShipModel = null
var _orbit_yaw: float = 30.0
var _orbit_pitch: float = -15.0
var _orbit_distance: float = 8.0
var _orbit_min_dist: float = 3.0
var _orbit_max_dist: float = 60.0
var _orbit_dragging: bool = false
var _last_input_time: float = 0.0

# UI
var _tab_bar: UITabBar = null
var _item_list: UIScrollList = null
var _buy_btn: UIButton = null
var _back_btn: UIButton = null
var _current_tab: int = 0
var _available_items: Array[StringName] = []
var _selected_slot: int = 0

const TAB_NAMES: Array[String] = ["ARMEMENT", "BOUCLIER", "MOTEUR", "MODULES"]
const VIEWER_RATIO := 0.45
const ROW_H := 44.0
const SLOT_H := 28.0
const BOTTOM_BAR_H := 60.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = TAB_NAMES
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.visible = false
	add_child(_tab_bar)

	_item_list = UIScrollList.new()
	_item_list.row_height = ROW_H
	_item_list.item_draw_callback = _draw_item_row
	_item_list.item_double_clicked.connect(_on_item_double_clicked)
	_item_list.visible = false
	add_child(_item_list)

	_buy_btn = UIButton.new()
	_buy_btn.text = "ACHETER"
	_buy_btn.visible = false
	_buy_btn.pressed.connect(_on_buy_pressed)
	add_child(_buy_btn)

	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.TEXT_DIM
	_back_btn.visible = false
	_back_btn.pressed.connect(func(): back_requested.emit())
	add_child(_back_btn)


func setup(mgr: CommerceManager, stype: int) -> void:
	_commerce_manager = mgr
	_station_type = stype


func set_ship(ship_id: StringName) -> void:
	_ship_id = ship_id
	_ship_data = ShipRegistry.get_ship_data(ship_id)
	if _ship_data == null: return
	# Create empty FleetShip (no default loadout — player picks everything)
	_fleet_ship = FleetShip.new()
	_fleet_ship.ship_id = ship_id
	_fleet_ship.weapons.resize(_ship_data.hardpoints.size())
	for i in _ship_data.hardpoints.size():
		_fleet_ship.weapons[i] = &""
	_fleet_ship.shield_name = &""
	_fleet_ship.engine_name = &""
	_fleet_ship.modules.resize(_ship_data.module_slots.size())
	for i in _ship_data.module_slots.size():
		_fleet_ship.modules[i] = &""

	_current_tab = 0
	_selected_slot = 0
	if _tab_bar: _tab_bar.current_tab = 0
	_setup_3d_viewer()
	_refresh_items()
	_show_controls()
	_layout()


func _on_resized() -> void:
	_layout()


func _show_controls() -> void:
	_tab_bar.visible = true
	_item_list.visible = true
	_buy_btn.visible = true
	_back_btn.visible = true


func _layout() -> void:
	var s := size
	var viewer_w: float = s.x * VIEWER_RATIO
	var sidebar_x: float = viewer_w + 5.0
	var sidebar_w: float = s.x - sidebar_x

	# 3D viewer
	if _viewport_container:
		_viewport_container.position = Vector2(0, 0)
		_viewport_container.size = Vector2(viewer_w, s.y - BOTTOM_BAR_H)
		if _viewport:
			_viewport.size = Vector2i(int(viewer_w), int(s.y - BOTTOM_BAR_H))

	# Tab bar
	_tab_bar.position = Vector2(sidebar_x, 0)
	_tab_bar.size = Vector2(sidebar_w, 28)

	# Slot strip area is drawn procedurally at y=30..30+slot_count*SLOT_H
	var slots_count := _get_current_slot_count()
	var slot_area_h: float = slots_count * SLOT_H + 8.0

	# Item list below slots
	var list_y: float = 30.0 + slot_area_h + 4.0
	var list_h: float = s.y - list_y - BOTTOM_BAR_H - 6.0
	_item_list.position = Vector2(sidebar_x, list_y)
	_item_list.size = Vector2(sidebar_w, list_h)

	# Buttons at bottom
	var btn_w: float = (sidebar_w - 10.0) / 2.0
	_back_btn.position = Vector2(sidebar_x, s.y - BOTTOM_BAR_H + 16.0)
	_back_btn.size = Vector2(btn_w, 34.0)
	_buy_btn.position = Vector2(sidebar_x + btn_w + 10, s.y - BOTTOM_BAR_H + 16.0)
	_buy_btn.size = Vector2(btn_w, 34.0)


func _get_current_slot_count() -> int:
	if _ship_data == null: return 0
	match _current_tab:
		0: return _ship_data.hardpoints.size()
		1: return 1  # shield
		2: return 1  # engine
		3: return _ship_data.module_slots.size()
	return 0


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_selected_slot = 0
	_refresh_items()
	_layout()
	queue_redraw()


func _refresh_items() -> void:
	_available_items.clear()
	match _current_tab:
		0: _available_items.assign(StationStock.get_available_weapons(_station_type))
		1: _available_items.assign(StationStock.get_available_shields(_station_type))
		2: _available_items.assign(StationStock.get_available_engines(_station_type))
		3: _available_items.assign(StationStock.get_available_modules(_station_type))
	var list_items: Array = []
	for item_name in _available_items:
		list_items.append(item_name)
	_item_list.items = list_items
	_item_list.selected_index = -1
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	if idx < 0 or idx >= _available_items.size(): return
	if _fleet_ship == null or _ship_data == null: return
	var item_name: StringName = _available_items[idx]
	match _current_tab:
		0:  # Weapon — equip to selected slot
			if _selected_slot >= 0 and _selected_slot < _fleet_ship.weapons.size():
				var hp: Dictionary = _ship_data.hardpoints[_selected_slot]
				var slot_size: String = hp.get("size", "S")
				var is_turret: bool = hp.get("is_turret", false)
				var w := WeaponRegistry.get_weapon(item_name)
				if w == null: return
				# Size compatibility check
				var w_size: int = w.slot_size  # 0=S, 1=M, 2=L
				var s_size: int = ["S", "M", "L"].find(slot_size)
				if w_size > s_size: return
				# Turret check
				if is_turret and w.weapon_type != WeaponResource.WeaponType.TURRET: return
				if not is_turret and w.weapon_type == WeaponResource.WeaponType.TURRET: return
				_fleet_ship.weapons[_selected_slot] = item_name
		1:  # Shield
			var sh := ShieldRegistry.get_shield(item_name)
			if sh == null: return
			var slot_int: int = ["S", "M", "L"].find(_ship_data.shield_slot_size)
			if sh.slot_size > slot_int: return
			_fleet_ship.shield_name = item_name
		2:  # Engine
			var e := EngineRegistry.get_engine(item_name)
			if e == null: return
			var slot_int: int = ["S", "M", "L"].find(_ship_data.engine_slot_size)
			if e.slot_size > slot_int: return
			_fleet_ship.engine_name = item_name
		3:  # Module
			if _selected_slot >= 0 and _selected_slot < _fleet_ship.modules.size():
				var m := ModuleRegistry.get_module(item_name)
				if m == null: return
				var slot_size_str: String = _ship_data.module_slots[_selected_slot]
				var slot_int: int = ["S", "M", "L"].find(slot_size_str)
				if m.slot_size > slot_int: return
				_fleet_ship.modules[_selected_slot] = item_name
	queue_redraw()


func _on_buy_pressed() -> void:
	if _commerce_manager == null or _fleet_ship == null or _ship_data == null: return
	var total: int = _ship_data.price + _fleet_ship.get_total_equipment_value()
	if not _commerce_manager.can_afford(total): return
	if _commerce_manager.buy_ship(_ship_id, _fleet_ship):
		purchase_completed.emit()


# =========================================================================
# 3D VIEWER (same pattern as ShipShopView)
# =========================================================================
func _setup_3d_viewer() -> void:
	_cleanup_3d_viewer()
	if _ship_data == null: return

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_viewport_container)
	move_child(_viewport_container, 0)

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

	# Scale lights to model size
	var scene_scale := ShipFactory.get_scene_model_scale(_ship_id)
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

	_viewer_camera = Camera3D.new()
	_viewer_camera.fov = 40.0
	_viewer_camera.near = 0.1
	_viewer_camera.far = 500.0
	_viewport.add_child(_viewer_camera)

	_model_node = ShipModel.new()
	_model_node.model_path = _ship_data.model_path
	_model_node.model_scale = scene_scale
	_model_node.model_rotation_degrees = ShipFactory.get_model_rotation(_ship_id)
	_model_node.skip_centering = false
	_model_node.engine_light_color = Color(0.3, 0.5, 1.0)
	_viewport.add_child(_model_node)

	_orbit_yaw = 30.0
	_orbit_pitch = -15.0
	_auto_fit_camera()
	_update_orbit_camera()


func _cleanup_3d_viewer() -> void:
	if _model_node and is_instance_valid(_model_node):
		_model_node.queue_free()
		_model_node = null
	if _viewport_container and is_instance_valid(_viewport_container):
		_viewport_container.queue_free()
		_viewport_container = null
		_viewport = null
		_viewer_camera = null


func _update_orbit_camera() -> void:
	if _viewer_camera == null: return
	var yaw_rad := deg_to_rad(_orbit_yaw)
	var pitch_rad := deg_to_rad(_orbit_pitch)
	_viewer_camera.position = Vector3(
		_orbit_distance * cos(pitch_rad) * sin(yaw_rad),
		_orbit_distance * sin(pitch_rad),
		_orbit_distance * cos(pitch_rad) * cos(yaw_rad),
	)
	_viewer_camera.look_at(Vector3.ZERO, Vector3.UP)


func _auto_fit_camera() -> void:
	var max_radius: float = 2.0
	if _model_node:
		var aabb := _model_node.get_visual_aabb()
		for i in 8:
			var corner: Vector3 = aabb.get_endpoint(i) + _model_node.position
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
		# Check if click is in slot strip area (right side)
		var viewer_w: float = size.x * VIEWER_RATIO
		if mb.position.x > viewer_w and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var slot_y: float = mb.position.y - 34.0
			var slot_idx: int = int(slot_y / SLOT_H)
			if slot_idx >= 0 and slot_idx < _get_current_slot_count():
				_selected_slot = slot_idx
				queue_redraw()
				return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = mb.pressed
			_last_input_time = 0.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(_orbit_min_dist, _orbit_distance * 0.9)
			_update_orbit_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(_orbit_max_dist, _orbit_distance * 1.1)
			_update_orbit_camera()
	elif event is InputEventMouseMotion and _orbit_dragging:
		var mm := event as InputEventMouseMotion
		_orbit_yaw += mm.relative.x * 0.3
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.3, -80.0, 80.0)
		_update_orbit_camera()


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
	var viewer_w: float = s.x * VIEWER_RATIO
	var sidebar_x: float = viewer_w + 5.0
	var sidebar_w: float = s.x - sidebar_x

	# Viewer/sidebar separator
	draw_line(Vector2(viewer_w + 2, 0), Vector2(viewer_w + 2, s.y), UITheme.BORDER, 1.0)

	if _ship_data == null or _fleet_ship == null: return

	# Slot strip
	var slot_y: float = 34.0
	var slot_count := _get_current_slot_count()
	for i in slot_count:
		var rect := Rect2(sidebar_x, slot_y + i * SLOT_H, sidebar_w, SLOT_H - 2.0)
		var is_sel: bool = (i == _selected_slot)
		var bg_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12 if is_sel else 0.04)
		draw_rect(rect, bg_col)
		if is_sel:
			draw_rect(rect, UITheme.PRIMARY, false, 1.0)

		# Slot label
		var slot_label := _get_slot_label(i)
		var equipped_name := _get_equipped_name(i)
		draw_string(font, Vector2(rect.position.x + 6, rect.position.y + 10),
			slot_label, HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
		var eq_color: Color = UITheme.TEXT if equipped_name != "(vide)" else UITheme.TEXT_DIM
		draw_string(font, Vector2(rect.position.x + 90, rect.position.y + 10),
			equipped_name, HORIZONTAL_ALIGNMENT_LEFT, sidebar_w - 100, UITheme.FONT_SIZE_SMALL, eq_color)

		# Price of equipped item
		if equipped_name != "(vide)":
			var item_price := _get_equipped_price(i)
			if item_price > 0:
				draw_string(font, Vector2(rect.position.x + 6, rect.position.y + 22),
					PriceCatalog.format_price(item_price),
					HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, PlayerEconomy.CREDITS_COLOR)

	# Bottom price bar
	var bottom_y: float = s.y - BOTTOM_BAR_H
	draw_rect(Rect2(0, bottom_y, s.x, BOTTOM_BAR_H), Color(0.01, 0.02, 0.04, 0.7))
	draw_line(Vector2(0, bottom_y), Vector2(s.x, bottom_y), UITheme.BORDER, 1.0)

	var ship_price: int = _ship_data.price
	var equip_price: int = _fleet_ship.get_total_equipment_value()
	var total: int = ship_price + equip_price

	draw_string(font, Vector2(10, bottom_y + 16),
		"Vaisseau: " + PriceCatalog.format_price(ship_price),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(10, bottom_y + 32),
		"Equipement: " + PriceCatalog.format_price(equip_price),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(s.x * 0.4, bottom_y + 28),
		"TOTAL: " + PriceCatalog.format_price(total),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)

	# Can afford?
	if _commerce_manager and _commerce_manager.player_economy:
		var credits := _commerce_manager.player_economy.credits
		draw_string(font, Vector2(10, bottom_y + 48),
			"Credits: " + PriceCatalog.format_price(credits),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL,
			UITheme.TEXT if credits >= total else UITheme.DANGER)


func _get_slot_label(slot_idx: int) -> String:
	match _current_tab:
		0:
			if _ship_data and slot_idx < _ship_data.hardpoints.size():
				var hp: Dictionary = _ship_data.hardpoints[slot_idx]
				var sz: String = hp.get("size", "S")
				var turret: bool = hp.get("is_turret", false)
				return "[%s]%s" % [sz, " T" if turret else ""]
			return "[?]"
		1: return "[%s]" % _ship_data.shield_slot_size
		2: return "[%s]" % _ship_data.engine_slot_size
		3:
			if _ship_data and slot_idx < _ship_data.module_slots.size():
				return "[%s]" % _ship_data.module_slots[slot_idx]
			return "[?]"
	return ""


func _get_equipped_name(slot_idx: int) -> String:
	if _fleet_ship == null: return "(vide)"
	match _current_tab:
		0:
			if slot_idx < _fleet_ship.weapons.size() and _fleet_ship.weapons[slot_idx] != &"":
				return String(_fleet_ship.weapons[slot_idx])
		1:
			if _fleet_ship.shield_name != &"":
				return String(_fleet_ship.shield_name)
		2:
			if _fleet_ship.engine_name != &"":
				return String(_fleet_ship.engine_name)
		3:
			if slot_idx < _fleet_ship.modules.size() and _fleet_ship.modules[slot_idx] != &"":
				return String(_fleet_ship.modules[slot_idx])
	return "(vide)"


func _get_equipped_price(slot_idx: int) -> int:
	if _fleet_ship == null: return 0
	match _current_tab:
		0:
			if slot_idx < _fleet_ship.weapons.size():
				return PriceCatalog.get_weapon_price(_fleet_ship.weapons[slot_idx])
		1: return PriceCatalog.get_shield_price(_fleet_ship.shield_name)
		2: return PriceCatalog.get_engine_price(_fleet_ship.engine_name)
		3:
			if slot_idx < _fleet_ship.modules.size():
				return PriceCatalog.get_module_price(_fleet_ship.modules[slot_idx])
	return 0


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _available_items.size(): return
	var item_name: StringName = _available_items[idx]
	var font: Font = UITheme.get_font()

	if idx == _item_list.selected_index:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12))

	var name_str := String(item_name)
	var price: int = 0
	var size_str := ""
	var detail := ""

	match _current_tab:
		0:
			var w := WeaponRegistry.get_weapon(item_name)
			if w:
				price = w.price
				size_str = ["S", "M", "L"][w.slot_size]
				detail = "DPS: %.0f" % (w.damage_per_hit * w.fire_rate)
		1:
			var sh := ShieldRegistry.get_shield(item_name)
			if sh:
				price = sh.price
				size_str = ["S", "M", "L"][sh.slot_size]
				detail = "%.0f PV/face" % sh.shield_hp_per_facing
		2:
			var en := EngineRegistry.get_engine(item_name)
			if en:
				price = en.price
				size_str = ["S", "M", "L"][en.slot_size]
				detail = "x%.2f accel" % en.accel_mult
		3:
			var mo := ModuleRegistry.get_module(item_name)
			if mo:
				price = mo.price
				size_str = ["S", "M", "L"][mo.slot_size]
				var bonuses := mo.get_bonuses_text()
				detail = bonuses[0] if bonuses.size() > 0 else ""

	# Size badge
	ci.draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 14),
		"[%s]" % size_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Name
	ci.draw_string(font, Vector2(rect.position.x + 30, rect.position.y + 14),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Detail + price
	ci.draw_string(font, Vector2(rect.position.x + 30, rect.position.y + 30),
		detail, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.5,
		UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.6, rect.position.y + 30),
		PriceCatalog.format_price(price), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.35,
		UITheme.FONT_SIZE_TINY, PlayerEconomy.CREDITS_COLOR)
