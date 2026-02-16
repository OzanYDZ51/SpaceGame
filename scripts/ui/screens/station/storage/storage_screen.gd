class_name StorageScreen
extends UIScreen

# =============================================================================
# Storage Screen — Dedicated ENTREPOT service.
# Two panels: station storage (left) + ship hold (right) with fleet dropdown.
# Transfers ores, refined materials, and cargo between ship and station.
# Refactored from UIScrollList to drawn card grids (3 columns per panel).
# =============================================================================

signal storage_closed

var _player_data = null
var _station_key: String = ""
var _station_name: String = "STATION"
var _selected_fleet_index: int = 0

# UI elements (children)
var _fleet_dropdown: UIDropdown = null
var _back_btn: UIButton = null
var _transfer_to_ship_btn: UIButton = null
var _transfer_to_station_btn: UIButton = null
var _transfer_all_to_ship_btn: UIButton = null
var _transfer_all_to_station_btn: UIButton = null

# Data arrays
var _station_items: Array = []  # [{id, qty, name, color, source}]
var _ship_items: Array = []     # [{id, qty, name, color, source}]
var _selected_station_item: int = -1
var _selected_ship_item: int = -1
var _fleet_options: Array[String] = []
var _fleet_indices: Array[int] = []  # Maps dropdown index -> fleet index

# Card grid state — station (left)
var _station_card_rects: Array[Rect2] = []
var _hovered_station_idx: int = -1
var _station_scroll_offset: float = 0.0
var _station_total_content_h: float = 0.0
var _station_grid_area: Rect2 = Rect2()

# Card grid state — ship (right)
var _ship_card_rects: Array[Rect2] = []
var _hovered_ship_idx: int = -1
var _ship_scroll_offset: float = 0.0
var _ship_total_content_h: float = 0.0
var _ship_grid_area: Rect2 = Rect2()

const TRANSFER_QTY: int = 10
const CONTENT_TOP: float = 65.0
const BOTTOM_H: float = 50.0
const CENTER_W: float = 90.0
const CARD_W: float = 100.0
const CARD_H: float = 70.0
const CARD_GAP: float = 6.0


func _ready() -> void:
	screen_title = "ENTREPOT"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Fleet dropdown
	_fleet_dropdown = UIDropdown.new()
	_fleet_dropdown.visible = false
	_fleet_dropdown.option_selected.connect(_on_fleet_changed)
	add_child(_fleet_dropdown)

	# Transfer buttons
	_transfer_to_ship_btn = UIButton.new()
	_transfer_to_ship_btn.text = "<- x%d" % TRANSFER_QTY
	_transfer_to_ship_btn.accent_color = UITheme.ACCENT
	_transfer_to_ship_btn.pressed.connect(_on_transfer_to_ship)
	_transfer_to_ship_btn.visible = false
	add_child(_transfer_to_ship_btn)

	_transfer_all_to_ship_btn = UIButton.new()
	_transfer_all_to_ship_btn.text = "<- TOUT"
	_transfer_all_to_ship_btn.accent_color = UITheme.ACCENT
	_transfer_all_to_ship_btn.pressed.connect(_on_transfer_all_to_ship)
	_transfer_all_to_ship_btn.visible = false
	add_child(_transfer_all_to_ship_btn)

	_transfer_to_station_btn = UIButton.new()
	_transfer_to_station_btn.text = "x%d ->" % TRANSFER_QTY
	_transfer_to_station_btn.accent_color = UITheme.PRIMARY
	_transfer_to_station_btn.pressed.connect(_on_transfer_to_station)
	_transfer_to_station_btn.visible = false
	add_child(_transfer_to_station_btn)

	_transfer_all_to_station_btn = UIButton.new()
	_transfer_all_to_station_btn.text = "TOUT ->"
	_transfer_all_to_station_btn.accent_color = UITheme.PRIMARY
	_transfer_all_to_station_btn.pressed.connect(_on_transfer_all_to_station)
	_transfer_all_to_station_btn.visible = false
	add_child(_transfer_all_to_station_btn)

	# Back button
	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.WARNING
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)


