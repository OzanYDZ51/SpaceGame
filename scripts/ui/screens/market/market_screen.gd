class_name MarketScreen
extends UIScreen

# =============================================================================
# MarketScreen — Hotel des Ventes (HDV) — Global player marketplace
# Accessible anytime via O key. 3 tabs: PARCOURIR / VENDRE / MES ANNONCES
# =============================================================================

var market_manager: MarketManager = null
var player_data = null

var _tab_bar: UITabBar = null
var _browse_view: MarketBrowseView = null
var _sell_view: MarketSellView = null
var _my_listings_view: MarketMyListingsView = null
var _active_view: Control = null
var _current_tab: int = 0


func _ready() -> void:
	screen_title = Locale.t("screen.market")
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = _get_tab_names()
	_tab_bar.current_tab = 0
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	_browse_view = MarketBrowseView.new()
	_browse_view.visible = false
	add_child(_browse_view)

	_sell_view = MarketSellView.new()
	_sell_view.visible = false
	add_child(_sell_view)

	_my_listings_view = MarketMyListingsView.new()
	_my_listings_view.visible = false
	add_child(_my_listings_view)


func setup(mgr: MarketManager, pdata) -> void:
	market_manager = mgr
	player_data = pdata
	if _browse_view:
		_browse_view.setup(mgr, pdata)
	if _sell_view:
		_sell_view.setup(mgr, pdata)
	if _my_listings_view:
		_my_listings_view.setup(mgr, pdata)


func _on_opened() -> void:
	_tab_bar.tabs = _get_tab_names()
	_switch_tab(0)


func _on_closed() -> void:
	_hide_all_views()


func _on_tab_changed(idx: int) -> void:
	_switch_tab(idx)


func _switch_tab(idx: int) -> void:
	_current_tab = idx
	_tab_bar.current_tab = idx
	_hide_all_views()

	match idx:
		0:
			_browse_view.visible = true
			_active_view = _browse_view
			_browse_view.refresh()
		1:
			_sell_view.visible = true
			_active_view = _sell_view
			_sell_view.refresh()
		2:
			_my_listings_view.visible = true
			_active_view = _my_listings_view
			_my_listings_view.refresh()

	_layout_content()
	queue_redraw()


func _hide_all_views() -> void:
	if _browse_view: _browse_view.visible = false
	if _sell_view: _sell_view.visible = false
	if _my_listings_view: _my_listings_view.visible = false
	_active_view = null


func _layout_content() -> void:
	if _tab_bar == null:
		return
	var s: Vector2 = size
	var margin: float = 20.0
	var tab_h: float = 32.0
	var top: float = 60.0

	_tab_bar.position = Vector2(margin, top)
	_tab_bar.size = Vector2(s.x - margin * 2, tab_h)

	if _active_view:
		_active_view.position = Vector2(margin, top + tab_h + 6.0)
		_active_view.size = Vector2(s.x - margin * 2, s.y - top - tab_h - 50.0)


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))
	draw_rect(Rect2(0, 0, s.x, 50), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 40, s.x, 40), Color(0.0, 0.0, 0.02, 0.5))
	_draw_title(s)

	if not _is_open: return

	var font: Font = UITheme.get_font()

	# Credits display
	if player_data and player_data.economy:
		var cr_text: String = PlayerEconomy.format_credits(player_data.economy.credits) + " CR"
		draw_string(font, Vector2(s.x - 180, 55), cr_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 160, UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Docking status indicator
	var is_docked: bool = GameManager.current_state == Constants.GameState.DOCKED
	var dock_text: String = Locale.t("market.status_docked") if is_docked else Locale.t("market.status_flying")
	var dock_col: Color = UITheme.ACCENT if is_docked else UITheme.TEXT_DIM
	draw_string(font, Vector2(20, 55), dock_text,
		HORIZONTAL_ALIGNMENT_LEFT, 300, UITheme.FONT_SIZE_SMALL, dock_col)

	# Corners + scanline
	draw_corners(Rect2(15, 15, s.x - 30, s.y - 30), 15.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_content()


func _on_language_changed(_lang: String) -> void:
	screen_title = Locale.t("screen.market")
	_tab_bar.tabs = _get_tab_names()
	queue_redraw()


func _get_tab_names() -> Array[String]:
	return [
		Locale.t("market.tab.browse"),
		Locale.t("market.tab.sell"),
		Locale.t("market.tab.my_listings"),
	]
