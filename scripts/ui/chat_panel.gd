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

# Fake player names for demo messages
var _demo_names := ["StarPilot_X", "NovaHunter", "CptDarkStar", "GhostRider77", "NebulaFox", "IronViper", "CosmicDust", "ZeroGrav", "ShadowFleet", "AstroKnight"]
var _demo_timer: float = 0.0
var _demo_interval: float = 4.0


func _ready() -> void:
	# Initialize message storage for all channels
	for ch in Channel.values():
		_messages[ch] = []
		_unread_indicators[ch] = 0

	_build_chat()
	_add_system_messages()

	# Don't capture mouse on the main control, only children handle it
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_bg.draw.connect(_draw_panel_bg.bind(_panel_bg))
	add_child(_panel_bg)

	# === Tab bar ===
	var tab_bar := Control.new()
	tab_bar.anchor_right = 1.0
	tab_bar.offset_top = 2
	tab_bar.offset_bottom = 26
	tab_bar.offset_left = 2
	tab_bar.offset_right = -2
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_bar)

	_tab_container = HBoxContainer.new()
	_tab_container.anchor_right = 1.0
	_tab_container.anchor_bottom = 1.0
	_tab_container.add_theme_constant_override("separation", 2)
	_tab_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_bar.add_child(_tab_container)

	for ch in Channel.values():
		var btn := Button.new()
		btn.text = CHANNEL_NAMES[ch]
		btn.toggle_mode = true
		btn.button_pressed = (ch == _current_channel)
		btn.custom_minimum_size = Vector2(58, 22)
		btn.add_theme_font_size_override("font_size", 10)
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
	_message_scroll.mouse_filter = Control.MOUSE_FILTER_PASS

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
	_input_field.add_theme_font_size_override("font_size", 11)
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

	# Redraw background for animations
	_panel_bg.queue_redraw()

	# Demo messages (simulate multiplayer chat)
	_demo_timer += delta
	if _demo_timer >= _demo_interval:
		_demo_timer = 0.0
		_demo_interval = randf_range(3.0, 8.0)
		_spawn_demo_message()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if not _is_focused and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_input_field.grab_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		elif _is_focused and _input_field.text.is_empty():
			_input_field.release_focus()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		elif _is_focused:
			# Enter with text: let LineEdit handle it, but consume so ship doesn't react
			get_viewport().set_input_as_handled()
	elif _is_focused:
		# Chat has focus: consume ALL keyboard events so ship doesn't move while typing
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

	_input_field.clear()

	# Add player's message
	add_message(_current_channel, "Joueur", text, Color(0.3, 0.85, 1.0))

	# Emit signal for network sending
	message_sent.emit(CHANNEL_NAMES[_current_channel], text)

	# Keep focus on input
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
	rtl.add_theme_font_size_override("normal_font_size", 11)

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
# DEMO MESSAGES - Simulated multiplayer chat for testing
# =============================================================================
func _add_system_messages() -> void:
	add_message(Channel.SYSTEM, "SYSTÈME", "Connexion établie. Bienvenue dans le Secteur Alpha.", Color(1.0, 0.85, 0.3))
	add_message(Channel.SYSTEM, "SYSTÈME", "Canal de communication ouvert. 247 pilotes en ligne.", Color(1.0, 0.85, 0.3))
	add_message(Channel.GLOBAL, "StarPilot_X", "Quelqu'un près de la Station Alpha ? Besoin d'escorte pour un convoi", Color(0.3, 0.85, 1.0))
	add_message(Channel.GLOBAL, "NovaHunter", "Attention aux pirates près de la ceinture d'astéroïdes", Color(0.9, 0.4, 0.4))
	add_message(Channel.TRADE, "CosmicDust", "Vend Canons Plasma Mk3 x5 - 12k crédits pièce", Color(0.5, 0.9, 0.5))
	add_message(Channel.GLOBAL, "GhostRider77", "o7 commandants", Color(0.6, 0.8, 0.6))


func _spawn_demo_message() -> void:
	var channel: int = [Channel.GLOBAL, Channel.GLOBAL, Channel.GLOBAL, Channel.TRADE, Channel.SYSTEM].pick_random()
	var name_idx := randi_range(0, _demo_names.size() - 1)
	var author: String = _demo_names[name_idx]
	var author_color := Color(randf_range(0.4, 1.0), randf_range(0.5, 1.0), randf_range(0.6, 1.0))

	var messages_global := [
		"Quelqu'un pour un run dans la nébuleuse ?",
		"Je viens d'atteindre 50k crédits, je suis riche !",
		"o7 volez prudemment tout le monde",
		"Où trouver du deutérium dans le coin ?",
		"Cette station a les meilleurs prix de réparation",
		"Nouveau joueur ici, des conseils ?",
		"Prudence dans le secteur 7, forte activité pirate",
		"Je cherche un clan, quelqu'un recrute ?",
		"Ce jeu est incroyable",
		"GG pour le dogfight de tout à l'heure",
		"Quelqu'un fait du commerce de minerais rares ?",
		"Comment activer le mode croisière déjà ?",
		"Flotte en formation à la Station Alpha, tous bienvenus",
	]
	var messages_trade := [
		"Ach Générateur de Bouclier Mk2, offre 8k",
		"Vend Conteneurs de cargo x20 pas cher",
		"Recherche drones de combat, MP svp",
		"Vend Laser Minier amélioré, 15k à débattre",
		"Besoin d'un transporteur pour 200 unités de minerai",
	]
	var messages_system := [
		"Champ d'astéroïdes détecté à proximité.",
		"Contact signal : Vaisseau inconnu.",
		"Scan du secteur terminé.",
	]

	var text: String
	match channel:
		Channel.GLOBAL: text = messages_global.pick_random()
		Channel.TRADE: text = messages_trade.pick_random()
		Channel.SYSTEM:
			text = messages_system.pick_random()
			author = "SYSTÈME"
			author_color = Color(1.0, 0.85, 0.3)
		_: text = messages_global.pick_random()

	add_message(channel, author, text, author_color)
