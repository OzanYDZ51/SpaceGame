class_name SplashScreen
extends CanvasLayer

# =============================================================================
# Splash Screen — Loading screen with real progress bar and step text.
# Covers the viewport during init + backend load so the player never sees
# the default ship position. Dismisses only after progress reaches 1.0.
# =============================================================================

signal finished

const FADE_IN_DURATION: float = 0.7
const TEXT_REVEAL_DURATION: float = 0.5
const HOLD_DURATION: float = 1.0
const FADE_OUT_DURATION: float = 0.8
const STAR_COUNT: int = 60
const LOGO_SIZE: float = 96.0
const BAR_W: float = 280.0
const BAR_H: float = 3.0
const BAR_TWEEN_DURATION: float = 0.35

static var TIPS: Array[String]:
	get:
		return [
			Locale.t("splash.tip_target"),
			Locale.t("splash.tip_cruise"),
			Locale.t("splash.tip_deploy"),
			Locale.t("splash.tip_station"),
			Locale.t("splash.tip_danger"),
			Locale.t("splash.tip_squadron"),
			Locale.t("splash.tip_help"),
			Locale.t("splash.tip_refine"),
			Locale.t("splash.tip_corp"),
		]

var _bg: ColorRect
var _logo: TextureRect
var _title_label: Label
var _subtitle_label: Label
var _line_top: ColorRect
var _line_bottom: ColorRect
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _bar_glow: ColorRect
var _step_label: Label
var _tip_label: Label
var _version_label: Label
var _star_container: Control
var _stars: Array[Dictionary] = []
var _elapsed: float = 0.0
var _phase: int = 0  # 0=fade_in, 1=reveal, 2=hold, 3=fade_out, 4=done
var _phase_timer: float = 0.0
var _ready_to_dismiss: bool = false
var _min_display_done: bool = false
var _progress: float = 0.0        # Current visual progress (tweened)
var _target_progress: float = 0.0  # Target progress from set_step()
var _bar_tween: Tween = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	var font_bold: Font = null
	var font_medium: Font = null
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-Bold.ttf"):
		font_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-Medium.ttf"):
		font_medium = load("res://assets/fonts/Rajdhani-Medium.ttf")

	# --- Full-screen background ---
	_bg = ColorRect.new()
	_bg.color = Color(0.006, 0.008, 0.018, 1.0)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# --- Stars ---
	_star_container = Control.new()
	_star_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_star_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_star_container)

	var vp_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	for i in STAR_COUNT:
		var star := ColorRect.new()
		var s: float = randf_range(1.0, 2.5)
		star.custom_minimum_size = Vector2(s, s)
		star.size = Vector2(s, s)
		star.color = Color(0.5, 0.7, 1.0, 0.0)
		star.position = Vector2(randf() * vp_size.x, randf() * vp_size.y)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_star_container.add_child(star)
		_stars.append({
			"node": star,
			"base_alpha": randf_range(0.08, 0.35),
			"speed": randf_range(0.4, 2.0),
			"phase": randf() * TAU,
			"drift_x": randf_range(-5.0, 5.0),
			"drift_y": randf_range(-2.0, 2.0),
		})

	# --- Logo ---
	var icon_tex: Texture2D = load("res://icon.png")
	_logo = TextureRect.new()
	_logo.texture = icon_tex
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(LOGO_SIZE, LOGO_SIZE)
	_logo.size = Vector2(LOGO_SIZE, LOGO_SIZE)
	_logo.modulate = Color(1, 1, 1, 0)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_logo)

	# --- Top separator ---
	_line_top = ColorRect.new()
	_line_top.custom_minimum_size = Vector2(280, 1)
	_line_top.size = Vector2(280, 1)
	_line_top.color = Color(0.0, 0.65, 0.9, 0.0)
	_line_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_line_top)

	# --- Title ---
	_title_label = Label.new()
	_title_label.text = "I M P E R I O N"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		_title_label.add_theme_font_override("font", font_bold)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.75, 0.88, 0.95, 0.0))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_title_label)

	# --- Subtitle ---
	_subtitle_label = Label.new()
	_subtitle_label.text = "O N L I N E"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_medium:
		_subtitle_label.add_theme_font_override("font", font_medium)
	_subtitle_label.add_theme_font_size_override("font_size", 14)
	_subtitle_label.add_theme_color_override("font_color", Color(0.0, 0.65, 0.85, 0.0))
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_subtitle_label)

	# --- Bottom separator ---
	_line_bottom = ColorRect.new()
	_line_bottom.custom_minimum_size = Vector2(160, 1)
	_line_bottom.size = Vector2(160, 1)
	_line_bottom.color = Color(0.0, 0.65, 0.9, 0.0)
	_line_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_line_bottom)

	# --- Progress bar background ---
	_bar_bg = ColorRect.new()
	_bar_bg.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar_bg.size = Vector2(BAR_W, BAR_H)
	_bar_bg.color = Color(0.1, 0.15, 0.2, 0.0)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_bar_bg)

	# --- Progress bar fill ---
	_bar_fill = ColorRect.new()
	_bar_fill.custom_minimum_size = Vector2(0, BAR_H)
	_bar_fill.size = Vector2(0, BAR_H)
	_bar_fill.color = Color(0.0, 0.75, 1.0, 0.0)  # Cyan primary
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_bar_fill)

	# --- Progress bar glow (slightly taller, behind fill for bloom effect) ---
	_bar_glow = ColorRect.new()
	_bar_glow.custom_minimum_size = Vector2(0, BAR_H + 4)
	_bar_glow.size = Vector2(0, BAR_H + 4)
	_bar_glow.color = Color(0.0, 0.6, 1.0, 0.0)
	_bar_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_bar_glow)

	# --- Step text (below bar) ---
	_step_label = Label.new()
	_step_label.text = Locale.t("splash.init")
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_medium:
		_step_label.add_theme_font_override("font", font_medium)
	_step_label.add_theme_font_size_override("font_size", 12)
	_step_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.6, 0.0))
	_step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_step_label)

	# --- Tip text (below step) ---
	_tip_label = Label.new()
	_tip_label.text = TIPS[randi() % TIPS.size()]
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_medium:
		_tip_label.add_theme_font_override("font", font_medium)
	_tip_label.add_theme_font_size_override("font_size", 13)
	_tip_label.add_theme_color_override("font_color", Color(0.25, 0.4, 0.5, 0.0))
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_tip_label)

	# --- Version ---
	_version_label = Label.new()
	_version_label.text = "v" + Constants.GAME_VERSION
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if font_medium:
		_version_label.add_theme_font_override("font", font_medium)
	_version_label.add_theme_font_size_override("font_size", 11)
	_version_label.add_theme_color_override("font_color", Color(0.2, 0.3, 0.38, 0.0))
	_version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_version_label)

	_layout.call_deferred()
	_phase = 0
	_phase_timer = 0.0


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var cx: float = vp.x * 0.5
	var block_top: float = vp.y * 0.5 - 150.0

	_logo.position = Vector2(cx - LOGO_SIZE * 0.5, block_top)
	_logo.pivot_offset = Vector2(LOGO_SIZE * 0.5, LOGO_SIZE * 0.5)

	var line_top_y: float = block_top + LOGO_SIZE + 20.0
	_line_top.position = Vector2(cx - 140.0, line_top_y)

	var title_y: float = line_top_y + 10.0
	_title_label.size = Vector2(vp.x, 42)
	_title_label.position = Vector2(0, title_y)

	var sub_y: float = title_y + 42.0 + 4.0
	_subtitle_label.size = Vector2(vp.x, 22)
	_subtitle_label.position = Vector2(0, sub_y)

	var line_bot_y: float = sub_y + 26.0
	_line_bottom.position = Vector2(cx - 80.0, line_bot_y)

	# Progress bar
	var bar_y: float = line_bot_y + 30.0
	_bar_bg.position = Vector2(cx - BAR_W * 0.5, bar_y)
	_bar_fill.position = Vector2(cx - BAR_W * 0.5, bar_y)
	_bar_glow.position = Vector2(cx - BAR_W * 0.5, bar_y - 2.0)

	# Step text
	_step_label.size = Vector2(vp.x, 18)
	_step_label.position = Vector2(0, bar_y + 14.0)

	# Tip text
	_tip_label.size = Vector2(vp.x * 0.5, 40)
	_tip_label.position = Vector2(vp.x * 0.25, bar_y + 38.0)

	# Version
	_version_label.size = Vector2(200, 18)
	_version_label.position = Vector2(vp.x - 220, vp.y - 36)


