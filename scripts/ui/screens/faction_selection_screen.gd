class_name FactionSelectionScreen
extends UIScreen

# =============================================================================
# Faction Selection Screen — Fullscreen faction choice at first connection.
# Two large cards (Nova Terra / Kharsis), sci-fi dark design.
# No close button — choice is mandatory.
# =============================================================================

signal faction_selected(faction_id: StringName)

var _factions: Array[FactionResource] = []
var _selected_index: int = -1
var _hovered_index: int = -1
var _confirmed: bool = false

# Card layout constants
const CARD_W: float = 380.0
const CARD_H: float = 420.0
const CARD_GAP: float = 60.0
const BTN_W: float = 260.0
const BTN_H: float = 44.0

var _btn_confirm: UIButton = null


func _init() -> void:
	screen_title = "CHOISISSEZ VOTRE FACTION"
	screen_mode = ScreenMode.FULLSCREEN


func _ready() -> void:
	super._ready()

	# Confirm button (hidden until selection)
	_btn_confirm = UIButton.new()
	_btn_confirm.text = "CONFIRMER"
	_btn_confirm.custom_minimum_size = Vector2(BTN_W, BTN_H)
	_btn_confirm.visible = false
	_btn_confirm.pressed.connect(_on_confirm)
	add_child(_btn_confirm)


func setup(factions: Array[FactionResource], current_faction: StringName) -> void:
	_factions = factions
	_selected_index = -1
	_confirmed = false
	# Pre-select if already chosen
	if current_faction != &"":
		for i in _factions.size():
			if _factions[i].faction_id == current_faction:
				_selected_index = i
				break
	_update_confirm_button()


func _on_opened() -> void:
	queue_redraw()


## Override close to prevent closing without selection
func close() -> void:
	if _confirmed:
		super.close()


func _on_confirm() -> void:
	if _selected_index < 0 or _selected_index >= _factions.size():
		return
	_confirmed = true
	faction_selected.emit(_factions[_selected_index].faction_id)


func _update_confirm_button() -> void:
	if _btn_confirm:
		_btn_confirm.visible = _selected_index >= 0
		if _selected_index >= 0 and _selected_index < _factions.size():
			_btn_confirm.accent_color = _factions[_selected_index].color_primary


func _get_card_rects() -> Array[Rect2]:
	var s := size
	var total_w: float = CARD_W * _factions.size() + CARD_GAP * maxf(0, _factions.size() - 1)
	var start_x: float = (s.x - total_w) * 0.5
	var start_y: float = (s.y - CARD_H) * 0.5 - 30.0

	var rects: Array[Rect2] = []
	for i in _factions.size():
		var x: float = start_x + i * (CARD_W + CARD_GAP)
		rects.append(Rect2(x, start_y, CARD_W, CARD_H))
	return rects


