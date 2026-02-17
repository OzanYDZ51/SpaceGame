class_name OptionsScreen
extends UIScreen

# =============================================================================
# Options Screen - OVERLAY with Audio + Controls tabs
# Audio: Master / Music / SFX sliders
# Controls: rebindable key list with conflict swap + reset
# Settings persisted to user://settings.cfg via ConfigFile
# =============================================================================

var _tab_bar: UITabBar
var _current_tab: int = 0
var _dropdown_lang: UIDropdown

# --- Audio ---
var _slider_master: UISlider
var _slider_music: UISlider
var _slider_sfx: UISlider

# --- Controls ---
var _listening: bool = false
var _listening_action: String = ""
var _scroll_offset: float = 0.0

const PANEL_W: float = 500.0
const PANEL_H: float = 540.0
const ROW_H: float = 28.0
const SETTINGS_PATH: String = "user://settings.cfg"

# Rebindable actions: [action_name, locale_key, default_keycode]
const REBINDABLE_ACTIONS: Array = [
	["move_forward", "key.forward", KEY_W],
	["move_backward", "key.backward", KEY_S],
	["strafe_left", "key.left", KEY_A],
	["strafe_right", "key.right", KEY_D],
	["strafe_up", "key.up", KEY_SPACE],
	["strafe_down", "key.down", KEY_CTRL],
	["roll_left", "key.roll_left", KEY_Q],
	["roll_right", "key.roll_right", KEY_E],
	["boost", "key.boost", KEY_SHIFT],
	["toggle_cruise", "key.cruise", KEY_C],
	["toggle_camera", "key.camera", KEY_V],
	["toggle_flight_assist", "key.flight_assist", KEY_Z],
	["toggle_map", "key.system_map", KEY_M],
	["toggle_corporation", "key.corporation", KEY_N],
	["toggle_galaxy_map", "key.galaxy_map", KEY_G],
	["toggle_multiplayer", "key.multiplayer", KEY_P],
	["target_cycle", "key.target_cycle", KEY_TAB],
	["target_nearest", "key.target_nearest", KEY_T],
	["target_clear", "key.target_clear", KEY_Y],
	["pip_weapons", "key.pip_weapons", KEY_UP],
	["pip_shields", "key.pip_shields", KEY_LEFT],
	["pip_engines", "key.pip_engines", KEY_RIGHT],
	["pip_reset", "key.pip_reset", KEY_DOWN],
	["dock", "key.dock", KEY_F],
	["gate_jump", "key.gate_jump", KEY_J],
	["build", "key.build", KEY_B],
	["scanner_pulse", "key.scanner", KEY_H],
	["toggle_weapon_1", "key.weapon_1", KEY_1],
	["toggle_weapon_2", "key.weapon_2", KEY_2],
	["toggle_weapon_3", "key.weapon_3", KEY_3],
	["toggle_weapon_4", "key.weapon_4", KEY_4],
]

# Cached layout rects (set in _draw, used in _gui_input)
var _content_x: float = 0.0
var _content_y: float = 0.0
var _content_w: float = 0.0
var _content_max_h: float = 0.0


func _init() -> void:
	screen_title = Locale.t("screen.options")
	screen_mode = ScreenMode.OVERLAY


func _ready() -> void:
	super._ready()

	# Language dropdown (above tab bar)
	_dropdown_lang = UIDropdown.new()
	_dropdown_lang.options = Array(Locale.get_language_labels()) as Array[String]
	_dropdown_lang.selected_index = Locale.get_language_index()
	_dropdown_lang.option_selected.connect(_on_lang_selected)
	add_child(_dropdown_lang)

	# Tab bar
	_tab_bar = UITabBar.new()
	_tab_bar.tabs = [Locale.t("tab.audio"), Locale.t("tab.controls")]
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	# Audio sliders
	_slider_master = _create_slider(Locale.t("slider.master"))
	_slider_master.value_changed.connect(_on_master_changed)

	_slider_music = _create_slider(Locale.t("slider.music"))
	_slider_music.value_changed.connect(_on_music_changed)

	_slider_sfx = _create_slider(Locale.t("slider.sfx"))
	_slider_sfx.value_changed.connect(_on_sfx_changed)


