class_name SellEquipmentView
extends UIComponent

# =============================================================================
# Sell Equipment View — Card grid of owned items (3 columns) + detail panel.
# Tab bar: ARMES / BOUCLIERS / MOTEURS / MODULES.
# Each card: size badge, type icon, name, quantity if >1, sell price (50%).
# =============================================================================

var _commerce_manager = null

var _tab_bar: UITabBar = null
var _sell_btn: UIButton = null
var _current_tab: int = 0
var _available_items: Array[StringName] = []
var _selected_index: int = -1

# Card grid state
var _card_rects: Array[Rect2] = []
var _hovered_idx: int = -1
var _scroll_offset: float = 0.0
var _total_content_h: float = 0.0
var _grid_area: Rect2 = Rect2()

static var TAB_NAMES: Array[String]:
	get: return [Locale.t("equip.sell_weapons"), Locale.t("equip.shields"), Locale.t("equip.engines"), Locale.t("equip.modules")]
const DETAIL_W: float = 240.0
const CARD_W: float = 140.0
const CARD_H: float = 110.0
const CARD_GAP: float = 8.0
const GRID_TOP: float = 34.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = TAB_NAMES
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_tab_bar.visible = false
	add_child(_tab_bar)

	_sell_btn = UIButton.new()
	_sell_btn.text = Locale.t("hud.sell")
	_sell_btn.accent_color = UITheme.WARNING
	_sell_btn.visible = false
	_sell_btn.pressed.connect(_on_sell_pressed)
	add_child(_sell_btn)


func setup(mgr) -> void:
	_commerce_manager = mgr


func refresh() -> void:
	_tab_bar.visible = true
	_sell_btn.visible = true
	_tab_bar.current_tab = _current_tab
	_refresh_items()
	_layout()


func _layout() -> void:
	var s = size
	var list_w: float = s.x - DETAIL_W - 10.0
	_tab_bar.position = Vector2(0, 0)
	_tab_bar.size = Vector2(list_w, 28)
	_sell_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_btn.size = Vector2(DETAIL_W - 20, 34)
	_grid_area = Rect2(0, GRID_TOP, list_w, s.y - GRID_TOP)
	_compute_card_grid()


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_selected_index = -1
	_scroll_offset = 0.0
	_refresh_items()
	queue_redraw()


func _refresh_items() -> void:
	_available_items.clear()
	if _commerce_manager == null or _commerce_manager.player_inventory == null:
		_compute_card_grid()
		queue_redraw()
		return
	var inv = _commerce_manager.player_inventory
	match _current_tab:
		0: _available_items.assign(inv.get_all_weapons())
		1: _available_items.assign(inv.get_all_shields())
		2: _available_items.assign(inv.get_all_engines())
		3: _available_items.assign(inv.get_all_modules())
	if _selected_index >= _available_items.size():
		_selected_index = -1
	_compute_card_grid()
	queue_redraw()


func _compute_card_grid() -> void:
	_card_rects.clear()
	if _available_items.is_empty():
		_total_content_h = 0.0
		return
	var area_w: float = _grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _available_items.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _grid_area.position.y + row * (CARD_H + CARD_GAP) - _scroll_offset
		_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	var cols2: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	@warning_ignore("integer_division")
	var total_rows: int = (_available_items.size() + cols2 - 1) / cols2
	_total_content_h = total_rows * (CARD_H + CARD_GAP)


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
			var sell_price: int = _get_sell_price(item_name)
			GameManager._notif.commerce.sold(String(item_name), sell_price)
		_refresh_items()
	queue_redraw()


func _get_sell_price(item_name: StringName) -> int:
	match _current_tab:
		0:
			var w = WeaponRegistry.get_weapon(item_name)
			return PriceCatalog.get_sell_price(w.price) if w else 0
		1:
			var sh = ShieldRegistry.get_shield(item_name)
			return PriceCatalog.get_sell_price(sh.price) if sh else 0
		2:
			var en = EngineRegistry.get_engine(item_name)
			return PriceCatalog.get_sell_price(en.price) if en else 0
		3:
			var mo = ModuleRegistry.get_module(item_name)
			return PriceCatalog.get_sell_price(mo.price) if mo else 0
	return 0


