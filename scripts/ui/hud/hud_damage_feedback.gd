class_name HudDamageFeedback
extends Control

# =============================================================================
# HUD Hit Markers — Visual feedback for weapon impacts
# =============================================================================

# Each entry: {"type": int, "t": float (1→0), "intensity": float, "shield_ratio": float}
var _hit_markers: Array[Dictionary] = []

const HIT_MARKER_DURATION_SHIELD =0.28
const HIT_MARKER_DURATION_HULL =0.35
const HIT_MARKER_DURATION_KILL =0.7
const HIT_MARKER_DURATION_BREAK =0.35
const HIT_MARKER_MAX =6

var COL_HIT_SHIELD: Color:
	get: return Color(0.3, 0.7, 1.0, 1.0)
var COL_HIT_SHIELD_LOW: Color:
	get: return Color(1.0, 0.5, 0.15, 1.0)
var COL_HIT_HULL: Color:
	get: return Color(1.0, 0.15, 0.1, 1.0)
var COL_HIT_KILL: Color:
	get: return Color(1.0, 0.85, 0.2, 1.0)
var COL_HIT_BREAK: Color:
	get: return Color(1.0, 0.4, 0.05, 1.0)

var _weapon_manager = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_weapon_manager(w) -> void:
	if _weapon_manager and _weapon_manager.hit_landed.is_connected(_on_hit_landed):
		_weapon_manager.hit_landed.disconnect(_on_hit_landed)
	_weapon_manager = w
	if _weapon_manager:
		_weapon_manager.hit_landed.connect(_on_hit_landed)


func update_markers(delta: float) -> void:
	var i =_hit_markers.size() - 1
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


func draw_hit_markers(ctrl: Control, center: Vector2) -> void:
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


func _on_hit_landed(hit_type: int, damage_amount: float, shield_ratio: float) -> void:
	if _hit_markers.size() >= HIT_MARKER_MAX:
		_hit_markers.pop_front()
	var intensity =clampf(damage_amount / 30.0, 0.6, 2.5)
	_hit_markers.append({
		"type": hit_type,
		"t": 1.0,
		"intensity": intensity,
		"shield_ratio": shield_ratio,
	})


func _draw_shield_tick(ctrl: Control, c: Vector2, t: float, intensity: float, shield_ratio: float) -> void:
	var col =COL_HIT_SHIELD.lerp(COL_HIT_SHIELD_LOW, clampf(1.0 - shield_ratio, 0.0, 1.0))
	var flash =clampf((t - 0.7) / 0.3, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.6)
	var alpha =t * t
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap =8.0 + (1.0 - t) * 7.0 * intensity
	var tick_len =7.0 + intensity * 3.0
	var width =2.2 * t + 0.5

	var diag =0.7071
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir =Vector2(sign_x * diag, sign_y * diag)
			var p1 =c + dir * base_gap
			var p2 =c + dir * (base_gap + tick_len)
			ctrl.draw_line(p1, p2, col, width)

	if flash > 0.0:
		var ring_col =col * Color(1, 1, 1, flash * 0.3)
		ctrl.draw_arc(c, base_gap - 2.0, 0, TAU, 16, ring_col, 1.0)


func _draw_hull_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	var col =COL_HIT_HULL
	var flash =clampf((t - 0.65) / 0.35, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.5)
	var alpha =t * t
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap =6.0 + (1.0 - t) * 10.0 * intensity
	var tick_len =9.0 + intensity * 4.0
	var width =2.5 * t + 0.8

	var diag =0.7071
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir =Vector2(sign_x * diag, sign_y * diag)
			var p1 =c + dir * base_gap
			var p2 =c + dir * (base_gap + tick_len)
			ctrl.draw_line(p1, p2, col, width)
			var perp =Vector2(-dir.y, dir.x) * 1.0
			ctrl.draw_line(p1 + perp, p2 + perp, col * Color(1, 1, 1, 0.4), width * 0.5)

	if flash > 0.2:
		var dot_col =COL_HIT_HULL * Color(1, 1, 1, (flash - 0.2) * 0.6)
		ctrl.draw_circle(c, 2.5 * flash, dot_col)


func _draw_kill_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	var col =COL_HIT_KILL
	var flash =clampf((t - 0.6) / 0.4, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.7)
	var alpha: float
	if t > 0.4:
		alpha = 1.0
	else:
		alpha = t / 0.4
	col.a = alpha

	var base_gap =7.0 + (1.0 - t) * 14.0
	var tick_len =11.0 + intensity * 4.0
	var width =2.8 * minf(t * 2.0, 1.0) + 0.5

	var angles: Array[float] = [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, PI * 1.25, PI * 1.5, PI * 1.75]
	for angle in angles:
		var dir =Vector2(cos(angle), sin(angle))
		var p1 =c + dir * base_gap
		var p2 =c + dir * (base_gap + tick_len)
		ctrl.draw_line(p1, p2, col, width)

	if flash > 0.0:
		var ring_r =4.0 + (1.0 - flash) * 12.0
		var ring_col =COL_HIT_KILL * Color(1, 1, 1, flash * 0.5)
		ctrl.draw_arc(c, ring_r, 0, TAU, 24, ring_col, 1.5)

	if t > 0.7:
		var core_a =(t - 0.7) / 0.3
		ctrl.draw_circle(c, 3.5 * core_a, Color(1.0, 0.95, 0.8, core_a * 0.7))


func _draw_shield_break_tick(ctrl: Control, c: Vector2, t: float, intensity: float) -> void:
	var col =COL_HIT_BREAK
	var flash =clampf((t - 0.6) / 0.4, 0.0, 1.0)
	col = col.lerp(Color.WHITE, flash * 0.5)
	var alpha =t * t
	col.a = alpha * clampf(intensity, 0.7, 1.0)

	var base_gap =7.0 + (1.0 - t) * 12.0 * intensity
	var tick_len =8.0 + intensity * 3.0
	var width =2.0 * t + 0.6

	var diag =0.7071
	var jitter =sin(t * 30.0) * 1.5
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var dir =Vector2(sign_x * diag, sign_y * diag)
			var perp =Vector2(-dir.y, dir.x)
			var p1 =c + dir * base_gap + perp * jitter
			var p2 =c + dir * (base_gap + tick_len) - perp * jitter
			ctrl.draw_line(p1, p2, col, width)

	if flash > 0.0:
		var arc_r =base_gap - 1.0
		var arc_col =COL_HIT_BREAK * Color(1, 1, 1, flash * 0.4)
		for i in 4:
			var start_angle =float(i) * PI * 0.5 + 0.3
			ctrl.draw_arc(c, arc_r, start_angle, start_angle + 0.5, 6, arc_col, 1.2)
