class_name MissionCardDrawer
extends RefCounted

# =============================================================================
# Mission Card Drawer - Extracted draw helpers for mission board cards.
# Keeps MissionBoardScreen under 300 lines by handling card rendering here.
# =============================================================================

const CARD_BORDER_LEFT: float = 4.0
const BUTTON_W: float = 120.0
const BUTTON_H: float = 28.0


## Draw a full mission card including title, description, rewards, and action button.
static func draw_card(
		canvas: CanvasItem,
		rect: Rect2,
		mission: MissionData,
		is_hovered: bool,
		flash_v: float,
		show_progress: bool,
		btn_hovered: bool,
		is_accept_tab: bool,
		mission_manager
) -> void:
	var font: Font = UITheme.get_font()
	var accent: Color = danger_color(mission.danger_level)

	# Background
	var bg: Color = Color(0.015, 0.04, 0.08, 0.82) if not is_hovered else Color(0.025, 0.06, 0.12, 0.9)
	canvas.draw_rect(rect, bg)

	# Flash
	if flash_v > 0.0:
		canvas.draw_rect(rect, Color(1, 1, 1, flash_v * 0.15))

	# Border
	var bcol: Color = UITheme.BORDER_ACTIVE if is_hovered else UITheme.BORDER
	canvas.draw_rect(rect, bcol, false, 1.0)

	# Left accent bar
	canvas.draw_rect(Rect2(rect.position.x, rect.position.y + 2, CARD_BORDER_LEFT, rect.size.y - 4), accent)

	# Top glow
	var ga: float = 0.2 if is_hovered else 0.08
	canvas.draw_line(Vector2(rect.position.x + 1, rect.position.y),
		Vector2(rect.end.x - 1, rect.position.y),
		Color(accent.r, accent.g, accent.b, ga), 2.0)

	# Corner accents
	_draw_corners(canvas, rect, 8.0, bcol)

	# Content offset (after left bar)
	var cx: float = rect.position.x + CARD_BORDER_LEFT + 12.0
	var cw: float = rect.size.x - CARD_BORDER_LEFT - 12.0 - BUTTON_W - 30.0

	# Title
	var title_y: float = rect.position.y + 22.0
	canvas.draw_string(font, Vector2(cx, title_y), mission.title.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, cw, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)

	# Danger badge
	var title_w: float = font.get_string_size(mission.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, cw, UITheme.FONT_SIZE_HEADER).x
	var badge_x: float = cx + title_w + 8.0
	_draw_danger_badge(canvas, Vector2(badge_x, title_y - 12.0), mission.danger_level, accent)

	# Description
	var desc_y: float = title_y + 18.0
	canvas.draw_string(font, Vector2(cx, desc_y), mission.description,
		HORIZONTAL_ALIGNMENT_LEFT, cw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Progress (active tab only)
	if show_progress:
		_draw_progress(canvas, cx, desc_y + 18.0, cw, mission)

	# Reward line
	var reward_y: float = rect.end.y - 14.0
	_draw_rewards(canvas, cx, reward_y, cw, mission, show_progress)

	# Action button
	var btn_r: Rect2 = get_button_rect(rect)
	_draw_action_button(canvas, btn_r, btn_hovered, mission, is_accept_tab, mission_manager)


## Returns the action button rect within a card.
static func get_button_rect(card_rect: Rect2) -> Rect2:
	var bx: float = card_rect.end.x - BUTTON_W - 16.0
	var by: float = card_rect.end.y - BUTTON_H - 12.0
	return Rect2(bx, by, BUTTON_W, BUTTON_H)


static func _draw_progress(canvas: CanvasItem, cx: float, prog_y: float, cw: float, mission: MissionData) -> void:
	var font: Font = UITheme.get_font()
	var progress_text: String = mission.get_progress_text()
	var prog_col: Color = UITheme.ACCENT if mission.is_completed else UITheme.PRIMARY
	canvas.draw_string(font, Vector2(cx, prog_y), progress_text,
		HORIZONTAL_ALIGNMENT_LEFT, cw, UITheme.FONT_SIZE_SMALL, prog_col)

	# Progress bar
	if not mission.objectives.is_empty():
		var obj: Dictionary = mission.objectives[0]
		var current: int = obj.get("current", 0)
		var total: int = obj.get("count", 1)
		var ratio: float = float(current) / float(total) if total > 0 else 0.0
		var bar_rect := Rect2(cx, prog_y + 4.0, cw * 0.4, 6.0)
		canvas.draw_rect(bar_rect, UITheme.BG_DARK)
		if ratio > 0.0:
			canvas.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(ratio, 0.0, 1.0), bar_rect.size.y)), UITheme.ACCENT)
		canvas.draw_rect(bar_rect, UITheme.BORDER, false, 1.0)


