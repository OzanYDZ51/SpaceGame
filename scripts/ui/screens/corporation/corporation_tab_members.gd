class_name CorporationTabMembers
extends UIComponent

# =============================================================================
# Corporation Tab: Members - Searchable, sortable member list with actions
# Bigger row heights, richer drawing, colored status indicators
# =============================================================================

var _cm = null
var _search: UITextInput = null
var _filter_dropdown: UIDropdown = null
var _table: UIDataTable = null
var _btn_promote: UIButton = null
var _btn_demote: UIButton = null
var _btn_kick: UIButton = null

var _filtered_members: Array[CorporationMember] = []
var _selected_member: CorporationMember = null

# Applications section
var _applications: Array = []
var _app_scroll_offset: int = 0
var _app_hovered_row: int = -1
var _show_applications: bool = false
var _processing_application: bool = false


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_search = UITextInput.new()
	_search.placeholder = Locale.t("corp.search_member")
	_search.text_changed.connect(_on_search_changed)
	add_child(_search)

	_filter_dropdown = UIDropdown.new()
	_filter_dropdown.options.assign([Locale.t("corp.all_ranks")])
	_filter_dropdown.option_selected.connect(_on_filter_changed)
	add_child(_filter_dropdown)

	_table = UIDataTable.new()
	_table._row_height = 24.0
	_table.columns = [
		{ "label": Locale.t("corp.col_name"), "width_ratio": 0.22 },
		{ "label": Locale.t("corp.col_rank"), "width_ratio": 0.15 },
		{ "label": Locale.t("corp.col_status_header"), "width_ratio": 0.10 },
		{ "label": Locale.t("corp.col_contribution"), "width_ratio": 0.18 },
		{ "label": Locale.t("corp.col_kills"), "width_ratio": 0.10 },
		{ "label": Locale.t("corp.col_last_seen"), "width_ratio": 0.25 },
	]
	_table.row_selected.connect(_on_row_selected)
	_table.column_sort_requested.connect(_on_sort_requested)
	add_child(_table)

	_btn_promote = UIButton.new()
	_btn_promote.text = Locale.t("corp.promote")
	_btn_promote.accent_color = UITheme.ACCENT
	_btn_promote.pressed.connect(_on_promote)
	_btn_promote.visible = false
	add_child(_btn_promote)

	_btn_demote = UIButton.new()
	_btn_demote.text = Locale.t("corp.demote")
	_btn_demote.accent_color = UITheme.WARNING
	_btn_demote.pressed.connect(_on_demote)
	_btn_demote.visible = false
	add_child(_btn_demote)

	_btn_kick = UIButton.new()
	_btn_kick.text = Locale.t("corp.kick")
	_btn_kick.accent_color = UITheme.DANGER
	_btn_kick.pressed.connect(_on_kick)
	_btn_kick.visible = false
	add_child(_btn_kick)


func refresh(cm) -> void:
	_cm = cm
	_selected_member = null
	_btn_promote.visible = false
	_btn_demote.visible = false
	_btn_kick.visible = false
	_applications.clear()
	_show_applications = false

	if _cm == null or not _cm.has_corporation():
		return

	var rank_names: Array[String] = [Locale.t("corp.all_ranks")]
	for r in _cm.corporation_data.ranks:
		rank_names.append(r.rank_name)
	_filter_dropdown.options.assign(rank_names)
	_filter_dropdown.selected_index = 0
	_filter_dropdown.queue_redraw()
	_rebuild_table()

	# Load applications if officer+ (has invite permission)
	if _cm.player_has_permission(CorporationRank.PERM_INVITE):
		_applications = await _cm.fetch_applications()
		queue_redraw()


func _rebuild_table() -> void:
	if _cm == null:
		return

	var search_text =_search.get_text().to_lower()
	var filter_rank =_filter_dropdown.selected_index - 1

	_filtered_members.clear()
	for m in _cm.members:
		if search_text != "" and m.display_name.to_lower().find(search_text) == -1:
			continue
		if filter_rank >= 0 and m.rank_index != filter_rank:
			continue
		_filtered_members.append(m)

	if _table.sort_column >= 0:
		_sort_members(_table.sort_column, _table.sort_ascending)

	_table.rows.clear()
	for m in _filtered_members:
		var rank_name: String = _cm.corporation_data.ranks[m.rank_index].rank_name if m.rank_index < _cm.corporation_data.ranks.size() else "?"
		var status: String = Locale.t("corp.status_online") if m.is_online else Locale.t("corp.status_offline")
		var contrib_str =_format_num(m.contribution_total)
		var vu =_format_last_seen(m)
		_table.rows.append([m.display_name, rank_name, status, contrib_str, str(m.kills), vu])

	_table.selected_row = -1
	_table.queue_redraw()


