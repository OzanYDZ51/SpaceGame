class_name ClanTabRanks
extends UIComponent

# =============================================================================
# Clan Tab: Ranks - Rank list (left) + permission editor (right)
# Rich panels with header bars and visual indicators
# =============================================================================

var _cm = null
var _rank_list: UIScrollList = null
var _perm_toggles: Array[UIToggleButton] = []
var _name_input: UITextInput = null
var _btn_save: UIButton = null
var _btn_add: UIButton = null
var _btn_remove: UIButton = null

var _selected_rank_index: int = -1
var _perm_bits: Array[int] = [
	ClanRank.PERM_INVITE, ClanRank.PERM_KICK, ClanRank.PERM_PROMOTE, ClanRank.PERM_DEMOTE,
	ClanRank.PERM_EDIT_MOTD, ClanRank.PERM_WITHDRAW, ClanRank.PERM_DIPLOMACY, ClanRank.PERM_MANAGE_RANKS,
]

const LEFT_W =270.0
const GAP =16.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_rank_list = UIScrollList.new()
	_rank_list.row_height = 36.0
	_rank_list.item_draw_callback = _draw_rank_item
	_rank_list.item_selected.connect(_on_rank_selected)
	add_child(_rank_list)

	for bit in _perm_bits:
		var toggle =UIToggleButton.new()
		toggle.text = ClanRank.PERM_NAMES.get(bit, "???")
		toggle.visible = false
		add_child(toggle)
		_perm_toggles.append(toggle)

	_name_input = UITextInput.new()
	_name_input.placeholder = "Nom du rang..."
	_name_input.visible = false
	add_child(_name_input)

	_btn_save = UIButton.new()
	_btn_save.text = "Sauvegarder les modifications"
	_btn_save.accent_color = UITheme.ACCENT
	_btn_save.pressed.connect(_on_save)
	_btn_save.visible = false
	add_child(_btn_save)

	_btn_add = UIButton.new()
	_btn_add.text = "+ Ajouter un rang"
	_btn_add.pressed.connect(_on_add_rank)
	add_child(_btn_add)

	_btn_remove = UIButton.new()
	_btn_remove.text = "- Supprimer ce rang"
	_btn_remove.accent_color = UITheme.DANGER
	_btn_remove.pressed.connect(_on_remove_rank)
	_btn_remove.visible = false
	add_child(_btn_remove)


func refresh(cm) -> void:
	_cm = cm
	_selected_rank_index = -1
	_hide_editor()

	if _cm == null or not _cm.has_clan():
		return

	_rank_list.items.clear()
	for i in _cm.clan_data.ranks.size():
		_rank_list.items.append(i)
	_rank_list.selected_index = -1
	_rank_list.queue_redraw()

	var can_manage: bool = _cm.player_has_permission(ClanRank.PERM_MANAGE_RANKS)
	_btn_add.visible = can_manage
	_btn_add.enabled = can_manage


