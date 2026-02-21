class_name ChatPanel
extends Control

# =============================================================================
# Multiplayer Chat Panel - DarkOrbit inspired
# Semi-transparent, bottom-left, tabbed channels, immersive sci-fi style
# =============================================================================

signal message_sent(channel: String, text: String)

# Chat channels
enum Channel { GLOBAL, SYSTEM, CORP, TRADE, PRIVATE, GROUP }
var _current_channel: int = Channel.GLOBAL

# Colors per channel
const CHANNEL_COLORS = {
	Channel.GLOBAL: Color(0.7, 0.92, 1.0),
	Channel.SYSTEM: Color(1.0, 0.85, 0.3),
	Channel.CORP: Color(0.4, 1.0, 0.5),
	Channel.TRADE: Color(1.0, 0.6, 0.2),
	Channel.PRIVATE: Color(0.85, 0.5, 1.0),
	Channel.GROUP: Color(0.3, 1.0, 0.6),
}

var CHANNEL_NAMES: Dictionary = {
	Channel.GLOBAL: "GÉNÉRAL",
	Channel.SYSTEM: "SYSTÈME",
	Channel.CORP: "CORP",
	Channel.TRADE: "COMMERCE",
	Channel.PRIVATE: "MP",
	Channel.GROUP: "GROUPE",
}


# Dynamic tabs — hidden by default, shown when relevant
var _corp_tab_visible: bool = false
var _pm_tab_visible: bool = false
var _group_tab_visible: bool = false

# Theme colors
const COL_BG =Color(0.0, 0.02, 0.05, 0.7)
const COL_BG_DARKER =Color(0.0, 0.01, 0.03, 0.85)
const COL_BORDER =Color(0.06, 0.25, 0.4, 0.5)
const COL_BORDER_ACTIVE =Color(0.1, 0.6, 0.9, 0.7)
const COL_TAB_BG =Color(0.0, 0.03, 0.08, 0.6)
const COL_TAB_ACTIVE =Color(0.02, 0.08, 0.15, 0.9)
const COL_TAB_HOVER =Color(0.03, 0.06, 0.12, 0.7)
const COL_INPUT_BG =Color(0.0, 0.02, 0.05, 0.9)
const COL_TEXT_DIM =Color(0.35, 0.5, 0.6, 0.7)
const COL_TIMESTAMP =Color(0.3, 0.4, 0.5, 0.5)
const COL_SCROLLBAR =Color(0.1, 0.4, 0.6, 0.3)
const COL_CORNER =Color(0.1, 0.5, 0.7, 0.4)

# UI refs
var _tab_container: HBoxContainer = null
var _tab_buttons: Array[Button] = []
var _message_scroll: ScrollContainer = null
var _message_list: VBoxContainer = null
var _input_field: LineEdit = null
var _panel_bg: Control = null
var _unread_indicators: Dictionary = {}  # Channel -> int count

# Messages storage per channel
var _messages: Dictionary = {}  # Channel -> Array of {text, author, time, color}

# State
var _is_focused: bool = false
var _panel_height: float = 260.0
var _panel_width: float = 364.0
var _fade_alpha: float = 0.6
var _target_alpha: float = 0.6
var _max_messages_per_channel: int = 100

var _bg_redraw_timer: float = 0.0
var _private_target: String = ""  # Target player name for PRIVATE channel
var _submit_frame: int = -10  # Frame when last message was submitted (anti key-repeat)
var _scroll_pending: bool = false  # True when we need to auto-scroll after content resize

# Resize
enum ResizeEdge { NONE, TOP, RIGHT, TOP_RIGHT }
var _resize_dragging: ResizeEdge = ResizeEdge.NONE
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO  # (width, height) at drag start
const RESIZE_HANDLE_SIZE: float = 6.0
const PANEL_MIN_W: float = 280.0
const PANEL_MAX_W: float = 700.0
const PANEL_MIN_H: float = 150.0
const PANEL_MAX_H: float = 600.0

# Slash command autocomplete
var _autocomplete_popup: Control = null
var _autocomplete_list: VBoxContainer = null
var _autocomplete_items: Array[Dictionary] = []  # Visible filtered commands
var _autocomplete_selected: int = -1  # Currently highlighted index
var _autocomplete_visible: bool = false

static var SLASH_COMMANDS: Array[Dictionary]:
	get: return [
		{"cmd": "/help", "desc": Locale.t("chat.desc_help")},
		{"cmd": "/w", "desc": Locale.t("chat.desc_w")},
		{"cmd": "/mp", "desc": Locale.t("chat.desc_w")},
		{"cmd": "/r", "desc": Locale.t("chat.desc_r")},
		{"cmd": "/joueurs", "desc": Locale.t("chat.desc_players")},
		{"cmd": "/players", "desc": Locale.t("chat.desc_players")},
		{"cmd": "/clear", "desc": Locale.t("chat.desc_clear")},
	]

