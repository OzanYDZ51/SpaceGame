class_name FlightHUD
extends Control

# =============================================================================
# Flight HUD - Immersive sci-fi cockpit display
# Holographic aesthetic with decorated headers, segmented bars, diamond accents
# =============================================================================

var _ship: ShipController = null
var _health_system: HealthSystem = null
var _energy_system: EnergySystem = null
var _targeting_system: TargetingSystem = null
var _weapon_manager: WeaponManager = null

var _crosshair: Control = null
var _cockpit_overlay: Control = null
var _speed_arc: Control = null
var _left_panel: Control = null
var _right_panel: Control = null
var _top_bar: Control = null
var _compass: Control = null
var _warnings: Control = null
var _target_overlay: Control = null

# Target info panel (bottom-right, directional shields)
var _weapon_panel: Control = null
var _target_panel: Control = null
var _dock_prompt: Control = null
var _loot_prompt: Control = null
var _nav_markers: Control = null
var _radar: Control = null
var _target_shield_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _target_hull_flash: float = 0.0
var _connected_target_health: HealthSystem = null
var _prev_target_shields: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_target_hull: float = 0.0
var _last_tracked_target: Node3D = null
var _docking_system: DockingSystem = null
var _loot_pickup: LootPickupSystem = null

var _sil_verts: PackedVector3Array = PackedVector3Array()
var _silhouette_ship: Node3D = null
# Cached weapon panel geometry (recomputed only on ship change)
var _cached_hull: PackedVector2Array = PackedVector2Array()
var _cached_hp_screen: Array[Vector2] = []
var _cached_hp_label_dirs: Array[Vector2] = []
var _cached_wp_size: Vector2 = Vector2.ZERO

var _scan_line_y: float = 0.0
var _pulse_t: float = 0.0
var _warning_flash: float = 0.0
var _boot_alpha: float = 0.0
var _boot_done: bool = false

# --- HUD redraw throttle ---
const HUD_SLOW_INTERVAL: float = 0.1  # 10 Hz for radar/nav/weapon panel
var _slow_timer: float = 0.0
var _slow_dirty: bool = true  # Force first draw

# --- Hit Markers ---
# Each entry: {"type": int, "t": float (1→0), "intensity": float, "shield_ratio": float}
var _hit_markers: Array[Dictionary] = []
const HIT_MARKER_DURATION_SHIELD := 0.28
const HIT_MARKER_DURATION_HULL := 0.35
const HIT_MARKER_DURATION_KILL := 0.7
const HIT_MARKER_DURATION_BREAK := 0.35
const HIT_MARKER_MAX := 6  # Max stacked markers

# Colors for hit markers
var COL_HIT_SHIELD: Color:
	get: return Color(0.3, 0.7, 1.0, 1.0)  # Bright cyan-blue
var COL_HIT_SHIELD_LOW: Color:
	get: return Color(1.0, 0.5, 0.15, 1.0)  # Orange (shields depleting)
var COL_HIT_HULL: Color:
	get: return Color(1.0, 0.15, 0.1, 1.0)  # Aggressive red
var COL_HIT_KILL: Color:
	get: return Color(1.0, 0.85, 0.2, 1.0)  # Gold
var COL_HIT_BREAK: Color:
	get: return Color(1.0, 0.4, 0.05, 1.0)  # Deep orange

# Colors — now sourced from UITheme autoload (unified palette)
var COL_PRIMARY: Color:
	get: return UITheme.PRIMARY
var COL_PRIMARY_DIM: Color:
	get: return UITheme.PRIMARY_DIM
var COL_PRIMARY_FAINT: Color:
	get: return UITheme.PRIMARY_FAINT
var COL_HEADER: Color:
	get: return UITheme.HEADER
var COL_ACCENT: Color:
	get: return UITheme.ACCENT
var COL_WARN: Color:
	get: return UITheme.WARNING
var COL_DANGER: Color:
	get: return UITheme.DANGER
var COL_BOOST: Color:
	get: return UITheme.BOOST
var COL_CRUISE: Color:
	get: return UITheme.CRUISE
var COL_BG: Color:
	get: return UITheme.BG
var COL_BG_DARK: Color:
	get: return UITheme.BG_DARK
var COL_BORDER: Color:
	get: return UITheme.BORDER
var COL_SCANLINE: Color:
	get: return UITheme.SCANLINE
var COL_TEXT: Color:
	get: return UITheme.TEXT
var COL_TEXT_DIM: Color:
	get: return UITheme.TEXT_DIM
var COL_SHIELD: Color:
	get: return UITheme.SHIELD
var COL_TARGET: Color:
	get: return UITheme.TARGET
var COL_LEAD: Color:
	get: return UITheme.LEAD


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud()

func set_ship(s: ShipController) -> void: _ship = s
func set_health_system(h: HealthSystem) -> void: _health_system = h
func set_energy_system(e: EnergySystem) -> void: _energy_system = e
func set_targeting_system(t: TargetingSystem) -> void: _targeting_system = t
func set_weapon_manager(w: WeaponManager) -> void:
	if _weapon_manager and _weapon_manager.hit_landed.is_connected(_on_hit_landed):
		_weapon_manager.hit_landed.disconnect(_on_hit_landed)
	_weapon_manager = w
	if _weapon_manager:
		_weapon_manager.hit_landed.connect(_on_hit_landed)
func set_docking_system(d: DockingSystem) -> void: _docking_system = d
func set_loot_pickup_system(lps: LootPickupSystem) -> void: _loot_pickup = lps


func _build_hud() -> void:
	_crosshair = _make_ctrl(0.5, 0.5, 0.5, 0.5, -40, -40, 40, 40)
	_crosshair.draw.connect(_draw_crosshair.bind(_crosshair))
	add_child(_crosshair)

	_speed_arc = _make_ctrl(0.5, 1.0, 0.5, 1.0, -160, -130, 160, -10)
	_speed_arc.draw.connect(_draw_speed_arc.bind(_speed_arc))
	add_child(_speed_arc)

	_left_panel = _make_ctrl(0.0, 0.5, 0.0, 0.5, 16, -195, 242, 195)
	_left_panel.draw.connect(_draw_left_panel.bind(_left_panel))
	add_child(_left_panel)

	_right_panel = _make_ctrl(1.0, 0.5, 1.0, 0.5, -242, -120, -16, 120)
	_right_panel.draw.connect(_draw_right_panel.bind(_right_panel))
	add_child(_right_panel)

	_top_bar = _make_ctrl(0.5, 0.0, 0.5, 0.0, -200, 10, 200, 50)
	_top_bar.draw.connect(_draw_top_bar.bind(_top_bar))
	add_child(_top_bar)

	_compass = _make_ctrl(0.5, 0.0, 0.5, 0.0, -120, 52, 120, 72)
	_compass.draw.connect(_draw_compass.bind(_compass))
	add_child(_compass)

	_warnings = _make_ctrl(0.5, 0.5, 0.5, 0.5, -150, 60, 150, 100)
	_warnings.draw.connect(_draw_warnings.bind(_warnings))
	add_child(_warnings)

	_target_overlay = _make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_target_overlay.draw.connect(_draw_target_overlay.bind(_target_overlay))
	add_child(_target_overlay)

	_weapon_panel = _make_ctrl(0.5, 1.0, 0.5, 1.0, 140, -195, 390, -10)
	_weapon_panel.draw.connect(_draw_weapon_panel.bind(_weapon_panel))
	add_child(_weapon_panel)

	_target_panel = _make_ctrl(1.0, 1.0, 1.0, 1.0, -244, -270, -16, -16)
	_target_panel.draw.connect(_draw_target_info_panel.bind(_target_panel))
	_target_panel.visible = false
	add_child(_target_panel)

	_dock_prompt = _make_ctrl(0.5, 0.5, 0.5, 0.5, -100, 55, 100, 90)
	_dock_prompt.draw.connect(_draw_dock_prompt.bind(_dock_prompt))
	_dock_prompt.visible = false
	add_child(_dock_prompt)

	_loot_prompt = _make_ctrl(0.5, 0.5, 0.5, 0.5, -100, 95, 100, 130)
	_loot_prompt.draw.connect(_draw_loot_prompt.bind(_loot_prompt))
	_loot_prompt.visible = false
	add_child(_loot_prompt)

	_nav_markers = _make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_nav_markers.draw.connect(_draw_nav_markers.bind(_nav_markers))
	add_child(_nav_markers)

	_radar = _make_ctrl(1.0, 0.0, 1.0, 0.0, -210, 8, -16, 210)
	_radar.draw.connect(_draw_radar.bind(_radar))
	add_child(_radar)

	_cockpit_overlay = _make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_cockpit_overlay.draw.connect(_draw_cockpit_hud.bind(_cockpit_overlay))
	_cockpit_overlay.visible = false
	add_child(_cockpit_overlay)


func _process(delta: float) -> void:
	_pulse_t += delta
	_scan_line_y = fmod(_scan_line_y + delta * 80.0, get_viewport_rect().size.y)
	_warning_flash += delta * 3.0

	# Throttle: expensive panels redraw at 10 Hz, cheap ones at full rate
	_slow_timer += delta
	if _slow_timer >= HUD_SLOW_INTERVAL:
		_slow_timer -= HUD_SLOW_INTERVAL
		_slow_dirty = true

	if not _boot_done:
		_boot_alpha = min(_boot_alpha + delta * 0.8, 1.0)
		if _boot_alpha >= 1.0:
			_boot_done = true
		modulate.a = _boot_alpha

	# Detect cockpit mode
	var cam := get_viewport().get_camera_3d()
	var is_cockpit: bool = cam is ShipCamera and (cam as ShipCamera).camera_mode == ShipCamera.CameraMode.COCKPIT

	# Toggle HUD layers
	_crosshair.visible = not is_cockpit
	_speed_arc.visible = not is_cockpit
	_left_panel.visible = not is_cockpit
	_right_panel.visible = not is_cockpit
	_top_bar.visible = not is_cockpit
	_compass.visible = not is_cockpit
	_weapon_panel.visible = not is_cockpit
	_cockpit_overlay.visible = is_cockpit

	# Target tracking & flash decay
	var current_target: Node3D = null
	if _targeting_system and _targeting_system.current_target and is_instance_valid(_targeting_system.current_target):
		current_target = _targeting_system.current_target
	_track_target(current_target)

	for i in 4:
		_target_shield_flash[i] = maxf(_target_shield_flash[i] - delta * 3.0, 0.0)
	_target_hull_flash = maxf(_target_hull_flash - delta * 3.0, 0.0)

	# Hit marker decay
	_update_hit_markers(delta)

	# Fast controls: redraw every frame (cheap: crosshair, warnings, target box)
	# Slow controls: redraw at 10 Hz (expensive: radar, nav, weapon panel, panels)
	if is_cockpit:
		_cockpit_overlay.queue_redraw()
		_warnings.queue_redraw()
		_target_overlay.queue_redraw()
		if _slow_dirty:
			_nav_markers.queue_redraw()
			_radar.queue_redraw()
	else:
		# Fast: crosshair, warnings, target_overlay (small, cheap draws)
		_crosshair.queue_redraw()
		_warnings.queue_redraw()
		_target_overlay.queue_redraw()
		# Slow: everything else (entity queries, complex geometry)
		if _slow_dirty:
			_speed_arc.queue_redraw()
			_left_panel.queue_redraw()
			_right_panel.queue_redraw()
			_top_bar.queue_redraw()
			_compass.queue_redraw()
			_weapon_panel.queue_redraw()
			_nav_markers.queue_redraw()
			_radar.queue_redraw()

	if _slow_dirty:
		_slow_dirty = false

	if _target_panel:
		_target_panel.visible = current_target != null and not is_cockpit
		if _target_panel.visible:
			_target_panel.queue_redraw()

	if _dock_prompt:
		var show_dock: bool = _docking_system != null and _docking_system.can_dock and not _docking_system.is_docked
		_dock_prompt.visible = show_dock
		if show_dock:
			_dock_prompt.queue_redraw()

	if _loot_prompt:
		var show_loot: bool = _loot_pickup != null and _loot_pickup.can_pickup
		_loot_prompt.visible = show_loot
		if show_loot:
			_loot_prompt.queue_redraw()


# =============================================================================
# DECORATIVE HELPERS
# =============================================================================
func _draw_diamond(ctrl: Control, pos: Vector2, sz: float, col: Color) -> void:
	ctrl.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -sz), pos + Vector2(sz, 0),
		pos + Vector2(0, sz), pos + Vector2(-sz, 0),
	]), col)


