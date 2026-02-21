class_name HelpScreen
extends UIScreen

# =============================================================================
# Help Screen - In-game tabbed reference guide for controls, systems, and tips
# All rendering via _draw() — holographic sci-fi style matching UI framework
# =============================================================================

var _active_tab: int = 0
var _scroll_offset: float = 0.0
var _tab_hovered: int = -1
var _max_scroll: float = 0.0

var TAB_LABELS: PackedStringArray = []
const LINE_H: float = 20.0
const SCROLL_STEP: float = 48.0
const TAB_H: float = 30.0
const TAB_PAD: float = 20.0
const KEY_COL_W: float = 140.0

# Tab content data: sections with { "t": title, "l": [lines] }
var _tab_data: Array = []


func _init() -> void:
	screen_title = Locale.t("screen.help")
	screen_mode = ScreenMode.FULLSCREEN
	_rebuild_data()


func _ready() -> void:
	super._ready()


func _on_language_changed(_lang: String) -> void:
	screen_title = Locale.t("screen.help")
	_rebuild_data()
	queue_redraw()


func _on_opened() -> void:
	_active_tab = 0
	_scroll_offset = 0.0
	_tab_hovered = -1
	queue_redraw()


func _on_closed() -> void:
	_scroll_offset = 0.0

func _rebuild_data() -> void:
	TAB_LABELS = PackedStringArray([Locale.t("tab.controls"), Locale.t("tab.combat"), Locale.t("tab.economy"), Locale.t("tab.fleet")])
	_tab_data = [null, _build_combat(), _build_economy(), _build_fleet()]


func _build_combat() -> Array:
	return [
		{"t": Locale.t("help.combat.shields_title"), "l": [
			Locale.t("help.combat.shields_1"),
			Locale.t("help.combat.shields_2"),
			Locale.t("help.combat.shields_3")]},
		{"t": Locale.t("help.combat.energy_title"), "l": [
			Locale.t("help.combat.energy_1"),
			Locale.t("help.combat.energy_2"),
			Locale.t("help.combat.energy_3"),
			Locale.t("help.combat.energy_4")]},
		{"t": Locale.t("help.combat.targeting_title"), "l": [
			Locale.t("help.combat.targeting_1"),
			Locale.t("help.combat.targeting_2"),
			Locale.t("help.combat.targeting_3")]},
		{"t": Locale.t("help.combat.cruise_title"), "l": [
			Locale.t("help.combat.cruise_1"),
			Locale.t("help.combat.cruise_2"),
			Locale.t("help.combat.cruise_3")]},
	]


func _build_economy() -> Array:
	return [
		{"t": Locale.t("help.economy.trade_title"), "l": [
			Locale.t("help.economy.trade_1"),
			Locale.t("help.economy.trade_2"),
			Locale.t("help.economy.trade_3")]},
		{"t": Locale.t("help.economy.mining_title"), "l": [
			Locale.t("help.economy.mining_1"),
			Locale.t("help.economy.mining_2"),
			Locale.t("help.economy.mining_3"),
			Locale.t("help.economy.mining_4")]},
		{"t": Locale.t("help.economy.refinery_title"), "l": [
			Locale.t("help.economy.refinery_1"),
			Locale.t("help.economy.refinery_2"),
			Locale.t("help.economy.refinery_3")]},
		{"t": Locale.t("help.economy.station_title"), "l": [
			Locale.t("help.economy.station_1"),
			Locale.t("help.economy.station_2")]},
	]


func _build_fleet() -> Array:
	return [
		{"t": Locale.t("help.fleet.management_title"), "l": [
			Locale.t("help.fleet.management_1"),
			Locale.t("help.fleet.management_2"),
			Locale.t("help.fleet.management_3")]},
		{"t": Locale.t("help.fleet.orders_title"), "l": [
			Locale.t("help.fleet.orders_1"),
			Locale.t("help.fleet.orders_2")]},
		{"t": Locale.t("help.fleet.squadron_title"), "l": [
			Locale.t("help.fleet.squadron_1"),
			Locale.t("help.fleet.squadron_2"),
			Locale.t("help.fleet.squadron_3")]},
		{"t": Locale.t("help.fleet.respawn_title"), "l": [
			Locale.t("help.fleet.respawn_1"),
			Locale.t("help.fleet.respawn_2"),
			Locale.t("help.fleet.respawn_3")]},
	]


