class_name ChatPanel
extends Control

# =============================================================================
# Multiplayer Chat Panel - DarkOrbit inspired
# Semi-transparent, bottom-left, tabbed channels, immersive sci-fi style
# =============================================================================

signal message_sent(channel: String, text: String)

# Chat channels
enum Channel { GLOBAL, SYSTEM, CLAN, TRADE, PRIVATE }
var _current_channel: int = Channel.GLOBAL

# Colors per channel
const CHANNEL_COLORS := {
	Channel.GLOBAL: Color(0.7, 0.92, 1.0),
	Channel.SYSTEM: Color(1.0, 0.85, 0.3),
	Channel.CLAN: Color(0.4, 1.0, 0.5),
	Channel.TRADE: Color(1.0, 0.6, 0.2),
	Channel.PRIVATE: Color(0.85, 0.5, 1.0),
}

const CHANNEL_NAMES := {
	Channel.GLOBAL: "GÉNÉRAL",
	Channel.SYSTEM: "SYSTÈME",
	Channel.CLAN: "CLAN",
	Channel.TRADE: "COMMERCE",
	Channel.PRIVATE: "MP",
}

const CHANNEL_PREFIXES := {
	Channel.GLOBAL: "[G]",
	Channel.SYSTEM: "[S]",
	Channel.CLAN: "[C]",
	Channel.TRADE: "[T]",
	Channel.PRIVATE: "[PM]",
}

# Theme colors
const COL_BG := Color(0.0, 0.02, 0.05, 0.7)
const COL_BG_DARKER := Color(0.0, 0.01, 0.03, 0.85)
const COL_BORDER := Color(0.06, 0.25, 0.4, 0.5)
const COL_BORDER_ACTIVE := Color(0.1, 0.6, 0.9, 0.7)
const COL_TAB_BG := Color(0.0, 0.03, 0.08, 0.6)
const COL_TAB_ACTIVE := Color(0.02, 0.08, 0.15, 0.9)
const COL_TAB_HOVER := Color(0.03, 0.06, 0.12, 0.7)
const COL_INPUT_BG := Color(0.0, 0.02, 0.05, 0.9)
const COL_TEXT_DIM := Color(0.35, 0.5, 0.6, 0.7)
const COL_TIMESTAMP := Color(0.3, 0.4, 0.5, 0.5)
const COL_SCROLLBAR := Color(0.1, 0.4, 0.6, 0.3)
const COL_CORNER := Color(0.1, 0.5, 0.7, 0.4)

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
var _fade_alpha: float = 0.6
var _target_alpha: float = 0.6
var _max_messages_per_channel: int = 100

var _bg_redraw_timer: float = 0.0
var _private_target: String = ""  # Target player name for PRIVATE channel
var _submit_frame: int = -10  # Frame when last message was submitted (anti key-repeat)


