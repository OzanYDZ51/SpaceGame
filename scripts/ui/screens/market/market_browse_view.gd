class_name MarketBrowseView
extends UIComponent

# =============================================================================
# MarketBrowseView — PARCOURIR tab: search, filter, browse all listings
# =============================================================================

var _market_manager: MarketManager = null
var _player_data = null
var browse_only: bool = false

# Filter widgets
var _category_dropdown: UIDropdown = null
var _search_input: UITextInput = null
var _search_btn: UIButton = null
var _sort_dropdown: UIDropdown = null

# Results
var _table: UIDataTable = null
var _buy_btn: UIButton = null

# State
var _listings: Array = []
var _selected_index: int = -1
var _total_results: int = 0
var _current_offset: int = 0
var _loading: bool = false

const DETAIL_W: float = 260.0
const PAGE_SIZE: int = 50

static var CATEGORIES: Array[String]:
	get:
		return [
			Locale.t("market.category.all"),
			Locale.t("market.category.ship"),
			Locale.t("market.category.weapon"),
			Locale.t("market.category.shield"),
			Locale.t("market.category.engine"),
			Locale.t("market.category.module"),
			Locale.t("market.category.ore"),
			Locale.t("market.category.refined"),
			Locale.t("market.category.cargo"),
		]

const CATEGORY_KEYS: Array[String] = ["all", "ship", "weapon", "shield", "engine", "module", "ore", "refined", "cargo"]

static var SORT_OPTIONS: Array[String]:
	get:
		return [
			Locale.t("market.sort.newest"),
			Locale.t("market.sort.price_asc"),
			Locale.t("market.sort.price_desc"),
			Locale.t("market.sort.name"),
		]

const SORT_KEYS: Array[String] = ["newest", "price_asc", "price_desc", "name"]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Category dropdown
	_category_dropdown = UIDropdown.new()
	_category_dropdown.options = CATEGORIES
	_category_dropdown.selected_index = 0
	_category_dropdown.option_selected.connect(func(_idx): _do_search())
	add_child(_category_dropdown)

	# Search input
	_search_input = UITextInput.new()
	_search_input.placeholder = Locale.t("market.search_placeholder")
	_search_input.text_submitted.connect(func(_t): _do_search())
	add_child(_search_input)

	# Search button
	_search_btn = UIButton.new()
	_search_btn.text = Locale.t("market.btn.search")
	_search_btn.pressed.connect(_do_search)
	add_child(_search_btn)

	# Sort dropdown
	_sort_dropdown = UIDropdown.new()
	_sort_dropdown.options = SORT_OPTIONS
	_sort_dropdown.selected_index = 0
	_sort_dropdown.option_selected.connect(func(_idx): _do_search())
	add_child(_sort_dropdown)

	# Results table
	_table = UIDataTable.new()
	_table.columns = [
		{"label": Locale.t("market.col.item"), "width_ratio": 0.25},
		{"label": Locale.t("market.col.station"), "width_ratio": 0.25},
		{"label": Locale.t("market.col.quantity"), "width_ratio": 0.1},
		{"label": Locale.t("market.col.price"), "width_ratio": 0.15},
		{"label": Locale.t("market.col.seller"), "width_ratio": 0.15},
	]
	_table.row_selected.connect(_on_row_selected)
	add_child(_table)

	# Buy button
	_buy_btn = UIButton.new()
	_buy_btn.text = Locale.t("market.btn.buy")
	_buy_btn.accent_color = UITheme.ACCENT
	_buy_btn.pressed.connect(_on_buy_pressed)
	add_child(_buy_btn)

	resized.connect(_layout)


func setup(mgr: MarketManager, pdata) -> void:
	_market_manager = mgr
	_player_data = pdata
	if mgr:
		if not mgr.listings_loaded.is_connected(_on_listings_loaded):
			mgr.listings_loaded.connect(_on_listings_loaded)
		if not mgr.listing_bought.is_connected(_on_listing_bought):
			mgr.listing_bought.connect(_on_listing_bought)
		if not mgr.market_error.is_connected(_on_market_error):
			mgr.market_error.connect(_on_market_error)


