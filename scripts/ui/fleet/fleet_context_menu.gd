class_name FleetContextMenu
extends Control

# =============================================================================
# Fleet Context Menu — Holographic popup menu for fleet orders
# Appears at cursor position, shows filtered order list
# Custom _draw(), no child Controls
# =============================================================================

signal order_selected(order_id: StringName, params: Dictionary)
signal cancelled

var _orders: Array[Dictionary] = []
var _context: Dictionary = {}
var _hovered_index: int = -1

const ITEM_H: float = 28.0
const PADDING: float = 8.0
const MENU_W: float = 180.0
const CORNER_LEN: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100


func show_menu(pos: Vector2, orders: Array[Dictionary], context: Dictionary) -> void:
	_orders = orders
	_context = context
	_hovered_index = -1
	visible = true

	var menu_h: float = PADDING * 2 + _orders.size() * ITEM_H
	# Clamp to screen bounds
	var parent_size: Vector2 = get_parent_control().size if get_parent_control() else get_viewport_rect().size
	if pos.x + MENU_W > parent_size.x - 10:
		pos.x = parent_size.x - MENU_W - 10
	if pos.y + menu_h > parent_size.y - 10:
		pos.y = parent_size.y - menu_h - 10

	position = pos
	size = Vector2(MENU_W, menu_h)
	queue_redraw()


func _draw() -> void:
	if _orders.is_empty():
		return

	var font: Font = UITheme.get_font()
	var menu_h: float = PADDING * 2 + _orders.size() * ITEM_H
	var rect := Rect2(Vector2.ZERO, Vector2(MENU_W, menu_h))

	# Background
	draw_rect(rect, Color(0.0, 0.02, 0.06, 0.92))
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cc := UITheme.PRIMARY
	draw_line(Vector2(0, 0), Vector2(CORNER_LEN, 0), cc, 1.5)
	draw_line(Vector2(0, 0), Vector2(0, CORNER_LEN), cc, 1.5)
	draw_line(Vector2(MENU_W, 0), Vector2(MENU_W - CORNER_LEN, 0), cc, 1.5)
	draw_line(Vector2(MENU_W, 0), Vector2(MENU_W, CORNER_LEN), cc, 1.5)
	draw_line(Vector2(0, menu_h), Vector2(CORNER_LEN, menu_h), cc, 1.5)
	draw_line(Vector2(0, menu_h), Vector2(0, menu_h - CORNER_LEN), cc, 1.5)
	draw_line(Vector2(MENU_W, menu_h), Vector2(MENU_W - CORNER_LEN, menu_h), cc, 1.5)
	draw_line(Vector2(MENU_W, menu_h), Vector2(MENU_W, menu_h - CORNER_LEN), cc, 1.5)

	# Items
	for i in _orders.size():
		var y: float = PADDING + i * ITEM_H
		var item_rect := Rect2(2, y, MENU_W - 4, ITEM_H)

		# Hover highlight
		if i == _hovered_index:
			draw_rect(item_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15))

		# Label
		var text_col: Color = UITheme.PRIMARY if i == _hovered_index else UITheme.TEXT
		draw_string(font, Vector2(PADDING + 4, y + ITEM_H - 8), _orders[i]["display_name"], HORIZONTAL_ALIGNMENT_LEFT, MENU_W - PADDING * 2 - 8, UITheme.FONT_SIZE_BODY, text_col)

		# Separator line (except after last)
		if i < _orders.size() - 1:
			draw_line(Vector2(PADDING, y + ITEM_H), Vector2(MENU_W - PADDING, y + ITEM_H), Color(UITheme.BORDER, 0.3), 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local_y: float = event.position.y - PADDING
		var idx: int = int(local_y / ITEM_H)
		if idx >= 0 and idx < _orders.size() and event.position.x >= 0 and event.position.x <= MENU_W:
			_hovered_index = idx
		else:
			_hovered_index = -1
		queue_redraw()
		accept_event()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_index >= 0 and _hovered_index < _orders.size():
				var order: Dictionary = _orders[_hovered_index]
				var params: Dictionary = {}
				# Squadron orders (sq_ prefix) don't use FleetOrderRegistry params
				if not String(order["id"]).begins_with("sq_"):
					params = FleetOrderRegistry.build_default_params(order["id"], _context)
				order_selected.emit(order["id"], params)
			else:
				cancelled.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancelled.emit()
			accept_event()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Escape closes menu
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()
		return
	# Click outside closes menu
	if event is InputEventMouseButton and event.pressed:
		var local_pos: Vector2 = event.position - global_position
		if local_pos.x < 0 or local_pos.x > MENU_W or local_pos.y < 0 or local_pos.y > size.y:
			cancelled.emit()
			# Right-click outside: let event propagate to StellarMap for new order
			if event.button_index != MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
