class_name ShipyardScreen
extends UIScreen

# =============================================================================
# Shipyard Screen - Buy and sell ships (standalone station service)
# Left: 2 tab buttons (ACHETER / VENDRE)
# Right: Active view (ShipShopView / SellShipView)
# Bottom: Credits display
# =============================================================================

signal shipyard_closed

var commerce_manager = null
var station_type: int = 0
var station_name: String = "STATION"
var station_id: String = ""

var _sidebar_buttons: Array[UIButton] = []
var _active_view: Control = null
var _ship_shop: ShipShopView = null
var _sell_ship: SellShipView = null
var _back_btn: UIButton = null
var _current_tab: int = -1

const SIDEBAR_W =180.0
const CONTENT_TOP =65.0
const BOTTOM_H =50.0
const SECTION_HEADER_H =22.0
const TABS: Array[Array] = [
	["ACHETER", "Acheter des vaisseaux"],
	["VENDRE", "Vendre un vaisseau"],
]


func _ready() -> void:
	screen_title = "CHANTIER NAVAL"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	for i in TABS.size():
		var btn =UIButton.new()
		btn.text = TABS[i][0]
		btn.visible = false
		btn.pressed.connect(_on_tab_pressed.bind(i))
		add_child(btn)
		_sidebar_buttons.append(btn)

	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.WARNING
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	_ship_shop = ShipShopView.new()
	_ship_shop.visible = false
	_ship_shop.ship_purchased.connect(_on_ship_purchased)
	add_child(_ship_shop)

	_sell_ship = SellShipView.new()
	_sell_ship.visible = false
	add_child(_sell_ship)


func setup(mgr, stype: int, sname: String, sid: String = "") -> void:
	commerce_manager = mgr
	station_type = stype
	station_name = sname
	station_id = sid
	screen_title = "CHANTIER NAVAL — " + sname.to_upper()
	if _ship_shop:
		_ship_shop.setup(mgr, stype)
	if _sell_ship:
		_sell_ship.setup(mgr, sid)


func _on_opened() -> void:
	_layout_controls()
	for btn in _sidebar_buttons:
		btn.visible = true
	_back_btn.visible = true
	_switch_to_tab(0)


func _on_closed() -> void:
	for btn in _sidebar_buttons:
		btn.visible = false
	_back_btn.visible = false
	_hide_all_views()
	_current_tab = -1
	shipyard_closed.emit()


func _on_tab_pressed(idx: int) -> void:
	_switch_to_tab(idx)


func _on_back_pressed() -> void:
	close()


func _on_ship_purchased(_ship_id: StringName) -> void:
	_switch_to_tab(0)


func _switch_to_tab(idx: int) -> void:
	_current_tab = idx
	_hide_all_views()
	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].accent_color = UITheme.PRIMARY if i == idx else UITheme.TEXT_DIM

	match idx:
		0:
			_ship_shop.visible = true
			_active_view = _ship_shop
			_ship_shop.refresh()
		1:
			_sell_ship.visible = true
			_active_view = _sell_ship
			_sell_ship.refresh()
	_layout_content_area()
	queue_redraw()


func _hide_all_views() -> void:
	if _ship_shop: _ship_shop.visible = false
	if _sell_ship: _sell_ship.visible = false
	_active_view = null


func _layout_controls() -> void:
	var s =size
	var sidebar_x: float = 30.0
	var btn_w: float = SIDEBAR_W - 20.0
	var btn_h: float = 28.0
	var btn_gap: float = 4.0
	var y: float = CONTENT_TOP + 14.0

	y += SECTION_HEADER_H
	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].position = Vector2(sidebar_x, y)
		_sidebar_buttons[i].size = Vector2(btn_w, btn_h)
		y += btn_h + btn_gap

	_back_btn.position = Vector2(sidebar_x, s.y - BOTTOM_H - 35.0)
	_back_btn.size = Vector2(btn_w, btn_h)

	_layout_content_area()


func _layout_content_area() -> void:
	if _active_view == null: return
	var s =size
	var content_x: float = SIDEBAR_W + 10.0
	var content_y: float = CONTENT_TOP + 5.0
	var content_w: float = s.x - content_x - 20.0
	var content_h: float = s.y - content_y - BOTTOM_H - 10.0
	_active_view.position = Vector2(content_x, content_y)
	_active_view.size = Vector2(content_w, content_h)


func _draw() -> void:
	var s =size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.85))

	_draw_title(s)

	if not _is_open: return

	var font: Font = UITheme.get_font()

	# Sidebar background
	draw_rect(Rect2(20, CONTENT_TOP, SIDEBAR_W, s.y - CONTENT_TOP - BOTTOM_H),
		Color(0.02, 0.04, 0.06, 0.6))

	# Section header
	_draw_section_header(font)

	# Sidebar/content separator
	draw_line(Vector2(SIDEBAR_W + 5, CONTENT_TOP), Vector2(SIDEBAR_W + 5, s.y - BOTTOM_H),
		UITheme.BORDER, 1.0)

	# Bottom bar
	draw_rect(Rect2(0, s.y - BOTTOM_H, s.x, BOTTOM_H), Color(0.01, 0.02, 0.04, 0.7))
	draw_line(Vector2(0, s.y - BOTTOM_H), Vector2(s.x, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Credits display
	if commerce_manager and commerce_manager.player_economy:
		var credits_text ="Credits: " + PriceCatalog.format_price(commerce_manager.player_economy.credits)
		draw_string(font, Vector2(SIDEBAR_W + 20, s.y - 18),
			credits_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Corner decorations
	var m: float = 20.0
	var cl: float = 15.0
	var cc: Color = UITheme.CORNER
	draw_line(Vector2(m, m), Vector2(m + cl, m), cc, 1.5)
	draw_line(Vector2(m, m), Vector2(m, m + cl), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), cc, 1.5)

	# Scanline
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col =Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _draw_section_header(font: Font) -> void:
	if _sidebar_buttons.is_empty():
		return
	var lx: float = 28.0
	var rx: float = SIDEBAR_W - 2.0

	var first_btn =_sidebar_buttons[0]
	var header_y: float = first_btn.position.y - SECTION_HEADER_H + 2.0
	draw_rect(Rect2(lx, header_y, 3, 12), UITheme.PRIMARY)
	draw_string(font, Vector2(lx + 8, header_y + 11), "CHANTIER NAVAL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
	var text_w: float = font.get_string_size("CHANTIER NAVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x
	draw_line(Vector2(lx + 12 + text_w, header_y + 7),
		Vector2(rx, header_y + 7),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.25), 1.0)

	var last_btn =_sidebar_buttons[_sidebar_buttons.size() - 1]
	var section_bottom: float = last_btn.position.y + last_btn.size.y + 4
	draw_rect(Rect2(22, header_y - 2, SIDEBAR_W - 4, section_bottom - header_y + 4),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03))


func _process(_delta: float) -> void:
	if _is_open:
		queue_redraw()
