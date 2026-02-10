class_name SellShipView
extends Control

# =============================================================================
# Sell Ship View - Shows ALL fleet ships with status, sells non-active docked ones
# Left: UIScrollList (all ships, status tags), Right: detail + sell button
# =============================================================================

var _commerce_manager: CommerceManager = null
var _station_id: String = ""

var _item_list: UIScrollList = null
var _sell_btn: UIButton = null
var _fleet_ships: Array[FleetShip] = []   # all ships in display order
var _fleet_indices: Array[int] = []       # original fleet index per row
var _ship_can_sell: Array[bool] = []      # whether each row is sellable
var _ship_status: Array[String] = []      # status tag per row
var _selected_index: int = -1

const DETAIL_W := 240.0
const ROW_H := 52.0


func _ready() -> void:
	resized.connect(_layout)

	_item_list = UIScrollList.new()
	_item_list.row_height = ROW_H
	_item_list.item_draw_callback = _draw_item_row
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_double_clicked.connect(_on_item_double_clicked)
	_item_list.visible = false
	add_child(_item_list)

	_sell_btn = UIButton.new()
	_sell_btn.text = "VENDRE VAISSEAU"
	_sell_btn.accent_color = UITheme.DANGER
	_sell_btn.visible = false
	_sell_btn.pressed.connect(_on_sell_pressed)
	add_child(_sell_btn)


func setup(mgr: CommerceManager, station_id: String = "") -> void:
	_commerce_manager = mgr
	_station_id = station_id


func refresh() -> void:
	_item_list.visible = true
	_sell_btn.visible = true
	_refresh_items()
	_layout()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_item_list.position = Vector2(0, 0)
	_item_list.size = Vector2(list_w, s.y)
	_sell_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_btn.size = Vector2(DETAIL_W - 20, 34)


func _refresh_items() -> void:
	_fleet_ships.clear()
	_fleet_indices.clear()
	_ship_can_sell.clear()
	_ship_status.clear()
	if _commerce_manager == null or _commerce_manager.player_fleet == null:
		_item_list.items = []
		return

	var fleet := _commerce_manager.player_fleet
	var is_only_ship: bool = (fleet.ships.size() <= 1)

	for i in fleet.ships.size():
		var fs := fleet.ships[i]
		_fleet_ships.append(fs)
		_fleet_indices.append(i)

		var is_active: bool = (i == fleet.active_index)
		var is_docked: bool = (fs.deployment_state == FleetShip.DeploymentState.DOCKED)
		var is_deployed: bool = (fs.deployment_state == FleetShip.DeploymentState.DEPLOYED)
		var is_destroyed: bool = (fs.deployment_state == FleetShip.DeploymentState.DESTROYED)
		var is_here: bool = is_docked and (_station_id == "" or fs.docked_station_id == _station_id)

		# Determine sell eligibility and status tag
		if is_active:
			_ship_can_sell.append(false)
			_ship_status.append("ACTIF")
		elif is_destroyed:
			_ship_can_sell.append(false)
			_ship_status.append("DETRUIT")
		elif is_deployed:
			_ship_can_sell.append(false)
			_ship_status.append("DEPLOYE")
		elif is_docked and not is_here:
			_ship_can_sell.append(false)
			_ship_status.append("AILLEURS")
		elif is_here and is_only_ship:
			_ship_can_sell.append(false)
			_ship_status.append("DERNIER")
		elif is_here:
			_ship_can_sell.append(true)
			_ship_status.append("ICI")
		else:
			_ship_can_sell.append(false)
			_ship_status.append("")

	var list_items: Array = []
	for fs in _fleet_ships:
		list_items.append(fs.custom_name)
	_item_list.items = list_items
	if _selected_index >= _fleet_ships.size():
		_selected_index = -1
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	if idx >= 0 and idx < _ship_can_sell.size() and _ship_can_sell[idx]:
		_do_sell()


func _on_sell_pressed() -> void:
	_do_sell()