func _create_slider(label: String) -> UISlider:
	var s := UISlider.new()
	s.label_text = label
	s.value = 1.0
	s.show_percentage = true
	add_child(s)
	return s


# =========================================================================
# Screen lifecycle
# =========================================================================
func _on_opened() -> void:
	_current_tab = 0
	_tab_bar.current_tab = 0
	_listening = false
	_scroll_offset = 0.0
	_update_visibility()
	# Read live audio bus volumes
	_slider_master.value = _get_bus_linear("Master")
	_slider_music.value = _get_bus_linear("Music")
	_slider_sfx.value = _get_bus_linear("SFX")


func _on_closed() -> void:
	_listening = false
	save_settings()


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_listening = false
	_update_visibility()
	queue_redraw()


func _on_lang_selected(idx: int) -> void:
	var code: String = Locale.SUPPORTED_LANGUAGES[idx]["code"]
	Locale.set_language(code)


func _on_language_changed(_lang: String) -> void:
	screen_title = Locale.t("screen.options")
	_tab_bar.tabs = [Locale.t("tab.audio"), Locale.t("tab.controls")]
	_slider_master.label_text = Locale.t("slider.master")
	_slider_music.label_text = Locale.t("slider.music")
	_slider_sfx.label_text = Locale.t("slider.sfx")
	queue_redraw()


func _update_visibility() -> void:
	var show_audio: bool = (_current_tab == 0)
	_slider_master.visible = show_audio
	_slider_music.visible = show_audio
	_slider_sfx.visible = show_audio


