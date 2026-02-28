class_name MarketSellView
extends UIComponent

# =============================================================================
# MarketSellView — VENDRE tab: create new listings from inventory
# Only visible/usable when docked at a station.
# =============================================================================

var _market_manager: MarketManager = null
var _player_data = null

# Inventory list
var _table: UIDataTable = null
var _selected_index: int = -1
var _sellable_items: Array[Dictionary] = []  # {category, id, name, quantity, price}

# Form controls
var _price_input: UITextInput = null
var _quantity_input: UITextInput = null
var _duration_dropdown: UIDropdown = null
var _sell_btn: UIButton = null

const FORM_W: float = 260.0

static var DURATION_OPTIONS: Array[String]:
	get:
		return [
			Locale.t("market.duration.24h"),
			Locale.t("market.duration.48h"),
			Locale.t("market.duration.72h"),
		]

const DURATION_HOURS: Array[int] = [24, 48, 72]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Inventory table
	_table = UIDataTable.new()
	_table.columns = [
		{"label": Locale.t("market.col.item"), "width_ratio": 0.35},
		{"label": Locale.t("market.col.category"), "width_ratio": 0.2},
		{"label": Locale.t("market.col.quantity"), "width_ratio": 0.15},
		{"label": Locale.t("market.col.value"), "width_ratio": 0.2},
	]
	_table.row_selected.connect(_on_item_selected)
	add_child(_table)

	# Price input
	_price_input = UITextInput.new()
	_price_input.placeholder = Locale.t("market.price_placeholder")
	add_child(_price_input)

	# Quantity input
	_quantity_input = UITextInput.new()
	_quantity_input.placeholder = Locale.t("market.quantity_placeholder")
	add_child(_quantity_input)

	# Duration dropdown
	_duration_dropdown = UIDropdown.new()
	_duration_dropdown.options = DURATION_OPTIONS
	_duration_dropdown.selected_index = 0
	add_child(_duration_dropdown)

	# Sell button
	_sell_btn = UIButton.new()
	_sell_btn.text = Locale.t("market.btn.sell")
	_sell_btn.accent_color = UITheme.WARNING
	_sell_btn.pressed.connect(_on_sell_pressed)
	add_child(_sell_btn)

	resized.connect(_layout)


func setup(mgr: MarketManager, pdata) -> void:
	_market_manager = mgr
	_player_data = pdata
	if mgr:
		if not mgr.listing_created.is_connected(_on_listing_created):
			mgr.listing_created.connect(_on_listing_created)
		if not mgr.market_error.is_connected(_on_market_error):
			mgr.market_error.connect(_on_market_error)


func refresh() -> void:
	_selected_index = -1
	_build_sellable_list()
	_layout()
	queue_redraw()