static func _draw_rewards(canvas: CanvasItem, cx: float, reward_y: float, cw: float, mission: MissionData, show_time: bool) -> void:
	var font: Font = UITheme.get_font()

	# Credits
	var reward_text: String = "%s CR" % PlayerEconomy.format_credits(mission.reward_credits)
	canvas.draw_string(font, Vector2(cx, reward_y), reward_text,
		HORIZONTAL_ALIGNMENT_LEFT, cw * 0.5, UITheme.FONT_SIZE_BODY, PlayerEconomy.CREDITS_COLOR)

	# Reputation
	if mission.reward_reputation > 0.0:
		var rep_text: String = "+%.0f REP" % mission.reward_reputation
		canvas.draw_string(font, Vector2(cx + 140.0, reward_y), rep_text,
			HORIZONTAL_ALIGNMENT_LEFT, 100.0, UITheme.FONT_SIZE_SMALL, UITheme.ACCENT)

	# Timer (if timed + active tab)
	if mission.time_limit > 0.0 and show_time:
		var time_text: String = format_time(mission.time_remaining)
		var time_col: Color = UITheme.WARNING if mission.time_remaining > 60.0 else UITheme.DANGER
		canvas.draw_string(font, Vector2(cx + 260.0, reward_y), time_text,
			HORIZONTAL_ALIGNMENT_LEFT, 80.0, UITheme.FONT_SIZE_SMALL, time_col)


static func _draw_action_button(canvas: CanvasItem, rect: Rect2, hovered: bool, mission: MissionData, is_accept: bool, mission_manager) -> void:
	var font: Font = UITheme.get_font()
	var label: String
	var accent: Color

	if is_accept:
		var is_full: bool = mission_manager and mission_manager.get_active_count() >= MissionManager.MAX_ACTIVE
		var already: bool = mission_manager and mission_manager.has_mission(mission.mission_id)
		if already:
			label = "ACCEPTEE"
			accent = UITheme.TEXT_DIM
		elif is_full:
			label = "LIMITE"
			accent = UITheme.TEXT_DIM
		else:
			label = "ACCEPTER"
			accent = UITheme.ACCENT
	else:
		label = "ABANDONNER"
		accent = UITheme.DANGER

	# Background
	var bg_a: float = 0.18 if hovered else 0.08
	canvas.draw_rect(rect, Color(accent.r, accent.g, accent.b, bg_a))

	# Border
	var bc: Color = accent if hovered else Color(accent.r, accent.g, accent.b, 0.5)
	canvas.draw_rect(rect, bc, false, 1.0)

	# Left accent bar
	canvas.draw_rect(Rect2(rect.position.x, rect.position.y + 2, 3, rect.size.y - 4), accent)

	# Corner accents
	_draw_corners(canvas, rect, 5.0, bc)

	# Text
	var ty: float = rect.position.y + (rect.size.y + UITheme.FONT_SIZE_BODY) * 0.5 - 2.0
	canvas.draw_string(font, Vector2(rect.position.x, ty), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UITheme.FONT_SIZE_BODY, UITheme.TEXT)


static func _draw_danger_badge(canvas: CanvasItem, pos: Vector2, level: int, col: Color) -> void:
	var font: Font = UITheme.get_font()
	var badge_text: String = ""
	for i in level:
		badge_text += "*"
	var bw: float = float(level) * 8.0 + 8.0
	var bh: float = 16.0
	canvas.draw_rect(Rect2(pos.x, pos.y, bw, bh), Color(col.r, col.g, col.b, 0.15))
	canvas.draw_rect(Rect2(pos.x, pos.y, bw, bh), Color(col.r, col.g, col.b, 0.4), false, 1.0)
	canvas.draw_string(font, Vector2(pos.x, pos.y + bh - 2.0), badge_text,
		HORIZONTAL_ALIGNMENT_CENTER, bw, UITheme.FONT_SIZE_TINY, col)


## Returns a color based on danger level.
static func danger_color(level: int) -> Color:
	match level:
		1: return UITheme.ACCENT
		2: return UITheme.PRIMARY
		3: return UITheme.WARNING
		4: return Color(1.0, 0.5, 0.15)
		5: return UITheme.DANGER
	return UITheme.PRIMARY


## Format seconds into M:SS string.
static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "0:00"
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	return "%d:%02d" % [mins, secs]


## Draw L-shaped corner accents (static version for use outside UIComponent).
static func _draw_corners(canvas: CanvasItem, rect: Rect2, length: float, col: Color) -> void:
	var x1: float = rect.position.x
	var y1: float = rect.position.y
	var x2: float = rect.end.x
	var y2: float = rect.end.y
	var l: float = minf(length, minf(rect.size.x * 0.3, rect.size.y * 0.3))
	canvas.draw_line(Vector2(x1, y1), Vector2(x1 + l, y1), col, 1.5)
	canvas.draw_line(Vector2(x1, y1), Vector2(x1, y1 + l), col, 1.5)
	canvas.draw_line(Vector2(x2, y1), Vector2(x2 - l, y1), col, 1.5)
	canvas.draw_line(Vector2(x2, y1), Vector2(x2, y1 + l), col, 1.5)
	canvas.draw_line(Vector2(x1, y2), Vector2(x1 + l, y2), col, 1.5)
	canvas.draw_line(Vector2(x1, y2), Vector2(x1, y2 - l), col, 1.5)
	canvas.draw_line(Vector2(x2, y2), Vector2(x2 - l, y2), col, 1.5)
	canvas.draw_line(Vector2(x2, y2), Vector2(x2, y2 - l), col, 1.5)