func _sort_members(col: int, ascending: bool) -> void:
	_filtered_members.sort_custom(func(a: CorporationMember, b: CorporationMember) -> bool:
		var va: Variant
		var vb: Variant
		match col:
			0: va = a.display_name.to_lower(); vb = b.display_name.to_lower()
			1: va = a.rank_index; vb = b.rank_index
			2: va = 0 if a.is_online else 1; vb = 0 if b.is_online else 1
			3: va = a.contribution_total; vb = b.contribution_total
			4: va = a.kills; vb = b.kills
			5: va = a.last_online_timestamp; vb = b.last_online_timestamp
			_: return false
		if ascending:
			return va < vb
		return va > vb
	)


func _on_search_changed(_text: String) -> void:
	_rebuild_table()

func _on_filter_changed(_index: int) -> void:
	_rebuild_table()

func _on_sort_requested(_col: int) -> void:
	_rebuild_table()


func _on_row_selected(index: int) -> void:
	if index < 0 or index >= _filtered_members.size():
		_selected_member = null
		_btn_promote.visible = false
		_btn_demote.visible = false
		_btn_kick.visible = false
		return

	_selected_member = _filtered_members[index]
	var is_self: bool = (_selected_member == _cm.player_member)
	var can_act: bool = not is_self and _cm.player_member != null and _selected_member.rank_index > _cm.player_member.rank_index

	_btn_promote.visible = can_act and _cm.player_has_permission(CorporationRank.PERM_PROMOTE) and _selected_member.rank_index > 1
	_btn_demote.visible = can_act and _cm.player_has_permission(CorporationRank.PERM_DEMOTE) and _selected_member.rank_index < _cm.corporation_data.ranks.size() - 1
	_btn_kick.visible = can_act and _cm.player_has_permission(CorporationRank.PERM_KICK)


func _on_promote() -> void:
	if _selected_member and _cm:
		_cm.promote_member(_selected_member.player_id)
		_rebuild_table()
		_hide_actions()

func _on_demote() -> void:
	if _selected_member and _cm:
		_cm.demote_member(_selected_member.player_id)
		_rebuild_table()
		_hide_actions()

func _on_kick() -> void:
	if _selected_member and _cm:
		_cm.kick_member(_selected_member.player_id)
		_selected_member = null
		_rebuild_table()
		_hide_actions()

func _hide_actions() -> void:
	_btn_promote.visible = false
	_btn_demote.visible = false
	_btn_kick.visible = false


func _format_last_seen(m: CorporationMember) -> String:
	if m.is_online:
		return Locale.t("corp.seen_now")
	if m.last_online_timestamp <= 0:
		return Locale.t("corp.seen_unknown")
	var now := int(Time.get_unix_time_from_system())
	var diff := now - m.last_online_timestamp
	if diff < 0:
		return Locale.t("corp.seen_now")
	if diff < 3600:
		return Locale.t("corp.seen_minutes") % int(diff / 60.0)
	if diff < 86400:
		return Locale.t("corp.seen_hours") % int(diff / 3600.0)
	if diff < 86400 * 365:
		return Locale.t("corp.seen_days") % int(diff / 86400.0)
	return Locale.t("corp.seen_long_ago")


func _format_num(val: float) -> String:
	var i =int(val)
	var s =str(i)
	var result =""
	var count =0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[idx] + result
		count += 1
	return result


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	var m: float = 12.0

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position

		# Click on applications badge → toggle view
		if _applications.size() > 0 and _cm and _cm.player_has_permission(CorporationRank.PERM_INVITE):
			var badge_rect := Rect2(size.x - 200, m + 4, 190, 24)
			if badge_rect.has_point(pos):
				_show_applications = not _show_applications
				_table.visible = not _show_applications
				_search.visible = not _show_applications
				_filter_dropdown.visible = not _show_applications
				_btn_promote.visible = false
				_btn_demote.visible = false
				_btn_kick.visible = false
				queue_redraw()
				accept_event()
				return

		# Click on accept/reject buttons in applications view
		if _show_applications:
			var panel_y: float = m + 42
			var hdr_y: float = panel_y + 30
			var start_y: float = hdr_y + 22
			var row_h: float = 60.0
			var col_actions_x: float = size.x - 140

			for i in _applications.size():
				var idx: int = i + _app_scroll_offset
				if idx >= _applications.size():
					break
				var ry: float = start_y + i * row_h

				# Accept button
				var accept_rect := Rect2(col_actions_x, ry + 5, 50, 22)
				if accept_rect.has_point(pos):
					_handle_application(idx, "accept")
					accept_event()
					return

				# Reject button
				var reject_rect := Rect2(col_actions_x + 58, ry + 5, 50, 22)
				if reject_rect.has_point(pos):
					_handle_application(idx, "reject")
					accept_event()
					return

	elif event is InputEventMouseMotion and _show_applications:
		var pos: Vector2 = event.position
		var panel_y: float = m + 42
		var hdr_y: float = panel_y + 30
		var start_y: float = hdr_y + 22
		var row_h: float = 60.0
		var old_hovered := _app_hovered_row
		var row_idx: int = int((pos.y - start_y) / row_h) + _app_scroll_offset
		if row_idx >= 0 and row_idx < _applications.size():
			_app_hovered_row = row_idx
		else:
			_app_hovered_row = -1
		if _app_hovered_row != old_hovered:
			queue_redraw()