static var ADMIN_COMMANDS: Array[Dictionary] = [
	{"cmd": "/reset_npcs", "desc": "Supprimer tous les PNJ et repartir à zéro"},
]


func _ready() -> void:
	# Initialize message storage for all channels
	for ch in Channel.values():
		_messages[ch] = []
		_unread_indicators[ch] = 0

	_build_chat()
	_add_system_messages()

	# Stop mouse events from passing through to the game (e.g. firing weapons)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Deferred: check corporation status once GameManager is ready
	_check_corporation.call_deferred()


func _check_corporation() -> void:
	var gm = GameManager
	if gm == null:
		return
	var corp_mgr = gm.get_node_or_null("CorporationManager")
	if corp_mgr == null:
		# CorporationManager not ready yet — wait for it
		await get_tree().create_timer(1.0).timeout
		corp_mgr = gm.get_node_or_null("CorporationManager")
	if corp_mgr == null:
		return
	# Connect to future changes
	if corp_mgr.has_signal("corporation_loaded"):
		corp_mgr.corporation_loaded.connect(_on_corporation_updated.bind(corp_mgr))
	# Check current state
	_on_corporation_updated(corp_mgr)


func _on_corporation_updated(corp_mgr) -> void:
	if corp_mgr.has_corporation():
		var tag: String = corp_mgr.corporation_data.corporation_tag
		set_corporation_tab(true, tag)
	else:
		set_corporation_tab(false)


