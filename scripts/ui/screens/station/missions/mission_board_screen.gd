class_name MissionBoardScreen
extends UIScreen

# =============================================================================
# Mission Board Screen - Station mission terminal
# Two tabs: DISPONIBLES (available) / EN COURS (active)
# Custom-drawn (_draw), follows UIScreen + UIComponent patterns.
# Card rendering delegated to MissionCardDrawer.
# =============================================================================

signal mission_board_closed

# --- Tab constants ---
const TAB_AVAILABLE: int = 0
const TAB_ACTIVE: int = 1
const TAB_LABELS: PackedStringArray = PackedStringArray(["DISPONIBLES", "EN COURS"])

# --- Card layout ---
const CARD_MARGIN_X: float = 40.0
const CARD_HEIGHT: float = 110.0
const CARD_GAP: float = 10.0

# --- State ---
var _available_missions: Array = []
var _mission_manager = null
var _active_tab: int = TAB_AVAILABLE
var _hovered_card: int = -1
var _hovered_button: int = -1
var _scroll_offset: float = 0.0
var _tab_hovered: int = -1
var _flash: Dictionary = {}


func _ready() -> void:
	screen_title = "MISSIONS"
	screen_mode = ScreenMode.FULLSCREEN
	super._ready()


## Called before opening to inject data.
func setup(available: Array, mission_mgr) -> void:
	_available_missions = available
	_mission_manager = mission_mgr
	_scroll_offset = 0.0
	_hovered_card = -1
	_hovered_button = -1
	queue_redraw()


func _on_opened() -> void:
	_active_tab = TAB_AVAILABLE
	_hovered_card = -1
	_hovered_button = -1
	_scroll_offset = 0.0
	queue_redraw()


func _on_closed() -> void:
	_hovered_card = -1
	_hovered_button = -1
	mission_board_closed.emit()


# =============================================================================
# LAYOUT HELPERS
# =============================================================================

func _get_content_rect() -> Rect2:
	var s: Vector2 = size
	var top: float = 80.0
	var bottom: float = 20.0
	return Rect2(CARD_MARGIN_X, top, s.x - CARD_MARGIN_X * 2.0, s.y - top - bottom)


func _get_tab_rect(tab_idx: int) -> Rect2:
	var tab_w: float = 160.0
	var tab_h: float = 28.0
	var total_w: float = tab_w * TAB_LABELS.size() + 8.0
	var start_x: float = (size.x - total_w) * 0.5
	return Rect2(start_x + tab_idx * (tab_w + 8.0), 48.0, tab_w, tab_h)


func _get_current_list() -> Array:
	if _active_tab == TAB_ACTIVE and _mission_manager:
		return _mission_manager.get_active_missions()
	return _available_missions


func _get_card_rect(idx: int, content: Rect2) -> Rect2:
	var y: float = content.position.y + idx * (CARD_HEIGHT + CARD_GAP) - _scroll_offset
	return Rect2(content.position.x, y, content.size.x, CARD_HEIGHT)


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), UITheme.BG_DARK)
	_draw_title(s)

	if not _is_open:
		return

	_draw_tabs()
	var content: Rect2 = _get_content_rect()
	var missions: Array = _get_current_list()

	if missions.is_empty():
		_draw_empty_state(content)
	else:
		var is_accept: bool = _active_tab == TAB_AVAILABLE
		var show_prog: bool = _active_tab == TAB_ACTIVE
		for i in missions.size():
			var card_r: Rect2 = _get_card_rect(i, content)
			if card_r.end.y < content.position.y or card_r.position.y > content.end.y:
				continue
			MissionCardDrawer.draw_card(
				self, card_r, missions[i],
				_hovered_card == i, _flash.get(i, 0.0),
				show_prog, _hovered_button == i,
				is_accept, _mission_manager
			)

	_draw_scroll_indicator(content, missions.size())

	draw_corners(Rect2(20, 20, s.x - 40, s.y - 40), 15.0, UITheme.CORNER)
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03), 1.0)


func _draw_tabs() -> void:
	var font: Font = UITheme.get_font()
	for i in TAB_LABELS.size():
		var r: Rect2 = _get_tab_rect(i)
		var is_active: bool = _active_tab == i
		var is_hov: bool = _tab_hovered == i

		if is_active:
			draw_rect(r, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.2))
		elif is_hov:
			draw_rect(r, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08))

		var bcol: Color = UITheme.PRIMARY if is_active else (UITheme.BORDER_HOVER if is_hov else UITheme.BORDER)
		draw_rect(r, bcol, false, 1.0)

		if is_active:
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), UITheme.PRIMARY, 2.0)

		var tcol: Color = UITheme.TEXT if is_active else UITheme.TEXT_DIM
		var ty: float = r.position.y + (r.size.y + UITheme.FONT_SIZE_BODY) * 0.5 - 2.0
		var label: String = TAB_LABELS[i]
		if i == TAB_ACTIVE and _mission_manager:
			label += " (%d)" % _mission_manager.get_active_count()
		draw_string(font, Vector2(r.position.x, ty), label,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UITheme.FONT_SIZE_BODY, tcol)