func _draw_section_header(ctrl: Control, font: Font, x: float, y: float, w: float, text: String) -> float:
	ctrl.draw_rect(Rect2(x, y - 11, 3, 14), COL_PRIMARY)
	ctrl.draw_string(font, Vector2(x + 9, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_HEADER)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var lx := x + 9 + tw + 8
	if lx < x + w:
		ctrl.draw_line(Vector2(lx, y - 4), Vector2(x + w, y - 4), COL_PRIMARY_DIM, 1.0)
	return y + 18


# =============================================================================
# DOCKING PROMPT
# =============================================================================
func _draw_dock_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(_pulse_t * 3.0) * 0.3

	# Background
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.0, 0.02, 0.06, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.3 * pulse), false, 1.0)

	# Station name (small, dim)
	if _docking_system:
		ctrl.draw_string(font, Vector2(0, 13), _docking_system.nearest_station_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 9, COL_TEXT_DIM * Color(1, 1, 1, pulse))

	# "DOCKER [F]" main text
	var dock_col := Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "DOCKER  [F]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, dock_col)

	# Small diamonds flanking the text
	var tw: float = font.get_string_size("DOCKER  [F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var dy: float = 24.0
	_draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, dock_col)
	_draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, dock_col)


# =============================================================================
# LOOT PROMPT
# =============================================================================
func _draw_loot_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := ThemeDB.fallback_font
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(_pulse_t * 3.0) * 0.3

	# Background (yellow-orange tint)
	var loot_col := Color(1.0, 0.7, 0.2)
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.06, 0.04, 0.0, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(loot_col.r, loot_col.g, loot_col.b, 0.3 * pulse), false, 1.0)

	# Crate info (small, dim)
	if _loot_pickup and _loot_pickup.nearest_crate:
		var summary: String = _loot_pickup.nearest_crate.get_contents_summary()
		ctrl.draw_string(font, Vector2(0, 13), summary.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 9, COL_TEXT_DIM * Color(1, 1, 1, pulse))

	# "SOUTE [X]" main text
	var text_col := Color(loot_col.r, loot_col.g, loot_col.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "SOUTE  [X]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, text_col)

	# Small diamonds flanking the text
	var tw: float = font.get_string_size("SOUTE  [X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var dy: float = 24.0
	_draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	_draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


# =============================================================================
# HIT MARKERS
# =============================================================================
func _on_hit_landed(hit_type: int, damage_amount: float, shield_ratio: float) -> void:
	# Cap stacked markers
	if _hit_markers.size() >= HIT_MARKER_MAX:
		_hit_markers.pop_front()
	var intensity := clampf(damage_amount / 30.0, 0.6, 2.5)
	_hit_markers.append({
		"type": hit_type,
		"t": 1.0,
		"intensity": intensity,
		"shield_ratio": shield_ratio,
	})


func _update_hit_markers(delta: float) -> void:
	var i := _hit_markers.size() - 1
	while i >= 0:
		var m: Dictionary = _hit_markers[i]
		var dur: float
		match m["type"]:
			WeaponManager.HitType.SHIELD:
				dur = HIT_MARKER_DURATION_SHIELD
			WeaponManager.HitType.HULL:
				dur = HIT_MARKER_DURATION_HULL
			WeaponManager.HitType.KILL:
				dur = HIT_MARKER_DURATION_KILL
			WeaponManager.HitType.SHIELD_BREAK:
				dur = HIT_MARKER_DURATION_BREAK
			_:
				dur = 0.3
		m["t"] -= delta / dur
		if m["t"] <= 0.0:
			_hit_markers.remove_at(i)
		i -= 1


func _draw_hit_markers(ctrl: Control, center: Vector2) -> void:
	for m in _hit_markers:
		var t: float = m["t"]
		var hit_type: int = m["type"]
		var intensity: float = m["intensity"]
		var sr: float = m["shield_ratio"]

		match hit_type:
			WeaponManager.HitType.SHIELD:
				_draw_shield_tick(ctrl, center, t, intensity, sr)
			WeaponManager.HitType.HULL:
				_draw_hull_tick(ctrl, center, t, intensity)
			WeaponManager.HitType.KILL:
				_draw_kill_tick(ctrl, center, t, intensity)
			WeaponManager.HitType.SHIELD_BREAK:
				_draw_shield_break_tick(ctrl, center, t, intensity)


func _draw_shield_tick(ctrl: Control, c: Vector2, t: float, intensity: float, shield_ratio: float) -> void:
	# Cyan-blue diagonal ticks that expand outward — lerp to orange if shield low
	var col := COL_HIT_SHIELD.lerp(COL_HIT_SHIELD_LOW, clampf(1.0 - shield_ratio, 0.0, 1.0))
	# Flash: bright white at start, fade to color
	var flash := clampf((t - 0.7) / 0.3, 0.0, 1.0)  # 1.0 in first 30% of lifetime
	col = col.lerp(Color.WHITE, flash * 0.6)
	# Alpha easing: fast at start, smooth at end
	var alpha := t * t  # quadratic ease-out
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap := 8.0 + (1.0 - t) * 7.0 * intensity  # Expands outward
	var tick_len := 7.0 + intensity * 3.0
	var width := 2.2 * t + 0.5

	# 4 diagonal ticks (45-degree angles)
	var diag := 0.7071  # sin(45) = cos(45)
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir := Vector2(sign_x * diag, sign_y * diag)
			var p1 := c + dir * base_gap
			var p2 := c + dir * (base_gap + tick_len)
			ctrl.draw_line(p1, p2, col, width)

	# Inner glow ring (subtle)
	if flash > 0.0:
		var ring_col := col * Color(1, 1, 1, flash * 0.3)
		ctrl.draw_arc(c, base_gap - 2.0, 0, TAU, 16, ring_col, 1.0)


func _draw_hull_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	# Aggressive red X-marks — tighter, sharper
	var col := COL_HIT_HULL
	var flash := clampf((t - 0.65) / 0.35, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.5)
	var alpha := t * t
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap := 6.0 + (1.0 - t) * 10.0 * intensity
	var tick_len := 9.0 + intensity * 4.0
	var width := 2.5 * t + 0.8

	# 4 diagonal X-marks (same 45-degree but thicker, more aggressive)
	var diag := 0.7071
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir := Vector2(sign_x * diag, sign_y * diag)
			var p1 := c + dir * base_gap
			var p2 := c + dir * (base_gap + tick_len)
			ctrl.draw_line(p1, p2, col, width)
			# Second line slightly offset for thickness feel
			var perp := Vector2(-dir.y, dir.x) * 1.0
			ctrl.draw_line(p1 + perp, p2 + perp, col * Color(1, 1, 1, 0.4), width * 0.5)

	# Red center dot pulse on hull hit
	if flash > 0.2:
		var dot_col := COL_HIT_HULL * Color(1, 1, 1, (flash - 0.2) * 0.6)
		ctrl.draw_circle(c, 2.5 * flash, dot_col)


func _draw_kill_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	# Gold starburst — 8 marks (cardinal + diagonal), wider, longer, with center flash
	var col := COL_HIT_KILL
	var flash := clampf((t - 0.6) / 0.4, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.7)
	var alpha: float
	if t > 0.4:
		alpha = 1.0
	else:
		alpha = t / 0.4  # Hold full brightness longer, then fade
	col.a = alpha

	var base_gap := 7.0 + (1.0 - t) * 14.0
	var tick_len := 11.0 + intensity * 4.0
	var width := 2.8 * minf(t * 2.0, 1.0) + 0.5

	# 8 marks: cardinal + diagonal
	var angles: Array[float] = [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, PI * 1.25, PI * 1.5, PI * 1.75]
	for angle in angles:
		var dir := Vector2(cos(angle), sin(angle))
		var p1 := c + dir * base_gap
		var p2 := c + dir * (base_gap + tick_len)
		ctrl.draw_line(p1, p2, col, width)

	# Center flash ring
	if flash > 0.0:
		var ring_r := 4.0 + (1.0 - flash) * 12.0
		var ring_col := COL_HIT_KILL * Color(1, 1, 1, flash * 0.5)
		ctrl.draw_arc(c, ring_r, 0, TAU, 24, ring_col, 1.5)

	# Inner bright core
	if t > 0.7:
		var core_a := (t - 0.7) / 0.3
		ctrl.draw_circle(c, 3.5 * core_a, Color(1.0, 0.95, 0.8, core_a * 0.7))


func _draw_shield_break_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	# Orange crackling marks — shield shattering feel
	var col := COL_HIT_BREAK
	var flash := clampf((t - 0.6) / 0.4, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.5)
	var alpha := t * t
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap := 7.0 + (1.0 - t) * 12.0 * intensity
	var tick_len := 8.0 + intensity * 3.0
	var width := 2.0 * t + 0.6

	# 4 diagonal marks with jagged offset for "breaking" feel
	var diag := 0.7071
	var jitter := sin(t * 30.0) * 1.5  # Fast oscillation for electric feel
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir := Vector2(sign_x * diag, sign_y * diag)
			var perp := Vector2(-dir.y, dir.x)
			var p1 := c + dir * base_gap + perp * jitter
			var p2 := c + dir * (base_gap + tick_len) - perp * jitter
			ctrl.draw_line(p1, p2, col, width)

	# Breaking ring fragments
	if flash > 0.0:
		var arc_r := base_gap - 1.0
		var arc_col := COL_HIT_BREAK * Color(1, 1, 1, flash * 0.4)
		for i in 4:
			var start_angle := float(i) * PI * 0.5 + 0.3
			ctrl.draw_arc(c, arc_r, start_angle, start_angle + 0.5, 6, arc_col, 1.2)


# =============================================================================
# CROSSHAIR
# =============================================================================
func _draw_crosshair(ctrl: Control) -> void:
	var c := ctrl.size / 2.0
	var pulse: float = sin(_pulse_t * 2.0) * 0.1 + 0.9
	var col := COL_PRIMARY * Color(1, 1, 1, pulse)
	var gap := 5.0
	var line_len := 12.0
	ctrl.draw_line(c + Vector2(0, -gap), c + Vector2(0, -gap - line_len), col, 1.5)
	ctrl.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + line_len), col, 1.5)
	ctrl.draw_line(c + Vector2(-gap, 0), c + Vector2(-gap - line_len, 0), col, 1.5)
	ctrl.draw_line(c + Vector2(gap, 0), c + Vector2(gap + line_len, 0), col, 1.5)
	ctrl.draw_circle(c, 1.5, col)

	# Draw hit markers on top of crosshair
	_draw_hit_markers(ctrl, c)


# =============================================================================
# SPEED ARC
# =============================================================================
func _draw_speed_arc(ctrl: Control) -> void:
	if _ship == null:
		return
	var cx := ctrl.size.x / 2.0
	var cy := ctrl.size.y + 20.0
	var r := 120.0
	var a0 := PI + 0.4
	var a1 := TAU - 0.4
	var ar := a1 - a0

	ctrl.draw_arc(Vector2(cx, cy), r, a0, a1, 48, COL_PRIMARY_FAINT, 3.0, true)
	ctrl.draw_arc(Vector2(cx, cy), r - 8, a0, a1, 48, COL_PRIMARY_FAINT, 1.0, true)

	var max_spd := Constants.get_max_speed(_ship.speed_mode)
	for i in 11:
		var t := float(i) / 10.0
		var angle := a0 + t * ar
		var p1 := Vector2(cx + cos(angle) * (r - 12), cy + sin(angle) * (r - 12))
		var p2 := Vector2(cx + cos(angle) * (r - 4), cy + sin(angle) * (r - 4))
		ctrl.draw_line(p1, p2, COL_PRIMARY if (i == 0 or i == 10 or i == 5) else COL_PRIMARY_DIM, 1.0)

	var ratio: float = clamp(_ship.current_speed / max_spd, 0.0, 1.0)
	if ratio > 0.01:
		var fe := a0 + ratio * ar
		var fc := _get_mode_color()
		ctrl.draw_arc(Vector2(cx, cy), r - 4, a0, fe, 32, fc, 5.0, true)
		ctrl.draw_circle(Vector2(cx + cos(fe) * (r - 4), cy + sin(fe) * (r - 4)), 3.0, fc)

	var font := ThemeDB.fallback_font
	var st: String = "%.1f" % _ship.current_speed if _ship.current_speed < 10.0 else "%.0f" % _ship.current_speed
	var sw := font.get_string_size(st, HORIZONTAL_ALIGNMENT_CENTER, -1, 28).x
	ctrl.draw_string(font, Vector2(cx - sw / 2.0, cy - 50), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COL_TEXT)
	ctrl.draw_string(font, Vector2(cx - 15, cy - 35), "M/S", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_DIM)

	var mt := _get_mode_text()
	var mc := _get_mode_color()
	var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	ctrl.draw_string(font, Vector2(cx - mw / 2.0, cy - 20), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, mc)
	ctrl.draw_line(Vector2(cx - mw / 2.0 - 18, cy - 26), Vector2(cx - mw / 2.0 - 4, cy - 26), mc * Color(1, 1, 1, 0.5), 1.0)
	ctrl.draw_line(Vector2(cx + mw / 2.0 + 4, cy - 26), Vector2(cx + mw / 2.0 + 18, cy - 26), mc * Color(1, 1, 1, 0.5), 1.0)

	var mx := "%.0f" % max_spd
	var mxw := font.get_string_size(mx, HORIZONTAL_ALIGNMENT_CENTER, -1, 10).x
	var mp := Vector2(cx + cos(a1) * (r + 14), cy + sin(a1) * (r + 14))
	ctrl.draw_string(font, mp - Vector2(mxw / 2.0, 0), mx, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)


