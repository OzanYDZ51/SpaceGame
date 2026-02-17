class_name StationAdminScreen
extends UIScreen

# =============================================================================
# Station Administration Screen - Rename station (OVERLAY)
# Pattern: ConstructionScreen (OVERLAY, custom _draw(), UIButton + UITextInput)
# =============================================================================

signal station_renamed(new_name: String)

var _station_node = null
var _station_entity_id: String = ""
var _name_input: UITextInput = null
var _rename_btn: UIButton = null
var _close_btn: UIButton = null
var _current_name: String = ""
var _pulse_time: float = 0.0

const PANEL_W =480.0
const INPUT_W =260.0
const INPUT_H =32.0
const BTN_W =120.0
const BTN_H =32.0
const MAX_NAME_LENGTH =40
const NAME_PREFIX ="Station "


func _ready() -> void:
	screen_title = Locale.t("admin.screen_title")
	screen_mode = ScreenMode.OVERLAY
	super._ready()

	_name_input = UITextInput.new()
	_name_input.placeholder = Locale.t("admin.new_name_placeholder")
	_name_input.visible = false
	_name_input.text_submitted.connect(func(_t): _on_rename())
	add_child(_name_input)

	_rename_btn = UIButton.new()
	_rename_btn.text = Locale.t("admin.validate")
	_rename_btn.visible = false
	_rename_btn.pressed.connect(_on_rename)
	add_child(_rename_btn)

	_close_btn = UIButton.new()
	_close_btn.text = Locale.t("admin.close")
	_close_btn.accent_color = UITheme.WARNING
	_close_btn.visible = false
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


func setup(station_node, entity_id: String) -> void:
	_station_node = station_node
	_station_entity_id = entity_id
	_current_name = station_node.station_name if station_node else "Station"

	# Pre-fill input with the suffix (part after "Station ")
	var suffix: String = _current_name
	if suffix.begins_with(NAME_PREFIX):
		suffix = suffix.substr(NAME_PREFIX.length())
	_name_input.set_text(suffix)


func _on_rename() -> void:
	var suffix: String = _name_input.get_text().strip_edges()
	if suffix.is_empty():
		return

	var new_name: String = NAME_PREFIX + suffix
	if new_name.length() > MAX_NAME_LENGTH:
		new_name = new_name.left(MAX_NAME_LENGTH)

	# 1. Update SpaceStation node
	if _station_node and is_instance_valid(_station_node):
		_station_node.station_name = new_name

	# 2. Update EntityRegistry (dict by reference — propagates to HUD, map, etc.)
	if _station_entity_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(_station_entity_id)
		if not ent.is_empty():
			ent["name"] = new_name

	_current_name = new_name
	station_renamed.emit(new_name)

	# Toast feedback
	if GameManager._notif:
		GameManager._notif.toast(Locale.t("admin.renamed_toast") + new_name)

	queue_redraw()


func _on_opened() -> void:
	_name_input.visible = true
	_rename_btn.visible = true
	_close_btn.visible = true
	_layout_controls()


func _on_closed() -> void:
	_name_input.visible = false
	_rename_btn.visible = false
	_close_btn.visible = false


func _process(delta: float) -> void:
	if _is_open:
		_pulse_time += delta
		queue_redraw()


func _layout_controls() -> void:
	var s =size
	var cx =s.x * 0.5
	var panel_x =cx - PANEL_W * 0.5

	# Input + Rename button row
	var row_y =164.0
	var prefix_w =70.0  # width reserved for "Station " label
	_name_input.position = Vector2(panel_x + prefix_w + 8, row_y)
	_name_input.size = Vector2(INPUT_W, INPUT_H)

	_rename_btn.position = Vector2(panel_x + prefix_w + INPUT_W + 16, row_y)
	_rename_btn.size = Vector2(BTN_W, BTN_H)

	# Close button (bottom center)
	_close_btn.position = Vector2(cx - BTN_W * 0.5, s.y - 80)
	_close_btn.size = Vector2(BTN_W, BTN_H)


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
	var title_text =Locale.t("admin.title_prefix") % _current_name.to_upper()
	draw_string(font_bold, Vector2(0, 38), title_text,
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

	# Panel area
	var panel_x =cx - PANEL_W * 0.5

	# =========================================================================
	# SECTION: RENOMMER LA STATION
	# =========================================================================
	var section_y =90.0
	draw_rect(Rect2(panel_x, section_y, 2, 12), UITheme.PRIMARY)
	draw_string(font, Vector2(panel_x + 8, section_y + 10), Locale.t("admin.rename_header"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)
	var header_w =font.get_string_size(Locale.t("admin.rename_header"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL).x
	draw_line(
		Vector2(panel_x + 12 + header_w, section_y + 5),
		Vector2(panel_x + PANEL_W, section_y + 5),
		UITheme.BORDER, 1.0
	)

	# Subsection background
	var sub_rect =Rect2(panel_x, 114, PANEL_W, 140)
	draw_rect(sub_rect, Color(0.0, 0.02, 0.06, 0.4))
	draw_rect(sub_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12), false, 1.0)

	# Current name label (context shown first, near top of subsection)
	draw_string(font, Vector2(panel_x + 12, 136), Locale.t("admin.current_name"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	draw_string(font, Vector2(panel_x + 90, 136), _current_name,
		HORIZONTAL_ALIGNMENT_LEFT, int(PANEL_W - 100), UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)

	# "Nouveau nom:" small label (dimmed, above input)
	draw_string(font, Vector2(panel_x + 12, 160), Locale.t("admin.new_name"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# "Station " prefix label (left of input)
	var prefix_x =panel_x + 12
	draw_string(font_bold, Vector2(prefix_x, 178), Locale.t("admin.station_prefix"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# =========================================================================
	# CORNER DECORATIONS
	# =========================================================================
	var accent =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3)
	var corner_len =20.0
	# Top-left
	draw_line(Vector2(panel_x, 114), Vector2(panel_x + corner_len, 114), accent, 1.0)
	draw_line(Vector2(panel_x, 114), Vector2(panel_x, 114 + corner_len), accent, 1.0)
	# Top-right
	draw_line(Vector2(panel_x + PANEL_W, 114), Vector2(panel_x + PANEL_W - corner_len, 114), accent, 1.0)
	draw_line(Vector2(panel_x + PANEL_W, 114), Vector2(panel_x + PANEL_W, 114 + corner_len), accent, 1.0)

	# =========================================================================
	# CLOSE SECTION SEPARATOR
	# =========================================================================
	var undock_y =s.y - 110.0
	draw_line(Vector2(cx - 100, undock_y), Vector2(cx + 100, undock_y), UITheme.BORDER, 1.0)

	# =========================================================================
	# SCANLINE
	# =========================================================================
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col =Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)
