class_name SellResourceView
extends Control

# =============================================================================
# Sell Resource View - Sell mined ores from per-ship resources
# Ship filter dropdown: TOUS / active ship / other docked ships
# Left: UIScrollList of ores (qty > 0), Right: detail + sell buttons
# =============================================================================

var _commerce_manager: CommerceManager = null
var _station_id: String = ""

var _ship_dropdown: UIDropdown = null
var _item_list: UIScrollList = null
var _sell_1_btn: UIButton = null
var _sell_10_btn: UIButton = null
var _sell_all_btn: UIButton = null
var _resource_ids: Array[StringName] = []
var _resource_ship: Array[FleetShip] = []  # which ship owns each row
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

	_sell_1_btn = UIButton.new()
	_sell_1_btn.text = "VENDRE x1"
	_sell_1_btn.accent_color = UITheme.WARNING
	_sell_1_btn.visible = false
	_sell_1_btn.pressed.connect(_on_sell_1)
	add_child(_sell_1_btn)

	_sell_10_btn = UIButton.new()
	_sell_10_btn.text = "VENDRE x10"
	_sell_10_btn.accent_color = UITheme.WARNING
	_sell_10_btn.visible = false
	_sell_10_btn.pressed.connect(_on_sell_10)
	add_child(_sell_10_btn)

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
	var pd := _commerce_manager.player_data
	if pd.fleet == null:
		return
	var fleet := pd.fleet
	var active := fleet.get_active()
	if active:
		_docked_ships.append(active)
	if _station_id != "":
		var docked_indices := fleet.get_ships_at_station(_station_id)
		for idx in docked_indices:
			var fs := fleet.ships[idx]
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
	_refresh_items()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_ship_dropdown.position = Vector2(0, 0)
	_ship_dropdown.size = Vector2(list_w, DROPDOWN_H)
	var list_top: float = DROPDOWN_H + 4.0
	_item_list.position = Vector2(0, list_top)
	_item_list.size = Vector2(list_w, s.y - list_top)
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
		_item_list.items = []
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

	var list_items: Array = []
	for rid in _resource_ids:
		list_items.append(rid)
	_item_list.items = list_items
	if _selected_index >= _resource_ids.size():
		_selected_index = -1
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	_do_sell(1)


func _on_sell_1() -> void:
	_do_sell(1)


func _on_sell_10() -> void:
	_do_sell(10)


func _on_sell_all() -> void:
	if _selected_index < 0 or _selected_index >= _resource_ids.size(): return
	if _commerce_manager == null: return
	var res_id: StringName = _resource_ids[_selected_index]
	var ship: FleetShip = _resource_ship[_selected_index]
	var qty: int = ship.get_resource(res_id)
	if qty > 0:
		_do_sell(qty)


func _do_sell(qty: int) -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _resource_ids.size(): return
	var res_id: StringName = _resource_ids[_selected_index]
	var ship: FleetShip = _resource_ship[_selected_index]
	var available: int = ship.get_resource(res_id)
	qty = mini(qty, available)
	if qty <= 0: return
	if _commerce_manager.sell_resource_from_ship(res_id, qty, ship):
		var toast_mgr := _find_toast_manager()
		if toast_mgr:
			var total := PriceCatalog.get_resource_price(res_id) * qty
			var res_data := MiningRegistry.get_resource(res_id)
			var rname := res_data.display_name if res_data else String(res_id)
			toast_mgr.show_toast("%s x%d vendu! +%s CR" % [rname, qty, PlayerEconomy.format_credits(total)])
		_refresh_items()
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

	if _resource_ids.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), "Aucun minerai",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _resource_ids.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un minerai",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var res_id: StringName = _resource_ids[_selected_index]
	var res_data := MiningRegistry.get_resource(res_id)
	if res_data == null: return
	var ship: FleetShip = _resource_ship[_selected_index]
	var qty: int = ship.get_resource(res_id)
	var unit_price := res_data.base_value

	var y: float = 10.0

	# Ship owner label (when "TOUS" filter)
	if _filter_ship_index == 0 and _docked_ships.size() > 1:
		draw_string(font, Vector2(detail_x + 10, y + 12), ship.custom_name,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
		y += 16.0

	# Name with color
	draw_string(font, Vector2(detail_x + 10, y + 14), res_data.display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, res_data.icon_color)
	y += 24.0

	# Description
	if res_data.description != "":
		draw_string(font, Vector2(detail_x + 10, y + 10), res_data.description,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
		y += 18.0

	# Rarity
	var rarity_str: String = ["Commun", "Peu commun", "Rare", "Tres rare", "Legendaire"][res_data.rarity]
	draw_string(font, Vector2(detail_x + 10, y + 12), "Rarete",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), rarity_str,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
	y += 18.0

	# Quantity
	draw_string(font, Vector2(detail_x + 10, y + 12), "En stock",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), str(qty),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
	y += 18.0

	# Unit price
	draw_string(font, Vector2(detail_x + 10, y + 12), "Prix/u",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(unit_price),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, PlayerEconomy.CREDITS_COLOR)
	y += 24.0

	# Total value box
	var total_price := unit_price * qty
	y += 4.0
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(font, Vector2(detail_x + 10, y + 19),
		"TOTAL: +" + PriceCatalog.format_price(total_price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _resource_ids.size(): return
	var res_id: StringName = _resource_ids[idx]
	var res_data := MiningRegistry.get_resource(res_id)
	if res_data == null: return
	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

	var ship: FleetShip = _resource_ship[idx]
	var qty: int = ship.get_resource(res_id)

	# Color badge
	ci.draw_rect(Rect2(rect.position.x + 6, rect.position.y + 8, 12, 12), res_data.icon_color)

	# Ship name prefix (when TOUS filter and multiple ships)
	var prefix: String = ""
	if _filter_ship_index == 0 and _docked_ships.size() > 1:
		prefix = ship.custom_name.substr(0, 8) + " | "

	# Name + quantity
	var label := "%s%s x%d" % [prefix, res_data.display_name, qty]
	ci.draw_string(font, Vector2(rect.position.x + 24, rect.position.y + 18),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Price (right-aligned)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.6, rect.position.y + 18),
		"+" + PriceCatalog.format_price(res_data.base_value) + "/u", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.35,
		UITheme.FONT_SIZE_SMALL, PlayerEconomy.CREDITS_COLOR)
