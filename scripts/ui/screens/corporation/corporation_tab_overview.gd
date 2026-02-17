class_name CorporationTabOverview
extends UIComponent

# =============================================================================
# Corporation Tab: Overview - Rich holographic layout with emblem, stats, MOTD
# =============================================================================

var _cm = null
var _emblem: CorporationEmblem = null
var _btn_motd: UIButton = null
var _btn_leave: UIButton = null
var _btn_recruit: UIButton = null
var _leave_modal: UIModal = null
var _motd_input: UITextInput = null
var _btn_motd_save: UIButton = null
var _motd_editing: bool = false

const LEFT_W =300.0
const RIGHT_W =300.0
const GAP =16.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_emblem = CorporationEmblem.new()
	add_child(_emblem)

	_btn_motd = UIButton.new()
	_btn_motd.text = "Modifier MOTD"
	_btn_motd.pressed.connect(_on_motd_pressed)
	add_child(_btn_motd)

	_btn_leave = UIButton.new()
	_btn_leave.text = "Quitter la corporation"
	_btn_leave.accent_color = UITheme.DANGER
	_btn_leave.pressed.connect(_on_leave_pressed)
	add_child(_btn_leave)

	_btn_recruit = UIButton.new()
	_btn_recruit.text = "Recrutement: ---"
	_btn_recruit.pressed.connect(_on_recruit_pressed)
	add_child(_btn_recruit)

	# Leave confirmation modal
	_leave_modal = UIModal.new()
	_leave_modal.title = "Quitter la corporation"
	_leave_modal.body = "Voulez-vous vraiment quitter la corporation ?"
	_leave_modal.confirm_text = "QUITTER"
	_leave_modal.cancel_text = "ANNULER"
	_leave_modal.confirmed.connect(_on_leave_confirmed)
	add_child(_leave_modal)

	# MOTD editing
	_motd_input = UITextInput.new()
	_motd_input.placeholder = "Nouveau message du jour..."
	_motd_input.visible = false
	add_child(_motd_input)

	_btn_motd_save = UIButton.new()
	_btn_motd_save.text = "Sauvegarder"
	_btn_motd_save.visible = false
	_btn_motd_save.pressed.connect(_on_motd_save)
	add_child(_btn_motd_save)


func refresh(cm) -> void:
	_cm = cm
	if _cm == null or not _cm.has_corporation():
		return
	_emblem.corporation_color = _cm.corporation_data.corporation_color
	_emblem.emblem_id = _cm.corporation_data.emblem_id
	_btn_motd.visible = _cm.player_has_permission(CorporationRank.PERM_EDIT_MOTD)
	_btn_recruit.text = "Recrutement: %s" % ("OUVERT" if _cm.corporation_data.is_recruiting else "FERME")
	queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	var m: float = 12.0
	var right_x: float = size.x - RIGHT_W
	var bot =size.y - 48

	_emblem.position = Vector2((LEFT_W - 120) * 0.5, m + 8)
	_emblem.size = Vector2(120, 120)

	_btn_motd.position = Vector2(right_x + m, bot - 36)
	_btn_motd.size = Vector2(RIGHT_W - m * 2, 30)

	_btn_leave.position = Vector2(m, bot + 6)
	_btn_leave.size = Vector2(170, 30)
	_btn_recruit.position = Vector2(m + 180, bot + 6)
	_btn_recruit.size = Vector2(210, 30)

	# MOTD input (in right column, above motd save btn)
	if _motd_editing:
		_motd_input.position = Vector2(right_x + m, bot - 76)
		_motd_input.size = Vector2(RIGHT_W - m * 2, 30)
		_btn_motd_save.position = Vector2(right_x + m, bot - 36)
		_btn_motd_save.size = Vector2(RIGHT_W - m * 2, 30)


