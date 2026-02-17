class_name SellShipView
extends UIComponent

# =============================================================================
# Sell Ship View - Card grid of fleet ships with status badges + detail panel
# Left: 2-column card grid (all ships, status tags), Right: detail + sell button
# =============================================================================

var _commerce_manager = null
var _station_id: String = ""

var _sell_btn: UIButton = null
var _fleet_ships: Array[FleetShip] = []   # all ships in display order
var _fleet_indices: Array[int] = []       # original fleet index per row
var _ship_can_sell: Array[bool] = []      # whether each card is sellable
var _ship_status: Array[String] = []      # status tag per card
var _selected_index: int = -1

# Card grid state
var _card_rects: Array[Rect2] = []
var _hovered_idx: int = -1
var _scroll_offset: float = 0.0
var _total_content_h: float = 0.0
var _grid_area: Rect2 = Rect2()

const DETAIL_W: float = 240.0
const CARD_W: float = 220.0
const CARD_H: float = 140.0
const CARD_GAP: float = 10.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)

	_sell_btn = UIButton.new()
	_sell_btn.text = "VENDRE VAISSEAU"
	_sell_btn.accent_color = UITheme.DANGER
	_sell_btn.visible = false
	_sell_btn.pressed.connect(_on_sell_pressed)
	add_child(_sell_btn)


func setup(mgr, station_id: String = "") -> void:
	_commerce_manager = mgr
	_station_id = station_id


func refresh() -> void:
	_sell_btn.visible = true
	_refresh_items()
	_layout()


func _layout() -> void:
	var s: Vector2 = size
	var grid_w: float = s.x - DETAIL_W - 10.0
	_grid_area = Rect2(0, 0, grid_w, s.y)
	_sell_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_btn.size = Vector2(DETAIL_W - 20, 34)
	_compute_card_grid()


func _refresh_items() -> void:
	_fleet_ships.clear()
	_fleet_indices.clear()
	_ship_can_sell.clear()
	_ship_status.clear()
	if _commerce_manager == null or _commerce_manager.player_fleet == null:
		_card_rects.clear()
		_total_content_h = 0.0
		queue_redraw()
		return

	var fleet = _commerce_manager.player_fleet
	var is_only_ship: bool = (fleet.ships.size() <= 1)

	for i in fleet.ships.size():
		var fs: FleetShip = fleet.ships[i]
		_fleet_ships.append(fs)
		_fleet_indices.append(i)

		var is_active: bool = (i == fleet.active_index)
		var is_docked: bool = (fs.deployment_state == FleetShip.DeploymentState.DOCKED)
		var is_deployed: bool = (fs.deployment_state == FleetShip.DeploymentState.DEPLOYED)
		var is_destroyed: bool = (fs.deployment_state == FleetShip.DeploymentState.DESTROYED)
		var is_here: bool = is_docked and (_station_id == "" or fs.docked_station_id == _station_id)

		if is_active:
			_ship_can_sell.append(false)
			_ship_status.append("ACTIF")
		elif is_destroyed:
			_ship_can_sell.append(false)
			_ship_status.append("DETRUIT")
		elif is_deployed:
			_ship_can_sell.append(false)
			_ship_status.append("DEPLOYE")
		elif is_docked and not is_here:
			_ship_can_sell.append(false)
			_ship_status.append("AILLEURS")
		elif is_here and is_only_ship:
			_ship_can_sell.append(false)
			_ship_status.append("DERNIER")
		elif is_here:
			_ship_can_sell.append(true)
			_ship_status.append("ICI")
		else:
			_ship_can_sell.append(false)
			_ship_status.append("")

	if _selected_index >= _fleet_ships.size():
		_selected_index = -1
	_compute_card_grid()
	queue_redraw()


func _compute_card_grid() -> void:
	_card_rects.clear()
	if _fleet_ships.is_empty():
		_total_content_h = 0.0
		return
	var area_w: float = _grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _fleet_ships.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _grid_area.position.y + row * (CARD_H + CARD_GAP) - _scroll_offset
		_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	@warning_ignore("integer_division")
	var total_rows: int = (_fleet_ships.size() + maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP))) - 1) / maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	_total_content_h = total_rows * (CARD_H + CARD_GAP)


func _on_sell_pressed() -> void:
	_do_sell()