func refresh() -> void:
	_selected_index = -1
	_current_offset = 0
	_do_search()
	_layout()
	queue_redraw()


func _layout() -> void:
	var s: Vector2 = size
	var filter_y: float = 0.0
	var filter_h: float = 32.0
	var gap: float = 6.0

	# Filter row
	_category_dropdown.position = Vector2(0, filter_y)
	_category_dropdown.size = Vector2(140, filter_h)

	_search_input.position = Vector2(146, filter_y)
	_search_input.size = Vector2(180, filter_h)

	_search_btn.position = Vector2(332, filter_y)
	_search_btn.size = Vector2(90, filter_h)

	_sort_dropdown.position = Vector2(428, filter_y)
	_sort_dropdown.size = Vector2(130, filter_h)

	# Table: left side
	var table_top: float = filter_y + filter_h + gap
	var table_w: float = s.x - DETAIL_W - 10.0
	_table.position = Vector2(0, table_top)
	_table.size = Vector2(table_w, s.y - table_top)

	# Buy button: bottom right in detail panel
	_buy_btn.position = Vector2(table_w + 20, s.y - 40)
	_buy_btn.size = Vector2(DETAIL_W - 30, 34)


func _do_search() -> void:
	if _market_manager == null or _loading:
		return
	_loading = true
	var cat: String = CATEGORY_KEYS[_category_dropdown.selected_index]
	var search: String = _search_input.get_text()
	var sort: String = SORT_KEYS[_sort_dropdown.selected_index]
	_market_manager.search_listings(cat, search, sort, -1, -1, -1, PAGE_SIZE, _current_offset)
	queue_redraw()


func _on_listings_loaded(listings: Array, total: int) -> void:
	_loading = false
	_listings = listings
	_total_results = total
	_selected_index = -1

	# Populate table
	var rows: Array = []
	for l in listings:
		rows.append([
			l.item_name,
			_format_location(l),
			str(l.quantity),
			PlayerEconomy.format_credits(l.unit_price),
			l.seller_name,
		])
	_table.rows = rows
	_table.selected_row = -1
	_table.queue_redraw()
	queue_redraw()


func _on_row_selected(idx: int) -> void:
	_selected_index = idx
	_update_buy_button()
	queue_redraw()


func _on_buy_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _listings.size():
		return
	var listing: MarketListing = _listings[_selected_index]
	if not listing.is_in_current_station():
		return
	if _player_data and _player_data.economy:
		if _player_data.economy.credits < listing.get_total_price():
			return
	_market_manager.buy_listing(listing.id)


func _on_listing_bought(_listing: MarketListing) -> void:
	# Refresh the listing
	_do_search()
	if GameManager._notif:
		GameManager._notif.toast(Locale.t("notif.market_bought") % _listing.item_name)


func _on_market_error(msg: String) -> void:
	_loading = false
	if GameManager._notif:
		GameManager._notif.toast(msg, UIToast.ToastType.ERROR)
	queue_redraw()


func _format_location(listing: MarketListing) -> String:
	var sys_name: String = ""
	if GameManager._galaxy:
		sys_name = GameManager._galaxy.get_system_name(listing.system_id)
	if sys_name != "" and sys_name != "Unknown":
		return "%s (%s)" % [listing.station_name, sys_name]
	return listing.station_name