func _do_sell() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _fleet_ships.size(): return
	if not _ship_can_sell[_selected_index]: return
	var fleet_idx: int = _fleet_indices[_selected_index]
	var fs := _fleet_ships[_selected_index]
	var sell_price := _commerce_manager.get_ship_sell_price(fs)
	if _commerce_manager.sell_ship(fleet_idx):
		var toast_mgr := _find_toast_manager()
		if toast_mgr:
			toast_mgr.show_toast("%s vendu! +%s CR" % [fs.custom_name, PlayerEconomy.format_credits(sell_price)])
		_selected_index = -1
		_refresh_items()
	queue_redraw()


func _find_toast_manager() -> UIToastManager:
	var node := get_tree().root.find_child("UIToastManager", true, false)
	return node as UIToastManager if node else null


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# =========================================================================
# STATUS HELPERS
# =========================================================================
func _get_status_color(status: String) -> Color:
	match status:
		"ACTIF": return UITheme.PRIMARY
		"ICI": return Color(0.2, 0.9, 0.3)
		"AILLEURS": return UITheme.TEXT_DIM
		"DEPLOYE": return Color(0.3, 0.6, 1.0)
		"DETRUIT": return UITheme.DANGER
		"DERNIER": return UITheme.WARNING
		_: return UITheme.TEXT_DIM


