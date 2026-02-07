class_name ClanTabMembers
extends UIComponent

# =============================================================================
# Clan Tab: Members - Searchable, sortable member list with actions
# Bigger row heights, richer drawing, colored status indicators
# =============================================================================

var _cm: ClanManager = null
var _search: UITextInput = null
var _filter_dropdown: UIDropdown = null
var _table: UIDataTable = null
var _btn_promote: UIButton = null
var _btn_demote: UIButton = null
var _btn_kick: UIButton = null

var _filtered_members: Array[ClanMember] = []
var _selected_member: ClanMember = null


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_search = UITextInput.new()
	_search.placeholder = "Rechercher un membre..."
	_search.text_changed.connect(_on_search_changed)
	add_child(_search)

	_filter_dropdown = UIDropdown.new()
	_filter_dropdown.options.assign(["Tous les rangs"])
	_filter_dropdown.option_selected.connect(_on_filter_changed)
	add_child(_filter_dropdown)

	_table = UIDataTable.new()
	_table._row_height = 24.0
	_table.columns = [
		{ "label": "Nom", "width_ratio": 0.22 },
		{ "label": "Rang", "width_ratio": 0.15 },
		{ "label": "Statut", "width_ratio": 0.10 },
		{ "label": "Contribution", "width_ratio": 0.18 },
		{ "label": "Kills", "width_ratio": 0.10 },
		{ "label": "Derniere connexion", "width_ratio": 0.25 },
	]
	_table.row_selected.connect(_on_row_selected)
	_table.column_sort_requested.connect(_on_sort_requested)
	add_child(_table)

	_btn_promote = UIButton.new()
	_btn_promote.text = "Promouvoir"
	_btn_promote.accent_color = UITheme.ACCENT
	_btn_promote.pressed.connect(_on_promote)
	_btn_promote.visible = false
	add_child(_btn_promote)

	_btn_demote = UIButton.new()
	_btn_demote.text = "Retrograder"
	_btn_demote.accent_color = UITheme.WARNING
	_btn_demote.pressed.connect(_on_demote)
	_btn_demote.visible = false
	add_child(_btn_demote)

	_btn_kick = UIButton.new()
	_btn_kick.text = "Expulser"
	_btn_kick.accent_color = UITheme.DANGER
	_btn_kick.pressed.connect(_on_kick)
	_btn_kick.visible = false
	add_child(_btn_kick)


func refresh(cm: ClanManager) -> void:
	_cm = cm
	_selected_member = null
	_btn_promote.visible = false
	_btn_demote.visible = false
	_btn_kick.visible = false

	if _cm == null or not _cm.has_clan():
		return

	var rank_names: Array[String] = ["Tous les rangs"]
	for r in _cm.clan_data.ranks:
		rank_names.append(r.rank_name)
	_filter_dropdown.options.assign(rank_names)
	_filter_dropdown.selected_index = 0
	_filter_dropdown.queue_redraw()
	_rebuild_table()


func _rebuild_table() -> void:
	if _cm == null:
		return

	var search_text := _search.get_text().to_lower()
	var filter_rank := _filter_dropdown.selected_index - 1

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
		var rank_name: String = _cm.clan_data.ranks[m.rank_index].rank_name if m.rank_index < _cm.clan_data.ranks.size() else "?"
		var status: String = "EN LIGNE" if m.is_online else "HORS LIGNE"
		var contrib_str := _format_num(m.contribution_total)
		var vu := _format_last_seen(m)
		_table.rows.append([m.display_name, rank_name, status, contrib_str, str(m.kills), vu])

	_table.selected_row = -1
	_table.queue_redraw()


func _sort_members(col: int, ascending: bool) -> void:
	_filtered_members.sort_custom(func(a: ClanMember, b: ClanMember) -> bool:
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

	_btn_promote.visible = can_act and _cm.player_has_permission(ClanRank.PERM_PROMOTE) and _selected_member.rank_index > 1
	_btn_demote.visible = can_act and _cm.player_has_permission(ClanRank.PERM_DEMOTE) and _selected_member.rank_index < _cm.clan_data.ranks.size() - 1
	_btn_kick.visible = can_act and _cm.player_has_permission(ClanRank.PERM_KICK)


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


func _format_last_seen(m: ClanMember) -> String:
	if m.is_online:
		return "Maintenant"
	var now := int(Time.get_unix_time_from_system())
	var diff := now - m.last_online_timestamp
	if diff < 3600:
		return "Il y a %d min" % int(diff / 60.0)
	if diff < 86400:
		return "Il y a %d h" % int(diff / 3600.0)
	return "Il y a %d j" % int(diff / 86400.0)


func _format_num(val: float) -> String:
	var i := int(val)
	var s := str(i)
	var result := ""
	var count := 0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[idx] + result
		count += 1
	return result


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0

	# Search & filter bar
	_search.position = Vector2(m, m)
	_search.size = Vector2(size.x * 0.42, 30)
	_filter_dropdown.position = Vector2(size.x * 0.42 + m * 2, m)
	_filter_dropdown.size = Vector2(size.x * 0.38, 30)

	# Table
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

	# Search bar area background
	draw_rect(Rect2(0, 0, size.x, m + 38), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))
	draw_line(Vector2(0, m + 38), Vector2(size.x, m + 38), UITheme.BORDER, 1.0)

	# Bottom action bar background
	if _btn_promote.visible or _btn_demote.visible or _btn_kick.visible:
		var bar_y: float = size.y - 44
		draw_line(Vector2(0, bar_y), Vector2(size.x, bar_y), UITheme.BORDER, 1.0)
		draw_rect(Rect2(0, bar_y, size.x, size.y - bar_y), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))

		# Selected member info
		if _selected_member:
			var font: Font = UITheme.get_font()
			var info_str := "Selectionne: %s" % _selected_member.display_name
			draw_string(font, Vector2(size.x - 260, size.y - 16), info_str, HORIZONTAL_ALIGNMENT_RIGHT, 250, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