func _draw_rank_item(ctrl: Control, _index: int, rect: Rect2, item: Variant) -> void:
	var font: Font = UITheme.get_font()
	var rank_idx: int = item as int
	if _cm == null or rank_idx >= _cm.clan_data.ranks.size():
		return
	var rank: ClanRank = _cm.clan_data.ranks[rank_idx]

	# Priority badge background
	var badge_rect =Rect2(rect.end.x - 36, rect.position.y + 6, 28, rect.size.y - 12)
	var badge_col =UITheme.PRIMARY if rank_idx == 0 else UITheme.PRIMARY_DIM
	ctrl.draw_rect(badge_rect, Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
	ctrl.draw_rect(badge_rect, Color(badge_col.r, badge_col.g, badge_col.b, 0.3), false, 1.0)
	ctrl.draw_string(font, Vector2(badge_rect.position.x + 2, rect.position.y + rect.size.y - 8), str(rank.priority), HORIZONTAL_ALIGNMENT_CENTER, 24, UITheme.FONT_SIZE_BODY, badge_col)

	# Rank name
	var name_col =UITheme.TEXT_HEADER if rank_idx == 0 else UITheme.TEXT
	ctrl.draw_string(font, Vector2(rect.position.x + 14, rect.position.y + rect.size.y - 10), rank.rank_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 54, UITheme.FONT_SIZE_BODY, name_col)

	# Leader indicator
	if rank_idx == 0:
		ctrl.draw_rect(Rect2(rect.position.x + 2, rect.position.y + 4, 3, rect.size.y - 8), UITheme.ACCENT)


func _on_rank_selected(index: int) -> void:
	if _cm == null or index < 0 or index >= _cm.clan_data.ranks.size():
		_hide_editor()
		return

	_selected_rank_index = index
	var rank: ClanRank = _cm.clan_data.ranks[index]

	_name_input.visible = true
	_name_input.set_text(rank.rank_name)
	_btn_save.visible = true

	var is_leader =(index == 0)
	var can_manage: bool = _cm.player_has_permission(ClanRank.PERM_MANAGE_RANKS)
	var editable: bool = not is_leader and can_manage

	for i in _perm_toggles.size():
		var toggle =_perm_toggles[i]
		toggle.visible = true
		toggle.is_on = rank.has_permission(_perm_bits[i])
		toggle.enabled = editable
		toggle.queue_redraw()

	_name_input.enabled = editable
	_btn_save.enabled = editable
	_btn_remove.visible = editable and index > 0
	queue_redraw()


func _hide_editor() -> void:
	_name_input.visible = false
	_btn_save.visible = false
	_btn_remove.visible = false
	for toggle in _perm_toggles:
		toggle.visible = false
	queue_redraw()


func _on_save() -> void:
	if _cm == null or _selected_rank_index < 0:
		return
	var new_name =_name_input.get_text().strip_edges()
	if new_name == "":
		return
	var perms =0
	for i in _perm_toggles.size():
		if _perm_toggles[i].is_on:
			perms |= _perm_bits[i]
	_cm.update_rank(_selected_rank_index, new_name, perms)
	refresh(_cm)


func _on_add_rank() -> void:
	if _cm == null:
		return
	_cm.add_rank("Nouveau rang", 0)
	refresh(_cm)


func _on_remove_rank() -> void:
	if _cm == null or _selected_rank_index <= 0:
		return
	_cm.remove_rank(_selected_rank_index)
	refresh(_cm)


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0
	var rx: float = LEFT_W + GAP
	var rw: float = size.x - rx

	# Left list
	_rank_list.position = Vector2(0, 0)
	_rank_list.size = Vector2(LEFT_W, size.y - 48)

	_btn_add.position = Vector2(m, size.y - 38)
	_btn_add.size = Vector2(120, 30)
	_btn_remove.position = Vector2(m + 130, size.y - 38)
	_btn_remove.size = Vector2(120, 30)

	# Right editor
	var ty: float = 36.0
	for toggle in _perm_toggles:
		if not toggle.visible:
			continue
		toggle.position = Vector2(rx + m, ty)
		toggle.size = Vector2(rw - m * 2, 28)
		ty += 34.0

	ty += 24
	_name_input.position = Vector2(rx + m, ty)
	_name_input.size = Vector2(rw - m * 2, 30)

	_btn_save.position = Vector2(rx + m, ty + 44)
	_btn_save.size = Vector2(rw - m * 2, 32)


func _draw() -> void:
	if _cm == null or not _cm.has_clan():
		return

	var font: Font = UITheme.get_font()
	var m: float = 12.0
	var rx: float = LEFT_W + GAP
	var rw: float = size.x - rx

	# Left panel
	draw_panel_bg(Rect2(0, 0, LEFT_W, size.y - 48))

	# Right panel
	if _selected_rank_index >= 0:
		draw_panel_bg(Rect2(rx, 0, rw, size.y - 48))

		var rank: ClanRank = _cm.clan_data.ranks[_selected_rank_index]
		var header: String = "RANG: %s" % rank.rank_name.to_upper()
		if _selected_rank_index == 0:
			header += " (CHEF - NON MODIFIABLE)"

		# Header bar
		draw_rect(Rect2(rx, 0, rw, 28), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
		draw_rect(Rect2(rx, 0, 3, 28), UITheme.PRIMARY)
		draw_string(font, Vector2(rx + m + 4, 18), header, HORIZONTAL_ALIGNMENT_LEFT, rw - m * 2, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)
		draw_line(Vector2(rx, 28), Vector2(rx + rw, 28), UITheme.BORDER, 1.0)

		# "NOM DU RANG" label above name input
		if _name_input.visible:
			draw_string(font, Vector2(rx + m + 4, _name_input.position.y - 16 + UITheme.FONT_SIZE_TINY), "NOM DU RANG", HORIZONTAL_ALIGNMENT_LEFT, rw - m * 2, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

		# Permission count
		var perm_count =0
		for toggle in _perm_toggles:
			if toggle.is_on:
				perm_count += 1
		var perm_str ="%d / 8 permissions actives" % perm_count
		draw_string(font, Vector2(rx + rw - 200, 18), perm_str, HORIZONTAL_ALIGNMENT_RIGHT, 190, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	else:
		# Empty state
		draw_panel_bg(Rect2(rx, 0, rw, size.y - 48))
		draw_string(font, Vector2(rx, size.y * 0.4), "Selectionnez un rang", HORIZONTAL_ALIGNMENT_CENTER, rw, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
		draw_string(font, Vector2(rx, size.y * 0.4 + 24), "pour modifier ses permissions", HORIZONTAL_ALIGNMENT_CENTER, rw, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# Bottom separator
	draw_line(Vector2(0, size.y - 48), Vector2(size.x, size.y - 48), UITheme.BORDER, 1.0)
