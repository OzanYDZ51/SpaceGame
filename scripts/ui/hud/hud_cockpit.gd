class_name HudCockpit
extends Control

# =============================================================================
# HUD Cockpit — Fighter jet style targeting system (V key toggle)
# =============================================================================

var ship: ShipController = null
var health_system: HealthSystem = null
var energy_system: EnergySystem = null
var targeting_system: TargetingSystem = null
var weapon_manager: WeaponManager = null
var damage_feedback: HudDamageFeedback = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0
var warning_flash: float = 0.0

var _cockpit_overlay: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cockpit_overlay = HudDrawHelpers.make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_cockpit_overlay.draw.connect(_draw_cockpit_hud.bind(_cockpit_overlay))
	_cockpit_overlay.visible = false
	add_child(_cockpit_overlay)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_cockpit_overlay.visible = is_cockpit


func redraw() -> void:
	if _cockpit_overlay.visible:
		_cockpit_overlay.queue_redraw()


# =============================================================================
# MAIN COCKPIT DRAW
# =============================================================================
func _draw_cockpit_hud(ctrl: Control) -> void:
	if ship == null:
		return
	var s := ctrl.size
	var cx := s.x * 0.5
	var cy := s.y * 0.5
	var center := Vector2(cx, cy)
	var font := ThemeDB.fallback_font
	var fwd := -ship.global_transform.basis.z

	_draw_cockpit_reticle(ctrl, center, font)
	_draw_cockpit_pitch_ladder(ctrl, center, fwd, font)
	_draw_cockpit_heading(ctrl, font, cx, cy, fwd)
	_draw_cockpit_speed(ctrl, font, cx, cy)
	_draw_cockpit_bars(ctrl, font, cx, cy)
	_draw_cockpit_target_info(ctrl, font, cx, cy)

	if not ship.flight_assist:
		var flash := absf(sin(warning_flash)) * 0.5 + 0.5
		var wt := "AV DÉSACTIVÉ"
		var ww := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		ctrl.draw_string(font, Vector2(cx - ww * 0.5, cy + 140), wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.DANGER * Color(1, 1, 1, flash))

	_draw_cockpit_frame(ctrl)


# =============================================================================
# RETICLE
# =============================================================================
func _draw_cockpit_reticle(ctrl: Control, center: Vector2, font: Font) -> void:
	var pulse := sin(pulse_t * 1.5) * 0.06 + 0.94
	var r_outer := 88.0
	var r_inner := 50.0

	ctrl.draw_arc(center, r_outer, 0, TAU, 64, UITheme.PRIMARY * Color(1, 1, 1, 0.22 * pulse), 1.0, true)

	for i in 12:
		var angle := float(i) * TAU / 12.0 - PI * 0.5
		var is_major := i % 3 == 0
		var tick_len := 12.0 if is_major else 5.0
		var tick_w := 2.0 if is_major else 1.0
		var p1 := center + Vector2(cos(angle), sin(angle)) * r_outer
		var p2 := center + Vector2(cos(angle), sin(angle)) * (r_outer - tick_len)
		ctrl.draw_line(p1, p2, UITheme.PRIMARY * Color(1, 1, 1, 0.5 if is_major else 0.3), tick_w)

	ctrl.draw_arc(center, r_inner, 0, TAU, 48, UITheme.PRIMARY * Color(1, 1, 1, 0.4), 1.5, true)

	var gap := 10.0
	var line_end := 40.0
	var col_ch := UITheme.PRIMARY * Color(1, 1, 1, 0.85)
	ctrl.draw_line(center + Vector2(0, -gap), center + Vector2(0, -line_end), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(0, gap), center + Vector2(0, line_end), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(-gap, 0), center + Vector2(-line_end, 0), col_ch, 1.5)
	ctrl.draw_line(center + Vector2(gap, 0), center + Vector2(line_end, 0), col_ch, 1.5)

	for dir: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var perp := Vector2(-dir.y, dir.x)
		var tip := center + dir * line_end
		ctrl.draw_line(tip + perp * 4, tip - perp * 4, col_ch, 1.0)

	ctrl.draw_circle(center, 2.0, UITheme.PRIMARY)

	var scan_a := fmod(pulse_t * 0.7, TAU)
	ctrl.draw_arc(center, r_outer + 4, scan_a, scan_a + 0.5, 8, UITheme.PRIMARY * Color(1, 1, 1, 0.12), 1.5, true)

	ctrl.draw_string(font, center + Vector2(r_inner + 3, -3), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UITheme.TEXT_DIM * Color(1, 1, 1, 0.4))
	ctrl.draw_string(font, center + Vector2(r_outer + 3, -3), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UITheme.TEXT_DIM * Color(1, 1, 1, 0.4))

	if damage_feedback:
		damage_feedback.draw_hit_markers(ctrl, center)


