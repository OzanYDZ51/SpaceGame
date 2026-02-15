class_name SellCargoView
extends Control

# =============================================================================
# Sell Cargo View - Sell loot cargo items (metal, electronics, weapon_part…)
# Ship filter dropdown: TOUS / active ship / other docked ships
# Left: UIScrollList of cargo items, Right: detail panel + sell buttons
# =============================================================================

var _commerce_manager: CommerceManager = null
var _station_id: String = ""

var _ship_dropdown: UIDropdown = null
var _item_list: UIScrollList = null
var _sell_one_btn: UIButton = null
var _sell_all_btn: UIButton = null
var _cargo_items: Array[Dictionary] = []  # flattened items for display
var _cargo_item_ship: Array[FleetShip] = []  # which ship owns each item
var _selected_index: int = -1
var _docked_ships: Array[FleetShip] = []
var _filter_ship_index: int = 0  # 0 = TOUS

const DETAIL_W := 240.0
const ROW_H := 44.0
const DROPDOWN_H := 32.0


func _ready() -> void:
	resized.connect(_layout)

	_ship_dropdown = UIDropdown.new()
	_ship_dropdown.visible = false
	_ship_dropdown.option_selected.connect(_on_ship_filter_changed)
	add_child(_ship_dropdown)

	_item_list = UIScrollList.new()
	_item_list.row_height = ROW_H
	_item_list.item_draw_callback = _draw_item_row
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_double_clicked.connect(_on_item_double_clicked)
	_item_list.visible = false
	add_child(_item_list)

	_sell_one_btn = UIButton.new()
	_sell_one_btn.text = "VENDRE x1"
	_sell_one_btn.accent_color = UITheme.WARNING
	_sell_one_btn.visible = false
	_sell_one_btn.pressed.connect(_on_sell_one)
	add_child(_sell_one_btn)

	_sell_all_btn = UIButton.new()
	_sell_all_btn.text = "VENDRE TOUT"
	_sell_all_btn.accent_color = UITheme.WARNING
	_sell_all_btn.visible = false
	_sell_all_btn.pressed.connect(_on_sell_all)
	add_child(_sell_all_btn)


func setup(mgr: CommerceManager, station_id: String = "") -> void:
	_commerce_manager = mgr
	_station_id = station_id


func refresh() -> void:
	_ship_dropdown.visible = true
	_item_list.visible = true
	_sell_one_btn.visible = true
	_sell_all_btn.visible = true
	_rebuild_docked_ships()
	_refresh_items()
	_layout()


func _rebuild_docked_ships() -> void:
	_docked_ships.clear()
	if _commerce_manager == null or _commerce_manager.player_data == null:
		return
	var pd := _commerce_manager.player_data
	if pd.fleet == null:
		return
	var fleet := pd.fleet
	# Always include active ship first
	var active := fleet.get_active()
	if active:
		_docked_ships.append(active)
	# Add other ships docked at this station
	if _station_id != "":
		var docked_indices := fleet.get_ships_at_station(_station_id)
		for idx in docked_indices:
			var fs := fleet.ships[idx]
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
	_refresh_items()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_ship_dropdown.position = Vector2(0, 0)
	if _ship_dropdown._expanded:
		_ship_dropdown.size.x = list_w
	else:
		_ship_dropdown.size = Vector2(list_w, DROPDOWN_H)
	var list_top: float = DROPDOWN_H + 4.0
	_item_list.position = Vector2(0, list_top)
	_item_list.size = Vector2(list_w, s.y - list_top)
	_sell_one_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 82)
	_sell_one_btn.size = Vector2(DETAIL_W - 20, 34)
	_sell_all_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_all_btn.size = Vector2(DETAIL_W - 20, 34)


func _refresh_items() -> void:
	_cargo_items.clear()
	_cargo_item_ship.clear()
	if _commerce_manager == null:
		_item_list.items = []
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

	var list_items: Array = []
	for item in _cargo_items:
		list_items.append(item.get("name", ""))
	_item_list.items = list_items
	if _selected_index >= _cargo_items.size():
		_selected_index = -1
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	_sell_one()


func _on_sell_one() -> void:
	_sell_one()


func _on_sell_all() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var ship: FleetShip = _cargo_item_ship[_selected_index]
	var item_name: String = item.get("name", "")
	var qty: int = item.get("quantity", 1)
	if _commerce_manager.sell_cargo_from_ship(item_name, qty, ship):
		if GameManager._notif:
			var total := PriceCatalog.get_cargo_price(item_name) * qty
			GameManager._notif.commerce.sold_qty(item_name, qty, total)
		_refresh_items()
	queue_redraw()


func _sell_one() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var ship: FleetShip = _cargo_item_ship[_selected_index]
	var item_name: String = item.get("name", "")
	if _commerce_manager.sell_cargo_from_ship(item_name, 1, ship):
		if GameManager._notif:
			var unit_price := PriceCatalog.get_cargo_price(item_name)
			GameManager._notif.commerce.sold(item_name, unit_price)
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

	if _cargo_items.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), "Soute vide",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _cargo_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un objet",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item: Dictionary = _cargo_items[_selected_index]
	var item_name: String = item.get("name", "")
	var item_type: String = item.get("type", "")
	var qty: int = item.get("quantity", 1)
	var unit_price := PriceCatalog.get_cargo_price(item_name)

	var y: float = 10.0

	# Ship owner label (when "TOUS" filter)
	if _filter_ship_index == 0 and _selected_index < _cargo_item_ship.size():
		var owner_ship := _cargo_item_ship[_selected_index]
		draw_string(font, Vector2(detail_x + 10, y + 12), owner_ship.custom_name,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
		y += 16.0

	# Name
	draw_string(font, Vector2(detail_x + 10, y + 14), item_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	# Type
	if item_type != "":
		draw_string(font, Vector2(detail_x + 10, y + 12), "Type",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), item_type,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
		y += 18.0

	# Quantity
	draw_string(font, Vector2(detail_x + 10, y + 12), "Quantite",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), str(qty),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Unit price
	draw_string(font, Vector2(detail_x + 10, y + 12), "Prix/u",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(unit_price),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
	y += 24.0

	# Total sell price box
	var total_price := unit_price * qty
	y += 4.0
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(font, Vector2(detail_x + 10, y + 19),
		"TOTAL: +" + PriceCatalog.format_price(total_price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[idx]
	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

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

	# Color badge
	ci.draw_rect(Rect2(rect.position.x + 6, rect.position.y + 8, 12, 12), icon_col)

	# Ship name prefix (when TOUS filter and multiple ships)
	var prefix: String = ""
	if _filter_ship_index == 0 and _docked_ships.size() > 1 and idx < _cargo_item_ship.size():
		prefix = _cargo_item_ship[idx].custom_name.substr(0, 8) + " | "

	# Name + quantity
	var label := "%s%s x%d" % [prefix, item_name, qty]
	ci.draw_string(font, Vector2(rect.position.x + 24, rect.position.y + 18),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_LABEL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Price (right-aligned)
	var unit_price := PriceCatalog.get_cargo_price(item_name)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.6, rect.position.y + 18),
		"+" + PriceCatalog.format_price(unit_price) + "/u", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.35,
		UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
