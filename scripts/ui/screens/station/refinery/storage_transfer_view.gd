class_name StorageTransferView
extends Control

# =============================================================================
# Storage Transfer View — two lists (station / ship) with transfer buttons.
# Allows moving ores and refined materials between ship and station.
# =============================================================================

var _manager: RefineryManager = null
var _station_key: String = ""
var _player_data: PlayerData = null

var _station_list: UIScrollList = null
var _ship_list: UIScrollList = null
var _transfer_to_station_btn: UIButton = null
var _transfer_to_ship_btn: UIButton = null
var _transfer_all_to_station_btn: UIButton = null
var _transfer_all_to_ship_btn: UIButton = null

var _station_items: Array = []  # [{id: StringName, qty: int, name: String, color: Color}]
var _ship_items: Array = []     # [{id: StringName, qty: int, name: String, color: Color}]
var _selected_station_item: int = -1
var _selected_ship_item: int = -1

const TRANSFER_QTY := 10


func _ready() -> void:
	clip_contents = true

	_station_list = UIScrollList.new()
	_station_list.item_draw_callback = _draw_storage_row
	_station_list.item_selected.connect(_on_station_selected)
	add_child(_station_list)

	_ship_list = UIScrollList.new()
	_ship_list.item_draw_callback = _draw_storage_row
	_ship_list.item_selected.connect(_on_ship_selected)
	add_child(_ship_list)

	# Transfer buttons
	_transfer_to_ship_btn = UIButton.new()
	_transfer_to_ship_btn.text = "← CHARGER x%d" % TRANSFER_QTY
	_transfer_to_ship_btn.accent_color = UITheme.ACCENT
	_transfer_to_ship_btn.pressed.connect(_on_transfer_to_ship)
	_transfer_to_ship_btn.visible = false
	add_child(_transfer_to_ship_btn)

	_transfer_to_station_btn = UIButton.new()
	_transfer_to_station_btn.text = "DECHARGER → x%d" % TRANSFER_QTY
	_transfer_to_station_btn.accent_color = UITheme.PRIMARY
	_transfer_to_station_btn.pressed.connect(_on_transfer_to_station)
	_transfer_to_station_btn.visible = false
	add_child(_transfer_to_station_btn)

	_transfer_all_to_ship_btn = UIButton.new()
	_transfer_all_to_ship_btn.text = "← TOUT"
	_transfer_all_to_ship_btn.accent_color = UITheme.ACCENT
	_transfer_all_to_ship_btn.pressed.connect(_on_transfer_all_to_ship)
	_transfer_all_to_ship_btn.visible = false
	add_child(_transfer_all_to_ship_btn)

	_transfer_all_to_station_btn = UIButton.new()
	_transfer_all_to_station_btn.text = "TOUT →"
	_transfer_all_to_station_btn.accent_color = UITheme.PRIMARY
	_transfer_all_to_station_btn.pressed.connect(_on_transfer_all_to_station)
	_transfer_all_to_station_btn.visible = false
	add_child(_transfer_all_to_station_btn)


func setup(mgr: RefineryManager, station_key: String, pdata: PlayerData) -> void:
	_manager = mgr
	_station_key = station_key
	_player_data = pdata


func refresh() -> void:
	_rebuild_lists()
	_selected_station_item = -1
	_selected_ship_item = -1
	_station_list.selected_index = -1
	_ship_list.selected_index = -1
	_update_button_visibility()
	_layout()
	queue_redraw()


func _rebuild_lists() -> void:
	_station_items.clear()
	_ship_items.clear()

	# Station storage
	if _manager:
		var storage := _manager.get_storage(_station_key)
		var items := storage.get_all_items()
		for item_id in items:
			_station_items.append({
				id = item_id,
				qty = items[item_id],
				name = RefineryRegistry.get_display_name(item_id),
				color = RefineryRegistry.get_item_color(item_id),
			})
		# Sort by name
		_station_items.sort_custom(func(a, b): return a.name < b.name)

	# Ship resources (mining ores)
	if _player_data and _player_data.fleet:
		var active := _player_data.fleet.get_active()
		if active:
			for res_id in active.ship_resources:
				var qty: int = active.ship_resources[res_id]
				if qty > 0:
					_ship_items.append({
						id = res_id,
						qty = qty,
						name = RefineryRegistry.get_display_name(res_id),
						color = RefineryRegistry.get_item_color(res_id),
					})
			_ship_items.sort_custom(func(a, b): return a.name < b.name)

	_station_list.items = _station_items
	_ship_list.items = _ship_items
	_station_list.queue_redraw()
	_ship_list.queue_redraw()


func _on_station_selected(idx: int) -> void:
	_selected_station_item = idx
	_update_button_visibility()
	queue_redraw()


func _on_ship_selected(idx: int) -> void:
	_selected_ship_item = idx
	_update_button_visibility()
	queue_redraw()


