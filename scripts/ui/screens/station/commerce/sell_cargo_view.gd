class_name SellCargoView
extends Control

# =============================================================================
# Sell Cargo View - Sell loot cargo items (metal, electronics, weapon_part…)
# Left: UIScrollList of cargo items, Right: detail panel + sell buttons
# =============================================================================

var _commerce_manager: CommerceManager = null

var _item_list: UIScrollList = null
var _sell_one_btn: UIButton = null
var _sell_all_btn: UIButton = null
var _cargo_items: Array[Dictionary] = []
var _selected_index: int = -1

const DETAIL_W := 240.0
const ROW_H := 44.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout)

	_item_list = UIScrollList.new()
	_item_list.row_height = ROW_H
	_item_list.item_draw_callback = _draw_item_row
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_double_clicked.connect(_on_item_double_clicked)
	_item_list.visible = false
	add_child(_item_list)

	_sell_one_btn = UIButton.new()
	_sell_one_btn.text = "VENDRE x1"
	_sell_one_btn.accent_color = UITheme.WARNING
	_sell_one_btn.visible = false
	_sell_one_btn.pressed.connect(_on_sell_one)
	add_child(_sell_one_btn)

	_sell_all_btn = UIButton.new()
	_sell_all_btn.text = "VENDRE TOUT"
	_sell_all_btn.accent_color = UITheme.WARNING
	_sell_all_btn.visible = false
	_sell_all_btn.pressed.connect(_on_sell_all)
	add_child(_sell_all_btn)


func setup(mgr: CommerceManager) -> void:
	_commerce_manager = mgr


func refresh() -> void:
	_item_list.visible = true
	_sell_one_btn.visible = true
	_sell_all_btn.visible = true
	_refresh_items()
	_layout()


func _layout() -> void:
	var s := size
	var list_w: float = s.x - DETAIL_W - 10.0
	_item_list.position = Vector2(0, 0)
	_item_list.size = Vector2(list_w, s.y)
	_sell_one_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 82)
	_sell_one_btn.size = Vector2(DETAIL_W - 20, 34)
	_sell_all_btn.position = Vector2(s.x - DETAIL_W + 10, s.y - 42)
	_sell_all_btn.size = Vector2(DETAIL_W - 20, 34)


func _refresh_items() -> void:
	_cargo_items.clear()
	if _commerce_manager and _commerce_manager.player_cargo:
		_cargo_items.assign(_commerce_manager.player_cargo.get_all())
	var list_items: Array = []
	for item in _cargo_items:
		list_items.append(item.get("name", ""))
	_item_list.items = list_items
	if _selected_index >= _cargo_items.size():
		_selected_index = -1
	_item_list.selected_index = _selected_index
	queue_redraw()


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	queue_redraw()


func _on_item_double_clicked(idx: int) -> void:
	_selected_index = idx
	_sell_one()


func _on_sell_one() -> void:
	_sell_one()


func _on_sell_all() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var item_name: String = item.get("name", "")
	var qty: int = item.get("quantity", 1)
	if _commerce_manager.sell_cargo(item_name, qty):
		var toast_mgr := _find_toast_manager()
		if toast_mgr:
			var total := PriceCatalog.get_cargo_price(item_name) * qty
			toast_mgr.show_toast("%s x%d vendu! +%s CR" % [item_name, qty, PlayerEconomy.format_credits(total)])
		_refresh_items()
	queue_redraw()


func _sell_one() -> void:
	if _commerce_manager == null: return
	if _selected_index < 0 or _selected_index >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[_selected_index]
	var item_name: String = item.get("name", "")
	if _commerce_manager.sell_cargo(item_name, 1):
		var toast_mgr := _find_toast_manager()
		if toast_mgr:
			toast_mgr.show_toast("%s vendu!" % item_name)
		_refresh_items()
	queue_redraw()


