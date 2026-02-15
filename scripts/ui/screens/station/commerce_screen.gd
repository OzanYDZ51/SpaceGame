class_name CommerceScreen
extends UIScreen

# =============================================================================
# Commerce Screen - Hub with category sidebar + content area
# Left: 5 category buttons (buy + sell) with separator
# Right: Active view (EquipmentShopView / Sell views)
# Bottom: Credits display
# =============================================================================

signal commerce_closed

var commerce_manager = null
var station_type: int = 0  # StationData.StationType value
var station_name: String = "STATION"
var station_id: String = ""

var _sidebar_buttons: Array[UIButton] = []
var _active_view: Control = null
var _equipment_shop: EquipmentShopView = null
var _sell_equipment: SellEquipmentView = null
var _sell_cargo: SellCargoView = null
var _sell_resource: SellResourceView = null
var _back_btn: UIButton = null
var _current_category: int = -1

const SIDEBAR_W =180.0
const CONTENT_TOP =65.0
const BOTTOM_H =50.0
const BUY_COUNT =2      # first 2 categories are buy
const SECTION_HEADER_H =22.0  # height reserved for section label
const CATEGORIES: Array[Array] = [
	["ARMURERIE", "Armes et tourelles"],
	["EQUIPEMENTS", "Boucliers, moteurs, modules"],
	["VENDRE EQUIP.", "Vendre equipement"],
	["VENDRE CARGO", "Vendre cargaison"],
	["VENDRE MINERAIS", "Vendre minerais"],
]


func _ready() -> void:
	screen_title = "COMMERCE"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Category buttons
	for i in CATEGORIES.size():
		var btn =UIButton.new()
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
	_equipment_shop = EquipmentShopView.new()
	_equipment_shop.visible = false
	add_child(_equipment_shop)

	_sell_equipment = SellEquipmentView.new()
	_sell_equipment.visible = false
	add_child(_sell_equipment)

	_sell_cargo = SellCargoView.new()
	_sell_cargo.visible = false
	add_child(_sell_cargo)

	_sell_resource = SellResourceView.new()
	_sell_resource.visible = false
	add_child(_sell_resource)


func setup(mgr, stype: int, sname: String, sid: String = "") -> void:
	commerce_manager = mgr
	station_type = stype
	station_name = sname
	station_id = sid
	screen_title = "COMMERCE — " + sname.to_upper()
	if _equipment_shop:
		_equipment_shop.setup(mgr, stype)
	if _sell_equipment:
		_sell_equipment.setup(mgr)
	if _sell_cargo:
		_sell_cargo.setup(mgr, sid)
	if _sell_resource:
		_sell_resource.setup(mgr, sid)


func _on_opened() -> void:
	_layout_controls()
	for btn in _sidebar_buttons:
		btn.visible = true
	_back_btn.visible = true
	# Default to weapons (ARMURERIE)
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


func _switch_to_category(idx: int) -> void:
	_current_category = idx
	_hide_all_views()
	# Update button highlights
	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].accent_color = UITheme.PRIMARY if i == idx else UITheme.TEXT_DIM

	match idx:
		0:  # Weapons
			_equipment_shop.set_initial_tab(0)
			_equipment_shop.visible = true
			_active_view = _equipment_shop
			_equipment_shop.refresh()
		1:  # Shields/engines/modules
			_equipment_shop.set_initial_tab(1)
			_equipment_shop.visible = true
			_active_view = _equipment_shop
			_equipment_shop.refresh()
		2:  # Sell equipment
			_sell_equipment.visible = true
			_active_view = _sell_equipment
			_sell_equipment.refresh()
		3:  # Sell cargo
			_sell_cargo.visible = true
			_active_view = _sell_cargo
			_sell_cargo.refresh()
		4:  # Sell resources
			_sell_resource.visible = true
			_active_view = _sell_resource
			_sell_resource.refresh()
	_layout_content_area()
	queue_redraw()


func _hide_all_views() -> void:
	if _equipment_shop: _equipment_shop.visible = false
	if _sell_equipment: _sell_equipment.visible = false
	if _sell_cargo: _sell_cargo.visible = false
	if _sell_resource: _sell_resource.visible = false
	_active_view = null


