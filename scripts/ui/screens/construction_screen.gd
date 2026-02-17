class_name ConstructionScreen
extends UIScreen

# =============================================================================
# Construction Screen - Overlay to deposit resources and build a station
# Pattern: LootScreen (OVERLAY, custom _draw(), UIButton children)
# =============================================================================

signal construction_completed(marker_id: int)

const STATION_RECIPE ={
	&"iron": 50,
	&"copper": 30,
	&"titanium": 20,
	&"crystal": 10,
}

var _marker: Dictionary = {}
var _player_economy = null
var _deposit_btns: Dictionary = {}  # StringName → UIButton
var _construct_btn: UIButton = null
var _close_btn: UIButton = null
var _pulse_time: float = 0.0

const PANEL_W =520.0
const ROW_H =48.0
const CONTENT_TOP =90.0
const BTN_W =160.0
const BTN_H =40.0
const DEPOSIT_BTN_W =100.0
const DEPOSIT_BTN_H =32.0


func _ready() -> void:
	screen_title = Locale.t("build.screen_title")
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	# Create deposit buttons for each recipe resource
	for res_id in STATION_RECIPE:
		var btn =UIButton.new()
		btn.text = Locale.t("build.deposit")
		btn.visible = false
		btn.pressed.connect(_on_deposit.bind(res_id))
		add_child(btn)
		_deposit_btns[res_id] = btn

	# Construct button
	_construct_btn = UIButton.new()
	_construct_btn.text = Locale.t("build.construct")
	_construct_btn.visible = false
	_construct_btn.enabled = false
	_construct_btn.pressed.connect(_on_construct)
	add_child(_construct_btn)

	# Close button
	_close_btn = UIButton.new()
	_close_btn.text = Locale.t("build.close")
	_close_btn.accent_color = UITheme.WARNING
	_close_btn.visible = false
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


func setup(marker: Dictionary, economy) -> void:
	_marker = marker
	_player_economy = economy


func _on_opened() -> void:
	for btn in _deposit_btns.values():
		btn.visible = true
	_construct_btn.visible = true
	_close_btn.visible = true
	_layout_controls()
	_update_button_states()


func _on_closed() -> void:
	for btn in _deposit_btns.values():
		btn.visible = false
	_construct_btn.visible = false
	_close_btn.visible = false


func _process(delta: float) -> void:
	if _is_open:
		_pulse_time += delta
		_update_button_states()
		queue_redraw()


func _layout_controls() -> void:
	var s =size
	var cx =s.x * 0.5
	var panel_x =cx - PANEL_W * 0.5

	# Position deposit buttons on each resource row
	var recipe_keys =STATION_RECIPE.keys()
	for i in recipe_keys.size():
		var res_id: StringName = recipe_keys[i]
		var ry =CONTENT_TOP + i * ROW_H
		var btn: UIButton = _deposit_btns[res_id]
		btn.position = Vector2(panel_x + PANEL_W - DEPOSIT_BTN_W - 12, ry + 8)
		btn.size = Vector2(DEPOSIT_BTN_W, DEPOSIT_BTN_H)

	# Bottom buttons
	var btn_y =CONTENT_TOP + recipe_keys.size() * ROW_H + 80.0
	var total_w =BTN_W * 2 + 20
	var bx =cx - total_w * 0.5
	_construct_btn.position = Vector2(bx, btn_y)
	_construct_btn.size = Vector2(BTN_W, BTN_H)
	_close_btn.position = Vector2(bx + BTN_W + 20, btn_y)
	_close_btn.size = Vector2(BTN_W, BTN_H)


func _update_button_states() -> void:
	if _marker.is_empty() or _player_economy == null:
		return

	var deposited: Dictionary = _marker.get("deposited_resources", {})
	var all_complete =true

	for res_id in STATION_RECIPE:
		var required: int = STATION_RECIPE[res_id]
		var current: int = deposited.get(res_id, 0)
		var stock: int = _player_economy.get_resource(res_id)
		var needed =required - current

		var btn: UIButton = _deposit_btns.get(res_id)
		if btn:
			btn.enabled = needed > 0 and stock > 0

		if needed > 0:
			all_complete = false

	_construct_btn.enabled = all_complete


