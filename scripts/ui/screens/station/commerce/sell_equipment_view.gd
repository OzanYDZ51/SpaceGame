class_name SellEquipmentView
extends Control

# =============================================================================
# Sell Equipment View - Sell weapons/shields/engines/modules from inventory
# Same layout as EquipmentShopView: Tab bar + list + detail panel + sell button
# =============================================================================

var _commerce_manager: CommerceManager = null

var _tab_bar: UITabBar = null
var _item_list: UIScrollList = null
var _sell_btn: UIButton = null
var _current_tab: int = 0
var _available_items: Array[StringName] = []
var _selected_index: int = -1

const TAB_NAMES: Array[String] = ["ARMES", "BOUCLIERS", "MOTEURS", "MODULES"]
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

	_sell_btn = UIButton.new()
	_sell_btn.text = "VENDRE"
	_sell_btn.accent_color = UITheme.WARNING
	_sell_btn.visible = false
	_sell_btn.pressed.connect(_on_sell_pressed)
	add_child(_sell_btn)


func setup(mgr: CommerceManager) -> void:
	_commerce_manager = mgr


func refresh() -> void:
	_tab_bar.visible = true
	_item_list.visible = true
	_sell_btn.visible = true
	_tab_bar.current_tab = _current_tab
	_refresh_items()
	_layout()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_tab_bar.position = Vector2(0, 0)
	_tab_bar.size = Vector2(list_w, 28)
	_item_list.position = Vector2(0, 32)
	_item_list.size = Vector2(list_w, s.y - 32)
	_sell_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_btn.size = Vector2(DETAIL_W - 20, 34)


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_selected_index = -1
	_refresh_items()
	queue_redraw()


func _refresh_items() -> void:
	_available_items.clear()
	if _commerce_manager == null or _commerce_manager.player_inventory == null:
		_item_list.items = []
		return
	var inv := _commerce_manager.player_inventory
	match _current_tab:
		0: _available_items.assign(inv.get_all_weapons())
		1: _available_items.assign(inv.get_all_shields())
		2: _available_items.assign(inv.get_all_engines())
		3: _available_items.assign(inv.get_all_modules())
	var list_items: Array = []
	for item_name in _available_items:
		list_items.append(item_name)
	_item_list.items = list_items
	if _selected_index >= _available_items.size():
		_selected_index = -1
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	_do_sell()


func _on_sell_pressed() -> void:
	_do_sell()