# =============================================================================
# PITCH LADDER
# =============================================================================
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
		var col := UITheme.PRIMARY * Color(1, 1, 1, alpha)
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
		ctrl.draw_string(font, Vector2(center.x + half_w + 4, py + 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT_DIM * Color(1, 1, 1, lbl_a * 0.6))

	var horizon_y := center.y + pitch * ppd
	if absf(horizon_y - center.y) < clip_r:
		var h_alpha := 0.3 * (1.0 - absf(horizon_y - center.y) / clip_r)
		var hcol := UITheme.ACCENT * Color(1, 1, 1, h_alpha)
		ctrl.draw_line(Vector2(center.x - 35, horizon_y), Vector2(center.x - 6, horizon_y), hcol, 1.5)
		ctrl.draw_line(Vector2(center.x + 6, horizon_y), Vector2(center.x + 35, horizon_y), hcol, 1.5)


# =============================================================================
# HEADING
# =============================================================================
func _draw_cockpit_heading(ctrl: Control, font: Font, cx: float, cy: float, fwd: Vector3) -> void:
	var heading := rad_to_deg(atan2(fwd.x, -fwd.z))
	if heading < 0:
		heading += 360.0
	var pitch := rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))

	var hy := cy - 112
	var heading_str := "CAP %06.1f\u00B0" % heading
	var hw := font.get_string_size(heading_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	ctrl.draw_rect(Rect2(cx - hw * 0.5 - 8, hy - 13, hw + 16, 18), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - hw * 0.5 - 8, hy - 13, hw + 16, 18), UITheme.PRIMARY * Color(1, 1, 1, 0.15), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - hw * 0.5, hy), heading_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.PRIMARY)

	var pitch_str := "INCL %+.1f\u00B0" % pitch
	var pw := font.get_string_size(pitch_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	ctrl.draw_string(font, Vector2(cx - pw * 0.5, hy + 16), pitch_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_DIM)


# =============================================================================
# SPEED
# =============================================================================
func _draw_cockpit_speed(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	var sy := cy + 105
	var speed_str: String = "%.1f" % ship.current_speed if ship.current_speed < 10.0 else "%.0f" % ship.current_speed
	var sw := font.get_string_size(speed_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x

	ctrl.draw_rect(Rect2(cx - sw * 0.5 - 10, sy - 18, sw + 20, 24), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - sw * 0.5 - 10, sy - 18, sw + 20, 24), UITheme.PRIMARY * Color(1, 1, 1, 0.15), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - sw * 0.5, sy), speed_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UITheme.TEXT)

	ctrl.draw_string(font, Vector2(cx - 10, sy + 14), "M/S", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)

	var mt := HudDrawHelpers.get_mode_text(ship)
	var mc := HudDrawHelpers.get_mode_color(ship)
	var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ctrl.draw_string(font, Vector2(cx - mw * 0.5, sy + 30), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mc)
	ctrl.draw_line(Vector2(cx - mw * 0.5 - 16, sy + 24), Vector2(cx - mw * 0.5 - 4, sy + 24), mc * Color(1, 1, 1, 0.4), 1.0)
	ctrl.draw_line(Vector2(cx + mw * 0.5 + 4, sy + 24), Vector2(cx + mw * 0.5 + 16, sy + 24), mc * Color(1, 1, 1, 0.4), 1.0)


# =============================================================================
# BARS (shield, hull, energy, weapon status)
# =============================================================================
func _draw_cockpit_bars(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	var bar_w := 58.0
	var bar_h := 5.0
	var spacing := 16.0

	var lx := cx - 170
	var ly := cy - 22

	var shd_r := health_system.get_total_shield_ratio() if health_system else 0.85
	ctrl.draw_string(font, Vector2(lx, ly), "BCL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, shd_r, UITheme.SHIELD)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(shd_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.SHIELD)

	ly += spacing
	var hull_r := health_system.get_hull_ratio() if health_system else 1.0
	var hull_c := UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
	ctrl.draw_string(font, Vector2(lx, ly), "COQ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, hull_r, hull_c)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(hull_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, hull_c)

	ly += spacing
	var nrg_r := energy_system.get_energy_ratio() if energy_system else 0.7
	var nrg_c := Color(0.2, 0.6, 1.0, 0.9)
	ctrl.draw_string(font, Vector2(lx, ly), "NRG", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	_draw_cockpit_bar(ctrl, Vector2(lx + 26, ly - 5), bar_w, bar_h, nrg_r, nrg_c)
	ctrl.draw_string(font, Vector2(lx + 26 + bar_w + 4, ly), "%d%%" % int(nrg_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, nrg_c)

	if weapon_manager == null:
		return
	var rx := cx + 108
	var ry := cy - 22
	var hp_count := weapon_manager.get_hardpoint_count()

	for i in mini(hp_count, 4):
		var status := weapon_manager.get_hardpoint_status(i)
		if status.is_empty():
			continue
		var is_on: bool = status["enabled"]
		var wname: String = str(status["weapon_name"])
		var cd: float = float(status["cooldown_ratio"])

		var label := str(i + 1) + "."
		if wname != "":
			label += wname.get_slice(" ", 0).left(3).to_upper()
		else:
			label += "---"

		var slot_col := UITheme.PRIMARY if is_on else UITheme.DANGER * Color(1, 1, 1, 0.4)
		ctrl.draw_string(font, Vector2(rx, ry), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, slot_col)
		_draw_cockpit_bar(ctrl, Vector2(rx + 32, ry - 5), 30.0, bar_h, 1.0 - cd if is_on else 0.0, UITheme.PRIMARY if cd < 0.1 else UITheme.WARNING)
		ry += spacing


func _draw_cockpit_bar(ctrl: Control, pos: Vector2, w: float, h: float, ratio: float, col: Color) -> void:
	ctrl.draw_rect(Rect2(pos, Vector2(w, h)), Color(0.0, 0.02, 0.06, 0.5))
	if ratio > 0.0:
		ctrl.draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), h)), col)


# =============================================================================
# TARGET INFO
# =============================================================================
func _draw_cockpit_target_info(ctrl: Control, font: Font, cx: float, cy: float) -> void:
	if targeting_system == null or targeting_system.current_target == null:
		return
	if not is_instance_valid(targeting_system.current_target):
		return
	var target := targeting_system.current_target
	var ty := cy - 138

	var name_str := target.name as String
	if target is ShipController and (target as ShipController).ship_data:
		name_str = str((target as ShipController).ship_data.ship_class) + " \u2014 " + name_str

	var dist := targeting_system.get_target_distance()
	var dist_str := ""
	if dist >= 0.0:
		dist_str = " | %.0fm" % dist if dist < 1000.0 else " | %.1fkm" % (dist / 1000.0)

	var full_str := "CIBLE: " + name_str + dist_str
	var tw := font.get_string_size(full_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x

	ctrl.draw_rect(Rect2(cx - tw * 0.5 - 8, ty - 12, tw + 16, 16), Color(0.0, 0.02, 0.06, 0.55))
	ctrl.draw_rect(Rect2(cx - tw * 0.5 - 8, ty - 12, tw + 16, 16), UITheme.TARGET * Color(1, 1, 1, 0.2), false, 1.0)
	ctrl.draw_string(font, Vector2(cx - tw * 0.5, ty), full_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TARGET)

	var t_health := target.get_node_or_null("HealthSystem") as HealthSystem
	if t_health:
		var t_shd := t_health.get_total_shield_ratio()
		var t_hull := t_health.get_hull_ratio()
		var by := ty + 8
		ctrl.draw_string(font, Vector2(cx - 60, by), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.SHIELD)
		_draw_cockpit_bar(ctrl, Vector2(cx - 52, by - 5), 45.0, 4.0, t_shd, UITheme.SHIELD)
		ctrl.draw_string(font, Vector2(cx + 4, by), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.ACCENT if t_hull > 0.5 else UITheme.DANGER)
		_draw_cockpit_bar(ctrl, Vector2(cx + 12, by - 5), 45.0, 4.0, t_hull, UITheme.ACCENT if t_hull > 0.5 else UITheme.DANGER)


# =============================================================================
# FRAME
# =============================================================================
func _draw_cockpit_frame(ctrl: Control) -> void:
	var s := ctrl.size
	var col := UITheme.PRIMARY * Color(1, 1, 1, 0.06)
	var cl := 50.0
	var m := 16.0

	ctrl.draw_line(Vector2(m, m), Vector2(m + cl, m), col, 1.5)
	ctrl.draw_line(Vector2(m, m), Vector2(m, m + cl), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), col, 1.5)
	ctrl.draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), col, 1.5)
	ctrl.draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), col, 1.5)
	ctrl.draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), col, 1.5)

	var sly := fmod(scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), UITheme.SCANLINE, 1.0)

	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, Vector2(m + 4, m + 14), "MODE VISÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.HEADER * Color(1, 1, 1, 0.5))
