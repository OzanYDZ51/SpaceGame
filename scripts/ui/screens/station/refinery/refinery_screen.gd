class_name RefineryScreen
extends UIScreen

# =============================================================================
# Refinery Screen — Hub with sidebar (2 tabs) + content area.
# Tabs: RECETTES (recipe browser), FILE (queue)
# =============================================================================

signal refinery_closed

var _player_data: PlayerData = null
var _station_key: String = ""
var _station_name: String = "STATION"

var _sidebar_buttons: Array[UIButton] = []
var _back_btn: UIButton = null
var _active_view: Control = null
var _recipe_view: RecipeBrowserView = null
var _queue_view: QueueView = null
var _current_tab: int = -1

const SIDEBAR_W := 160.0
const CONTENT_TOP := 65.0
const BOTTOM_H := 50.0
const TABS: Array[Array] = [
	["RECETTES", "Parcourir et lancer des recettes"],
	["FILE", "Jobs en cours et completes"],
]


func _ready() -> void:
	screen_title = "RAFFINERIE"
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	for i in TABS.size():
		var btn := UIButton.new()
		btn.text = TABS[i][0]
		btn.visible = false
		btn.pressed.connect(_on_tab_pressed.bind(i))
		add_child(btn)
		_sidebar_buttons.append(btn)

	_back_btn = UIButton.new()
	_back_btn.text = "RETOUR"
	_back_btn.accent_color = UITheme.WARNING
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)

	_recipe_view = RecipeBrowserView.new()
	_recipe_view.visible = false
	add_child(_recipe_view)

	_queue_view = QueueView.new()
	_queue_view.visible = false
	add_child(_queue_view)


func setup(pdata: PlayerData, station_key: String, sname: String) -> void:
	_player_data = pdata
	_station_key = station_key
	_station_name = sname
	screen_title = "RAFFINERIE — " + sname.to_upper()
	var mgr: RefineryManager = pdata.refinery_manager if pdata else null
	if _recipe_view:
		_recipe_view.setup(mgr, station_key, pdata)
	if _queue_view:
		_queue_view.setup(mgr, station_key)


func _on_opened() -> void:
	_layout_controls()
	for btn in _sidebar_buttons:
		btn.visible = true
	_back_btn.visible = true
	_switch_to_tab(0)


func _on_closed() -> void:
	for btn in _sidebar_buttons:
		btn.visible = false
	_back_btn.visible = false
	_hide_all_views()
	_current_tab = -1
	refinery_closed.emit()


func _on_tab_pressed(idx: int) -> void:
	_switch_to_tab(idx)


func _on_back_pressed() -> void:
	close()


func _switch_to_tab(idx: int) -> void:
	_current_tab = idx
	_hide_all_views()
	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].accent_color = UITheme.PRIMARY if i == idx else UITheme.TEXT_DIM

	match idx:
		0:
			_recipe_view.visible = true
			_active_view = _recipe_view
			_recipe_view.refresh()
		1:
			_queue_view.visible = true
			_active_view = _queue_view
			_queue_view.refresh()
	queue_redraw()


func _hide_all_views() -> void:
	if _recipe_view:
		_recipe_view.visible = false
	if _queue_view:
		_queue_view.visible = false
	_active_view = null


func _layout_controls() -> void:
	var s: Vector2 = size
	var btn_w: float = SIDEBAR_W - 16.0
	var btn_h: float = 28.0
	var btn_x: float = 8.0
	var btn_y: float = CONTENT_TOP + 8.0

	for i in _sidebar_buttons.size():
		_sidebar_buttons[i].position = Vector2(btn_x, btn_y + i * (btn_h + 4.0))
		_sidebar_buttons[i].size = Vector2(btn_w, btn_h)

	_back_btn.position = Vector2(btn_x, s.y - BOTTOM_H - btn_h)
	_back_btn.size = Vector2(btn_w, btn_h)

	var content_rect := Rect2(SIDEBAR_W, CONTENT_TOP, s.x - SIDEBAR_W - 8.0, s.y - CONTENT_TOP - BOTTOM_H)
	if _recipe_view:
		_recipe_view.position = content_rect.position
		_recipe_view.size = content_rect.size
	if _queue_view:
		_queue_view.position = content_rect.position
		_queue_view.size = content_rect.size


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

	# Sidebar separator
	draw_line(Vector2(SIDEBAR_W, CONTENT_TOP), Vector2(SIDEBAR_W, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Bottom bar
	draw_line(Vector2(0, s.y - BOTTOM_H), Vector2(s.x, s.y - BOTTOM_H), UITheme.BORDER, 1.0)

	# Credits display
	if _player_data and _player_data.economy:
		var cr_text: String = "Credits: %s CR" % PlayerEconomy.format_credits(_player_data.economy.credits)
		draw_string(font, Vector2(SIDEBAR_W + 12, s.y - BOTTOM_H + 22), cr_text,
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