# =============================================================================
# LEFT PANEL - Systems + Shield Diamond + Energy Pips
# =============================================================================
func _draw_left_panel(ctrl: Control) -> void:
	_draw_panel_bg(ctrl)
	var font := ThemeDB.fallback_font
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var y := 22.0

	y = _draw_section_header(ctrl, font, x, y, w, "SYSTÈMES")
	y += 2

	# Hull — label left, pct right, bar below
	var hull_r := _health_system.get_hull_ratio() if _health_system else 1.0
	var hull_c := COL_ACCENT if hull_r > 0.5 else (COL_WARN if hull_r > 0.25 else COL_DANGER)
	ctrl.draw_string(font, Vector2(x, y), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	var hp := "%d%%" % int(hull_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hull_c)
	y += 8
	_draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)
	y += 20

	# Shield
	var shd_r := _health_system.get_total_shield_ratio() if _health_system else 0.85
	ctrl.draw_string(font, Vector2(x, y), "BOUCLIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	var sp := "%d%%" % int(shd_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_SHIELD)
	y += 8
	_draw_bar(ctrl, Vector2(x, y), w, shd_r, COL_SHIELD)
	y += 20

	# Energy
	var nrg_r := _energy_system.get_energy_ratio() if _energy_system else 0.7
	var nrg_c := Color(0.2, 0.6, 1.0, 0.9)
	ctrl.draw_string(font, Vector2(x, y), "ÉNERGIE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	var np := "%d%%" % int(nrg_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(np, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), np, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, nrg_c)
	y += 8
	_draw_bar(ctrl, Vector2(x, y), w, nrg_r, nrg_c)
	y += 24

	# Shield Diamond
	_draw_shield_diamond(ctrl, Vector2(x + w / 2.0, y + 38.0))
	y += 86

	# Energy Pips (segmented)
	_draw_energy_pips(ctrl, Vector2(x, y))
	y += 62

	# Flight Assist with status dot
	if _ship:
		if _ship.flight_assist:
			ctrl.draw_circle(Vector2(x + 4, y - 3), 3.5, COL_ACCENT)
			ctrl.draw_string(font, Vector2(x + 13, y), "AV ACTIF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_ACCENT)
		else:
			var flash: float = abs(sin(_warning_flash)) * 0.5 + 0.5
			var fc := COL_DANGER * Color(1, 1, 1, flash)
			ctrl.draw_circle(Vector2(x + 4, y - 3), 3.5, fc)
			ctrl.draw_string(font, Vector2(x + 13, y), "AV DÉSACTIVÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)


# =============================================================================
# SHIELD DIAMOND - Player's own 4 directional shields
# =============================================================================
func _draw_shield_diamond(ctrl: Control, center: Vector2) -> void:
	if _health_system == null:
		return
	var sz := 32.0

	# Breathing glow ring
	var glow_a := sin(_pulse_t * 1.2) * 0.08 + 0.12
	ctrl.draw_arc(center, sz + 6, 0, TAU, 32, COL_SHIELD * Color(1, 1, 1, glow_a), 1.5, true)
	# Rotating scan arc
	var scan_a := fmod(_pulse_t * 1.5, TAU)
	ctrl.draw_arc(center, sz + 6, scan_a, scan_a + 0.7, 10, COL_PRIMARY_DIM, 1.5, true)

	var pts := [
		center + Vector2(0, -sz), center + Vector2(sz, 0),
		center + Vector2(0, sz), center + Vector2(-sz, 0),
	]
	var facings := [
		HealthSystem.ShieldFacing.FRONT, HealthSystem.ShieldFacing.RIGHT,
		HealthSystem.ShieldFacing.REAR, HealthSystem.ShieldFacing.LEFT,
	]
	for i in 4:
		var ratio := _health_system.get_shield_ratio(facings[i])
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % 4]
		ctrl.draw_line(p1, p2, COL_PRIMARY_FAINT, 3.0)
		if ratio > 0.01:
			ctrl.draw_line(p1, p1.lerp(p2, ratio), COL_SHIELD if ratio > 0.3 else COL_WARN, 3.0)

	# Ship icon
	var ts := 9.0
	ctrl.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -ts), center + Vector2(ts * 0.6, ts * 0.5), center + Vector2(-ts * 0.6, ts * 0.5),
	]), COL_PRIMARY_DIM)

	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, center + Vector2(-6, -sz - 6), "AV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(sz + 5, 4), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-6, sz + 14), "AR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-sz - 14, 4), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)


# =============================================================================
# ENERGY PIPS - Segmented bars (4 segments each)
# =============================================================================
func _draw_energy_pips(ctrl: Control, pos: Vector2) -> void:
	if _energy_system == null:
		return
	var font := ThemeDB.fallback_font
	var num_seg := 4
	var seg_w := 22.0
	var seg_gap := 3.0
	var bar_h := 9.0
	var total_w := num_seg * seg_w + (num_seg - 1) * seg_gap
	var spacing := 20.0
	var bar_x := pos.x + 34.0

	var pips := [
		{name = "ARM", value = _energy_system.pip_weapons, color = COL_DANGER},
		{name = "BCL", value = _energy_system.pip_shields, color = COL_SHIELD},
		{name = "MOT", value = _energy_system.pip_engines, color = COL_ACCENT},
	]
	for i in pips.size():
		var py := pos.y + i * spacing
		ctrl.draw_string(font, Vector2(pos.x, py + bar_h - 1), pips[i].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)
		var val: float = clamp(pips[i].value, 0.0, 1.0)
		for s in num_seg:
			var sx := bar_x + s * (seg_w + seg_gap)
			ctrl.draw_rect(Rect2(sx, py, seg_w, bar_h), COL_BG_DARK)
			var seg_start := float(s) / float(num_seg)
			var seg_end := float(s + 1) / float(num_seg)
			if val >= seg_end - 0.01:
				ctrl.draw_rect(Rect2(sx, py, seg_w, bar_h), pips[i].color)
			elif val > seg_start:
				ctrl.draw_rect(Rect2(sx, py, seg_w * (val - seg_start) * float(num_seg), bar_h), pips[i].color)
		var pct := "%d%%" % int(val * 100)
		ctrl.draw_string(font, Vector2(bar_x + total_w + 6, py + bar_h - 1), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)


# =============================================================================
# WEAPON PANEL - Real mesh silhouette with hardpoint markers (BSG Online style)
# =============================================================================
func _rebuild_silhouette() -> void:
	_silhouette_ship = _ship
	_sil_verts = PackedVector3Array()
	_cached_hull = PackedVector2Array()
	_cached_hp_screen = []
	_cached_hp_label_dirs = []
	_cached_wp_size = Vector2.ZERO
	if _ship == null:
		return
	var model := _ship.get_node_or_null("ShipModel") as ShipModel
	if model:
		_sil_verts = model.get_silhouette_points()


func _rebuild_weapon_panel_cache(s: Vector2) -> void:
	_cached_wp_size = s
	_cached_hull = PackedVector2Array()
	_cached_hp_screen = []
	_cached_hp_label_dirs = []

	if _weapon_manager == null or _ship == null or _ship.ship_data == null:
		return
	var hp_count := _weapon_manager.get_hardpoint_count()
	var hp_defs: Array = _ship.ship_data.hardpoints
	if hp_count == 0 or hp_defs.is_empty():
		return

	var sil_area_w := 140.0
	var header_h := 20.0
	var footer_h := 22.0
	var a_l := 10.0
	var a_t := header_h + 2.0
	var a_r := sil_area_w - 6.0
	var a_b := s.y - footer_h - 2.0
	var a_w := a_r - a_l
	var a_h := a_b - a_t
	var a_cx := (a_l + a_r) * 0.5
	var a_cy := (a_t + a_b) * 0.5
	const Y_FOLD := 0.3

	var sil_2d := PackedVector2Array()
	for v in _sil_verts:
		sil_2d.append(Vector2(v.x, -v.z + v.y * Y_FOLD))

	var hp_2d: Array[Vector2] = []
	for i in mini(hp_count, hp_defs.size()):
		var p: Vector3 = hp_defs[i]["position"]
		hp_2d.append(Vector2(p.x, -p.z + p.y * Y_FOLD))

	if sil_2d.size() >= 3:
		_cached_hull = Geometry2D.convex_hull(sil_2d)

	var sil_min := Vector2(INF, INF)
	var sil_max := Vector2(-INF, -INF)
	if _cached_hull.size() >= 3:
		for pt in _cached_hull:
			sil_min = Vector2(minf(sil_min.x, pt.x), minf(sil_min.y, pt.y))
			sil_max = Vector2(maxf(sil_max.x, pt.x), maxf(sil_max.y, pt.y))
	for pt in hp_2d:
		sil_min = Vector2(minf(sil_min.x, pt.x - 5.0), minf(sil_min.y, pt.y - 5.0))
		sil_max = Vector2(maxf(sil_max.x, pt.x + 5.0), maxf(sil_max.y, pt.y + 5.0))

	var sil_w := maxf(sil_max.x - sil_min.x, 1.0)
	var sil_h := maxf(sil_max.y - sil_min.y, 1.0)
	var sil_cx := (sil_min.x + sil_max.x) * 0.5
	var sil_cy := (sil_min.y + sil_max.y) * 0.5
	var sc := minf(a_w / sil_w, a_h / sil_h) * 0.82

	var hp_count_actual := mini(hp_count, hp_2d.size())
	for i in hp_count_actual:
		_cached_hp_screen.append(Vector2(
			a_cx + (hp_2d[i].x - sil_cx) * sc,
			a_cy + (hp_2d[i].y - sil_cy) * sc
		))

	# Separate overlapping hardpoints
	var min_dist := 16.0
	for _iter in 6:
		var moved := false
		for i in _cached_hp_screen.size():
			for j in range(i + 1, _cached_hp_screen.size()):
				var diff := _cached_hp_screen[i] - _cached_hp_screen[j]
				var dist := diff.length()
				if dist < min_dist:
					moved = true
					if dist < 0.1:
						diff = Vector2(1.0, 0.0) if (i % 2 == 0) else Vector2(-1.0, 0.0)
						dist = 0.1
					var push := diff.normalized() * (min_dist - dist) * 0.55
					_cached_hp_screen[i] += push
					_cached_hp_screen[j] -= push
		if not moved:
			break

	for i in _cached_hp_screen.size():
		_cached_hp_screen[i].x = clampf(_cached_hp_screen[i].x, a_l + 8.0, a_r - 8.0)
		_cached_hp_screen[i].y = clampf(_cached_hp_screen[i].y, a_t + 8.0, a_b - 8.0)

	# Label directions
	for i in _cached_hp_screen.size():
		var away := Vector2.ZERO
		for j in _cached_hp_screen.size():
			if i == j:
				continue
			var diff := _cached_hp_screen[i] - _cached_hp_screen[j]
			var d := diff.length()
			if d < 30.0 and d > 0.01:
				away += diff.normalized() / d
		if away.length() < 0.01:
			away = Vector2(-1, -1)
		_cached_hp_label_dirs.append(away.normalized())


func _get_weapon_type_color(wtype: int) -> Color:
	match wtype:
		0: return Color(0.0, 0.9, 1.0)   # LASER → cyan
		1: return Color(0.2, 1.0, 0.3)   # PLASMA → green
		2: return Color(1.0, 0.6, 0.1)   # MISSILE → orange
		3: return Color(1.0, 1.0, 0.2)   # RAILGUN → yellow
		4: return Color(1.0, 0.2, 0.2)   # MINE → red
	return COL_PRIMARY


