class_name ShipyardScreen
extends UIScreen

# =============================================================================
# Shipyard Screen — Card-based hub with 2 large cards (ACHETER / VENDRE).
# Click a card → opens the corresponding sub-view fullscreen.
# =============================================================================

signal shipyard_closed

var commerce_manager = null
var station_type: int = 0
var station_name: String = "STATION"
var station_id: String = ""

var _active_view: Control = null
var _ship_shop: ShipShopView = null
var _sell_ship: SellShipView = null
var _current_tab: int = -1

# Hub card state
var _hovered_card: int = -1
var _flash: Dictionary = {}
var _back_hovered: bool = false
var _back_flash: float = 0.0
var _card_rects: Array[Rect2] = []
var _back_rect: Rect2 = Rect2()
var _in_hub: bool = true

# Back button for sub-views
var _view_back_btn: UIButton = null

const CARD_W: float = 200.0
const CARD_H: float = 130.0
const CARD_GAP: float = 16.0


func _ready() -> void:
	screen_title = "CHANTIER NAVAL"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	_ship_shop = ShipShopView.new()
	_ship_shop.visible = false
	_ship_shop.ship_purchased.connect(_on_ship_purchased)
	add_child(_ship_shop)

	_sell_ship = SellShipView.new()
	_sell_ship.visible = false
	add_child(_sell_ship)

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
	screen_title = "CHANTIER NAVAL — " + sname.to_upper()
	if _ship_shop:
		_ship_shop.setup(mgr, stype)
	if _sell_ship:
		_sell_ship.setup(mgr, sid)


func _on_opened() -> void:
	_show_hub()


func _on_closed() -> void:
	_hide_all_views()
	_view_back_btn.visible = false
	_in_hub = true
	_current_tab = -1
	shipyard_closed.emit()


func _on_ship_purchased(_ship_id: StringName) -> void:
	_show_hub()


func _show_hub() -> void:
	_in_hub = true
	_hide_all_views()
	_view_back_btn.visible = false
	_hovered_card = -1
	_back_hovered = false
	screen_title = "CHANTIER NAVAL — " + station_name.to_upper()
	queue_redraw()


func _return_to_hub() -> void:
	_show_hub()


func _switch_to_tab(idx: int) -> void:
	_current_tab = idx
	_in_hub = false
	_hide_all_views()
	_view_back_btn.visible = true

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


func _layout_content_area() -> void:
	if _active_view == null: return
	var s = size
	var margin: float = 30.0
	var top: float = 65.0
	var bottom: float = 50.0
	_active_view.position = Vector2(margin, top)
	_active_view.size = Vector2(s.x - margin * 2, s.y - top - bottom - 10.0)
	_view_back_btn.position = Vector2(margin, s.y - bottom - 30.0)
	_view_back_btn.size = Vector2(120, 28)


# =============================================================================
# HUB LAYOUT
# =============================================================================