func _draw() -> void:
	if _cm == null or not _cm.has_corporation():
		var no_corporation_font: Font = UITheme.get_font()
		draw_string(no_corporation_font, Vector2(0, size.y * 0.5), "Aucune corporation", HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_TITLE, UITheme.TEXT_DIM)
		return

	var font: Font = UITheme.get_font()
	var m: float = 12.0
	var center_x: float = LEFT_W + GAP
	var center_w: float = size.x - LEFT_W - RIGHT_W - GAP * 2
	var right_x: float = size.x - RIGHT_W
	var bot: float = size.y - 48
	var cd = _cm.corporation_data
	var pulse: float = UITheme.get_pulse(0.5)

	# ─── LEFT COLUMN: Identity ──────────────────────────────────────────
	var left_rect =Rect2(0, 0, LEFT_W, bot - 8)
	draw_panel_bg(left_rect)

	# Corporation name (large) — pushed below emblem child (ends at y=140)
	var name_y: float = m + 156
	draw_string(font, Vector2(m, name_y), cd.corporation_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, LEFT_W - m * 2, UITheme.FONT_SIZE_TITLE, UITheme.TEXT_HEADER)

	# Tag with bracket decoration
	var tag_y: float = name_y + 24
	var tag_str ="[%s]" % cd.corporation_tag
	draw_string(font, Vector2(m, tag_y), tag_str, HORIZONTAL_ALIGNMENT_CENTER, LEFT_W - m * 2, UITheme.FONT_SIZE_HEADER, UITheme.PRIMARY)
	# Small accent lines around tag
	var tag_w: float = font.get_string_size(tag_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_HEADER).x
	var tag_cx: float = LEFT_W * 0.5
	var tag_line_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3)
	draw_line(Vector2(tag_cx - tag_w * 0.5 - 30, tag_y - 5), Vector2(tag_cx - tag_w * 0.5 - 4, tag_y - 5), tag_line_col, 1.0)
	draw_line(Vector2(tag_cx + tag_w * 0.5 + 4, tag_y - 5), Vector2(tag_cx + tag_w * 0.5 + 30, tag_y - 5), tag_line_col, 1.0)

	# Motto (italic feel)
	var motto_y: float = tag_y + 24
	draw_string(font, Vector2(m + 4, motto_y), "\"%s\"" % cd.motto, HORIZONTAL_ALIGNMENT_CENTER, LEFT_W - m * 2 - 8, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# ─── Description section ─────
	var desc_y =_draw_rich_header(m, motto_y + 24, LEFT_W - m * 2, "DESCRIPTION")
	var desc_lines =_wrap_text(cd.description, font, UITheme.FONT_SIZE_BODY, LEFT_W - m * 2 - 16)
	for line in desc_lines:
		draw_string(font, Vector2(m + 8, desc_y + UITheme.FONT_SIZE_BODY + 2), line, HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - m * 2 - 16, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		desc_y += 18

	# ─── CENTER COLUMN: Stats ───────────────────────────────────────────
	var center_rect =Rect2(center_x, 0, center_w, bot - 8)
	draw_panel_bg(center_rect)

	var sy =_draw_rich_header(center_x + m, m, center_w - m * 2, "STATISTIQUES DE LA CORPORATION")

	sy = _draw_stat_row(center_x + m, sy, center_w - m * 2, "Membres", "%d / %d" % [_cm.members.size(), cd.max_members], float(_cm.members.size()) / float(cd.max_members), UITheme.PRIMARY)
	sy = _draw_stat_row(center_x + m, sy, center_w - m * 2, "En ligne", str(_cm.get_online_count()), float(_cm.get_online_count()) / maxf(1.0, float(_cm.members.size())), UITheme.ACCENT)

	sy += 6
	draw_line(Vector2(center_x + m, sy), Vector2(center_x + center_w - m, sy), UITheme.BORDER, 1.0)
	sy += 10

	# Key-value pairs with bigger font
	sy = _draw_kv_big(center_x + m, sy, center_w - m * 2, "Tresorerie", "%s cr" % _format_num(cd.treasury_balance), UITheme.ACCENT)
	sy = _draw_kv_big(center_x + m, sy, center_w - m * 2, "Reputation", str(cd.reputation_score), UITheme.PRIMARY)

	# Combat stats
	sy += 6
	draw_line(Vector2(center_x + m, sy), Vector2(center_x + center_w - m, sy), UITheme.BORDER, 1.0)
	sy += 10
	sy = _draw_rich_header(center_x + m, sy, center_w - m * 2, "COMBAT")

	var total_k =0
	var total_d =0
	for member in _cm.members:
		total_k += member.kills
		total_d += member.deaths
	var avg_kd: float = float(total_k) / maxf(1.0, float(total_d))
	sy = _draw_kv_big(center_x + m, sy, center_w - m * 2, "K/D moyen", "%.1f" % avg_kd, UITheme.WARNING if avg_kd < 1.0 else UITheme.ACCENT)
	sy = _draw_kv_big(center_x + m, sy, center_w - m * 2, "Kills total", str(total_k), UITheme.TARGET)
	sy = _draw_kv_big(center_x + m, sy, center_w - m * 2, "Morts total", str(total_d), UITheme.DANGER)

	# ─── RIGHT COLUMN: MOTD ─────────────────────────────────────────────
	var right_rect =Rect2(right_x, 0, RIGHT_W, bot - 8)
	draw_panel_bg(right_rect)

	var motd_y =_draw_rich_header(right_x + m, m, RIGHT_W - m * 2, "MESSAGE DU JOUR")

	# MOTD background panel
	var motd_panel =Rect2(right_x + m - 2, motd_y, RIGHT_W - m * 2 + 4, bot - motd_y - 56)
	draw_rect(motd_panel, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03))
	draw_rect(motd_panel, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.3), false, 1.0)

	# MOTD text
	var motd_lines =_wrap_text(cd.motd, font, UITheme.FONT_SIZE_BODY, RIGHT_W - m * 2 - 16)
	var my: float = motd_y + 6
	for line in motd_lines:
		draw_string(font, Vector2(right_x + m + 6, my + UITheme.FONT_SIZE_BODY + 2), line, HORIZONTAL_ALIGNMENT_LEFT, RIGHT_W - m * 2 - 16, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		my += 18

	# ─── Bottom separator + buttons area ────────────────────────────────
	draw_line(Vector2(0, bot - 2), Vector2(size.x, bot - 2), UITheme.BORDER, 1.0)
	var glow =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06 + pulse * 0.04)
	draw_line(Vector2(0, bot - 1), Vector2(size.x, bot - 1), glow, 2.0)