func _get_weapon_type_abbr(wtype: int) -> String:
	match wtype:
		0: return "LASE"
		1: return "PLAS"
		2: return "MISS"
		3: return "RAIL"
		4: return "MINE"
	return "----"


func _draw_weapon_panel(ctrl: Control) -> void:
	var font := ThemeDB.fallback_font
	var s := ctrl.size

	# Background
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.02, 0.06, 0.45))
	ctrl.draw_line(Vector2(0, 0), Vector2(s.x, 0), COL_PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 12), COL_PRIMARY, 1.5)
	ctrl.draw_line(Vector2(s.x, 0), Vector2(s.x, 12), COL_PRIMARY, 1.5)
	var sly: float = fmod(_scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), COL_SCANLINE, 1.0)

	if _weapon_manager == null or _ship == null or _ship.ship_data == null:
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "---", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 11, COL_TEXT_DIM)
		return

	var hp_count := _weapon_manager.get_hardpoint_count()
	var hp_defs: Array = _ship.ship_data.hardpoints
	if hp_count == 0 or hp_defs.is_empty():
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "AUCUNE ARME", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 10, COL_TEXT_DIM)
		return

	if _ship != _silhouette_ship:
		_rebuild_silhouette()

	# Rebuild cached geometry if ship changed or panel resized
	if _cached_wp_size != s or _cached_hp_screen.is_empty():
		_rebuild_weapon_panel_cache(s)

	# --- Header: ARMEMENT ─── [Ship Class] ---
	ctrl.draw_string(font, Vector2(8, 13), "ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_HEADER)
	var hdr_w := font.get_string_size("ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	ctrl.draw_line(Vector2(8 + hdr_w + 6, 7), Vector2(s.x - 8, 7), COL_PRIMARY_DIM, 1.0)
	var class_str: String = _ship.ship_data.ship_class
	if class_str == "":
		class_str = "---"
	var csw := font.get_string_size(class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	ctrl.draw_string(font, Vector2(s.x - csw - 8, 13), class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT_DIM)

	# --- Layout zones ---
	var sil_area_w := 140.0
	var list_x := sil_area_w + 4.0
	var list_w := s.x - list_x - 6.0
	var header_h := 20.0
	var footer_h := 22.0

	# Vertical separator between silhouette and list
	ctrl.draw_line(Vector2(sil_area_w, header_h), Vector2(sil_area_w, s.y - footer_h), Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.15), 1.0)

	# === TOP-DOWN SILHOUETTE (from cache) ===
	var a_l := 10.0
	var a_t := header_h + 2.0
	var a_r := sil_area_w - 6.0
	var a_b := s.y - footer_h - 2.0
	var a_w := a_r - a_l
	var a_h := a_b - a_t
	var a_cx := (a_l + a_r) * 0.5
	var a_cy := (a_t + a_b) * 0.5

	# Draw convex hull (from cache — no per-frame recompute)
	if _cached_hull.size() >= 3:
		var sil_min := Vector2(INF, INF)
		var sil_max := Vector2(-INF, -INF)
		for pt in _cached_hull:
			sil_min = Vector2(minf(sil_min.x, pt.x), minf(sil_min.y, pt.y))
			sil_max = Vector2(maxf(sil_max.x, pt.x), maxf(sil_max.y, pt.y))
		var sil_w := maxf(sil_max.x - sil_min.x, 1.0)
		var sil_h := maxf(sil_max.y - sil_min.y, 1.0)
		var sil_cx := (sil_min.x + sil_max.x) * 0.5
		var sil_cy := (sil_min.y + sil_max.y) * 0.5
		var sc := minf(a_w / sil_w, a_h / sil_h) * 0.82
		var screen_poly := PackedVector2Array()
		for pt in _cached_hull:
			screen_poly.append(Vector2(
				a_cx + (pt.x - sil_cx) * sc,
				a_cy + (pt.y - sil_cy) * sc
			))
		ctrl.draw_colored_polygon(screen_poly, Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.04))
		var closed := PackedVector2Array(screen_poly)
		closed.append(screen_poly[0])
		ctrl.draw_polyline(closed, COL_PRIMARY_DIM, 1.0)
		# Centerline
		var top_y := a_cy + (sil_min.y - sil_cy) * sc
		var bot_y := a_cy + (sil_max.y - sil_cy) * sc
		ctrl.draw_line(Vector2(a_cx, top_y), Vector2(a_cx, bot_y), Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.1), 1.0)
		_draw_diamond(ctrl, Vector2(a_cx, top_y), 2.5, COL_PRIMARY_DIM)
	else:
		var tri := PackedVector2Array([
			Vector2(a_cx, a_cy - a_h * 0.4),
			Vector2(a_cx + a_w * 0.3, a_cy + a_h * 0.3),
			Vector2(a_cx - a_w * 0.3, a_cy + a_h * 0.3),
		])
		ctrl.draw_colored_polygon(tri, Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.04))
		tri.append(tri[0])
		ctrl.draw_polyline(tri, COL_PRIMARY_DIM, 1.0)

	# Draw hardpoint markers from cached positions
	for i in _cached_hp_screen.size():
		var status := _weapon_manager.get_hardpoint_status(i)
		var label_dir := _cached_hp_label_dirs[i] if i < _cached_hp_label_dirs.size() else Vector2(-1, -1)
		_draw_hardpoint_marker(ctrl, font, _cached_hp_screen[i], i, status, label_dir)

	# === WEAPON LIST (right zone) ===
	_draw_weapon_list(ctrl, font, list_x, header_h + 4.0, list_w, hp_count)

	# === FOOTER: WEP energy bar ===
	_draw_weapon_footer(ctrl, font, s, footer_h)


func _draw_hardpoint_marker(ctrl: Control, font: Font, pos: Vector2, index: int, status: Dictionary, label_dir: Vector2 = Vector2(-1, -1)) -> void:
	if status.is_empty():
		return
	var is_on: bool = status["enabled"]
	var wname: String = str(status["weapon_name"])
	var ssize: String = status["slot_size"]
	var cd: float = float(status["cooldown_ratio"])
	var wtype: int = int(status.get("weapon_type", -1))
	var armed: bool = wname != ""

	# Radius scales with slot size
	var r := 6.0
	match ssize:
		"M": r = 8.0
		"L": r = 10.0

	# Color by weapon type (or default cyan)
	var type_col: Color = _get_weapon_type_color(wtype) if armed else COL_PRIMARY
	var is_missile: bool = wtype == 2  # WeaponType.MISSILE

	if is_on and armed:
		# Pulsing glow
		var ga := sin(_pulse_t * 2.0 + float(index) * 1.5) * 0.12 + 0.2
		ctrl.draw_arc(pos, r + 3, 0, TAU, 16, Color(type_col.r, type_col.g, type_col.b, ga), 2.0, true)

		if is_missile:
			# Diamond shape for missiles
			var d := r * 0.85
			var diamond := PackedVector2Array([
				pos + Vector2(0, -d), pos + Vector2(d, 0),
				pos + Vector2(0, d), pos + Vector2(-d, 0),
			])
			ctrl.draw_colored_polygon(diamond, Color(type_col.r, type_col.g, type_col.b, 0.15))
			diamond.append(diamond[0])
			if cd > 0.01:
				ctrl.draw_polyline(diamond, Color(type_col.r, type_col.g, type_col.b, 0.3), 1.5)
				# Cooldown arc around diamond
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r + 1, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_polyline(diamond, type_col, 2.0)
		else:
			# Circle for other weapons
			ctrl.draw_circle(pos, r, Color(type_col.r, type_col.g, type_col.b, 0.12))
			if cd > 0.01:
				ctrl.draw_arc(pos, r, 0, TAU, 20, Color(type_col.r, type_col.g, type_col.b, 0.25), 1.5, true)
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_arc(pos, r, 0, TAU, 20, type_col, 2.0, true)
	elif is_on:
		# Empty slot
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(COL_TEXT_DIM.r, COL_TEXT_DIM.g, COL_TEXT_DIM.b, 0.25), 1.0, true)
	else:
		# Disabled — red dim with X
		ctrl.draw_circle(pos, r, Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.08))
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.3), 1.5, true)
		var xsz := r * 0.5
		ctrl.draw_line(pos + Vector2(-xsz, -xsz), pos + Vector2(xsz, xsz), Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.5), 1.5)
		ctrl.draw_line(pos + Vector2(xsz, -xsz), pos + Vector2(-xsz, xsz), Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.5), 1.5)

	# Hotkey number — placed in the direction away from neighbors
	var num_col: Color = type_col if (is_on and armed) else (COL_PRIMARY if is_on else Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.4))
	var num_str := str(index + 1)
	var num_w := font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var label_offset := label_dir * (r + 6.0)
	# Adjust so text baseline is centered on the offset point
	var num_pos := pos + label_offset + Vector2(-num_w * 0.5, 3.0)
	ctrl.draw_string(font, num_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, num_col)


func _draw_weapon_list(ctrl: Control, font: Font, x: float, y: float, w: float, hp_count: int) -> void:
	var line_h := 16.0
	var grp_colors: Array[Color] = [COL_PRIMARY, Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 1.0)]

	for i in hp_count:
		var status := _weapon_manager.get_hardpoint_status(i)
		if status.is_empty():
			continue
		var ly := y + i * line_h
		var is_on: bool = status["enabled"]
		var wname: String = str(status["weapon_name"])
		var wtype: int = int(status.get("weapon_type", -1))
		var cd: float = float(status["cooldown_ratio"])
		var fire_grp: int = int(status.get("fire_group", -1))
		var armed: bool = wname != ""

		# Hotkey number
		var num_col: Color
		if is_on and armed:
			num_col = _get_weapon_type_color(wtype)
		elif is_on:
			num_col = COL_TEXT_DIM
		else:
			num_col = Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.5)
		ctrl.draw_string(font, Vector2(x, ly + 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, num_col)

		if not armed:
			# Empty slot
			ctrl.draw_string(font, Vector2(x + 12, ly + 10), "---", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(COL_TEXT_DIM.r, COL_TEXT_DIM.g, COL_TEXT_DIM.b, 0.3))
			continue

		# Weapon type abbreviation
		var abbr := _get_weapon_type_abbr(wtype)
		var name_col: Color
		if not is_on:
			name_col = Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.4)
		else:
			name_col = Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.8)
		ctrl.draw_string(font, Vector2(x + 12, ly + 10), abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, name_col)

		# Short weapon name (after type abbr)
		var short_name := wname.get_slice(" ", 0).left(4)
		ctrl.draw_string(font, Vector2(x + 44, ly + 10), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(COL_TEXT_DIM.r, COL_TEXT_DIM.g, COL_TEXT_DIM.b, 0.6 if is_on else 0.3))

		if not is_on:
			# Strikethrough for disabled
			var strike_y := ly + 6.0
			ctrl.draw_line(Vector2(x + 10, strike_y), Vector2(x + w - 18, strike_y), Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.35), 1.0)
			continue

		# Cooldown / ready indicator (right side)
		var ind_x := x + w - 18.0
		if cd > 0.01:
			# Mini cooldown bar
			var bar_w := 14.0
			var bar_h := 4.0
			var bar_y := ly + 5.0
			ctrl.draw_rect(Rect2(ind_x, bar_y, bar_w, bar_h), Color(COL_TEXT_DIM.r, COL_TEXT_DIM.g, COL_TEXT_DIM.b, 0.15))
			var fill := (1.0 - cd) * bar_w
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_rect(Rect2(ind_x, bar_y, fill, bar_h), Color(type_c.r, type_c.g, type_c.b, 0.7))
		else:
			# Ready dot
			var dot_pos := Vector2(ind_x + 7.0, ly + 7.0)
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_circle(dot_pos, 2.5, type_c)

		# Fire group indicator (small colored dot before the ready indicator)
		if fire_grp >= 0 and fire_grp < grp_colors.size():
			var grp_x := x + w - 32.0
			var grp_y := ly + 7.0
			ctrl.draw_circle(Vector2(grp_x, grp_y), 2.0, Color(grp_colors[fire_grp].r, grp_colors[fire_grp].g, grp_colors[fire_grp].b, 0.6))