func setup(pdata, station_key: String, sname: String) -> void:
	_player_data = pdata
	_station_key = station_key
	_station_name = sname
	screen_title = "ENTREPOT — " + sname.to_upper()
	_selected_fleet_index = pdata.fleet.active_index if pdata and pdata.fleet else 0
	_rebuild_fleet_dropdown()


func _on_opened() -> void:
	_layout_controls()
	_fleet_dropdown.visible = true
	_back_btn.visible = true
	_refresh()


func _on_closed() -> void:
	_fleet_dropdown.visible = false
	_back_btn.visible = false
	_hide_transfer_buttons()
	storage_closed.emit()


func _on_back_pressed() -> void:
	close()


# =========================================================================
# FLEET DROPDOWN
# =========================================================================

func _rebuild_fleet_dropdown() -> void:
	_fleet_options.clear()
	_fleet_indices.clear()
	if _player_data == null or _player_data.fleet == null:
		return
	var fleet = _player_data.fleet
	var current_station_id: String = ""
	var active_fs = fleet.get_active()
	if active_fs:
		current_station_id = active_fs.docked_station_id
	var dropdown_sel: int = 0
	for i in fleet.ships.size():
		var fs = fleet.ships[i]
		# Only show ships docked at this station (+ active ship)
		if i != fleet.active_index:
			if fs.deployment_state != FleetShip.DeploymentState.DOCKED:
				continue
			if current_station_id != "" and fs.docked_station_id != current_station_id:
				continue
		var label: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
		if i == fleet.active_index:
			label += " (ACTIF)"
		if i == _selected_fleet_index:
			dropdown_sel = _fleet_options.size()
		_fleet_options.append(label)
		_fleet_indices.append(i)
	_fleet_dropdown.options = _fleet_options
	_fleet_dropdown.selected_index = dropdown_sel


func _on_fleet_changed(idx: int) -> void:
	if idx >= 0 and idx < _fleet_indices.size():
		_selected_fleet_index = _fleet_indices[idx]
	_refresh()


func _get_selected_fleet_ship():
	if _player_data == null or _player_data.fleet == null:
		return null
	if _selected_fleet_index < 0 or _selected_fleet_index >= _player_data.fleet.ships.size():
		return null
	return _player_data.fleet.ships[_selected_fleet_index]


# =========================================================================
# LIST REFRESH
# =========================================================================

func _refresh() -> void:
	_rebuild_lists()
	_selected_station_item = -1
	_selected_ship_item = -1
	_station_scroll_offset = 0.0
	_ship_scroll_offset = 0.0
	_update_button_visibility()
	_layout_controls()
	queue_redraw()


func _rebuild_lists() -> void:
	_station_items.clear()
	_ship_items.clear()

	# Station storage items
	if _player_data and _player_data.refinery_manager:
		var storage = _player_data.refinery_manager.get_storage(_station_key)
		var items = storage.get_all_items()
		for item_id in items:
			_station_items.append({
				id = item_id,
				qty = items[item_id],
				name = RefineryRegistry.get_display_name(item_id),
				color = RefineryRegistry.get_item_color(item_id),
				source = "storage",
			})
		_station_items.sort_custom(func(a, b): return a.name < b.name)

	# Ship resources + cargo
	var fs = _get_selected_fleet_ship()
	if fs:
		# Mining ores / resources
		for res_id in fs.ship_resources:
			var qty: int = fs.ship_resources[res_id]
			if qty > 0:
				_ship_items.append({
					id = res_id,
					qty = qty,
					name = RefineryRegistry.get_display_name(res_id),
					color = RefineryRegistry.get_item_color(res_id),
					source = "resource",
				})
		# Cargo items
		if fs.cargo:
			for ci in fs.cargo.get_all():
				var item_name: String = ci.get("name", "")
				var qty: int = ci.get("quantity", 0)
				if qty > 0 and item_name != "":
					_ship_items.append({
						id = StringName(item_name),
						qty = qty,
						name = RefineryRegistry.get_display_name(StringName(item_name)),
						color = RefineryRegistry.get_item_color(StringName(item_name)),
						source = "cargo",
					})
		_ship_items.sort_custom(func(a, b): return a.name < b.name)

	_compute_station_grid()
	_compute_ship_grid()