func _do_sell() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _available_items.size(): return
	var item_name: StringName = _available_items[_selected_index]
	var success: bool = false
	match _current_tab:
		0: success = _commerce_manager.sell_weapon(item_name)
		1: success = _commerce_manager.sell_shield(item_name)
		2: success = _commerce_manager.sell_engine(item_name)
		3: success = _commerce_manager.sell_module(item_name)
	if success:
		if GameManager._notif:
			var sell_price: int = 0
			match _current_tab:
				0:
					var w := WeaponRegistry.get_weapon(item_name)
					if w: sell_price = PriceCatalog.get_sell_price(w.price)
				1:
					var sh := ShieldRegistry.get_shield(item_name)
					if sh: sell_price = PriceCatalog.get_sell_price(sh.price)
				2:
					var en := EngineRegistry.get_engine(item_name)
					if en: sell_price = PriceCatalog.get_sell_price(en.price)
				3:
					var mo := ModuleRegistry.get_module(item_name)
					if mo: sell_price = PriceCatalog.get_sell_price(mo.price)
			GameManager._notif.commerce.sold(String(item_name), sell_price)
		_refresh_items()
	queue_redraw()


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

	if _selected_index < 0 or _selected_index >= _available_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un objet",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item_name: StringName = _available_items[_selected_index]
	var y: float = 10.0
	var sell_price: int = 0

	match _current_tab:
		0:
			var w := WeaponRegistry.get_weapon(item_name)
			if w:
				sell_price = PriceCatalog.get_sell_price(w.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				var type_str: String = ["Laser", "Plasma", "Missile", "Railgun", "Mine", "Tourelle", "Laser Minier"][w.weapon_type]
				y = _draw_detail_rows(font, detail_x, y, [
					["Type", type_str],
					["Taille", ["S", "M", "L"][w.slot_size]],
					["DPS", "%.0f" % (w.damage_per_hit * w.fire_rate)],
				])
		1:
			var sh := ShieldRegistry.get_shield(item_name)
			if sh:
				sell_price = PriceCatalog.get_sell_price(sh.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				y = _draw_detail_rows(font, detail_x, y, [
					["Taille", ["S", "M", "L"][sh.slot_size]],
					["PV/face", "%.0f" % sh.shield_hp_per_facing],
					["Regen", "%.0f/s" % sh.regen_rate],
				])
		2:
			var e := EngineRegistry.get_engine(item_name)
			if e:
				sell_price = PriceCatalog.get_sell_price(e.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				y = _draw_detail_rows(font, detail_x, y, [
					["Taille", ["S", "M", "L"][e.slot_size]],
					["Accel", "x%.2f" % e.accel_mult],
					["Vitesse", "x%.2f" % e.speed_mult],
				])
		3:
			var m := ModuleRegistry.get_module(item_name)
			if m:
				sell_price = PriceCatalog.get_sell_price(m.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				var rows: Array = [["Taille", ["S", "M", "L"][m.slot_size]]]
				for bonus in m.get_bonuses_text():
					rows.append(["Bonus", bonus])
				y = _draw_detail_rows(font, detail_x, y, rows)

	# Sell price box
	if sell_price > 0:
		y = _draw_sell_price_box(font, detail_x, y, sell_price)

	# Quantity in inventory
	if _commerce_manager and _commerce_manager.player_inventory:
		var count: int = 0
		match _current_tab:
			0: count = _commerce_manager.player_inventory.get_weapon_count(item_name)
			1: count = _commerce_manager.player_inventory.get_shield_count(item_name)
			2: count = _commerce_manager.player_inventory.get_engine_count(item_name)
			3: count = _commerce_manager.player_inventory.get_module_count(item_name)
		if count > 0:
			draw_string(font, Vector2(detail_x + 10, y + 14),
				"Quantite: %d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _draw_detail_header(font: Font, x: float, y: float, item_name: StringName) -> float:
	draw_string(font, Vector2(x + 10, y + 14), String(item_name).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	return y + 24.0


func _draw_detail_rows(font: Font, x: float, y: float, rows: Array) -> float:
	for row in rows:
		draw_string(font, Vector2(x + 10, y + 12), row[0],
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(x + 95, y + 12), row[1],
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
		y += 18.0
	return y + 6.0


func _draw_sell_price_box(_font: Font, x: float, y: float, price: int) -> float:
	y += 4.0
	draw_rect(Rect2(x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(UITheme.get_font(), Vector2(x + 10, y + 19),
		"+" + PriceCatalog.format_price(price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)
	return y + 36.0


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _available_items.size(): return
	var item_name: StringName = _available_items[idx]
	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

	var name_str := String(item_name)
	var size_str := ""
	var sell_price: int = 0
	var count: int = 0
	var inv := _commerce_manager.player_inventory if _commerce_manager else null

	match _current_tab:
		0:
			var w := WeaponRegistry.get_weapon(item_name)
			if w:
				size_str = ["S", "M", "L"][w.slot_size]
				sell_price = PriceCatalog.get_sell_price(w.price)
			if inv: count = inv.get_weapon_count(item_name)
		1:
			var sh := ShieldRegistry.get_shield(item_name)
			if sh:
				size_str = ["S", "M", "L"][sh.slot_size]
				sell_price = PriceCatalog.get_sell_price(sh.price)
			if inv: count = inv.get_shield_count(item_name)
		2:
			var en := EngineRegistry.get_engine(item_name)
			if en:
				size_str = ["S", "M", "L"][en.slot_size]
				sell_price = PriceCatalog.get_sell_price(en.price)
			if inv: count = inv.get_engine_count(item_name)
		3:
			var mo := ModuleRegistry.get_module(item_name)
			if mo:
				size_str = ["S", "M", "L"][mo.slot_size]
				sell_price = PriceCatalog.get_sell_price(mo.price)
			if inv: count = inv.get_module_count(item_name)

	# Size badge
	var badge_col: Color = UITheme.PRIMARY if size_str == "S" else (UITheme.WARNING if size_str == "M" else Color(1.0, 0.5, 0.2))
	ci.draw_rect(Rect2(rect.position.x + 4, rect.position.y + 4, 24, 16), Color(badge_col.r, badge_col.g, badge_col.b, 0.2))
	ci.draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 16),
		size_str, HORIZONTAL_ALIGNMENT_CENTER, 24, UITheme.FONT_SIZE_TINY, badge_col)

	# Name + count
	var label := name_str
	if count > 1:
		label += " x%d" % count
	ci.draw_string(font, Vector2(rect.position.x + 34, rect.position.y + 16),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_LABEL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Sell price (right-aligned)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.6, rect.position.y + 16),
		"+" + PriceCatalog.format_price(sell_price), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.35,
		UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
