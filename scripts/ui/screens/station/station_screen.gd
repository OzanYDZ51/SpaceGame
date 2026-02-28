class_name StationScreen
extends UIScreen

# =============================================================================
# Station Screen — Grid-based service terminal with category tiles, icons,
# and locked/unlocked card states. Locked services show price, unlocked glow.
# =============================================================================

signal undock_requested
signal equipment_requested
signal commerce_requested
signal repair_requested
signal shipyard_requested
signal refinery_requested
signal storage_requested
signal station_equipment_requested
signal administration_requested
signal missions_requested
signal market_requested

# --- Card grid constants ---
const CARD_W: float = 150.0
const CARD_H: float = 118.0
const CARD_GAP: float = 12.0

# --- State ---
var _station_name: String = "STATION"
var _emblem_pulse: float = 0.0
var _services = null
var _system_id: int = -1
var _station_idx: int = 0
var _economy = null

# Interaction
var _hovered_card: int = -1
var _flash: Dictionary = {}
var _undock_hovered: bool = false
var _undock_flash: float = 0.0

# Computed layout
var _card_rects: Array[Rect2] = []
var _cat_header_y: PackedFloat32Array = PackedFloat32Array()
var _undock_rect: Rect2 = Rect2()
var _emblem_center_y: float = 85.0

# Card data
var _cards: Array[Dictionary] = []
var _cat_labels: PackedStringArray = PackedStringArray()

enum ICO { COMMERCE, SHIPYARD, STORAGE, REPAIR, EQUIP, REFINERY, STN_EQUIP, ADMIN, MISSIONS, MARKET }


func _ready() -> void:
	screen_title = Locale.t("screen.station")
	screen_mode = ScreenMode.OVERLAY
	super._ready()
	_rebuild_labels()


func _rebuild_labels() -> void:
	_cat_labels = PackedStringArray([Locale.t("cat.trade"), Locale.t("cat.tech"), Locale.t("cat.station")])
	_cards = [
		{"svc": StationServices.Service.COMMERCE, "label": Locale.t("station.commerce"), "icon": ICO.COMMERCE, "cat": 0, "special": ""},
		{"svc": StationServices.Service.SHIPYARD, "label": Locale.t("station.shipyard"), "icon": ICO.SHIPYARD, "cat": 0, "special": ""},
		{"svc": StationServices.Service.ENTREPOT, "label": Locale.t("station.storage"), "icon": ICO.STORAGE, "cat": 0, "special": ""},
		{"svc": StationServices.Service.MARKET, "label": Locale.t("station.market"), "icon": ICO.MARKET, "cat": 0, "special": ""},
		{"svc": StationServices.Service.REPAIR, "label": Locale.t("station.repair"), "icon": ICO.REPAIR, "cat": 1, "special": ""},
		{"svc": StationServices.Service.EQUIPMENT, "label": Locale.t("station.equipment"), "icon": ICO.EQUIP, "cat": 1, "special": ""},
		{"svc": StationServices.Service.REFINERY, "label": Locale.t("station.refinery"), "icon": ICO.REFINERY, "cat": 1, "special": ""},
		{"svc": -1, "label": Locale.t("station.station_equip"), "icon": ICO.STN_EQUIP, "cat": 2, "special": "station_equip"},
		{"svc": -1, "label": Locale.t("station.administration"), "icon": ICO.ADMIN, "cat": 2, "special": "admin"},
		{"svc": -1, "label": Locale.t("station.missions"), "icon": ICO.MISSIONS, "cat": 2, "special": "missions"},
	]


func set_station_name(sname: String) -> void:
	_station_name = sname
	screen_title = sname.to_upper()


func setup(services, system_id: int, station_idx: int, economy) -> void:
	_services = services
	_system_id = system_id
	_station_idx = station_idx
	_economy = economy
	queue_redraw()


func _on_language_changed(_lang: String) -> void:
	_rebuild_labels()
	queue_redraw()


func _on_opened() -> void:
	_hovered_card = -1
	_undock_hovered = false
	queue_redraw()


func _on_closed() -> void:
	_hovered_card = -1
	_undock_hovered = false


