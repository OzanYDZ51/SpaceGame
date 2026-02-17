class_name ClanTabProperties
extends UIComponent

# =============================================================================
# Clan Tab: Properties - Clan-owned stations, treasury, and territory
# Replaces the old Treasury tab with a broader assets view
# =============================================================================

var _cm = null
var _input_deposit: UITextInput = null
var _input_withdraw: UITextInput = null
var _btn_deposit: UIButton = null
var _btn_withdraw: UIButton = null

const GAP := 16.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_input_deposit = UITextInput.new()
	_input_deposit.placeholder = "Montant..."
	add_child(_input_deposit)

	_btn_deposit = UIButton.new()
	_btn_deposit.text = "Deposer"
	_btn_deposit.accent_color = UITheme.ACCENT
	_btn_deposit.pressed.connect(_on_deposit)
	add_child(_btn_deposit)

	_input_withdraw = UITextInput.new()
	_input_withdraw.placeholder = "Montant..."
	add_child(_input_withdraw)

	_btn_withdraw = UIButton.new()
	_btn_withdraw.text = "Retirer"
	_btn_withdraw.accent_color = UITheme.WARNING
	_btn_withdraw.pressed.connect(_on_withdraw)
	add_child(_btn_withdraw)


func refresh(cm) -> void:
	_cm = cm
	if _cm == null or not _cm.has_clan():
		return
	_btn_withdraw.enabled = _cm.player_has_permission(ClanRank.PERM_WITHDRAW)
	queue_redraw()


func _on_deposit() -> void:
	if _cm == null:
		return
	var amount := float(_input_deposit.get_text())
	if amount > 0:
		_cm.deposit_funds(amount)
		_input_deposit.set_text("")
		refresh(_cm)


func _on_withdraw() -> void:
	if _cm == null:
		return
	var amount := float(_input_withdraw.get_text())
	if amount > 0:
		_cm.withdraw_funds(amount)
		_input_withdraw.set_text("")
		refresh(_cm)


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0
	var treasury_y: float = 80.0

	# Treasury inputs
	_input_deposit.position = Vector2(m, treasury_y)
	_input_deposit.size = Vector2(150, 30)
	_btn_deposit.position = Vector2(m + 158, treasury_y)
	_btn_deposit.size = Vector2(100, 30)

	var wx: float = m + 280
	_input_withdraw.position = Vector2(wx, treasury_y)
	_input_withdraw.size = Vector2(150, 30)
	_btn_withdraw.position = Vector2(wx + 158, treasury_y)
	_btn_withdraw.size = Vector2(100, 30)