func _ready() -> void:
	# Initialize message storage for all channels
	for ch in Channel.values():
		_messages[ch] = []
		_unread_indicators[ch] = 0

	_build_chat()
	_add_system_messages()

	# Stop mouse events from passing through to the game (e.g. firing weapons)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_chat() -> void:
	# === Main container positioned bottom-left ===
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 16
	offset_top = -_panel_height - 16
	offset_right = 380
	offset_bottom = -16

	# === Background drawing control ===
	_panel_bg = Control.new()
	_panel_bg.anchor_right = 1.0
	_panel_bg.anchor_bottom = 1.0
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_bg.draw.connect(_draw_panel_bg.bind(_panel_bg))
	add_child(_panel_bg)

	# === Tab bar ===
	var tab_bar := Control.new()
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
		var btn := Button.new()
		btn.text = CHANNEL_NAMES[ch]
		btn.toggle_mode = true
		btn.button_pressed = (ch == _current_channel)
		btn.custom_minimum_size = Vector2(58, 22)
		btn.add_theme_font_size_override("font_size", 12)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		# Style the button
		var normal_style := StyleBoxFlat.new()
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

		var pressed_style := StyleBoxFlat.new()
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

		var hover_style := StyleBoxFlat.new()
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
	var sb_style := StyleBoxFlat.new()
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

	# === Input field ===
	_input_field = LineEdit.new()
	_input_field.anchor_right = 1.0
	_input_field.anchor_top = 1.0
	_input_field.anchor_bottom = 1.0
	_input_field.offset_top = -28
	_input_field.offset_bottom = -2
	_input_field.offset_left = 4
	_input_field.offset_right = -4
	_input_field.placeholder_text = "Écrire un message... (Entrée pour envoyer)"
	_input_field.add_theme_font_size_override("font_size", 13)
	_input_field.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0))
	_input_field.add_theme_color_override("font_placeholder_color", COL_TEXT_DIM)
	_input_field.add_theme_color_override("caret_color", Color(0.2, 0.8, 1.0))
	_input_field.mouse_filter = Control.MOUSE_FILTER_STOP

	var input_style := StyleBoxFlat.new()
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

	var input_focus := input_style.duplicate()
	input_focus.border_color = COL_BORDER_ACTIVE
	_input_field.add_theme_stylebox_override("focus", input_focus)

	_input_field.text_submitted.connect(_on_message_submitted)
	_input_field.focus_entered.connect(_on_input_focused)
	_input_field.focus_exited.connect(_on_input_unfocused)
	add_child(_input_field)


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
	if not (event is InputEventKey and event.pressed):
		return

	if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		if not _is_focused and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_input_field.grab_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		elif _is_focused and _input_field.text.is_empty():
			# Skip if message was just submitted (Enter key repeat would close chat)
			if Engine.get_process_frames() - _submit_frame <= 2:
				get_viewport().set_input_as_handled()
				return
			_input_field.release_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		elif _is_focused:
			# Enter with text: DON'T consume — let LineEdit receive it for text_submitted
			pass
	elif event.physical_keycode == KEY_ESCAPE and _is_focused:
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

	_submit_frame = Engine.get_process_frames()
	_input_field.clear()

	# Handle slash commands
	if text.begins_with("/"):
		_handle_command(text)
		_input_field.grab_focus()
		return

	var player_name: String = NetworkManager.local_player_name

	add_message(_current_channel, player_name, text, Color(0.3, 0.85, 1.0))
	message_sent.emit(CHANNEL_NAMES[_current_channel], text)

	_input_field.grab_focus()


func add_message(channel: int, author: String, text: String, author_color: Color = Color.WHITE) -> void:
	var timestamp := Time.get_time_string_from_system().substr(0, 5)  # HH:MM
	var msg := {
		"author": author,
		"text": text,
		"time": timestamp,
		"channel": channel,
		"color": author_color,
	}
	_messages[channel].append(msg)

	# Trim old messages
	if _messages[channel].size() > _max_messages_per_channel:
		_messages[channel].pop_front()

	# Track unread for non-active channels
	if channel != _current_channel:
		_unread_indicators[channel] += 1
		# Update tab appearance
		var idx := channel
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
		var line := _create_message_label(msg)
		_message_list.add_child(line)

	# Scroll to bottom next frame (use a deferred call instead of await to avoid race conditions)
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	if _message_scroll:
		_message_scroll.scroll_vertical = int(_message_scroll.get_v_scroll_bar().max_value)


func _create_message_label(msg: Dictionary) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", 13)

	var time_hex := COL_TIMESTAMP.to_html(false)
	var chan_col: Color = CHANNEL_COLORS.get(msg["channel"], Color.WHITE)
	var chan_hex := chan_col.to_html(false)
	var author_hex: String = msg["color"].to_html(false)
	var prefix: String = CHANNEL_PREFIXES.get(msg["channel"], "")

	var bbcode := "[color=#%s]%s[/color] [color=#%s]%s[/color] [color=#%s]%s:[/color] %s" % [
		time_hex, msg["time"],
		chan_hex, prefix,
		author_hex, msg["author"],
		msg["text"]
	]
	rtl.text = bbcode
	return rtl