func _process(delta: float) -> void:
	_emblem_pulse += delta
	var dirty: bool = false
	for key in _flash.keys():
		_flash[key] = maxf(0.0, _flash[key] - delta / 0.12)
		if _flash[key] <= 0.0:
			_flash.erase(key)
		dirty = true
	if _undock_flash > 0.0:
		_undock_flash = maxf(0.0, _undock_flash - delta / 0.12)
		dirty = true
	if dirty:
		queue_redraw()


func _is_unlocked(card: Dictionary) -> bool:
	if card["special"] != "":
		return true
	return _services != null and _services.is_unlocked(_system_id, _station_idx, card["svc"])


# =============================================================================
# LAYOUT
# =============================================================================

func _compute_layout() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5
	_card_rects.resize(_cards.size())
	_cat_header_y.resize(_cat_labels.size())

	# Calculate total content height first for vertical centering
	# 3 categories: headers (26 each) + 3 rows of cards (CARD_H+14 gap between rows)
	# + station header area (emblem+name ~60px above first card)
	var total_content_h: float = 60.0  # emblem + name
	total_content_h += 3 * 26.0  # 3 category headers
	total_content_h += 3 * CARD_H  # 3 rows of cards
	total_content_h += 2 * 14.0  # gaps between card rows
	total_content_h += 40.0 + 34.0  # undock gap + button

	# Dynamic vertical padding: center content or use minimum top
	var min_top: float = 100.0
	var ideal_top: float = (s.y - total_content_h) * 0.45
	var start_y: float = maxf(min_top, ideal_top)

	# Station emblem area starts at start_y, cards start after
	var y: float = start_y + 60.0
	var current_cat: int = -1
	var row_start: int = 0

	for i in _cards.size():
		var cat: int = _cards[i]["cat"]
		if cat != current_cat:
			if i > row_start:
				_place_row(row_start, i, cx, y)
				y += CARD_H + 14.0
			_cat_header_y[cat] = y
			y += 26.0
			current_cat = cat
			row_start = i

	if _cards.size() > row_start:
		_place_row(row_start, _cards.size(), cx, y)
		y += CARD_H

	var btn_w: float = minf(CARD_W * 3.0 + CARD_GAP * 2.0, s.x - 100.0)
	_undock_rect = Rect2(cx - btn_w * 0.5, y + 40.0, btn_w, 34.0)
	_emblem_center_y = start_y + 25.0


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
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))
	draw_rect(Rect2(0, 0, s.x, 50), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 40, s.x, 40), Color(0.0, 0.0, 0.02, 0.5))
	_draw_title(s)

	if not _is_open:
		return

	_compute_layout()
	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5

	# --- Station emblem + name ---
	_draw_station_emblem(Vector2(cx, _emblem_center_y), 20.0)
	var name_y: float = _emblem_center_y + 36.0
	draw_string(font, Vector2(0, name_y), _station_name.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	var unlocked_count: int = _services.get_unlocked_count(_system_id, _station_idx) if _services else 0
	draw_string(font, Vector2(0, name_y + 18), Locale.t("station.terminal") % unlocked_count,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# --- Category headers ---
	var grid_w: float = CARD_W * 3.0 + CARD_GAP * 2.0
	var grid_x: float = cx - grid_w * 0.5
	for ci in _cat_labels.size():
		draw_section_header(grid_x, _cat_header_y[ci], grid_w, _cat_labels[ci])

	# --- Cards ---
	for i in _cards.size():
		_draw_card(_card_rects[i], _cards[i], i)

	# --- Separator + undock ---
	var sep_y: float = _undock_rect.position.y - 12.0
	draw_line(Vector2(grid_x, sep_y), Vector2(grid_x + grid_w, sep_y), UITheme.BORDER, 1.0)
	_draw_undock()

	# --- Screen corners + scanline ---
	draw_corners(Rect2(30, 30, s.x - 60, s.y - 60), 20.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


func _draw_card(rect: Rect2, card: Dictionary, idx: int) -> void:
	var unlocked: bool = _is_unlocked(card)
	var hovered: bool = _hovered_card == idx
	var flash_v: float = _flash.get(idx, 0.0)
	var is_special: bool = card["special"] != ""

	# Background
	var bg: Color
	if unlocked:
		bg = Color(0.015, 0.04, 0.08, 0.88) if not hovered else Color(0.025, 0.06, 0.12, 0.92)
	else:
		bg = Color(0.01, 0.015, 0.03, 0.6) if not hovered else Color(0.02, 0.03, 0.06, 0.72)
	draw_rect(rect, bg)

	if flash_v > 0.0:
		draw_rect(rect, Color(1, 1, 1, flash_v * 0.2))

	# Border
	var bcol: Color
	if is_special:
		bcol = Color(0.5, 0.6, 1.0, 0.8) if hovered else Color(0.4, 0.5, 0.8, 0.5)
	elif unlocked:
		bcol = UITheme.BORDER_ACTIVE if hovered else UITheme.PRIMARY_DIM
	else:
		bcol = UITheme.BORDER_HOVER if hovered else UITheme.BORDER
	draw_rect(rect, bcol, false, 1.0)

	# Top glow line (unlocked/special only)
	if unlocked:
		var ga: float = 0.25 if hovered else 0.12
		var gc: Color = Color(0.4, 0.5, 1.0, ga) if is_special else Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, ga)
		draw_line(Vector2(rect.position.x + 1, rect.position.y), Vector2(rect.end.x - 1, rect.position.y), gc, 2.0)

	# Mini corner accents
	draw_corners(rect, 8.0, bcol)

	# Icon
	var ic: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 38.0)
	var icol: Color
	if is_special:
		icol = Color(0.5, 0.6, 1.0, 0.9)
	elif unlocked:
		icol = UITheme.PRIMARY
	else:
		icol = Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.45)
	_draw_icon(ic, card["icon"], icol)

	# Lock badge (top-right)
	if not unlocked:
		_draw_lock(Vector2(rect.end.x - 14, rect.position.y + 14), UITheme.WARNING)

	# Label
	var font: Font = UITheme.get_font()
	var lcol: Color = UITheme.TEXT if unlocked else UITheme.TEXT_DIM
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 74),
		card["label"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, UITheme.FONT_SIZE_SMALL, lcol)

	# Status / price
	if is_special:
		draw_string(font, Vector2(rect.position.x, rect.end.y - 10), Locale.t("common.available"),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_TINY, Color(0.5, 0.6, 1.0, 0.6))
	elif unlocked:
		# Small green dot + ACTIVE
		draw_circle(Vector2(rect.position.x + rect.size.x * 0.5 - 24, rect.end.y - 15), 3.0, UITheme.ACCENT)
		draw_string(font, Vector2(rect.position.x + 8, rect.end.y - 10), Locale.t("common.active"),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16, UITheme.FONT_SIZE_TINY, UITheme.ACCENT)
	else:
		var price: int = StationServices.SERVICE_PRICES[card["svc"]]
		draw_string(font, Vector2(rect.position.x, rect.end.y - 10),
			PlayerEconomy.format_credits(price) + " CR",
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_TINY, UITheme.WARNING)