func _get_sell_reason(idx: int) -> String:
	if idx < 0 or idx >= _ship_status.size():
		return ""
	match _ship_status[idx]:
		"ACTIF": return "Vaisseau en cours d'utilisation.\nChangez de vaisseau pour le vendre."
		"DEPLOYE": return "Vaisseau actuellement deploye.\nRappelez-le d'abord."
		"DETRUIT": return "Vaisseau detruit."
		"AILLEURS": return "Vaisseau docke dans une autre\nstation. Rendez-vous sur place."
		"DERNIER": return "Impossible de vendre votre\ndernier vaisseau."
		_: return ""


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

	if _fleet_ships.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), "Aucun vaisseau",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _fleet_ships.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un vaisseau",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		# Fleet summary
		var total_ships := _fleet_ships.size()
		var sellable_count: int = 0
		for can in _ship_can_sell:
			if can:
				sellable_count += 1
		draw_string(font, Vector2(detail_x + 10, 54), "Flotte: %d vaisseau%s" % [total_ships, "x" if total_ships > 1 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
		if sellable_count > 0:
			draw_string(font, Vector2(detail_x + 10, 72), "%d vendable%s ici" % [sellable_count, "s" if sellable_count > 1 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, Color(0.2, 0.9, 0.3))
		else:
			draw_string(font, Vector2(detail_x + 10, 72), "Aucun vendable ici",
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.WARNING)
		return

	var fs := _fleet_ships[_selected_index]
	var ship_data := ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null: return
	var can_sell: bool = _ship_can_sell[_selected_index]
	var status: String = _ship_status[_selected_index]

	var y: float = 10.0

	# Status badge
	var status_col := _get_status_color(status)
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 18),
		Color(status_col.r, status_col.g, status_col.b, 0.15))
	draw_rect(Rect2(detail_x + 10, y, 3, 18), status_col)
	draw_string(font, Vector2(detail_x + 18, y + 13), status,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 30, UITheme.FONT_SIZE_TINY, status_col)
	y += 24.0

	# Ship name
	draw_string(font, Vector2(detail_x + 10, y + 14), fs.custom_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	# Ship class
	draw_string(font, Vector2(detail_x + 10, y + 12), "Classe",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), String(ship_data.ship_class),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Hull HP
	draw_string(font, Vector2(detail_x + 10, y + 12), "Coque",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), "%.0f PV" % ship_data.hull_hp,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Hardpoints
	var weapon_count: int = 0
	for wn in fs.weapons:
		if wn != &"":
			weapon_count += 1
	draw_string(font, Vector2(detail_x + 10, y + 12), "Armes",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), "%d/%d" % [weapon_count, fs.weapons.size()],
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Equipment value
	var equip_val := fs.get_total_equipment_value()
	if equip_val > 0:
		draw_string(font, Vector2(detail_x + 10, y + 12), "Equip.",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(equip_val),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
		y += 18.0

	# Cargo
	if fs.cargo:
		var cargo_count := fs.cargo.get_total_count()
		if cargo_count > 0:
			draw_string(font, Vector2(detail_x + 10, y + 12), "Cargo",
				HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
			draw_string(font, Vector2(detail_x + 95, y + 12), "%d items" % cargo_count,
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.WARNING)
			y += 18.0

	y += 8.0

	if can_sell:
		# Price breakdown
		var hull_price := PriceCatalog.get_sell_price(ship_data.price)
		var equip_price := PriceCatalog.get_sell_price(equip_val)
		var total_price := hull_price + equip_price

		# Section header
		draw_rect(Rect2(detail_x + 10, y, 2, 10), PlayerEconomy.CREDITS_COLOR)
		draw_string(font, Vector2(detail_x + 16, y + 9), "ESTIMATION",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_HEADER)
		y += 18.0

		draw_string(font, Vector2(detail_x + 10, y + 12), "Coque",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), "+" + PriceCatalog.format_price(hull_price),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
		y += 16.0

		if equip_price > 0:
			draw_string(font, Vector2(detail_x + 10, y + 12), "Equip.",
				HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
			draw_string(font, Vector2(detail_x + 95, y + 12), "+" + PriceCatalog.format_price(equip_price),
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
			y += 16.0

		y += 4.0

		# Total sell price box
		draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
			Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
		draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
		draw_string(font, Vector2(detail_x + 10, y + 19),
			"TOTAL: +" + PriceCatalog.format_price(total_price),
			HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)

		# Cargo loss warning
		if fs.cargo and fs.cargo.get_total_count() > 0:
			y += 36.0
			draw_string(font, Vector2(detail_x + 10, y + 10), "Cargo perdu a la vente!",
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.DANGER)
	else:
		# Non-sellable: show reason
		var reason := _get_sell_reason(_selected_index)
		if reason != "":
			draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 42),
				Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.08))
			draw_rect(Rect2(detail_x + 10, y, 3, 42), UITheme.DANGER)
			var lines := reason.split("\n")
			for li in lines.size():
				draw_string(font, Vector2(detail_x + 18, y + 14 + li * 16), lines[li],
					HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 30, UITheme.FONT_SIZE_TINY, UITheme.WARNING)

	# Update sell button state
	if _sell_btn:
		_sell_btn.enabled = can_sell


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _fleet_ships.size(): return
	var fs := _fleet_ships[idx]
	var ship_data := ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null: return
	var font: Font = UITheme.get_font()
	var can_sell: bool = _ship_can_sell[idx] if idx < _ship_can_sell.size() else false
	var status: String = _ship_status[idx] if idx < _ship_status.size() else ""

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		var sel_col := UITheme.PRIMARY if can_sell else UITheme.TEXT_DIM
		ci.draw_rect(rect, Color(sel_col.r, sel_col.g, sel_col.b, 0.12))

	var alpha: float = 1.0 if can_sell else 0.5

	# Status badge (small colored tag on left)
	var status_col := _get_status_color(status)
	ci.draw_rect(Rect2(rect.position.x + 4, rect.position.y + 6, 3, rect.size.y - 12),
		Color(status_col.r, status_col.g, status_col.b, alpha))

	# Ship name
	var name_col := UITheme.TEXT if (is_sel and can_sell) else Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, alpha)
	ci.draw_string(font, Vector2(rect.position.x + 14, rect.position.y + 18),
		fs.custom_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_BODY, name_col)

	# Status tag (right side, top)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x - 8, rect.position.y + 16),
		status, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.3,
		UITheme.FONT_SIZE_TINY, Color(status_col.r, status_col.g, status_col.b, alpha))

	# Class + sell price (bottom line)
	ci.draw_string(font, Vector2(rect.position.x + 14, rect.position.y + 36),
		String(ship_data.ship_class), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.4,
		UITheme.FONT_SIZE_SMALL, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, alpha))

	if can_sell:
		var sell_price := _commerce_manager.get_ship_sell_price(fs) if _commerce_manager else 0
		ci.draw_string(font, Vector2(rect.position.x + rect.size.x - 8, rect.position.y + 36),
			"+" + PriceCatalog.format_price(sell_price), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.4,
			UITheme.FONT_SIZE_SMALL, PlayerEconomy.CREDITS_COLOR)
