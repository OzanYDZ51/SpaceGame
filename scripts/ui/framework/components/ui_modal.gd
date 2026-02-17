class_name UIModal
extends UIComponent

# =============================================================================
# UI Modal - Centered dialog with overlay, title, body, Confirm/Cancel buttons
# =============================================================================

signal confirmed
signal cancelled

var title: String = ""
var body: String = ""
var confirm_text: String = ""
var cancel_text: String = ""

var _hovered_btn: int = -1  # 0 = confirm, 1 = cancel

const MODAL_WIDTH := 400.0
const MODAL_HEIGHT := 180.0
const BTN_WIDTH := 120.0
const BTN_HEIGHT := 30.0


func _ready() -> void:
	super._ready()
	confirm_text = Locale.t("btn.confirm")
	cancel_text = Locale.t("btn.cancel")
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 90


func show_modal(p_title: String = "", p_body: String = "") -> void:
	if p_title != "":
		title = p_title
	if p_body != "":
		body = p_body
	visible = true
	queue_redraw()


func hide_modal() -> void:
	visible = false


func _draw() -> void:
	var vp := size
	var font: Font = UITheme.get_font()

	# Full-screen dark overlay
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))

	# Modal box
	var mx: float = (vp.x - MODAL_WIDTH) * 0.5
	var my: float = (vp.y - MODAL_HEIGHT) * 0.5
	var modal_rect := Rect2(mx, my, MODAL_WIDTH, MODAL_HEIGHT)

	draw_panel_bg(modal_rect, UITheme.BG_MODAL)

	# Title
	var ty: float = my + UITheme.MARGIN_PANEL + UITheme.FONT_SIZE_HEADER
	draw_string(font, Vector2(mx + UITheme.MARGIN_PANEL, ty), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, MODAL_WIDTH - UITheme.MARGIN_PANEL * 2, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)

	# Separator
	var sep_y: float = ty + 8
	draw_line(Vector2(mx + UITheme.MARGIN_PANEL, sep_y), Vector2(mx + MODAL_WIDTH - UITheme.MARGIN_PANEL, sep_y), UITheme.BORDER, 1.0)

	# Body text
	var body_y: float = sep_y + UITheme.FONT_SIZE_BODY + 10
	draw_string(font, Vector2(mx + UITheme.MARGIN_PANEL, body_y), body, HORIZONTAL_ALIGNMENT_LEFT, MODAL_WIDTH - UITheme.MARGIN_PANEL * 2, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# Buttons
	var btn_y: float = my + MODAL_HEIGHT - BTN_HEIGHT - UITheme.MARGIN_PANEL
	var confirm_rect := Rect2(mx + MODAL_WIDTH - UITheme.MARGIN_PANEL - BTN_WIDTH * 2 - 10, btn_y, BTN_WIDTH, BTN_HEIGHT)
	var cancel_rect := Rect2(mx + MODAL_WIDTH - UITheme.MARGIN_PANEL - BTN_WIDTH, btn_y, BTN_WIDTH, BTN_HEIGHT)

	_draw_modal_btn(confirm_rect, confirm_text, UITheme.ACCENT, _hovered_btn == 0, font)
	_draw_modal_btn(cancel_rect, cancel_text, UITheme.DANGER, _hovered_btn == 1, font)


func _draw_modal_btn(rect: Rect2, text: String, accent: Color, hovered: bool, font: Font) -> void:
	var bg := Color(accent.r, accent.g, accent.b, 0.08 if not hovered else 0.15)
	draw_rect(rect, bg)
	draw_rect(rect, accent if hovered else UITheme.BORDER, false, 1.0)
	draw_rect(Rect2(rect.position.x, rect.position.y + 2, 3, rect.size.y - 4), accent)
	var text_y: float = rect.position.y + (rect.size.y + UITheme.FONT_SIZE_BODY) * 0.5 - 1
	draw_string(font, Vector2(rect.position.x + 12, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


func _get_button_rects() -> Array[Rect2]:
	var vp := size
	var mx: float = (vp.x - MODAL_WIDTH) * 0.5
	var my: float = (vp.y - MODAL_HEIGHT) * 0.5
	var btn_y: float = my + MODAL_HEIGHT - BTN_HEIGHT - UITheme.MARGIN_PANEL
	return [
		Rect2(mx + MODAL_WIDTH - UITheme.MARGIN_PANEL - BTN_WIDTH * 2 - 10, btn_y, BTN_WIDTH, BTN_HEIGHT),
		Rect2(mx + MODAL_WIDTH - UITheme.MARGIN_PANEL - BTN_WIDTH, btn_y, BTN_WIDTH, BTN_HEIGHT),
	]


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		var rects := _get_button_rects()
		var prev := _hovered_btn
		_hovered_btn = -1
		for i in rects.size():
			if rects[i].has_point(event.position):
				_hovered_btn = i
				break
		if _hovered_btn != prev:
			queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rects := _get_button_rects()
		if rects[0].has_point(event.position):
			confirmed.emit()
			hide_modal()
		elif rects[1].has_point(event.position):
			cancelled.emit()
			hide_modal()

	# Consume all input
	accept_event()