func _draw_icon(c: Vector2, icon: int, col: Color) -> void:
	var r: float = 13.0
	match icon:
		ICO.COMMERCE:
			# Diamond (trade)
			var d: PackedVector2Array = [c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]
			draw_polyline(d, col, 1.5)
			draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), col, 1.0)
		ICO.SHIPYARD:
			# Ship chevron
			draw_line(c + Vector2(0, -r), c + Vector2(-r * 0.8, r * 0.6), col, 1.5)
			draw_line(c + Vector2(0, -r), c + Vector2(r * 0.8, r * 0.6), col, 1.5)
			draw_line(c + Vector2(-r * 0.8, r * 0.6), c + Vector2(0, r * 0.15), col, 1.5)
			draw_line(c + Vector2(r * 0.8, r * 0.6), c + Vector2(0, r * 0.15), col, 1.5)
		ICO.STORAGE:
			# Crate with shelves
			draw_rect(Rect2(c.x - r * 0.7, c.y - r * 0.8, r * 1.4, r * 1.6), col, false, 1.5)
			draw_line(c + Vector2(-r * 0.7, -r * 0.1), c + Vector2(r * 0.7, -r * 0.1), col, 1.0)
			draw_line(c + Vector2(-r * 0.7, r * 0.5), c + Vector2(r * 0.7, r * 0.5), col, 1.0)
		ICO.REPAIR:
			# Wrench
			draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.3, -r * 0.3), col, 2.0)
			draw_arc(c + Vector2(r * 0.45, -r * 0.45), r * 0.35, -PI * 0.75, PI * 0.75, 10, col, 1.5)
		ICO.EQUIP:
			# Crosshair
			draw_arc(c, r * 0.65, 0, TAU, 20, col, 1.5)
			draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.3), col, 1.0)
			draw_line(c + Vector2(0, r), c + Vector2(0, r * 0.3), col, 1.0)
			draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.3, 0), col, 1.0)
			draw_line(c + Vector2(r, 0), c + Vector2(r * 0.3, 0), col, 1.0)
			draw_circle(c, 2.0, col)
		ICO.REFINERY:
			# Flask
			draw_line(c + Vector2(-4, -r), c + Vector2(4, -r), col, 1.5)
			draw_line(c + Vector2(-4, -r), c + Vector2(-r * 0.7, r * 0.7), col, 1.5)
			draw_line(c + Vector2(4, -r), c + Vector2(r * 0.7, r * 0.7), col, 1.5)
			draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.7, r * 0.7), col, 1.5)
			draw_line(c + Vector2(-r * 0.35, r * 0.15), c + Vector2(r * 0.35, r * 0.15),
				Color(col.r, col.g, col.b, col.a * 0.4), 1.0)
		ICO.STN_EQUIP:
			# Gear (hexagon + hub)
			var pts: PackedVector2Array = []
			for k in 7:
				var a: float = TAU * float(k) / 6.0 - PI * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.8)
			draw_polyline(pts, col, 1.5)
			draw_arc(c, r * 0.3, 0, TAU, 10, col, 1.5)
		ICO.ADMIN:
			# Document with lines
			var hw: float = r * 0.55
			var hh: float = r * 0.75
			draw_rect(Rect2(c.x - hw, c.y - hh, hw * 2, hh * 2), col, false, 1.5)
			draw_line(c + Vector2(hw - 5, -hh), c + Vector2(hw, -hh + 5), col, 1.0)
			draw_line(c + Vector2(-hw * 0.5, -hh * 0.3), c + Vector2(hw * 0.5, -hh * 0.3), col, 1.0)
			draw_line(c + Vector2(-hw * 0.5, hh * 0.1), c + Vector2(hw * 0.5, hh * 0.1), col, 1.0)
			draw_line(c + Vector2(-hw * 0.5, hh * 0.5), c + Vector2(hw * 0.15, hh * 0.5), col, 1.0)
		ICO.MISSIONS:
			# Diamond with exclamation mark (mission marker)
			var d: PackedVector2Array = [c + Vector2(0, -r), c + Vector2(r * 0.7, 0), c + Vector2(0, r), c + Vector2(-r * 0.7, 0), c + Vector2(0, -r)]
			draw_polyline(d, col, 1.5)
			draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.15), col, 2.0)
			draw_circle(c + Vector2(0, r * 0.4), 1.5, col)
		ICO.MARKET:
			# Balance / scales (auction house)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.7), col, 1.5)  # Center post
			draw_line(c + Vector2(-r * 0.8, -r * 0.4), c + Vector2(r * 0.8, -r * 0.4), col, 1.5)  # Beam
			# Left pan
			draw_line(c + Vector2(-r * 0.8, -r * 0.4), c + Vector2(-r * 0.6, r * 0.2), col, 1.0)
			draw_line(c + Vector2(-r * 0.8, -r * 0.4), c + Vector2(-r, r * 0.2), col, 1.0)
			draw_line(c + Vector2(-r, r * 0.2), c + Vector2(-r * 0.6, r * 0.2), col, 1.0)
			# Right pan
			draw_line(c + Vector2(r * 0.8, -r * 0.4), c + Vector2(r * 0.6, r * 0.2), col, 1.0)
			draw_line(c + Vector2(r * 0.8, -r * 0.4), c + Vector2(r, r * 0.2), col, 1.0)
			draw_line(c + Vector2(r, r * 0.2), c + Vector2(r * 0.6, r * 0.2), col, 1.0)
			# Base
			draw_line(c + Vector2(-r * 0.35, r * 0.7), c + Vector2(r * 0.35, r * 0.7), col, 1.5)