func _process(delta: float) -> void:
	_elapsed += delta
	_phase_timer += delta
	_update_stars(delta)

	match _phase:
		0:  # Fade in
			var t: float = clampf(_phase_timer / FADE_IN_DURATION, 0.0, 1.0)
			var e: float = _ease_out_cubic(t)
			_logo.modulate.a = e
			_logo.scale = Vector2.ONE * lerpf(1.08, 1.0, e)
			if _phase_timer >= FADE_IN_DURATION:
				_phase = 1
				_phase_timer = 0.0

		1:  # Text + bar reveal
			var t: float = clampf(_phase_timer / TEXT_REVEAL_DURATION, 0.0, 1.0)
			var e: float = _ease_out_cubic(t)

			_line_top.scale.x = e
			_line_top.pivot_offset.x = 140.0
			_line_top.color.a = e * 0.5

			var title_base_y: float = _line_top.position.y + 10.0
			_title_label.position.y = title_base_y + 8.0 * (1.0 - e)
			_set_label_alpha(_title_label, e)

			var st: float = clampf((_phase_timer - 0.15) / (TEXT_REVEAL_DURATION - 0.15), 0.0, 1.0)
			_set_label_alpha(_subtitle_label, _ease_out_cubic(st))

			var lt: float = clampf((_phase_timer - 0.2) / (TEXT_REVEAL_DURATION - 0.2), 0.0, 1.0)
			var le: float = _ease_out_cubic(lt)
			_line_bottom.scale.x = le
			_line_bottom.pivot_offset.x = 80.0
			_line_bottom.color.a = le * 0.35

			# Bar + step text
			var bt: float = clampf((_phase_timer - 0.25) / (TEXT_REVEAL_DURATION - 0.25), 0.0, 1.0)
			var be: float = _ease_out_cubic(bt)
			_bar_bg.color.a = be * 0.35
			_bar_fill.color.a = be * 0.9
			_bar_glow.color.a = be * 0.15
			_set_label_alpha(_step_label, be * 0.6)
			_set_label_alpha(_tip_label, be * 0.35)
			_set_label_alpha(_version_label, e * 0.3)

			if _phase_timer >= TEXT_REVEAL_DURATION:
				_phase = 2
				_phase_timer = 0.0

		2:  # Hold — wait for dismiss
			# Pulse the glow
			var pulse: float = 0.1 + 0.08 * sin(_elapsed * 2.0)
			_bar_glow.color.a = pulse
			if _phase_timer >= HOLD_DURATION:
				_min_display_done = true
			if _min_display_done and _ready_to_dismiss:
				_phase = 3
				_phase_timer = 0.0

		3:  # Fade out
			var t: float = clampf(_phase_timer / FADE_OUT_DURATION, 0.0, 1.0)
			var e: float = _ease_in_cubic(t)
			_bg.modulate.a = 1.0 - e
			if _phase_timer >= FADE_OUT_DURATION:
				_phase = 4
				finished.emit()
				queue_free()


