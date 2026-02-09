class_name HudStatusPanels
extends Control

# =============================================================================
# HUD Status Panels — Left panel (systems/shields/energy), right panel (nav),
# economy panel (top-left)
# =============================================================================

var ship: ShipController = null
var health_system: HealthSystem = null
var energy_system: EnergySystem = null
var player_economy: PlayerEconomy = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0
var warning_flash: float = 0.0

var _left_panel: Control = null
var _right_panel: Control = null
var _economy_panel: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_left_panel = HudDrawHelpers.make_ctrl(0.0, 0.5, 0.0, 0.5, 16, -195, 242, 195)
	_left_panel.draw.connect(_draw_left_panel.bind(_left_panel))
	add_child(_left_panel)

	_right_panel = HudDrawHelpers.make_ctrl(1.0, 0.5, 1.0, 0.5, -242, -120, -16, 120)
	_right_panel.draw.connect(_draw_right_panel.bind(_right_panel))
	add_child(_right_panel)

	_economy_panel = HudDrawHelpers.make_ctrl(0.0, 0.0, 0.0, 0.0, 16, 12, 230, 180)
	_economy_panel.draw.connect(_draw_economy_panel.bind(_economy_panel))
	add_child(_economy_panel)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_left_panel.visible = not is_cockpit
	_right_panel.visible = not is_cockpit
	_economy_panel.visible = not is_cockpit


func redraw_slow() -> void:
	_left_panel.queue_redraw()
	_right_panel.queue_redraw()
	_economy_panel.queue_redraw()


# =============================================================================
# LEFT PANEL
# =============================================================================
func _draw_left_panel(ctrl: Control) -> void:
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y)
	var font := ThemeDB.fallback_font
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var y := 22.0

	y = HudDrawHelpers.draw_section_header(ctrl, font, x, y, w, "SYSTÈMES")
	y += 2

	# Hull
	var hull_r := health_system.get_hull_ratio() if health_system else 1.0
	var hull_c := UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
	ctrl.draw_string(font, Vector2(x, y), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
	var hp := "%d%%" % int(hull_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hull_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)
	y += 20

	# Shield
	var shd_r := health_system.get_total_shield_ratio() if health_system else 0.85
	ctrl.draw_string(font, Vector2(x, y), "BOUCLIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
	var sp := "%d%%" % int(shd_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.SHIELD)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, shd_r, UITheme.SHIELD)
	y += 20

	# Energy
	var nrg_r := energy_system.get_energy_ratio() if energy_system else 0.7
	var nrg_c := Color(0.2, 0.6, 1.0, 0.9)
	ctrl.draw_string(font, Vector2(x, y), "ÉNERGIE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
	var np := "%d%%" % int(nrg_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(np, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, y), np, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, nrg_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, nrg_r, nrg_c)
	y += 24

	# Shield Diamond
	_draw_shield_diamond(ctrl, Vector2(x + w / 2.0, y + 38.0))
	y += 86

	# Energy Pips
	_draw_energy_pips(ctrl, Vector2(x, y))
	y += 62

	# Flight Assist
	if ship:
		if ship.flight_assist:
			ctrl.draw_circle(Vector2(x + 4, y - 3), 3.5, UITheme.ACCENT)
			ctrl.draw_string(font, Vector2(x + 13, y), "AV ACTIF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.ACCENT)
		else:
			var flash: float = abs(sin(warning_flash)) * 0.5 + 0.5
			var fc := UITheme.DANGER * Color(1, 1, 1, flash)
			ctrl.draw_circle(Vector2(x + 4, y - 3), 3.5, fc)
			ctrl.draw_string(font, Vector2(x + 13, y), "AV DÉSACTIVÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)


# =============================================================================
# SHIELD DIAMOND
# =============================================================================
func _draw_shield_diamond(ctrl: Control, center: Vector2) -> void:
	if health_system == null:
		return
	var sz := 32.0

	var glow_a := sin(pulse_t * 1.2) * 0.08 + 0.12
	ctrl.draw_arc(center, sz + 6, 0, TAU, 32, UITheme.SHIELD * Color(1, 1, 1, glow_a), 1.5, true)
	var scan_a := fmod(pulse_t * 1.5, TAU)
	ctrl.draw_arc(center, sz + 6, scan_a, scan_a + 0.7, 10, UITheme.PRIMARY_DIM, 1.5, true)

	var pts := [
		center + Vector2(0, -sz), center + Vector2(sz, 0),
		center + Vector2(0, sz), center + Vector2(-sz, 0),
	]
	var facings := [
		HealthSystem.ShieldFacing.FRONT, HealthSystem.ShieldFacing.RIGHT,
		HealthSystem.ShieldFacing.REAR, HealthSystem.ShieldFacing.LEFT,
	]
	for i in 4:
		var ratio := health_system.get_shield_ratio(facings[i])
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % 4]
		ctrl.draw_line(p1, p2, UITheme.PRIMARY_FAINT, 3.0)
		if ratio > 0.01:
			ctrl.draw_line(p1, p1.lerp(p2, ratio), UITheme.SHIELD if ratio > 0.3 else UITheme.WARNING, 3.0)

	var ts := 9.0
	ctrl.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -ts), center + Vector2(ts * 0.6, ts * 0.5), center + Vector2(-ts * 0.6, ts * 0.5),
	]), UITheme.PRIMARY_DIM)

	var font := ThemeDB.fallback_font
	ctrl.draw_string(font, center + Vector2(-6, -sz - 6), "AV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(sz + 5, 4), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-6, sz + 14), "AR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-sz - 14, 4), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)


