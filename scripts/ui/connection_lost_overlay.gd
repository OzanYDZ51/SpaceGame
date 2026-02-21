class_name ConnectionLostOverlay
extends CanvasLayer

# =============================================================================
# Connection Lost Overlay — Always-on-top banner (layer 100)
# Appears over any UI view when the server connection drops.
# =============================================================================

const BANNER_HEIGHT: float = 76.0
const SLIDE_DURATION: float = 0.28

var _banner: Control = null
var _title_label: Label = null
var _status_label: Label = null
var _time_label: Label = null

var _is_shown: bool = false
var _disconnect_time: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	layer = 100
	_build_ui()
	NetworkManager.server_connection_lost.connect(_on_connection_lost)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connection_succeeded.connect(_on_connection_restored)


func _build_ui() -> void:
	_banner = Control.new()
	_banner.name = "ConnectionBanner"
	# Full width via anchor_right, fixed height via offset_bottom — no anchor preset
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	# Start hidden above the screen (offset_top/bottom keep height constant)
	_set_banner_y(-BANNER_HEIGHT)

	# Dark red background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.01, 0.01, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(bg)

	# Red bottom border line
	var border := ColorRect.new()
	border.anchor_left = 0.0
	border.anchor_right = 1.0
	border.anchor_top = 1.0
	border.anchor_bottom = 1.0
	border.offset_top = -3
	border.offset_bottom = 0
	border.color = Color(0.9, 0.2, 0.1, 0.9)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(border)

	# Content row
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(hbox)

	var icon_lbl := Label.new()
	icon_lbl.text = "⚠"
	icon_lbl.add_theme_font_size_override("font_size", 26)
	icon_lbl.add_theme_color_override("font_color", Color(1.0, 0.28, 0.12))
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "CONNEXION PERDUE"
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.18))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_status_label)

	_time_label = Label.new()
	_time_label.text = ""
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.add_theme_color_override("font_color", Color(0.6, 0.35, 0.28))
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_time_label)


## Keep height constant during slide — only moves the Y position.
func _set_banner_y(y: float) -> void:
	_banner.offset_top = y
	_banner.offset_bottom = y + BANNER_HEIGHT


func _process(_delta: float) -> void:
	if not _is_shown:
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _disconnect_time
	var m: int = int(elapsed / 60.0)
	var s: int = int(elapsed) % 60
	_time_label.text = "Hors ligne depuis %02d:%02d" % [m, s]


func _on_connection_lost(reason: String) -> void:
	_disconnect_time = Time.get_ticks_msec() / 1000.0
	_title_label.text = "CONNEXION PERDUE"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.18))
	_status_label.text = reason
	_time_label.text = ""
	_show_banner()


func _on_connection_failed(reason: String) -> void:
	if not _is_shown:
		return
	_status_label.text = reason


func _on_connection_restored() -> void:
	if not _is_shown:
		return
	_title_label.text = "RECONNECTÉ"
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.45))
	_status_label.text = "Connexion rétablie"
	_time_label.text = ""
	get_tree().create_timer(2.5).timeout.connect(_hide_banner, CONNECT_ONE_SHOT)


func _show_banner() -> void:
	_is_shown = true
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	var current_y: float = _banner.offset_top
	_tween.tween_method(_set_banner_y, current_y, 0.0, SLIDE_DURATION)


func _hide_banner() -> void:
	_is_shown = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	var current_y: float = _banner.offset_top
	_tween.tween_method(_set_banner_y, current_y, -BANNER_HEIGHT, SLIDE_DURATION)