# =========================================================================
# Drawing
# =========================================================================
func _draw() -> void:
	var s := size

	# Modal background
	draw_rect(Rect2(Vector2.ZERO, s), UITheme.BG_MODAL)

	# Centered panel
	var px: float = (s.x - PANEL_W) * 0.5
	var py: float = (s.y - PANEL_H) * 0.5
	draw_panel_bg(Rect2(px, py, PANEL_W, PANEL_H))

	# Title
	var font_bold: Font = UITheme.get_font_bold()
	var fsize: int = UITheme.FONT_SIZE_TITLE
	var title_y: float = py + UITheme.MARGIN_PANEL + fsize
	var title_text: String = Locale.t("screen.options")
	draw_string(font_bold, Vector2(px, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, fsize, UITheme.TEXT_HEADER)

	# Decorative title lines
	var title_w: float = font_bold.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	var cx: float = px + PANEL_W * 0.5
	var deco_y: float = title_y - fsize * 0.35
	var half: float = title_w * 0.5 + 16
	draw_line(Vector2(cx - half - 80, deco_y), Vector2(cx - half, deco_y), UITheme.BORDER, 1.0)
	draw_line(Vector2(cx + half, deco_y), Vector2(cx + half + 80, deco_y), UITheme.BORDER, 1.0)

	# Separator
	var sep_y: float = title_y + 10
	draw_line(Vector2(px + 16, sep_y), Vector2(px + PANEL_W - 16, sep_y), UITheme.BORDER, 1.0)

	# Language dropdown (top-right of panel)
	var lang_w: float = 130.0
	var lang_h: float = 24.0
	_dropdown_lang.position = Vector2(px + PANEL_W - UITheme.MARGIN_PANEL - lang_w, py + UITheme.MARGIN_PANEL + 2)
	_dropdown_lang.size = Vector2(lang_w, lang_h)

	# Tab bar
	var tab_y: float = sep_y + 8
	_tab_bar.position = Vector2(px + UITheme.MARGIN_PANEL, tab_y)
	_tab_bar.size = Vector2(PANEL_W - UITheme.MARGIN_PANEL * 2, 32)

	# Content area
	_content_x = px + UITheme.MARGIN_PANEL
	_content_y = tab_y + 44
	_content_w = PANEL_W - UITheme.MARGIN_PANEL * 2
	_content_max_h = PANEL_H - (_content_y - py) - UITheme.MARGIN_PANEL - 20

	if _current_tab == 0:
		_draw_audio_tab()
	else:
		_draw_controls_tab()

	# Close hint
	var hint_font: Font = UITheme.get_font()
	draw_string(hint_font, Vector2(px, py + PANEL_H - 14), Locale.t("common.close_hint"), HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


func _draw_audio_tab() -> void:
	var slider_h: float = 48.0
	var gap: float = 20.0
	_slider_master.position = Vector2(_content_x, _content_y)
	_slider_master.size = Vector2(_content_w, slider_h)
	_slider_music.position = Vector2(_content_x, _content_y + slider_h + gap)
	_slider_music.size = Vector2(_content_w, slider_h)
	_slider_sfx.position = Vector2(_content_x, _content_y + (slider_h + gap) * 2)
	_slider_sfx.size = Vector2(_content_w, slider_h)


func _draw_controls_tab() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_LABEL
	var vis_top: float = _content_y
	var vis_bot: float = _content_y + _content_max_h - 36  # Reserve space for reset button

	for i in REBINDABLE_ACTIONS.size():
		var draw_y: float = _content_y - _scroll_offset + i * ROW_H

		# Clip
		if draw_y + ROW_H < vis_top or draw_y > vis_bot:
			continue

		var entry: Array = REBINDABLE_ACTIONS[i]
		var action: String = entry[0]
		var label: String = Locale.t(entry[1])

		# Alternating row bg
		if i % 2 == 0:
			draw_rect(Rect2(_content_x, draw_y, _content_w, ROW_H), Color(0.0, 0.1, 0.2, 0.15))

		# Label
		var text_y: float = draw_y + ROW_H * 0.5 + fsize * 0.35
		draw_string(font, Vector2(_content_x + 8, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, _content_w * 0.55, fsize, UITheme.TEXT_DIM)

		# Key button
		var key_w: float = 130.0
		var key_x: float = _content_x + _content_w - key_w
		var key_rect := Rect2(key_x, draw_y + 3, key_w, ROW_H - 6)
		draw_rect(key_rect, UITheme.BG_DARK)
		draw_rect(key_rect, UITheme.BORDER, false, 1.0)

		var key_text: String = _get_action_key_name(action)
		var key_col: Color = UITheme.TEXT
		if _listening and _listening_action == action:
			key_text = Locale.t("common.press_key")
			var pulse: float = UITheme.get_pulse(2.0)
			key_col = UITheme.WARNING.lerp(Color(1.0, 1.0, 0.5, 1.0), pulse)
			# Highlight border
			draw_rect(key_rect, UITheme.WARNING, false, 1.5)

		draw_string(font, Vector2(key_x, text_y), key_text, HORIZONTAL_ALIGNMENT_CENTER, key_w, fsize, key_col)

	# Scroll indicator
	var total_h: float = REBINDABLE_ACTIONS.size() * ROW_H
	var view_h: float = vis_bot - vis_top
	if total_h > view_h:
		var bar_h: float = maxf(20.0, view_h * view_h / total_h)
		var bar_y: float = vis_top + (_scroll_offset / (total_h - view_h)) * (view_h - bar_h)
		draw_rect(Rect2(_content_x + _content_w - 3, bar_y, 3, bar_h), UITheme.PRIMARY_DIM)

	# Reset button
	var reset_y: float = _content_y + _content_max_h - 32
	var reset_w: float = 160.0
	var reset_rect := Rect2(_content_x + _content_w - reset_w, reset_y, reset_w, 28)
	draw_rect(reset_rect, UITheme.BG)
	draw_rect(reset_rect, UITheme.BORDER, false, 1.0)
	var reset_font: Font = UITheme.get_font()
	draw_string(reset_font, Vector2(reset_rect.position.x, reset_y + 20), Locale.t("btn.reset"), HORIZONTAL_ALIGNMENT_CENTER, reset_w, UITheme.FONT_SIZE_SMALL, UITheme.DANGER)


# =========================================================================
# Input
# =========================================================================
func _input(event: InputEvent) -> void:
	if not _listening or not _is_open:
		return
	if not (event is InputEventKey and event.pressed):
		return
	if event.physical_keycode == KEY_ESCAPE:
		_cancel_listening()
	else:
		_apply_rebind(event.physical_keycode)
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# Mouse wheel scrolling for controls tab
	if _current_tab == 1 and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_offset = maxf(0.0, _scroll_offset - 40.0)
			queue_redraw()
			accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var view_h: float = _content_max_h - 36
			var max_scroll: float = maxf(0.0, REBINDABLE_ACTIONS.size() * ROW_H - view_h)
			_scroll_offset = minf(max_scroll, _scroll_offset + 40.0)
			queue_redraw()
			accept_event()
			return

	# Left click on controls tab
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _current_tab == 1:
			_handle_controls_click(event.position)

	# Consume all input (prevent game input)
	accept_event()


func _handle_controls_click(pos: Vector2) -> void:
	var vis_top: float = _content_y
	var vis_bot: float = _content_y + _content_max_h - 36

	# Check reset button
	var reset_y: float = _content_y + _content_max_h - 32
	var reset_w: float = 160.0
	var reset_rect := Rect2(_content_x + _content_w - reset_w, reset_y, reset_w, 28)
	if reset_rect.has_point(pos):
		_reset_controls()
		return

	# Check key buttons
	for i in REBINDABLE_ACTIONS.size():
		var draw_y: float = _content_y - _scroll_offset + i * ROW_H
		if draw_y + ROW_H < vis_top or draw_y > vis_bot:
			continue
		var key_w: float = 130.0
		var key_x: float = _content_x + _content_w - key_w
		var key_rect := Rect2(key_x, draw_y + 3, key_w, ROW_H - 6)
		if key_rect.has_point(pos):
			_start_listening(REBINDABLE_ACTIONS[i][0])
			return


func _start_listening(action: String) -> void:
	_listening = true
	_listening_action = action
	queue_redraw()


func _cancel_listening() -> void:
	_listening = false
	_listening_action = ""
	queue_redraw()


func _apply_rebind(keycode: int) -> void:
	var action: String = _listening_action
	_listening = false
	_listening_action = ""

	# Conflict swap: if another action uses this key, give it our old key
	var old_key: int = _get_action_keycode(action)
	for entry in REBINDABLE_ACTIONS:
		var other: String = entry[0]
		if other == action:
			continue
		if _get_action_keycode(other) == keycode:
			_set_action_key(other, old_key)
			break

	_set_action_key(action, keycode)
	queue_redraw()


func _reset_controls() -> void:
	for entry in REBINDABLE_ACTIONS:
		_set_action_key(entry[0], entry[2])
	_listening = false
	queue_redraw()


# =========================================================================
# Audio helpers
# =========================================================================
func _on_master_changed(val: float) -> void:
	_set_bus_volume("Master", val)


func _on_music_changed(val: float) -> void:
	_set_bus_volume("Music", val)


func _on_sfx_changed(val: float) -> void:
	_set_bus_volume("SFX", val)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _get_bus_linear(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


# =========================================================================
# InputMap helpers
# =========================================================================
func _get_action_keycode(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			return ev.physical_keycode
	return 0


func _get_action_key_name(action: String) -> String:
	var keycode: int = _get_action_keycode(action)
	if keycode == 0:
		return "---"
	return OS.get_keycode_string(keycode)


func _set_action_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	# Remove existing key events (keep mouse events)
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	# Add new key
	var new_event := InputEventKey.new()
	new_event.physical_keycode = keycode as Key
	InputMap.action_add_event(action, new_event)


# =========================================================================
# Settings persistence
# =========================================================================
func save_settings() -> void:
	var cfg := ConfigFile.new()
	# Audio
	cfg.set_value("audio", "master", _slider_master.value)
	cfg.set_value("audio", "music", _slider_music.value)
	cfg.set_value("audio", "sfx", _slider_sfx.value)
	# Controls
	for entry in REBINDABLE_ACTIONS:
		var keycode: int = _get_action_keycode(entry[0])
		if keycode > 0:
			cfg.set_value("controls", entry[0], keycode)
	cfg.save(SETTINGS_PATH)
	# Mark dirty so next auto-save syncs settings to backend
	SaveManager.mark_dirty()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# Audio
	if cfg.has_section("audio"):
		var master_val: float = cfg.get_value("audio", "master", 1.0)
		_set_bus_volume("Master", master_val)
		_slider_master.value = master_val
		var music_val: float = cfg.get_value("audio", "music", 1.0)
		_set_bus_volume("Music", music_val)
		_slider_music.value = music_val
		var sfx_val: float = cfg.get_value("audio", "sfx", 1.0)
		_set_bus_volume("SFX", sfx_val)
		_slider_sfx.value = sfx_val
	# Controls
	if cfg.has_section("controls"):
		for entry in REBINDABLE_ACTIONS:
			var action: String = entry[0]
			if cfg.has_section_key("controls", action):
				var keycode: int = cfg.get_value("controls", action, 0)
				if keycode > 0:
					_set_action_key(action, keycode)


func _process(_delta: float) -> void:
	if _listening and _is_open:
		queue_redraw()


# =========================================================================
# Static helpers for backend settings sync
# =========================================================================

## Collects current audio + control settings into a Dictionary for backend save.
static func collect_settings_dict() -> Dictionary:
	var data: Dictionary = {}
	# Audio — read from buses directly (works even if screen is closed)
	var audio: Dictionary = {}
	for pair in [["master", "Master"], ["music", "Music"], ["sfx", "SFX"]]:
		var idx: int = AudioServer.get_bus_index(pair[1])
		if idx < 0:
			audio[pair[0]] = 1.0
		elif AudioServer.is_bus_mute(idx):
			audio[pair[0]] = 0.0
		else:
			audio[pair[0]] = db_to_linear(AudioServer.get_bus_volume_db(idx))
	data["audio"] = audio
	# Controls — read from InputMap
	var controls: Dictionary = {}
	for entry in REBINDABLE_ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			continue
		var events := InputMap.action_get_events(action)
		for ev in events:
			if ev is InputEventKey:
				controls[action] = ev.physical_keycode
				break
	data["controls"] = controls
	return data


## Applies audio + control settings from a backend Dictionary.
## Also writes to local settings.cfg for offline cache.
static func apply_settings_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	# Audio
	var audio: Dictionary = data.get("audio", {}) if data.get("audio") is Dictionary else {}
	if not audio.is_empty():
		var buses: Array = [["master", "Master"], ["music", "Music"], ["sfx", "SFX"]]
		for pair in buses:
			var key: String = pair[0]
			var bus_name: String = pair[1]
			if not audio.has(key):
				continue
			var linear: float = float(audio[key])
			var idx: int = AudioServer.get_bus_index(bus_name)
			if idx < 0:
				continue
			if linear <= 0.001:
				AudioServer.set_bus_mute(idx, true)
			else:
				AudioServer.set_bus_mute(idx, false)
				AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	# Controls
	var controls: Dictionary = data.get("controls", {}) if data.get("controls") is Dictionary else {}
	if not controls.is_empty():
		for action in controls:
			var keycode: int = int(controls[action])
			if keycode <= 0 or not InputMap.has_action(action):
				continue
			# Remove existing key events (keep mouse events)
			var events := InputMap.action_get_events(action)
			for ev in events:
				if ev is InputEventKey:
					InputMap.action_erase_event(action, ev)
			var new_event := InputEventKey.new()
			new_event.physical_keycode = keycode as Key
			InputMap.action_add_event(action, new_event)
	# Write to local cache for offline fallback
	var cfg := ConfigFile.new()
	for key in ["master", "music", "sfx"]:
		if audio.has(key):
			cfg.set_value("audio", key, float(audio[key]))
	for action in controls:
		cfg.set_value("controls", action, int(controls[action]))
	cfg.save(SETTINGS_PATH)
