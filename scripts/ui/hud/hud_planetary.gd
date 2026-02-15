class_name HudPlanetary
extends Control

# =============================================================================
# HUD Planetary — Altimeter + planet name when near a planet surface
# =============================================================================

var planet_approach_mgr = null

var _info_ctrl: Control = null
var _last_altitude: float = INF
var _last_zone: int = PlanetApproachManager.Zone.SPACE
var _last_planet_name: String = ""

const ZONE_COLORS: Dictionary = {
	0: Color(0.4, 0.6, 0.8, 0.0),     # SPACE — invisible
	1: Color(0.4, 0.6, 0.8, 0.6),     # APPROACH — blue
	2: Color(0.9, 0.7, 0.2, 0.8),     # EXTERIOR — yellow
	3: Color(0.9, 0.45, 0.15, 0.85),  # ATMOSPHERE — orange
	4: Color(0.8, 0.2, 0.2, 0.9),     # SURFACE — red
}

const ZONE_NAMES: Dictionary = {
	0: "",
	1: "APPROCHE",
	2: "ZONE EXTERIEURE",
	3: "ATMOSPHERE",
	4: "SURFACE",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Bottom-left info display
	_info_ctrl = HudDrawHelpers.make_ctrl(0.0, 1.0, 0.0, 1.0, 20, -120, 280, -20)
	_info_ctrl.draw.connect(_draw_info.bind(_info_ctrl))
	add_child(_info_ctrl)


func _process(_delta: float) -> void:
	if planet_approach_mgr == null:
		_info_ctrl.visible = false
		return

	var zone: int = planet_approach_mgr.current_zone
	_info_ctrl.visible = zone > PlanetApproachManager.Zone.SPACE
	if _info_ctrl.visible:
		_last_altitude = planet_approach_mgr.current_altitude
		_last_zone = zone
		_last_planet_name = planet_approach_mgr.current_planet_name
		_info_ctrl.queue_redraw()


func _draw_info(ctrl: Control) -> void:
	var s: Vector2 = ctrl.size
	var zone_color: Color = ZONE_COLORS.get(_last_zone, Color.WHITE)
	var zone_name: String = ZONE_NAMES.get(_last_zone, "")

	# Background panel
	var bg_color =Color(0.02, 0.03, 0.06, 0.6)
	ctrl.draw_rect(Rect2(0, 0, s.x, s.y), bg_color)
	ctrl.draw_rect(Rect2(0, 0, s.x, s.y), zone_color * 0.5, false, 1.0)

	# Planet name
	var font =UITheme.get_font_bold()
	if _last_planet_name != "":
		ctrl.draw_string(font, Vector2(10, 22), _last_planet_name, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 14, zone_color)

	# Zone name
	var font_reg =UITheme.get_font()
	if zone_name != "":
		ctrl.draw_string(font_reg, Vector2(10, 42), zone_name, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 11, zone_color * 0.8)

	# Altitude
	var alt_text: String
	if _last_altitude > 10000.0:
		alt_text = "ALT: %.1f km" % (_last_altitude / 1000.0)
	elif _last_altitude > 100.0:
		alt_text = "ALT: %.0f m" % _last_altitude
	else:
		alt_text = "ALT: %.1f m" % _last_altitude

	ctrl.draw_string(font, Vector2(10, 68), alt_text, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 16, zone_color)

	# Gravity indicator
	if planet_approach_mgr:
		var grav_pct =planet_approach_mgr.gravity_strength * 100.0
		if grav_pct > 0.1:
			var grav_text ="GRAV: %.0f%%" % grav_pct
			ctrl.draw_string(font_reg, Vector2(10, 88), grav_text, HORIZONTAL_ALIGNMENT_LEFT, s.x - 20, 11, zone_color * 0.7)
