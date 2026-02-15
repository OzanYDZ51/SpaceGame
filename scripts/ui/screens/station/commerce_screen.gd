class_name CommerceScreen
extends UIScreen

# =============================================================================
# Commerce Screen — Card-based hub with category tiles (like station_screen).
# Categories: ACHETER (2 cards), VENDRE (3 cards)
# Click a card → opens the corresponding sub-view fullscreen.
# =============================================================================

signal commerce_closed

var commerce_manager = null
var station_type: int = 0
var station_name: String = "STATION"
var station_id: String = ""

var _active_view: Control = null
var _equipment_shop: EquipmentShopView = null
var _sell_equipment: SellEquipmentView = null
var _sell_cargo: SellCargoView = null
var _sell_resource: SellResourceView = null
var _current_category: int = -1

# Hub card state
var _hovered_card: int = -1
var _flash: Dictionary = {}
var _back_hovered: bool = false
var _back_flash: float = 0.0
var _card_rects: Array[Rect2] = []
var _cat_header_y: PackedFloat32Array = PackedFloat32Array()
var _back_rect: Rect2 = Rect2()
var _in_hub: bool = true

# Back button for sub-views
var _view_back_btn: UIButton = null

const CARD_W: float = 150.0
const CARD_H: float = 105.0
const CARD_GAP: float = 12.0

enum ICO { ARMURERIE, EQUIPEMENTS, SELL_EQUIP, SELL_CARGO, SELL_MINERAI }

const CARDS: Array[Dictionary] = [
	{label = "ARMURERIE", desc = "Armes et tourelles", icon = ICO.ARMURERIE, cat = 0, view_idx = 0},
	{label = "EQUIPEMENTS", desc = "Boucliers, moteurs, modules", icon = ICO.EQUIPEMENTS, cat = 0, view_idx = 1},
	{label = "EQUIPEMENT", desc = "Vendre equipement", icon = ICO.SELL_EQUIP, cat = 1, view_idx = 2},
	{label = "CARGO", desc = "Vendre cargaison", icon = ICO.SELL_CARGO, cat = 1, view_idx = 3},
	{label = "MINERAIS", desc = "Vendre minerais", icon = ICO.SELL_MINERAI, cat = 1, view_idx = 4},
]
const CAT_LABELS: PackedStringArray = ["ACHETER", "VENDRE"]


func _ready() -> void:
	screen_title = "COMMERCE"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

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

	# Back button for sub-views
	_view_back_btn = UIButton.new()
	_view_back_btn.text = "RETOUR"
	_view_back_btn.accent_color = UITheme.WARNING
	_view_back_btn.visible = false
	_view_back_btn.pressed.connect(_return_to_hub)
	add_child(_view_back_btn)


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
	_show_hub()


func _on_closed() -> void:
	_hide_all_views()
	_view_back_btn.visible = false
	_in_hub = true
	_current_category = -1
	commerce_closed.emit()


func _show_hub() -> void:
	_in_hub = true
	_hide_all_views()
	_view_back_btn.visible = false
	_hovered_card = -1
	_back_hovered = false
	screen_title = "COMMERCE — " + station_name.to_upper()
	queue_redraw()


func _return_to_hub() -> void:
	_show_hub()


func _switch_to_category(idx: int) -> void:
	_current_category = idx
	_in_hub = false
	_hide_all_views()
	_view_back_btn.visible = true

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


func _layout_content_area() -> void:
	if _active_view == null: return
	var s = size
	var margin: float = 30.0
	var top: float = 65.0
	var bottom: float = 50.0
	_active_view.position = Vector2(margin, top)
	_active_view.size = Vector2(s.x - margin * 2, s.y - top - bottom - 10.0)
	# Back button at bottom-left
	_view_back_btn.position = Vector2(margin, s.y - bottom - 30.0)
	_view_back_btn.size = Vector2(120, 28)


# =============================================================================
# HUB LAYOUT
# =============================================================================

func _compute_hub_layout() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5
	_card_rects.resize(CARDS.size())
	_cat_header_y.resize(CAT_LABELS.size())

	# Calculate total content height for centering
	var total_h: float = 2 * 26.0 + 2 * CARD_H + 14.0 + 40.0 + 34.0
	var min_top: float = 90.0
	var ideal_top: float = (s.y - total_h) * 0.42
	var y: float = maxf(min_top, ideal_top)

	var current_cat: int = -1
	var row_start: int = 0

	for i in CARDS.size():
		var cat: int = CARDS[i].cat
		if cat != current_cat:
			if i > row_start:
				_place_row(row_start, i, cx, y)
				y += CARD_H + 14.0
			_cat_header_y[cat] = y
			y += 26.0
			current_cat = cat
			row_start = i

	if CARDS.size() > row_start:
		_place_row(row_start, CARDS.size(), cx, y)
		y += CARD_H

	var btn_w: float = minf(CARD_W * 3.0 + CARD_GAP * 2.0, s.x - 100.0)
	_back_rect = Rect2(cx - btn_w * 0.5, y + 40.0, btn_w, 34.0)