func _draw_weapon_footer(ctrl: Control, font: Font, s: Vector2, footer_h: float) -> void:
	var fy := s.y - footer_h
	# Separator line
	ctrl.draw_line(Vector2(6, fy), Vector2(s.x - 6, fy), Color(COL_PRIMARY.r, COL_PRIMARY.g, COL_PRIMARY.b, 0.15), 1.0)

	# Fire group labels
	var grp_colors: Array[Color] = [COL_PRIMARY, Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 1.0)]
	var gx := 8.0
	for g in _weapon_manager.weapon_groups.size():
		if _weapon_manager.weapon_groups[g].is_empty():
			continue
		var label := "G" + str(g + 1)
		var gc: Color = grp_colors[g] if g < grp_colors.size() else COL_TEXT_DIM
		ctrl.draw_string(font, Vector2(gx, fy + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, gc)
		gx += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 2
		# Dots for hardpoints in this group
		for hp_idx in _weapon_manager.weapon_groups[g]:
			var st := _weapon_manager.get_hardpoint_status(hp_idx)
			var dot_c: Color = gc if st.get("enabled", false) else Color(gc.r, gc.g, gc.b, 0.2)
			ctrl.draw_circle(Vector2(gx + 2, fy + 10), 2.5, dot_c)
			gx += 7.0
		gx += 6.0

	# WEP energy bar (right side of footer)
	if _energy_system:
		var bar_x := s.x - 90.0
		var bar_y := fy + 5.0
		var bar_w := 58.0
		var bar_h := 6.0
		var ratio := _energy_system.get_energy_ratio()
		ctrl.draw_string(font, Vector2(bar_x - 26, fy + 14), "WEP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT_DIM)
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(COL_TEXT_DIM.r, COL_TEXT_DIM.g, COL_TEXT_DIM.b, 0.15))
		var fill_w := ratio * bar_w
		var bar_col := COL_PRIMARY if ratio > 0.25 else COL_WARN
		ctrl.draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), Color(bar_col.r, bar_col.g, bar_col.b, 0.7))
		# Percentage text
		var pct_str := str(int(ratio * 100.0)) + "%"
		ctrl.draw_string(font, Vector2(bar_x + bar_w + 4, fy + 14), pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, COL_TEXT_DIM)


# =============================================================================
# RIGHT PANEL - Navigation data
# =============================================================================
func _draw_right_panel(ctrl: Control) -> void:
	_draw_panel_bg(ctrl)
	var font := ThemeDB.fallback_font
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var y := 22.0

	y = _draw_section_header(ctrl, font, x, y, w, "NAVIGATION")
	y += 2

	# Position (label above, value below)
	ctrl.draw_string(font, Vector2(x, y), "POS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)
	y += 14
	var pos_str := FloatingOrigin.get_universe_pos_string() if FloatingOrigin else "0, 0, 0"
	ctrl.draw_string(font, Vector2(x, y), pos_str, HORIZONTAL_ALIGNMENT_LEFT, int(w), 11, COL_TEXT)
	y += 22

	if _ship:
		var fwd := -_ship.global_transform.basis.z
		# Heading — key left, value right-aligned
		var heading: float = rad_to_deg(atan2(fwd.x, -fwd.z))
		if heading < 0: heading += 360.0
		ctrl.draw_string(font, Vector2(x, y), "CAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
		var hv := "%06.2f\u00B0" % heading
		var hvw := font.get_string_size(hv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ctrl.draw_string(font, Vector2(x + w - hvw, y), hv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_PRIMARY)
		y += 22

		# Pitch — key left, value right-aligned
		var pitch: float = rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))
		ctrl.draw_string(font, Vector2(x, y), "INCL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
		var pv := "%+.1f\u00B0" % pitch
		var pvw := font.get_string_size(pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ctrl.draw_string(font, Vector2(x + w - pvw, y), pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_PRIMARY)
		y += 22

	# Sector — key left, value right-aligned
	ctrl.draw_string(font, Vector2(x, y), "SECTEUR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	var sv := "ALPHA-0"
	var svw := font.get_string_size(sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ctrl.draw_string(font, Vector2(x + w - svw, y), sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT)


# =============================================================================
# TARGET OVERLAY - 3D->2D projected target bracket + lead indicator
# =============================================================================
func _draw_target_overlay(ctrl: Control) -> void:
	if _targeting_system == null:
		return
	if _targeting_system.current_target == null or not is_instance_valid(_targeting_system.current_target):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target := _targeting_system.current_target
	var cf: Vector3 = -cam.global_transform.basis.z

	var to_t: Vector3 = (target.global_position - cam.global_position).normalized()
	if cf.dot(to_t) > 0.1:
		_draw_target_bracket(ctrl, cam.unproject_position(target.global_position))

	if _ship and _ship.current_speed > 0.1:
		var lp: Vector3 = _targeting_system.get_lead_indicator_position()
		var to_l: Vector3 = (lp - cam.global_position).normalized()
		if cf.dot(to_l) > 0.1:
			_draw_lead_indicator(ctrl, cam.unproject_position(lp))


func _draw_target_bracket(ctrl: Control, sp: Vector2) -> void:
	var bk := 22.0
	var bl := 10.0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var corner: Vector2 = sp + s * bk
		ctrl.draw_line(corner, corner + Vector2(-s.x * bl, 0), COL_TARGET, 1.5)
		ctrl.draw_line(corner, corner + Vector2(0, -s.y * bl), COL_TARGET, 1.5)


func _draw_lead_indicator(ctrl: Control, sp: Vector2) -> void:
	ctrl.draw_arc(sp, 8.0, 0, TAU, 16, COL_LEAD, 1.5, true)
	ctrl.draw_line(sp + Vector2(-4, 0), sp + Vector2(4, 0), COL_LEAD, 1.0)
	ctrl.draw_line(sp + Vector2(0, -4), sp + Vector2(0, 4), COL_LEAD, 1.0)


# =============================================================================
# TARGET INFO PANEL - Dedicated display with directional shields + hit flash
# =============================================================================
func _draw_target_info_panel(ctrl: Control) -> void:
	_draw_panel_bg(ctrl)
	var font := ThemeDB.fallback_font
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var cx := ctrl.size.x / 2.0
	var y := 22.0

	# Decorated header
	y = _draw_section_header(ctrl, font, x, y, w, "CIBLE")
	y += 4

	if _targeting_system == null or _targeting_system.current_target == null:
		return
	if not is_instance_valid(_targeting_system.current_target):
		return

	var target := _targeting_system.current_target
	var t_health := target.get_node_or_null("HealthSystem") as HealthSystem

	# Target name — prominent
	ctrl.draw_string(font, Vector2(x, y), target.name as String, HORIZONTAL_ALIGNMENT_LEFT, int(w), 14, COL_TARGET)
	y += 18

	# Class + distance on same line
	var class_text := ""
	if target is ShipController and (target as ShipController).ship_data:
		class_text = str((target as ShipController).ship_data.ship_class)
	ctrl.draw_string(font, Vector2(x, y), class_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)

	var dist := _targeting_system.get_target_distance()
	if dist >= 0.0:
		var dt: String = "%.0fm" % dist if dist < 1000.0 else "%.1fkm" % (dist / 1000.0)
		var dtw := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_RIGHT, -1, 13).x
		ctrl.draw_string(font, Vector2(x + w - dtw, y), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT)
	y += 24

	# Shield diagram with arcs
	var diagram_center := Vector2(cx, y + 52)
	_draw_target_ship_shields(ctrl, diagram_center, t_health)
	y += 114

	# Per-facing shield percentages (2 rows)
	if t_health:
		var f_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.FRONT)
		var r_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.REAR)
		var l_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.LEFT)
		var d_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.RIGHT)
		var col_x2 := cx + 10
		ctrl.draw_string(font, Vector2(x, y), "AV: %d%%" % int(f_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _shield_ratio_color(f_r))
		ctrl.draw_string(font, Vector2(col_x2, y), "AR: %d%%" % int(r_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _shield_ratio_color(r_r))
		y += 14
		ctrl.draw_string(font, Vector2(x, y), "G: %d%%" % int(l_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _shield_ratio_color(l_r))
		ctrl.draw_string(font, Vector2(col_x2, y), "D: %d%%" % int(d_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _shield_ratio_color(d_r))
		y += 18
	else:
		y += 32

	# Hull bar with inline pct
	var hull_r := t_health.get_hull_ratio() if t_health else 0.0
	var hull_c := COL_ACCENT if hull_r > 0.5 else (COL_WARN if hull_r > 0.25 else COL_DANGER)
	ctrl.draw_string(font, Vector2(x, y), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	var hp := "%d%%" % int(hull_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hull_c)
	y += 8
	_draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)

	# Hull flash overlay
	if _target_hull_flash > 0.01:
		var bar_fw: float = w * clampf(hull_r, 0.0, 1.0)
		if bar_fw > 0:
			ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_hull_flash * 0.5))


func _draw_target_ship_shields(ctrl: Control, center: Vector2, health: HealthSystem) -> void:
	var radius := 40.0
	var arc_half := deg_to_rad(40.0)
	var arc_width := 5.0
	var bg_width := 3.0
	var segments := 24

	var arc_centers: Array[float] = [-PI / 2.0, PI / 2.0, PI, 0.0]
	var facings: Array[int] = [
		HealthSystem.ShieldFacing.FRONT, HealthSystem.ShieldFacing.REAR,
		HealthSystem.ShieldFacing.LEFT, HealthSystem.ShieldFacing.RIGHT,
	]

	for i in 4:
		var ac: float = arc_centers[i]
		var a0: float = ac - arc_half
		var a1: float = ac + arc_half
		ctrl.draw_arc(center, radius, a0, a1, segments, COL_PRIMARY_FAINT, bg_width, true)
		if health:
			var ratio := health.get_shield_ratio(facings[i])
			if ratio > 0.01:
				ctrl.draw_arc(center, radius, a0, a0 + (a1 - a0) * ratio, segments, _shield_ratio_color(ratio), arc_width, true)
			if _target_shield_flash[i] > 0.01:
				ctrl.draw_arc(center, radius, a0, a1, segments, Color(1, 1, 1, _target_shield_flash[i] * 0.8), arc_width + 2.0, true)

	# Ship silhouette
	var tri_h := 14.0
	var tri_w := 9.0
	var tri := PackedVector2Array([
		center + Vector2(0, -tri_h), center + Vector2(tri_w, tri_h * 0.5), center + Vector2(-tri_w, tri_h * 0.5),
	])
	ctrl.draw_colored_polygon(tri, COL_PRIMARY_DIM)
	ctrl.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), COL_PRIMARY, 1.0)

	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, center + Vector2(-5, -radius - 8), "AV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-5, radius + 16), "AR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-radius - 14, 4), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(radius + 6, 4), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)


func _shield_ratio_color(ratio: float) -> Color:
	if ratio > 0.5: return COL_SHIELD
	elif ratio > 0.25: return COL_WARN
	elif ratio > 0.0: return COL_DANGER
	return COL_PRIMARY_FAINT


# =============================================================================
# TARGET TRACKING - Signal management for hit flash effects
# =============================================================================
func _track_target(new_target: Node3D) -> void:
	if new_target == _last_tracked_target:
		return
	_disconnect_target_signals()
	_last_tracked_target = new_target
	_target_shield_flash = [0.0, 0.0, 0.0, 0.0]
	_target_hull_flash = 0.0
	if new_target and is_instance_valid(new_target):
		_connect_target_signals(new_target)


func _connect_target_signals(target: Node3D) -> void:
	var health := target.get_node_or_null("HealthSystem") as HealthSystem
	if health == null:
		return
	_connected_target_health = health
	health.shield_changed.connect(_on_target_shield_hit)
	health.hull_changed.connect(_on_target_hull_hit)
	for i in 4:
		_prev_target_shields[i] = health.shield_current[i]
	_prev_target_hull = health.hull_current


func _disconnect_target_signals() -> void:
	if _connected_target_health and is_instance_valid(_connected_target_health):
		if _connected_target_health.shield_changed.is_connected(_on_target_shield_hit):
			_connected_target_health.shield_changed.disconnect(_on_target_shield_hit)
		if _connected_target_health.hull_changed.is_connected(_on_target_hull_hit):
			_connected_target_health.hull_changed.disconnect(_on_target_hull_hit)
	_connected_target_health = null


func _on_target_shield_hit(facing: int, current: float, _max_val: float) -> void:
	if facing >= 0 and facing < 4 and current < _prev_target_shields[facing]:
		_target_shield_flash[facing] = 1.0
	if facing >= 0 and facing < 4:
		_prev_target_shields[facing] = current