func _update_stars(delta: float) -> void:
	for sd in _stars:
		var node: ColorRect = sd["node"]
		var twinkle: float = (1.0 + sin(_elapsed * sd["speed"] + sd["phase"])) * 0.5
		var target_a: float = sd["base_alpha"] * twinkle
		if _elapsed < 0.4:
			target_a *= _elapsed / 0.4
		if _phase == 3:
			target_a *= 1.0 - clampf(_phase_timer / FADE_OUT_DURATION, 0.0, 1.0)
		node.color.a = target_a
		node.position.x += sd["drift_x"] * delta * 0.2
		node.position.y += sd["drift_y"] * delta * 0.2


## Set the current loading step text and progress (0.0 to 1.0).
## Progress bar animates smoothly to the target value.
func set_step(text: String, progress: float) -> void:
	_target_progress = clampf(progress, 0.0, 1.0)
	if _step_label:
		_step_label.text = text
	# Tween the visual progress
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_bar_tween.tween_method(_set_progress, _progress, _target_progress, BAR_TWEEN_DURATION)


func _set_progress(value: float) -> void:
	_progress = value
	var fill_w: float = BAR_W * _progress
	_bar_fill.size.x = fill_w
	_bar_fill.custom_minimum_size.x = fill_w
	_bar_glow.size.x = fill_w
	_bar_glow.custom_minimum_size.x = fill_w


## Call when the game is ready. Splash fades out after min display + progress 1.0.
func dismiss() -> void:
	_ready_to_dismiss = true


func _set_label_alpha(label: Label, alpha: float) -> void:
	var c: Color = label.get_theme_color("font_color")
	c.a = alpha
	label.add_theme_color_override("font_color", c)


static func _ease_out_cubic(t: float) -> float:
	var inv: float = 1.0 - t
	return 1.0 - inv * inv * inv


static func _ease_in_cubic(t: float) -> float:
	return t * t * t