func _place_row(from: int, to: int, cx: float, y: float) -> void:
	var count: int = to - from
	var total_w: float = count * CARD_W + (count - 1) * CARD_GAP
	var sx: float = cx - total_w * 0.5
	for j in count:
		_card_rects[from + j] = Rect2(sx + j * (CARD_W + CARD_GAP), y, CARD_W, CARD_H)


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	var s = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.85))
	_draw_title(s)

	if not _is_open: return

	if _in_hub:
		_draw_hub(s)
	else:
		_draw_view_mode(s)


func _draw_hub(s: Vector2) -> void:
	_compute_hub_layout()
	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5

	# Credits display at top-right
	if commerce_manager and commerce_manager.player_economy:
		var cr_text: String = PlayerEconomy.format_credits(commerce_manager.player_economy.credits) + " CR"
		draw_string(font, Vector2(s.x - 180, 55), cr_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 160, UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Category headers
	var grid_w: float = CARD_W * 3.0 + CARD_GAP * 2.0
	var grid_x: float = cx - grid_w * 0.5
	for ci in CAT_LABELS.size():
		var header_col: Color = UITheme.PRIMARY if ci == 0 else UITheme.WARNING
		var hy: float = _cat_header_y[ci]
		draw_rect(Rect2(grid_x, hy + 2, 3, UITheme.FONT_SIZE_LABEL), header_col)
		draw_string(font, Vector2(grid_x + 8, hy + UITheme.FONT_SIZE_LABEL),
			CAT_LABELS[ci], HORIZONTAL_ALIGNMENT_LEFT, grid_w - 8, UITheme.FONT_SIZE_LABEL, header_col)
		var line_y: float = hy + UITheme.FONT_SIZE_LABEL + 4
		draw_line(Vector2(grid_x, line_y), Vector2(grid_x + grid_w, line_y), UITheme.BORDER, 1.0)

	# Cards
	for i in CARDS.size():
		_draw_hub_card(_card_rects[i], CARDS[i], i)

	# Separator + back button
	var sep_y: float = _back_rect.position.y - 12.0
	draw_line(Vector2(grid_x, sep_y), Vector2(grid_x + grid_w, sep_y), UITheme.BORDER, 1.0)
	_draw_back_button()

	# Screen corners + scanline
	draw_corners(Rect2(20, 20, s.x - 40, s.y - 40), 15.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


func _draw_hub_card(rect: Rect2, card: Dictionary, idx: int) -> void:
	var hovered: bool = _hovered_card == idx
	var flash_v: float = _flash.get(idx, 0.0)
	var is_buy: bool = card.cat == 0
	var accent: Color = UITheme.PRIMARY if is_buy else UITheme.WARNING

	# Background
	var bg: Color = Color(0.015, 0.04, 0.08, 0.88) if not hovered else Color(0.025, 0.06, 0.12, 0.92)
	draw_rect(rect, bg)

	if flash_v > 0.0:
		draw_rect(rect, Color(1, 1, 1, flash_v * 0.2))

	# Border
	var bcol: Color = UITheme.BORDER_ACTIVE if hovered else Color(accent.r, accent.g, accent.b, 0.4)
	draw_rect(rect, bcol, false, 1.0)

	# Top glow
	var ga: float = 0.25 if hovered else 0.12
	draw_line(Vector2(rect.position.x + 1, rect.position.y),
		Vector2(rect.end.x - 1, rect.position.y),
		Color(accent.r, accent.g, accent.b, ga), 2.0)

	# Mini corners
	draw_corners(rect, 8.0, bcol)

	# Icon
	var ic: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 32.0)
	_draw_hub_icon(ic, card.icon, accent)

	# Label
	var font: Font = UITheme.get_font()
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 62),
		card.label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Description
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 78),
		card.desc, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Category accent dot
	var dot_col: Color = UITheme.ACCENT if is_buy else UITheme.WARNING
	draw_circle(Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - 10), 2.5, dot_col)


