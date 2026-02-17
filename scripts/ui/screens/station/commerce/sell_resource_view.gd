class_name SellResourceView
extends UIComponent

# =============================================================================
# Sell Resource View — Card grid of ores (4 columns) + detail panel.
# Ship filter dropdown: TOUS / active ship / other docked ships.
# Each card: ore crystal icon, name, quantity, unit price, rarity stars.
# =============================================================================

var _commerce_manager = null
var _station_id: String = ""

var _ship_dropdown: UIDropdown = null
var _sell_1_btn: UIButton = null
var _sell_10_btn: UIButton = null
var _sell_all_btn: UIButton = null
var _resource_ids: Array[StringName] = []
var _resource_ship: Array[FleetShip] = []  # which ship owns each entry
var _selected_index: int = -1
var _docked_ships: Array[FleetShip] = []
var _filter_ship_index: int = 0  # 0 = TOUS

# Card grid state
var _card_rects: Array[Rect2] = []
var _hovered_idx: int = -1
var _scroll_offset: float = 0.0
var _total_content_h: float = 0.0
var _grid_area: Rect2 = Rect2()

const DETAIL_W: float = 240.0
const CARD_W: float = 110.0
const CARD_H: float = 100.0
const CARD_GAP: float = 8.0
const GRID_TOP: float = 38.0
const DROPDOWN_H: float = 32.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)

	_ship_dropdown = UIDropdown.new()
	_ship_dropdown.visible = false
	_ship_dropdown.option_selected.connect(_on_ship_filter_changed)
	add_child(_ship_dropdown)

	_sell_1_btn = UIButton.new()
	_sell_1_btn.text = Locale.t("btn.sell_x1")
	_sell_1_btn.accent_color = UITheme.WARNING
	_sell_1_btn.visible = false
	_sell_1_btn.pressed.connect(_on_sell_1)
	add_child(_sell_1_btn)

	_sell_10_btn = UIButton.new()
	_sell_10_btn.text = Locale.t("btn.sell_x10")
	_sell_10_btn.accent_color = UITheme.WARNING
	_sell_10_btn.visible = false
	_sell_10_btn.pressed.connect(_on_sell_10)
	add_child(_sell_10_btn)

	_sell_all_btn = UIButton.new()
	_sell_all_btn.text = Locale.t("btn.sell_all")
	_sell_all_btn.accent_color = UITheme.WARNING
	_sell_all_btn.visible = false
	_sell_all_btn.pressed.connect(_on_sell_all)
	add_child(_sell_all_btn)


func setup(mgr, station_id: String = "") -> void:
	_commerce_manager = mgr
	_station_id = station_id


func refresh() -> void:
	_ship_dropdown.visible = true
	_sell_1_btn.visible = true
	_sell_10_btn.visible = true
	_sell_all_btn.visible = true
	_rebuild_docked_ships()
	_refresh_items()
	_layout()


func _rebuild_docked_ships() -> void:
	_docked_ships.clear()
	if _commerce_manager == null or _commerce_manager.player_data == null:
		return
	var pd = _commerce_manager.player_data
	if pd.fleet == null:
		return
	var fleet = pd.fleet
	var active = fleet.get_active()
	if active:
		_docked_ships.append(active)
	if _station_id != "":
		var docked_indices = fleet.get_ships_at_station(_station_id)
		for idx in docked_indices:
			var fs = fleet.ships[idx]
			if fs != active:
				_docked_ships.append(fs)
	var opts: Array[String] = []
	opts.append("TOUS")
	for fs in _docked_ships:
		var suffix: String = " [ACTIF]" if fs == active else ""
		opts.append(fs.custom_name + suffix)
	_ship_dropdown.options = opts
	_ship_dropdown.selected_index = 0
	_filter_ship_index = 0


func _on_ship_filter_changed(_idx: int) -> void:
	_filter_ship_index = _ship_dropdown.selected_index
	_selected_index = -1
	_scroll_offset = 0.0
	_refresh_items()