func _handle_application(idx: int, action: String) -> void:
	if _processing_application:
		return
	if idx < 0 or idx >= _applications.size() or _cm == null:
		return
	var app: Dictionary = _applications[idx]
	var app_id: int = int(app.get("id", 0))
	if app_id == 0:
		return

	_processing_application = true
	var success: bool = false
	if action == "accept":
		success = await _cm.accept_application(app_id)
	else:
		success = await _cm.reject_application(app_id)
	_processing_application = false

	if success:
		_applications.remove_at(idx)
		if _applications.is_empty():
			_show_applications = false
			_table.visible = true
			_search.visible = true
			_filter_dropdown.visible = true
		# Refresh members list if we accepted someone
		if action == "accept" and _cm.has_corporation():
			_cm.refresh_from_backend()
		queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0

	# Search & filter bar (hidden in applications mode)
	_search.position = Vector2(m, m)
	_search.size = Vector2(size.x * 0.42, 30)
	_filter_dropdown.position = Vector2(size.x * 0.42 + m * 2, m)
	# Shrink filter dropdown when badge is visible to prevent overlap
	var has_badge: bool = _applications.size() > 0 and _cm != null and _cm.player_has_permission(CorporationRank.PERM_INVITE)
	var filter_w: float = size.x * 0.38
	if has_badge:
		var badge_start: float = size.x - 210
		var filter_end: float = _filter_dropdown.position.x + filter_w
		if filter_end > badge_start:
			filter_w = maxf(badge_start - _filter_dropdown.position.x, 100.0)
	if _filter_dropdown._expanded:
		_filter_dropdown.size.x = filter_w
	else:
		_filter_dropdown.size = Vector2(filter_w, 30)

	# Table (hidden in applications mode)
	_table.position = Vector2(0, m + 42)
	_table.size = Vector2(size.x, size.y - 98)

	# Bottom action bar
	var btn_y: float = size.y - 38
	_btn_promote.position = Vector2(m, btn_y)
	_btn_promote.size = Vector2(160, 30)
	_btn_demote.position = Vector2(m + 170, btn_y)
	_btn_demote.size = Vector2(160, 30)
	_btn_kick.position = Vector2(m + 340, btn_y)
	_btn_kick.size = Vector2(160, 30)