func _build_chat() -> void:
	# === Main container positioned bottom-left ===
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 16
	offset_top = -_panel_height - 16
	offset_right = 16 + _panel_width
	offset_bottom = -16

	# === Background drawing control ===
	_panel_bg = Control.new()
	_panel_bg.anchor_right = 1.0
	_panel_bg.anchor_bottom = 1.0
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_bg.draw.connect(_draw_panel_bg.bind(_panel_bg))
	_panel_bg.gui_input.connect(_on_panel_gui_input)
	add_child(_panel_bg)

	# === Tab bar ===
	var tab_bar =Control.new()
	tab_bar.anchor_right = 1.0
	tab_bar.offset_top = 2
	tab_bar.offset_bottom = 26
	tab_bar.offset_left = 2
	tab_bar.offset_right = -2
	tab_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(tab_bar)

	_tab_container = HBoxContainer.new()
	_tab_container.anchor_right = 1.0
	_tab_container.anchor_bottom = 1.0
	_tab_container.add_theme_constant_override("separation", 2)
	_tab_container.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_bar.add_child(_tab_container)

	for ch in Channel.values():
		var btn = Button.new()
		btn.text = CHANNEL_NAMES[ch]
		btn.toggle_mode = true
		btn.button_pressed = (ch == _current_channel)
		btn.custom_minimum_size = Vector2(58, 22)
		btn.add_theme_font_size_override("font_size", 12)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		# CORP, PM, and GROUP tabs start hidden
		if ch == Channel.CORP or ch == Channel.PRIVATE or ch == Channel.GROUP:
			btn.visible = false

		# Style the button
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = COL_TAB_BG
		normal_style.border_color = COL_BORDER
		normal_style.border_width_bottom = 1
		normal_style.corner_radius_top_left = 2
		normal_style.corner_radius_top_right = 2
		normal_style.content_margin_left = 4
		normal_style.content_margin_right = 4
		normal_style.content_margin_top = 2
		normal_style.content_margin_bottom = 2
		btn.add_theme_stylebox_override("normal", normal_style)

		var pressed_style =StyleBoxFlat.new()
		pressed_style.bg_color = COL_TAB_ACTIVE
		pressed_style.border_color = COL_BORDER_ACTIVE
		pressed_style.border_width_bottom = 2
		pressed_style.corner_radius_top_left = 2
		pressed_style.corner_radius_top_right = 2
		pressed_style.content_margin_left = 4
		pressed_style.content_margin_right = 4
		pressed_style.content_margin_top = 2
		pressed_style.content_margin_bottom = 2
		btn.add_theme_stylebox_override("pressed", pressed_style)

		var hover_style =StyleBoxFlat.new()
		hover_style.bg_color = COL_TAB_HOVER
		hover_style.border_color = COL_BORDER
		hover_style.border_width_bottom = 1
		hover_style.corner_radius_top_left = 2
		hover_style.corner_radius_top_right = 2
		hover_style.content_margin_left = 4
		hover_style.content_margin_right = 4
		hover_style.content_margin_top = 2
		hover_style.content_margin_bottom = 2
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.add_theme_color_override("font_color", CHANNEL_COLORS[ch] * Color(1, 1, 1, 0.6))
		btn.add_theme_color_override("font_pressed_color", CHANNEL_COLORS[ch])
		btn.add_theme_color_override("font_hover_color", CHANNEL_COLORS[ch] * Color(1, 1, 1, 0.8))

		btn.pressed.connect(_on_tab_pressed.bind(ch))
		_tab_container.add_child(btn)
		_tab_buttons.append(btn)

	# === Message scroll area ===
	_message_scroll = ScrollContainer.new()
	_message_scroll.anchor_right = 1.0
	_message_scroll.anchor_bottom = 1.0
	_message_scroll.offset_top = 28
	_message_scroll.offset_bottom = -30
	_message_scroll.offset_left = 4
	_message_scroll.offset_right = -4
	_message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_message_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	# Scrollbar style
	var sb_style =StyleBoxFlat.new()
	sb_style.bg_color = COL_SCROLLBAR
	sb_style.corner_radius_top_left = 2
	sb_style.corner_radius_top_right = 2
	sb_style.corner_radius_bottom_left = 2
	sb_style.corner_radius_bottom_right = 2
	sb_style.content_margin_left = 3
	sb_style.content_margin_right = 3

	add_child(_message_scroll)

	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_theme_constant_override("separation", 1)
	_message_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_scroll.add_child(_message_list)

	# Auto-scroll: react when scrollbar range changes (content resized), not on a fixed frame delay
	_message_scroll.get_v_scroll_bar().changed.connect(_on_scrollbar_changed)

	# === Input field ===
	_input_field = LineEdit.new()
	_input_field.anchor_right = 1.0
	_input_field.anchor_top = 1.0
	_input_field.anchor_bottom = 1.0
	_input_field.offset_top = -28
	_input_field.offset_bottom = -2
	_input_field.offset_left = 4
	_input_field.offset_right = -4
	_input_field.placeholder_text = Locale.t("chat.placeholder")
	_input_field.add_theme_font_size_override("font_size", 13)
	_input_field.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0))
	_input_field.add_theme_color_override("font_placeholder_color", COL_TEXT_DIM)
	_input_field.add_theme_color_override("caret_color", Color(0.2, 0.8, 1.0))
	_input_field.mouse_filter = Control.MOUSE_FILTER_STOP

	var input_style =StyleBoxFlat.new()
	input_style.bg_color = COL_INPUT_BG
	input_style.border_color = COL_BORDER
	input_style.border_width_top = 1
	input_style.border_width_bottom = 1
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	input_style.corner_radius_top_left = 2
	input_style.corner_radius_top_right = 2
	input_style.corner_radius_bottom_left = 2
	input_style.corner_radius_bottom_right = 2
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 2
	input_style.content_margin_bottom = 2
	_input_field.add_theme_stylebox_override("normal", input_style)

	var input_focus =input_style.duplicate()
	input_focus.border_color = COL_BORDER_ACTIVE
	_input_field.add_theme_stylebox_override("focus", input_focus)

	# NOTE: Do NOT connect text_submitted — Enter is handled in _input() which
	# calls _on_message_submitted directly. Connecting both causes double-send
	# because _input() fires first, then LineEdit's text_submitted fires with
	# the original text (captured before _input_field.clear()).
	_input_field.focus_entered.connect(_on_input_focused)
	_input_field.focus_exited.connect(_on_input_unfocused)
	_input_field.text_changed.connect(_on_input_text_changed)
	add_child(_input_field)

	# === Autocomplete popup (above input field) ===
	_autocomplete_popup = Control.new()
	_autocomplete_popup.anchor_left = 0.0
	_autocomplete_popup.anchor_right = 1.0
	_autocomplete_popup.anchor_top = 1.0
	_autocomplete_popup.anchor_bottom = 1.0
	_autocomplete_popup.offset_left = 4
	_autocomplete_popup.offset_right = -4
	# Height will be adjusted dynamically; starts invisible
	_autocomplete_popup.offset_top = -30
	_autocomplete_popup.offset_bottom = -30
	_autocomplete_popup.visible = false
	_autocomplete_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_autocomplete_popup.draw.connect(_draw_autocomplete_bg.bind(_autocomplete_popup))
	add_child(_autocomplete_popup)

	_autocomplete_list = VBoxContainer.new()
	_autocomplete_list.anchor_right = 1.0
	_autocomplete_list.anchor_bottom = 1.0
	_autocomplete_list.offset_left = 2
	_autocomplete_list.offset_right = -2
	_autocomplete_list.offset_top = 2
	_autocomplete_list.offset_bottom = -2
	_autocomplete_list.add_theme_constant_override("separation", 0)
	_autocomplete_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_autocomplete_popup.add_child(_autocomplete_list)


func _process(delta: float) -> void:
	# Smooth alpha transition
	_fade_alpha = lerp(_fade_alpha, _target_alpha, delta * 8.0)
	modulate.a = _fade_alpha

	# Throttle background redraw to ~10Hz (scanline animation doesn't need 60fps)
	_bg_redraw_timer -= delta
	if _bg_redraw_timer <= 0.0:
		_bg_redraw_timer = 0.1
		_panel_bg.queue_redraw()