func _on_target_hull_hit(current: float, _max_val: float) -> void:
	if current < _prev_target_hull:
		_target_hull_flash = 1.0
	_prev_target_hull = current


# =============================================================================
# TOP BAR
# =============================================================================
func _draw_top_bar(ctrl: Control) -> void:
	var font := ThemeDB.fallback_font
	var cx := ctrl.size.x / 2.0
	ctrl.draw_line(Vector2(0, ctrl.size.y - 1), Vector2(ctrl.size.x, ctrl.size.y - 1), COL_BORDER, 1.0)
	var cl := 8.0
	ctrl.draw_line(Vector2(0, 0), Vector2(cl, 0), COL_PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, cl), COL_PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x - cl, 0), COL_PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x, cl), COL_PRIMARY_DIM, 1.0)

	if _ship == null:
		return
	var mt := _get_mode_text()
	var mc := _get_mode_color()
	var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
	ctrl.draw_string(font, Vector2(cx - mw / 2.0, 24), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, mc)
	ctrl.draw_line(Vector2(cx - mw / 2.0 - 18, 18), Vector2(cx - mw / 2.0 - 4, 18), mc * Color(1, 1, 1, 0.5), 1.0)
	ctrl.draw_line(Vector2(cx + mw / 2.0 + 4, 18), Vector2(cx + mw / 2.0 + 18, 18), mc * Color(1, 1, 1, 0.5), 1.0)

	var fa := "AV" if _ship.flight_assist else "AV DÉSACT"
	ctrl.draw_string(font, Vector2(10, 24), fa, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_ACCENT if _ship.flight_assist else COL_DANGER)

	var fps_str := "%d FPS" % Engine.get_frames_per_second()
	ctrl.draw_string(font, Vector2(10, 38), fps_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)

	var st := "%.0f m/s" % _ship.current_speed
	var sw := font.get_string_size(st, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12).x
	ctrl.draw_string(font, Vector2(ctrl.size.x - sw - 10, 24), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)


# =============================================================================
# COMPASS
# =============================================================================
func _draw_compass(ctrl: Control) -> void:
	if _ship == null:
		return
	var font := ThemeDB.fallback_font
	var w := ctrl.size.x
	var h := ctrl.size.y
	var cx := w / 2.0
	ctrl.draw_rect(Rect2(0, 0, w, h), COL_BG_DARK)
	ctrl.draw_line(Vector2(0, h - 1), Vector2(w, h - 1), COL_BORDER, 1.0)

	var fwd := -_ship.global_transform.basis.z
	var heading: float = rad_to_deg(atan2(fwd.x, -fwd.z))
	if heading < 0: heading += 360.0
	var ppd := 3.0
	var labels := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

	for d in range(-50, 51):
		var wd: float = fmod(heading + d + 360.0, 360.0)
		var sx := cx + d * ppd
		if sx < 0 or sx > w:
			continue
		var rd := int(round(wd)) % 360
		if rd % 10 == 0:
			ctrl.draw_line(Vector2(sx, h - (4.0 if rd % 30 == 0 else 2.0) - 2), Vector2(sx, h - 2), COL_PRIMARY_DIM, 1.0)
		if rd in labels and abs(d) < 48:
			var lbl: String = labels[rd]
			var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 10).x
			ctrl.draw_string(font, Vector2(sx - lw / 2.0, 12), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_PRIMARY)
	ctrl.draw_line(Vector2(cx, 0), Vector2(cx, 4), COL_TEXT, 1.5)


# =============================================================================
# WARNINGS
# =============================================================================
func _draw_warnings(ctrl: Control) -> void:
	if _ship == null:
		return
	var font := ThemeDB.fallback_font
	var cx := ctrl.size.x / 2.0

	if not _ship.flight_assist:
		var flash := absf(sin(_warning_flash)) * 0.6 + 0.4
		var wt := "ASSIST. VOL DÉSACTIVÉ"
		var tw := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 20), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_DANGER * Color(1, 1, 1, flash))

	if _ship.speed_mode == Constants.SpeedMode.CRUISE and _ship.current_speed > 2500:
		var wt := "VITESSE ÉLEVÉE"
		var tw := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 38), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_WARN)

	if _health_system and _health_system.get_total_shield_ratio() < 0.1:
		var flash := absf(sin(_warning_flash * 1.5)) * 0.7 + 0.3
		var wt := "BOUCLIERS FAIBLES"
		var tw := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 56), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_WARN * Color(1, 1, 1, flash))

	if _health_system and _health_system.get_hull_ratio() < 0.25:
		var flash := absf(sin(_warning_flash * 2.0)) * 0.8 + 0.2
		var wt := "COQUE CRITIQUE"
		var tw := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 74), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_DANGER * Color(1, 1, 1, flash))


# =============================================================================
# NAVIGATION MARKERS - BSGO-style POI indicators with distance
# =============================================================================
const NAV_EDGE_MARGIN: float = 40.0
const NAV_NPC_RANGE: float = 3000.0
const NAV_COL_STATION: Color = Color(0.2, 0.85, 0.8, 0.85)
const NAV_COL_STAR: Color = Color(1.0, 0.85, 0.4, 0.75)
const NAV_COL_HOSTILE: Color = Color(1.0, 0.3, 0.2, 0.85)
const NAV_COL_FRIENDLY: Color = Color(0.3, 0.9, 0.4, 0.85)
const NAV_COL_NEUTRAL_NPC: Color = Color(0.6, 0.4, 0.9, 0.85)

func _draw_nav_markers(ctrl: Control) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen_size := ctrl.size
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var cam_pos: Vector3 = cam.global_position
	var font := ThemeDB.fallback_font

	# Stations + Star from EntityRegistry
	for ent in EntityRegistry.get_all().values():
		var etype: int = ent["type"]
		if etype != EntityRegistrySystem.EntityType.STATION and etype != EntityRegistrySystem.EntityType.STAR:
			continue
		var world_pos: Vector3
		var node: Node3D = ent.get("node")
		if node != null and is_instance_valid(node):
			world_pos = node.global_position
		else:
			world_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		var player_upos: Array = FloatingOrigin.to_universe_pos(cam_pos)
		var dx: float = ent["pos_x"] - player_upos[0]
		var dy: float = ent["pos_y"] - player_upos[1]
		var dz: float = ent["pos_z"] - player_upos[2]
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		var marker_col: Color = NAV_COL_STATION if etype == EntityRegistrySystem.EntityType.STATION else NAV_COL_STAR
		_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos, ent["name"], dist, marker_col)

	# NPC ships — use LOD manager if available (LOD0/LOD1 only, LOD2+ have Label3D tags)
	if _ship:
		var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
		if lod_mgr:
			var nearby := lod_mgr.get_ships_in_radius(cam_pos, NAV_NPC_RANGE)
			var npc_marker_count: int = 0
			var _used_screen_spots: Array[Vector2] = []
			for npc_id in nearby:
				if npc_id == &"player_ship":
					continue
				if npc_marker_count >= 30:
					break  # Cap NPC markers to avoid clutter
				var data := lod_mgr.get_ship_data(npc_id)
				if data == null or data.is_dead:
					continue
				# Skip LOD2+ ships — they have their own Label3D name tags
				if data.current_lod >= ShipLODData.LODLevel.LOD2:
					continue
				var world_pos: Vector3 = data.position
				var dist: float = cam_pos.distance_to(world_pos)
				# Dedup: skip if another marker is too close on screen
				var to_ent := world_pos - cam_pos
				var dot_fwd: float = cam_fwd.dot(to_ent.normalized())
				if dot_fwd > 0.1:
					var sp := cam.unproject_position(world_pos)
					var too_close := false
					for used_sp in _used_screen_spots:
						if sp.distance_to(used_sp) < 40.0:
							too_close = true
							break
					if too_close:
						continue
					_used_screen_spots.append(sp)
				var nav_name := data.display_name if not data.display_name.is_empty() else String(data.ship_class)
				var nav_col := _get_faction_nav_color(data.faction)
				_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos, nav_name, dist, nav_col)
				npc_marker_count += 1
		else:
			for ship_node in get_tree().get_nodes_in_group("ships"):
				if ship_node == _ship or not is_instance_valid(ship_node) or not ship_node is Node3D:
					continue
				var world_pos: Vector3 = (ship_node as Node3D).global_position
				var dist: float = cam_pos.distance_to(world_pos)
				if dist > NAV_NPC_RANGE:
					continue
				_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos,
					_get_npc_name(ship_node), dist, _get_npc_nav_color(ship_node))


func _draw_nav_entity(ctrl: Control, font: Font, cam: Camera3D, cam_fwd: Vector3, cam_pos: Vector3, screen_size: Vector2, world_pos: Vector3, ent_name: String, dist: float, col: Color) -> void:
	var dist_str := _format_nav_distance(dist)
	var to_ent: Vector3 = world_pos - cam_pos
	if to_ent.length() < 0.1:
		return
	var dot: float = cam_fwd.dot(to_ent.normalized())
	if dot > 0.1:
		var sp: Vector2 = cam.unproject_position(world_pos)
		if sp.x >= 0 and sp.x <= screen_size.x and sp.y >= 0 and sp.y <= screen_size.y:
			_draw_nav_onscreen(ctrl, font, sp, ent_name, dist_str, col)
			return
	_draw_nav_offscreen(ctrl, font, screen_size, cam, cam_pos, world_pos, ent_name, dist_str, col)


