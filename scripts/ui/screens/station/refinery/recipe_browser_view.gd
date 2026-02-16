class_name RecipeBrowserView
extends UIComponent

# =============================================================================
# Recipe Browser View — tier tabs + card grid + detail panel + LANCER button.
# Refactored from UIScrollList to a drawn card grid (3 columns).
# =============================================================================

var _manager = null
var _station_key: String = ""
var _player_data = null

var _tab_bar: UITabBar = null
var _launch_btn: UIButton = null
var _qty_up_btn: UIButton = null
var _qty_down_btn: UIButton = null
var _selected_recipe: RefineryRecipe = null
var _current_tier: int = 1
var _quantity: int = 1

# Card grid state
var _recipes: Array = []
var _card_rects: Array[Rect2] = []
var _hovered_idx: int = -1
var _selected_index: int = -1
var _scroll_offset: float = 0.0
var _total_content_h: float = 0.0
var _grid_area: Rect2 = Rect2()

const DETAIL_W: float = 260.0
const GRID_TOP: float = 34.0
const CARD_W: float = 140.0
const CARD_H: float = 100.0
const CARD_GAP: float = 8.0


func _ready() -> void:
	super._ready()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = ["TIER 1", "TIER 2", "TIER 3"]
	_tab_bar.tab_changed.connect(_on_tier_changed)
	add_child(_tab_bar)

	_qty_down_btn = UIButton.new()
	_qty_down_btn.text = "-"
	_qty_down_btn.pressed.connect(func(): _set_quantity(_quantity - 1))
	_qty_down_btn.visible = false
	add_child(_qty_down_btn)

	_qty_up_btn = UIButton.new()
	_qty_up_btn.text = "+"
	_qty_up_btn.pressed.connect(func(): _set_quantity(_quantity + 1))
	_qty_up_btn.visible = false
	add_child(_qty_up_btn)

	_launch_btn = UIButton.new()
	_launch_btn.text = "LANCER"
	_launch_btn.accent_color = UITheme.ACCENT
	_launch_btn.pressed.connect(_on_launch)
	_launch_btn.visible = false
	add_child(_launch_btn)


func setup(mgr, station_key: String, pdata) -> void:
	_manager = mgr
	_station_key = station_key
	_player_data = pdata


func refresh() -> void:
	_populate_list()
	_selected_recipe = null
	_selected_index = -1
	_quantity = 1
	_scroll_offset = 0.0
	_update_detail_visibility()
	_layout()
	queue_redraw()


func _on_tier_changed(idx: int) -> void:
	_current_tier = idx + 1
	_selected_recipe = null
	_selected_index = -1
	_quantity = 1
	_scroll_offset = 0.0
	_populate_list()
	_update_detail_visibility()
	queue_redraw()


func _set_quantity(q: int) -> void:
	_quantity = clampi(q, 1, 99)
	queue_redraw()


func _on_launch() -> void:
	if _selected_recipe == null or _manager == null:
		return
	var job = _manager.submit_job(_station_key, _selected_recipe.recipe_id, _quantity)
	if job:
		if GameManager._notif:
			GameManager._notif.general.service_unlocked("Raffinage: %s x%d" % [_selected_recipe.display_name, _quantity])
		_quantity = 1
		queue_redraw()
	else:
		if GameManager._notif:
			GameManager._notif.general.insufficient_credits("Ressources insuffisantes")


func _populate_list() -> void:
	_recipes = RefineryRegistry.get_by_tier(_current_tier)
	_compute_card_grid()
	queue_redraw()


func _update_detail_visibility() -> void:
	var vis: bool = _selected_recipe != null
	_launch_btn.visible = vis
	_qty_up_btn.visible = vis
	_qty_down_btn.visible = vis


# =========================================================================
# LAYOUT
# =========================================================================