func _draw_empty_state(content: Rect2) -> void:
	var font: Font = UITheme.get_font()
	var cy: float = content.position.y + content.size.y * 0.4
	var msg: String = "Aucune mission disponible" if _active_tab == TAB_AVAILABLE else "Aucune mission en cours"
	draw_string(font, Vector2(content.position.x, cy), msg,
		HORIZONTAL_ALIGNMENT_CENTER, content.size.x, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)


func _draw_scroll_indicator(content: Rect2, total: int) -> void:
	if total <= 0:
		return
	var total_h: float = total * (CARD_HEIGHT + CARD_GAP)
	if total_h <= content.size.y:
		return
	var track_x: float = content.end.x + 4.0
	var track_h: float = content.size.y
	var ratio: float = content.size.y / total_h
	var thumb_h: float = maxf(track_h * ratio, 20.0)
	var scroll_ratio: float = _scroll_offset / (total_h - content.size.y)
	var thumb_y: float = content.position.y + (track_h - thumb_h) * clampf(scroll_ratio, 0.0, 1.0)
	draw_rect(Rect2(track_x, content.position.y, 3.0, track_h), Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.2))
	draw_rect(Rect2(track_x, thumb_y, 3.0, thumb_h), UITheme.PRIMARY_DIM)


# =============================================================================
# INTERACTION
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	var content: Rect2 = _get_content_rect()
	var missions: Array = _get_current_list()

	if event is InputEventMouseMotion:
		var old_card: int = _hovered_card
		var old_btn: int = _hovered_button
		var old_tab: int = _tab_hovered
		_hovered_card = -1
		_hovered_button = -1
		_tab_hovered = -1

		for i in TAB_LABELS.size():
			if _get_tab_rect(i).has_point(event.position):
				_tab_hovered = i
				break

		for i in missions.size():
			var card_r: Rect2 = _get_card_rect(i, content)
			if card_r.end.y < content.position.y or card_r.position.y > content.end.y:
				continue
			if card_r.has_point(event.position):
				_hovered_card = i
				if MissionCardDrawer.get_button_rect(card_r).has_point(event.position):
					_hovered_button = i
				break

		if _hovered_card != old_card or _hovered_button != old_btn or _tab_hovered != old_tab:
			queue_redraw()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Close button
			var close_rect := Rect2(size.x - UITheme.MARGIN_SCREEN - 28, UITheme.MARGIN_SCREEN, 32, 28)
			if close_rect.has_point(event.position):
				close()
				accept_event()
				return

			for i in TAB_LABELS.size():
				if _get_tab_rect(i).has_point(event.position):
					_active_tab = i
					_scroll_offset = 0.0
					_hovered_card = -1
					_hovered_button = -1
					queue_redraw()
					accept_event()
					return

			for i in missions.size():
				var card_r: Rect2 = _get_card_rect(i, content)
				if card_r.end.y < content.position.y or card_r.position.y > content.end.y:
					continue
				if MissionCardDrawer.get_button_rect(card_r).has_point(event.position):
					_flash[i] = 1.0
					_on_button_clicked(missions[i])
					accept_event()
					return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = maxf(0.0, _scroll_offset - 40.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var total_h: float = missions.size() * (CARD_HEIGHT + CARD_GAP)
			var max_scroll: float = maxf(0.0, total_h - content.size.y)
			_scroll_offset = minf(max_scroll, _scroll_offset + 40.0)
			queue_redraw()

	accept_event()


func _on_button_clicked(mission: MissionData) -> void:
	if _mission_manager == null:
		return
	if _active_tab == TAB_AVAILABLE:
		if _mission_manager.has_mission(mission.mission_id):
			return
		var success: bool = _mission_manager.accept_mission(mission)
		if success and GameManager._notif:
			GameManager._notif.toast("MISSION ACCEPTEE: " + mission.title)
	else:
		_mission_manager.abandon_mission(mission.mission_id)
		if GameManager._notif:
			GameManager._notif.toast("MISSION ABANDONNEE: " + mission.title)
	queue_redraw()


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	if not _is_open:
		return
	var dirty: bool = false
	for key in _flash.keys():
		_flash[key] = maxf(0.0, _flash[key] - delta / 0.12)
		if _flash[key] <= 0.0:
			_flash.erase(key)
		dirty = true
	if _active_tab == TAB_ACTIVE and _mission_manager and _mission_manager.get_active_count() > 0:
		dirty = true
	if dirty:
		queue_redraw()
