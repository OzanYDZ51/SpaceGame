class_name SellCargoView
extends UIComponent

# =============================================================================
# Sell Cargo View — Card grid of cargo items (3 columns) + detail panel.
# Ship filter dropdown at top. Each card: color badge, name, quantity, price/unit.
# Detail panel: item details + VENDRE x1 and VENDRE TOUT buttons.
# =============================================================================

var _commerce_manager = null
var _station_id: String = ""

var _ship_dropdown: UIDropdown = null
var _sell_one_btn: UIButton = null
var _sell_all_btn: UIButton = null
var _cargo_items: Array[Dictionary] = []  # flattened items for display
var _cargo_item_ship: Array[FleetShip] = []  # which ship owns each item
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
const CARD_W: float = 140.0
const CARD_H: float = 95.0
const CARD_GAP: float = 8.0
const DROPDOWN_H: float = 32.0
const GRID_TOP: float = 38.0  # dropdown height + gap


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)

	_ship_dropdown = UIDropdown.new()
	_ship_dropdown.visible = false
	_ship_dropdown.option_selected.connect(_on_ship_filter_changed)
	add_child(_ship_dropdown)

	_sell_one_btn = UIButton.new()
	_sell_one_btn.text = Locale.t("btn.sell_x1")
	_sell_one_btn.accent_color = UITheme.WARNING
	_sell_one_btn.visible = false
	_sell_one_btn.pressed.connect(_on_sell_one)
	add_child(_sell_one_btn)

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
	_sell_one_btn.visible = true
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
	# Always include active ship first
	var active = fleet.get_active()
	if active:
		_docked_ships.append(active)
	# Add other ships docked at this station
	if _station_id != "":
		var docked_indices = fleet.get_ships_at_station(_station_id)
		for idx in docked_indices:
			var fs = fleet.ships[idx]
			if fs != active:
				_docked_ships.append(fs)
	# Build dropdown options
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
	_sell_one_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 82)
	_sell_one_btn.size = Vector2(DETAIL_W - 20, 34)
	_sell_all_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_all_btn.size = Vector2(DETAIL_W - 20, 34)
	_grid_area = Rect2(0, GRID_TOP, list_w, s.y - GRID_TOP)
	_compute_card_grid()


func _refresh_items() -> void:
	_cargo_items.clear()
	_cargo_item_ship.clear()
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
		if fs.cargo == null:
			continue
		for item in fs.cargo.get_all():
			_cargo_items.append(item)
			_cargo_item_ship.append(fs)

	if _selected_index >= _cargo_items.size():
		_selected_index = -1
	_compute_card_grid()
	queue_redraw()


func _compute_card_grid() -> void:
	_card_rects.clear()
	if _cargo_items.is_empty():
		_total_content_h = 0.0
		return
	var area_w: float = _grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _cargo_items.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _grid_area.position.y + row * (CARD_H + CARD_GAP) - _scroll_offset
		_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	var cols2: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	@warning_ignore("integer_division")
	var total_rows: int = (_cargo_items.size() + cols2 - 1) / cols2
	_total_content_h = total_rows * (CARD_H + CARD_GAP)


func _on_sell_one() -> void:
	_sell_one()


func _on_sell_all() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var ship = _cargo_item_ship[_selected_index]
	var item_name: String = item.get("name", "")
	var qty: int = item.get("quantity", 1)
	if _commerce_manager.sell_cargo_from_ship(item_name, qty, ship):
		if GameManager._notif:
			var total = PriceCatalog.get_cargo_price(item_name) * qty
			GameManager._notif.commerce.sold_qty(item_name, qty, total)
		_refresh_items()
	queue_redraw()


func _sell_one() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var ship = _cargo_item_ship[_selected_index]
	var item_name: String = item.get("name", "")
	if _commerce_manager.sell_cargo_from_ship(item_name, 1, ship):
		if GameManager._notif:
			var unit_price = PriceCatalog.get_cargo_price(item_name)
			GameManager._notif.commerce.sold(item_name, unit_price)
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
						_sell_one()
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

	if _cargo_items.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), Locale.t("shop.cargo_empty"),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _cargo_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), Locale.t("ui.select_item"),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item: Dictionary = _cargo_items[_selected_index]
	var item_name: String = item.get("name", "")
	var item_type: String = item.get("type", "")
	var qty: int = item.get("quantity", 1)
	var unit_price = PriceCatalog.get_cargo_price(item_name)

	var y: float = 10.0

	# Ship owner label (when "TOUS" filter)
	if _filter_ship_index == 0 and _selected_index < _cargo_item_ship.size():
		var owner_ship = _cargo_item_ship[_selected_index]
		draw_string(font, Vector2(detail_x + 10, y + 12), owner_ship.custom_name,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
		y += 16.0

	# Name
	draw_string(font, Vector2(detail_x + 10, y + 14), item_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	# Type
	if item_type != "":
		draw_string(font, Vector2(detail_x + 10, y + 12), Locale.t("stat.type"),
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), item_type,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
		y += 18.0

	# Quantity
	draw_string(font, Vector2(detail_x + 10, y + 12), Locale.t("shop.quantity"),
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

	# Total sell price box (WARNING colored)
	var total_price = unit_price * qty
	y += 4.0
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(font, Vector2(detail_x + 10, y + 19),
		"TOTAL: +" + PriceCatalog.format_price(total_price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)


func _draw_card_grid(font: Font) -> void:
	for i in _card_rects.size():
		var r: Rect2 = _card_rects[i]
		# Clip: only draw if visible in grid area
		if r.end.y < _grid_area.position.y or r.position.y > _grid_area.end.y:
			continue
		_draw_cargo_card(font, r, i)


func _draw_cargo_card(font: Font, rect: Rect2, idx: int) -> void:
	if idx >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[idx]
	var is_sel: bool = idx == _selected_index
	var is_hov: bool = idx == _hovered_idx

	var item_name: String = item.get("name", "")
	var qty: int = item.get("quantity", 1)
	var icon_color_raw = item.get("icon_color", "")
	var icon_col: Color
	if icon_color_raw is Color:
		icon_col = icon_color_raw
	elif icon_color_raw is String and icon_color_raw != "":
		icon_col = Color.from_string(icon_color_raw, UITheme.TEXT_DIM)
	else:
		icon_col = UITheme.TEXT_DIM
	var unit_price = PriceCatalog.get_cargo_price(item_name)

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

	# Color badge (top-left)
	draw_rect(Rect2(rect.position.x + 6, rect.position.y + 6, 14, 14), icon_col)
	draw_rect(Rect2(rect.position.x + 6, rect.position.y + 6, 14, 14),
		Color(icon_col.r, icon_col.g, icon_col.b, 0.4), false, 1.0)

	# Ship name prefix (top-right, tiny) when TOUS filter and multiple ships
	if _filter_ship_index == 0 and _docked_ships.size() > 1 and idx < _cargo_item_ship.size():
		var ship_label: String = _cargo_item_ship[idx].custom_name.substr(0, 8)
		draw_string(font, Vector2(rect.end.x - 60, rect.position.y + 14),
			ship_label, HORIZONTAL_ALIGNMENT_RIGHT, 56,
			UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Name (centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 38),
		item_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Quantity (centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 56),
		"x%d" % qty, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_LABEL, UITheme.WARNING)

	# Price per unit (bottom, centered)
	draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 8),
		"+" + PriceCatalog.format_price(unit_price) + "/u", HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 8, UITheme.FONT_SIZE_TINY, PlayerEconomy.CREDITS_COLOR)
