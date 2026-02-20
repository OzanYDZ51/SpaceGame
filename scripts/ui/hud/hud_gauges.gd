class_name HudGauges
extends Control

# =============================================================================
# HUD Gauges — Crosshair, speed arc, compass, warnings, top bar
# =============================================================================

var ship = null
var health_system = null
var targeting_system = null
var system_transition = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0
var warning_flash: float = 0.0

# Ref to damage feedback component to draw hit markers on crosshair
var damage_feedback: HudDamageFeedback = null

var _crosshair: Control = null
var _speed_arc: Control = null
var _top_bar: Control = null
var _compass: Control = null
var _warnings: Control = null

const NAV_COL_GATE: Color = Color(0.15, 0.6, 1.0, 0.85)
const COMPASS_COL_STATION: Color = Color(0.2, 0.85, 0.8, 0.85)
const COMPASS_COL_GATE: Color = Color(0.15, 0.6, 1.0, 0.85)
const COMPASS_COL_PLANET: Color = Color(0.6, 0.8, 1.0, 0.75)
const COMPASS_COL_STAR: Color = Color(1.0, 0.85, 0.4, 0.75)
const COMPASS_COL_TARGET: Color = Color(1.0, 0.3, 0.2, 0.9)
const COMPASS_COL_FLEET: Color = Color(0.4, 0.65, 1.0, 0.9)
const COMPASS_POI_TYPES: Array = [
	EntityRegistrySystem.EntityType.STATION,
	EntityRegistrySystem.EntityType.JUMP_GATE,
	EntityRegistrySystem.EntityType.PLANET,
	EntityRegistrySystem.EntityType.STAR,
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_crosshair = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -40, -40, 40, 40)
	_crosshair.draw.connect(_draw_crosshair.bind(_crosshair))
	add_child(_crosshair)

	_speed_arc = HudDrawHelpers.make_ctrl(0.5, 1.0, 0.5, 1.0, -160, -130, 160, -10)
	_speed_arc.draw.connect(_draw_speed_arc.bind(_speed_arc))
	add_child(_speed_arc)

	_top_bar = HudDrawHelpers.make_ctrl(0.5, 0.0, 0.5, 0.0, -320, 8, 320, 58)
	_top_bar.draw.connect(_draw_top_bar.bind(_top_bar))
	add_child(_top_bar)

	_compass = HudDrawHelpers.make_ctrl(0.5, 0.0, 0.5, 0.0, -120, 46, 120, 80)
	_compass.draw.connect(_draw_compass.bind(_compass))
	add_child(_compass)

	_warnings = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -150, 60, 150, 100)
	_warnings.draw.connect(_draw_warnings.bind(_warnings))
	add_child(_warnings)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_crosshair.visible = not is_cockpit
	_speed_arc.visible = not is_cockpit
	_top_bar.visible = not is_cockpit
	_compass.visible = not is_cockpit


func redraw_fast() -> void:
	_crosshair.queue_redraw()
	_warnings.queue_redraw()
	_compass.queue_redraw()


func redraw_slow() -> void:
	_speed_arc.queue_redraw()
	_top_bar.queue_redraw()


# =============================================================================
# CROSSHAIR
# =============================================================================
func _draw_crosshair(ctrl: Control) -> void:
	var c =ctrl.size / 2.0
	var pulse: float = sin(pulse_t * 2.0) * 0.1 + 0.9
	var col =UITheme.PRIMARY * Color(1, 1, 1, pulse)
	var gap =5.0
	var line_len =12.0
	ctrl.draw_line(c + Vector2(0, -gap), c + Vector2(0, -gap - line_len), col, 1.5)
	ctrl.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + line_len), col, 1.5)
	ctrl.draw_line(c + Vector2(-gap, 0), c + Vector2(-gap - line_len, 0), col, 1.5)
	ctrl.draw_line(c + Vector2(gap, 0), c + Vector2(gap + line_len, 0), col, 1.5)
	ctrl.draw_circle(c, 1.5, col)

	if damage_feedback:
		damage_feedback.draw_hit_markers(ctrl, c)


