class_name CorporationScreen
extends UIScreen

# =============================================================================
# Corporation Screen - Main shell with UITabBar + 6 tab panels
# Rich holographic frame with decorative borders and glow effects
# Switches between corporation view (tabs) and no-corporation view (create/join)
# =============================================================================

var _tab_bar: UITabBar = null
var _tabs: Array[UIComponent] = []
var _no_corporation_view: NoCorporationView = null
var _corporation_manager = null

var TAB_NAMES: Array = []


func _ready() -> void:
	screen_title = Locale.t("screen.corporation")
	screen_mode = ScreenMode.FULLSCREEN
	super._ready()

	# Tab bar
	TAB_NAMES = [Locale.t("tab.overview"), Locale.t("tab.members"), Locale.t("tab.ranks"), Locale.t("tab.diplomacy"), Locale.t("tab.properties"), Locale.t("tab.log")]
	_tab_bar = UITabBar.new()
	_tab_bar.tabs.assign(TAB_NAMES)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	# Create the 6 tab panels
	var overview = CorporationTabOverview.new()
	var members_tab = CorporationTabMembers.new()
	var ranks = CorporationTabRanks.new()
	var diplo = CorporationTabDiplomacy.new()
	var treasury = CorporationTabProperties.new()
	var log_tab = CorporationTabLog.new()

	_tabs = [overview, members_tab, ranks, diplo, treasury, log_tab]
	for tab in _tabs:
		tab.visible = false
		add_child(tab)
	_tabs[0].visible = true

	# No-corporation view (create/join)
	_no_corporation_view = NoCorporationView.new()
	_no_corporation_view.visible = false
	_no_corporation_view.corporation_action_completed.connect(_on_corporation_action_completed)
	add_child(_no_corporation_view)


func _on_opened() -> void:
	_corporation_manager = GameManager.get_node_or_null("CorporationManager")
	if _corporation_manager == null:
		push_warning("CorporationScreen: CorporationManager not found")
		return

	# Connect corporation_loaded for live updates (connect only once)
	if not _corporation_manager.corporation_loaded.is_connected(_on_corporation_data_refreshed):
		_corporation_manager.corporation_loaded.connect(_on_corporation_data_refreshed)

	# Show current state immediately, then refresh
	_update_view()

	# Refresh from backend if authenticated (awaited for correct view)
	if AuthManager.is_authenticated:
		await _corporation_manager.refresh_from_backend()
		_update_view()


func _on_closed() -> void:
	if _corporation_manager and _corporation_manager.corporation_loaded.is_connected(_on_corporation_data_refreshed):
		_corporation_manager.corporation_loaded.disconnect(_on_corporation_data_refreshed)


func _update_view() -> void:
	if _corporation_manager == null:
		return

	var has_corporation: bool = _corporation_manager.has_corporation()

	# Toggle between corporation tabs and no-corporation view
	_tab_bar.visible = has_corporation
	for tab in _tabs:
		tab.visible = false
	_no_corporation_view.visible = not has_corporation

	if has_corporation:
		screen_title = Locale.t("corp.header_with_tag") % [_corporation_manager.corporation_data.corporation_name, _corporation_manager.corporation_data.corporation_tag]
		# Show the currently selected tab
		var current_tab: int = _tab_bar.current_tab if _tab_bar.current_tab >= 0 else 0
		if current_tab < _tabs.size():
			_tabs[current_tab].visible = true
		for tab in _tabs:
			if tab.has_method("refresh"):
				tab.call("refresh", _corporation_manager)
	else:
		screen_title = Locale.t("screen.corporation")
		_no_corporation_view.refresh(_corporation_manager)

	queue_redraw()


func _on_corporation_data_refreshed() -> void:
	_update_view()


func _on_corporation_action_completed() -> void:
	# Called when create/join succeeds from the no-corporation view
	_update_view()


func _on_tab_changed(index: int) -> void:
	for i in _tabs.size():
		_tabs[i].visible = (i == index)
	if _corporation_manager and _tabs[index].has_method("refresh"):
		_tabs[index].call("refresh", _corporation_manager)


func _process(_delta: float) -> void:
	if not visible:
		return

	var margin: float = UITheme.MARGIN_SCREEN + 8
	var tab_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	var content_y: float = tab_y + 40

	if _tab_bar.visible:
		_tab_bar.position = Vector2(margin, tab_y)
		_tab_bar.size = Vector2(size.x - margin * 2, 34)

	for tab in _tabs:
		tab.position = Vector2(margin, content_y)
		tab.size = Vector2(size.x - margin * 2, size.y - content_y - margin)

	if _no_corporation_view.visible:
		_no_corporation_view.position = Vector2(margin, content_y)
		_no_corporation_view.size = Vector2(size.x - margin * 2, size.y - content_y - margin)


func _draw() -> void:
	super._draw()

	var margin: float = UITheme.MARGIN_SCREEN + 8
	var tab_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	var content_y: float = tab_y + 40
	var content_rect = Rect2(margin - 2, content_y - 2, size.x - (margin - 2) * 2, size.y - content_y - margin + 4)

	# Content area outer frame
	draw_rect(content_rect, UITheme.BORDER, false, 1.0)
	draw_corners(content_rect, 16.0, UITheme.PRIMARY)

	# Subtle glow line under tab bar
	var glow_col = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12)
	draw_rect(Rect2(margin, content_y - 2, size.x - margin * 2, 2), glow_col)

	# Outer frame glow (faint)
	var outer = Rect2(margin - 6, tab_y - 4, size.x - (margin - 6) * 2, size.y - tab_y - margin + 8)
	var pulse: float = UITheme.get_pulse(0.5)
	var outer_col = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03 + pulse * 0.02)
	draw_rect(outer, outer_col, false, 2.0)