func _get_base_price(item_name: StringName) -> int:
	match _current_tab:
		0:
			var w = WeaponRegistry.get_weapon(item_name)
			return w.price if w else 0
		1:
			var sh = ShieldRegistry.get_shield(item_name)
			return sh.price if sh else 0
		2:
			var en = EngineRegistry.get_engine(item_name)
			return en.price if en else 0
		3:
			var mo = ModuleRegistry.get_module(item_name)
			return mo.price if mo else 0
	return 0


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# =========================================================================
# INPUT
# =========================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old: int = _hovered_idx
		_hovered_idx = -1
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position) and _grid_area.has_point(event.position):
				_hovered_idx = i
				break
		if _hovered_idx != old:
			queue_redraw()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in _card_rects.size():
				if _card_rects[i].has_point(event.position) and _grid_area.has_point(event.position):
					if _selected_index == i:
						_do_sell()
					else:
						_selected_index = i
					queue_redraw()
					accept_event()
					return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - 40.0)
			_compute_card_grid()
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var max_scroll: float = maxf(0.0, _total_content_h - _grid_area.size.y)
			_scroll_offset = minf(max_scroll, _scroll_offset + 40.0)
			_compute_card_grid()
			queue_redraw()
			accept_event()


# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	var s = size
	var font: Font = UITheme.get_font()
	var detail_x: float = s.x - DETAIL_W

	# Grid area — draw cards
	_draw_card_grid(font)

	# Detail panel background
	draw_rect(Rect2(detail_x, 0, DETAIL_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(detail_x, 0), Vector2(detail_x, s.y), UITheme.BORDER, 1.0)

	# Draw selected item details
	if _selected_index < 0 or _selected_index >= _available_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), Locale.t("ui.select_item"),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item_name: StringName = _available_items[_selected_index]
	var y: float = 10.0
	var sell_price: int = 0

	match _current_tab:
		0:
			var w = WeaponRegistry.get_weapon(item_name)
			if w:
				sell_price = PriceCatalog.get_sell_price(w.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				var type_str: String = [Locale.t("weapon.laser"), Locale.t("weapon.plasma"), Locale.t("weapon.missile"), Locale.t("weapon.railgun"), Locale.t("weapon.mine"), Locale.t("weapon.turret"), Locale.t("weapon.mining_laser")][w.weapon_type]
				y = _draw_detail_rows(font, detail_x, y, [
					[Locale.t("stat.type"), type_str],
					[Locale.t("stat.size"), ["S", "M", "L"][w.slot_size]],
					[Locale.t("stat.damage"), "%.0f/tir" % w.damage_per_hit],
					[Locale.t("stat.fire_rate"), "%.1f/s" % w.fire_rate],
					[Locale.t("stat.dps"), "%.0f" % (w.damage_per_hit * w.fire_rate)],
					[Locale.t("stat.energy_cost"), "%.0f/tir" % w.energy_cost_per_shot],
					[Locale.t("stat.range"), "%.0fm" % (w.projectile_speed * w.projectile_lifetime)],
				])
		1:
			var sh = ShieldRegistry.get_shield(item_name)
			if sh:
				sell_price = PriceCatalog.get_sell_price(sh.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				y = _draw_detail_rows(font, detail_x, y, [
					[Locale.t("stat.size"), ["S", "M", "L"][sh.slot_size]],
					[Locale.t("stat.hp_short") + "/face", "%.0f" % sh.shield_hp_per_facing],
					[Locale.t("stat.hp_short") + " total", "%.0f" % (sh.shield_hp_per_facing * 4)],
					[Locale.t("stat.regen"), "%.0f/s" % sh.regen_rate],
					[Locale.t("stat.delay"), "%.1fs" % sh.regen_delay],
					[Locale.t("stat.perforation"), "%.0f%%" % (sh.bleedthrough * 100)],
				])
		2:
			var e = EngineRegistry.get_engine(item_name)
			if e:
				sell_price = PriceCatalog.get_sell_price(e.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				y = _draw_detail_rows(font, detail_x, y, [
					[Locale.t("stat.size"), ["S", "M", "L"][e.slot_size]],
					[Locale.t("stat.acceleration"), "x%.2f" % e.accel_mult],
					[Locale.t("stat.speed"), "x%.2f" % e.speed_mult],
					[Locale.t("stat.rotation"), "x%.2f" % e.rotation_mult],
					[Locale.t("stat.cruise"), "x%.2f" % e.cruise_mult],
					[Locale.t("stat.boost_drain_short"), "x%.2f" % e.boost_drain_mult],
				])
		3:
			var m = ModuleRegistry.get_module(item_name)
			if m:
				sell_price = PriceCatalog.get_sell_price(m.price)
				y = _draw_detail_header(font, detail_x, y, item_name)
				var rows: Array = [[Locale.t("stat.size"), ["S", "M", "L"][m.slot_size]]]
				for bonus in m.get_bonuses_text():
					rows.append(["Bonus", bonus])
				y = _draw_detail_rows(font, detail_x, y, rows)

	# Sell price box (WARNING colored)
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
				Locale.t("shop.quantity") + ": %d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _draw_card_grid(font: Font) -> void:
	for i in _card_rects.size():
		var r: Rect2 = _card_rects[i]
		# Clip: only draw if visible in grid area
		if r.end.y < _grid_area.position.y or r.position.y > _grid_area.end.y:
			continue
		_draw_equip_card(font, r, i)


func _draw_equip_card(font: Font, rect: Rect2, idx: int) -> void:
	if idx >= _available_items.size(): return
	var item_name: StringName = _available_items[idx]
	var is_sel: bool = idx == _selected_index
	var is_hov: bool = idx == _hovered_idx

	# Get item data
	var size_str: String = ""
	var stat_label: String = ""
	var stat_val: String = ""
	var stat_ratio: float = 0.0
	var sell_price: int = 0
	var stat_col: Color = UITheme.PRIMARY
	var count: int = 0
	var inv = _commerce_manager.player_inventory if _commerce_manager else null

	match _current_tab:
		0:
			var w = WeaponRegistry.get_weapon(item_name)
			if w:
				size_str = ["S", "M", "L"][w.slot_size]
				var dps: float = w.damage_per_hit * w.fire_rate
				stat_label = Locale.t("stat.dps")
				stat_val = "%.0f" % dps
				stat_ratio = clampf(dps / 500.0, 0.0, 1.0)
				sell_price = PriceCatalog.get_sell_price(w.price)
				stat_col = UITheme.DANGER
			if inv: count = inv.get_weapon_count(item_name)
		1:
			var sh = ShieldRegistry.get_shield(item_name)
			if sh:
				size_str = ["S", "M", "L"][sh.slot_size]
				stat_label = Locale.t("stat.hp_short")
				stat_val = "%.0f" % sh.shield_hp_per_facing
				stat_ratio = clampf(sh.shield_hp_per_facing / 1000.0, 0.0, 1.0)
				sell_price = PriceCatalog.get_sell_price(sh.price)
				stat_col = UITheme.SHIELD
			if inv: count = inv.get_shield_count(item_name)
		2:
			var en = EngineRegistry.get_engine(item_name)
			if en:
				size_str = ["S", "M", "L"][en.slot_size]
				stat_label = Locale.t("stat.speed_short")
				stat_val = "x%.1f" % en.speed_mult
				stat_ratio = clampf(en.speed_mult / 3.0, 0.0, 1.0)
				sell_price = PriceCatalog.get_sell_price(en.price)
				stat_col = UITheme.BOOST
			if inv: count = inv.get_engine_count(item_name)
		3:
			var mo = ModuleRegistry.get_module(item_name)
			if mo:
				size_str = ["S", "M", "L"][mo.slot_size]
				var bonuses = mo.get_bonuses_text()
				stat_label = ""
				stat_val = bonuses[0] if bonuses.size() > 0 else ""
				stat_ratio = 0.5
				sell_price = PriceCatalog.get_sell_price(mo.price)
				stat_col = UITheme.ACCENT
			if inv: count = inv.get_module_count(item_name)

	# Card background
	var bg: Color
	if is_sel:
		bg = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15)
	elif is_hov:
		bg = Color(0.025, 0.06, 0.12, 0.9)
	else:
		bg = Color(0.015, 0.04, 0.08, 0.8)
	draw_rect(rect, bg)

	# Border
	var bcol: Color
	if is_sel:
		bcol = UITheme.PRIMARY
	elif is_hov:
		bcol = UITheme.BORDER_HOVER
	else:
		bcol = UITheme.BORDER
	draw_rect(rect, bcol, false, 1.0)

	# Top glow if selected
	if is_sel:
		draw_line(Vector2(rect.position.x + 1, rect.position.y),
			Vector2(rect.end.x - 1, rect.position.y),
			Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3), 2.0)

	# Size badge (top-left)
	draw_size_badge(Vector2(rect.position.x + 4, rect.position.y + 4), size_str)

	# Quantity badge (top-right) if >1
	if count > 1:
		var qty_str: String = "x%d" % count
		draw_string(font, Vector2(rect.end.x - 34, rect.position.y + 14),
			qty_str, HORIZONTAL_ALIGNMENT_RIGHT, 30,
			UITheme.FONT_SIZE_TINY, UITheme.WARNING)

	# Type icon (top-center)
	var ic: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 28.0)
	var icol: Color = stat_col if is_sel else Color(stat_col.r, stat_col.g, stat_col.b, 0.6)
	_draw_type_icon(ic, _current_tab, icol)

	# Name (centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 52),
		String(item_name), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Stat mini bar
	if stat_label != "" or stat_val != "":
		draw_stat_mini_bar(
			Rect2(rect.position.x + 6, rect.position.y + 66, rect.size.x - 12, 14),
			stat_ratio, stat_col, stat_label, stat_val)

	# Sell price (bottom)
	var pcol: Color = PlayerEconomy.CREDITS_COLOR
	draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 8),
		"+" + PriceCatalog.format_price(sell_price), HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8, UITheme.FONT_SIZE_TINY, pcol)