func _do_sell() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _fleet_ships.size(): return
	if not _ship_can_sell[_selected_index]: return
	var fleet_idx: int = _fleet_indices[_selected_index]
	var fs: FleetShip = _fleet_ships[_selected_index]
	var sell_price: int = _commerce_manager.get_ship_sell_price(fs)
	if _commerce_manager.sell_ship(fleet_idx):
		if GameManager._notif:
			GameManager._notif.commerce.sold(fs.custom_name, sell_price)
		_selected_index = -1
		_refresh_items()
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# =========================================================================
# INPUT
# =========================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old: int = _hovered_idx
		_hovered_idx = -1
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position) and _grid_area.has_point(event.position):
				_hovered_idx = i
				break
		if _hovered_idx != old:
			queue_redraw()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in _card_rects.size():
				if _card_rects[i].has_point(event.position) and _grid_area.has_point(event.position):
					_selected_index = i
					queue_redraw()
					accept_event()
					return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - 40.0)
			_compute_card_grid()
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var max_scroll: float = maxf(0.0, _total_content_h - _grid_area.size.y)
			_scroll_offset = minf(max_scroll, _scroll_offset + 40.0)
			_compute_card_grid()
			queue_redraw()
			accept_event()


# =========================================================================
# STATUS HELPERS
# =========================================================================

func _get_status_color(status: String) -> Color:
	match status:
		"ACTIF": return UITheme.PRIMARY
		"ICI": return Color(0.2, 0.9, 0.3)
		"AILLEURS": return UITheme.TEXT_DIM
		"DEPLOYE": return Color(0.3, 0.6, 1.0)
		"DETRUIT": return UITheme.DANGER
		"DERNIER": return UITheme.WARNING
		_: return UITheme.TEXT_DIM


func _get_sell_reason(idx: int) -> String:
	if idx < 0 or idx >= _ship_status.size():
		return ""
	match _ship_status[idx]:
		"ACTIF": return "Vaisseau en cours d'utilisation.\nChangez de vaisseau pour le vendre."
		"DEPLOYE": return "Vaisseau actuellement deploye.\nRappelez-le d'abord."
		"DETRUIT": return "Vaisseau detruit."
		"AILLEURS": return "Vaisseau docke dans une autre\nstation. Rendez-vous sur place."
		"DERNIER": return "Impossible de vendre votre\ndernier vaisseau."
		_: return ""


# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	var s: Vector2 = size
	var font: Font = UITheme.get_font()
	var detail_x: float = s.x - DETAIL_W

	# Draw card grid
	_draw_card_grid(font)

	# Detail panel background
	draw_rect(Rect2(detail_x, 0, DETAIL_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(detail_x, 0), Vector2(detail_x, s.y), UITheme.BORDER, 1.0)

	if _fleet_ships.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), "Aucun vaisseau",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _fleet_ships.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un vaisseau",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		# Fleet summary
		var total_ships: int = _fleet_ships.size()
		var sellable_count: int = 0
		for can in _ship_can_sell:
			if can:
				sellable_count += 1
		draw_string(font, Vector2(detail_x + 10, 54), "Flotte: %d vaisseau%s" % [total_ships, "x" if total_ships > 1 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
		if sellable_count > 0:
			draw_string(font, Vector2(detail_x + 10, 72), "%d vendable%s ici" % [sellable_count, "s" if sellable_count > 1 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, Color(0.2, 0.9, 0.3))
		else:
			draw_string(font, Vector2(detail_x + 10, 72), "Aucun vendable ici",
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.WARNING)
		return

	_draw_detail_panel(font, detail_x)


func _draw_card_grid(font: Font) -> void:
	for i in _card_rects.size():
		var r: Rect2 = _card_rects[i]
		# Clip: only draw if visible in grid area
		if r.end.y < _grid_area.position.y or r.position.y > _grid_area.end.y:
			continue
		_draw_ship_card(font, r, i)


func _draw_ship_card(font: Font, rect: Rect2, idx: int) -> void:
	if idx >= _fleet_ships.size(): return
	var fs: FleetShip = _fleet_ships[idx]
	var ship_data: ShipData = ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null: return

	var can_sell: bool = _ship_can_sell[idx] if idx < _ship_can_sell.size() else false
	var status: String = _ship_status[idx] if idx < _ship_status.size() else ""
	var status_col: Color = _get_status_color(status)
	var is_sel: bool = idx == _selected_index
	var is_hov: bool = idx == _hovered_idx

	# --- Card background ---
	var bg: Color
	if is_sel:
		bg = Color(status_col.r, status_col.g, status_col.b, 0.15)
	elif is_hov:
		bg = Color(0.025, 0.06, 0.12, 0.9) if can_sell else Color(0.015, 0.025, 0.05, 0.62)
	else:
		bg = Color(0.015, 0.04, 0.08, 0.8) if can_sell else Color(0.01, 0.015, 0.03, 0.5)
	draw_rect(rect, bg)

	# --- Border ---
	var bcol: Color
	if is_sel:
		bcol = status_col
	elif is_hov:
		bcol = UITheme.BORDER_HOVER
	else:
		bcol = Color(status_col.r, status_col.g, status_col.b, 0.3) if can_sell else UITheme.BORDER
	draw_rect(rect, bcol, false, 1.0)

	# --- Top glow ---
	if can_sell or is_sel:
		var ga: float = 0.25 if (is_hov or is_sel) else 0.1
		draw_line(Vector2(rect.position.x + 1, rect.position.y),
			Vector2(rect.end.x - 1, rect.position.y),
			Color(status_col.r, status_col.g, status_col.b, ga), 2.0)

	# --- Mini corners ---
	draw_corners(rect, 6.0, bcol)

	var alpha: float = 1.0 if can_sell else 0.5
	var y: float = rect.position.y

	# --- Status badge (top-left) ---
	var badge_w: float = minf(font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x + 12.0, rect.size.x * 0.45)
	var badge_rect: Rect2 = Rect2(rect.position.x + 4, y + 4, badge_w, 16)
	draw_rect(badge_rect, Color(status_col.r, status_col.g, status_col.b, 0.15 * alpha))
	draw_rect(Rect2(badge_rect.position.x, badge_rect.position.y, 3, badge_rect.size.y),
		Color(status_col.r, status_col.g, status_col.b, alpha))
	draw_string(font, Vector2(badge_rect.position.x + 6, badge_rect.position.y + 12),
		status, HORIZONTAL_ALIGNMENT_LEFT, badge_w - 8,
		UITheme.FONT_SIZE_TINY, Color(status_col.r, status_col.g, status_col.b, alpha))

	# --- Ship name (centered, below badge) ---
	var name_col: Color = UITheme.TEXT if (is_sel or can_sell) else Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, alpha)
	draw_string(font, Vector2(rect.position.x + 6, y + 38),
		fs.custom_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12,
		UITheme.FONT_SIZE_SMALL, name_col)

	# --- Ship class (centered, smaller) ---
	draw_string(font, Vector2(rect.position.x + 6, y + 54),
		String(ship_data.ship_class), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12,
		UITheme.FONT_SIZE_TINY, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, alpha))

	# --- Hull HP mini bar ---
	var bar_x: float = rect.position.x + 8
	var bar_w: float = rect.size.x - 16
	var bar_h: float = 12.0
	var hull_ratio: float = clampf(ship_data.hull_hp / 2000.0, 0.0, 1.0)
	draw_stat_mini_bar(
		Rect2(bar_x, y + 62, bar_w, bar_h),
		hull_ratio, Color(0.2, 0.8, 0.3, alpha), "PV", "%.0f" % ship_data.hull_hp)

	# --- Weapon slots mini bar ---
	var weapon_count: int = 0
	for wn in fs.weapons:
		if wn != &"":
			weapon_count += 1
	var weapon_total: int = fs.weapons.size()
	var weapon_ratio: float = float(weapon_count) / maxf(1.0, float(weapon_total))
	draw_stat_mini_bar(
		Rect2(bar_x, y + 78, bar_w, bar_h),
		weapon_ratio, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, alpha),
		Locale.t("ship.weapons_label"), "%d/%d" % [weapon_count, weapon_total])

	# --- Sell price estimate (bottom) ---
	if can_sell and _commerce_manager:
		var sell_price: int = _commerce_manager.get_ship_sell_price(fs)
		draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 10),
			"+" + PriceCatalog.format_price(sell_price), HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x - 8, UITheme.FONT_SIZE_TINY, PlayerEconomy.CREDITS_COLOR)

	# --- Grey overlay + lock for non-sellable ---
	if not can_sell:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.2))
		# Lock icon (simple padlock shape)
		var lc: Vector2 = Vector2(rect.end.x - 16, rect.end.y - 16)
		var lock_col: Color = Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.5)
		draw_arc(lc + Vector2(0, -4), 4.0, PI, 0.0, 8, lock_col, 1.5)
		draw_rect(Rect2(lc.x - 5, lc.y - 2, 10, 8), lock_col, false, 1.0)