func _update_buy_button() -> void:
	if browse_only:
		_buy_btn.visible = false
		return
	_buy_btn.visible = true
	if _selected_index < 0 or _selected_index >= _listings.size():
		_buy_btn.text = Locale.t("market.btn.buy")
		_buy_btn.enabled = false
		return

	var listing: MarketListing = _listings[_selected_index]
	var is_docked_here: bool = listing.is_in_current_station()
	var can_afford: bool = true
	if _player_data and _player_data.economy:
		can_afford = _player_data.economy.credits >= listing.get_total_price()

	if not is_docked_here:
		_buy_btn.text = Locale.t("market.dock_required") % listing.station_name
		_buy_btn.enabled = false
	elif not can_afford:
		_buy_btn.text = Locale.t("market.insufficient_credits")
		_buy_btn.enabled = false
	else:
		_buy_btn.text = Locale.t("market.btn.buy") + " — " + PlayerEconomy.format_credits(listing.get_total_price()) + " CR"
		_buy_btn.enabled = true


func _draw() -> void:
	var s: Vector2 = size

	# Detail panel background (right side)
	var table_w: float = s.x - DETAIL_W - 10.0
	var detail_x: float = table_w + 10.0
	var detail_rect: Rect2 = Rect2(detail_x, 0, DETAIL_W, s.y)
	draw_rect(detail_rect, Color(0.01, 0.02, 0.05, 0.6))
	draw_rect(detail_rect, UITheme.BORDER, false, 1.0)

	var font: Font = UITheme.get_font()

	if _loading:
		draw_string(font, Vector2(s.x * 0.5 - 40, s.y * 0.5),
			Locale.t("common.loading"), HORIZONTAL_ALIGNMENT_CENTER, 200, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
		return

	if _listings.is_empty() and not _loading:
		draw_string(font, Vector2(table_w * 0.5 - 80, s.y * 0.5),
			Locale.t("market.no_results"), HORIZONTAL_ALIGNMENT_CENTER, 200, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# Results count
	if _total_results > 0:
		draw_string(font, Vector2(0, s.y - 6),
			"%d " % _total_results + Locale.t("market.results"),
			HORIZONTAL_ALIGNMENT_LEFT, 200, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Detail panel content
	if _selected_index >= 0 and _selected_index < _listings.size():
		_draw_detail_panel(detail_rect, _listings[_selected_index])


func _draw_detail_panel(rect: Rect2, listing: MarketListing) -> void:
	var font: Font = UITheme.get_font()
	var x: float = rect.position.x + 12.0
	var y: float = rect.position.y + 16.0
	var w: float = rect.size.x - 24.0

	# Item name
	draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_HEADER),
		listing.item_name, HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += UITheme.FONT_SIZE_HEADER + 8.0

	# Category badge
	var cat_text: String = listing.item_category.to_upper()
	draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_SMALL),
		cat_text, HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_SMALL, UITheme.PRIMARY)
	y += UITheme.FONT_SIZE_SMALL + 12.0

	# Separator
	draw_line(Vector2(x, y), Vector2(x + w, y), UITheme.BORDER, 1.0)
	y += 10.0

	# Key-value pairs
	y = draw_key_value(x, y, w, Locale.t("market.detail.seller"), listing.seller_name)
	y = draw_key_value(x, y, w, Locale.t("market.detail.station"), _format_location(listing))
	y = draw_key_value(x, y, w, Locale.t("market.detail.quantity"), str(listing.quantity))
	y = draw_key_value(x, y, w, Locale.t("market.detail.unit_price"), PlayerEconomy.format_credits(listing.unit_price) + " CR")
	y = draw_key_value(x, y, w, Locale.t("market.detail.total"), PlayerEconomy.format_credits(listing.get_total_price()) + " CR")
	y += 6.0

	# Separator
	draw_line(Vector2(x, y), Vector2(x + w, y), UITheme.BORDER, 1.0)
	y += 10.0

	# Dock status
	var is_docked_here: bool = listing.is_in_current_station()
	if is_docked_here:
		draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_SMALL),
			Locale.t("market.at_station"), HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)
	else:
		draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_SMALL),
			Locale.t("market.dock_required") % listing.station_name,
			HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_SMALL, UITheme.WARNING)