func _draw() -> void:
	var m: float = 12.0
	var font: Font = UITheme.get_font()

	# Search bar area background
	draw_rect(Rect2(0, 0, size.x, m + 38), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))
	draw_line(Vector2(0, m + 38), Vector2(size.x, m + 38), UITheme.BORDER, 1.0)

	# Applications badge in the search bar area (right side)
	if _applications.size() > 0 and _cm and _cm.player_has_permission(CorporationRank.PERM_INVITE):
		var badge_x: float = size.x - 200
		var badge_y: float = m + 4
		var badge_text: String = Locale.t("corp.applications_badge") % _applications.size() if not _show_applications else Locale.t("tab.members").to_upper()
		var badge_col: Color = UITheme.WARNING if not _show_applications else UITheme.PRIMARY
		var badge_rect := Rect2(badge_x, badge_y, 190, 24)
		draw_rect(badge_rect, Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		draw_rect(badge_rect, badge_col, false, 1.0)
		draw_string(font, Vector2(badge_x + 6, badge_y + 17), badge_text, HORIZONTAL_ALIGNMENT_CENTER, 178, UITheme.FONT_SIZE_SMALL, badge_col)

	# Draw applications panel if showing
	if _show_applications and _applications.size() > 0:
		_draw_applications_panel(m, font)
	else:
		# Bottom action bar background (members mode)
		if _btn_promote.visible or _btn_demote.visible or _btn_kick.visible:
			var bar_y: float = size.y - 44
			draw_line(Vector2(0, bar_y), Vector2(size.x, bar_y), UITheme.BORDER, 1.0)
			draw_rect(Rect2(0, bar_y, size.x, size.y - bar_y), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))

			if _selected_member:
				var info_str: String = Locale.t("corp.selected_member") % _selected_member.display_name
				draw_string(font, Vector2(size.x - 260, size.y - 16), info_str, HORIZONTAL_ALIGNMENT_RIGHT, 250, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


func _draw_applications_panel(m: float, font: Font) -> void:
	var panel_y: float = m + 42
	var panel_h: float = size.y - panel_y - 10
	var row_h: float = 60.0

	# Panel background
	draw_rect(Rect2(0, panel_y, size.x, panel_h), Color(0, 0, 0, 0.2))

	# Header
	draw_rect(Rect2(m, panel_y, size.x - m * 2, 28), Color(UITheme.WARNING.r, UITheme.WARNING.g, UITheme.WARNING.b, 0.1))
	draw_string(font, Vector2(m + 8, panel_y + 19), Locale.t("corp.applications_header"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, UITheme.WARNING)

	# Table headers
	var hdr_y: float = panel_y + 30
	var col_name_x: float = m + 8
	var col_note_x: float = m + 180
	var col_date_x: float = size.x - 260
	var col_actions_x: float = size.x - 140
	draw_string(font, Vector2(col_name_x, hdr_y + 14), Locale.t("corp.app_col_player"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(col_note_x, hdr_y + 14), Locale.t("corp.app_col_note"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(col_date_x, hdr_y + 14), Locale.t("corp.app_col_date"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_string(font, Vector2(col_actions_x, hdr_y + 14), Locale.t("corp.app_col_actions"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	draw_line(Vector2(m, hdr_y + 20), Vector2(size.x - m, hdr_y + 20), UITheme.BORDER, 1.0)

	# Rows
	var start_y: float = hdr_y + 22
	var visible_count: int = int((panel_h - 60) / row_h)
	for i in mini(_applications.size(), visible_count):
		var idx: int = i + _app_scroll_offset
		if idx >= _applications.size():
			break
		var app: Dictionary = _applications[idx]
		var ry: float = start_y + i * row_h

		# Row hover highlight
		if idx == _app_hovered_row:
			draw_rect(Rect2(m, ry, size.x - m * 2, row_h), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))

		# Separator
		if i > 0:
			draw_line(Vector2(m, ry), Vector2(size.x - m, ry), Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.3), 1.0)

		# Player name
		var pname: String = str(app.get("player_name", "???"))
		draw_string(font, Vector2(col_name_x, ry + 20), pname, HORIZONTAL_ALIGNMENT_LEFT, 160, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

		# Note (truncated)
		var note: String = str(app.get("note", ""))
		if note.length() > 60:
			note = note.substr(0, 57) + "..."
		if note == "":
			note = Locale.t("corp.app_no_note")
		var note_col: Color = UITheme.TEXT_DIM if app.get("note", "") == "" else UITheme.TEXT
		draw_string(font, Vector2(col_note_x, ry + 20), note, HORIZONTAL_ALIGNMENT_LEFT, col_date_x - col_note_x - 10, UITheme.FONT_SIZE_SMALL, note_col)

		# Date
		var date_str: String = _format_app_date(app)
		draw_string(font, Vector2(col_date_x, ry + 20), date_str, HORIZONTAL_ALIGNMENT_LEFT, 110, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		# Accept button
		var accept_rect := Rect2(col_actions_x, ry + 5, 50, 22)
		draw_rect(accept_rect, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.2))
		draw_rect(accept_rect, UITheme.ACCENT, false, 1.0)
		draw_string(font, Vector2(col_actions_x + 4, ry + 21), Locale.t("corp.app_accept"), HORIZONTAL_ALIGNMENT_CENTER, 42, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)

		# Reject button
		var reject_rect := Rect2(col_actions_x + 58, ry + 5, 50, 22)
		draw_rect(reject_rect, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.2))
		draw_rect(reject_rect, UITheme.DANGER, false, 1.0)
		draw_string(font, Vector2(col_actions_x + 62, ry + 21), Locale.t("corp.app_reject"), HORIZONTAL_ALIGNMENT_CENTER, 42, UITheme.FONT_SIZE_SMALL, UITheme.DANGER)

	if _applications.is_empty():
		draw_string(font, Vector2(0, panel_y + panel_h * 0.4), Locale.t("corp.app_none"), HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


func _format_app_date(app: Dictionary) -> String:
	var created: String = str(app.get("created_at", ""))
	if created == "" or created == "null":
		return "?"
	# Parse ISO date roughly
	if "T" in created:
		var parts := created.split("T")
		if parts.size() >= 2:
			return parts[0]
	return created.substr(0, 10)