func _build_sellable_list() -> void:
	_sellable_items.clear()
	if _player_data == null:
		_update_table()
		return

	var inventory: PlayerInventory = _player_data.inventory if _player_data else null
	var economy: PlayerEconomy = _player_data.economy if _player_data else null

	# Equipment from inventory
	if inventory:
		for wn in inventory.get_all_weapons():
			var w = WeaponRegistry.get_weapon(wn)
			if w:
				_sellable_items.append({"category": "weapon", "id": str(wn), "name": str(wn).replace("_", " ").capitalize(), "quantity": inventory.get_weapon_count(wn), "price": w.price})
		for sn in inventory.get_all_shields():
			var s = ShieldRegistry.get_shield(sn)
			if s:
				_sellable_items.append({"category": "shield", "id": str(sn), "name": str(sn).replace("_", " ").capitalize(), "quantity": inventory.get_shield_count(sn), "price": s.price})
		for en in inventory.get_all_engines():
			var e = EngineRegistry.get_engine(en)
			if e:
				_sellable_items.append({"category": "engine", "id": str(en), "name": str(en).replace("_", " ").capitalize(), "quantity": inventory.get_engine_count(en), "price": e.price})
		for mn in inventory.get_all_modules():
			var m = ModuleRegistry.get_module(mn)
			if m:
				_sellable_items.append({"category": "module", "id": str(mn), "name": str(mn).replace("_", " ").capitalize(), "quantity": inventory.get_module_count(mn), "price": m.price})

	# Ship resources (ores) from active fleet ship
	var fleet = _player_data.fleet if _player_data else null
	if fleet:
		var active_fs = fleet.get_active()
		if active_fs:
			for res_id in active_fs.ship_resources:
				var qty: int = active_fs.ship_resources[res_id]
				if qty > 0:
					var def: Dictionary = PlayerEconomy.RESOURCE_DEFS.get(res_id, {})
					var rname: String = def.get("name", str(res_id))
					_sellable_items.append({"category": "ore", "id": str(res_id), "name": rname, "quantity": qty, "price": 0})

	# Player-level resources (economy)
	if economy:
		for res_id in economy.resources:
			var qty: int = economy.resources[res_id]
			if qty > 0:
				# Skip if already added from ship_resources
				var already: bool = false
				for existing in _sellable_items:
					if existing["id"] == str(res_id) and existing["category"] == "ore":
						already = true
						break
				if not already:
					var def: Dictionary = PlayerEconomy.RESOURCE_DEFS.get(res_id, {})
					var rname: String = def.get("name", str(res_id))
					_sellable_items.append({"category": "ore", "id": str(res_id), "name": rname, "quantity": qty, "price": 0})

	# Ship cargo (active ship)
	if fleet:
		var active_fs = fleet.get_active()
		if active_fs and active_fs.cargo:
			for item in active_fs.cargo.get_all():
				_sellable_items.append({"category": "cargo", "id": str(item.get("item_name", "")), "name": str(item.get("item_name", "")), "quantity": int(item.get("quantity", 1)), "price": 0})

	_update_table()


func _update_table() -> void:
	var rows: Array = []
	for item in _sellable_items:
		var price_str: String = PlayerEconomy.format_credits(item["price"]) + " CR" if item["price"] > 0 else "—"
		rows.append([
			item["name"],
			item["category"].to_upper(),
			str(item["quantity"]),
			price_str,
		])
	_table.rows = rows
	_table.selected_row = -1
	_table.queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	if idx >= 0 and idx < _sellable_items.size():
		var item: Dictionary = _sellable_items[idx]
		_quantity_input.set_text("1")
		var suggested_price: int = item["price"] if item["price"] > 0 else 100
		_price_input.set_text(str(suggested_price))
	queue_redraw()


func _on_sell_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _sellable_items.size():
		return
	if _market_manager == null or _player_data == null:
		return

	var is_docked: bool = GameManager.current_state == Constants.GameState.DOCKED
	if not is_docked:
		return

	var item: Dictionary = _sellable_items[_selected_index]
	var price_text: String = _price_input.get_text().strip_edges()
	var qty_text: String = _quantity_input.get_text().strip_edges()

	if not price_text.is_valid_int() or not qty_text.is_valid_int():
		if GameManager._notif:
			GameManager._notif.toast(Locale.t("market.invalid_input"), UIToast.ToastType.ERROR)
		return

	var unit_price: int = int(price_text)
	var quantity: int = int(qty_text)

	if unit_price <= 0 or quantity <= 0:
		if GameManager._notif:
			GameManager._notif.toast(Locale.t("market.invalid_input"), UIToast.ToastType.ERROR)
		return

	if quantity > item["quantity"]:
		if GameManager._notif:
			GameManager._notif.toast(Locale.t("market.not_enough_items"), UIToast.ToastType.ERROR)
		return

	# Get station info
	var fleet = _player_data.fleet
	var active_fs = fleet.get_active() if fleet else null
	if active_fs == null:
		return

	var station_id: String = active_fs.docked_station_id
	var system_id: int = active_fs.docked_system_id
	var station_name: String = ""
	var ent: Dictionary = EntityRegistry.get_entity(station_id)
	station_name = ent.get("name", station_id)

	var duration_hours: int = DURATION_HOURS[_duration_dropdown.selected_index]

	_market_manager.create_listing(
		item["category"], item["id"], item["name"],
		quantity, unit_price, duration_hours,
		system_id, station_id, station_name
	)