func _find_toast_manager() -> UIToastManager:
	var node := get_tree().root.find_child("UIToastManager", true, false)
	return node as UIToastManager if node else null


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# =========================================================================
# DRAWING
# =========================================================================
func _draw() -> void:
	var s := size
	var font: Font = UITheme.get_font()
	var detail_x: float = s.x - DETAIL_W

	# Detail panel background
	draw_rect(Rect2(detail_x, 0, DETAIL_W, s.y), Color(0.02, 0.04, 0.06, 0.5))
	draw_line(Vector2(detail_x, 0), Vector2(detail_x, s.y), UITheme.BORDER, 1.0)

	if _cargo_items.is_empty():
		draw_string(font, Vector2(detail_x + 10, 30), "Soute vide",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	if _selected_index < 0 or _selected_index >= _cargo_items.size():
		draw_string(font, Vector2(detail_x + 10, 30), "Selectionnez un objet",
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	var item: Dictionary = _cargo_items[_selected_index]
	var item_name: String = item.get("name", "")
	var item_type: String = item.get("type", "")
	var qty: int = item.get("quantity", 1)
	var unit_price := PriceCatalog.get_cargo_price(item_name)

	var y: float = 10.0

	# Name
	draw_string(font, Vector2(detail_x + 10, y + 14), item_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 24.0

	# Type
	if item_type != "":
		draw_string(font, Vector2(detail_x + 10, y + 12), "Type",
			HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
		draw_string(font, Vector2(detail_x + 95, y + 12), item_type,
			HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
		y += 18.0

	# Quantity
	draw_string(font, Vector2(detail_x + 10, y + 12), "Quantite",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), str(qty),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
	y += 18.0

	# Unit price
	draw_string(font, Vector2(detail_x + 10, y + 12), "Prix/u",
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(detail_x + 95, y + 12), PriceCatalog.format_price(unit_price),
		HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 105, UITheme.FONT_SIZE_SMALL, PlayerEconomy.CREDITS_COLOR)
	y += 24.0

	# Total sell price box
	var total_price := unit_price * qty
	y += 4.0
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28),
		Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_rect(Rect2(detail_x + 10, y, DETAIL_W - 20, 28), UITheme.WARNING, false, 1.0)
	draw_string(font, Vector2(detail_x + 10, y + 19),
		"TOTAL: +" + PriceCatalog.format_price(total_price),
		HORIZONTAL_ALIGNMENT_CENTER, DETAIL_W - 20, UITheme.FONT_SIZE_HEADER, PlayerEconomy.CREDITS_COLOR)


func _draw_item_row(ci: CanvasItem, idx: int, rect: Rect2, _item: Variant) -> void:
	if idx < 0 or idx >= _cargo_items.size(): return
	var item: Dictionary = _cargo_items[idx]
	var font: Font = UITheme.get_font()

	var is_sel: bool = (idx == _item_list.selected_index)
	if is_sel:
		ci.draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

	var item_name: String = item.get("name", "")
	var qty: int = item.get("quantity", 1)
	var icon_color_str: String = item.get("icon_color", "")
	var icon_col: Color = Color.from_string(icon_color_str, UITheme.TEXT_DIM) if icon_color_str != "" else UITheme.TEXT_DIM

	# Color badge
	ci.draw_rect(Rect2(rect.position.x + 6, rect.position.y + 8, 12, 12), icon_col)

	# Name + quantity
	var label := "%s x%d" % [item_name, qty]
	ci.draw_string(font, Vector2(rect.position.x + 24, rect.position.y + 18),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 0.55,
		UITheme.FONT_SIZE_SMALL, UITheme.TEXT if is_sel else UITheme.TEXT_DIM)

	# Price (right-aligned)
	var unit_price := PriceCatalog.get_cargo_price(item_name)
	ci.draw_string(font, Vector2(rect.position.x + rect.size.x * 0.6, rect.position.y + 18),
		"+" + PriceCatalog.format_price(unit_price) + "/u", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.35,
		UITheme.FONT_SIZE_SMALL, PlayerEconomy.CREDITS_COLOR)
