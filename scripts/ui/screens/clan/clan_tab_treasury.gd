class_name ClanTabTreasury
extends UIComponent

# =============================================================================
# Clan Tab: Treasury - Rich balance display, deposit/withdraw, history, top 5
# =============================================================================

var _cm = null
var _input_deposit: UITextInput = null
var _input_withdraw: UITextInput = null
var _btn_deposit: UIButton = null
var _btn_withdraw: UIButton = null
var _history_table: UIDataTable = null


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_input_deposit = UITextInput.new()
	_input_deposit.placeholder = "Montant a deposer..."
	add_child(_input_deposit)

	_btn_deposit = UIButton.new()
	_btn_deposit.text = "Deposer"
	_btn_deposit.accent_color = UITheme.ACCENT
	_btn_deposit.pressed.connect(_on_deposit)
	add_child(_btn_deposit)

	_input_withdraw = UITextInput.new()
	_input_withdraw.placeholder = "Montant a retirer..."
	add_child(_input_withdraw)

	_btn_withdraw = UIButton.new()
	_btn_withdraw.text = "Retirer"
	_btn_withdraw.accent_color = UITheme.WARNING
	_btn_withdraw.pressed.connect(_on_withdraw)
	add_child(_btn_withdraw)

	_history_table = UIDataTable.new()
	_history_table._row_height = 22.0
	_history_table.columns = [
		{ "label": "Date", "width_ratio": 0.25 },
		{ "label": "Type", "width_ratio": 0.18 },
		{ "label": "Montant", "width_ratio": 0.27 },
		{ "label": "Membre", "width_ratio": 0.30 },
	]
	add_child(_history_table)


func refresh(cm) -> void:
	_cm = cm
	if _cm == null or not _cm.has_clan():
		return

	_btn_withdraw.enabled = _cm.player_has_permission(ClanRank.PERM_WITHDRAW)

	_history_table.rows.clear()
	for t in _cm.transactions:
		var ts: int = t.get("timestamp", 0)
		var date_str =_format_timestamp(ts)
		var type_str: String = t.get("type", "?")
		var amount: float = t.get("amount", 0.0)
		var amount_str: String = ("+%s" if amount > 0 else "%s") % _format_num(amount)
		var actor: String = t.get("actor", "?")
		_history_table.rows.append([date_str, type_str, amount_str, actor])
	_history_table.queue_redraw()
	queue_redraw()


func _on_deposit() -> void:
	if _cm == null:
		return
	var amount =float(_input_deposit.get_text())
	if amount > 0:
		_cm.deposit_funds(amount)
		_input_deposit.set_text("")
		refresh(_cm)


func _on_withdraw() -> void:
	if _cm == null:
		return
	var amount =float(_input_withdraw.get_text())
	if amount > 0:
		_cm.withdraw_funds(amount)
		_input_withdraw.set_text("")
		refresh(_cm)


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0
	var action_y: float = 80.0

	# Deposit row
	_input_deposit.position = Vector2(m, action_y)
	_input_deposit.size = Vector2(180, 30)
	_btn_deposit.position = Vector2(m + 188, action_y)
	_btn_deposit.size = Vector2(110, 30)

	# Withdraw row
	var wx: float = m + 320
	_input_withdraw.position = Vector2(wx, action_y)
	_input_withdraw.size = Vector2(180, 30)
	_btn_withdraw.position = Vector2(wx + 188, action_y)
	_btn_withdraw.size = Vector2(110, 30)

	# History table (left 58%)
	var table_y: float = action_y + 52
	var table_w: float = size.x * 0.56
	_history_table.position = Vector2(0, table_y)
	_history_table.size = Vector2(table_w, size.y - table_y)