func _draw() -> void:
	if _cm == null or not _cm.has_clan():
		return

	var font: Font = UITheme.get_font()
	var m: float = 12.0
	var pulse: float = UITheme.get_pulse(0.5)
	var half_w: float = (size.x - GAP) * 0.5

	# ─── TRESORERIE section (top) ──────────────────────────────────────
	var treasury_rect := Rect2(0, 0, size.x, 126)
	draw_panel_bg(treasury_rect)

	# Header
	_draw_section_header(m, m, size.x - m * 2, "TRESORERIE")

	# Big balance
	var balance: float = _cm.clan_data.treasury_balance
	var bal_str := "%s CREDITS" % _format_num(balance)
	var bal_col: Color = UITheme.ACCENT if balance > 0 else UITheme.TEXT_DIM
	var glow_alpha: float = 0.8 + pulse * 0.2
	draw_string(font, Vector2(0, 60), bal_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_TITLE, Color(bal_col.r, bal_col.g, bal_col.b, glow_alpha))

	# Decorative lines
	var bal_w: float = font.get_string_size(bal_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TITLE).x
	var bcx: float = size.x * 0.5
	var bl_col := Color(bal_col.r, bal_col.g, bal_col.b, 0.2 + pulse * 0.1)
	draw_line(Vector2(bcx - bal_w * 0.5 - 40, 52), Vector2(bcx - bal_w * 0.5 - 6, 52), bl_col, 1.0)
	draw_line(Vector2(bcx + bal_w * 0.5 + 6, 52), Vector2(bcx + bal_w * 0.5 + 40, 52), bl_col, 1.0)

	# Deposit/Withdraw labels
	draw_string(font, Vector2(m, 70), "DEPOSER", HORIZONTAL_ALIGNMENT_LEFT, 150, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)
	draw_string(font, Vector2(m + 280, 70), "RETIRER", HORIZONTAL_ALIGNMENT_LEFT, 150, UITheme.FONT_SIZE_SMALL, UITheme.WARNING)

	draw_line(Vector2(0, 126), Vector2(size.x, 126), UITheme.BORDER, 1.0)

	# ─── STATIONS section (left) ──────────────────────────────────────
	var content_y: float = 140.0
	var content_h: float = size.y - content_y

	var left_rect := Rect2(0, content_y, half_w, content_h)
	draw_panel_bg(left_rect)

	var _sy: float = _draw_section_header(m, content_y + m, half_w - m * 2, "STATIONS DU CLAN")

	# Station list or empty state
	# TODO: When station ownership is implemented, show owned stations here
	var empty_y: float = content_y + content_h * 0.35
	draw_string(font, Vector2(m, empty_y), "Aucune station acquise", HORIZONTAL_ALIGNMENT_CENTER, half_w - m * 2, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
	draw_string(font, Vector2(m, empty_y + 24), "Les stations capturees ou construites", HORIZONTAL_ALIGNMENT_CENTER, half_w - m * 2, UITheme.FONT_SIZE_BODY, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.6))
	draw_string(font, Vector2(m, empty_y + 42), "par le clan apparaitront ici", HORIZONTAL_ALIGNMENT_CENTER, half_w - m * 2, UITheme.FONT_SIZE_BODY, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.6))

	# Decorative station icon (simple geometric)
	var icon_cx: float = half_w * 0.5
	var icon_cy: float = content_y + content_h * 0.18
	var icon_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15)
	# Hexagon-ish shape
	draw_rect(Rect2(icon_cx - 20, icon_cy - 20, 40, 40), icon_col, false, 2.0)
	draw_rect(Rect2(icon_cx - 12, icon_cy - 12, 24, 24), icon_col, false, 1.0)
	draw_line(Vector2(icon_cx, icon_cy - 24), Vector2(icon_cx, icon_cy + 24), icon_col, 1.0)
	draw_line(Vector2(icon_cx - 24, icon_cy), Vector2(icon_cx + 24, icon_cy), icon_col, 1.0)

	# ─── TERRITOIRE section (right) ───────────────────────────────────
	var right_x: float = half_w + GAP
	var right_rect := Rect2(right_x, content_y, half_w, content_h)
	draw_panel_bg(right_rect)

	var ty: float = _draw_section_header(right_x + m, content_y + m, half_w - m * 2, "TERRITOIRE")

	# Territory stats from member data
	var member_count: int = _cm.members.size()
	var online_count: int = _cm.get_online_count()

	ty = _draw_kv_row(right_x + m, ty, half_w - m * 2, "Membres actifs", "%d / %d" % [online_count, member_count], UITheme.ACCENT)
	ty = _draw_kv_row(right_x + m, ty, half_w - m * 2, "Reputation", str(_cm.clan_data.reputation_score), UITheme.PRIMARY)
	ty = _draw_kv_row(right_x + m, ty, half_w - m * 2, "Recrutement", "OUVERT" if _cm.clan_data.is_recruiting else "FERME", UITheme.ACCENT if _cm.clan_data.is_recruiting else UITheme.DANGER)

	ty += 8
	draw_line(Vector2(right_x + m, ty), Vector2(right_x + half_w - m, ty), UITheme.BORDER, 1.0)
	ty += 12

	# Top contributors (moved from old treasury tab)
	_draw_section_header(right_x + m, ty, half_w - m * 2, "TOP CONTRIBUTEURS")
	ty += 30

	var sorted_members: Array[ClanMember] = []
	for member in _cm.members:
		sorted_members.append(member)
	sorted_members.sort_custom(func(a: ClanMember, b: ClanMember) -> bool:
		return a.contribution_total > b.contribution_total
	)

	var max_contrib: float = sorted_members[0].contribution_total if sorted_members.size() > 0 else 1.0
	var count: int = mini(5, sorted_members.size())

	for i in count:
		var mem: ClanMember = sorted_members[i]
		var bar_ratio: float = mem.contribution_total / maxf(1.0, max_contrib)

		# Medal color
		var medal_col: Color = UITheme.TEXT_DIM
		if i == 0: medal_col = Color(1.0, 0.85, 0.2)
		elif i == 1: medal_col = Color(0.75, 0.75, 0.8)
		elif i == 2: medal_col = Color(0.8, 0.5, 0.2)

		# Rank number + name + value
		draw_string(font, Vector2(right_x + m + 4, ty + UITheme.FONT_SIZE_BODY + 2), "#%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_BODY, medal_col)
		draw_string(font, Vector2(right_x + m + 36, ty + UITheme.FONT_SIZE_BODY + 2), mem.display_name, HORIZONTAL_ALIGNMENT_LEFT, half_w * 0.5 - 8, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		draw_string(font, Vector2(right_x + m + 36, ty + UITheme.FONT_SIZE_BODY + 2), _format_num(mem.contribution_total), HORIZONTAL_ALIGNMENT_RIGHT, half_w - m * 2 - 44, UITheme.FONT_SIZE_BODY, UITheme.LABEL_VALUE)

		# Progress bar
		ty += 20
		var bar_w: float = (half_w - m * 2 - 16) * bar_ratio
		draw_rect(Rect2(right_x + m + 6, ty, half_w - m * 2 - 16, 5), UITheme.BG_DARK)
		var bar_col: Color = medal_col if i < 3 else UITheme.PRIMARY
		draw_rect(Rect2(right_x + m + 6, ty, bar_w, 5), Color(bar_col.r, bar_col.g, bar_col.b, 0.4))
		if bar_w > 2:
			draw_rect(Rect2(right_x + m + 4 + bar_w, ty, 2, 5), Color(bar_col.r, bar_col.g, bar_col.b, 0.8))
		ty += 14


# =============================================================================
# DRAW HELPERS
# =============================================================================

func _draw_section_header(x: float, y: float, w: float, text: String) -> float:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_HEADER
	draw_rect(Rect2(x, y + 2, 3, fsize + 2), UITheme.PRIMARY)
	draw_string(font, Vector2(x + 10, y + fsize + 1), text, HORIZONTAL_ALIGNMENT_LEFT, w - 14, fsize, UITheme.TEXT_HEADER)
	var ly: float = y + fsize + 6
	draw_line(Vector2(x, ly), Vector2(x + w, ly), UITheme.PRIMARY_DIM, 1.0)
	return ly + 8


func _draw_kv_row(x: float, y: float, w: float, key: String, value: String, val_col: Color = UITheme.LABEL_VALUE) -> float:
	var font: Font = UITheme.get_font()
	var ty: float = y + UITheme.FONT_SIZE_BODY + 2
	draw_string(font, Vector2(x, ty), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.55, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	draw_string(font, Vector2(x, ty), value, HORIZONTAL_ALIGNMENT_RIGHT, w, UITheme.FONT_SIZE_BODY, val_col)
	return y + 22


func _format_num(val: float) -> String:
	var i := int(val)
	var negative := i < 0
	if negative:
		i = -i
	var s := str(i)
	var result := ""
	var count := 0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[idx] + result
		count += 1
	if negative:
		result = "-" + result
	return result