func _on_listing_created(listing: MarketListing) -> void:
	if GameManager._notif:
		GameManager._notif.toast(Locale.t("notif.market_listed") % listing.item_name)
	refresh()


func _on_market_error(msg: String) -> void:
	if GameManager._notif:
		GameManager._notif.toast(msg, UIToast.ToastType.ERROR)


func _layout() -> void:
	var s: Vector2 = size
	var table_w: float = s.x - FORM_W - 10.0

	_table.position = Vector2(0, 0)
	_table.size = Vector2(table_w, s.y)

	var fx: float = table_w + 16.0
	var fw: float = FORM_W - 24.0
	var fy: float = 0.0

	_price_input.position = Vector2(fx, fy + 26)
	_price_input.size = Vector2(fw, 30)

	_quantity_input.position = Vector2(fx, fy + 82)
	_quantity_input.size = Vector2(fw, 30)

	_duration_dropdown.position = Vector2(fx, fy + 138)
	_duration_dropdown.size = Vector2(fw, 30)

	_sell_btn.position = Vector2(fx, s.y - 40)
	_sell_btn.size = Vector2(fw, 34)


func _draw() -> void:
	var s: Vector2 = size
	var table_w: float = s.x - FORM_W - 10.0
	var is_docked: bool = GameManager.current_state == Constants.GameState.DOCKED
	var font: Font = UITheme.get_font()

	# Form panel
	var form_x: float = table_w + 10.0
	var form_rect: Rect2 = Rect2(form_x, 0, FORM_W, s.y)
	draw_rect(form_rect, Color(0.01, 0.02, 0.05, 0.6))
	draw_rect(form_rect, UITheme.BORDER, false, 1.0)

	if not is_docked:
		# "Dock required" overlay
		draw_string(font, Vector2(form_x + 12, s.y * 0.4),
			Locale.t("market.sell_dock_required"),
			HORIZONTAL_ALIGNMENT_LEFT, FORM_W - 24, UITheme.FONT_SIZE_BODY, UITheme.WARNING)
		return

	var fx: float = form_x + 12.0
	var fw: float = FORM_W - 24.0
	var fy: float = 0.0

	# Section header
	draw_section_header(fx, fy, fw, Locale.t("market.sell_header"))
	fy += 26.0

	# Price label
	draw_string(font, Vector2(fx, fy + 16), Locale.t("market.label.price"),
		HORIZONTAL_ALIGNMENT_LEFT, fw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Quantity label
	draw_string(font, Vector2(fx, fy + 72), Locale.t("market.label.quantity"),
		HORIZONTAL_ALIGNMENT_LEFT, fw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Duration label
	draw_string(font, Vector2(fx, fy + 128), Locale.t("market.label.duration"),
		HORIZONTAL_ALIGNMENT_LEFT, fw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Fee summary
	if _selected_index >= 0 and _selected_index < _sellable_items.size():
		var price_text: String = _price_input.get_text().strip_edges()
		var qty_text: String = _quantity_input.get_text().strip_edges()
		if price_text.is_valid_int() and qty_text.is_valid_int():
			var up: int = int(price_text)
			var qt: int = int(qty_text)
			var total: int = up * qt
			var fee: int = maxi(1, int(total * 0.05))
			var summary_y: float = fy + 190.0
			draw_line(Vector2(fx, summary_y), Vector2(fx + fw, summary_y), UITheme.BORDER, 1.0)
			summary_y += 8.0
			summary_y = draw_key_value(fx, summary_y, fw, Locale.t("market.summary.total"), PlayerEconomy.format_credits(total) + " CR")
			summary_y = draw_key_value(fx, summary_y, fw, Locale.t("market.summary.fee"), PlayerEconomy.format_credits(fee) + " CR")
			summary_y = draw_key_value(fx, summary_y, fw, Locale.t("market.summary.you_receive"), PlayerEconomy.format_credits(total) + " CR")