# =========================================================================
# SELECTION
# =========================================================================

func _update_button_visibility() -> void:
	var has_station_sel: bool = _selected_station_item >= 0 and _selected_station_item < _station_items.size()
	var has_ship_sel: bool = _selected_ship_item >= 0 and _selected_ship_item < _ship_items.size()
	_transfer_to_ship_btn.visible = has_station_sel
	_transfer_all_to_ship_btn.visible = has_station_sel
	_transfer_to_station_btn.visible = has_ship_sel
	_transfer_all_to_station_btn.visible = has_ship_sel


func _hide_transfer_buttons() -> void:
	_transfer_to_ship_btn.visible = false
	_transfer_all_to_ship_btn.visible = false
	_transfer_to_station_btn.visible = false
	_transfer_all_to_station_btn.visible = false


# =========================================================================
# TRANSFERS
# =========================================================================

func _on_transfer_to_ship() -> void:
	if _selected_station_item < 0 or _selected_station_item >= _station_items.size():
		return
	var item: Dictionary = _station_items[_selected_station_item]
	_do_transfer_to_ship(item, TRANSFER_QTY)


func _on_transfer_all_to_ship() -> void:
	if _selected_station_item < 0 or _selected_station_item >= _station_items.size():
		return
	var item: Dictionary = _station_items[_selected_station_item]
	_do_transfer_to_ship(item, item.qty)


func _on_transfer_to_station() -> void:
	if _selected_ship_item < 0 or _selected_ship_item >= _ship_items.size():
		return
	var item: Dictionary = _ship_items[_selected_ship_item]
	_do_transfer_to_station(item, TRANSFER_QTY)


func _on_transfer_all_to_station() -> void:
	if _selected_ship_item < 0 or _selected_ship_item >= _ship_items.size():
		return
	var item: Dictionary = _ship_items[_selected_ship_item]
	_do_transfer_to_station(item, item.qty)


func _do_transfer_to_ship(item: Dictionary, qty: int) -> void:
	var mgr = _player_data.refinery_manager if _player_data else null
	if mgr == null:
		return
	var fs = _get_selected_fleet_ship()
	if fs == null:
		return
	# Storage -> ship: all storage items become resources on the ship
	mgr.transfer_to_ship_from_storage(_station_key, item.id, qty, fs, _player_data)
	_refresh()


func _do_transfer_to_station(item: Dictionary, qty: int) -> void:
	var mgr = _player_data.refinery_manager if _player_data else null
	if mgr == null:
		return
	var fs = _get_selected_fleet_ship()
	if fs == null:
		return
	var source: String = item.get("source", "resource")
	if source == "cargo":
		mgr.transfer_cargo_to_storage(_station_key, String(item.id), qty, fs)
	else:
		mgr.transfer_to_storage_from_ship(_station_key, item.id, qty, fs, _player_data)
	_refresh()


# =========================================================================
# LAYOUT
# =========================================================================

