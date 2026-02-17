class_name NoCorporationView
extends UIComponent

# =============================================================================
# No Corporation View - Create or join a corporation when player has none
# Two panels: Left = Create, Right = Search & Join
# =============================================================================

signal corporation_action_completed

var _cm = null

# Create panel
var _input_name: UITextInput = null
var _input_tag: UITextInput = null
var _btn_create: UIButton = null
var _selected_color_idx: int = 0

# Search panel
var _input_search: UITextInput = null
var _btn_search: UIButton = null
var _btn_join: UIButton = null
var _search_results: Array = []
var _selected_result_idx: int = -1
var _scroll_offset: int = 0
var _hovered_row: int = -1

# Status
var _status_text: String = ""
var _status_color: Color = UITheme.TEXT

const GAP := 20.0
const COLOR_PRESETS: Array[Color] = [
	Color(0.0, 0.85, 1.0),    # Cyan
	Color(0.15, 0.85, 0.15),  # Green
	Color(1.0, 0.4, 0.2),     # Orange
	Color(0.8, 0.2, 1.0),     # Purple
	Color(1.0, 0.85, 0.0),    # Yellow
	Color(1.0, 0.15, 0.1),    # Red
]
const COLOR_NAMES: Array[String] = ["Cyan", "Vert", "Orange", "Violet", "Jaune", "Rouge"]


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	# ─── Create panel inputs ───
	_input_name = UITextInput.new()
	_input_name.placeholder = "Nom de la corporation (3+ caracteres)"
	add_child(_input_name)

	_input_tag = UITextInput.new()
	_input_tag.placeholder = "Tag (2-4 lettres)"
	add_child(_input_tag)

	_btn_create = UIButton.new()
	_btn_create.text = "Creer la corporation"
	_btn_create.pressed.connect(_on_create_pressed)
	add_child(_btn_create)

	# ─── Search panel inputs ───
	_input_search = UITextInput.new()
	_input_search.placeholder = "Rechercher une corporation..."
	_input_search.text_submitted.connect(_on_search_submitted)
	add_child(_input_search)

	_btn_search = UIButton.new()
	_btn_search.text = "Chercher"
	_btn_search.pressed.connect(_on_search_pressed)
	add_child(_btn_search)

	_btn_join = UIButton.new()
	_btn_join.text = "Rejoindre"
	_btn_join.visible = false
	_btn_join.pressed.connect(_on_join_pressed)
	add_child(_btn_join)