func _draw_type_icon(c: Vector2, tab: int, col: Color) -> void:
	var r: float = 10.0
	match tab:
		0:  # Weapon crosshair
			draw_arc(c, r * 0.6, 0, TAU, 12, col, 1.0)
			draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.3), col, 1.0)
			draw_line(c + Vector2(0, r), c + Vector2(0, r * 0.3), col, 1.0)
			draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.3, 0), col, 1.0)
			draw_line(c + Vector2(r, 0), c + Vector2(r * 0.3, 0), col, 1.0)
		1:  # Shield hexagon
			var pts: PackedVector2Array = []
			for k in 7:
				var a: float = TAU * float(k) / 6.0 - PI * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, col, 1.0)
		2:  # Engine rocket
			draw_line(c + Vector2(0, -r), c + Vector2(-r * 0.5, r * 0.7), col, 1.0)
			draw_line(c + Vector2(0, -r), c + Vector2(r * 0.5, r * 0.7), col, 1.0)
			draw_line(c + Vector2(-r * 0.5, r * 0.7), c + Vector2(0, r * 0.3), col, 1.0)
			draw_line(c + Vector2(r * 0.5, r * 0.7), c + Vector2(0, r * 0.3), col, 1.0)
			draw_line(c + Vector2(0, r * 0.7), c + Vector2(0, r), col, 1.0)
		3:  # Module chip
			draw_rect(Rect2(c.x - r * 0.5, c.y - r * 0.5, r, r), col, false, 1.0)
			draw_line(c + Vector2(-r * 0.5, -r * 0.2), c + Vector2(-r * 0.9, -r * 0.2), col, 1.0)
			draw_line(c + Vector2(-r * 0.5, r * 0.2), c + Vector2(-r * 0.9, r * 0.2), col, 1.0)
			draw_line(c + Vector2(r * 0.5, -r * 0.2), c + Vector2(r * 0.9, -r * 0.2), col, 1.0)
			draw_line(c + Vector2(r * 0.5, r * 0.2), c + Vector2(r * 0.9, r * 0.2), col, 1.0)


# =========================================================================
# DETAIL PANEL
# =========================================================================

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