# =============================================================================
# SPEED ARC
# =============================================================================
func _draw_speed_arc(ctrl: Control) -> void:
	if ship == null:
		return
	var cx =ctrl.size.x / 2.0
	var cy =ctrl.size.y + 20.0
	var r =120.0
	var a0 =PI + 0.4
	var a1 =TAU - 0.4
	var ar =a1 - a0

	ctrl.draw_arc(Vector2(cx, cy), r, a0, a1, 48, UITheme.PRIMARY_FAINT, 3.0, true)
	ctrl.draw_arc(Vector2(cx, cy), r - 8, a0, a1, 48, UITheme.PRIMARY_FAINT, 1.0, true)

	var max_spd =Constants.get_max_speed(ship.speed_mode)
	for i in 11:
		var t =float(i) / 10.0
		var angle =a0 + t * ar
		var p1 =Vector2(cx + cos(angle) * (r - 12), cy + sin(angle) * (r - 12))
		var p2 =Vector2(cx + cos(angle) * (r - 4), cy + sin(angle) * (r - 4))
		ctrl.draw_line(p1, p2, UITheme.PRIMARY if (i == 0 or i == 10 or i == 5) else UITheme.PRIMARY_DIM, 1.0)

	var ratio: float = clamp(ship.current_speed / max_spd, 0.0, 1.0)
	if ratio > 0.01:
		var fe =a0 + ratio * ar
		var fc =HudDrawHelpers.get_mode_color(ship)
		ctrl.draw_arc(Vector2(cx, cy), r - 4, a0, fe, 32, fc, 5.0, true)
		ctrl.draw_circle(Vector2(cx + cos(fe) * (r - 4), cy + sin(fe) * (r - 4)), 3.0, fc)

	var font =UITheme.get_font_medium()
	var speed_label: String
	var speed_unit: String
	if ship.current_speed >= 1000.0:
		speed_label = "%.1f" % (ship.current_speed / 1000.0)
		speed_unit = "KM/S"
	elif ship.current_speed < 10.0:
		speed_label = "%.1f" % ship.current_speed
		speed_unit = "M/S"
	else:
		speed_label = "%.0f" % ship.current_speed
		speed_unit = "M/S"
	var sw =font.get_string_size(speed_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 28).x
	ctrl.draw_string(font, Vector2(cx - sw / 2.0, cy - 50), speed_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UITheme.TEXT)
	var uw =font.get_string_size(speed_unit, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	ctrl.draw_string(font, Vector2(cx - uw / 2.0, cy - 35), speed_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT_DIM)

	var mt =HudDrawHelpers.get_mode_text(ship)
	var mc =HudDrawHelpers.get_mode_color(ship)
	var mw =font.get_string_size(mt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
	ctrl.draw_string(font, Vector2(cx - mw / 2.0, cy - 20), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, mc)
	ctrl.draw_line(Vector2(cx - mw / 2.0 - 18, cy - 26), Vector2(cx - mw / 2.0 - 4, cy - 26), mc * Color(1, 1, 1, 0.5), 1.0)
	ctrl.draw_line(Vector2(cx + mw / 2.0 + 4, cy - 26), Vector2(cx + mw / 2.0 + 18, cy - 26), mc * Color(1, 1, 1, 0.5), 1.0)

	var mx ="%.0f" % max_spd
	var mxw =font.get_string_size(mx, HORIZONTAL_ALIGNMENT_CENTER, -1, UITheme.FONT_SIZE_TINY).x
	var mp =Vector2(cx + cos(a1) * (r + 14), cy + sin(a1) * (r + 14))
	ctrl.draw_string(font, mp - Vector2(mxw / 2.0, 0), mx, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


# =============================================================================
# TOP BAR
# =============================================================================
func _draw_top_bar(ctrl: Control) -> void:
	var font =UITheme.get_font_medium()
	var w =ctrl.size.x
	var h =ctrl.size.y
	var cx =w / 2.0

	# Bottom edge
	ctrl.draw_line(Vector2(0, h - 1), Vector2(w, h - 1), UITheme.BORDER, 1.0)
	# Corner accents
	var cl =10.0
	ctrl.draw_line(Vector2(0, 0), Vector2(cl, 0), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, cl), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(w, 0), Vector2(w - cl, 0), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(w, 0), Vector2(w, cl), UITheme.PRIMARY_DIM, 1.0)

	if ship == null:
		return

	# === ROW 1: System name — Flight mode — Speed ===
	var row1_y =18.0

	# System name (left)
	var sys_name ="---"
	if system_transition and system_transition.current_system_data:
		sys_name = system_transition.current_system_data.system_name.to_upper()
	ctrl.draw_string(font, Vector2(12, row1_y), sys_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.PRIMARY)

	# Flight mode (center)
	var mt =HudDrawHelpers.get_mode_text(ship)
	var mc =HudDrawHelpers.get_mode_color(ship)
	var mw =font.get_string_size(mt, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
	ctrl.draw_string(font, Vector2(cx - mw / 2.0, row1_y), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, mc)
	ctrl.draw_line(Vector2(cx - mw / 2.0 - 20, row1_y - 6), Vector2(cx - mw / 2.0 - 4, row1_y - 6), mc * Color(1, 1, 1, 0.5), 1.0)
	ctrl.draw_line(Vector2(cx + mw / 2.0 + 4, row1_y - 6), Vector2(cx + mw / 2.0 + 20, row1_y - 6), mc * Color(1, 1, 1, 0.5), 1.0)

	# Speed (right)
	var st: String
	if ship.current_speed >= 1000.0:
		st = "%.1f km/s" % (ship.current_speed / 1000.0)
	else:
		st = "%.0f m/s" % ship.current_speed
	var s_w =font.get_string_size(st, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14).x
	ctrl.draw_string(font, Vector2(w - s_w - 12, row1_y), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)

	# === Separator ===
	ctrl.draw_line(Vector2(12, 25), Vector2(w - 12, 25), UITheme.PRIMARY_FAINT, 1.0)

	# === ROW 2: AV — CAP — INCL — POS ===
	var row2_y =40.0

	# AV status (dot + label)
	var fa_on =ship.flight_assist
	var fa_col =UITheme.ACCENT if fa_on else UITheme.DANGER
	ctrl.draw_circle(Vector2(16, row2_y - 4), 3.0, fa_col)
	ctrl.draw_string(font, Vector2(24, row2_y), Locale.t("hud.flight_assist_label") if fa_on else Locale.t("hud.flight_assist_off_label"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, fa_col)

	# CAP heading
	var fwd =-ship.global_transform.basis.z
	var heading: float = rad_to_deg(atan2(fwd.x, -fwd.z))
	if heading < 0: heading += 360.0
	ctrl.draw_string(font, Vector2(58, row2_y), Locale.t("hud.heading"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	ctrl.draw_string(font, Vector2(86, row2_y), "%06.2f\u00B0" % heading, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# INCL pitch
	var pitch: float = rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))
	ctrl.draw_string(font, Vector2(170, row2_y), Locale.t("hud.pitch"), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	ctrl.draw_string(font, Vector2(204, row2_y), "%+.1f\u00B0" % pitch, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT)

	# FPS + MS + connection (right of INCL, before POS)
	if OptionsScreen.show_fps:
		var fps_val: int = int(Engine.get_frames_per_second())
		var ms_val: float = 1000.0 / maxf(fps_val, 1) if fps_val > 0 else 0.0
		var fps_col: Color = UITheme.ACCENT if fps_val >= 55 else (UITheme.WARNING if fps_val >= 30 else UITheme.DANGER)
		var perf_str: String = "%d FPS  %.1f ms" % [fps_val, ms_val]
		var px: float = 270.0
		ctrl.draw_string(font, Vector2(px, row2_y), perf_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, fps_col)
		# Connection status
		var net_x: float = px + font.get_string_size(perf_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x + 12.0
		var net_str: String
		var net_col: Color
		match NetworkManager.connection_state:
			NetworkManager.ConnectionState.CONNECTED:
				var peer_count: int = NetworkManager.peers.size()
				net_str = "ONLINE (%d)" % peer_count
				net_col = UITheme.ACCENT
			NetworkManager.ConnectionState.CONNECTING:
				net_str = "CONNECTING..."
				net_col = UITheme.WARNING
			_:
				net_str = "OFFLINE"
				net_col = UITheme.TEXT_DIM
		ctrl.draw_string(font, Vector2(net_x, row2_y), net_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, net_col)

	# POS (right-aligned)
	var pos_str =FloatingOrigin.get_universe_pos_string() if FloatingOrigin else "0, 0, 0"
	var pos_w =font.get_string_size(pos_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY).x
	ctrl.draw_string(font, Vector2(w - pos_w - 12, row2_y), pos_str, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)


# =============================================================================
# COMPASS
# =============================================================================
func _draw_compass(ctrl: Control) -> void:
	if ship == null:
		return
	var font =UITheme.get_font_medium()
	var w =ctrl.size.x
	var h =ctrl.size.y
	var cx =w / 2.0
	# Top 14px reserved for POI markers, bottom 20px for compass strip
	var strip_top: float = 14.0
	ctrl.draw_rect(Rect2(0, strip_top, w, h - strip_top), UITheme.BG_DARK)
	ctrl.draw_line(Vector2(0, h - 1), Vector2(w, h - 1), UITheme.BORDER, 1.0)

	var fwd =-ship.global_transform.basis.z
	var heading_deg: float = rad_to_deg(atan2(fwd.x, -fwd.z))
	if heading_deg < 0: heading_deg += 360.0
	var heading_rad: float = atan2(fwd.x, -fwd.z)
	var ppd =3.0
	var labels ={0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

	for d in range(-50, 51):
		var wd: float = fmod(heading_deg + d + 360.0, 360.0)
		var sx =cx + d * ppd
		if sx < 0 or sx > w:
			continue
		var rd =int(round(wd)) % 360
		if rd % 10 == 0:
			ctrl.draw_line(Vector2(sx, h - (4.0 if rd % 30 == 0 else 2.0) - 2), Vector2(sx, h - 2), UITheme.PRIMARY_DIM, 1.0)
		if rd in labels and abs(d) < 48:
			var lbl: String = labels[rd]
			var lw =font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, UITheme.FONT_SIZE_TINY).x
			ctrl.draw_string(font, Vector2(sx - lw / 2.0, strip_top + 12), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.PRIMARY)
	# Center tick
	ctrl.draw_line(Vector2(cx, strip_top), Vector2(cx, strip_top + 4), UITheme.TEXT, 1.5)

	# --- POI markers (Star Citizen style chevrons in the top 14px zone) ---
	var half_fov_deg: float = 40.0
	var player_upos: Array = FloatingOrigin.to_universe_pos(ship.global_position)
	var px: float = player_upos[0]
	var pz: float = player_upos[2]

	# Get current target id
	var target_id: String = ""
	if targeting_system and targeting_system.has_method("get_target_id"):
		target_id = targeting_system.get_target_id()
	elif targeting_system and "current_target" in targeting_system:
		var t = targeting_system.current_target
		if t != null and is_instance_valid(t):
			var t_ent: Dictionary = EntityRegistry.get_entity(t.name)
			if not t_ent.is_empty():
				target_id = t_ent["id"]

	# Collect POI markers: [{bearing_delta, label, color, is_target}]
	var markers: Array = []
	for ent in EntityRegistry.get_all().values():
		var etype: int = ent["type"]
		var is_target: bool = ent["id"] == target_id and target_id != ""
		var is_poi: bool = etype in COMPASS_POI_TYPES
		if not is_poi and not is_target:
			continue

		var dx: float = ent["pos_x"] - px
		var dz: float = ent["pos_z"] - pz
		var bearing: float = atan2(dx, -dz)
		var delta: float = bearing - heading_rad
		# Normalize to [-PI, PI]
		while delta > PI: delta -= TAU
		while delta < -PI: delta += TAU
		var delta_deg: float = rad_to_deg(delta)

		if abs(delta_deg) > half_fov_deg:
			continue

		var marker_col: Color
		var marker_label: String
		if is_target:
			marker_col = COMPASS_COL_TARGET
			marker_label = "TGT"
		else:
			match etype:
				EntityRegistrySystem.EntityType.STATION:
					marker_col = COMPASS_COL_STATION
					marker_label = "STA"
				EntityRegistrySystem.EntityType.JUMP_GATE:
					marker_col = COMPASS_COL_GATE
					marker_label = "JMP"
				EntityRegistrySystem.EntityType.PLANET:
					marker_col = COMPASS_COL_PLANET
					marker_label = "PLN"
				EntityRegistrySystem.EntityType.STAR:
					marker_col = COMPASS_COL_STAR
					marker_label = "SOL"
				_:
					marker_col = UITheme.PRIMARY
					marker_label = "???"

		markers.append({"delta_deg": delta_deg, "label": marker_label, "color": marker_col, "is_target": is_target})

	# Sort: targets on top (drawn last)
	markers.sort_custom(func(a, b): return not a["is_target"] and b["is_target"])

	for m in markers:
		var sx: float = cx + m["delta_deg"] * ppd
		sx = clampf(sx, 6.0, w - 6.0)
		var mc: Color = m["color"]
		# Chevron pointing down (▽) at top of compass
		var cy_m: float = 3.0
		var cs: float = 4.0 if m["is_target"] else 3.0
		ctrl.draw_line(Vector2(sx - cs, cy_m), Vector2(sx, cy_m + cs), mc, 1.5 if m["is_target"] else 1.0)
		ctrl.draw_line(Vector2(sx + cs, cy_m), Vector2(sx, cy_m + cs), mc, 1.5 if m["is_target"] else 1.0)
		# Small label
		var lbl: String = m["label"]
		var lw: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 8).x
		ctrl.draw_string(font, Vector2(sx - lw / 2.0, cy_m + cs + 7), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(mc.r, mc.g, mc.b, 0.7))


# =============================================================================
# WARNINGS
# =============================================================================
func _draw_warnings(ctrl: Control) -> void:
	if ship == null:
		return
	var font =UITheme.get_font_medium()
	var cx =ctrl.size.x / 2.0

	if not ship.flight_assist:
		var flash =absf(sin(warning_flash)) * 0.6 + 0.4
		var wt =Locale.t("hud.assist_off")
		var tw =font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 20), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.DANGER * Color(1, 1, 1, flash))

	if ship.combat_locked:
		var flash =absf(sin(warning_flash * 1.5)) * 0.6 + 0.4
		var wt =Locale.t("hud.cruise_blocked")
		var tw =font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 38), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.DANGER * Color(1, 1, 1, flash))
	elif ship.speed_mode == Constants.SpeedMode.CRUISE and ship.current_speed > 2500:
		var wt =Locale.t("hud.high_speed")
		var tw =font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 38), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.WARNING)

	if health_system and health_system.get_total_shield_ratio() < 0.1:
		var flash =absf(sin(warning_flash * 1.5)) * 0.7 + 0.3
		var wt =Locale.t("hud.low_shields")
		var tw =font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 56), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.WARNING * Color(1, 1, 1, flash))

	if health_system and health_system.get_hull_ratio() < 0.25:
		var flash =absf(sin(warning_flash * 2.0)) * 0.8 + 0.2
		var wt =Locale.t("hud.hull_critical")
		var tw =font.get_string_size(wt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		ctrl.draw_string(font, Vector2(cx - tw / 2.0, 74), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.DANGER * Color(1, 1, 1, flash))

	# Autopilot indicator
	if ship and ship.autopilot_active:
		var ap_col =NAV_COL_GATE
		var pulse =0.7 + sin(warning_flash * 0.8) * 0.3
		var ap_text =Locale.t("hud.autopilot") + " → " + ship.autopilot_target_name.to_upper()
		var ap_ent: Dictionary = EntityRegistry.get_entity(ship.autopilot_target_id)
		if not ap_ent.is_empty():
			var player_upos: Array = FloatingOrigin.to_universe_pos(ship.global_position)
			var dx: float = ap_ent["pos_x"] - player_upos[0]
			var dy: float = ap_ent["pos_y"] - player_upos[1]
			var dz: float = ap_ent["pos_z"] - player_upos[2]
			var ap_dist: float = sqrt(dx * dx + dy * dy + dz * dz)
			ap_text += "  " + HudDrawHelpers.format_nav_distance(ap_dist)
		var ap_tw =font.get_string_size(ap_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		var pill_w =ap_tw + 20.0
		ctrl.draw_rect(Rect2(cx - pill_w / 2.0, -8, pill_w, 20), Color(0.0, 0.05, 0.15, 0.7 * pulse))
		ctrl.draw_rect(Rect2(cx - pill_w / 2.0, -8, pill_w, 20), Color(ap_col.r, ap_col.g, ap_col.b, 0.4 * pulse), false, 1.0)
		ctrl.draw_string(font, Vector2(cx - ap_tw / 2.0, 6), ap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(ap_col.r, ap_col.g, ap_col.b, pulse))
