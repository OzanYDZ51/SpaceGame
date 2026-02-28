class_name MarketMyListingsView
extends UIComponent

# =============================================================================
# MarketMyListingsView — MES ANNONCES tab: manage own listings
# =============================================================================

var _market_manager: MarketManager = null
var _player_data = null

var _status_dropdown: UIDropdown = null
var _table: UIDataTable = null
var _cancel_btn: UIButton = null

var _listings: Array = []
var _selected_index: int = -1

static var STATUS_OPTIONS: Array[String]:
	get:
		return [
			Locale.t("market.status.all"),
			Locale.t("market.status.active"),
			Locale.t("market.status.sold"),
			Locale.t("market.status.expired"),
			Locale.t("market.status.cancelled"),
		]

const STATUS_KEYS: Array[String] = ["all", "active", "sold", "expired", "cancelled"]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Status filter
	_status_dropdown = UIDropdown.new()
	_status_dropdown.options = STATUS_OPTIONS
	_status_dropdown.selected_index = 0
	_status_dropdown.option_selected.connect(func(_idx): _do_fetch())
	add_child(_status_dropdown)

	# Table
	_table = UIDataTable.new()
	_table.columns = [
		{"label": Locale.t("market.col.item"), "width_ratio": 0.22},
		{"label": Locale.t("market.col.price"), "width_ratio": 0.13},
		{"label": Locale.t("market.col.quantity"), "width_ratio": 0.08},
		{"label": Locale.t("market.col.station"), "width_ratio": 0.22},
		{"label": Locale.t("market.col.status"), "width_ratio": 0.12},
		{"label": Locale.t("market.col.buyer"), "width_ratio": 0.13},
	]
	_table.row_selected.connect(_on_row_selected)
	add_child(_table)

	# Cancel button
	_cancel_btn = UIButton.new()
	_cancel_btn.text = Locale.t("market.btn.cancel")
	_cancel_btn.accent_color = UITheme.DANGER
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_cancel_btn.enabled = false
	add_child(_cancel_btn)

	resized.connect(_layout)


func setup(mgr: MarketManager, pdata) -> void:
	_market_manager = mgr
	_player_data = pdata
	if mgr:
		if not mgr.my_listings_loaded.is_connected(_on_my_listings_loaded):
			mgr.my_listings_loaded.connect(_on_my_listings_loaded)
		if not mgr.listing_cancelled.is_connected(_on_listing_cancelled):
			mgr.listing_cancelled.connect(_on_listing_cancelled)
		if not mgr.market_error.is_connected(_on_market_error):
			mgr.market_error.connect(_on_market_error)


func refresh() -> void:
	_selected_index = -1
	_cancel_btn.enabled = false
	_do_fetch()
	_layout()


func _do_fetch() -> void:
	if _market_manager == null:
		return
	var status_key: String = STATUS_KEYS[_status_dropdown.selected_index]
	_market_manager.get_my_listings(status_key)


func _on_my_listings_loaded(listings: Array) -> void:
	_listings = listings
	_selected_index = -1
	_cancel_btn.enabled = false

	var rows: Array = []
	for l in listings:
		var status_text: String = _translate_status(l.status)
		var buyer_text: String = l.sold_to_name if l.sold_to_name != "" else "—"
		var loc: String = l.station_name
		if GameManager._galaxy:
			var sn: String = GameManager._galaxy.get_system_name(l.system_id)
			if sn != "" and sn != "Unknown":
				loc = "%s (%s)" % [l.station_name, sn]
		rows.append([
			l.item_name,
			PlayerEconomy.format_credits(l.unit_price),
			str(l.quantity),
			loc,
			status_text,
			buyer_text,
		])
	_table.rows = rows
	_table.selected_row = -1
	_table.queue_redraw()
	queue_redraw()


func _on_row_selected(idx: int) -> void:
	_selected_index = idx
	_cancel_btn.enabled = false
	if idx >= 0 and idx < _listings.size():
		var listing: MarketListing = _listings[idx]
		_cancel_btn.enabled = listing.status == "active"
	queue_redraw()


func _on_cancel_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _listings.size():
		return
	var listing: MarketListing = _listings[_selected_index]
	if listing.status != "active":
		return
	_market_manager.cancel_listing(listing.id)


func _on_listing_cancelled(_listing_id: int) -> void:
	if GameManager._notif:
		GameManager._notif.toast(Locale.t("notif.market_cancelled"))
	_do_fetch()


func _on_market_error(msg: String) -> void:
	if GameManager._notif:
		GameManager._notif.toast(msg, UIToast.ToastType.ERROR)


func _translate_status(s: String) -> String:
	match s:
		"active": return Locale.t("market.status.active")
		"sold": return Locale.t("market.status.sold")
		"expired": return Locale.t("market.status.expired")
		"cancelled": return Locale.t("market.status.cancelled")
	return s.to_upper()


func _layout() -> void:
	var s: Vector2 = size

	_status_dropdown.position = Vector2(0, 0)
	_status_dropdown.size = Vector2(160, 30)

	_table.position = Vector2(0, 38)
	_table.size = Vector2(s.x, s.y - 80)

	_cancel_btn.position = Vector2(0, s.y - 38)
	_cancel_btn.size = Vector2(180, 34)


func _draw() -> void:
	var font: Font = UITheme.get_font()
	if _listings.is_empty():
		draw_string(font, Vector2(size.x * 0.5 - 80, size.y * 0.5),
			Locale.t("market.no_listings"), HORIZONTAL_ALIGNMENT_CENTER, 200,
			UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
