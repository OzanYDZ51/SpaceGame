class_name PauseScreen
extends UIScreen

# =============================================================================
# Pause Screen - OVERLAY with REPRENDRE / OPTIONS / QUITTER buttons
# =============================================================================

signal options_requested
signal quit_requested

var _btn_resume: UIButton
var _btn_options: UIButton
var _btn_quit: UIButton

const PANEL_W: float = 320.0
const PANEL_H: float = 300.0
const BTN_W: float = 240.0
const BTN_H: float = 40.0
const BTN_GAP: float = 12.0


func _init() -> void:
	screen_title = "PAUSE"
	screen_mode = ScreenMode.OVERLAY


func _ready() -> void:
	super._ready()

	_btn_resume = UIButton.new()
	_btn_resume.text = "REPRENDRE"
	_btn_resume.custom_minimum_size = Vector2(BTN_W, BTN_H)
	_btn_resume.pressed.connect(close)
	add_child(_btn_resume)

	_btn_options = UIButton.new()
	_btn_options.text = "OPTIONS"
	_btn_options.custom_minimum_size = Vector2(BTN_W, BTN_H)
	_btn_options.pressed.connect(func(): options_requested.emit())
	add_child(_btn_options)

	_btn_quit = UIButton.new()
	_btn_quit.text = "QUITTER"
	_btn_quit.accent_color = UITheme.DANGER
	_btn_quit.custom_minimum_size = Vector2(BTN_W, BTN_H)
	_btn_quit.pressed.connect(func(): quit_requested.emit())
	add_child(_btn_quit)


func _draw() -> void:
	var s := size

	# Modal background (full screen)
	draw_rect(Rect2(Vector2.ZERO, s), UITheme.BG_MODAL)

	# Centered panel
	var px: float = (s.x - PANEL_W) * 0.5
	var py: float = (s.y - PANEL_H) * 0.5
	var panel_rect := Rect2(px, py, PANEL_W, PANEL_H)
	draw_panel_bg(panel_rect)

	# Title
	var font: Font = UITheme.get_font_bold()
	var fsize: int = UITheme.FONT_SIZE_TITLE
	var title_y: float = py + UITheme.MARGIN_PANEL + fsize
	draw_string(font, Vector2(px, title_y), "PAUSE", HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, fsize, UITheme.TEXT_HEADER)

	# Decorative lines beside title
	var title_w: float = font.get_string_size("PAUSE", HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	var cx: float = px + PANEL_W * 0.5
	var line_y: float = title_y - fsize * 0.35
	var half: float = title_w * 0.5 + 16
	draw_line(Vector2(cx - half - 60, line_y), Vector2(cx - half, line_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(cx + half, line_y), Vector2(cx + half + 60, line_y), UITheme.BORDER, 1.0)

	# Separator
	var sep_y: float = title_y + 10
	draw_line(Vector2(px + 16, sep_y), Vector2(px + PANEL_W - 16, sep_y), UITheme.BORDER, 1.0)

	# Position buttons
	var btn_x: float = px + (PANEL_W - BTN_W) * 0.5
	var btn_start_y: float = sep_y + 28

	_btn_resume.position = Vector2(btn_x, btn_start_y)
	_btn_resume.size = Vector2(BTN_W, BTN_H)
	_btn_options.position = Vector2(btn_x, btn_start_y + BTN_H + BTN_GAP)
	_btn_options.size = Vector2(BTN_W, BTN_H)
	_btn_quit.position = Vector2(btn_x, btn_start_y + (BTN_H + BTN_GAP) * 2)
	_btn_quit.size = Vector2(BTN_W, BTN_H)

	# Close hint
	var hint_font: Font = UITheme.get_font()
	var hint_y: float = py + PANEL_H - 14
	draw_string(hint_font, Vector2(px, hint_y), "ECHAP POUR FERMER", HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