# =============================================================================
# Drawing
# =============================================================================
func _draw() -> void:
	super._draw()
	var s := size
	var margin: float = UITheme.MARGIN_SCREEN + 8
	var font: Font = UITheme.get_font()
	var font_bold: Font = UITheme.get_font_bold()

	var top_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	_draw_tabs(margin, top_y, font_bold)

	var content_y: float = top_y + TAB_H + 12
	var content_rect := Rect2(margin, content_y, s.x - margin * 2, s.y - content_y - margin - 24)

	# Content area frame
	draw_rect(content_rect, UITheme.BG_PANEL)
	draw_rect(content_rect, UITheme.BORDER, false, 1.0)
	draw_corners(content_rect, 14.0, UITheme.CORNER)
	draw_scanline(content_rect)

	# Tab content
	var vis_top: float = content_rect.position.y - LINE_H
	var vis_bot: float = content_rect.end.y + LINE_H
	if _active_tab == 0:
		_max_scroll = _draw_controls_tab(content_rect, font, font_bold, vis_top, vis_bot)
	else:
		_max_scroll = _draw_generic_tab(_tab_data[_active_tab], content_rect, font, font_bold, vis_top, vis_bot)
	_max_scroll = maxf(0.0, _max_scroll - content_rect.size.y + LINE_H)
	_scroll_offset = clampf(_scroll_offset, 0.0, _max_scroll)

	# Scrollbar
	if _max_scroll > 0.0:
		var vh: float = content_rect.size.y
		var bh: float = maxf(24.0, vh * vh / (vh + _max_scroll))
		var by: float = content_rect.position.y + (_scroll_offset / _max_scroll) * (vh - bh)
		draw_rect(Rect2(content_rect.end.x - 4, by, 3, bh), UITheme.PRIMARY_DIM)

	# Close hint
	draw_string(font, Vector2(margin, s.y - margin), Locale.t("common.close_hint"),
		HORIZONTAL_ALIGNMENT_CENTER, content_rect.size.x, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Outer decorative frame with pulse
	var pulse: float = UITheme.get_pulse(0.5)
	var oc := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03 + pulse * 0.02)
	draw_rect(Rect2(margin - 4, top_y - 4, s.x - (margin - 4) * 2, s.y - top_y - margin + 8), oc, false, 1.5)