func _input(event: InputEvent) -> void:
	# Global mouse handling for resize drag (continues even outside the panel)
	if _resize_dragging != ResizeEdge.NONE:
		if event is InputEventMouseMotion:
			var delta: Vector2 = get_global_mouse_position() - _resize_start_mouse
			var new_w: float = _resize_start_size.x
			var new_h: float = _resize_start_size.y
			if _resize_dragging == ResizeEdge.RIGHT or _resize_dragging == ResizeEdge.TOP_RIGHT:
				new_w = clampf(_resize_start_size.x + delta.x, PANEL_MIN_W, PANEL_MAX_W)
			if _resize_dragging == ResizeEdge.TOP or _resize_dragging == ResizeEdge.TOP_RIGHT:
				new_h = clampf(_resize_start_size.y - delta.y, PANEL_MIN_H, PANEL_MAX_H)
			_apply_resize(new_w, new_h)
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_resize_dragging = ResizeEdge.NONE
			_panel_bg.queue_redraw()
			return

	if not (event is InputEventKey and event.pressed):
		return

	var key: int = event.physical_keycode

	# --- Autocomplete navigation (intercept BEFORE normal handling) ---
	if _is_focused and _autocomplete_visible and not event.echo:
		if key == KEY_UP:
			_autocomplete_navigate(-1)
			get_viewport().set_input_as_handled()
			return
		elif key == KEY_DOWN:
			_autocomplete_navigate(1)
			get_viewport().set_input_as_handled()
			return
		elif key == KEY_TAB and not _autocomplete_items.is_empty():
			_autocomplete_accept()
			get_viewport().set_input_as_handled()
			return
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			if _autocomplete_selected >= 0:
				_autocomplete_accept()
				get_viewport().set_input_as_handled()
				return
			# else: fall through to normal Enter handling (submit text)

	if key == KEY_ENTER or key == KEY_KP_ENTER:
		# Ignore key-repeat (echo) — only react to fresh presses
		if event.echo:
			if _is_focused:
				get_viewport().set_input_as_handled()
			return
		if not _is_focused and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			# Open chat
			_input_field.grab_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		elif _is_focused and _input_field.text.strip_edges().is_empty():
			# Empty field + Enter → close chat (but not right after a submit)
			if Engine.get_process_frames() - _submit_frame <= 10:
				get_viewport().set_input_as_handled()
				return
			_input_field.clear()
			_input_field.release_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		elif _is_focused:
			# Enter with text: consume event and submit directly
			# (if we let it propagate, other _input handlers may eat it)
			_on_message_submitted(_input_field.text)
			get_viewport().set_input_as_handled()

	elif key == KEY_TAB and _is_focused:
		# Tab cycles channels forward, Shift+Tab cycles backward (skip hidden tabs)
		if event.echo:
			get_viewport().set_input_as_handled()
			return
		var count: int = Channel.size()
		var direction: int = -1 if event.shift_pressed else 1
		var next_ch: int = _current_channel
		for _i in count:
			next_ch = (next_ch + direction + count) % count
			if next_ch < _tab_buttons.size() and _tab_buttons[next_ch].visible:
				break
		_on_tab_pressed(next_ch)
		get_viewport().set_input_as_handled()

	elif key == KEY_ESCAPE and _is_focused:
		if event.echo:
			get_viewport().set_input_as_handled()
			return
		if _autocomplete_visible:
			_hide_autocomplete()
			get_viewport().set_input_as_handled()
			return
		_input_field.clear()
		_input_field.release_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()


func _on_input_focused() -> void:
	_is_focused = true
	_target_alpha = 1.0


func _on_input_unfocused() -> void:
	_is_focused = false
	_target_alpha = 0.6
	_hide_autocomplete()


func _on_tab_pressed(channel: int) -> void:
	_current_channel = channel
	_unread_indicators[channel] = 0

	# Update button states
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = (i == channel)
		if i == channel:
			_tab_buttons[i].add_theme_color_override("font_color", CHANNEL_COLORS[i])
		else:
			var unread: int = _unread_indicators[i]
			if unread > 0:
				_tab_buttons[i].add_theme_color_override("font_color", CHANNEL_COLORS[i] * Color(1, 1, 1, 0.9))
			else:
				_tab_buttons[i].add_theme_color_override("font_color", CHANNEL_COLORS[i] * Color(1, 1, 1, 0.6))

	_refresh_messages()


func _on_message_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return

	_hide_autocomplete()
	_submit_frame = Engine.get_process_frames()
	_input_field.clear()

	# Handle slash commands
	if text.begins_with("/"):
		_handle_command(text)
		_input_field.grab_focus()
		return

	var player_name: String = AuthManager.username
	var corp_tag: String = ""
	var corp_mgr = GameManager.get_node_or_null("CorporationManager")
	if corp_mgr and corp_mgr.has_corporation():
		corp_tag = corp_mgr.corporation_data.corporation_tag

	var local_role: String = AuthManager.role if AuthManager.is_authenticated else "player"
	var local_color := Color(1.0, 0.25, 0.25) if local_role == "admin" else Color(0.3, 0.85, 1.0)
	add_message(_current_channel, player_name, text, local_color, corp_tag, local_role)
	message_sent.emit(CHANNEL_NAMES[_current_channel], text)

	_input_field.grab_focus()