func _compute_hub_layout() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5
	_card_rects.resize(2)

	var total_w: float = CARD_W * 2 + CARD_GAP
	var sx: float = cx - total_w * 0.5

	# Center cards vertically
	var total_h: float = 26.0 + CARD_H + 40.0 + 34.0
	var ideal_top: float = (s.y - total_h) * 0.42
	var y: float = maxf(90.0, ideal_top)

	# Section header Y
	y += 26.0

	_card_rects[0] = Rect2(sx, y, CARD_W, CARD_H)
	_card_rects[1] = Rect2(sx + CARD_W + CARD_GAP, y, CARD_W, CARD_H)

	var btn_w: float = total_w
	_back_rect = Rect2(cx - btn_w * 0.5, y + CARD_H + 40.0, btn_w, 34.0)


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

	# Credits
	if commerce_manager and commerce_manager.player_economy:
		var cr_text: String = PlayerEconomy.format_credits(commerce_manager.player_economy.credits) + " CR"
		draw_string(font, Vector2(s.x - 180, 55), cr_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 160, UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Section header
	var grid_w: float = CARD_W * 2 + CARD_GAP
	var grid_x: float = cx - grid_w * 0.5
	var header_y: float = _card_rects[0].position.y - 26.0
	draw_rect(Rect2(grid_x, header_y + 2, 3, UITheme.FONT_SIZE_LABEL), UITheme.PRIMARY)
	draw_string(font, Vector2(grid_x + 8, header_y + UITheme.FONT_SIZE_LABEL),
		"CHANTIER NAVAL", HORIZONTAL_ALIGNMENT_LEFT, grid_w - 8, UITheme.FONT_SIZE_LABEL, UITheme.PRIMARY)
	draw_line(Vector2(grid_x, header_y + UITheme.FONT_SIZE_LABEL + 4),
		Vector2(grid_x + grid_w, header_y + UITheme.FONT_SIZE_LABEL + 4), UITheme.BORDER, 1.0)

	# Card: ACHETER
	_draw_hub_card(_card_rects[0], "ACHETER", "Parcourir les vaisseaux disponibles", 0, UITheme.PRIMARY)
	# Card: VENDRE
	_draw_hub_card(_card_rects[1], "VENDRE", "Vendre vos vaisseaux de flotte", 1, UITheme.WARNING)

	# Separator + back button
	var sep_y: float = _back_rect.position.y - 12.0
	draw_line(Vector2(grid_x, sep_y), Vector2(grid_x + grid_w, sep_y), UITheme.BORDER, 1.0)
	_draw_back_button()

	# Corners + scanline
	draw_corners(Rect2(20, 20, s.x - 40, s.y - 40), 15.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


func _draw_hub_card(rect: Rect2, label: String, desc: String, idx: int, accent: Color) -> void:
	var hovered: bool = _hovered_card == idx
	var flash_v: float = _flash.get(idx, 0.0)
	var font: Font = UITheme.get_font()

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
	draw_corners(rect, 8.0, bcol)

	# Icon
	var ic: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 40.0)
	if idx == 0:
		# Ship chevron (buy)
		var r: float = 16.0
		draw_line(ic + Vector2(0, -r), ic + Vector2(-r * 0.8, r * 0.6), accent, 1.5)
		draw_line(ic + Vector2(0, -r), ic + Vector2(r * 0.8, r * 0.6), accent, 1.5)
		draw_line(ic + Vector2(-r * 0.8, r * 0.6), ic + Vector2(0, r * 0.15), accent, 1.5)
		draw_line(ic + Vector2(r * 0.8, r * 0.6), ic + Vector2(0, r * 0.15), accent, 1.5)
	else:
		# Credits symbol (sell)
		var r: float = 14.0
		draw_arc(ic, r, 0, TAU, 16, accent, 1.5)
		draw_string(font, Vector2(ic.x - 6, ic.y + 5), "CR",
			HORIZONTAL_ALIGNMENT_LEFT, 12, UITheme.FONT_SIZE_TINY, accent)

	# Label
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 78),
		label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)

	# Description
	draw_string(font, Vector2(rect.position.x + 8, rect.position.y + 100),
		desc, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


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
	var bottom_h: float = 50.0
	draw_rect(Rect2(0, s.y - bottom_h, s.x, bottom_h), Color(0.01, 0.02, 0.04, 0.7))
	draw_line(Vector2(0, s.y - bottom_h), Vector2(s.x, s.y - bottom_h), UITheme.BORDER, 1.0)
	if commerce_manager and commerce_manager.player_economy:
		var credits_text = "Credits: " + PriceCatalog.format_price(commerce_manager.player_economy.credits)
		draw_string(font, Vector2(180, s.y - 18), credits_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)
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
		var close_x: float = size.x - UITheme.MARGIN_SCREEN - 28
		var close_y: float = UITheme.MARGIN_SCREEN
		if Rect2(close_x, close_y, 32, 28).has_point(event.position):
			close()
			accept_event()
			return

		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				_flash[i] = 1.0
				_switch_to_tab(i)
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