func refresh(cm) -> void:
	_cm = cm
	_search_results.clear()
	_selected_result_idx = -1
	_status_text = ""
	_btn_join.visible = false
	queue_redraw()
	# Auto-load all corporations so the list is populated on open
	if _cm != null and AuthManager.is_authenticated:
		_status_text = "Chargement..."
		_status_color = UITheme.PRIMARY
		queue_redraw()
		_search_results = await _cm.fetch_all_corporations()
		if _search_results.size() > 0:
			_status_text = "%d corporation(s) trouvee(s)" % _search_results.size()
			_status_color = UITheme.ACCENT
		else:
			_status_text = "Aucune corporation trouvee"
			_status_color = UITheme.TEXT_DIM
		queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 16.0
	var half_w: float = (size.x - GAP) * 0.5

	# Left panel: Create
	var lx: float = 0.0
	var ly: float = 80.0
	_input_name.position = Vector2(lx + m, ly)
	_input_name.size = Vector2(half_w - m * 2, 30)

	_input_tag.position = Vector2(lx + m, ly + 40)
	_input_tag.size = Vector2(half_w * 0.4, 30)

	# Color buttons are drawn, not Controls

	_btn_create.position = Vector2(lx + m, ly + 160)
	_btn_create.size = Vector2(half_w - m * 2, 34)

	# Right panel: Search
	var rx: float = half_w + GAP
	var ry: float = 80.0
	var search_btn_w: float = 100.0
	_input_search.position = Vector2(rx + m, ry)
	_input_search.size = Vector2(half_w - m * 2 - search_btn_w - 8, 30)

	_btn_search.position = Vector2(rx + half_w - m - search_btn_w, ry)
	_btn_search.size = Vector2(search_btn_w, 30)

	_btn_join.position = Vector2(rx + m, size.y - 50)
	_btn_join.size = Vector2(half_w - m * 2, 34)


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var m: float = 16.0
	var half_w: float = (size.x - GAP) * 0.5

	# If not authenticated, show message
	if not AuthManager.is_authenticated:
		draw_panel_bg(Rect2(0, 0, size.x, size.y))
		draw_string(font, Vector2(0, size.y * 0.4), "CONNEXION REQUISE", HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_TITLE, UITheme.TEXT_DIM)
		draw_string(font, Vector2(0, size.y * 0.4 + 28), "Connectez-vous pour creer ou rejoindre une corporation", HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_BODY, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.6))
		return

	# ─── LEFT PANEL: Create ────────────────────────────────────────────
	var left_rect := Rect2(0, 0, half_w, size.y)
	draw_panel_bg(left_rect)

	# Title
	var _header_y := _draw_section_header(m, m, half_w - m * 2, "CREER UNE CORPORATION")

	# Color selector (below tag input)
	var color_y: float = 80.0 + 80.0
	draw_string(font, Vector2(m, color_y + 14), "Couleur:", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	var cx: float = m + 70
	for i in COLOR_PRESETS.size():
		var col: Color = COLOR_PRESETS[i]
		var btn_rect := Rect2(cx + i * 38, color_y, 30, 24)
		if i == _selected_color_idx:
			draw_rect(Rect2(btn_rect.position.x - 2, btn_rect.position.y - 2, btn_rect.size.x + 4, btn_rect.size.y + 4), UITheme.PRIMARY, false, 2.0)
		draw_rect(btn_rect, col)
		draw_rect(btn_rect, Color(1, 1, 1, 0.15), false, 1.0)

	# Color name
	draw_string(font, Vector2(m, color_y + 44), "Selectionnee: %s" % COLOR_NAMES[_selected_color_idx], HORIZONTAL_ALIGNMENT_LEFT, half_w - m * 2, UITheme.FONT_SIZE_SMALL, COLOR_PRESETS[_selected_color_idx])

	# ─── RIGHT PANEL: Search ───────────────────────────────────────────
	var rx: float = half_w + GAP
	var right_rect := Rect2(rx, 0, half_w, size.y)
	draw_panel_bg(right_rect)

	_draw_section_header(rx + m, m, half_w - m * 2, "REJOINDRE UNE CORPORATION")

	# Results table
	var table_y: float = 80.0 + 42.0
	var table_h: float = size.y - table_y - 64.0
	var row_h: float = 28.0

	# Table header
	draw_rect(Rect2(rx + m, table_y, half_w - m * 2, row_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08))
	var col_tag_x: float = rx + m + 4
	var col_name_x: float = rx + m + 60
	var col_members_x: float = rx + half_w - m - 100
	var col_status_x: float = rx + half_w - m - 40
	draw_string(font, Vector2(col_tag_x, table_y + 18), "TAG", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(col_name_x, table_y + 18), "NOM", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(col_members_x, table_y + 18), "MEMBRES", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Rows
	var visible_rows: int = int(table_h / row_h) - 1
	for i in mini(_search_results.size(), visible_rows):
		var idx: int = i + _scroll_offset
		if idx >= _search_results.size():
			break
		var r: Dictionary = _search_results[idx]
		var ry: float = table_y + row_h * (i + 1)

		# Selection highlight
		if idx == _selected_result_idx:
			draw_rect(Rect2(rx + m, ry, half_w - m * 2, row_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.12))
		elif idx == _hovered_row:
			draw_rect(Rect2(rx + m, ry, half_w - m * 2, row_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.05))

		# Row separator
		draw_line(Vector2(rx + m, ry), Vector2(rx + half_w - m, ry), Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.3), 1.0)

		var text_col: Color = UITheme.TEXT if r.get("is_recruiting", false) else UITheme.TEXT_DIM
		draw_string(font, Vector2(col_tag_x, ry + 18), "[%s]" % r.get("tag", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.PRIMARY)
		draw_string(font, Vector2(col_name_x, ry + 18), str(r.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, col_members_x - col_name_x - 8, UITheme.FONT_SIZE_BODY, text_col)
		draw_string(font, Vector2(col_members_x, ry + 18), str(r.get("members", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

		# Recruiting status
		var status_text: String = "OUVERT" if r.get("is_recruiting", false) else "FERME"
		var status_col: Color = UITheme.ACCENT if r.get("is_recruiting", false) else UITheme.DANGER
		draw_string(font, Vector2(col_status_x, ry + 18), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, status_col)

	if _search_results.is_empty() and _status_text != "Chargement...":
		var empty_y: float = table_y + table_h * 0.4
		draw_string(font, Vector2(rx + m, empty_y), "Aucune corporation disponible", HORIZONTAL_ALIGNMENT_CENTER, half_w - m * 2, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# ─── Status text ───────────────────────────────────────────────────
	if _status_text != "":
		draw_string(font, Vector2(0, size.y - 8), _status_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_BODY, _status_color)


func _draw_section_header(x: float, y: float, w: float, text: String) -> float:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_HEADER
	draw_rect(Rect2(x, y + 2, 3, fsize + 2), UITheme.PRIMARY)
	draw_string(font, Vector2(x + 10, y + fsize + 1), text, HORIZONTAL_ALIGNMENT_LEFT, w - 14, fsize, UITheme.TEXT_HEADER)
	var ly: float = y + fsize + 6
	draw_line(Vector2(x, ly), Vector2(x + w, ly), UITheme.PRIMARY_DIM, 1.0)
	return ly + 8


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	var half_w: float = (size.x - GAP) * 0.5
	var m: float = 16.0

	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position

		# Color selector clicks (left panel)
		var color_y: float = 80.0 + 80.0
		var cx: float = m + 70
		for i in COLOR_PRESETS.size():
			var btn_rect := Rect2(cx + i * 38, color_y, 30, 24)
			if btn_rect.has_point(pos):
				_selected_color_idx = i
				queue_redraw()
				accept_event()
				return

		# Search result clicks (right panel)
		var rx: float = half_w + GAP
		var table_y: float = 80.0 + 42.0
		var row_h: float = 28.0
		if pos.x >= rx + m and pos.x <= rx + half_w - m:
			var row_idx: int = int((pos.y - table_y - row_h) / row_h) + _scroll_offset
			if row_idx >= 0 and row_idx < _search_results.size():
				_selected_result_idx = row_idx
				_btn_join.visible = _search_results[row_idx].get("is_recruiting", false)
				queue_redraw()
				accept_event()
				return

		# Mouse wheel for scroll
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxi(0, _scroll_offset - 1)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_offset = mini(_search_results.size() - 1, _scroll_offset + 1)
			queue_redraw()

	elif event is InputEventMouseMotion:
		var pos: Vector2 = event.position
		var rx: float = half_w + GAP
		var table_y: float = 80.0 + 42.0
		var row_h: float = 28.0
		var old_hovered := _hovered_row
		if pos.x >= rx + m and pos.x <= rx + half_w - m:
			_hovered_row = int((pos.y - table_y - row_h) / row_h) + _scroll_offset
			if _hovered_row < 0 or _hovered_row >= _search_results.size():
				_hovered_row = -1
		else:
			_hovered_row = -1
		if _hovered_row != old_hovered:
			queue_redraw()


# =============================================================================
# ACTIONS
# =============================================================================

func _on_create_pressed() -> void:
	if _cm == null or not AuthManager.is_authenticated:
		_status_text = "Connexion requise"
		_status_color = UITheme.DANGER
		queue_redraw()
		return

	var cname: String = _input_name.get_text().strip_edges()
	var tag: String = _input_tag.get_text().strip_edges().to_upper()

	if cname.length() < 3:
		_status_text = "Le nom de la corporation doit contenir au moins 3 caracteres"
		_status_color = UITheme.DANGER
		queue_redraw()
		return

	if tag.length() < 2 or tag.length() > 4:
		_status_text = "Le tag doit contenir entre 2 et 4 caracteres"
		_status_color = UITheme.DANGER
		queue_redraw()
		return

	_status_text = "Creation de la corporation en cours..."
	_status_color = UITheme.PRIMARY
	queue_redraw()

	var success: bool = await _cm.create_corporation(cname, tag, COLOR_PRESETS[_selected_color_idx], 0)
	if success:
		_status_text = ""
		corporation_action_completed.emit()
	else:
		_status_text = "Erreur lors de la creation de la corporation"
		_status_color = UITheme.DANGER
		queue_redraw()


func _on_search_submitted(_text: String) -> void:
	_on_search_pressed()


func _on_search_pressed() -> void:
	if _cm == null or not AuthManager.is_authenticated:
		_status_text = "Connexion requise"
		_status_color = UITheme.DANGER
		queue_redraw()
		return

	var query: String = _input_search.get_text().strip_edges()
	_status_text = "Recherche..."
	_status_color = UITheme.PRIMARY
	_selected_result_idx = -1
	_btn_join.visible = false
	queue_redraw()

	_search_results = await _cm.search_corporations(query)
	_status_text = "%d corporation(s) trouvee(s)" % _search_results.size() if _search_results.size() > 0 else "Aucune corporation trouvee"
	_status_color = UITheme.ACCENT if _search_results.size() > 0 else UITheme.TEXT_DIM
	queue_redraw()


func _on_join_pressed() -> void:
	if _cm == null or _selected_result_idx < 0 or _selected_result_idx >= _search_results.size():
		return

	var corporation: Dictionary = _search_results[_selected_result_idx]
	if not corporation.get("is_recruiting", false):
		_status_text = "Cette corporation ne recrute pas"
		_status_color = UITheme.WARNING
		queue_redraw()
		return

	_status_text = "Rejoindre la corporation en cours..."
	_status_color = UITheme.PRIMARY
	queue_redraw()

	var success: bool = await _cm.join_corporation(str(corporation.get("id", "")))
	if success:
		_status_text = ""
		corporation_action_completed.emit()
	else:
		_status_text = "Erreur lors de la tentative de rejoindre la corporation"
		_status_color = UITheme.DANGER
		queue_redraw()
