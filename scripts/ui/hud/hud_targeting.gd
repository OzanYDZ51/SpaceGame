class_name HudTargeting
extends Control

# =============================================================================
# HUD Targeting — Target bracket, lead indicator, info panel with shields
# =============================================================================

var targeting_system: TargetingSystem = null
var ship: ShipController = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _target_shield_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _target_hull_flash: float = 0.0
var _connected_target_health: HealthSystem = null
var _prev_target_shields: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_target_hull: float = 0.0
var _last_tracked_target: Node3D = null

var _connected_struct_health: StructureHealth = null

var _target_overlay: Control = null
var _target_panel: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_target_overlay = HudDrawHelpers.make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_target_overlay.draw.connect(_draw_target_overlay.bind(_target_overlay))
	add_child(_target_overlay)

	_target_panel = HudDrawHelpers.make_ctrl(1.0, 1.0, 1.0, 1.0, -276, -296, -16, -16)
	_target_panel.draw.connect(_draw_target_info_panel.bind(_target_panel))
	_target_panel.visible = false
	add_child(_target_panel)


func update(delta: float, is_cockpit: bool) -> void:
	var current_target: Node3D = null
	if targeting_system and targeting_system.current_target and is_instance_valid(targeting_system.current_target):
		current_target = targeting_system.current_target
	_track_target(current_target)

	for i in 4:
		_target_shield_flash[i] = maxf(_target_shield_flash[i] - delta * 3.0, 0.0)
	_target_hull_flash = maxf(_target_hull_flash - delta * 3.0, 0.0)

	_target_overlay.queue_redraw()

	if _target_panel:
		_target_panel.visible = current_target != null and not is_cockpit
		if _target_panel.visible:
			_target_panel.queue_redraw()


# =============================================================================
# TARGET OVERLAY
# =============================================================================
func _draw_target_overlay(ctrl: Control) -> void:
	if targeting_system == null:
		return
	if targeting_system.current_target == null or not is_instance_valid(targeting_system.current_target):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target := targeting_system.current_target
	var cf: Vector3 = -cam.global_transform.basis.z

	var target_pos: Vector3 = TargetingSystem.get_ship_center(target)

	var to_t: Vector3 = (target_pos - cam.global_position).normalized()
	if cf.dot(to_t) > 0.1:
		_draw_target_bracket(ctrl, cam.unproject_position(target_pos))

	if ship and ship.current_speed > 0.1:
		var lp: Vector3 = targeting_system.get_lead_indicator_position()
		var to_l: Vector3 = (lp - cam.global_position).normalized()
		if cf.dot(to_l) > 0.1:
			_draw_lead_indicator(ctrl, cam.unproject_position(lp))


func _draw_target_bracket(ctrl: Control, sp: Vector2) -> void:
	var bk := 22.0
	var bl := 10.0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var corner: Vector2 = sp + s * bk
		ctrl.draw_line(corner, corner + Vector2(-s.x * bl, 0), UITheme.TARGET, 1.5)
		ctrl.draw_line(corner, corner + Vector2(0, -s.y * bl), UITheme.TARGET, 1.5)


func _draw_lead_indicator(ctrl: Control, sp: Vector2) -> void:
	ctrl.draw_arc(sp, 8.0, 0, TAU, 16, UITheme.LEAD, 1.5, true)
	ctrl.draw_line(sp + Vector2(-4, 0), sp + Vector2(4, 0), UITheme.LEAD, 1.0)
	ctrl.draw_line(sp + Vector2(0, -4), sp + Vector2(0, 4), UITheme.LEAD, 1.0)