func _layout() -> void:
	var s: Vector2 = size
	var list_w: float = s.x - DETAIL_W - 8.0

	_tab_bar.position = Vector2.ZERO
	_tab_bar.size = Vector2(list_w, 30)

	_grid_area = Rect2(0, GRID_TOP, list_w, s.y - GRID_TOP)
	_compute_card_grid()

	# Detail panel buttons
	var dx: float = s.x - DETAIL_W + 12
	var btn_y: float = s.y - 44

	_qty_down_btn.position = Vector2(dx, btn_y)
	_qty_down_btn.size = Vector2(36, 28)
	_qty_up_btn.position = Vector2(dx + 40, btn_y)
	_qty_up_btn.size = Vector2(36, 28)
	_launch_btn.position = Vector2(dx + 84, btn_y)
	_launch_btn.size = Vector2(DETAIL_W - 100, 28)


func _compute_card_grid() -> void:
	_card_rects.clear()
	if _recipes.is_empty():
		_total_content_h = 0.0
		return
	var area_w: float = _grid_area.size.x
	var cols: int = maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	for i in _recipes.size():
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = _grid_area.position.x + col * (CARD_W + CARD_GAP)
		var y: float = _grid_area.position.y + row * (CARD_H + CARD_GAP) - _scroll_offset
		_card_rects.append(Rect2(x, y, CARD_W, CARD_H))
	@warning_ignore("integer_division")
	var total_rows: int = (_recipes.size() + maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP))) - 1) / maxi(1, int((area_w + CARD_GAP) / (CARD_W + CARD_GAP)))
	_total_content_h = total_rows * (CARD_H + CARD_GAP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


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
					if i < _recipes.size():
						_selected_recipe = _recipes[i] as RefineryRecipe
					else:
						_selected_recipe = null
					_quantity = 1
					_update_detail_visibility()
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
# DRAW
# =========================================================================

func _draw() -> void:
	var s: Vector2 = size
	var font: Font = UITheme.get_font()

	# Draw card grid
	_draw_card_grid(font)

	# Detail panel background
	var dx: float = s.x - DETAIL_W
	draw_rect(Rect2(dx, 0, DETAIL_W, s.y), UITheme.BG_PANEL)
	draw_line(Vector2(dx, 0), Vector2(dx, s.y), UITheme.BORDER, 1.0)

	if _selected_recipe == null:
		draw_string(font, Vector2(dx + 12, 60), "Selectionnez une recette",
			HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	# --- Detail panel content ---
	var r: RefineryRecipe = _selected_recipe

	# Recipe name in icon_color
	draw_string(font, Vector2(dx + 12, 24), r.display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_HEADER, r.icon_color)

	# Tier
	var tier_text: String = "Tier %d" % r.tier
	draw_string(font, Vector2(dx + 12, 42), tier_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Inputs
	var iy: float = 62.0
	draw_string(font, Vector2(dx + 12, iy), "INPUTS:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_KEY)
	iy += 18

	var storage: StationStorage = null
	if _manager:
		storage = _manager.get_storage(_station_key)

	for input in r.inputs:
		var input_id: StringName = input.id
		var input_qty: int = input.qty * _quantity
		var iname: String = RefineryRegistry.get_display_name(input_id)
		var have: int = storage.get_amount(input_id) if storage else 0
		var col: Color = UITheme.ACCENT if have >= input_qty else UITheme.DANGER
		var txt: String = "  %s: %d / %d" % [iname, have, input_qty]
		draw_string(font, Vector2(dx + 12, iy), txt,
			HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_SMALL, col)
		iy += 18

	# Output
	iy += 6
	draw_string(font, Vector2(dx + 12, iy), "OUTPUT:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.LABEL_KEY)
	iy += 18
	var out_name: String = RefineryRegistry.get_display_name(r.output_id)
	var out_text: String = "  %s x%d" % [out_name, r.output_qty * _quantity]
	draw_string(font, Vector2(dx + 12, iy), out_text,
		HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_SMALL, r.icon_color)
	iy += 22

	# Duration
	var total_time: float = r.duration * _quantity
	var time_text: String = "Duree: %s" % _format_time(total_time)
	draw_string(font, Vector2(dx + 12, iy), time_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)
	iy += 18

	# Value
	var val_text: String = "Valeur: %s CR" % PlayerEconomy.format_credits(r.value * _quantity)
	draw_string(font, Vector2(dx + 12, iy), val_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
	iy += 22

	# Quantity display
	var qty_y: float = s.y - 70
	draw_string(font, Vector2(dx + 12, qty_y), "Quantite: %d" % _quantity,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


func _draw_card_grid(font: Font) -> void:
	for i in _card_rects.size():
		var rect: Rect2 = _card_rects[i]
		# Clip: skip cards outside the visible grid area
		if rect.end.y < _grid_area.position.y or rect.position.y > _grid_area.end.y:
			continue
		_draw_recipe_card(font, rect, i)


func _draw_recipe_card(font: Font, rect: Rect2, idx: int) -> void:
	if idx >= _recipes.size():
		return
	var r: RefineryRecipe = _recipes[idx] as RefineryRecipe
	if r == null:
		return

	var is_sel: bool = idx == _selected_index
	var is_hov: bool = idx == _hovered_idx

	# Card background
	var bg: Color
	if is_sel:
		bg = Color(r.icon_color.r, r.icon_color.g, r.icon_color.b, 0.15)
	elif is_hov:
		bg = Color(0.025, 0.06, 0.12, 0.9)
	else:
		bg = Color(0.015, 0.04, 0.08, 0.8)
	draw_rect(rect, bg)

	# Border
	var bcol: Color
	if is_sel:
		bcol = r.icon_color
	elif is_hov:
		bcol = UITheme.BORDER_HOVER
	else:
		bcol = UITheme.BORDER
	draw_rect(rect, bcol, false, 1.0)

	# Top glow if selected
	if is_sel:
		draw_line(Vector2(rect.position.x + 1, rect.position.y),
			Vector2(rect.end.x - 1, rect.position.y),
			Color(r.icon_color.r, r.icon_color.g, r.icon_color.b, 0.3), 2.0)

	# Mini corners
	draw_corners(rect, 6.0, bcol)

	# Colored circle (recipe icon_color) — centered, upper area
	var circle_center: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 22.0)
	var circle_radius: float = 10.0
	var circle_col: Color = r.icon_color if is_sel else Color(r.icon_color.r, r.icon_color.g, r.icon_color.b, 0.7)
	draw_arc(circle_center, circle_radius, 0, TAU, 24, circle_col, 2.0)
	draw_arc(circle_center, circle_radius * 0.4, 0, TAU, 12,
		Color(circle_col.r, circle_col.g, circle_col.b, 0.5), 3.0)

	# Recipe name (centered)
	var name_col: Color = UITheme.TEXT if is_sel else UITheme.TEXT_DIM
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 46),
		r.display_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_SMALL, name_col)

	# Brief "inputs -> output" summary
	var parts: PackedStringArray = PackedStringArray()
	for input in r.inputs:
		parts.append("%s x%d" % [RefineryRegistry.get_display_name(input.id), input.qty])
	var out_name: String = RefineryRegistry.get_display_name(r.output_id)
	var summary: String = " + ".join(parts)
	# Truncate if too long
	if summary.length() > 20:
		summary = summary.substr(0, 18) + ".."
	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 62),
		summary, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	draw_string(font, Vector2(rect.position.x + 4, rect.position.y + 76),
		"-> " + out_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_TINY, Color(r.icon_color.r, r.icon_color.g, r.icon_color.b, 0.7))

	# Duration at bottom
	var time_str: String = _format_time(r.duration)
	draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 6),
		time_str, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8,
		UITheme.FONT_SIZE_TINY, UITheme.LABEL_VALUE)


static func _format_time(seconds: float) -> String:
	@warning_ignore("integer_division")
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	if mins > 0:
		return "%dm%02ds" % [mins, secs]
	return "%ds" % secs