func _draw_nav_onscreen(ctrl: Control, font: Font, sp: Vector2, ent_name: String, dist_str: String, col: Color) -> void:
	# Diamond marker
	_draw_diamond(ctrl, sp, 5.0, col)

	# Name above diamond
	var name_w := font.get_string_size(ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var name_pos := Vector2(sp.x - name_w * 0.5, sp.y - 18)
	# Background pill
	ctrl.draw_rect(Rect2(name_pos.x - 4, name_pos.y - 10, name_w + 8, 14), Color(0.0, 0.02, 0.06, 0.5))
	ctrl.draw_string(font, name_pos, ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)

	# Distance below diamond
	var dist_w := font.get_string_size(dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var dist_pos := Vector2(sp.x - dist_w * 0.5, sp.y + 18)
	ctrl.draw_rect(Rect2(dist_pos.x - 4, dist_pos.y - 11, dist_w + 8, 15), Color(0.0, 0.02, 0.06, 0.5))
	ctrl.draw_string(font, dist_pos, dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_nav_offscreen(ctrl: Control, font: Font, screen_size: Vector2, cam: Camera3D, cam_pos: Vector3, world_pos: Vector3, ent_name: String, dist_str: String, col: Color) -> void:
	# Project entity direction to 2D screen-space direction
	var to_ent: Vector3 = (world_pos - cam_pos).normalized()
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var screen_dir := Vector2(to_ent.dot(right), -to_ent.dot(up))
	if screen_dir.length() < 0.001:
		screen_dir = Vector2(0, -1)
	screen_dir = screen_dir.normalized()

	# Find edge point
	var center := screen_size * 0.5
	var margin := NAV_EDGE_MARGIN
	var half := center - Vector2(margin, margin)

	# Ray-box intersection to find edge point
	var edge_pos := center
	if abs(screen_dir.x) > 0.001:
		var tx: float = half.x / abs(screen_dir.x)
		var ty: float = half.y / abs(screen_dir.y) if abs(screen_dir.y) > 0.001 else 1e6
		var t: float = minf(tx, ty)
		edge_pos = center + screen_dir * t
	elif abs(screen_dir.y) > 0.001:
		var t: float = half.y / abs(screen_dir.y)
		edge_pos = center + screen_dir * t

	# Chevron arrow pointing outward
	var arrow_sz: float = 8.0
	var perp := Vector2(-screen_dir.y, screen_dir.x)
	var tip := edge_pos + screen_dir * 4.0
	ctrl.draw_line(tip, tip - screen_dir * arrow_sz + perp * arrow_sz * 0.5, col, 2.0)
	ctrl.draw_line(tip, tip - screen_dir * arrow_sz - perp * arrow_sz * 0.5, col, 2.0)

	# Name + distance next to arrow (offset inward)
	var text_offset := -screen_dir * 20.0 + perp * 14.0
	var text_pos := edge_pos + text_offset
	# Clamp text to screen
	text_pos.x = clampf(text_pos.x, 8.0, screen_size.x - 120.0)
	text_pos.y = clampf(text_pos.y, 16.0, screen_size.y - 16.0)

	ctrl.draw_string(font, text_pos, ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	ctrl.draw_string(font, text_pos + Vector2(0, 13), dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _format_nav_distance(dist_m: float) -> String:
	if dist_m < 1000.0:
		return "%.0f m" % dist_m
	elif dist_m < 100_000.0:
		return "%.1f km" % (dist_m / 1000.0)
	elif dist_m < 1_000_000.0:
		return "%.0f km" % (dist_m / 1000.0)
	else:
		return "%.1f Mm" % (dist_m / 1_000_000.0)


func _get_npc_nav_color(node: Node) -> Color:
	var faction = node.get("faction")
	if faction == &"hostile":
		return NAV_COL_HOSTILE
	elif faction == &"friendly":
		return NAV_COL_FRIENDLY
	return NAV_COL_NEUTRAL_NPC


func _get_faction_nav_color(faction: StringName) -> Color:
	if faction == &"hostile":
		return NAV_COL_HOSTILE
	elif faction == &"friendly":
		return NAV_COL_FRIENDLY
	return NAV_COL_NEUTRAL_NPC


func _get_npc_name(node: Node) -> String:
	var data = node.get("ship_data")
	if data and data.ship_class != "":
		return data.ship_class
	return node.name


# =============================================================================
# RADAR - Holographic tactical scanning display
# =============================================================================
const RADAR_RANGE: float = 5000.0
const RADAR_SWEEP_SPEED: float = 1.2
const RADAR_COL_BG: Color = Color(0.0, 0.03, 0.06, 0.7)
const RADAR_COL_RING: Color = Color(0.1, 0.4, 0.5, 0.25)
const RADAR_COL_SWEEP: Color = Color(0.15, 0.85, 0.75, 0.6)
const RADAR_COL_EDGE: Color = Color(0.1, 0.5, 0.6, 0.5)

func _draw_radar(ctrl: Control) -> void:
	if _ship == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := ThemeDB.fallback_font
	var s := ctrl.size
	var center := Vector2(s.x * 0.5, s.y * 0.5 + 10)
	var radar_r: float = minf(s.x, s.y) * 0.5 - 20.0
	var ship_basis := _ship.global_transform.basis
	var scale_factor: float = radar_r / RADAR_RANGE

	# --- Background ---
	ctrl.draw_circle(center, radar_r + 2, RADAR_COL_BG)

	# --- Range rings (3 rings at 1/3, 2/3, full) ---
	for ring_t in [0.333, 0.666]:
		ctrl.draw_arc(center, radar_r * ring_t, 0, TAU, 16, RADAR_COL_RING, 1.0, true)

	# --- Cross lines ---
	ctrl.draw_line(center + Vector2(0, -radar_r), center + Vector2(0, radar_r), RADAR_COL_RING, 1.0)
	ctrl.draw_line(center + Vector2(-radar_r, 0), center + Vector2(radar_r, 0), RADAR_COL_RING, 1.0)

	# --- Edge circle + tick marks ---
	ctrl.draw_arc(center, radar_r, 0, TAU, 32, RADAR_COL_EDGE, 1.5, true)
	for i in 12:
		var angle := float(i) * TAU / 12.0 - PI * 0.5
		var inner := center + Vector2(cos(angle), sin(angle)) * (radar_r - 4)
		var outer := center + Vector2(cos(angle), sin(angle)) * radar_r
		ctrl.draw_line(inner, outer, RADAR_COL_EDGE, 1.0)

	# --- Sonar ping (expanding ring) ---
	var ping_t := fmod(_pulse_t * 0.3, 1.0)
	var ping_r := ping_t * radar_r
	var ping_alpha := (1.0 - ping_t) * 0.12
	ctrl.draw_arc(center, ping_r, 0, TAU, 16, Color(RADAR_COL_SWEEP.r, RADAR_COL_SWEEP.g, RADAR_COL_SWEEP.b, ping_alpha), 1.0, true)

	# --- Sweep line with fading trail ---
	var sweep_angle := fmod(_pulse_t * RADAR_SWEEP_SPEED, TAU) - PI * 0.5
	for i in 10:
		var ta := sweep_angle - float(i) * 0.08
		var alpha := (1.0 - float(i) / 10.0) * 0.2
		ctrl.draw_line(center, center + Vector2(cos(ta), sin(ta)) * radar_r,
			Color(RADAR_COL_SWEEP.r, RADAR_COL_SWEEP.g, RADAR_COL_SWEEP.b, alpha), 1.0)
	ctrl.draw_line(center, center + Vector2(cos(sweep_angle), sin(sweep_angle)) * radar_r, RADAR_COL_SWEEP, 2.0)

	# --- Entity blips: Stations ---
	for ent in EntityRegistry.get_all().values():
		var etype: int = ent["type"]
		if etype == EntityRegistrySystem.EntityType.STATION:
			var node: Node3D = ent.get("node")
			if node and is_instance_valid(node):
				var rel := node.global_position - _ship.global_position
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, NAV_COL_STATION, 4.0, true)
		elif etype == EntityRegistrySystem.EntityType.STAR:
			# Star: direction arrow on edge (always far away)
			var star_local := Vector3(
				-FloatingOrigin.origin_offset_x,
				-FloatingOrigin.origin_offset_y,
				-FloatingOrigin.origin_offset_z
			) - _ship.global_position
			if star_local.length() > 0.01:
				var lx: float = star_local.dot(ship_basis.x)
				var lz: float = star_local.dot(ship_basis.z)
				var dir := Vector2(lx, lz).normalized()
				_draw_diamond(ctrl, center + dir * (radar_r - 6), 3.0, NAV_COL_STAR)

	# --- Entity blips: NPC ships (LOD manager shows all including LOD2) ---
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr:
		var all_ids := lod_mgr.get_ships_in_radius(_ship.global_position, RADAR_RANGE * 2.0)
		for npc_id in all_ids:
			if npc_id == &"player_ship":
				continue
			var data := lod_mgr.get_ship_data(npc_id)
			if data == null or data.is_dead:
				continue
			var rel: Vector3 = data.position - _ship.global_position
			var col := _get_faction_nav_color(data.faction)
			if rel.length() > RADAR_RANGE:
				var lx: float = rel.dot(ship_basis.x)
				var lz: float = rel.dot(ship_basis.z)
				if Vector2(lx, lz).length() > 0.01:
					var dir := Vector2(lx, lz).normalized()
					ctrl.draw_circle(center + dir * (radar_r - 3), 2.0, Color(col.r, col.g, col.b, 0.4))
			else:
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, col, 3.0, false)
	else:
		for ship_node in get_tree().get_nodes_in_group("ships"):
			if ship_node == _ship or not is_instance_valid(ship_node) or not ship_node is Node3D:
				continue
			var rel: Vector3 = (ship_node as Node3D).global_position - _ship.global_position
			var col := _get_npc_nav_color(ship_node)
			if rel.length() > RADAR_RANGE:
				var lx: float = rel.dot(ship_basis.x)
				var lz: float = rel.dot(ship_basis.z)
				if Vector2(lx, lz).length() > 0.01:
					var dir := Vector2(lx, lz).normalized()
					ctrl.draw_circle(center + dir * (radar_r - 3), 2.0, Color(col.r, col.g, col.b, 0.4))
			else:
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, col, 3.0, false)

	# --- Player icon (center triangle pointing up = forward) ---
	var tri_sz := 5.0
	ctrl.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -tri_sz),
		center + Vector2(tri_sz * 0.6, tri_sz * 0.4),
		center + Vector2(-tri_sz * 0.6, tri_sz * 0.4),
	]), COL_PRIMARY)

	# --- Header ---
	ctrl.draw_string(font, Vector2(0, 12), "RADAR", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 10, COL_HEADER)

	# --- Range label ---
	ctrl.draw_string(font, Vector2(0, s.y - 4), _format_nav_distance(RADAR_RANGE), HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 9, COL_TEXT_DIM)

	# --- Scanline ---
	var sly: float = fmod(_scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), COL_SCANLINE, 1.0)


func _draw_radar_blip(ctrl: Control, center: Vector2, radar_r: float, scale_factor: float, ship_basis: Basis, rel: Vector3, col: Color, sz: float, is_station: bool) -> void:
	var local_x: float = rel.dot(ship_basis.x)
	var local_z: float = rel.dot(ship_basis.z)
	var radar_pos := Vector2(local_x, local_z) * scale_factor
	if radar_pos.length() > radar_r - 4:
		radar_pos = radar_pos.normalized() * (radar_r - 4)
	var pos := center + radar_pos
	# Glow
	ctrl.draw_circle(pos, sz + 2, Color(col.r, col.g, col.b, 0.15))
	# Blip
	if is_station:
		_draw_diamond(ctrl, pos, sz, col)
	else:
		ctrl.draw_circle(pos, sz, col)


# =============================================================================
# COCKPIT HUD - Fighter jet style targeting system (V key)
# =============================================================================
func _draw_cockpit_hud(ctrl: Control) -> void:
	if _ship == null:
		return
	var s := ctrl.size
	var cx := s.x * 0.5
	var cy := s.y * 0.5
	var center := Vector2(cx, cy)
	var font := ThemeDB.fallback_font
	var ship_basis := _ship.global_transform.basis
	var fwd := -ship_basis.z

	_draw_cockpit_reticle(ctrl, center)
	_draw_cockpit_pitch_ladder(ctrl, center, fwd, font)
	_draw_cockpit_heading(ctrl, font, cx, cy, fwd)
	_draw_cockpit_speed(ctrl, font, cx, cy)
	_draw_cockpit_bars(ctrl, font, cx, cy)
	_draw_cockpit_target_info(ctrl, font, cx, cy)

	# Flight assist warning
	if not _ship.flight_assist:
		var flash := absf(sin(_warning_flash)) * 0.5 + 0.5
		var wt := "AV DÉSACTIVÉ"
		var ww := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		ctrl.draw_string(font, Vector2(cx - ww * 0.5, cy + 140), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DANGER * Color(1, 1, 1, flash))

	_draw_cockpit_frame(ctrl)


func _draw_cockpit_reticle(ctrl: Control, center: Vector2) -> void:
	var pulse := sin(_pulse_t * 1.5) * 0.06 + 0.94
	var r_outer := 88.0
	var r_inner := 50.0

	# Outer targeting ring
	ctrl.draw_arc(center, r_outer, 0, TAU, 64, COL_PRIMARY * Color(1, 1, 1, 0.22 * pulse), 1.0, true)

	# 12 tick marks (major at cardinal points)
	for i in 12:
		var angle := float(i) * TAU / 12.0 - PI * 0.5
		var is_major := i % 3 == 0
		var tick_len := 12.0 if is_major else 5.0
		var tick_w := 2.0 if is_major else 1.0
		var p1 := center + Vector2(cos(angle), sin(angle)) * r_outer
		var p2 := center + Vector2(cos(angle), sin(angle)) * (r_outer - tick_len)
		ctrl.draw_line(p1, p2, COL_PRIMARY * Color(1, 1, 1, 0.5 if is_major else 0.3), tick_w)

	# Inner circle
	ctrl.draw_arc(center, r_inner, 0, TAU, 48, COL_PRIMARY * Color(1, 1, 1, 0.4), 1.5, true)

	# Crosshair lines with gap
	var gap := 10.0
	var line_end := 40.0
	var col_ch := COL_PRIMARY * Color(1, 1, 1, 0.85)
	ctrl.draw_line(center + Vector2(0, -gap), center + Vector2(0, -line_end), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(0, gap), center + Vector2(0, line_end), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(-gap, 0), center + Vector2(-line_end, 0), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(gap, 0), center + Vector2(line_end, 0), col_ch, 1.5)

	# Small perpendicular ticks at line ends
	for dir: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var perp := Vector2(-dir.y, dir.x)
		var tip := center + dir * line_end
		ctrl.draw_line(tip + perp * 4, tip - perp * 4, col_ch, 1.0)

	# Center dot
	ctrl.draw_circle(center, 2.0, COL_PRIMARY)

	# Rotating scan arc (subtle)
	var scan_a := fmod(_pulse_t * 0.7, TAU)
	ctrl.draw_arc(center, r_outer + 4, scan_a, scan_a + 0.5, 8, COL_PRIMARY * Color(1, 1, 1, 0.12), 1.5, true)

	# Range ring labels
	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, center + Vector2(r_inner + 3, -3), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, COL_TEXT_DIM * Color(1, 1, 1, 0.4))
	ctrl.draw_string(font, center + Vector2(r_outer + 3, -3), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, COL_TEXT_DIM * Color(1, 1, 1, 0.4))

	# Hit markers in cockpit mode too
	_draw_hit_markers(ctrl, center)