func _draw_lock(pos: Vector2, col: Color) -> void:
	draw_arc(pos + Vector2(0, -3), 4.0, PI, TAU, 8, col, 1.5)
	draw_rect(Rect2(pos.x - 5, pos.y, 10, 7), col, false, 1.5)
	draw_circle(pos + Vector2(0, 3.5), 1.0, col)


func _draw_undock() -> void:
	var r: Rect2 = _undock_rect
	var hov: bool = _undock_hovered
	draw_rect(r, Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.18 if hov else 0.08))
	if _undock_flash > 0.0:
		draw_rect(r, Color(1, 1, 1, _undock_flash * 0.2))
	var bc: Color = UITheme.WARNING if hov else Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.45)
	draw_rect(r, bc, false, 1.0)
	draw_rect(Rect2(r.position.x, r.position.y + 2, 3, r.size.y - 4), UITheme.WARNING)
	draw_corners(r, 6.0, bc)
	var font: Font = UITheme.get_font()
	var ty: float = r.position.y + (r.size.y + UITheme.FONT_SIZE_BODY) * 0.5 - 1
	draw_string(font, Vector2(r.position.x, ty), Locale.t("btn.leave_dock"),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


func _draw_station_emblem(center: Vector2, radius: float) -> void:
	var pts: PackedVector2Array = []
	for i in 7:
		var a: float = TAU * float(i) / 6.0 - PI * 0.5
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	var ga: float = 0.1 + sin(_emblem_pulse * 1.5) * 0.06
	var gcol: Color = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, ga)
	for i in 6:
		var a1: float = TAU * float(i) / 6.0 - PI * 0.5
		var a2: float = TAU * float(i + 1) / 6.0 - PI * 0.5
		draw_line(center + Vector2(cos(a1), sin(a1)) * (radius + 4),
			center + Vector2(cos(a2), sin(a2)) * (radius + 4), gcol, 1.0)
	draw_polyline(pts, UITheme.PRIMARY, 1.0)
	var ir: float = radius * 0.4
	var inner: PackedVector2Array = [
		center + Vector2(0, -ir), center + Vector2(ir, 0),
		center + Vector2(0, ir), center + Vector2(-ir, 0), center + Vector2(0, -ir)]
	draw_polyline(inner, UITheme.PRIMARY_DIM, 1.0)
	draw_circle(center, 2.0, UITheme.PRIMARY)