func _draw_hub_icon(c: Vector2, icon: int, col: Color) -> void:
	var r: float = 12.0
	match icon:
		ICO.ARMURERIE:
			# Crosshair (weapons)
			draw_arc(c, r * 0.65, 0, TAU, 20, col, 1.5)
			draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.3), col, 1.0)
			draw_line(c + Vector2(0, r), c + Vector2(0, r * 0.3), col, 1.0)
			draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.3, 0), col, 1.0)
			draw_line(c + Vector2(r, 0), c + Vector2(r * 0.3, 0), col, 1.0)
			draw_circle(c, 2.0, col)
		ICO.EQUIPEMENTS:
			# Gear (shields/engines/modules)
			var pts: PackedVector2Array = []
			for k in 7:
				var a: float = TAU * float(k) / 6.0 - PI * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.8)
			draw_polyline(pts, col, 1.5)
			draw_arc(c, r * 0.3, 0, TAU, 10, col, 1.5)
		ICO.SELL_EQUIP:
			# Arrow down + gear
			draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.5), col, 1.5)
			draw_line(c + Vector2(-r * 0.4, r * 0.1), c + Vector2(0, r * 0.5), col, 1.5)
			draw_line(c + Vector2(r * 0.4, r * 0.1), c + Vector2(0, r * 0.5), col, 1.5)
			draw_arc(c + Vector2(0, -r * 0.3), r * 0.25, 0, TAU, 8, col, 1.0)
		ICO.SELL_CARGO:
			# Crate/box
			draw_rect(Rect2(c.x - r * 0.7, c.y - r * 0.6, r * 1.4, r * 1.2), col, false, 1.5)
			draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(r * 0.7, 0), col, 1.0)
			draw_line(c + Vector2(-r * 0.15, -r * 0.6), c + Vector2(-r * 0.15, r * 0.6), col, 1.0)
			draw_line(c + Vector2(r * 0.15, -r * 0.6), c + Vector2(r * 0.15, r * 0.6), col, 1.0)
		ICO.SELL_MINERAI:
			# Crystal/diamond
			draw_ore_crystal(c, r, col)


func _draw_back_button() -> void:
	var r: Rect2 = _back_rect
	var hov: bool = _back_hovered
	draw_rect(r, Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.18 if hov else 0.08))
	if _back_flash > 0.0:
		draw_rect(r, Color(1, 1, 1, _back_flash * 0.2))
	var bc: Color = UITheme.WARNING if hov else Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.45)
	draw_rect(r, bc, false, 1.0)
	draw_rect(Rect2(r.position.x, r.position.y + 2, 3, r.size.y - 4), UITheme.WARNING)
	draw_corners(r, 6.0, bc)
	var font: Font = UITheme.get_font()
	var ty: float = r.position.y + (r.size.y + UITheme.FONT_SIZE_BODY) * 0.5 - 1
	draw_string(font, Vector2(r.position.x, ty), "RETOUR",
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


func _draw_view_mode(s: Vector2) -> void:
	var font: Font = UITheme.get_font()

	# Bottom bar
	var bottom_h: float = 50.0
	draw_rect(Rect2(0, s.y - bottom_h, s.x, bottom_h), Color(0.01, 0.02, 0.04, 0.7))
	draw_line(Vector2(0, s.y - bottom_h), Vector2(s.x, s.y - bottom_h), UITheme.BORDER, 1.0)

	# Credits display
	if commerce_manager and commerce_manager.player_economy:
		var credits_text = "Credits: " + PriceCatalog.format_price(commerce_manager.player_economy.credits)
		draw_string(font, Vector2(180, s.y - 18),
			credits_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Corners + scanline
	draw_corners(Rect2(20, 20, s.x - 40, s.y - 40), 15.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


# =============================================================================
# INTERACTION
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if _in_hub:
		_hub_gui_input(event)
	else:
		super._gui_input(event)


func _hub_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old_h: int = _hovered_card
		var old_b: bool = _back_hovered
		_hovered_card = -1
		_back_hovered = false
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				_hovered_card = i
				break
		_back_hovered = _back_rect.has_point(event.position)
		if _hovered_card != old_h or _back_hovered != old_b:
			queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Check close button first
		var close_x: float = size.x - UITheme.MARGIN_SCREEN - 28
		var close_y: float = UITheme.MARGIN_SCREEN
		var close_rect := Rect2(close_x, close_y, 32, 28)
		if close_rect.has_point(event.position):
			close()
			accept_event()
			return

		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				_flash[i] = 1.0
				_switch_to_category(CARDS[i].view_idx)
				accept_event()
				return
		if _back_rect.has_point(event.position):
			_back_flash = 1.0
			close()
			accept_event()
			return

	accept_event()


func _process(delta: float) -> void:
	if _is_open:
		var dirty: bool = false
		for key in _flash.keys():
			_flash[key] = maxf(0.0, _flash[key] - delta / 0.12)
			if _flash[key] <= 0.0:
				_flash.erase(key)
			dirty = true
		if _back_flash > 0.0:
			_back_flash = maxf(0.0, _back_flash - delta / 0.12)
			dirty = true
		if dirty or not _in_hub:
			queue_redraw()
