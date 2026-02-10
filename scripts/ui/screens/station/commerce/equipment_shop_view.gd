class_name EquipmentShopView
extends Control

# =============================================================================
# Equipment Shop View - Buy weapons/shields/engines/modules to inventory
# Left: Tab bar + sortable item list (UIScrollList)
# Right: Detail panel with stats + price + buy button
# =============================================================================

var _commerce_manager: CommerceManager = null
var _station_type: int = 0
var _initial_tab: int = 0

var _tab_bar: UITabBar = null
var _item_list: UIScrollList = null
var _buy_btn: UIButton = null
var _current_tab: int = 0
var _available_items: Array[StringName] = []
var _selected_index: int = -1

const TAB_NAMES: Array[String] = ["ARMEMENT", "BOUCLIERS", "MOTEURS", "MODULES"]
const DETAIL_W := 240.0
const ROW_H := 48.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout)

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = TAB_NAMES
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.visible = false
	add_child(_tab_bar)

	_item_list = UIScrollList.new()
	_item_list.row_height = ROW_H
	_item_list.item_draw_callback = _draw_item_row
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_double_clicked.connect(_on_item_double_clicked)
	_item_list.visible = false
	add_child(_item_list)

	_buy_btn = UIButton.new()
	_buy_btn.text = "ACHETER"
	_buy_btn.visible = false
	_buy_btn.pressed.connect(_on_buy_pressed)
	add_child(_buy_btn)


func setup(mgr: CommerceManager, stype: int) -> void:
	_commerce_manager = mgr
	_station_type = stype


func set_initial_tab(tab: int) -> void:
	_initial_tab = tab


func refresh() -> void:
	_current_tab = _initial_tab
	if _tab_bar: _tab_bar.current_tab = _current_tab
	_tab_bar.visible = true
	_item_list.visible = true
	_buy_btn.visible = true
	_refresh_items()
	_layout()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_tab_bar.position = Vector2(0, 0)
	_tab_bar.size = Vector2(list_w, 28)
	_item_list.position = Vector2(0, 32)
	_item_list.size = Vector2(list_w, s.y - 32)
	_buy_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_buy_btn.size = Vector2(DETAIL_W - 20, 34)


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_selected_index = -1
	_refresh_items()
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
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	_do_buy()


func _on_buy_pressed() -> void:
	_do_buy()


func _do_buy() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _available_items.size(): return
	var item_name: StringName = _available_items[_selected_index]
	var success: bool = false
	match _current_tab:
		0: success = _commerce_manager.buy_weapon(item_name)
		1: success = _commerce_manager.buy_shield(item_name)
		2: success = _commerce_manager.buy_engine(item_name)
		3: success = _commerce_manager.buy_module(item_name)
	if success:
		# Show toast
		var toast_mgr := _find_toast_manager()
		if toast_mgr:
			toast_mgr.show_toast("%s acheté!" % String(item_name))
	queue_redraw()