# =============================================================================
# DRAW HELPERS
# =============================================================================

## Rich section header with accent bar, text, and double underline
func _draw_rich_header(x: float, y: float, w: float, text: String) -> float:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_HEADER

	# Accent bar
	draw_rect(Rect2(x, y + 2, 3, fsize + 2), UITheme.PRIMARY)

	# Header text
	draw_string(font, Vector2(x + 10, y + fsize + 1), text, HORIZONTAL_ALIGNMENT_LEFT, w - 14, fsize, UITheme.TEXT_HEADER)

	# Underline (bright + dim)
	var ly: float = y + fsize + 6
	draw_line(Vector2(x, ly), Vector2(x + w, ly), UITheme.PRIMARY_DIM, 1.0)
	draw_line(Vector2(x, ly + 2), Vector2(x + w * 0.4, ly + 2), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), 1.0)

	return ly + UITheme.MARGIN_SECTION + 4


## Stat row with label, value, and mini bar indicator
func _draw_stat_row(x: float, y: float, w: float, label: String, value: String, ratio: float, col: Color) -> float:
	var font: Font = UITheme.get_font()

	# Label
	draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_BODY + 2), label, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# Value
	draw_string(font, Vector2(x, y + UITheme.FONT_SIZE_BODY + 2), value, HORIZONTAL_ALIGNMENT_RIGHT, w, UITheme.FONT_SIZE_BODY, col)

	# Mini bar
	var bar_y: float = y + UITheme.FONT_SIZE_BODY + 8
	var bar_h: float = 4.0
	draw_rect(Rect2(x, bar_y, w, bar_h), UITheme.BG_DARK)
	var fill_w: float = w * clampf(ratio, 0.0, 1.0)
	if fill_w > 0:
		draw_rect(Rect2(x, bar_y, fill_w, bar_h), Color(col.r, col.g, col.b, 0.5))
		draw_rect(Rect2(x + fill_w - 2, bar_y, 2, bar_h), col)

	return bar_y + bar_h + 10


## Key/value with larger font and colored value
func _draw_kv_big(x: float, y: float, w: float, key: String, value: String, val_col: Color = UITheme.LABEL_VALUE) -> float:
	var font: Font = UITheme.get_font()
	var ty: float = y + UITheme.FONT_SIZE_BODY + 2
	draw_string(font, Vector2(x, ty), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.55, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	draw_string(font, Vector2(x, ty), value, HORIZONTAL_ALIGNMENT_RIGHT, w, UITheme.FONT_SIZE_BODY, val_col)
	return y + 22


func _wrap_text(text: String, font: Font, fsize: int, max_w: float) -> Array[String]:
	var lines: Array[String] = []
	var words =text.split(" ")
	var current =""
	for word in words:
		var test =(current + " " + word).strip_edges()
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w and current != "":
			lines.append(current)
			current = word
		else:
			current = test
	if current != "":
		lines.append(current)
	return lines


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


func _on_motd_pressed() -> void:
	if _cm == null:
		return
	_motd_editing = not _motd_editing
	_motd_input.visible = _motd_editing
	_btn_motd_save.visible = _motd_editing
	if _motd_editing:
		_motd_input.set_text(_cm.corporation_data.motd)
		_btn_motd.text = "Annuler"
	else:
		_btn_motd.text = "Modifier MOTD"


func _on_motd_save() -> void:
	if _cm == null:
		return
	var new_text: String = _motd_input.get_text().strip_edges()
	if new_text != "":
		_cm.set_motd(new_text)
	_motd_editing = false
	_motd_input.visible = false
	_btn_motd_save.visible = false
	_btn_motd.text = "Modifier MOTD"
	queue_redraw()


func _on_leave_pressed() -> void:
	if _cm == null or not _cm.has_corporation():
		return
	if _cm.members.size() <= 1:
		_leave_modal.body = "Vous etes le dernier membre.\nLa corporation sera dissoute definitivement."
	else:
		_leave_modal.body = "Voulez-vous vraiment quitter la corporation ?"
	_leave_modal.show_modal()


func _on_leave_confirmed() -> void:
	if _cm:
		var success: bool = await _cm.leave_corporation()
		if not success:
			var notif = GameManager.get_node_or_null("NotificationService")
			if notif:
				notif.toast("Erreur: impossible de quitter la corporation", UIToast.ToastType.ERROR)


func _on_recruit_pressed() -> void:
	if _cm:
		_cm.toggle_recruitment()
		_btn_recruit.text = "Recrutement: %s" % ("OUVERT" if _cm.corporation_data.is_recruiting else "FERME")
		queue_redraw()