# =============================================================================
# TARGET INFO PANEL
# =============================================================================
func _draw_target_info_panel(ctrl: Control) -> void:
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y)
	var font := UITheme.get_font_medium()
	var x := 12.0
	var w := ctrl.size.x - 24.0
	var cx := ctrl.size.x / 2.0
	var y := 22.0

	if targeting_system == null or targeting_system.current_target == null:
		return
	if not is_instance_valid(targeting_system.current_target):
		return

	var target := targeting_system.current_target
	var t_health := target.get_node_or_null("HealthSystem") as HealthSystem
	var t_struct := target.get_node_or_null("StructureHealth") as StructureHealth

	# Determine hostility
	var is_hostile := false
	if target is ShipController:
		var sc := target as ShipController
		is_hostile = sc.faction != &"player_fleet" and sc.faction != &"neutral" and sc.faction != &"friendly"

	# Hostile: red top accent line
	if is_hostile:
		var lock_pulse := sin(pulse_t * 3.0) * 0.2 + 0.5
		ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, lock_pulse), 2.0)

	# Header
	if is_hostile:
		var hdr_pulse := sin(pulse_t * 3.0) * 0.3 + 0.7
		var hdr_col := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, hdr_pulse)
		ctrl.draw_rect(Rect2(x, y - 11, 3, 14), hdr_col)
		ctrl.draw_string(font, Vector2(x + 9, y), "CIBLE VERROUILLÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hdr_col)
		var tw := font.get_string_size("CIBLE VERROUILLÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lx := x + 9 + tw + 8
		if lx < x + w:
			ctrl.draw_line(Vector2(lx, y - 4), Vector2(x + w, y - 4), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.3), 1.0)
		y += 18
	else:
		y = HudDrawHelpers.draw_section_header(ctrl, font, x, y, w, "CIBLE")
	y += 4

	# Target name (prominent)
	var display_name: String = target.name
	if "station_name" in target and target.station_name != "":
		display_name = target.station_name
	var name_col := UITheme.DANGER if is_hostile else UITheme.TARGET
	ctrl.draw_string(font, Vector2(x, y), display_name, HORIZONTAL_ALIGNMENT_LEFT, int(w), 16, name_col)
	y += 20

	# Class / type + distance
	var class_text := ""
	if target is ShipController and (target as ShipController).ship_data:
		class_text = str((target as ShipController).ship_data.ship_class)
	elif t_struct:
		class_text = "STATION"
	ctrl.draw_string(font, Vector2(x, y), class_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)

	var dist := targeting_system.get_target_distance()
	if dist >= 0.0:
		var dt: String = HudDrawHelpers.format_nav_distance(dist)
		var dtw := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14).x
		ctrl.draw_string(font, Vector2(x + w - dtw, y), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)
	y += 22

	# Separator
	ctrl.draw_line(Vector2(x, y - 8), Vector2(x + w, y - 8), UITheme.PRIMARY_FAINT, 1.0)

	if t_struct:
		_draw_structure_health(ctrl, font, x, y, w, t_struct)
	else:
		var diagram_center := Vector2(cx, y + 50)
		_draw_target_ship_shields(ctrl, diagram_center, t_health, is_hostile)
		y += 110

		if t_health:
			var f_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.FRONT)
			var r_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.REAR)
			var l_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.LEFT)
			var d_r := t_health.get_shield_ratio(HealthSystem.ShieldFacing.RIGHT)
			var col_x2 := cx + 10
			ctrl.draw_string(font, Vector2(x, y), "AV: %d%%" % int(f_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(f_r))
			ctrl.draw_string(font, Vector2(col_x2, y), "AR: %d%%" % int(r_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(r_r))
			y += 14
			ctrl.draw_string(font, Vector2(x, y), "G: %d%%" % int(l_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(l_r))
			ctrl.draw_string(font, Vector2(col_x2, y), "D: %d%%" % int(d_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(d_r))
			y += 20
		else:
			y += 34

		# Separator before hull
		ctrl.draw_line(Vector2(x, y - 6), Vector2(x + w, y - 6), UITheme.PRIMARY_FAINT, 1.0)

		var hull_r := t_health.get_hull_ratio() if t_health else 0.0
		var hull_c := UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
		ctrl.draw_string(font, Vector2(x, y), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
		var hp := "%d%%" % int(hull_r * 100)
		ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hull_c)
		y += 8
		HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)

		if _target_hull_flash > 0.01:
			var bar_fw: float = w * clampf(hull_r, 0.0, 1.0)
			if bar_fw > 0:
				ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_hull_flash * 0.5))


func _draw_target_ship_shields(ctrl: Control, center: Vector2, health: HealthSystem, is_hostile: bool = false) -> void:
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
		ctrl.draw_arc(center, radius, a0, a1, segments, UITheme.PRIMARY_FAINT, bg_width, true)
		if health:
			var ratio := health.get_shield_ratio(facings[i])
			if ratio > 0.01:
				ctrl.draw_arc(center, radius, a0, a0 + (a1 - a0) * ratio, segments, _shield_ratio_color(ratio), arc_width, true)
			if _target_shield_flash[i] > 0.01:
				ctrl.draw_arc(center, radius, a0, a1, segments, Color(1, 1, 1, _target_shield_flash[i] * 0.8), arc_width + 2.0, true)

	var tri_h := 14.0
	var tri_w := 9.0
	var tri := PackedVector2Array([
		center + Vector2(0, -tri_h), center + Vector2(tri_w, tri_h * 0.5), center + Vector2(-tri_w, tri_h * 0.5),
	])
	var tri_fill := Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5) if is_hostile else UITheme.PRIMARY_DIM
	var tri_outline := UITheme.DANGER if is_hostile else UITheme.PRIMARY
	ctrl.draw_colored_polygon(tri, tri_fill)
	ctrl.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), tri_outline, 1.0)

	var font := UITheme.get_font_medium()
	ctrl.draw_string(font, center + Vector2(-5, -radius - 8), "AV", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-5, radius + 16), "AR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(-radius - 14, 4), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	ctrl.draw_string(font, center + Vector2(radius + 6, 4), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)