func _layout_controls() -> void:
	var s: Vector2 = size
	var left_w: float = (s.x - CENTER_W) * 0.5
	var right_w: float = left_w
	var right_x: float = s.x - right_w

	# Dropdown at top-right of ship panel
	var dropdown_h: float = 26.0
	var dropdown_y: float = CONTENT_TOP + 4.0
	_fleet_dropdown.position = Vector2(right_x + 4, dropdown_y)
	if _fleet_dropdown._expanded:
		_fleet_dropdown.size.x = right_w - 8
	else:
		_fleet_dropdown.size = Vector2(right_w - 8, dropdown_h)

	# Grid areas
	var list_top: float = CONTENT_TOP + 38.0
	var list_h: float = s.y - list_top - BOTTOM_H - 4

	_station_grid_area = Rect2(4, list_top, left_w - 8, list_h)
	_ship_grid_area = Rect2(right_x + 4, list_top, right_w - 8, list_h)

	_compute_station_grid()
	_compute_ship_grid()

	# Center transfer buttons
	var cx: float = left_w + 4
	var btn_w: float = CENTER_W - 8
	var btn_h: float = 24.0
	var btn_y: float = list_top + 30

	_transfer_to_ship_btn.position = Vector2(cx, btn_y)
	_transfer_to_ship_btn.size = Vector2(btn_w, btn_h)
	_transfer_all_to_ship_btn.position = Vector2(cx, btn_y + btn_h + 4)
	_transfer_all_to_ship_btn.size = Vector2(btn_w, btn_h)

	_transfer_to_station_btn.position = Vector2(cx, btn_y + (btn_h + 4) * 2 + 16)
	_transfer_to_station_btn.size = Vector2(btn_w, btn_h)
	_transfer_all_to_station_btn.position = Vector2(cx, btn_y + (btn_h + 4) * 3 + 16)
	_transfer_all_to_station_btn.size = Vector2(btn_w, btn_h)

	# Back button (bottom-left)
	_back_btn.position = Vector2(8, s.y - BOTTOM_H - 28)
	_back_btn.size = Vector2(100, 24)


func _compute_station_grid() -> void:
	_station_card_rects.clear()
	if _station_items.is_empty():
		_station_total_content_h = 0.0
		return
	var area_w: float = _station_grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _station_items.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _station_grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _station_grid_area.position.y + row * (CARD_H + CARD_GAP) - _station_scroll_offset
		_station_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	@warning_ignore("integer_division")
	var total_rows: int = (_station_items.size() + cols - 1) / cols
	_station_total_content_h = total_rows * (CARD_H + CARD_GAP)