func _draw_tabs(_margin: float, top_y: float, font_bold: Font) -> void:
	var x: float = _margin
	var fsize: int = UITheme.FONT_SIZE_BODY
	for i in TAB_LABELS.size():
		var tw: float = font_bold.get_string_size(TAB_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + TAB_PAD * 2
		var r := Rect2(x, top_y, tw, TAB_H)
		if i == _active_tab:
			draw_rect(r, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12))
			draw_line(Vector2(x, top_y + TAB_H), Vector2(x + tw, top_y + TAB_H), UITheme.PRIMARY, 2.0)
		elif i == _tab_hovered:
			draw_rect(r, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
		draw_rect(r, UITheme.BORDER, false, 1.0)
		var tc: Color = UITheme.TEXT_HEADER if i == _active_tab else UITheme.TEXT_DIM
		draw_string(font_bold, Vector2(x, top_y + TAB_H * 0.5 + fsize * 0.35), TAB_LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, tw, fsize, tc)
		x += tw + 4


# Controls tab uses two-column layout for keybinds
func _draw_controls_tab(rect: Rect2, font: Font, font_bold: Font, vt: float, vb: float) -> float:
	var x: float = rect.position.x + UITheme.MARGIN_PANEL
	var w: float = rect.size.x - UITheme.MARGIN_PANEL * 2
	var y0: float = rect.position.y + UITheme.MARGIN_PANEL - _scroll_offset
	var col_w: float = minf(w * 0.5 - 10, 380.0)

	# Left column: FLIGHT + NAVIGATION
	var y: float = _draw_kb(x, y0, col_w, Locale.t("help.flight.title"), [
		["W / S", Locale.t("help.flight.forward_back")], ["A / D", Locale.t("help.flight.strafe")],
		["Space / Ctrl", Locale.t("help.flight.up_down")], ["Q / E", Locale.t("help.flight.roll")],
		["Mouse", Locale.t("help.flight.orientation")], ["Shift", Locale.t("help.flight.boost")],
		["C", Locale.t("help.flight.cruise")], ["W", Locale.t("help.flight.freelook")]], font, font_bold, vt, vb)
	y = _draw_kb(x, y + 10, col_w, Locale.t("help.nav.title"), [
		["M", Locale.t("help.nav.system_map")], ["G", Locale.t("help.nav.galaxy_map")],
		["F", Locale.t("help.nav.dock")],
		["Entrée", Locale.t("help.nav.wormhole")]], font, font_bold, vt, vb)

	# Right column: COMBAT + MISC
	var rx: float = x + col_w + 20
	var ry: float = _draw_kb(rx, y0, col_w, Locale.t("help.combat.title"), [
		["LMB", Locale.t("help.combat.primary")], ["RMB", Locale.t("help.combat.secondary")],
		["Tab", Locale.t("help.combat.target_next")], ["T", Locale.t("help.combat.target_nearest")],
		["Y", Locale.t("help.combat.target_clear")], ["Tab + 1/2/3", Locale.t("help.combat.pips")]],
		font, font_bold, vt, vb)
	ry = _draw_kb(rx, ry + 10, col_w, Locale.t("help.misc.title"), [
		["X", Locale.t("help.misc.loot")], ["R", Locale.t("help.misc.respawn")], ["N", Locale.t("help.misc.corporation")],
		["P", Locale.t("help.misc.multiplayer")], ["F1", Locale.t("help.misc.help")], ["Esc", Locale.t("help.misc.pause")],
		["F12", Locale.t("help.misc.bug_report")]], font, font_bold, vt, vb)

	return maxf(y, ry) - y0 + UITheme.MARGIN_PANEL


# Generic tab renderer for text-based sections (combat, economy, fleet)
func _draw_generic_tab(sections: Array, rect: Rect2, font: Font, _font_bold: Font, vt: float, vb: float) -> float:
	var x: float = rect.position.x + UITheme.MARGIN_PANEL
	var w: float = rect.size.x - UITheme.MARGIN_PANEL * 2
	var y: float = rect.position.y + UITheme.MARGIN_PANEL - _scroll_offset
	var start_y: float = y
	var fsize: int = UITheme.FONT_SIZE_LABEL
	for sec in sections:
		if y > vt and y < vb:
			y = draw_section_header(x, y, w, sec["t"])
		else:
			y += UITheme.FONT_SIZE_LABEL + 4 + UITheme.MARGIN_SECTION
		for line in sec.get("l", []):
			if y > vt and y + LINE_H < vb:
				draw_string(font, Vector2(x + 8, y + fsize), line,
					HORIZONTAL_ALIGNMENT_LEFT, w - 16, fsize, UITheme.TEXT)
			y += LINE_H
		y += 10  # Section gap
	return y - start_y + UITheme.MARGIN_PANEL


# Draw keybind section: header + key/description rows
func _draw_kb(x: float, y: float, w: float, title: String, bindings: Array,
		font: Font, font_bold: Font, vt: float, vb: float) -> float:
	if y > vt and y < vb:
		y = draw_section_header(x, y, w, title)
	else:
		y += UITheme.FONT_SIZE_LABEL + 4 + UITheme.MARGIN_SECTION
	var fsize: int = UITheme.FONT_SIZE_LABEL
	for b in bindings:
		if y > vt and y + LINE_H < vb:
			var ty: float = y + fsize
			draw_string(font_bold, Vector2(x + 4, ty), b[0],
				HORIZONTAL_ALIGNMENT_LEFT, KEY_COL_W, fsize, UITheme.PRIMARY)
			draw_string(font, Vector2(x + KEY_COL_W + 8, ty), b[1],
				HORIZONTAL_ALIGNMENT_LEFT, w - KEY_COL_W - 12, fsize, UITheme.TEXT_DIM)
		y += LINE_H
	return y


# =============================================================================
# Input
# =============================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - SCROLL_STEP)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_offset = minf(_max_scroll, _scroll_offset + SCROLL_STEP)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var tab_idx: int = _hit_test_tab(event.position)
			if tab_idx >= 0 and tab_idx != _active_tab:
				_active_tab = tab_idx
				_scroll_offset = 0.0
				queue_redraw()
				accept_event()
				return
			var cr := Rect2(size.x - UITheme.MARGIN_SCREEN - 28, UITheme.MARGIN_SCREEN, 32, 28)
			if cr.has_point(event.position):
				close()
				accept_event()
				return

	if event is InputEventMouseMotion:
		var nh: int = _hit_test_tab(event.position)
		if nh != _tab_hovered:
			_tab_hovered = nh
			queue_redraw()
	accept_event()


func _hit_test_tab(pos: Vector2) -> int:
	var margin: float = UITheme.MARGIN_SCREEN + 8
	var tab_y: float = margin + UITheme.FONT_SIZE_TITLE + 20
	var fb: Font = UITheme.get_font_bold()
	var fsize: int = UITheme.FONT_SIZE_BODY
	var x: float = margin
	for i in TAB_LABELS.size():
		var tw: float = fb.get_string_size(TAB_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + TAB_PAD * 2
		if Rect2(x, tab_y, tw, TAB_H).has_point(pos):
			return i
		x += tw + 4
	return -1


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