func _draw() -> void:
	if _cm == null or not _cm.has_clan():
		return

	var font: Font = UITheme.get_font()
	var m: float = 12.0
	var pulse: float = UITheme.get_pulse(0.5)

	# ─── Balance Header Area ────────────────────────────────────────────
	var header_rect =Rect2(0, 0, size.x, 68)
	draw_rect(header_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.03))
	draw_line(Vector2(0, 68), Vector2(size.x, 68), UITheme.BORDER, 1.0)

	# Title
	draw_rect(Rect2(m, 6, 3, UITheme.FONT_SIZE_HEADER + 2), UITheme.PRIMARY)
	draw_string(font, Vector2(m + 10, 6 + UITheme.FONT_SIZE_HEADER), "TRESORERIE DU CLAN", HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.4, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)

	# Big balance (centered, glowing)
	var balance = _cm.clan_data.treasury_balance
	var bal_str ="%s CREDITS" % _format_num(balance)
	var bal_col =UITheme.ACCENT if balance > 0 else UITheme.DANGER
	var glow_alpha: float = 0.8 + pulse * 0.2
	var bal_draw_col =Color(bal_col.r, bal_col.g, bal_col.b, glow_alpha)
	draw_string(font, Vector2(0, 52), bal_str, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_TITLE, bal_draw_col)

	# Decorative lines around balance
	var bal_w: float = font.get_string_size(bal_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TITLE).x
	var bcx: float = size.x * 0.5
	var bl_col =Color(bal_col.r, bal_col.g, bal_col.b, 0.2 + pulse * 0.1)
	draw_line(Vector2(bcx - bal_w * 0.5 - 40, 44), Vector2(bcx - bal_w * 0.5 - 6, 44), bl_col, 1.0)
	draw_line(Vector2(bcx + bal_w * 0.5 + 6, 44), Vector2(bcx + bal_w * 0.5 + 40, 44), bl_col, 1.0)

	# ─── Action bar background ──────────────────────────────────────────
	var action_y: float = 80.0
	draw_rect(Rect2(0, 68, size.x, 52), Color(0.0, 0.01, 0.03, 0.3))
	draw_line(Vector2(0, action_y + 44), Vector2(size.x, action_y + 44), UITheme.BORDER, 1.0)

	# Labels above inputs
	draw_string(font, Vector2(m, action_y - 14), "DEPOSER", HORIZONTAL_ALIGNMENT_LEFT, 180, UITheme.FONT_SIZE_BODY, UITheme.ACCENT)
	var wx: float = m + 320
	draw_string(font, Vector2(wx, action_y - 14), "RETIRER", HORIZONTAL_ALIGNMENT_LEFT, 180, UITheme.FONT_SIZE_BODY, UITheme.WARNING)

	# ─── Right Side: Top Contributors ───────────────────────────────────
	var table_y: float = action_y + 52
	var right_x: float = size.x * 0.58 + m
	var right_w: float = size.x - right_x - m

	draw_panel_bg(Rect2(right_x - m * 0.5, table_y, right_w + m, size.y - table_y))

	# Contributors header
	draw_rect(Rect2(right_x - m * 0.5, table_y, right_w + m, 28), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
	draw_rect(Rect2(right_x - m * 0.5, table_y, 3, 28), UITheme.ACCENT)
	draw_string(font, Vector2(right_x + 4, table_y + 18), "TOP CONTRIBUTEURS", HORIZONTAL_ALIGNMENT_LEFT, right_w, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)
	draw_line(Vector2(right_x - m * 0.5, table_y + 28), Vector2(right_x + right_w + m * 0.5, table_y + 28), UITheme.BORDER, 1.0)

	# Sort members by contribution
	var sorted_members: Array[ClanMember] = []
	for member in _cm.members:
		sorted_members.append(member)
	sorted_members.sort_custom(func(a: ClanMember, b: ClanMember) -> bool:
		return a.contribution_total > b.contribution_total
	)

	var max_contrib: float = sorted_members[0].contribution_total if sorted_members.size() > 0 else 1.0
	var count =mini(5, sorted_members.size())
	var cy: float = table_y + 38

	for i in count:
		var mem =sorted_members[i]
		var bar_ratio: float = mem.contribution_total / maxf(1.0, max_contrib)

		# Rank medal color
		var medal_col =UITheme.TEXT_DIM
		if i == 0: medal_col = Color(1.0, 0.85, 0.2)    # Gold
		elif i == 1: medal_col = Color(0.75, 0.75, 0.8)  # Silver
		elif i == 2: medal_col = Color(0.8, 0.5, 0.2)    # Bronze

		# Rank number
		draw_string(font, Vector2(right_x + 4, cy + UITheme.FONT_SIZE_BODY + 2), "#%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_BODY, medal_col)

		# Name
		draw_string(font, Vector2(right_x + 36, cy + UITheme.FONT_SIZE_BODY + 2), mem.display_name, HORIZONTAL_ALIGNMENT_LEFT, right_w * 0.5 - 8, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

		# Value
		draw_string(font, Vector2(right_x + 36, cy + UITheme.FONT_SIZE_BODY + 2), _format_num(mem.contribution_total), HORIZONTAL_ALIGNMENT_RIGHT, right_w - 44, UITheme.FONT_SIZE_BODY, UITheme.LABEL_VALUE)

		# Progress bar
		cy += 20
		var bar_w: float = (right_w - 16) * bar_ratio
		draw_rect(Rect2(right_x + 6, cy, right_w - 16, 6), UITheme.BG_DARK)
		var bar_col =medal_col if i < 3 else UITheme.PRIMARY
		draw_rect(Rect2(right_x + 6, cy, bar_w, 6), Color(bar_col.r, bar_col.g, bar_col.b, 0.4))
		if bar_w > 2:
			draw_rect(Rect2(right_x + 4 + bar_w, cy, 2, 6), Color(bar_col.r, bar_col.g, bar_col.b, 0.8))
		cy += 16

	# History panel border (left side)
	var table_w: float = size.x * 0.56
	draw_panel_bg(Rect2(0, table_y, table_w, size.y - table_y))


func _format_timestamp(ts: int) -> String:
	var dt =Time.get_datetime_dict_from_unix_time(ts)
	return "%02d/%02d %02d:%02d" % [dt.get("day", 0), dt.get("month", 0), dt.get("hour", 0), dt.get("minute", 0)]


func _format_num(val: float) -> String:
	var i =int(val)
	var negative =i < 0
	if negative:
		i = -i
	var s =str(i)
	var result =""
	var count =0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[idx] + result
		count += 1
	if negative:
		result = "-" + result
	return result