func add_message(channel: int, author: String, text: String, author_color: Color = Color.WHITE, corp_tag: String = "", role: String = "player") -> void:
	var timestamp =Time.get_time_string_from_system().substr(0, 5)  # HH:MM
	var msg ={
		"author": author,
		"text": text,
		"time": timestamp,
		"channel": channel,
		"color": author_color,
		"corp_tag": corp_tag,
		"role": role,
	}
	_messages[channel].append(msg)

	# Trim old messages
	if _messages[channel].size() > _max_messages_per_channel:
		_messages[channel].pop_front()

	# Track unread for non-active channels
	if channel != _current_channel:
		_unread_indicators[channel] += 1
		# Update tab appearance
		var idx =channel
		if idx < _tab_buttons.size():
			_tab_buttons[idx].add_theme_color_override("font_color", CHANNEL_COLORS[channel])
			_tab_buttons[idx].text = CHANNEL_NAMES[channel] + " (%d)" % _unread_indicators[channel]

	# Refresh display if on current channel
	if channel == _current_channel:
		_refresh_messages()


func _refresh_messages() -> void:
	# Clear current display — remove immediately to avoid freed-node access
	for child in _message_list.get_children():
		_message_list.remove_child(child)
		child.queue_free()

	# Reset tab text
	for i in _tab_buttons.size():
		if _unread_indicators[i] > 0 and i != _current_channel:
			_tab_buttons[i].text = CHANNEL_NAMES[i] + " (%d)" % _unread_indicators[i]
		else:
			_tab_buttons[i].text = CHANNEL_NAMES[i]

	# Add messages for current channel
	var msgs: Array = _messages[_current_channel]
	for msg in msgs:
		var line =_create_message_label(msg)
		_message_list.add_child(line)

	# Flag for auto-scroll — will fire when the scrollbar range actually updates
	_scroll_pending = true


func _on_scrollbar_changed() -> void:
	if _scroll_pending:
		_scroll_pending = false
		_message_scroll.scroll_vertical = int(_message_scroll.get_v_scroll_bar().max_value)


func _create_message_label(msg: Dictionary) -> RichTextLabel:
	var rtl =RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", 13)

	var time_hex =COL_TIMESTAMP.to_html(false)
	var author_hex: String = msg["color"].to_html(false)
	var tag: String = msg.get("corp_tag", "")
	var is_admin: bool = msg.get("role", "player") == "admin"
	var crown: String = "♛ " if is_admin else ""

	var bbcode: String
	if tag != "":
		var tag_hex: String = Color(0.4, 1.0, 0.5).to_html(false)
		bbcode = "[color=#%s]%s[/color] [color=#%s][%s][/color] [color=#%s]%s%s:[/color] %s" % [
			time_hex, msg["time"],
			tag_hex, tag,
			author_hex, crown, msg["author"],
			msg["text"]
		]
	else:
		bbcode = "[color=#%s]%s[/color] [color=#%s]%s%s:[/color] %s" % [
			time_hex, msg["time"],
			author_hex, crown, msg["author"],
			msg["text"]
		]
	rtl.text = bbcode
	return rtl


func _draw_panel_bg(ctrl: Control) -> void:
	var rect =Rect2(Vector2.ZERO, ctrl.size)

	# Main background
	ctrl.draw_rect(rect, COL_BG)

	# Top edge glow
	ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), COL_BORDER_ACTIVE * Color(1, 1, 1, 0.3), 1.0)

	# Border
	ctrl.draw_rect(rect, COL_BORDER, false, 1.0)

	# Corner accents
	var cl: float = 12.0
	ctrl.draw_line(Vector2(0, 0), Vector2(cl, 0), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x - cl, 0), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x, cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, ctrl.size.y), Vector2(cl, ctrl.size.y), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, ctrl.size.y), Vector2(0, ctrl.size.y - cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, ctrl.size.y), Vector2(ctrl.size.x - cl, ctrl.size.y), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, ctrl.size.y), Vector2(ctrl.size.x, ctrl.size.y - cl), COL_CORNER, 1.5)

	# Resize grip — top-right corner (3 diagonal lines)
	var grip_col: Color = COL_CORNER if _resize_dragging == ResizeEdge.NONE else Color(0.2, 0.8, 1.0, 0.7)
	var gx: float = ctrl.size.x
	for i in 3:
		var off: float = 4.0 + i * 4.0
		ctrl.draw_line(Vector2(gx - off, 0), Vector2(gx, off), grip_col, 1.0)

	# Subtle scan line
	var scan_y =fmod(Time.get_ticks_msec() / 30.0, ctrl.size.y)
	ctrl.draw_line(Vector2(0, scan_y), Vector2(ctrl.size.x, scan_y), Color(0.1, 0.5, 0.7, 0.02), 1.0)