# =============================================================================
# ENERGY PIPS
# =============================================================================
func _draw_energy_pips(ctrl: Control, pos: Vector2) -> void:
	if energy_system == null:
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
		{name = "ARM", value = energy_system.pip_weapons, color = UITheme.DANGER},
		{name = "BCL", value = energy_system.pip_shields, color = UITheme.SHIELD},
		{name = "MOT", value = energy_system.pip_engines, color = UITheme.ACCENT},
	]
	for i in pips.size():
		var py := pos.y + i * spacing
		ctrl.draw_string(font, Vector2(pos.x, py + bar_h - 1), pips[i].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_DIM)
		var val: float = clamp(pips[i].value, 0.0, 1.0)
		for s in num_seg:
			var sx := bar_x + s * (seg_w + seg_gap)
			ctrl.draw_rect(Rect2(sx, py, seg_w, bar_h), UITheme.BG_DARK)
			var seg_start := float(s) / float(num_seg)
			var seg_end := float(s + 1) / float(num_seg)
			if val >= seg_end - 0.01:
				ctrl.draw_rect(Rect2(sx, py, seg_w, bar_h), pips[i].color)
			elif val > seg_start:
				ctrl.draw_rect(Rect2(sx, py, seg_w * (val - seg_start) * float(num_seg), bar_h), pips[i].color)
		var pct := "%d%%" % int(val * 100)
		ctrl.draw_string(font, Vector2(bar_x + total_w + 6, py + bar_h - 1), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)


