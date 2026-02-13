class_name FleetMiningSubmenu
extends Control

# =============================================================================
# Fleet Mining Submenu — Checkbox list of minable resources
# Appears next to FleetContextMenu when "MINER" is clicked.
# Custom _draw(), same holo style as FleetContextMenu.
# =============================================================================

signal confirmed(resource_filter: Array)
signal cancelled

var _resources: Array[Dictionary] = []  # [{id, display_name, color, checked}]
var _hovered_index: int = -1
var _all_checked: bool = true

const ITEM_H: float = 26.0
const PADDING: float = 8.0
const MENU_W: float = 190.0
const CORNER_LEN: float = 6.0
const HEADER_H: float = 28.0
const BUTTON_H: float = 32.0
const CHECK_SIZE: float = 14.0
const CHECK_MARGIN: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 101  # Above FleetContextMenu (z=100)
	_build_resource_list()


func _build_resource_list() -> void:
	_resources.clear()
	var ids := MiningRegistry.get_all_ids()
	for id in ids:
		var res := MiningRegistry.get_resource(id)
		if res:
			_resources.append({
				"id": id,
				"display_name": res.display_name.to_upper(),
				"color": res.icon_color,
				"checked": true,
			})
	_all_checked = true


func show_at(pos: Vector2) -> void:
	# Total height: HEADER (TOUT) + items + CONFIRMER button + padding
	var total_h: float = PADDING + HEADER_H + _resources.size() * ITEM_H + BUTTON_H + PADDING

	# Clamp to screen bounds
	var vp_size: Vector2 = get_viewport_rect().size
	if pos.x + MENU_W > vp_size.x - 10:
		pos.x -= MENU_W + 10
	if pos.y + total_h > vp_size.y - 10:
		pos.y = vp_size.y - total_h - 10

	position = pos
	size = Vector2(MENU_W, total_h)
	visible = true
	queue_redraw()


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var rect := Rect2(Vector2.ZERO, size)

	# Background
	draw_rect(rect, Color(0.0, 0.02, 0.06, 0.94))
	draw_rect(rect, UITheme.BORDER, false, 1.0)

	# Corner accents
	var cc := UITheme.PRIMARY
	draw_line(Vector2(0, 0), Vector2(CORNER_LEN, 0), cc, 1.5)
	draw_line(Vector2(0, 0), Vector2(0, CORNER_LEN), cc, 1.5)
	draw_line(Vector2(MENU_W, 0), Vector2(MENU_W - CORNER_LEN, 0), cc, 1.5)
	draw_line(Vector2(MENU_W, 0), Vector2(MENU_W, CORNER_LEN), cc, 1.5)
	draw_line(Vector2(0, size.y), Vector2(CORNER_LEN, size.y), cc, 1.5)
	draw_line(Vector2(0, size.y), Vector2(0, size.y - CORNER_LEN), cc, 1.5)
	draw_line(Vector2(MENU_W, size.y), Vector2(MENU_W - CORNER_LEN, size.y), cc, 1.5)
	draw_line(Vector2(MENU_W, size.y), Vector2(MENU_W, size.y - CORNER_LEN), cc, 1.5)

	var y: float = PADDING

	# --- "TOUT" header with checkbox ---
	var tout_rect := Rect2(2, y, MENU_W - 4, HEADER_H)
	if _hovered_index == -2:
		draw_rect(tout_rect, Color(cc.r, cc.g, cc.b, 0.15))
	_draw_checkbox(Vector2(PADDING + CHECK_MARGIN, y + (HEADER_H - CHECK_SIZE) * 0.5), _all_checked, cc)
	var tout_col: Color = cc if _hovered_index == -2 else UITheme.TEXT
	draw_string(font, Vector2(PADDING + CHECK_MARGIN + CHECK_SIZE + 8, y + HEADER_H - 8), "TOUT", HORIZONTAL_ALIGNMENT_LEFT, MENU_W - PADDING * 2, UITheme.FONT_SIZE_BODY, tout_col)
	y += HEADER_H

	# Separator
	draw_line(Vector2(PADDING, y), Vector2(MENU_W - PADDING, y), Color(UITheme.BORDER, 0.4), 1.0)

	# --- Resource items ---
	for i in _resources.size():
		var item: Dictionary = _resources[i]
		var item_rect := Rect2(2, y, MENU_W - 4, ITEM_H)

		if _hovered_index == i:
			draw_rect(item_rect, Color(cc.r, cc.g, cc.b, 0.12))

		var res_color: Color = item["color"]
		_draw_checkbox(Vector2(PADDING + CHECK_MARGIN, y + (ITEM_H - CHECK_SIZE) * 0.5), item["checked"], res_color)

		var text_col: Color = res_color if _hovered_index == i else Color(res_color, 0.8)
		draw_string(font, Vector2(PADDING + CHECK_MARGIN + CHECK_SIZE + 8, y + ITEM_H - 7), item["display_name"], HORIZONTAL_ALIGNMENT_LEFT, MENU_W - PADDING * 2, UITheme.FONT_SIZE_BODY - 1, text_col)
		y += ITEM_H

	# Separator before button
	draw_line(Vector2(PADDING, y + 2), Vector2(MENU_W - PADDING, y + 2), Color(UITheme.BORDER, 0.4), 1.0)

	# --- CONFIRMER button ---
	var btn_rect := Rect2(PADDING, y + 4, MENU_W - PADDING * 2, BUTTON_H - 8)
	var btn_hovered: bool = _hovered_index == -3
	var btn_bg := Color(cc.r, cc.g, cc.b, 0.25 if btn_hovered else 0.1)
	draw_rect(btn_rect, btn_bg)
	draw_rect(btn_rect, Color(cc, 0.6), false, 1.0)
	var btn_col: Color = cc if btn_hovered else UITheme.TEXT
	var btn_text_x: float = btn_rect.position.x + (btn_rect.size.x - font.get_string_size("CONFIRMER", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY).x) * 0.5
	draw_string(font, Vector2(btn_text_x, y + BUTTON_H - 12), "CONFIRMER", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, btn_col)


