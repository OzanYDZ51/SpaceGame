class_name LootScreen
extends UIScreen

# =============================================================================
# Loot Screen - Overlay to pick up items from a cargo crate
# Holographic AAA style matching Equipment/Station screens.
# =============================================================================

signal loot_collected(selected_items: Array[Dictionary])

var _crate_contents: Array[Dictionary] = []
var _selected: Array[bool] = []
var _scroll_offset: int = 0
var _pulse_time: float = 0.0

var _take_all_btn: UIButton = null
var _take_btn: UIButton = null
var _leave_btn: UIButton = null

const CONTENT_TOP := 80.0
const ROW_H := 44.0
const PANEL_W := 420.0
const BTN_W := 150.0
const BTN_H := 38.0
const MAX_VISIBLE_ROWS := 8


func _ready() -> void:
	screen_title = Locale.t("loot.title")
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	_take_all_btn = UIButton.new()
	_take_all_btn.text = Locale.t("loot.take_all")
	_take_all_btn.visible = false
	_take_all_btn.pressed.connect(_on_take_all)
	add_child(_take_all_btn)

	_take_btn = UIButton.new()
	_take_btn.text = Locale.t("loot.take")
	_take_btn.visible = false
	_take_btn.pressed.connect(_on_take_selected)
	add_child(_take_btn)

	_leave_btn = UIButton.new()
	_leave_btn.text = Locale.t("loot.abandon")
	_leave_btn.accent_color = UITheme.WARNING
	_leave_btn.visible = false
	_leave_btn.pressed.connect(_on_leave)
	add_child(_leave_btn)


func set_contents(contents: Array[Dictionary]) -> void:
	_crate_contents = contents.duplicate(true)
	_selected.clear()
	for i in _crate_contents.size():
		_selected.append(true)  # All selected by default
	_scroll_offset = 0


func _on_opened() -> void:
	_take_all_btn.visible = true
	_take_btn.visible = true
	_leave_btn.visible = true
	_layout_controls()


func _on_closed() -> void:
	_take_all_btn.visible = false
	_take_btn.visible = false
	_leave_btn.visible = false


func _process(delta: float) -> void:
	_pulse_time += delta


func _layout_controls() -> void:
	var s := size
	var cx := s.x * 0.5
	var btn_y := s.y - 70.0
	var btn_total := BTN_W * 3 + 30.0
	var bx := cx - btn_total * 0.5

	_take_all_btn.position = Vector2(bx, btn_y)
	_take_all_btn.size = Vector2(BTN_W, BTN_H)
	_take_btn.position = Vector2(bx + BTN_W + 15, btn_y)
	_take_btn.size = Vector2(BTN_W, BTN_H)
	_leave_btn.position = Vector2(bx + (BTN_W + 15) * 2, btn_y)
	_leave_btn.size = Vector2(BTN_W, BTN_H)


func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Click on rows to toggle selection
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := size
		var cx := s.x * 0.5
		var panel_x := cx - PANEL_W * 0.5
		var lx: float = event.position.x
		var ly: float = event.position.y
		if lx >= panel_x and lx <= panel_x + PANEL_W:
			var row_y := ly - CONTENT_TOP
			if row_y >= 0:
				var idx := int(row_y / ROW_H) + _scroll_offset
				if idx >= 0 and idx < _crate_contents.size():
					_selected[idx] = not _selected[idx]
					queue_redraw()
					accept_event()

	# Scroll
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_offset = maxi(_scroll_offset - 1, 0)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_scroll_offset = mini(_scroll_offset + 1, maxi(0, _crate_contents.size() - MAX_VISIBLE_ROWS))
			queue_redraw()
			accept_event()