# =============================================================================
# RIGHT PANEL
# =============================================================================
func _draw_right_panel(ctrl: Control) -> void:
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y)
	var font := ThemeDB.fallback_font
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var y := 22.0

	y = HudDrawHelpers.draw_section_header(ctrl, font, x, y, w, "NAVIGATION")
	y += 2

	ctrl.draw_string(font, Vector2(x, y), "POS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_DIM)
	y += 14
	var pos_str := FloatingOrigin.get_universe_pos_string() if FloatingOrigin else "0, 0, 0"
	ctrl.draw_string(font, Vector2(x, y), pos_str, HORIZONTAL_ALIGNMENT_LEFT, int(w), 11, UITheme.TEXT)
	y += 22

	if ship:
		var fwd := -ship.global_transform.basis.z
		var heading: float = rad_to_deg(atan2(fwd.x, -fwd.z))
		if heading < 0: heading += 360.0
		ctrl.draw_string(font, Vector2(x, y), "CAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
		var hv := "%06.2f\u00B0" % heading
		var hvw := font.get_string_size(hv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ctrl.draw_string(font, Vector2(x + w - hvw, y), hv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.PRIMARY)
		y += 22

		var pitch: float = rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))
		ctrl.draw_string(font, Vector2(x, y), "INCL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
		var pv := "%+.1f\u00B0" % pitch
		var pvw := font.get_string_size(pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ctrl.draw_string(font, Vector2(x + w - pvw, y), pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.PRIMARY)
		y += 22

	ctrl.draw_string(font, Vector2(x, y), "SECTEUR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
	var sv := "ALPHA-0"
	var svw := font.get_string_size(sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ctrl.draw_string(font, Vector2(x + w - svw, y), sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT)


# =============================================================================
# ECONOMY PANEL
# =============================================================================
func _draw_economy_panel(ctrl: Control) -> void:
	if player_economy == null:
		return
	var font := ThemeDB.fallback_font
	var w := ctrl.size.x

	# Collect resources with qty > 0
	var active_resources: Array[Dictionary] = []
	for res_id: StringName in PlayerEconomy.RESOURCE_DEFS:
		var qty: int = player_economy.get_resource(res_id)
		if qty > 0:
			var res_def: Dictionary = PlayerEconomy.RESOURCE_DEFS[res_id]
			active_resources.append({
				"name": res_def["name"],
				"color": res_def["color"],
				"qty": qty,
			})

	# Calculate panel height dynamically
	var row_h := 18.0
	var res_rows: int = ceili(active_resources.size() / 2.0)
	var panel_h: float = 16.0 + 28.0 + 8.0 + res_rows * row_h + 10.0  # top + credits + sep + resources + bottom
	ctrl.custom_minimum_size.y = panel_h
	ctrl.size.y = panel_h

	# --- Panel background ---
	var bg := Rect2(Vector2.ZERO, Vector2(w, panel_h))
	ctrl.draw_rect(bg, Color(0.0, 0.02, 0.05, 0.6))
	# Top + left accent lines
	ctrl.draw_line(Vector2(0, 0), Vector2(w, 0), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 10), UITheme.PRIMARY, 1.5)
	# Bottom fade line
	ctrl.draw_line(Vector2(4, panel_h - 1), Vector2(w - 4, panel_h - 1), UITheme.PRIMARY_FAINT, 1.0)

	var x := 10.0
	var y := 16.0

	# --- Credits (prominent, golden) ---
	var cr_col := PlayerEconomy.CREDITS_COLOR
	# Diamond icon
	HudDrawHelpers.draw_diamond(ctrl, Vector2(x + 5, y - 3), 5.0, cr_col)
	# Amount
	var cr_amount := PlayerEconomy.format_credits(player_economy.credits)
	ctrl.draw_string(font, Vector2(x + 16, y), cr_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, cr_col)
	# "CR" label dimmer, to the right
	var amt_w := font.get_string_size(cr_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	ctrl.draw_string(font, Vector2(x + 18 + amt_w, y), "CR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(cr_col.r, cr_col.g, cr_col.b, 0.5))

	y += 14.0

	# --- Separator ---
	ctrl.draw_line(Vector2(x, y), Vector2(w - x, y), UITheme.PRIMARY_FAINT, 1.0)
	y += 10.0

	# --- Resources (2-column grid, only qty > 0) ---
	if active_resources.is_empty():
		ctrl.draw_string(font, Vector2(x + 2, y + 10), "AUCUNE RESSOURCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
	else:
		var col_w: float = (w - x * 2) / 2.0
		for i in active_resources.size():
			var col: int = i % 2
			var row: int = int(i * 0.5)
			var rx: float = x + col * col_w
			var ry: float = y + row * row_h

			var res: Dictionary = active_resources[i]
			var rc: Color = res["color"]

			# Colored square icon
			ctrl.draw_rect(Rect2(rx, ry, 8, 8), rc)
			ctrl.draw_rect(Rect2(rx, ry, 8, 8), Color(rc.r, rc.g, rc.b, 0.35), false, 1.0)

			# Quantity (bright)
			var qty_str := str(res["qty"])
			ctrl.draw_string(font, Vector2(rx + 13, ry + 8), qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(rc.r, rc.g, rc.b, 0.95))

			# Name (dimmer, after quantity)
			var qty_w := font.get_string_size(qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			ctrl.draw_string(font, Vector2(rx + 15 + qty_w, ry + 8), res["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(rc.r, rc.g, rc.b, 0.45))

	# Scanline
	var sy: float = fmod(scan_line_y, panel_h)
	ctrl.draw_line(Vector2(0, sy), Vector2(w, sy), UITheme.SCANLINE, 1.0)
