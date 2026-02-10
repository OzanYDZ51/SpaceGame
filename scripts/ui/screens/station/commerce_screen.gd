class_name CommerceScreen
extends UIScreen

# =============================================================================
# Commerce Screen - Hub with category sidebar + content area
# Left: 3 category buttons (CHANTIER NAVAL / ARMURERIE / EQUIPEMENTS)
# Right: Active view (ShipShopView / EquipmentShopView)
# Bottom: Credits display
# =============================================================================

signal commerce_closed

var commerce_manager: CommerceManager = null
var station_type: int = 0  # StationData.StationType value
var station_name: String = "STATION"

var _sidebar_buttons: Array[UIButton] = []
var _active_view: Control = null
var _ship_shop: ShipShopView = null
var _equipment_shop: EquipmentShopView = null
var _back_btn: UIButton = null
var _current_category: int = -1

const SIDEBAR_W := 180.0
const CONTENT_TOP := 65.0
const BOTTOM_H := 50.0
const CATEGORIES: Array[Array] = [
	["CHANTIER NAVAL", "Acheter des vaisseaux"],
	["ARMURERIE", "Armes et tourelles"],
	["EQUIPEMENTS", "Boucliers, moteurs, modules"],
]


func _ready() -> void:
	screen_title = "COMMERCE"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Category buttons
	for i in CATEGORIES.size():
		var btn := UIButton.new()
		btn.text = CATEGORIES[i][0]
		btn.visible = false
		btn.pressed.connect(_on_category_pressed.bind(i))
		add_child(btn)
		_sidebar_buttons.append(btn)

	# Back button
	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.WARNING
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	# Create views (created once, shown/hidden)
	_ship_shop = ShipShopView.new()
	_ship_shop.visible = false
	_ship_shop.ship_purchased.connect(_on_ship_purchased)
	add_child(_ship_shop)

	_equipment_shop = EquipmentShopView.new()
	_equipment_shop.visible = false
	add_child(_equipment_shop)


func setup(mgr: CommerceManager, stype: int, sname: String) -> void:
	commerce_manager = mgr
	station_type = stype
	station_name = sname
	screen_title = "COMMERCE — " + sname.to_upper()
	if _ship_shop:
		_ship_shop.setup(mgr, stype)
	if _equipment_shop:
		_equipment_shop.setup(mgr, stype)


func _on_opened() -> void:
	_layout_controls()
	for btn in _sidebar_buttons:
		btn.visible = true
	_back_btn.visible = true
	# Default to ship shop
	_switch_to_category(0)


func _on_closed() -> void:
	for btn in _sidebar_buttons:
		btn.visible = false
	_back_btn.visible = false
	_hide_all_views()
	_current_category = -1
	commerce_closed.emit()


func _on_category_pressed(idx: int) -> void:
	_switch_to_category(idx)


func _on_back_pressed() -> void:
	close()


func _on_ship_purchased(_ship_id: StringName) -> void:
	# Refresh ship shop after purchase (credits changed)
	_switch_to_category(0)


func _switch_to_category(idx: int) -> void:
	_current_category = idx
	_hide_all_views()
	# Update button highlights
	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].accent_color = UITheme.PRIMARY if i == idx else UITheme.TEXT_DIM

	match idx:
		0:  # Ship shop
			_ship_shop.visible = true
			_active_view = _ship_shop
			_ship_shop.refresh()
		1:  # Weapons
			_equipment_shop.set_initial_tab(0)
			_equipment_shop.visible = true
			_active_view = _equipment_shop
			_equipment_shop.refresh()
		2:  # Shields/engines/modules
			_equipment_shop.set_initial_tab(1)
			_equipment_shop.visible = true
			_active_view = _equipment_shop
			_equipment_shop.refresh()
	_layout_content_area()
	queue_redraw()


func _hide_all_views() -> void:
	if _ship_shop: _ship_shop.visible = false
	if _equipment_shop: _equipment_shop.visible = false
	_active_view = null


func _layout_controls() -> void:
	var s := size
	var sidebar_x: float = 30.0
	var btn_w: float = SIDEBAR_W - 20.0
	var btn_h: float = 30.0
	var btn_gap: float = 6.0
	var btn_y: float = CONTENT_TOP + 20.0

	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].position = Vector2(sidebar_x, btn_y + i * (btn_h + btn_gap))
		_sidebar_buttons[i].size = Vector2(btn_w, btn_h)

	# Back button at bottom of sidebar
	_back_btn.position = Vector2(sidebar_x, s.y - BOTTOM_H - 35.0)
	_back_btn.size = Vector2(btn_w, btn_h)

	_layout_content_area()


func _layout_content_area() -> void:
	if _active_view == null: return
	var s := size
	var content_x: float = SIDEBAR_W + 10.0
	var content_y: float = CONTENT_TOP + 5.0
	var content_w: float = s.x - content_x - 20.0
	var content_h: float = s.y - content_y - BOTTOM_H - 10.0
	_active_view.position = Vector2(content_x, content_y)
	_active_view.size = Vector2(content_w, content_h)


func _draw() -> void:
	var s := size
	# Dark background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.85))

	# Title
	_draw_title(s)

	if not _is_open: return

	var font: Font = UITheme.get_font()

	# Sidebar background
	draw_rect(Rect2(20, CONTENT_TOP, SIDEBAR_W, s.y - CONTENT_TOP - BOTTOM_H),
		Color(0.02, 0.04, 0.06, 0.6))

	# Sidebar/content separator
	draw_line(Vector2(SIDEBAR_W + 5, CONTENT_TOP), Vector2(SIDEBAR_W + 5, s.y - BOTTOM_H),
		UITheme.BORDER, 1.0)

	# Bottom bar
	draw_rect(Rect2(0, s.y - BOTTOM_H, s.x, BOTTOM_H), Color(0.01, 0.02, 0.04, 0.7))
	draw_line(Vector2(0, s.y - BOTTOM_H), Vector2(s.x, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Credits display
	if commerce_manager and commerce_manager.player_economy:
		var credits_text := "Credits: " + PriceCatalog.format_price(commerce_manager.player_economy.credits)
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
	var scan_col := Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _process(_delta: float) -> void:
	if _is_open:
		queue_redraw()