func _layout_controls() -> void:
	var s =size
	var sidebar_x: float = 30.0
	var btn_w: float = SIDEBAR_W - 20.0
	var btn_h: float = 28.0
	var btn_gap: float = 4.0
	var y: float = CONTENT_TOP + 14.0

	# "ACHETER" section header space
	y += SECTION_HEADER_H
	for i in BUY_COUNT:
		_sidebar_buttons[i].position = Vector2(sidebar_x, y)
		_sidebar_buttons[i].size = Vector2(btn_w, btn_h)
		y += btn_h + btn_gap

	# Gap between sections
	y += 10.0

	# "VENDRE" section header space
	y += SECTION_HEADER_H
	for i in range(BUY_COUNT, _sidebar_buttons.size()):
		_sidebar_buttons[i].position = Vector2(sidebar_x, y)
		_sidebar_buttons[i].size = Vector2(btn_w, btn_h)
		y += btn_h + btn_gap

	# Back button at bottom of sidebar
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
	# Dark background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.85))

	# Title
	_draw_title(s)

	if not _is_open: return

	var font: Font = UITheme.get_font()

	# Sidebar background
	draw_rect(Rect2(20, CONTENT_TOP, SIDEBAR_W, s.y - CONTENT_TOP - BOTTOM_H),
		Color(0.02, 0.04, 0.06, 0.6))

	# Section headers
	_draw_section_headers(font)

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


func _draw_section_headers(font: Font) -> void:
	if _sidebar_buttons.is_empty():
		return
	var lx: float = 28.0
	var rx: float = SIDEBAR_W - 2.0

	# --- "ACHETER" header above first buy button ---
	var buy_btn =_sidebar_buttons[0]
	var buy_header_y: float = buy_btn.position.y - SECTION_HEADER_H + 2.0
	# Accent bar
	draw_rect(Rect2(lx, buy_header_y, 3, 12), UITheme.PRIMARY)
	# Label
	draw_string(font, Vector2(lx + 8, buy_header_y + 11), "ACHETER",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
	# Decorative line extending right
	var buy_text_w: float = font.get_string_size("ACHETER", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x
	draw_line(Vector2(lx + 12 + buy_text_w, buy_header_y + 7),
		Vector2(rx, buy_header_y + 7),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.25), 1.0)
	# Subtle glow bg behind buy section
	var buy_last =_sidebar_buttons[BUY_COUNT - 1]
	var buy_section_bottom: float = buy_last.position.y + buy_last.size.y + 4
	draw_rect(Rect2(22, buy_header_y - 2, SIDEBAR_W - 4, buy_section_bottom - buy_header_y + 4),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03))

	# --- "VENDRE" header above first sell button ---
	if BUY_COUNT < _sidebar_buttons.size():
		var sell_btn =_sidebar_buttons[BUY_COUNT]
		var sell_header_y: float = sell_btn.position.y - SECTION_HEADER_H + 2.0
		# Accent bar (red/danger for sell)
		var sell_col =UITheme.WARNING
		draw_rect(Rect2(lx, sell_header_y, 3, 12), sell_col)
		# Label
		draw_string(font, Vector2(lx + 8, sell_header_y + 11), "VENDRE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, sell_col)
		# Decorative line
		var sell_text_w: float = font.get_string_size("VENDRE", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x
		draw_line(Vector2(lx + 12 + sell_text_w, sell_header_y + 7),
			Vector2(rx, sell_header_y + 7),
			Color(sell_col.r, sell_col.g, sell_col.b, 0.25), 1.0)
		# Subtle glow bg behind sell section
		var sell_last =_sidebar_buttons[_sidebar_buttons.size() - 1]
		var sell_section_bottom: float = sell_last.position.y + sell_last.size.y + 4
		draw_rect(Rect2(22, sell_header_y - 2, SIDEBAR_W - 4, sell_section_bottom - sell_header_y + 4),
			Color(sell_col.r, sell_col.g, sell_col.b, 0.03))

		# Separator line between sections
		var sep_y: float = (buy_section_bottom + sell_header_y - 4) * 0.5
		draw_line(Vector2(lx + 10, sep_y), Vector2(rx - 10, sep_y),
			Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.3), 1.0)
		# Small diamond decoration at separator center
		var cx: float = (lx + rx) * 0.5
		var diamond =PackedVector2Array([
			Vector2(cx, sep_y - 3), Vector2(cx + 3, sep_y),
			Vector2(cx, sep_y + 3), Vector2(cx - 3, sep_y)])
		draw_colored_polygon(diamond, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.4))


func _process(_delta: float) -> void:
	if _is_open:
		queue_redraw()
