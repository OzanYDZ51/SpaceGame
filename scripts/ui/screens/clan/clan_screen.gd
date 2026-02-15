class_name ClanScreen
extends UIScreen

# =============================================================================
# Clan Screen - Main shell with UITabBar + 6 tab panels
# Rich holographic frame with decorative borders and glow effects
# =============================================================================

var _tab_bar: UITabBar = null
var _tabs: Array[UIComponent] = []
var _clan_manager = null

const TAB_NAMES =["Vue d'ensemble", "Membres", "Rangs", "Diplomatie", "Tresor", "Log"]


func _ready() -> void:
	screen_title = "CLAN"
	screen_mode = ScreenMode.FULLSCREEN
	super._ready()

	# Tab bar
	_tab_bar = UITabBar.new()
	_tab_bar.tabs.assign(TAB_NAMES)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	# Create the 6 tab panels
	var overview =ClanTabOverview.new()
	var members_tab =ClanTabMembers.new()
	var ranks =ClanTabRanks.new()
	var diplo =ClanTabDiplomacy.new()
	var treasury =ClanTabTreasury.new()
	var log_tab =ClanTabLog.new()

	_tabs = [overview, members_tab, ranks, diplo, treasury, log_tab]
	for tab in _tabs:
		tab.visible = false
		add_child(tab)
	_tabs[0].visible = true


func _on_opened() -> void:
	_clan_manager = GameManager.get_node_or_null("ClanManager")
	if _clan_manager == null:
		push_warning("ClanScreen: ClanManager not found")
		return

	if _clan_manager.has_clan():
		screen_title = "CLAN: %s [%s]" % [_clan_manager.clan_data.clan_name, _clan_manager.clan_data.clan_tag]

	for tab in _tabs:
		if tab.has_method("refresh"):
			tab.call("refresh", _clan_manager)


func _on_tab_changed(index: int) -> void:
	for i in _tabs.size():
		_tabs[i].visible = (i == index)
	if _clan_manager and _tabs[index].has_method("refresh"):
		_tabs[index].call("refresh", _clan_manager)


func _process(_delta: float) -> void:
	if not visible:
		return

	var margin: float = UITheme.MARGIN_SCREEN + 8
	var tab_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	_tab_bar.position = Vector2(margin, tab_y)
	_tab_bar.size = Vector2(size.x - margin * 2, 34)

	var content_y: float = tab_y + 40
	for tab in _tabs:
		tab.position = Vector2(margin, content_y)
		tab.size = Vector2(size.x - margin * 2, size.y - content_y - margin)


func _draw() -> void:
	super._draw()

	var margin: float = UITheme.MARGIN_SCREEN + 8
	var tab_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	var content_y: float = tab_y + 40
	var content_rect =Rect2(margin - 2, content_y - 2, size.x - (margin - 2) * 2, size.y - content_y - margin + 4)

	# Content area outer frame
	draw_rect(content_rect, UITheme.BORDER, false, 1.0)
	draw_corners(content_rect, 16.0, UITheme.PRIMARY)

	# Subtle glow line under tab bar
	var glow_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12)
	draw_rect(Rect2(margin, content_y - 2, size.x - margin * 2, 2), glow_col)

	# Outer frame glow (faint)
	var outer =Rect2(margin - 6, tab_y - 4, size.x - (margin - 6) * 2, size.y - tab_y - margin + 8)
	var pulse: float = UITheme.get_pulse(0.5)
	var outer_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03 + pulse * 0.02)
	draw_rect(outer, outer_col, false, 2.0)