func _draw() -> void:
	var s := size

	# Deep space background
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.015, 0.025, 0.97))

	# Subtle grid pattern
	var grid_col := Color(0.1, 0.15, 0.2, 0.04)
	var step: float = 40.0
	var x: float = 0.0
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), grid_col, 1.0)
		x += step
	var y: float = 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), grid_col, 1.0)
		y += step

	# Title
	var font_bold: Font = UITheme.get_font_bold()
	var fsize_title: int = UITheme.FONT_SIZE_TITLE
	var title_y: float = 60.0 + fsize_title
	draw_string(font_bold, Vector2(0, title_y), screen_title, HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize_title, UITheme.TEXT_HEADER)

	# Decorative lines beside title
	var title_w: float = font_bold.get_string_size(screen_title, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize_title).x
	var cx: float = s.x * 0.5
	var line_y: float = title_y - fsize_title * 0.35
	var half: float = title_w * 0.5 + 20
	draw_line(Vector2(cx - half - 120, line_y), Vector2(cx - half, line_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(cx + half, line_y), Vector2(cx + half + 120, line_y), UITheme.BORDER, 1.0)

	# Subtitle
	var font: Font = UITheme.get_font()
	var subtitle_y: float = title_y + 28.0
	draw_string(font, Vector2(0, subtitle_y), "Votre allégeance détermine vos alliés et vos ennemis.", HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# Faction cards
	var rects := _get_card_rects()
	for i in _factions.size():
		_draw_faction_card(rects[i], _factions[i], i == _selected_index, i == _hovered_index)

	# Position confirm button
	if _btn_confirm and _btn_confirm.visible:
		var btn_x: float = (s.x - BTN_W) * 0.5
		var btn_y: float = rects[0].end.y + 40.0 if not rects.is_empty() else s.y - 100.0
		_btn_confirm.position = Vector2(btn_x, btn_y)
		_btn_confirm.size = Vector2(BTN_W, BTN_H)

	# Bottom hint
	if _selected_index < 0:
		var hint_y: float = s.y - 40.0
		draw_string(font, Vector2(0, hint_y), "Sélectionnez une faction pour continuer", HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_SMALL, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.5 + sin(UITheme.scanline_y * 0.02) * 0.3))


func _draw_faction_card(rect: Rect2, fac: FactionResource, is_selected: bool, is_hovered: bool) -> void:
	var font_bold: Font = UITheme.get_font_bold()
	var font: Font = UITheme.get_font()
	var col: Color = fac.color_primary

	# Card background
	var bg_alpha: float = 0.12 if is_selected else (0.08 if is_hovered else 0.04)
	draw_rect(rect, Color(col.r, col.g, col.b, bg_alpha))

	# Border
	var border_alpha: float = 0.9 if is_selected else (0.5 if is_hovered else 0.2)
	var border_width: float = 2.0 if is_selected else 1.0
	draw_rect(rect, Color(col.r, col.g, col.b, border_alpha), false, border_width)

	# Top glow line
	if is_selected or is_hovered:
		var glow_a: float = 0.6 if is_selected else 0.3
		draw_line(Vector2(rect.position.x + 1, rect.position.y), Vector2(rect.end.x - 1, rect.position.y), Color(col.r, col.g, col.b, glow_a), 3.0)

	# Corner accents
	draw_corners(rect, 12.0, Color(col.r, col.g, col.b, border_alpha))

	# Selected indicator
	if is_selected:
		# Glowing border effect
		var outer := Rect2(rect.position - Vector2(3, 3), rect.size + Vector2(6, 6))
		draw_rect(outer, Color(col.r, col.g, col.b, 0.15), false, 1.0)

	var cx: float = rect.position.x + rect.size.x * 0.5
	var py: float = rect.position.y + 30.0

	# Geometric emblem (faction symbol)
	_draw_faction_emblem(Vector2(cx, py + 50.0), 40.0, col, fac.faction_id)
	py += 110.0

	# Faction name
	draw_string(font_bold, Vector2(rect.position.x, py), fac.faction_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_TITLE, col)
	py += 36.0

	# Separator
	var sep_w: float = rect.size.x * 0.6
	var sep_x: float = cx - sep_w * 0.5
	draw_line(Vector2(sep_x, py), Vector2(sep_x + sep_w, py), Color(col.r, col.g, col.b, 0.3), 1.0)
	py += 16.0

	# Description text (word-wrapped manually)
	var desc: String = fac.description
	var desc_lines: PackedStringArray = _wrap_text(desc, font, UITheme.FONT_SIZE_BODY, rect.size.x - 40.0)
	for line in desc_lines:
		draw_string(font, Vector2(rect.position.x + 20, py), line, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		py += 20.0

	# Status label at bottom
	var status_y: float = rect.end.y - 30.0
	if is_selected:
		draw_string(font_bold, Vector2(rect.position.x, status_y), "SELECTIONNEE", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_SMALL, col)
	elif is_hovered:
		draw_string(font, Vector2(rect.position.x, status_y), "CLIQUEZ POUR SELECTIONNER", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_TINY, Color(col.r, col.g, col.b, 0.7))


func _draw_faction_emblem(center: Vector2, radius: float, col: Color, faction_id: StringName) -> void:
	match faction_id:
		&"nova_terra":
			# Shield / star shape — federation symbol
			var pts: PackedVector2Array = []
			for i in 6:
				var angle: float = -PI * 0.5 + TAU * float(i) / 6.0
				var r: float = radius if i % 2 == 0 else radius * 0.5
				pts.append(center + Vector2(cos(angle) * r, sin(angle) * r))
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.2))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
			# Inner circle
			_draw_circle_outline(center, radius * 0.35, col, 16)
		&"kharsis":
			# Angular / aggressive — dominion symbol
			var pts: PackedVector2Array = [
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.8, -radius * 0.3),
				center + Vector2(radius * 0.5, radius * 0.8),
				center + Vector2(0, radius * 0.4),
				center + Vector2(-radius * 0.5, radius * 0.8),
				center + Vector2(-radius * 0.8, -radius * 0.3),
			]
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.2))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
			# Inner cross
			draw_line(center + Vector2(0, -radius * 0.5), center + Vector2(0, radius * 0.3), col, 2.0)
			draw_line(center + Vector2(-radius * 0.4, 0), center + Vector2(radius * 0.4, 0), col, 2.0)
		_:
			# Default circle
			_draw_circle_outline(center, radius, col, 24)


func _draw_circle_outline(center: Vector2, radius: float, col: Color, segments: int) -> void:
	var pts: PackedVector2Array = []
	for i in segments + 1:
		var angle: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(angle) * radius, sin(angle) * radius))
	draw_polyline(pts, col, 1.5)


func _wrap_text(text: String, font: Font, fsize: int, max_width: float) -> PackedStringArray:
	var lines: PackedStringArray = []
	var words: PackedStringArray = text.split(" ")
	var current_line: String = ""
	for word in words:
		var test: String = (current_line + " " + word).strip_edges() if current_line != "" else word
		var tw: float = font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if tw > max_width and current_line != "":
			lines.append(current_line)
			current_line = word
		else:
			current_line = test
	if current_line != "":
		lines.append(current_line)
	return lines


func _gui_input(event: InputEvent) -> void:
	if _confirmed:
		accept_event()
		return

	if event is InputEventMouseMotion:
		var rects := _get_card_rects()
		var old_hover: int = _hovered_index
		_hovered_index = -1
		for i in rects.size():
			if rects[i].has_point(event.position):
				_hovered_index = i
				break
		if old_hover != _hovered_index:
			queue_redraw()
		accept_event()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rects := _get_card_rects()
		for i in rects.size():
			if rects[i].has_point(event.position):
				_selected_index = i
				_update_confirm_button()
				queue_redraw()
				break
		accept_event()
	else:
		accept_event()