func _find_toast_manager() -> UIToastManager:
	var node := get_tree().root.find_child("UIToastManager", true, false)
	return node as UIToastManager if node else null


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# =========================================================================
# DRAWING
# =========================================================================
func _draw() -> void:
	var s := size
	var font: Font = UITheme.get_font()
	var detail_x: float = s.x - DETAIL_W

	# Detail panel background
	draw_rect(Rect2(detail_x, 0, DETAIL_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(detail_x, 0), Vector2(detail_x, s.y), UITheme.BORDER, 1.0)

	# Draw selected item details
	if _selected_index < 0 or _selected_index >= _available_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un objet",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item_name: StringName = _available_items[_selected_index]
	var y: float = 10.0

	match _current_tab:
		0: y = _draw_weapon_detail(font, detail_x, y, item_name)
		1: y = _draw_shield_detail(font, detail_x, y, item_name)
		2: y = _draw_engine_detail(font, detail_x, y, item_name)
		3: y = _draw_module_detail(font, detail_x, y, item_name)

	# Inventory count
	if _commerce_manager and _commerce_manager.player_inventory:
		var count: int = 0
		match _current_tab:
			0: count = _commerce_manager.player_inventory.get_weapon_count(item_name)
			1: count = _commerce_manager.player_inventory.get_shield_count(item_name)
			2: count = _commerce_manager.player_inventory.get_engine_count(item_name)
			3: count = _commerce_manager.player_inventory.get_module_count(item_name)
		if count > 0:
			draw_string(font, Vector2(detail_x + 10, y + 14),
				"En stock: %d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _draw_weapon_detail(font: Font, x: float, y: float, wn: StringName) -> float:
	var w := WeaponRegistry.get_weapon(wn)
	if w == null: return y

	# Name
	draw_string(font, Vector2(x + 10, y + 14), String(wn).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	var type_str: String = ["Laser", "Plasma", "Missile", "Railgun", "Mine", "Tourelle", "Laser Minier"][w.weapon_type]
	var size_str: String = ["S", "M", "L"][w.slot_size]

	y = _draw_detail_rows(font, x, y, [
		["Type", type_str],
		["Taille", size_str],
		["Degats", "%.0f/tir" % w.damage_per_hit],
		["Cadence", "%.1f/s" % w.fire_rate],
		["DPS", "%.0f" % (w.damage_per_hit * w.fire_rate)],
		["Energie", "%.0f/tir" % w.energy_cost_per_shot],
		["Portee", "%.0fm" % (w.projectile_speed * w.projectile_lifetime)],
	])

	y = _draw_price_box(font, x, y, w.price)
	return y


func _draw_shield_detail(font: Font, x: float, y: float, sn: StringName) -> float:
	var sh := ShieldRegistry.get_shield(sn)
	if sh == null: return y

	draw_string(font, Vector2(x + 10, y + 14), String(sn).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	y = _draw_detail_rows(font, x, y, [
		["Taille", ["S", "M", "L"][sh.slot_size]],
		["PV/face", "%.0f" % sh.shield_hp_per_facing],
		["PV total", "%.0f" % (sh.shield_hp_per_facing * 4)],
		["Regen", "%.0f/s" % sh.regen_rate],
		["Delai", "%.1fs" % sh.regen_delay],
		["Perforation", "%.0f%%" % (sh.bleedthrough * 100)],
	])

	y = _draw_price_box(font, x, y, sh.price)
	return y


func _draw_engine_detail(font: Font, x: float, y: float, en: StringName) -> float:
	var e := EngineRegistry.get_engine(en)
	if e == null: return y

	draw_string(font, Vector2(x + 10, y + 14), String(en).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	y = _draw_detail_rows(font, x, y, [
		["Taille", ["S", "M", "L"][e.slot_size]],
		["Acceleration", "x%.2f" % e.accel_mult],
		["Vitesse", "x%.2f" % e.speed_mult],
		["Rotation", "x%.2f" % e.rotation_mult],
		["Cruise", "x%.2f" % e.cruise_mult],
		["Conso boost", "x%.2f" % e.boost_drain_mult],
	])

	y = _draw_price_box(font, x, y, e.price)
	return y


func _draw_module_detail(font: Font, x: float, y: float, mn: StringName) -> float:
	var m := ModuleRegistry.get_module(mn)
	if m == null: return y

	draw_string(font, Vector2(x + 10, y + 14), String(mn).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	var rows: Array = [["Taille", ["S", "M", "L"][m.slot_size]]]
	var bonuses := m.get_bonuses_text()
	for bonus in bonuses:
		rows.append(["Bonus", bonus])
	y = _draw_detail_rows(font, x, y, rows)

	y = _draw_price_box(font, x, y, m.price)
	return y


func _draw_detail_rows(font: Font, x: float, y: float, rows: Array) -> float:
	for row in rows:
		draw_string(font, Vector2(x + 10, y + 12), row[0],
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(x + 95, y + 12), row[1],
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
		y += 18.0
	y += 6.0
	return y


func _draw_price_box(font: Font, x: float, y: float, price: int) -> float:
	y += 4.0
	draw_rect(Rect2(x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.1))
	draw_rect(Rect2(x + 10, y, DETAIL_W - 20, 28), UITheme.PRIMARY, false, 1.0)
	draw_string(font, Vector2(x + 10, y + 19), PriceCatalog.format_price(price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)
	y += 36.0

	# Can afford?
	if _commerce_manager and _commerce_manager.player_economy:
		if _commerce_manager.player_economy.credits < price:
			draw_string(font, Vector2(x + 10, y + 10), "CREDITS INSUFFISANTS",
				HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.DANGER)
			y += 18.0
	return y


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _available_items.size(): return
	var item_name: StringName = _available_items[idx]
	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

	var name_str := String(item_name)
	var size_str := ""
	var stat_str := ""
	var price: int = 0

	match _current_tab:
		0:  # Weapons
			var w := WeaponRegistry.get_weapon(item_name)
			if w:
				size_str = ["S", "M", "L"][w.slot_size]
				stat_str = "DPS: %.0f" % (w.damage_per_hit * w.fire_rate)
				price = w.price
		1:  # Shields
			var sh := ShieldRegistry.get_shield(item_name)
			if sh:
				size_str = ["S", "M", "L"][sh.slot_size]
				stat_str = "%.0f PV/face" % sh.shield_hp_per_facing
				price = sh.price
		2:  # Engines
			var en := EngineRegistry.get_engine(item_name)
			if en:
				size_str = ["S", "M", "L"][en.slot_size]
				stat_str = "x%.2f accel" % en.accel_mult
				price = en.price
		3:  # Modules
			var mo := ModuleRegistry.get_module(item_name)
			if mo:
				size_str = ["S", "M", "L"][mo.slot_size]
				var bonuses := mo.get_bonuses_text()
				stat_str = bonuses[0] if bonuses.size() > 0 else ""
				price = mo.price

	# Size badge
	var badge_col: Color = UITheme.PRIMARY if size_str == "S" else (UITheme.WARNING if size_str == "M" else Color(1.0, 0.5, 0.2))
	ci.draw_rect(Rect2(rect.position.x + 4, rect.position.y + 4, 24, 16), Color(badge_col.r, badge_col.g, badge_col.b, 0.2))
	ci.draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 16),
		size_str, HORIZONTAL_ALIGNMENT_CENTER, 24, UITheme.FONT_SIZE_TINY, badge_col)

	# Name
	ci.draw_string(font, Vector2(rect.position.x + 34, rect.position.y + 16),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_LABEL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Stats
	ci.draw_string(font, Vector2(rect.position.x + 34, rect.position.y + 32),
		stat_str, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.45,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Price (right-aligned)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.65, rect.position.y + 32),
		PriceCatalog.format_price(price), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.3,
		UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