# =============================================================================
# RESIZE HANDLING
# =============================================================================
func _get_resize_edge(local_pos: Vector2) -> ResizeEdge:
	var sz: Vector2 = _panel_bg.size
	var on_top: bool = local_pos.y < RESIZE_HANDLE_SIZE
	var on_right: bool = local_pos.x > sz.x - RESIZE_HANDLE_SIZE
	if on_top and on_right:
		return ResizeEdge.TOP_RIGHT
	if on_top:
		return ResizeEdge.TOP
	if on_right:
		return ResizeEdge.RIGHT
	return ResizeEdge.NONE


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var edge: ResizeEdge = _get_resize_edge(event.position)
				if edge != ResizeEdge.NONE:
					_resize_dragging = edge
					_resize_start_mouse = get_global_mouse_position()
					_resize_start_size = Vector2(_panel_width, _panel_height)
					_panel_bg.accept_event()
			else:
				if _resize_dragging != ResizeEdge.NONE:
					_resize_dragging = ResizeEdge.NONE
					_panel_bg.queue_redraw()
					_panel_bg.accept_event()

	elif event is InputEventMouseMotion:
		if _resize_dragging != ResizeEdge.NONE:
			var delta: Vector2 = get_global_mouse_position() - _resize_start_mouse
			var new_w: float = _resize_start_size.x
			var new_h: float = _resize_start_size.y
			if _resize_dragging == ResizeEdge.RIGHT or _resize_dragging == ResizeEdge.TOP_RIGHT:
				new_w = clampf(_resize_start_size.x + delta.x, PANEL_MIN_W, PANEL_MAX_W)
			if _resize_dragging == ResizeEdge.TOP or _resize_dragging == ResizeEdge.TOP_RIGHT:
				new_h = clampf(_resize_start_size.y - delta.y, PANEL_MIN_H, PANEL_MAX_H)
			_apply_resize(new_w, new_h)
			_panel_bg.accept_event()
		else:
			# Update cursor based on hover position
			var edge: ResizeEdge = _get_resize_edge(event.position)
			match edge:
				ResizeEdge.TOP_RIGHT:
					_panel_bg.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
				ResizeEdge.TOP:
					_panel_bg.mouse_default_cursor_shape = Control.CURSOR_VSIZE
				ResizeEdge.RIGHT:
					_panel_bg.mouse_default_cursor_shape = Control.CURSOR_HSIZE
				_:
					_panel_bg.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _apply_resize(w: float, h: float) -> void:
	_panel_width = w
	_panel_height = h
	offset_right = 16 + _panel_width
	offset_top = -_panel_height - 16
	_panel_bg.queue_redraw()


# =============================================================================
# SYSTEM MESSAGES & COMMANDS
# =============================================================================
func _add_system_messages() -> void:
	add_message(Channel.SYSTEM, "SYSTÈME", "Canal de communication ouvert. Tapez /help pour les commandes.", Color(1.0, 0.85, 0.3))


func add_system_message(text: String) -> void:
	add_message(Channel.SYSTEM, "SYSTÈME", text, Color(1.0, 0.85, 0.3))


## Show or hide the CORP tab. If a tag is provided, use it as label (e.g. "[NOVA]").
func set_corporation_tab(has_corp: bool, tag: String = "") -> void:
	if Channel.CORP >= _tab_buttons.size():
		return
	_corp_tab_visible = has_corp
	_tab_buttons[Channel.CORP].visible = has_corp
	if has_corp and tag != "":
		CHANNEL_NAMES[Channel.CORP] = tag.to_upper()
		_tab_buttons[Channel.CORP].text = tag.to_upper()
	else:
		CHANNEL_NAMES[Channel.CORP] = "CORP"
	# If currently on CORP tab and it disappears, switch to GLOBAL
	if not has_corp and _current_channel == Channel.CORP:
		_on_tab_pressed(Channel.GLOBAL)


## Show or hide the GROUP tab. Called when joining or leaving a group.
func set_group_tab_visible(show_tab: bool) -> void:
	if Channel.GROUP >= _tab_buttons.size():
		return
	_group_tab_visible = show_tab
	_tab_buttons[Channel.GROUP].visible = show_tab
	# If currently on GROUP tab and it disappears, switch to GLOBAL
	if not show_tab and _current_channel == Channel.GROUP:
		_on_tab_pressed(Channel.GLOBAL)


## Show the PM tab with a player name. Called when receiving a whisper.
func show_private_tab(player_name: String) -> void:
	_private_target = player_name
	_pm_tab_visible = true
	if Channel.PRIVATE < _tab_buttons.size():
		_tab_buttons[Channel.PRIVATE].visible = true
		_tab_buttons[Channel.PRIVATE].text = player_name


func set_private_target(player_name: String) -> void:
	_private_target = player_name
	show_private_tab(player_name)
	_current_channel = Channel.PRIVATE
	_on_tab_pressed(Channel.PRIVATE)
	_input_field.placeholder_text = Locale.t("chat.pm_placeholder") % player_name