func _on_transfer_to_ship() -> void:
	if _selected_station_item < 0 or _selected_station_item >= _station_items.size():
		return
	var item: Dictionary = _station_items[_selected_station_item]
	if _manager:
		_manager.transfer_to_ship(_station_key, item.id, TRANSFER_QTY, _player_data)
	_rebuild_lists()
	queue_redraw()


func _on_transfer_to_station() -> void:
	if _selected_ship_item < 0 or _selected_ship_item >= _ship_items.size():
		return
	var item: Dictionary = _ship_items[_selected_ship_item]
	if _manager:
		_manager.transfer_to_storage(_station_key, item.id, TRANSFER_QTY, _player_data)
	_rebuild_lists()
	queue_redraw()


func _on_transfer_all_to_ship() -> void:
	if _selected_station_item < 0 or _selected_station_item >= _station_items.size():
		return
	var item: Dictionary = _station_items[_selected_station_item]
	if _manager:
		_manager.transfer_to_ship(_station_key, item.id, item.qty, _player_data)
	_rebuild_lists()
	queue_redraw()


func _on_transfer_all_to_station() -> void:
	if _selected_ship_item < 0 or _selected_ship_item >= _ship_items.size():
		return
	var item: Dictionary = _ship_items[_selected_ship_item]
	if _manager:
		_manager.transfer_to_storage(_station_key, item.id, item.qty, _player_data)
	_rebuild_lists()
	queue_redraw()


func _update_button_visibility() -> void:
	var has_station_sel: bool = _selected_station_item >= 0 and _selected_station_item < _station_items.size()
	var has_ship_sel: bool = _selected_ship_item >= 0 and _selected_ship_item < _ship_items.size()
	_transfer_to_ship_btn.visible = has_station_sel
	_transfer_all_to_ship_btn.visible = has_station_sel
	_transfer_to_station_btn.visible = has_ship_sel
	_transfer_all_to_station_btn.visible = has_ship_sel


func _layout() -> void:
	var s: Vector2 = size
	var header_h: float = 36.0
	var list_h: float = s.y - header_h - 44
	var half_w: float = (s.x - 80) * 0.5  # 80px center for buttons

	_station_list.position = Vector2(0, header_h)
	_station_list.size = Vector2(half_w, list_h)

	_ship_list.position = Vector2(s.x - half_w, header_h)
	_ship_list.size = Vector2(half_w, list_h)

	# Center buttons
	var cx: float = half_w + 4
	var btn_w: float = 72.0
	var btn_h: float = 24.0
	var btn_y: float = header_h + 20

	_transfer_to_ship_btn.position = Vector2(cx, btn_y)
	_transfer_to_ship_btn.size = Vector2(btn_w, btn_h)
	_transfer_all_to_ship_btn.position = Vector2(cx, btn_y + btn_h + 4)
	_transfer_all_to_ship_btn.size = Vector2(btn_w, btn_h)

	_transfer_to_station_btn.position = Vector2(cx, btn_y + (btn_h + 4) * 2 + 12)
	_transfer_to_station_btn.size = Vector2(btn_w, btn_h)
	_transfer_all_to_station_btn.position = Vector2(cx, btn_y + (btn_h + 4) * 3 + 12)
	_transfer_all_to_station_btn.size = Vector2(btn_w, btn_h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _draw() -> void:
	var s: Vector2 = size
	var font: Font = UITheme.get_font()
	var half_w: float = (s.x - 80) * 0.5

	# Column headers
	draw_rect(Rect2(0, 0, 3, 14), UITheme.PRIMARY)
	draw_string(font, Vector2(10, 16), "STOCKAGE STATION",
		HORIZONTAL_ALIGNMENT_LEFT, int(half_w), UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	draw_rect(Rect2(s.x - half_w, 0, 3, 14), UITheme.ACCENT)
	draw_string(font, Vector2(s.x - half_w + 10, 16), "VAISSEAU",
		HORIZONTAL_ALIGNMENT_LEFT, int(half_w), UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	# Separators
	draw_line(Vector2(0, 28), Vector2(s.x, 28), UITheme.BORDER, 1.0)

	# Center column background
	draw_rect(Rect2(half_w, 28, 80, s.y - 28), Color(0.02, 0.015, 0.01, 0.3))

	# Transfer arrows label
	draw_string(font, Vector2(half_w + 8, 52), "TRANSFERT",
		HORIZONTAL_ALIGNMENT_LEFT, 72, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


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
	ctrl.draw_string(font, Vector2(x + 20, y), item_name,
		HORIZONTAL_ALIGNMENT_LEFT, int(w * 0.65), UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Quantity
	var qty: int = data.get("qty", 0)
	ctrl.draw_string(font, Vector2(x + w - 60, y), str(qty),
		HORIZONTAL_ALIGNMENT_RIGHT, 50, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