# =============================================================================
# INTERACTION
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old_h: int = _hovered_card
		var old_u: bool = _undock_hovered
		_hovered_card = -1
		_undock_hovered = false
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				_hovered_card = i
				break
		_undock_hovered = _undock_rect.has_point(event.position)
		if _hovered_card != old_h or _undock_hovered != old_u:
			queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				_flash[i] = 1.0
				_on_card_clicked(i)
				accept_event()
				return
		if _undock_rect.has_point(event.position):
			_undock_flash = 1.0
			undock_requested.emit()
			accept_event()
			return

	super._gui_input(event)


func _on_card_clicked(idx: int) -> void:
	var card: Dictionary = _cards[idx]
	if card["special"] == "station_equip":
		station_equipment_requested.emit()
		return
	if card["special"] == "admin":
		administration_requested.emit()
		return
	if card["special"] == "missions":
		missions_requested.emit()
		return

	var svc: int = card["svc"]
	if _is_unlocked(card):
		match svc:
			StationServices.Service.COMMERCE: commerce_requested.emit()
			StationServices.Service.REPAIR: repair_requested.emit()
			StationServices.Service.EQUIPMENT: equipment_requested.emit()
			StationServices.Service.SHIPYARD: shipyard_requested.emit()
			StationServices.Service.REFINERY: refinery_requested.emit()
			StationServices.Service.ENTREPOT: storage_requested.emit()
			StationServices.Service.MARKET: market_requested.emit()
	else:
		_try_unlock(svc)


func _try_unlock(svc: int) -> void:
	if _services == null or _economy == null:
		return
	var price: int = StationServices.SERVICE_PRICES[svc]
	if _economy.credits < price:
		if GameManager._notif:
			GameManager._notif.general.insufficient_credits(PlayerEconomy.format_credits(price))
		return
	if _services.unlock(_system_id, _station_idx, svc, _economy):
		if GameManager._notif:
			GameManager._notif.general.service_unlocked(StationServices.get_service_label(svc))
		queue_redraw()