func _layout() -> void:
	var s = size
	var list_w: float = s.x - DETAIL_W - 10.0
	_ship_dropdown.position = Vector2(0, 0)
	if _ship_dropdown._expanded:
		_ship_dropdown.size.x = list_w
	else:
		_ship_dropdown.size = Vector2(list_w, DROPDOWN_H)
	_grid_area = Rect2(0, GRID_TOP, list_w, s.y - GRID_TOP)
	_compute_card_grid()
	var btn_w: float = DETAIL_W - 20
	_sell_1_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 122)
	_sell_1_btn.size = Vector2(btn_w, 34)
	_sell_10_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 82)
	_sell_10_btn.size = Vector2(btn_w, 34)
	_sell_all_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_all_btn.size = Vector2(btn_w, 34)


func _refresh_items() -> void:
	_resource_ids.clear()
	_resource_ship.clear()
	if _commerce_manager == null:
		_compute_card_grid()
		queue_redraw()
		return

	var ships_to_show: Array[FleetShip] = []
	if _filter_ship_index == 0:
		ships_to_show = _docked_ships
	elif _filter_ship_index - 1 < _docked_ships.size():
		ships_to_show = [_docked_ships[_filter_ship_index - 1]]

	for fs in ships_to_show:
		for res_id in MiningRegistry.get_all_ids():
			var qty: int = fs.get_resource(res_id)
			if qty > 0:
				_resource_ids.append(res_id)
				_resource_ship.append(fs)

	if _selected_index >= _resource_ids.size():
		_selected_index = -1
	_compute_card_grid()
	queue_redraw()


func _compute_card_grid() -> void:
	_card_rects.clear()
	if _resource_ids.is_empty():
		_total_content_h = 0.0
		return
	var area_w: float = _grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _resource_ids.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _grid_area.position.y + row * (CARD_H + CARD_GAP) - _scroll_offset
		_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	@warning_ignore("integer_division")
	var total_rows: int = (_resource_ids.size() + maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP))) - 1) / maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	_total_content_h = total_rows * (CARD_H + CARD_GAP)


# =========================================================================
# SELL LOGIC
# =========================================================================

func _on_sell_1() -> void:
	_do_sell(1)


func _on_sell_10() -> void:
	_do_sell(10)


func _on_sell_all() -> void:
	if _selected_index < 0 or _selected_index >= _resource_ids.size(): return
	if _commerce_manager == null: return
	var res_id: StringName = _resource_ids[_selected_index]
	var ship = _resource_ship[_selected_index]
	var qty: int = ship.get_resource(res_id)
	if qty > 0:
		_do_sell(qty)