func _draw_checkbox(pos: Vector2, checked: bool, color: Color) -> void:
	var rect := Rect2(pos, Vector2(CHECK_SIZE, CHECK_SIZE))
	draw_rect(rect, Color(color, 0.15))
	draw_rect(rect, Color(color, 0.6), false, 1.0)
	if checked:
		# Draw check mark
		var cx: float = pos.x + 3.0
		var cy: float = pos.y + CHECK_SIZE * 0.5
		draw_line(Vector2(cx, cy), Vector2(cx + 3, cy + 4), color, 2.0)
		draw_line(Vector2(cx + 3, cy + 4), Vector2(cx + CHECK_SIZE - 5, cy - 3), color, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovered_index = _index_at_pos(event.position)
		queue_redraw()
		accept_event()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _index_at_pos(event.position)
		if idx == -2:
			# TOUT toggle
			_all_checked = not _all_checked
			for item in _resources:
				item["checked"] = _all_checked
			queue_redraw()
		elif idx >= 0 and idx < _resources.size():
			# Toggle individual resource
			_resources[idx]["checked"] = not _resources[idx]["checked"]
			_update_all_checked_state()
			queue_redraw()
		elif idx == -3:
			# CONFIRMER
			_emit_confirmed()
		accept_event()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancelled.emit()
		accept_event()


func _emit_confirmed() -> void:
	var filter: Array = []
	if not _all_checked:
		for item in _resources:
			if item["checked"]:
				filter.append(item["id"])
	# Empty filter = mine everything (all checked or TOUT)
	confirmed.emit(filter)


func _update_all_checked_state() -> void:
	_all_checked = true
	for item in _resources:
		if not item["checked"]:
			_all_checked = false
			return


## Returns: -2 = TOUT, 0..N = resource index, -3 = CONFIRMER, -1 = nothing
func _index_at_pos(mouse_pos: Vector2) -> int:
	var y: float = PADDING
	# TOUT header
	if mouse_pos.y >= y and mouse_pos.y < y + HEADER_H:
		return -2
	y += HEADER_H

	# Resource items
	for i in _resources.size():
		if mouse_pos.y >= y and mouse_pos.y < y + ITEM_H:
			return i
		y += ITEM_H

	# CONFIRMER button zone
	if mouse_pos.y >= y and mouse_pos.y < y + BUTTON_H:
		return -3

	return -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()
		return
	# Click outside closes submenu
	if event is InputEventMouseButton and event.pressed:
		var local_pos: Vector2 = event.position - global_position
		if local_pos.x < 0 or local_pos.x > MENU_W or local_pos.y < 0 or local_pos.y > size.y:
			cancelled.emit()
			if event.button_index != MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
