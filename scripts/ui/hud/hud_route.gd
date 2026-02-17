class_name HudRoute
extends Control

# =============================================================================
# HUD Route Indicator — Shows active route progress (top-center)
# Destination name, current/total jumps, progress dots
# =============================================================================

var pulse_t: float = 0.0
var _panel: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top-center panel
	_panel = HudDrawHelpers.make_ctrl(0.5, 0.0, 0.5, 0.0, -140, 84, 140, 126)
	_panel.draw.connect(_draw_route_panel.bind(_panel))
	add_child(_panel)


func update_visibility() -> void:
	var rm = GameManager._route_manager if GameManager else null
	var should_show: bool = rm != null and rm.is_route_active()
	_panel.visible = should_show
	if should_show:
		_panel.queue_redraw()


func _draw_route_panel(ctrl: Control) -> void:
	var rm = GameManager._route_manager if GameManager else null
	if rm == null or not rm.is_route_active():
		return

	var s =ctrl.size
	var font =UITheme.get_font_medium()
	var pulse: float = sin(pulse_t * 2.0) * 0.15 + 0.85

	# Background
	var bg =Color(0.0, 0.02, 0.06, 0.75)
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), bg)

	# Border
	var border =Color(0.0, 0.7, 1.0, 0.3 * pulse)
	ctrl.draw_rect(Rect2(Vector2.ZERO, s), border, false, 1.0)

	# Corner accents
	var cl: float = 6.0
	var cc =Color(0.0, 0.9, 1.0, 0.6)
	ctrl.draw_line(Vector2(0, 0), Vector2(cl, 0), cc, 1.5)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, cl), cc, 1.5)
	ctrl.draw_line(Vector2(s.x, 0), Vector2(s.x - cl, 0), cc, 1.5)
	ctrl.draw_line(Vector2(s.x, 0), Vector2(s.x, cl), cc, 1.5)

	# Destination name
	var dest_name: String = rm.target_system_name
	if dest_name.length() > 20:
		dest_name = dest_name.substr(0, 18) + ".."
	ctrl.draw_string(font, Vector2(8, 15), "ROUTE: " + dest_name, HORIZONTAL_ALIGNMENT_LEFT, s.x - 16, 13, Color(0.0, 0.9, 1.0, pulse))

	# Jump progress
	var current_jump: int = rm.get_current_jump()
	var total_jumps: int = rm.get_jumps_total()
	var jump_text ="SAUT %d/%d" % [current_jump + 1, total_jumps]
	ctrl.draw_string(font, Vector2(8, 30), jump_text, HORIZONTAL_ALIGNMENT_LEFT, 100, 13, Color(0.6, 0.8, 0.9, 0.8))

	# Progress dots
	var dot_x: float = 110.0
	var dot_y: float = 26.0
	var dot_spacing: float = 10.0
	var max_dots: int = mini(total_jumps, 15)
	for i in max_dots:
		var dot_col: Color
		if i < current_jump:
			dot_col = Color(0.0, 0.9, 1.0, 0.8)  # Completed
		elif i == current_jump:
			dot_col = Color(1.0, 0.8, 0.0, pulse)  # Current
		else:
			dot_col = Color(0.3, 0.5, 0.6, 0.4)  # Remaining
		ctrl.draw_circle(Vector2(dot_x + i * dot_spacing, dot_y), 2.5, dot_col)

	# State indicator
	var state_text: String = ""
	match rm.state:
		RouteManager.State.FLYING_TO_GATE: state_text = "EN ROUTE"
		RouteManager.State.WAITING_AT_GATE: state_text = "SAUT..."
		RouteManager.State.JUMPING: state_text = "SAUT EN COURS"
	if state_text != "":
		ctrl.draw_string(font, Vector2(s.x - 8, 30), state_text, HORIZONTAL_ALIGNMENT_RIGHT, 100, 13, Color(1.0, 0.8, 0.0, pulse * 0.8))