# =========================================================================
# DETAIL PANEL
# =========================================================================

func _draw_detail_panel(font: Font, detail_x: float) -> void:
	var fs: FleetShip = _fleet_ships[_selected_index]
	var ship_data: ShipData = ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null: return
	var can_sell: bool = _ship_can_sell[_selected_index]
	var status: String = _ship_status[_selected_index]

	var y: float = 10.0

	# Status badge
	var status_col: Color = _get_status_color(status)
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 18),
		Color(status_col.r, status_col.g, status_col.b, 0.15))
	draw_rect(Rect2(detail_x + 10, y, 3, 18), status_col)
	draw_string(font, Vector2(detail_x + 18, y + 13), status,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 30, UITheme.FONT_SIZE_TINY, status_col)
	y += 24.0

	# Ship name
	draw_string(font, Vector2(detail_x + 10, y + 14), fs.custom_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	# Ship class
	draw_string(font, Vector2(detail_x + 10, y + 12), "Classe",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), String(ship_data.ship_class),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Hull HP
	draw_string(font, Vector2(detail_x + 10, y + 12), "Coque",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), "%.0f PV" % ship_data.hull_hp,
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Hardpoints
	var weapon_count: int = 0
	for wn in fs.weapons:
		if wn != &"":
			weapon_count += 1
	draw_string(font, Vector2(detail_x + 10, y + 12), "Armes",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), "%d/%d" % [weapon_count, fs.weapons.size()],
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)
	y += 18.0

	# Equipment value
	var equip_val: int = fs.get_total_equipment_value()
	if equip_val > 0:
		draw_string(font, Vector2(detail_x + 10, y + 12), "Equip.",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(equip_val),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
		y += 18.0

	# Cargo
	if fs.cargo:
		var cargo_count: int = fs.cargo.get_total_count()
		if cargo_count > 0:
			draw_string(font, Vector2(detail_x + 10, y + 12), "Cargo",
				HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
			draw_string(font, Vector2(detail_x + 95, y + 12), "%d items" % cargo_count,
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, UITheme.WARNING)
			y += 18.0

	y += 8.0

	if can_sell:
		# Price breakdown
		var hull_price: int = PriceCatalog.get_sell_price(ship_data.price)
		var equip_price: int = PriceCatalog.get_sell_price(equip_val)
		var total_price: int = hull_price + equip_price

		# Section header
		draw_rect(Rect2(detail_x + 10, y, 2, 10), PlayerEconomy.CREDITS_COLOR)
		draw_string(font, Vector2(detail_x + 16, y + 9), "ESTIMATION",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_HEADER)
		y += 18.0

		draw_string(font, Vector2(detail_x + 10, y + 12), "Coque",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), "+" + PriceCatalog.format_price(hull_price),
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
		y += 16.0

		if equip_price > 0:
			draw_string(font, Vector2(detail_x + 10, y + 12), "Equip.",
				HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_KEY)
			draw_string(font, Vector2(detail_x + 95, y + 12), "+" + PriceCatalog.format_price(equip_price),
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_LABEL, PlayerEconomy.CREDITS_COLOR)
			y += 16.0

		y += 4.0

		# Total sell price box
		draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
			Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
		draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
		draw_string(font, Vector2(detail_x + 10, y + 19),
			"TOTAL: +" + PriceCatalog.format_price(total_price),
			HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)

		# Cargo loss warning
		if fs.cargo and fs.cargo.get_total_count() > 0:
			y += 36.0
			draw_string(font, Vector2(detail_x + 10, y + 10), "Cargo perdu a la vente!",
				HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_TINY, UITheme.DANGER)
	else:
		# Non-sellable: show reason
		var reason: String = _get_sell_reason(_selected_index)
		if reason != "":
			draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 42),
				Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.08))
			draw_rect(Rect2(detail_x + 10, y, 3, 42), UITheme.DANGER)
			var lines: PackedStringArray = reason.split("\n")
			for li in lines.size():
				draw_string(font, Vector2(detail_x + 18, y + 14 + li * 16), lines[li],
					HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 30, UITheme.FONT_SIZE_TINY, UITheme.WARNING)

	# Update sell button state
	if _sell_btn:
		_sell_btn.enabled = can_sell