func _draw_structure_health(ctrl: Control, font: Font, x: float, y: float, w: float, sh: StructureHealth) -> void:
	# Shield bar
	var shd_r := sh.get_shield_ratio()
	var shd_c := _shield_ratio_color(shd_r)
	ctrl.draw_string(font, Vector2(x, y), "BOUCLIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var sp := "%d%%" % int(shd_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, shd_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, shd_r, shd_c)

	if _target_shield_flash[0] > 0.01:
		var bar_fw: float = w * clampf(shd_r, 0.0, 1.0)
		if bar_fw > 0:
			ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_shield_flash[0] * 0.5))

	y += 20

	# Hull bar
	var hull_r := sh.get_hull_ratio()
	var hull_c := UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
	ctrl.draw_string(font, Vector2(x, y), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var hp := "%d%%" % int(hull_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hull_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)

	if _target_hull_flash > 0.01:
		var bar_fw: float = w * clampf(hull_r, 0.0, 1.0)
		if bar_fw > 0:
			ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_hull_flash * 0.5))


func _shield_ratio_color(ratio: float) -> Color:
	if ratio > 0.5: return UITheme.SHIELD
	elif ratio > 0.25: return UITheme.WARNING
	elif ratio > 0.0: return UITheme.DANGER
	return UITheme.PRIMARY_FAINT


# =============================================================================
# TARGET TRACKING
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
	if health:
		_connected_target_health = health
		health.shield_changed.connect(_on_target_shield_hit)
		health.hull_changed.connect(_on_target_hull_hit)
		for i in 4:
			_prev_target_shields[i] = health.shield_current[i]
		_prev_target_hull = health.hull_current
		return
	# Structure health (stations)
	var struct_health := target.get_node_or_null("StructureHealth") as StructureHealth
	if struct_health:
		_connected_struct_health = struct_health
		struct_health.shield_changed.connect(_on_struct_shield_hit)
		struct_health.hull_changed.connect(_on_target_hull_hit)
		_prev_target_shields[0] = struct_health.shield_current
		_prev_target_hull = struct_health.hull_current


func _disconnect_target_signals() -> void:
	if _connected_target_health and is_instance_valid(_connected_target_health):
		if _connected_target_health.shield_changed.is_connected(_on_target_shield_hit):
			_connected_target_health.shield_changed.disconnect(_on_target_shield_hit)
		if _connected_target_health.hull_changed.is_connected(_on_target_hull_hit):
			_connected_target_health.hull_changed.disconnect(_on_target_hull_hit)
	_connected_target_health = null
	if _connected_struct_health and is_instance_valid(_connected_struct_health):
		if _connected_struct_health.shield_changed.is_connected(_on_struct_shield_hit):
			_connected_struct_health.shield_changed.disconnect(_on_struct_shield_hit)
		if _connected_struct_health.hull_changed.is_connected(_on_target_hull_hit):
			_connected_struct_health.hull_changed.disconnect(_on_target_hull_hit)
	_connected_struct_health = null


func _on_target_shield_hit(facing: int, current: float, _max_val: float) -> void:
	if facing >= 0 and facing < 4 and current < _prev_target_shields[facing]:
		_target_shield_flash[facing] = 1.0
	if facing >= 0 and facing < 4:
		_prev_target_shields[facing] = current


func _on_struct_shield_hit(current: float, _max_val: float) -> void:
	if current < _prev_target_shields[0]:
		_target_shield_flash[0] = 1.0
	_prev_target_shields[0] = current


func _on_target_hull_hit(current: float, _max_val: float) -> void:
	if current < _prev_target_hull:
		_target_hull_flash = 1.0
	_prev_target_hull = current
