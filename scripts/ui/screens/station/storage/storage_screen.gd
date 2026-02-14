class_name StorageScreen
extends UIScreen

# =============================================================================
# Storage Screen — Dedicated ENTREPOT service.
# Two panels: station storage (left) + ship hold (right) with fleet dropdown.
# Transfers ores, refined materials, and cargo between ship and station.
# =============================================================================

signal storage_closed

var _player_data: PlayerData = null
var _station_key: String = ""
var _station_name: String = "STATION"
var _selected_fleet_index: int = 0

# UI elements
var _station_list: UIScrollList = null
var _ship_list: UIScrollList = null
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

const TRANSFER_QTY := 10
const CONTENT_TOP := 65.0
const BOTTOM_H := 50.0
const CENTER_W := 90.0


func _ready() -> void:
	screen_title = "ENTREPOT"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Fleet dropdown
	_fleet_dropdown = UIDropdown.new()
	_fleet_dropdown.visible = false
	_fleet_dropdown.option_selected.connect(_on_fleet_changed)
	add_child(_fleet_dropdown)

	# Station list (left)
	_station_list = UIScrollList.new()
	_station_list.item_draw_callback = _draw_storage_row
	_station_list.item_selected.connect(_on_station_selected)
	add_child(_station_list)

	# Ship list (right)
	_ship_list = UIScrollList.new()
	_ship_list.item_draw_callback = _draw_storage_row
	_ship_list.item_selected.connect(_on_ship_selected)
	add_child(_ship_list)

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


func setup(pdata: PlayerData, station_key: String, sname: String) -> void:
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
	var fleet := _player_data.fleet
	var current_station_id: String = ""
	var active_fs := fleet.get_active()
	if active_fs:
		current_station_id = active_fs.docked_station_id
	var dropdown_sel: int = 0
	for i in fleet.ships.size():
		var fs: FleetShip = fleet.ships[i]
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


func _get_selected_fleet_ship() -> FleetShip:
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
	_station_list.selected_index = -1
	_ship_list.selected_index = -1
	_update_button_visibility()
	_layout_controls()
	queue_redraw()


func _rebuild_lists() -> void:
	_station_items.clear()
	_ship_items.clear()

	# Station storage items
	if _player_data and _player_data.refinery_manager:
		var storage := _player_data.refinery_manager.get_storage(_station_key)
		var items := storage.get_all_items()
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
	var fs := _get_selected_fleet_ship()
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

	_station_list.items = _station_items
	_ship_list.items = _ship_items
	_station_list.queue_redraw()
	_ship_list.queue_redraw()


# =========================================================================
# SELECTION
# =========================================================================

func _on_station_selected(idx: int) -> void:
	_selected_station_item = idx
	_update_button_visibility()
	queue_redraw()


func _on_ship_selected(idx: int) -> void:
	_selected_ship_item = idx
	_update_button_visibility()
	queue_redraw()


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
	var mgr := _player_data.refinery_manager if _player_data else null
	if mgr == null:
		return
	var fs := _get_selected_fleet_ship()
	if fs == null:
		return
	# Storage -> ship: all storage items become resources on the ship
	mgr.transfer_to_ship_from_storage(_station_key, item.id, qty, fs, _player_data)
	_refresh()


func _do_transfer_to_station(item: Dictionary, qty: int) -> void:
	var mgr := _player_data.refinery_manager if _player_data else null
	if mgr == null:
		return
	var fs := _get_selected_fleet_ship()
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
	_fleet_dropdown.size = Vector2(right_w - 8, dropdown_h)

	# Lists
	var list_top: float = CONTENT_TOP + 38.0
	var list_h: float = s.y - list_top - BOTTOM_H - 4

	_station_list.position = Vector2(4, list_top)
	_station_list.size = Vector2(left_w - 8, list_h)

	_ship_list.position = Vector2(right_x + 4, list_top)
	_ship_list.size = Vector2(right_w - 8, list_h)

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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fleet_dropdown != null:
		_layout_controls()


# =========================================================================
# DRAW
# =========================================================================

func _draw() -> void:
	var s: Vector2 = size

	# Background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))
	var edge_col := Color(0.0, 0.0, 0.02, 0.5)
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

	# Bottom bar
	draw_line(Vector2(0, s.y - BOTTOM_H), Vector2(s.x, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Credits display
	if _player_data and _player_data.economy:
		var cr_text: String = "Credits: %s CR" % PlayerEconomy.format_credits(_player_data.economy.credits)
		draw_string(font, Vector2(120, s.y - BOTTOM_H + 22), cr_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Storage usage
	if _player_data and _player_data.refinery_manager:
		var storage := _player_data.refinery_manager.get_storage(_station_key)
		var total: int = storage.get_total()
		var cap: int = storage.capacity
		var st_text: String = "Stockage: %d / %d" % [total, cap]
		draw_string(font, Vector2(s.x - 220, s.y - BOTTOM_H + 22), st_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 200, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Scanline
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col := Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _draw_storage_row(ctrl: Control, _idx: int, rect: Rect2, item: Variant) -> void:
	var data := item as Dictionary
	if data == null or data.is_empty():
		return
	var font: Font = UITheme.get_font()
	var x: float = rect.position.x
	var y: float = rect.position.y + rect.size.y - 5
	var w: float = rect.size.x

	# Color pip
	var col: Color = data.get("color", UITheme.TEXT)
	ctrl.draw_rect(Rect2(x + 4, rect.position.y + 5, 10, 12), col)

	# Name
	var item_name: String = data.get("name", "???")
	var source: String = data.get("source", "")
	if source == "cargo":
		item_name += " [C]"
	ctrl.draw_string(font, Vector2(x + 20, y), item_name,
		HORIZONTAL_ALIGNMENT_LEFT, int(w * 0.65), UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Quantity
	var qty: int = data.get("qty", 0)
	ctrl.draw_string(font, Vector2(x + w - 60, y), str(qty),
		HORIZONTAL_ALIGNMENT_RIGHT, 50, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