func _draw_cockpit_pitch_ladder(ctrl: Control, center: Vector2, fwd: Vector3, font: Font) -> void:
	var pitch := rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))
	var ppd := 6.0
	var half_w := 22.0
	var clip_r := 70.0

	for deg in range(-30, 31, 5):
		if deg == 0:
			continue
		var py := center.y - (float(deg) - pitch) * ppd
		var offset_y := absf(py - center.y)
		if offset_y > clip_r:
			continue
		var alpha := 0.22 * (1.0 - offset_y / clip_r)
		var col := COL_PRIMARY * Color(1, 1, 1, alpha)
		if deg > 0:
			ctrl.draw_line(Vector2(center.x - half_w, py), Vector2(center.x - 6, py), col, 1.0)
			ctrl.draw_line(Vector2(center.x + 6, py), Vector2(center.x + half_w, py), col, 1.0)
		else:
			var dash := 4.0
			var x := center.x - half_w
			while x < center.x - 6:
				ctrl.draw_line(Vector2(x, py), Vector2(minf(x + dash, center.x - 6), py), col, 1.0)
				x += dash * 2
			x = center.x + 6
			while x < center.x + half_w:
				ctrl.draw_line(Vector2(x, py), Vector2(minf(x + dash, center.x + half_w), py), col, 1.0)
				x += dash * 2
		var lbl := "%+d" % deg
		var lbl_a := alpha / 0.22
		ctrl.draw_string(font, Vector2(center.x + half_w + 4, py + 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT_DIM * Color(1, 1, 1, lbl_a * 0.6))

	# Horizon line (deg 0)
	var horizon_y := center.y + pitch * ppd
	if absf(horizon_y - center.y) < clip_r:
		var h_alpha := 0.3 * (1.0 - absf(horizon_y - center.y) / clip_r)
		var hcol := COL_ACCENT * Color(1, 1, 1, h_alpha)
		ctrl.draw_line(Vector2(center.x - 35, horizon_y), Vector2(center.x - 6, horizon_y), hcol, 1.5)
		ctrl.draw_line(Vector2(center.x + 6, horizon_y), Vector2(center.x + 35, horizon_y), hcol, 1.5)


func _draw_cockpit_heading(ctrl: Control, font: Font, cx: float, cy: float, fwd: Vector3) -> void:
	var heading := rad_to_deg(atan2(fwd.x, -fwd.z))
	if heading < 0:
		heading += 360.0
	var pitch := rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))

	# Heading box
	var hy := cy - 112
	var heading_str := "CAP %06.1f\u00B0" % heading
	var hw := font.get_string_size(heading_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	ctrl.draw_rect(Rect2(cx - hw * 0.5 - 8, hy - 13, hw + 16, 18), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - hw * 0.5 - 8, hy - 13, hw + 16, 18), COL_PRIMARY * Color(1, 1, 1, 0.15), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - hw * 0.5, hy), heading_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_PRIMARY)

	# Pitch below
	var pitch_str := "INCL %+.1f\u00B0" % pitch
	var pw := font.get_string_size(pitch_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	ctrl.draw_string(font, Vector2(cx - pw * 0.5, hy + 16), pitch_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT_DIM)


func _draw_cockpit_speed(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	var sy := cy + 105
	var speed_str: String = "%.1f" % _ship.current_speed if _ship.current_speed < 10.0 else "%.0f" % _ship.current_speed
	var sw := font.get_string_size(speed_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x

	# Background pill
	ctrl.draw_rect(Rect2(cx - sw * 0.5 - 10, sy - 18, sw + 20, 24), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - sw * 0.5 - 10, sy - 18, sw + 20, 24), COL_PRIMARY * Color(1, 1, 1, 0.15), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - sw * 0.5, sy), speed_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COL_TEXT)

	# M/S label
	ctrl.draw_string(font, Vector2(cx - 10, sy + 14), "M/S", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)

	# Speed mode with decorative lines
	var mt := _get_mode_text()
	var mc := _get_mode_color()
	var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ctrl.draw_string(font, Vector2(cx - mw * 0.5, sy + 30), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mc)
	ctrl.draw_line(Vector2(cx - mw * 0.5 - 16, sy + 24), Vector2(cx - mw * 0.5 - 4, sy + 24), mc * Color(1, 1, 1, 0.4), 1.0)
	ctrl.draw_line(Vector2(cx + mw * 0.5 + 4, sy + 24), Vector2(cx + mw * 0.5 + 16, sy + 24), mc * Color(1, 1, 1, 0.4), 1.0)


func _draw_cockpit_bars(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	var bar_w := 58.0
	var bar_h := 5.0
	var spacing := 16.0

	# === LEFT: Shield + Hull ===
	var lx := cx - 170
	var ly := cy - 22

	# Shield
	var shd_r := _health_system.get_total_shield_ratio() if _health_system else 0.85
	ctrl.draw_string(font, Vector2(lx, ly), "BCL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, shd_r, COL_SHIELD)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(shd_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_SHIELD)

	# Hull
	ly += spacing
	var hull_r := _health_system.get_hull_ratio() if _health_system else 1.0
	var hull_c := COL_ACCENT if hull_r > 0.5 else (COL_WARN if hull_r > 0.25 else COL_DANGER)
	ctrl.draw_string(font, Vector2(lx, ly), "COQ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, hull_r, hull_c)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(hull_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, hull_c)

	# Energy
	ly += spacing
	var nrg_r := _energy_system.get_energy_ratio() if _energy_system else 0.7
	var nrg_c := Color(0.2, 0.6, 1.0, 0.9)
	ctrl.draw_string(font, Vector2(lx, ly), "NRG", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, nrg_r, nrg_c)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(nrg_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, nrg_c)

	# === RIGHT: Weapon status (per hardpoint) ===
	if _weapon_manager == null:
		return
	var rx := cx + 108
	var ry := cy - 22
	var hp_count := _weapon_manager.get_hardpoint_count()

	for i in mini(hp_count, 4):
		var status := _weapon_manager.get_hardpoint_status(i)
		if status.is_empty():
			continue
		var is_on: bool = status["enabled"]
		var wname: String = str(status["weapon_name"])
		var cd: float = float(status["cooldown_ratio"])

		# Label: slot number + abbreviated weapon name
		var label := str(i + 1) + "."
		if wname != "":
			label += wname.get_slice(" ", 0).left(3).to_upper()
		else:
			label += "---"

		var slot_col := COL_PRIMARY if is_on else COL_DANGER * Color(1, 1, 1, 0.4)
		ctrl.draw_string(font, Vector2(rx, ry), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, slot_col)
		_draw_cockpit_bar(ctrl, Vector2(rx + 32, ry - 5), 30.0, bar_h, 1.0 - cd if is_on else 0.0, COL_PRIMARY if cd < 0.1 else COL_WARN)
		ry += spacing


func _draw_cockpit_bar(ctrl: Control, pos: Vector2, w: float, h: float, ratio: float, col: Color) -> void:
	ctrl.draw_rect(Rect2(pos, Vector2(w, h)), Color(0.0, 0.02, 0.06, 0.5))
	if ratio > 0.0:
		ctrl.draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), h)), col)


func _draw_cockpit_target_info(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	if _targeting_system == null or _targeting_system.current_target == null:
		return
	if not is_instance_valid(_targeting_system.current_target):
		return
	var target := _targeting_system.current_target
	var ty := cy - 138

	var name_str := target.name as String
	if target is ShipController and (target as ShipController).ship_data:
		name_str = str((target as ShipController).ship_data.ship_class) + " \u2014 " + name_str

	var dist := _targeting_system.get_target_distance()
	var dist_str := ""
	if dist >= 0.0:
		dist_str = " | %.0fm" % dist if dist < 1000.0 else " | %.1fkm" % (dist / 1000.0)

	var full_str := "CIBLE: " + name_str + dist_str
	var tw := font.get_string_size(full_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x

	ctrl.draw_rect(Rect2(cx - tw * 0.5 - 8, ty - 12, tw + 16, 16), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - tw * 0.5 - 8, ty - 12, tw + 16, 16), COL_TARGET * Color(1, 1, 1, 0.2), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - tw * 0.5, ty), full_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TARGET)

	# Target shield/hull compact
	var t_health := target.get_node_or_null("HealthSystem") as HealthSystem
	if t_health:
		var t_shd := t_health.get_total_shield_ratio()
		var t_hull := t_health.get_hull_ratio()
		var by := ty + 8
		ctrl.draw_string(font, Vector2(cx - 60, by), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_SHIELD)
		_draw_cockpit_bar(ctrl, Vector2(cx - 52, by - 5), 45.0, 4.0, t_shd, COL_SHIELD)
		ctrl.draw_string(font, Vector2(cx + 4, by), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_ACCENT if t_hull > 0.5 else COL_DANGER)
		_draw_cockpit_bar(ctrl, Vector2(cx + 12, by - 5), 45.0, 4.0, t_hull, COL_ACCENT if t_hull > 0.5 else COL_DANGER)


func _draw_cockpit_frame(ctrl: Control) -> void:
	var s := ctrl.size
	var col := COL_PRIMARY * Color(1, 1, 1, 0.06)
	var cl := 50.0
	var m := 16.0

	# Corner accents
	ctrl.draw_line(Vector2(m, m), Vector2(m + cl, m), col, 1.5)
	ctrl.draw_line(Vector2(m, m), Vector2(m, m + cl), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), col, 1.5)
	ctrl.draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), col, 1.5)
	ctrl.draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), col, 1.5)

	# Scanline
	var sly := fmod(_scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), COL_SCANLINE, 1.0)

	# "COCKPIT" mode label top-left
	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, Vector2(m + 4, m + 14), "MODE VISÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_HEADER * Color(1, 1, 1, 0.5))


# =============================================================================
# HELPERS
# =============================================================================
func _make_ctrl(al: float, at: float, ar: float, ab: float, ol: float, ot: float, or_: float, ob: float) -> Control:
	var c := Control.new()
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = or_; c.offset_bottom = ob
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# Keep old name as alias for external callers
func _make_draw_control(al: float, at: float, ar: float, ab: float, ol: float, ot: float, or_: float, ob: float) -> Control:
	return _make_ctrl(al, at, ar, ab, ol, ot, or_, ob)


func _draw_panel_bg(ctrl: Control) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, ctrl.size), COL_BG)
	ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), COL_PRIMARY_DIM, 1.5)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 14), COL_PRIMARY, 1.5)
	ctrl.draw_line(Vector2(ctrl.size.x, 0), Vector2(ctrl.size.x, 14), COL_PRIMARY, 1.5)
	var sy: float = fmod(_scan_line_y, ctrl.size.y)
	ctrl.draw_line(Vector2(0, sy), Vector2(ctrl.size.x, sy), COL_SCANLINE, 1.0)


func _draw_bar(ctrl: Control, pos: Vector2, width: float, ratio: float, col: Color) -> void:
	var h := 8.0
	ctrl.draw_rect(Rect2(pos, Vector2(width, h)), COL_BG_DARK)
	if ratio > 0.0:
		var fw: float = width * clamp(ratio, 0.0, 1.0)
		ctrl.draw_rect(Rect2(pos, Vector2(fw, h)), col)
		ctrl.draw_rect(Rect2(pos + Vector2(fw - 2, 0), Vector2(2, h)), Color(col.r, col.g, col.b, 1.0))
	# Center tick + bottom edge
	ctrl.draw_line(Vector2(pos.x + width * 0.5, pos.y), Vector2(pos.x + width * 0.5, pos.y + h), Color(0.0, 0.05, 0.1, 0.5), 1.0)
	ctrl.draw_line(Vector2(pos.x, pos.y + h), Vector2(pos.x + width, pos.y + h), COL_BORDER, 1.0)

# Legacy name used by target panel hull bar
func _draw_status_bar(ctrl: Control, pos: Vector2, width: float, ratio: float, col: Color) -> void:
	_draw_bar(ctrl, pos, width, ratio, col)


func _get_mode_text() -> String:
	if _ship == null: return "---"
	match _ship.speed_mode:
		Constants.SpeedMode.BOOST: return "TURBO"
		Constants.SpeedMode.CRUISE: return "CROISIÈRE"
	return "NORMAL"


func _get_mode_color() -> Color:
	if _ship == null: return COL_PRIMARY
	match _ship.speed_mode:
		Constants.SpeedMode.BOOST: return COL_BOOST
		Constants.SpeedMode.CRUISE: return COL_CRUISE
	return COL_PRIMARY
