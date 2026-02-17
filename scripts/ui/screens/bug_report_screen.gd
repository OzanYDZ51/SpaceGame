class_name BugReportScreen
extends UIScreen

# =============================================================================
# Bug Report Screen
# F12 to open. Lets players submit bug reports with auto-filled context.
# Screenshot + system info sent to backend → Discord #bug-reports channel.
# =============================================================================

var _title_input: UITextInput = null
var _desc_input: UITextInput = null
var _system_label: Label = null
var _position_label: Label = null
var _submit_btn: UIButton = null
var _close_btn: UIButton = null
var _sending: bool = false


func _init() -> void:
	screen_mode = UIScreen.ScreenMode.OVERLAY


func _build_ui() -> void:
	# Background overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Panel
	var panel := UIPanel.new()
	panel.custom_minimum_size = Vector2(500, 420)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position -= panel.custom_minimum_size / 2
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.set("theme_override_constants/separation", 12)
	vbox.offset_left = 24
	vbox.offset_right = -24
	vbox.offset_top = 20
	vbox.offset_bottom = -20
	panel.add_child(vbox)

	# Title bar
	var title_label := Label.new()
	title_label.text = "RAPPORT DE BUG"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0, 0.78, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Title input
	var title_row := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "TITRE"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0, 0.78, 1.0, 0.5))
	title_lbl.custom_minimum_size.x = 70
	title_row.add_child(title_lbl)
	_title_input = UITextInput.new()
	_title_input.placeholder = "Decrivez le bug en quelques mots..."
	_title_input.custom_minimum_size.y = 32
	_title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_input)
	vbox.add_child(title_row)

	# Description input (multiline)
	var desc_lbl := Label.new()
	desc_lbl.text = "DESCRIPTION"
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0, 0.78, 1.0, 0.5))
	vbox.add_child(desc_lbl)

	_desc_input = UITextInput.new()
	_desc_input.placeholder = "Etapes pour reproduire, ce qui etait attendu, ce qui s'est passe..."
	_desc_input.custom_minimum_size.y = 120
	_desc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_desc_input)

	# Auto-filled info
	var info_panel := PanelContainer.new()
	var info_vbox := VBoxContainer.new()
	info_vbox.set("theme_override_constants/separation", 4)
	info_panel.add_child(info_vbox)

	_system_label = Label.new()
	_system_label.add_theme_font_size_override("font_size", 13)
	_system_label.add_theme_color_override("font_color", Color(0.69, 0.83, 0.91, 0.6))
	info_vbox.add_child(_system_label)

	_position_label = Label.new()
	_position_label.add_theme_font_size_override("font_size", 13)
	_position_label.add_theme_color_override("font_color", Color(0.69, 0.83, 0.91, 0.6))
	info_vbox.add_child(_position_label)

	var version_label := Label.new()
	version_label.text = "Version: " + Constants.GAME_VERSION
	version_label.add_theme_font_size_override("font_size", 13)
	version_label.add_theme_color_override("font_color", Color(0.69, 0.83, 0.91, 0.6))
	info_vbox.add_child(version_label)

	vbox.add_child(info_panel)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.set("theme_override_constants/separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	_submit_btn = UIButton.new()
	_submit_btn.text = "ENVOYER"
	_submit_btn.custom_minimum_size = Vector2(150, 36)
	_submit_btn.pressed.connect(_on_submit)
	btn_row.add_child(_submit_btn)

	_close_btn = UIButton.new()
	_close_btn.text = "FERMER"
	_close_btn.custom_minimum_size = Vector2(150, 36)
	_close_btn.pressed.connect(_on_close)
	btn_row.add_child(_close_btn)

	vbox.add_child(btn_row)


func _on_opened() -> void:
	if not _title_input:
		_build_ui()
	_title_input.set_text("")
	_desc_input.set_text("")
	_sending = false
	_submit_btn.text = "ENVOYER"
	_submit_btn.enabled = true
	_update_context_info()


func _update_context_info() -> void:
	var system_name := "Inconnu"
	var system_id := 0
	if GameManager._system_transition:
		system_id = GameManager._system_transition.current_system_id
		# Try to get system name from galaxy data
		if GameManager._galaxy:
			var sys_data = GameManager._galaxy.get_system(system_id)
			if sys_data:
				system_name = sys_data.get("name", "Systeme #%d" % system_id)

	_system_label.text = "Systeme: %s (#%d)" % [system_name, system_id]

	var pos := Vector3(FloatingOrigin.origin_offset_x, FloatingOrigin.origin_offset_y, FloatingOrigin.origin_offset_z)
	_position_label.text = "Position: %.0f, %.0f, %.0f" % [pos.x, pos.y, pos.z]


func _on_submit() -> void:
	if not AuthManager.is_authenticated:
		if GameManager._notif:
			GameManager._notif.general.bug_report_validation("Connexion requise pour envoyer un rapport")
		return

	var title_text: String = _title_input.get_text().strip_edges()
	var desc_text: String = _desc_input.get_text().strip_edges()

	if title_text.is_empty():
		if GameManager._notif:
			GameManager._notif.general.bug_report_validation("Le titre est requis")
		return

	if desc_text.is_empty():
		if GameManager._notif:
			GameManager._notif.general.bug_report_validation("La description est requise")
		return

	if _sending:
		return

	_sending = true
	_submit_btn.text = "ENVOI..."
	_submit_btn.enabled = false

	# Gather context
	var system_id := 0
	if GameManager._system_transition:
		system_id = GameManager._system_transition.current_system_id

	var pos := Vector3(FloatingOrigin.origin_offset_x, FloatingOrigin.origin_offset_y, FloatingOrigin.origin_offset_z)
	var position_str := "%.0f,%.0f,%.0f" % [pos.x, pos.y, pos.z]

	# Take screenshot
	var screenshot_b64 := ""
	var viewport := get_viewport()
	if viewport:
		var image := viewport.get_texture().get_image()
		if image:
			image.resize(640, 360)
			var png := image.save_png_to_buffer()
			screenshot_b64 = Marshalls.raw_to_base64(png)

	# Send to backend
	var body := {
		"title": title_text,
		"description": desc_text,
		"system_id": system_id,
		"position": position_str,
		"game_version": Constants.GAME_VERSION,
		"screenshot_b64": screenshot_b64,
	}

	var url: String = Constants.BACKEND_URL
	url += "/api/v1/player/bug-report"

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + AuthManager.get_access_token(),
	])

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		_sending = false
		_submit_btn.text = "ENVOYER"
		_submit_btn.enabled = true

		if code >= 200 and code < 300:
			if GameManager._notif:
				GameManager._notif.general.bug_report_sent()
			_on_close()
		else:
			if GameManager._notif:
				GameManager._notif.general.bug_report_error(code)
	)

	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _on_close() -> void:
	if GameManager._screen_manager:
		GameManager._screen_manager.close_top()
