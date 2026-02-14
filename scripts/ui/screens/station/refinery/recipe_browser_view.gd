class_name RecipeBrowserView
extends Control

# =============================================================================
# Recipe Browser View — tier tabs + recipe list + detail panel + LANCER button.
# =============================================================================

var _manager: RefineryManager = null
var _station_key: String = ""
var _player_data: PlayerData = null

var _tab_bar: UITabBar = null
var _recipe_list: UIScrollList = null
var _launch_btn: UIButton = null
var _qty_up_btn: UIButton = null
var _qty_down_btn: UIButton = null
var _selected_recipe: RefineryRecipe = null
var _current_tier: int = 1
var _quantity: int = 1

const DETAIL_W := 260.0
const LIST_TOP := 32.0


func _ready() -> void:
	clip_contents = true

	_tab_bar = UITabBar.new()
	_tab_bar.tabs = ["TIER 1", "TIER 2", "TIER 3"]
	_tab_bar.tab_changed.connect(_on_tier_changed)
	add_child(_tab_bar)

	_recipe_list = UIScrollList.new()
	_recipe_list.item_draw_callback = _draw_recipe_row
	_recipe_list.item_selected.connect(_on_recipe_selected)
	add_child(_recipe_list)

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


func setup(mgr: RefineryManager, station_key: String, pdata: PlayerData) -> void:
	_manager = mgr
	_station_key = station_key
	_player_data = pdata


func refresh() -> void:
	_populate_list()
	_selected_recipe = null
	_recipe_list.selected_index = -1
	_quantity = 1
	_update_detail_visibility()
	_layout()
	queue_redraw()


func _on_tier_changed(idx: int) -> void:
	_current_tier = idx + 1
	_selected_recipe = null
	_recipe_list.selected_index = -1
	_quantity = 1
	_populate_list()
	_update_detail_visibility()
	queue_redraw()


func _on_recipe_selected(idx: int) -> void:
	if idx >= 0 and idx < _recipe_list.items.size():
		_selected_recipe = _recipe_list.items[idx] as RefineryRecipe
	else:
		_selected_recipe = null
	_quantity = 1
	_update_detail_visibility()
	queue_redraw()


func _set_quantity(q: int) -> void:
	_quantity = clampi(q, 1, 99)
	queue_redraw()


func _on_launch() -> void:
	if _selected_recipe == null or _manager == null:
		return
	var job := _manager.submit_job(_station_key, _selected_recipe.recipe_id, _quantity)
	if job:
		if GameManager._notif:
			GameManager._notif.general.service_unlocked("Raffinage: %s x%d" % [_selected_recipe.display_name, _quantity])
		_quantity = 1
		queue_redraw()
	else:
		if GameManager._notif:
			GameManager._notif.general.insufficient_credits("Ressources insuffisantes")


func _populate_list() -> void:
	var recipes := RefineryRegistry.get_by_tier(_current_tier)
	_recipe_list.items = recipes
	_recipe_list.selected_index = -1
	_recipe_list.queue_redraw()


func _update_detail_visibility() -> void:
	var vis: bool = _selected_recipe != null
	_launch_btn.visible = vis
	_qty_up_btn.visible = vis
	_qty_down_btn.visible = vis


func _layout() -> void:
	var s: Vector2 = size
	_tab_bar.position = Vector2.ZERO
	_tab_bar.size = Vector2(s.x - DETAIL_W, 30)

	_recipe_list.position = Vector2(0, LIST_TOP)
	_recipe_list.size = Vector2(s.x - DETAIL_W - 8, s.y - LIST_TOP)

	# Detail panel buttons
	var dx: float = s.x - DETAIL_W + 12
	var btn_y: float = s.y - 44

	_qty_down_btn.position = Vector2(dx, btn_y)
	_qty_down_btn.size = Vector2(36, 28)
	_qty_up_btn.position = Vector2(dx + 40, btn_y)
	_qty_up_btn.size = Vector2(36, 28)
	_launch_btn.position = Vector2(dx + 84, btn_y)
	_launch_btn.size = Vector2(DETAIL_W - 100, 28)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var font: Font = UITheme.get_font()

	# Detail panel background
	var dx: float = s.x - DETAIL_W
	draw_rect(Rect2(dx, 0, DETAIL_W, s.y), UITheme.BG_PANEL)
	draw_line(Vector2(dx, 0), Vector2(dx, s.y), UITheme.BORDER, 1.0)

	if _selected_recipe == null:
		draw_string(font, Vector2(dx + 12, 60), "Selectionnez une recette",
			HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		return

	# Recipe name
	var r: RefineryRecipe = _selected_recipe
	draw_string(font, Vector2(dx + 12, 24), r.display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, int(DETAIL_W - 24), UITheme.FONT_SIZE_HEADER, r.icon_color)

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


func _draw_recipe_row(ctrl: Control, _idx: int, rect: Rect2, item: Variant) -> void:
	var r := item as RefineryRecipe
	if r == null:
		return
	var font: Font = UITheme.get_font()
	var y: float = rect.position.y + rect.size.y - 5
	var x: float = rect.position.x

	# Color pip
	ctrl.draw_rect(Rect2(x + 4, rect.position.y + 5, 10, 12), r.icon_color)

	# Name
	ctrl.draw_string(font, Vector2(x + 20, y), r.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x * 0.55), UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# Brief inputs summary
	var parts: PackedStringArray = PackedStringArray()
	for input in r.inputs:
		parts.append("%s x%d" % [str(input.id), input.qty])
	var inputs_text: String = " | ".join(parts)
	ctrl.draw_string(font, Vector2(x + rect.size.x * 0.55, y), inputs_text,
		HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x * 0.3), UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Duration
	var time_str: String = _format_time(r.duration)
	ctrl.draw_string(font, Vector2(x + rect.size.x - 55, y), time_str,
		HORIZONTAL_ALIGNMENT_RIGHT, 50, UITheme.FONT_SIZE_TINY, UITheme.LABEL_VALUE)


static func _format_time(seconds: float) -> String:
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	if mins > 0:
		return "%dm%02ds" % [mins, secs]
	return "%ds" % secs
