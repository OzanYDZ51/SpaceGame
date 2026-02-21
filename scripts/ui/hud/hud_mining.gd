class_name HudMining
extends Control

# =============================================================================
# HUD Mining — Heat bar + extraction progress + cargo fill bar
# =============================================================================

var mining_system = null
var pulse_t: float = 0.0

var _mining_heat: Control = null
var _mining_progress: Control = null
var _cargo_full_msg: Control = null

# Cargo full flash timer
var _cargo_full_timer: float = 0.0
const CARGO_FULL_DISPLAY_TIME: float = 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mining_heat = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -100, 215, 100, 250)
	_mining_heat.draw.connect(_draw_mining_heat.bind(_mining_heat))
	_mining_heat.visible = false
	add_child(_mining_heat)

	_mining_progress = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -140, 280, 140, 315)
	_mining_progress.draw.connect(_draw_mining_progress.bind(_mining_progress))
	_mining_progress.visible = false
	add_child(_mining_progress)

	# Cargo full message — centered above heat bar
	_cargo_full_msg = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -110, 195, 110, 215)
	_cargo_full_msg.draw.connect(_draw_cargo_full_msg.bind(_cargo_full_msg))
	_cargo_full_msg.visible = false
	add_child(_cargo_full_msg)


func connect_mining_system(ms) -> void:
	if mining_system and mining_system.cargo_full.is_connected(_on_cargo_full):
		mining_system.cargo_full.disconnect(_on_cargo_full)
	mining_system = ms
	if mining_system:
		mining_system.cargo_full.connect(_on_cargo_full)


func _on_cargo_full() -> void:
	_cargo_full_timer = CARGO_FULL_DISPLAY_TIME


func update_visibility() -> void:
	var has_laser: bool = mining_system != null and mining_system.has_mining_laser()

	if _mining_heat:
		var show_heat: bool = has_laser and mining_system.heat > 0.01
		_mining_heat.visible = show_heat
		if show_heat:
			_mining_heat.queue_redraw()

	if _mining_progress:
		var show_prog: bool = mining_system != null and mining_system.is_mining
		_mining_progress.visible = show_prog
		if show_prog:
			_mining_progress.queue_redraw()

	# Cargo full message — visible while timer active
	if _cargo_full_msg:
		_cargo_full_msg.visible = _cargo_full_timer > 0.0
		if _cargo_full_msg.visible:
			_cargo_full_msg.queue_redraw()


func _process(delta: float) -> void:
	if _cargo_full_timer > 0.0:
		_cargo_full_timer -= delta
		if _cargo_full_timer <= 0.0:
			_cargo_full_timer = 0.0


func _draw_mining_heat(ctrl: Control) -> void:
	if mining_system == null:
		return
	var s = ctrl.size
	var font = UITheme.get_font_medium()
	var heat_ratio: float = mining_system.heat
	var overheated: bool = mining_system.is_overheated

	var heat_col: Color
	if heat_ratio < 0.5:
		heat_col = Color(0.2, 1.0, 0.5).lerp(Color(1.0, 0.9, 0.2), heat_ratio * 2.0)
	else:
		heat_col = Color(1.0, 0.9, 0.2).lerp(Color(1.0, 0.2, 0.1), (heat_ratio - 0.5) * 2.0)

	var pulse: float = 1.0
	if overheated:
		pulse = 0.5 + sin(pulse_t * 8.0) * 0.5

	var bg_rect = Rect2(Vector2(6, 0), Vector2(s.x - 12, s.y))
	ctrl.draw_rect(bg_rect, Color(0.02, 0.02, 0.02, 0.6))
	ctrl.draw_rect(bg_rect, Color(heat_col.r, heat_col.g, heat_col.b, 0.25 * pulse), false, 1.0)

	var label: String = Locale.t("hud.mining_overheat") if overheated else Locale.t("hud.mining_heat")
	ctrl.draw_string(font, Vector2(0, 11), label,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, Color(heat_col.r, heat_col.g, heat_col.b, 0.9 * pulse))

	var bar_x: float = 12.0
	var bar_y: float = 16.0
	var bar_w: float = s.x - 24.0
	var bar_h: float = 8.0

	ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.08, 0.08, 0.08, 0.8))
	var fill_w: float = (bar_w - 2) * heat_ratio
	var fill_col = Color(heat_col.r, heat_col.g, heat_col.b, 0.9 * pulse)
	ctrl.draw_rect(Rect2(bar_x + 1, bar_y + 1, fill_w, bar_h - 2), fill_col)
	ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(heat_col.r, heat_col.g, heat_col.b, 0.4), false, 1.0)

	var thresh_x: float = bar_x + 1 + (bar_w - 2) * MiningSystem.OVERHEAT_THRESHOLD
	ctrl.draw_line(Vector2(thresh_x, bar_y), Vector2(thresh_x, bar_y + bar_h), Color(1, 1, 1, 0.2), 1.0)

	ctrl.draw_string(font, Vector2(0, bar_y + bar_h + 10), "%d%%" % int(heat_ratio * 100.0),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM)


func _draw_mining_progress(ctrl: Control) -> void:
	if mining_system == null or mining_system.mining_target == null:
		return
	var s = ctrl.size
	var font = UITheme.get_font_medium()
	var target = mining_system.mining_target
	var pulse: float = 0.8 + sin(pulse_t * 5.0) * 0.2

	var mine_col = Color(0.2, 1.0, 0.5)

	var bg_rect = Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.0, 0.04, 0.02, 0.7))
	ctrl.draw_rect(bg_rect, Color(mine_col.r, mine_col.g, mine_col.b, 0.4 * pulse), false, 1.0)

	var res = MiningRegistry.get_resource(target.primary_resource)
	var res_name: String = res.display_name if res else "?"
	ctrl.draw_string(font, Vector2(0, 13), (Locale.t("hud.mining_extraction") % res_name).to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, Color(mine_col.r, mine_col.g, mine_col.b, pulse))

	var bar_x: float = 20.0
	var bar_y: float = 18.0
	var bar_w: float = s.x - 40.0
	var bar_h: float = 10.0
	var hp_ratio: float = target.health_current / target.health_max if target.health_max > 0 else 0.0
	hp_ratio = clampf(hp_ratio, 0.0, 1.0)

	ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.12, 0.1, 0.8))
	var fill_col = mine_col * Color(1, 1, 1, pulse)
	ctrl.draw_rect(Rect2(bar_x + 1, bar_y + 1, (bar_w - 2) * hp_ratio, bar_h - 2), fill_col)
	ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(mine_col.r, mine_col.g, mine_col.b, 0.5), false, 1.0)

	var hp_text = "%d%%" % int(hp_ratio * 100.0)
	ctrl.draw_string(font, Vector2(0, bar_y + bar_h + 2), hp_text,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM)


func _draw_cargo_full_msg(ctrl: Control) -> void:
	var s = ctrl.size
	var font = UITheme.get_font_medium()
	var pulse: float = 0.5 + sin(pulse_t * 6.0) * 0.5
	var col = Color(1.0, 0.3, 0.1, pulse)

	var bg_rect = Rect2(Vector2(4, 0), Vector2(s.x - 8, s.y))
	ctrl.draw_rect(bg_rect, Color(0.15, 0.02, 0.0, 0.7 * pulse))
	ctrl.draw_rect(bg_rect, Color(1.0, 0.3, 0.1, 0.5 * pulse), false, 1.5)

	ctrl.draw_string(font, Vector2(0, 14), Locale.t("hud.mining_cargo_full"),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, col)