func _compute_ship_grid() -> void:
	_ship_card_rects.clear()
	if _ship_items.is_empty():
		_ship_total_content_h = 0.0
		return
	var area_w: float = _ship_grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _ship_items.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _ship_grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _ship_grid_area.position.y + row * (CARD_H + CARD_GAP) - _ship_scroll_offset
		_ship_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	@warning_ignore("integer_division")
	var total_rows: int = (_ship_items.size() + cols - 1) / cols
	_ship_total_content_h = total_rows * (CARD_H + CARD_GAP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fleet_dropdown != null:
		_layout_controls()


# =========================================================================
# INPUT
# =========================================================================

func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		# Let UIScreen handle close button
		super._gui_input(event)
		return

	if event is InputEventMouseMotion:
		var old_station: int = _hovered_station_idx
		var old_ship: int = _hovered_ship_idx
		_hovered_station_idx = -1
		_hovered_ship_idx = -1
		for i in _station_card_rects.size():
			if _station_card_rects[i].has_point(event.position) and _station_grid_area.has_point(event.position):
				_hovered_station_idx = i
				break
		for i in _ship_card_rects.size():
			if _ship_card_rects[i].has_point(event.position) and _ship_grid_area.has_point(event.position):
				_hovered_ship_idx = i
				break
		if _hovered_station_idx != old_station or _hovered_ship_idx != old_ship:
			queue_redraw()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Check station card clicks
			for i in _station_card_rects.size():
				if _station_card_rects[i].has_point(event.position) and _station_grid_area.has_point(event.position):
					_selected_station_item = i
					_update_button_visibility()
					queue_redraw()
					accept_event()
					return
			# Check ship card clicks
			for i in _ship_card_rects.size():
				if _ship_card_rects[i].has_point(event.position) and _ship_grid_area.has_point(event.position):
					_selected_ship_item = i
					_update_button_visibility()
					queue_redraw()
					accept_event()
					return

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _station_grid_area.has_point(event.position):
				_station_scroll_offset = maxf(0.0, _station_scroll_offset - 30.0)
				_compute_station_grid()
				queue_redraw()
				accept_event()
				return
			elif _ship_grid_area.has_point(event.position):
				_ship_scroll_offset = maxf(0.0, _ship_scroll_offset - 30.0)
				_compute_ship_grid()
				queue_redraw()
				accept_event()
				return

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _station_grid_area.has_point(event.position):
				var max_scroll: float = maxf(0.0, _station_total_content_h - _station_grid_area.size.y)
				_station_scroll_offset = minf(max_scroll, _station_scroll_offset + 30.0)
				_compute_station_grid()
				queue_redraw()
				accept_event()
				return
			elif _ship_grid_area.has_point(event.position):
				var max_scroll: float = maxf(0.0, _ship_total_content_h - _ship_grid_area.size.y)
				_ship_scroll_offset = minf(max_scroll, _ship_scroll_offset + 30.0)
				_compute_ship_grid()
				queue_redraw()
				accept_event()
				return

	# Let UIScreen handle close button click
	super._gui_input(event)


# =========================================================================
# DRAW
# =========================================================================

func _draw() -> void:
	var s: Vector2 = size

	# Background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))
	var edge_col = Color(0.0, 0.0, 0.02, 0.5)
	draw_rect(Rect2(0, 0, s.x, 50), edge_col)
	draw_rect(Rect2(0, s.y - 40, s.x, 40), edge_col)
	_draw_title(s)

	if not _is_open:
		return

	var font: Font = UITheme.get_font()
	var left_w: float = (s.x - CENTER_W) * 0.5
	var right_x: float = s.x - left_w
	var list_top: float = CONTENT_TOP + 38.0

	# Column headers
	draw_rect(Rect2(4, CONTENT_TOP + 8, 3, 14), UITheme.PRIMARY)
	draw_string(font, Vector2(14, CONTENT_TOP + 22), "STOCKAGE STATION",
		HORIZONTAL_ALIGNMENT_LEFT, int(left_w), UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	draw_rect(Rect2(right_x + 4, CONTENT_TOP + 8, 3, 14), UITheme.ACCENT)
	draw_string(font, Vector2(right_x + 14, CONTENT_TOP + 22), "SOUTE VAISSEAU",
		HORIZONTAL_ALIGNMENT_LEFT, int(left_w), UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	# Separator under headers
	draw_line(Vector2(4, list_top - 2), Vector2(s.x - 4, list_top - 2), UITheme.BORDER, 1.0)

	# Center column background
	draw_rect(Rect2(left_w, list_top, CENTER_W, s.y - list_top - BOTTOM_H), Color(0.02, 0.015, 0.01, 0.3))

	# Transfer label in center
	draw_string(font, Vector2(left_w + 8, list_top + 20), "TRANSFERT",
		HORIZONTAL_ALIGNMENT_LEFT, int(CENTER_W - 16), UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Draw card grids
	_draw_station_card_grid(font)
	_draw_ship_card_grid(font)

	# Empty state messages
	if _station_items.is_empty():
		draw_string(font, Vector2(_station_grid_area.position.x + 8, _station_grid_area.position.y + 24),
			"Aucun objet", HORIZONTAL_ALIGNMENT_LEFT, int(_station_grid_area.size.x),
			UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	if _ship_items.is_empty():
		draw_string(font, Vector2(_ship_grid_area.position.x + 8, _ship_grid_area.position.y + 24),
			"Soute vide", HORIZONTAL_ALIGNMENT_LEFT, int(_ship_grid_area.size.x),
			UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Bottom bar
	draw_line(Vector2(0, s.y - BOTTOM_H), Vector2(s.x, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Credits display
	if _player_data and _player_data.economy:
		var cr_text: String = "Credits: %s CR" % PlayerEconomy.format_credits(_player_data.economy.credits)
		draw_string(font, Vector2(120, s.y - BOTTOM_H + 22), cr_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Storage usage
	if _player_data and _player_data.refinery_manager:
		var storage = _player_data.refinery_manager.get_storage(_station_key)
		var total: int = storage.get_total()
		var cap: int = storage.capacity
		var st_text: String = "Stockage: %d / %d" % [total, cap]
		draw_string(font, Vector2(s.x - 220, s.y - BOTTOM_H + 22), st_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 200, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Scanline
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col = Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _draw_station_card_grid(font: Font) -> void:
	for i in _station_card_rects.size():
		var rect: Rect2 = _station_card_rects[i]
		if rect.end.y < _station_grid_area.position.y or rect.position.y > _station_grid_area.end.y:
			continue
		_draw_item_card_storage(font, rect, i, _station_items, _selected_station_item, _hovered_station_idx, UITheme.PRIMARY)


func _draw_ship_card_grid(font: Font) -> void:
	for i in _ship_card_rects.size():
		var rect: Rect2 = _ship_card_rects[i]
		if rect.end.y < _ship_grid_area.position.y or rect.position.y > _ship_grid_area.end.y:
			continue
		_draw_item_card_storage(font, rect, i, _ship_items, _selected_ship_item, _hovered_ship_idx, UITheme.ACCENT)


func _draw_item_card_storage(font: Font, rect: Rect2, idx: int, items: Array,
		selected_idx: int, hovered_idx: int, panel_accent: Color) -> void:
	if idx >= items.size():
		return
	var data: Dictionary = items[idx]
	if data.is_empty():
		return

	var is_sel: bool = idx == selected_idx
	var is_hov: bool = idx == hovered_idx

	# Card background
	var bg: Color
	if is_sel:
		bg = Color(panel_accent.r, panel_accent.g, panel_accent.b, 0.15)
	elif is_hov:
		bg = Color(0.025, 0.06, 0.12, 0.9)
	else:
		bg = Color(0.015, 0.04, 0.08, 0.8)
	draw_rect(rect, bg)

	# Border
	var bcol: Color
	if is_sel:
		bcol = panel_accent
	elif is_hov:
		bcol = UITheme.BORDER_HOVER
	else:
		bcol = UITheme.BORDER
	draw_rect(rect, bcol, false, 1.0)

	# Top glow if selected
	if is_sel:
		draw_line(Vector2(rect.position.x + 1, rect.position.y),
			Vector2(rect.end.x - 1, rect.position.y),
			Color(panel_accent.r, panel_accent.g, panel_accent.b, 0.3), 2.0)

	# Mini corners
	draw_corners(rect, 5.0, bcol)

	# Color pip (top-left)
	var item_color: Color = data.get("color", UITheme.TEXT)
	draw_rect(Rect2(rect.position.x + 6, rect.position.y + 6, 10, 10), item_color)

	# Cargo badge if source is cargo
	var source: String = data.get("source", "")
	if source == "cargo":
		draw_string(font, Vector2(rect.end.x - 22, rect.position.y + 14), "[C]",
			HORIZONTAL_ALIGNMENT_RIGHT, 18, UITheme.FONT_SIZE_TINY,
			Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.6))

	# Item name (centered)
	var item_name: String = data.get("name", "???")
	var name_col: Color = UITheme.TEXT if is_sel else UITheme.TEXT_DIM
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 34),
		item_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_SMALL, name_col)

	# Quantity (centered, bottom area)
	var qty: int = data.get("qty", 0)
	draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 10),
		str(qty), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_LABEL, UITheme.LABEL_VALUE)


func _process(_delta: float) -> void:
	if visible and _is_open:
		queue_redraw()
