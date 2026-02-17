class_name HudGroupPanel
extends Control

# =============================================================================
# HUD Group Panel — Displays party members + handles invite notifications.
# Top-left area, below radar. Uses _draw() pattern.
# =============================================================================

var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _panel: Control = null
var _invite_panel: Control = null

# Group display state
var _group_data: Dictionary = {}  # From NetworkManager.group_updated
var _visible_group: bool = false

# Invite state
var _invite_visible: bool = false
var _invite_name: String = ""
var _invite_group_id: int = 0
var _invite_timer: float = 0.0

const PANEL_W: float = 180.0
const PANEL_H_PER_MEMBER: float = 22.0
const PANEL_HEADER: float = 24.0
const PANEL_PADDING: float = 6.0
const INVITE_W: float = 260.0
const INVITE_H: float = 70.0

# Colors
const COL_BG: Color = Color(0.0, 0.02, 0.05, 0.7)
const COL_BORDER: Color = Color(0.06, 0.25, 0.4, 0.5)
const COL_LEADER: Color = Color(1.0, 0.85, 0.3)
const COL_MEMBER: Color = Color(0.7, 0.92, 1.0)
const COL_HULL_OK: Color = Color(0.3, 0.9, 0.4)
const COL_HULL_LOW: Color = Color(1.0, 0.3, 0.2)
const COL_GROUP_GREEN: Color = Color(0.3, 1.0, 0.6)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Group members panel — top-right, below radar
	_panel = HudDrawHelpers.make_ctrl(1.0, 0.0, 1.0, 0.0, -200, 220, -16, 420)
	_panel.draw.connect(_draw_group_panel.bind(_panel))
	_panel.visible = false
	add_child(_panel)

	# Invite notification — center-top
	_invite_panel = HudDrawHelpers.make_ctrl(0.5, 0.0, 0.5, 0.0, -INVITE_W * 0.5, 80, INVITE_W * 0.5, 80 + INVITE_H)
	_invite_panel.draw.connect(_draw_invite_panel.bind(_invite_panel))
	_invite_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_invite_panel.visible = false
	add_child(_invite_panel)

	# Accept/Decline buttons inside invite panel
	var btn_accept := Button.new()
	btn_accept.text = "ACCEPTER"
	btn_accept.position = Vector2(20, 42)
	btn_accept.custom_minimum_size = Vector2(100, 24)
	btn_accept.add_theme_font_size_override("font_size", 12)
	btn_accept.pressed.connect(_on_invite_accept)
	_invite_panel.add_child(btn_accept)

	var btn_decline := Button.new()
	btn_decline.text = "REFUSER"
	btn_decline.position = Vector2(140, 42)
	btn_decline.custom_minimum_size = Vector2(100, 24)
	btn_decline.add_theme_font_size_override("font_size", 12)
	btn_decline.pressed.connect(_on_invite_decline)
	_invite_panel.add_child(btn_decline)

	# Connect to NetworkManager signals
	NetworkManager.group_invite_received.connect(_on_group_invite)
	NetworkManager.group_updated.connect(_on_group_updated)
	NetworkManager.group_dissolved.connect(_on_group_dissolved)


func _process(delta: float) -> void:
	if _invite_visible:
		_invite_timer -= delta
		if _invite_timer <= 0.0:
			_hide_invite()
			NetworkManager.respond_group_invite(false)
		_invite_panel.queue_redraw()


func redraw_slow() -> void:
	if _visible_group:
		_panel.queue_redraw()


func _on_group_invite(inviter_name: String, gid: int) -> void:
	_invite_name = inviter_name
	_invite_group_id = gid
	_invite_timer = 30.0
	_invite_visible = true
	_invite_panel.visible = true
	_invite_panel.queue_redraw()


func _on_group_updated(gdata: Dictionary) -> void:
	_group_data = gdata
	var members: Array = gdata.get("members", [])
	_visible_group = members.size() > 0

	# Resize panel height based on member count
	var h: float = PANEL_HEADER + members.size() * PANEL_H_PER_MEMBER + PANEL_PADDING * 2
	_panel.offset_bottom = _panel.offset_top + h
	_panel.visible = _visible_group
	_panel.queue_redraw()


func _on_group_dissolved(reason: String) -> void:
	_group_data = {}
	_visible_group = false
	_panel.visible = false
	if reason != "":
		# Show toast-like feedback via chat
		pass  # The server already sends a chat message


func _on_invite_accept() -> void:
	NetworkManager.respond_group_invite(true)
	_hide_invite()


func _on_invite_decline() -> void:
	NetworkManager.respond_group_invite(false)
	_hide_invite()


func _hide_invite() -> void:
	_invite_visible = false
	_invite_panel.visible = false


# =============================================================================
# DRAWING
# =============================================================================

func _draw_group_panel(ctrl: Control) -> void:
	var font := UITheme.get_font_medium()
	var s := ctrl.size

	# Background
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), COL_BG)
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), COL_BORDER, false, 1.0)

	# Header
	ctrl.draw_string(font, Vector2(PANEL_PADDING, 16), "GROUPE", HORIZONTAL_ALIGNMENT_LEFT, int(s.x - PANEL_PADDING * 2), UITheme.FONT_SIZE_LABEL, COL_GROUP_GREEN)

	# Separator
	ctrl.draw_line(Vector2(PANEL_PADDING, PANEL_HEADER), Vector2(s.x - PANEL_PADDING, PANEL_HEADER), COL_BORDER, 1.0)

	# Members
	var members: Array = _group_data.get("members", [])
	var y: float = PANEL_HEADER + PANEL_PADDING
	for m in members:
		var name: String = m.get("name", "???")
		var hull: float = m.get("hull", 1.0)
		var is_leader: bool = m.get("is_leader", false)

		# Leader star prefix
		var display_name: String = name
		if is_leader:
			display_name = "★ " + name
		var name_col: Color = COL_LEADER if is_leader else COL_MEMBER

		# Name
		ctrl.draw_string(font, Vector2(PANEL_PADDING, y + 14), display_name, HORIZONTAL_ALIGNMENT_LEFT, int(s.x - 60), UITheme.FONT_SIZE_SMALL, name_col)

		# Hull bar
		var bar_x: float = s.x - 50
		var bar_w: float = 40.0
		var bar_h: float = 4.0
		var bar_y: float = y + 9
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.8))
		var hull_col: Color = COL_HULL_OK.lerp(COL_HULL_LOW, 1.0 - hull)
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w * clampf(hull, 0.0, 1.0), bar_h), hull_col)

		y += PANEL_H_PER_MEMBER

	# Scanline
	var sly: float = fmod(scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), UITheme.SCANLINE, 1.0)


func _draw_invite_panel(ctrl: Control) -> void:
	var font := UITheme.get_font_medium()
	var s := ctrl.size

	# Background
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.03, 0.08, 0.9))
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), COL_GROUP_GREEN * Color(1, 1, 1, 0.6), false, 1.5)

	# Text
	var msg: String = "%s vous invite dans un groupe" % _invite_name
	ctrl.draw_string(font, Vector2(20, 20), msg, HORIZONTAL_ALIGNMENT_LEFT, int(s.x - 40), UITheme.FONT_SIZE_SMALL, COL_MEMBER)

	# Timer
	var timer_text: String = "%ds" % ceili(_invite_timer)
	ctrl.draw_string(font, Vector2(s.x - 40, 20), timer_text, HORIZONTAL_ALIGNMENT_RIGHT, 30, UITheme.FONT_SIZE_SMALL, Color(1.0, 0.85, 0.3, 0.8))