func _do_sell(qty: int) -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _resource_ids.size(): return
	var res_id: StringName = _resource_ids[_selected_index]
	var ship = _resource_ship[_selected_index]
	var available: int = ship.get_resource(res_id)
	qty = mini(qty, available)
	if qty <= 0: return
	if _commerce_manager.sell_resource_from_ship(res_id, qty, ship):
		if GameManager._notif:
			var total = PriceCatalog.get_resource_price(res_id) * qty
			var res_data = MiningRegistry.get_resource(res_id)
			var rname = res_data.display_name if res_data else String(res_id)
			GameManager._notif.commerce.sold_qty(rname, qty, total)
		_refresh_items()
	queue_redraw()


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
						# Double-click-like: sell x1 on re-click
						pass
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

	# Grid area — draw ore cards
	_draw_card_grid(font)

	# Detail panel background
	draw_rect(Rect2(detail_x, 0, DETAIL_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(detail_x, 0), Vector2(detail_x, s.y), UITheme.BORDER, 1.0)

	# Detail panel content
	if _resource_ids.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), Locale.t("shop.no_ores"),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _resource_ids.size():
		draw_string(font, Vector2(detail_x + 10, 30), Locale.t("ui.select_ore"),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	_draw_detail_panel(font, detail_x)


func _draw_card_grid(font: Font) -> void:
	for i in _card_rects.size():
		var r: Rect2 = _card_rects[i]
		# Clip: only draw if visible in grid area
		if r.end.y < _grid_area.position.y or r.position.y > _grid_area.end.y:
			continue
		_draw_ore_card(font, r, i)


func _draw_ore_card(font: Font, rect: Rect2, idx: int) -> void:
	if idx >= _resource_ids.size(): return
	var res_id: StringName = _resource_ids[idx]
	var res_data = MiningRegistry.get_resource(res_id)
	if res_data == null: return
	var ship = _resource_ship[idx]
	var qty: int = ship.get_resource(res_id)
	var unit_price: int = res_data.base_value
	var is_sel: bool = idx == _selected_index
	var is_hov: bool = idx == _hovered_idx
	var ore_col: Color = res_data.icon_color

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

	# Ore crystal icon (top center)
	var icon_center: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 20.0)
	var icol: Color = ore_col if is_sel else Color(ore_col.r, ore_col.g, ore_col.b, 0.7)
	draw_ore_crystal(icon_center, 12.0, icol)

	# Ore name (centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 42),
		res_data.display_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Quantity (centered, below name)
	var qty_col: Color = UITheme.LABEL_VALUE if is_sel else UITheme.TEXT_DIM
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 56),
		"x%d" % qty, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_TINY, qty_col)

	# Rarity stars (centered)
	var star_y: float = rect.position.y + 68.0
	var star_center: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, star_y)
	var star_col: Color = ore_col if is_sel else Color(ore_col.r, ore_col.g, ore_col.b, 0.5)
	draw_rarity_badge(star_center, res_data.rarity + 1, star_col)

	# Unit price (bottom, centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 8),
		PriceCatalog.format_price(unit_price) + "/u", HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8, UITheme.FONT_SIZE_TINY, PlayerEconomy.CREDITS_COLOR)

	# Ship name prefix overlay (top-left, tiny) when TOUS filter + multiple ships
	if _filter_ship_index == 0 and _docked_ships.size() > 1:
		var short_name: String = ship.custom_name.substr(0, 6)
		draw_string(font, Vector2(rect.position.x + 3, rect.position.y + 9),
			short_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6,
			UITheme.FONT_SIZE_TINY, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.5))


func _draw_detail_panel(font: Font, detail_x: float) -> void:
	var res_id: StringName = _resource_ids[_selected_index]
	var res_data = MiningRegistry.get_resource(res_id)
	if res_data == null: return
	var ship = _resource_ship[_selected_index]
	var qty: int = ship.get_resource(res_id)
	var unit_price: int = res_data.base_value

	var y: float = 10.0

	# Ship owner label (when "TOUS" filter)
	if _filter_ship_index == 0 and _docked_ships.size() > 1:
		draw_string(font, Vector2(detail_x + 10, y + 12), ship.custom_name,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
		y += 16.0

	# Name with icon_color
	draw_string(font, Vector2(detail_x + 10, y + 14), res_data.display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, res_data.icon_color)
	y += 24.0

	# Description
	if res_data.description != "":
		draw_string(font, Vector2(detail_x + 10, y + 10), res_data.description,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
		y += 18.0

	# Rarity
	var rarity_str: String = [Locale.t("shop.rarity_common"), Locale.t("shop.rarity_uncommon"), Locale.t("shop.rarity_rare"), Locale.t("shop.rarity_very_rare"), Locale.t("shop.rarity_legendary")][res_data.rarity]
	draw_string(font, Vector2(detail_x + 10, y + 12), Locale.t("shop.rarity"),
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), rarity_str,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Quantity
	draw_string(font, Vector2(detail_x + 10, y + 12), Locale.t("shop.in_stock"),
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), str(qty),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Unit price
	draw_string(font, Vector2(detail_x + 10, y + 12), Locale.t("shop.price_per_unit"),
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(unit_price),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
	y += 24.0

	# Total value box
	var total_price: int = unit_price * qty
	y += 4.0
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(font, Vector2(detail_x + 10, y + 19),
		"TOTAL: +" + PriceCatalog.format_price(total_price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)