func _handle_command(text: String) -> void:
	var parts =text.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var cmd: String = parts[0].to_lower()

	match cmd:
		"/help":
			add_system_message(Locale.t("chat.help_header"))
			add_system_message(Locale.t("chat.cmd_w"))
			add_system_message(Locale.t("chat.cmd_w"))
			add_system_message(Locale.t("chat.cmd_r"))
			add_system_message(Locale.t("chat.cmd_players"))
			add_system_message(Locale.t("chat.cmd_players"))
			add_system_message(Locale.t("chat.cmd_clear"))
			if AuthManager.is_authenticated and AuthManager.role == "admin":
				add_system_message("── ADMIN ──")
				add_system_message("/reset_npcs — Supprimer tous les PNJ et repartir à zéro")

		"/clear":
			_messages[_current_channel].clear()
			_refresh_messages()
			add_system_message(Locale.t("chat.cleared"))

		"/joueurs", "/players":
			var names: PackedStringArray = []
			for pid in NetworkManager.peers:
				var state = NetworkManager.peers[pid]
				names.append(state.player_name)
			if names.is_empty():
				add_system_message(Locale.t("chat.no_players"))
			else:
				add_system_message(Locale.t("chat.players_list") % [names.size(), ", ".join(names)])

		"/w", "/mp":
			if parts.size() < 3:
				add_system_message(Locale.t("chat.usage_w"))
				return
			var target_name: String = parts[1]
			var msg_text: String = " ".join(parts.slice(2))
			show_private_tab(target_name)
			message_sent.emit("WHISPER:" + target_name, msg_text)
			add_message(Channel.PRIVATE, "→ " + target_name, msg_text, Color(0.85, 0.5, 1.0))

		"/r":
			if parts.size() < 2:
				add_system_message(Locale.t("chat.usage_r"))
				return
			if _private_target.is_empty():
				add_system_message(Locale.t("chat.no_pm"))
				return
			var msg_text: String = " ".join(parts.slice(1))
			show_private_tab(_private_target)
			message_sent.emit("WHISPER:" + _private_target, msg_text)
			add_message(Channel.PRIVATE, "→ " + _private_target, msg_text, Color(0.85, 0.5, 1.0))

		"/reset_npcs":
			if not AuthManager.is_authenticated or AuthManager.role != "admin":
				add_system_message("⚠ Accès refusé — commande réservée aux admins.")
				return
			if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
				# Pure client connected to remote server: send via RPC
				NetworkManager.send_admin_command("reset_npcs")
				add_system_message("♛ Commande de reset envoyée au serveur...")
			else:
				# Offline or running as server: execute directly
				var npc_auth = GameManager.get_node_or_null("NpcAuthority")
				if npc_auth:
					npc_auth.admin_reset_all_npcs()
					add_system_message("♛ Reset des PNJ effectué.")
				else:
					add_system_message("⚠ NpcAuthority introuvable.")

		_:
			add_system_message(Locale.t("chat.unknown_cmd") % cmd)


# =============================================================================
# SLASH COMMAND AUTOCOMPLETE
# =============================================================================
func _on_input_text_changed(new_text: String) -> void:
	if new_text.begins_with("/"):
		var typed: String = new_text.split(" ", false)[0].to_lower() if not new_text.contains(" ") else ""
		if typed != "":
			_filter_autocomplete(typed)
		else:
			_hide_autocomplete()
	else:
		_hide_autocomplete()


func _filter_autocomplete(typed: String) -> void:
	_autocomplete_items.clear()
	var all_cmds: Array = SLASH_COMMANDS.duplicate()
	# Admin commands are only shown to admins
	if AuthManager.is_authenticated and AuthManager.role == "admin":
		all_cmds.append_array(ADMIN_COMMANDS)
	for entry in all_cmds:
		var cmd: String = entry["cmd"]
		if cmd.begins_with(typed) or typed == "/":
			_autocomplete_items.append(entry)

	if _autocomplete_items.is_empty():
		_hide_autocomplete()
		return

	_autocomplete_selected = -1
	_rebuild_autocomplete_ui()
	_autocomplete_popup.visible = true
	_autocomplete_visible = true