func _on_deposit(res_id: StringName) -> void:
	if _marker.is_empty() or _player_economy == null:
		return

	var deposited: Dictionary = _marker.get("deposited_resources", {})
	var required: int = STATION_RECIPE.get(res_id, 0)
	var current: int = deposited.get(res_id, 0)
	var needed =required - current
	var stock: int = _player_economy.get_resource(res_id)
	var transfer =mini(needed, stock)

	if transfer <= 0:
		return

	_player_economy.spend_resource(res_id, transfer)
	deposited[res_id] = current + transfer
	_marker["deposited_resources"] = deposited
	_update_button_states()
	queue_redraw()


func _on_construct() -> void:
	var marker_id: int = _marker.get("id", -1)
	construction_completed.emit(marker_id)
	close()


# =============================================================================
# DRAW
# =============================================================================
func _draw() -> void:
	var s =size
	var cx =s.x * 0.5
	var font =UITheme.get_font_medium()
	var font_bold =UITheme.get_font_bold()

	# Background (OVERLAY)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.7))

	# Vignette top/bottom
	draw_rect(Rect2(0, 0, s.x, 50), Color(0.0, 0.0, 0.02, 0.5))
	draw_rect(Rect2(0, s.y - 34, s.x, 34), Color(0.0, 0.0, 0.02, 0.5))

	if not _is_open:
		return

	# Title
	draw_string(font_bold, Vector2(0, 38), Locale.t("build.title"),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, UITheme.PRIMARY)

	# Close [X] top-right
	var close_x: float = s.x - UITheme.MARGIN_SCREEN - 24
	var close_y: float = UITheme.MARGIN_SCREEN
	draw_string(font_bold, Vector2(close_x, close_y + 14), "X",
		HORIZONTAL_ALIGNMENT_LEFT, 24, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
	draw_rect(Rect2(close_x - 4, close_y, 28, 24), UITheme.BORDER, false, 1.0)

	# Separator
	draw_line(Vector2(UITheme.MARGIN_SCREEN, 48),
		Vector2(s.x - UITheme.MARGIN_SCREEN, 48), UITheme.BORDER, 1.0)

	# Compute totals
	var deposited: Dictionary = _marker.get("deposited_resources", {})
	var complete_count =0
	var total_deposited =0
	var total_required =0
	for res_id in STATION_RECIPE:
		var required: int = STATION_RECIPE[res_id]
		var current: int = deposited.get(res_id, 0)
		total_deposited += current
		total_required += required
		if current >= required:
			complete_count += 1

	# Subtitle
	draw_string(font, Vector2(0, 70), Locale.t("build.resources_complete") % [complete_count, STATION_RECIPE.size()],
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, UITheme.TEXT_DIM)

	# Panel background
	var panel_x =cx - PANEL_W * 0.5
	var recipe_keys =STATION_RECIPE.keys()
	var panel_h: float = recipe_keys.size() * ROW_H + 8.0
	var panel_rect =Rect2(panel_x, CONTENT_TOP - 4, PANEL_W, panel_h)
	draw_rect(panel_rect, Color(0.0, 0.02, 0.06, 0.5))
	draw_rect(panel_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), false, 1.0)

	# Resource rows
	for i in recipe_keys.size():
		var res_id: StringName = recipe_keys[i]
		var required: int = STATION_RECIPE[res_id]
		var current: int = deposited.get(res_id, 0)
		var stock: int = _player_economy.get_resource(res_id) if _player_economy else 0
		var is_complete: bool = current >= required
		var ry =CONTENT_TOP + i * ROW_H

		# Row highlight if complete
		if is_complete:
			draw_rect(Rect2(panel_x + 2, ry, PANEL_W - 4, ROW_H - 2),
				Color(0.1, 0.8, 0.2, 0.06))

		# Color swatch
		var res_def: Dictionary = PlayerEconomy.RESOURCE_DEFS.get(res_id, {})
		var icon_col: Color = res_def.get("color", Color.WHITE)
		draw_rect(Rect2(panel_x + 16, ry + 14, 16, 16), icon_col)

		# Check mark or square icon
		if is_complete:
			draw_string(font_bold, Vector2(panel_x + 36, ry + 30), "OK",
				HORIZONTAL_ALIGNMENT_LEFT, 24, 13, Color(0.2, 1.0, 0.3))

		# Resource name
		var res_name: String = res_def.get("name", str(res_id).to_upper())
		var name_col =Color(0.2, 1.0, 0.3) if is_complete else UITheme.TEXT
		draw_string(font, Vector2(panel_x + 62, ry + 30), res_name,
			HORIZONTAL_ALIGNMENT_LEFT, 120, 15, name_col)

		# Progress "X / Y"
		var progress_text ="%d / %d" % [current, required]
		var progress_col =Color(0.2, 1.0, 0.3) if is_complete else UITheme.PRIMARY
		draw_string(font, Vector2(panel_x + 190, ry + 30), progress_text,
			HORIZONTAL_ALIGNMENT_LEFT, 80, 15, progress_col)

		# Player stock
		var stock_col =UITheme.TEXT_DIM if stock == 0 else UITheme.TEXT
		draw_string(font, Vector2(panel_x + 290, ry + 30), Locale.t("build.stock") % stock,
			HORIZONTAL_ALIGNMENT_LEFT, 90, 13, stock_col)

		# Separator line
		draw_line(Vector2(panel_x + 8, ry + ROW_H - 2),
			Vector2(panel_x + PANEL_W - 8, ry + ROW_H - 2),
			Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08), 1.0)

	# Global progress bar
	var bar_y =CONTENT_TOP + panel_h + 20
	var bar_w =PANEL_W - 40
	var bar_h =18.0
	var bar_x =cx - bar_w * 0.5
	var progress: float = float(total_deposited) / float(total_required) if total_required > 0 else 0.0

	# Bar background
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.1, 0.6))
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h),
		Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), false, 1.0)

	# Bar fill
	if progress > 0:
		var fill_col =UITheme.PRIMARY if progress < 1.0 else Color(0.2, 1.0, 0.3)
		if progress >= 1.0:
			var pulse =0.8 + sin(_pulse_time * 3.0) * 0.2
			fill_col = Color(fill_col.r * pulse, fill_col.g * pulse, fill_col.b * pulse)
		draw_rect(Rect2(bar_x + 1, bar_y + 1, (bar_w - 2) * progress, bar_h - 2), fill_col)

	# Progress percentage
	var pct_text ="%d%%" % int(progress * 100)
	draw_string(font, Vector2(bar_x, bar_y + bar_h + 16), pct_text,
		HORIZONTAL_ALIGNMENT_CENTER, bar_w, 14, UITheme.TEXT_DIM)

	# Corner accents
	var accent =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3)
	var corner_len =20.0
	# Top-left
	draw_line(Vector2(panel_x, CONTENT_TOP - 4),
		Vector2(panel_x + corner_len, CONTENT_TOP - 4), accent, 1.0)
	draw_line(Vector2(panel_x, CONTENT_TOP - 4),
		Vector2(panel_x, CONTENT_TOP - 4 + corner_len), accent, 1.0)
	# Top-right
	draw_line(Vector2(panel_x + PANEL_W, CONTENT_TOP - 4),
		Vector2(panel_x + PANEL_W - corner_len, CONTENT_TOP - 4), accent, 1.0)
	draw_line(Vector2(panel_x + PANEL_W, CONTENT_TOP - 4),
		Vector2(panel_x + PANEL_W, CONTENT_TOP - 4 + corner_len), accent, 1.0)