func _draw_panel_bg(ctrl: Control) -> void:
	var rect := Rect2(Vector2.ZERO, ctrl.size)

	# Main background
	ctrl.draw_rect(rect, COL_BG)

	# Top edge glow
	ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), COL_BORDER_ACTIVE * Color(1, 1, 1, 0.3), 1.0)

	# Border
	ctrl.draw_rect(rect, COL_BORDER, false, 1.0)

	# Corner accents
	var cl := 12.0
	ctrl.draw_line(Vector2(0, 0), Vector2(cl, 0), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x - cl, 0), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x, cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, ctrl.size.y), Vector2(cl, ctrl.size.y), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(0, ctrl.size.y), Vector2(0, ctrl.size.y - cl), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, ctrl.size.y), Vector2(ctrl.size.x - cl, ctrl.size.y), COL_CORNER, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, ctrl.size.y), Vector2(ctrl.size.x, ctrl.size.y - cl), COL_CORNER, 1.5)

	# Subtle scan line
	var scan_y := fmod(Time.get_ticks_msec() / 30.0, ctrl.size.y)
	ctrl.draw_line(Vector2(0, scan_y), Vector2(ctrl.size.x, scan_y), Color(0.1, 0.5, 0.7, 0.02), 1.0)


# =============================================================================
# SYSTEM MESSAGES & COMMANDS
# =============================================================================
func _add_system_messages() -> void:
	add_message(Channel.SYSTEM, "SYSTÈME", "Canal de communication ouvert. Tapez /help pour les commandes.", Color(1.0, 0.85, 0.3))


func add_system_message(text: String) -> void:
	add_message(Channel.SYSTEM, "SYSTÈME", text, Color(1.0, 0.85, 0.3))


func set_private_target(player_name: String) -> void:
	_private_target = player_name
	_current_channel = Channel.PRIVATE
	_on_tab_pressed(Channel.PRIVATE)
	_input_field.placeholder_text = "MP à %s..." % player_name


func _handle_command(text: String) -> void:
	var parts := text.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var cmd: String = parts[0].to_lower()

	match cmd:
		"/help":
			add_system_message("--- Commandes disponibles ---")
			add_system_message("/w <joueur> <message> — Message privé")
			add_system_message("/mp <joueur> <message> — Message privé")
			add_system_message("/r <message> — Répondre au dernier MP")
			add_system_message("/joueurs — Lister les joueurs du système")
			add_system_message("/players — Lister les joueurs du système")
			add_system_message("/clear — Vider le canal actuel")

		"/clear":
			_messages[_current_channel].clear()
			_refresh_messages()
			add_system_message("Canal vidé.")

		"/joueurs", "/players":
			var names: PackedStringArray = []
			for pid in NetworkManager.peers:
				var state: NetworkState = NetworkManager.peers[pid]
				names.append(state.player_name)
			if names.is_empty():
				add_system_message("Aucun autre joueur dans le secteur.")
			else:
				add_system_message("Joueurs connectés (%d) : %s" % [names.size(), ", ".join(names)])

		"/w", "/mp":
			if parts.size() < 3:
				add_system_message("Usage : /w <joueur> <message>")
				return
			var target_name: String = parts[1]
			var msg_text: String = " ".join(parts.slice(2))
			message_sent.emit("WHISPER:" + target_name, msg_text)
			add_message(Channel.PRIVATE, "→ " + target_name, msg_text, Color(0.85, 0.5, 1.0))

		"/r":
			if parts.size() < 2:
				add_system_message("Usage : /r <message>")
				return
			if _private_target.is_empty():
				add_system_message("Aucun MP reçu auquel répondre.")
				return
			var msg_text: String = " ".join(parts.slice(1))
			message_sent.emit("WHISPER:" + _private_target, msg_text)
			add_message(Channel.PRIVATE, "→ " + _private_target, msg_text, Color(0.85, 0.5, 1.0))

		_:
			add_system_message("Commande inconnue : %s. Tapez /help." % cmd)