func _rebuild_autocomplete_ui() -> void:
	for child in _autocomplete_list.get_children():
		_autocomplete_list.remove_child(child)
		child.queue_free()

	var row_height: float = 22.0
	var total_h: float = _autocomplete_items.size() * row_height + 4  # +4 for padding
	_autocomplete_popup.offset_top = -30 - total_h
	_autocomplete_popup.offset_bottom = -30

	for i in _autocomplete_items.size():
		var entry: Dictionary = _autocomplete_items[i]
		var row: Button = Button.new()
		row.text = "%s  %s" % [entry["cmd"], entry["desc"]]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, row_height)
		row.add_theme_font_size_override("font_size", 12)
		row.mouse_filter = Control.MOUSE_FILTER_STOP

		var style_n: StyleBoxFlat = StyleBoxFlat.new()
		style_n.bg_color = Color.TRANSPARENT
		style_n.content_margin_left = 6
		style_n.content_margin_right = 6
		row.add_theme_stylebox_override("normal", style_n)

		var style_h: StyleBoxFlat = StyleBoxFlat.new()
		style_h.bg_color = Color(0.06, 0.3, 0.5, 0.5)
		style_h.content_margin_left = 6
		style_h.content_margin_right = 6
		row.add_theme_stylebox_override("hover", style_h)

		var style_p: StyleBoxFlat = style_h.duplicate()
		row.add_theme_stylebox_override("pressed", style_p)
		row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		row.add_theme_color_override("font_color", Color(0.55, 0.7, 0.8))
		row.add_theme_color_override("font_hover_color", Color(0.8, 0.95, 1.0))

		var idx: int = i
		row.pressed.connect(_on_autocomplete_clicked.bind(idx))
		_autocomplete_list.add_child(row)

	_update_autocomplete_highlight()


func _update_autocomplete_highlight() -> void:
	var children: Array[Node] = _autocomplete_list.get_children()
	for i in children.size():
		var btn: Button = children[i] as Button
		if btn == null:
			continue
		var entry: Dictionary = _autocomplete_items[i]
		if i == _autocomplete_selected:
			btn.text = "> %s  %s" % [entry["cmd"], entry["desc"]]
			btn.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0))
			# Set highlighted bg
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color(0.06, 0.3, 0.5, 0.5)
			style.content_margin_left = 6
			style.content_margin_right = 6
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.text = "  %s  %s" % [entry["cmd"], entry["desc"]]
			btn.add_theme_color_override("font_color", Color(0.55, 0.7, 0.8))
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
			style.content_margin_left = 6
			style.content_margin_right = 6
			btn.add_theme_stylebox_override("normal", style)


func _autocomplete_navigate(direction: int) -> void:
	if _autocomplete_items.is_empty():
		return
	_autocomplete_selected += direction
	if _autocomplete_selected < 0:
		_autocomplete_selected = _autocomplete_items.size() - 1
	elif _autocomplete_selected >= _autocomplete_items.size():
		_autocomplete_selected = 0
	_update_autocomplete_highlight()


func _autocomplete_accept() -> void:
	var idx: int = _autocomplete_selected if _autocomplete_selected >= 0 else 0
	if idx >= _autocomplete_items.size():
		return
	var cmd: String = _autocomplete_items[idx]["cmd"]
	_input_field.text = cmd + " "
	_input_field.caret_column = _input_field.text.length()
	_hide_autocomplete()


func _on_autocomplete_clicked(idx: int) -> void:
	_autocomplete_selected = idx
	_autocomplete_accept()
	_input_field.grab_focus()


func _hide_autocomplete() -> void:
	_autocomplete_popup.visible = false
	_autocomplete_visible = false
	_autocomplete_selected = -1


func _draw_autocomplete_bg(ctrl: Control) -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, ctrl.size)
	ctrl.draw_rect(rect, Color(0.0, 0.02, 0.06, 0.92))
	ctrl.draw_rect(rect, Color(0.06, 0.3, 0.5, 0.5), false, 1.0)
	# Top accent line
	ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), Color(0.1, 0.6, 0.9, 0.4), 1.0)


## Load chat history received from the server on (re)connect.
## Clears existing messages and populates channels without triggering unread indicators.
func load_history(history: Array) -> void:
	# Don't wipe local messages if the server sent an empty history (bug guard)
	if history.is_empty():
		return

	# Clear all channels
	for ch in Channel.values():
		_messages[ch].clear()
		_unread_indicators[ch] = 0

	# Add historical messages (no unread tracking)
	for entry in history:
		var ch: int = int(entry.get("ch", 0))
		if ch < 0 or ch >= Channel.size():
			continue
		var author: String = entry.get("s", "???")
		var entry_role: String = entry.get("rl", "player")
		var color: Color = Color(0.3, 0.85, 1.0)
		# Apply same transformations as NetworkChatRelay._on_network_chat_received
		if ch == Channel.SYSTEM:
			author = "SYSTÈME"
			color = Color(1.0, 0.85, 0.3)
			entry_role = "player"
		elif ch == Channel.PRIVATE:
			color = Color(0.85, 0.5, 1.0)
		if entry_role == "admin":
			color = Color(1.0, 0.25, 0.25)
		var msg ={
			"author": author,
			"text": entry.get("t", ""),
			"time": entry.get("ts", "--:--"),
			"channel": ch,
			"color": color,
			"corp_tag": entry.get("ctag", ""),
			"role": entry_role,
		}
		_messages[ch].append(msg)

	# Reset tab labels and refresh current view
	for i in _tab_buttons.size():
		_tab_buttons[i].text = CHANNEL_NAMES[i]
	_refresh_messages()