# =============================================================================
# DRAW
# =============================================================================
func _draw() -> void:
	var s := size
	var cx := s.x * 0.5
	var font := UITheme.get_font_medium()

	# Background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.6))

	# Vignette top/bottom
	draw_rect(Rect2(0, 0, s.x, 50), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 34, s.x, 34), Color(0.0, 0.0, 0.02, 0.5))

	if not _is_open:
		return

	# Title
	draw_string(font, Vector2(0, 38), Locale.t("loot.title"),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, UITheme.PRIMARY)

	# Subtitle: item count
	var total: int = 0
	for item in _crate_contents:
		total += item.get("quantity", 1)
	draw_string(font, Vector2(0, 58), Locale.t("loot.item_count") % [total, "s" if total > 1 else ""],
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM)

	# Panel background
	var panel_x := cx - PANEL_W * 0.5
	var panel_h: float = mini(_crate_contents.size(), MAX_VISIBLE_ROWS) * ROW_H + 8.0
	var panel_rect := Rect2(panel_x, CONTENT_TOP - 4, PANEL_W, panel_h)
	draw_rect(panel_rect, Color(0.0, 0.02, 0.06, 0.5))
	draw_rect(panel_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), false, 1.0)

	# Item rows
	var visible_count := mini(_crate_contents.size() - _scroll_offset, MAX_VISIBLE_ROWS)
	for i in visible_count:
		var idx := i + _scroll_offset
		var item: Dictionary = _crate_contents[idx]
		var ry := CONTENT_TOP + i * ROW_H
		var selected: bool = _selected[idx]

		# Row highlight if selected
		if selected:
			draw_rect(Rect2(panel_x + 2, ry, PANEL_W - 4, ROW_H - 2), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08))

		# Checkbox
		var cb_x := panel_x + 12.0
		var cb_y := ry + 10.0
		var cb_size := 18.0
		draw_rect(Rect2(cb_x, cb_y, cb_size, cb_size), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.2), false, 1.0)
		if selected:
			# Checkmark
			draw_rect(Rect2(cb_x + 3, cb_y + 3, cb_size - 6, cb_size - 6), UITheme.PRIMARY)

		# Color swatch
		var icon_col: Color = item.get("icon_color", Color.WHITE)
		draw_rect(Rect2(panel_x + 40, ry + 12, 14, 14), icon_col)

		# Item name
		var name_col := UITheme.TEXT if selected else UITheme.TEXT_DIM
		draw_string(font, Vector2(panel_x + 62, ry + 26), item.get("name", "???"),
			HORIZONTAL_ALIGNMENT_LEFT, 200, 14, name_col)

		# Type
		draw_string(font, Vector2(panel_x + 270, ry + 26), item.get("type", "").to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, 80, 13, UITheme.TEXT_DIM)

		# Quantity
		draw_string(font, Vector2(panel_x + PANEL_W - 60, ry + 26), "x%d" % item.get("quantity", 1),
			HORIZONTAL_ALIGNMENT_RIGHT, 50, 14, icon_col)

		# Separator line
		draw_line(Vector2(panel_x + 8, ry + ROW_H - 2), Vector2(panel_x + PANEL_W - 8, ry + ROW_H - 2),
			Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08), 1.0)

	# Scroll indicator
	if _crate_contents.size() > MAX_VISIBLE_ROWS:
		var scroll_text := "%d/%d" % [_scroll_offset + 1, _crate_contents.size()]
		draw_string(font, Vector2(panel_x, CONTENT_TOP + panel_h + 6), scroll_text,
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 13, UITheme.TEXT_DIM)

	# Corner accents
	var accent := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3)
	var corner_len := 20.0
	# Top-left
	draw_line(Vector2(panel_x, CONTENT_TOP - 4), Vector2(panel_x + corner_len, CONTENT_TOP - 4), accent, 1.0)
	draw_line(Vector2(panel_x, CONTENT_TOP - 4), Vector2(panel_x, CONTENT_TOP - 4 + corner_len), accent, 1.0)
	# Top-right
	draw_line(Vector2(panel_x + PANEL_W, CONTENT_TOP - 4), Vector2(panel_x + PANEL_W - corner_len, CONTENT_TOP - 4), accent, 1.0)
	draw_line(Vector2(panel_x + PANEL_W, CONTENT_TOP - 4), Vector2(panel_x + PANEL_W, CONTENT_TOP - 4 + corner_len), accent, 1.0)


# =============================================================================
# ACTIONS
# =============================================================================
func _on_take_all() -> void:
	for i in _selected.size():
		_selected[i] = true
	_collect_selected()


func _on_take_selected() -> void:
	_collect_selected()


func _on_leave() -> void:
	loot_collected.emit([])
	close()


func _collect_selected() -> void:
	var collected: Array[Dictionary] = []
	for i in _crate_contents.size():
		if _selected[i]:
			collected.append(_crate_contents[i])
	loot_collected.emit(collected)
	close()
