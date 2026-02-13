class_name HudPrompts
extends Control

# =============================================================================
# HUD Action Prompts — Dock [F], Loot [X], Gate [J], Wormhole [W]
# =============================================================================

var docking_system: DockingSystem = null
var loot_pickup: LootPickupSystem = null
var system_transition: SystemTransition = null
var asteroid_scanner: AsteroidScanner = null
var pulse_t: float = 0.0
var can_build: bool = false
var build_target_name: String = ""

var _dock_prompt: Control = null
var _loot_prompt: Control = null
var _gate_prompt: Control = null
var _wormhole_prompt: Control = null
var _build_prompt: Control = null
var _scan_prompt: Control = null

const NAV_COL_GATE: Color = Color(0.15, 0.6, 1.0, 0.85)
const SCAN_COL: Color = Color(0.0, 0.85, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dock_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -100, 55, 100, 90)
	_dock_prompt.draw.connect(_draw_dock_prompt.bind(_dock_prompt))
	_dock_prompt.visible = false
	add_child(_dock_prompt)

	_loot_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -100, 95, 100, 130)
	_loot_prompt.draw.connect(_draw_loot_prompt.bind(_loot_prompt))
	_loot_prompt.visible = false
	add_child(_loot_prompt)

	_gate_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -120, 135, 120, 170)
	_gate_prompt.draw.connect(_draw_gate_prompt.bind(_gate_prompt))
	_gate_prompt.visible = false
	add_child(_gate_prompt)

	_wormhole_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -130, 175, 130, 210)
	_wormhole_prompt.draw.connect(_draw_wormhole_prompt.bind(_wormhole_prompt))
	_wormhole_prompt.visible = false
	add_child(_wormhole_prompt)

	_build_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -130, 215, 130, 250)
	_build_prompt.draw.connect(_draw_build_prompt.bind(_build_prompt))
	_build_prompt.visible = false
	add_child(_build_prompt)

	_scan_prompt = HudDrawHelpers.make_ctrl(0.5, 0.5, 0.5, 0.5, -110, 255, 110, 290)
	_scan_prompt.draw.connect(_draw_scan_prompt.bind(_scan_prompt))
	_scan_prompt.visible = false
	add_child(_scan_prompt)


func update_visibility() -> void:
	if _dock_prompt:
		var show_dock: bool = docking_system != null and docking_system.can_dock and not docking_system.is_docked
		_dock_prompt.visible = show_dock
		if show_dock:
			_dock_prompt.queue_redraw()

	if _loot_prompt:
		var show_loot: bool = loot_pickup != null and loot_pickup.can_pickup
		_loot_prompt.visible = show_loot
		if show_loot:
			_loot_prompt.queue_redraw()

	if _gate_prompt:
		var show_gate: bool = system_transition != null and system_transition.can_gate_jump()
		_gate_prompt.visible = show_gate
		if show_gate:
			_gate_prompt.queue_redraw()

	if _wormhole_prompt:
		var show_wh: bool = system_transition != null and system_transition.can_wormhole_jump()
		_wormhole_prompt.visible = show_wh
		if show_wh:
			_wormhole_prompt.queue_redraw()

	if _build_prompt:
		_build_prompt.visible = can_build
		if can_build:
			_build_prompt.queue_redraw()

	if _scan_prompt:
		var show_scan: bool = asteroid_scanner != null and asteroid_scanner.can_scan() and _is_in_belt()
		_scan_prompt.visible = show_scan
		if show_scan:
			_scan_prompt.queue_redraw()


# --- Dock ---
func _draw_dock_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.0, 0.02, 0.06, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.3 * pulse), false, 1.0)

	if docking_system:
		ctrl.draw_string(font, Vector2(0, 13), docking_system.nearest_station_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM * Color(1, 1, 1, pulse))

	var dock_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "DOCKER  [F]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, dock_col)

	var tw: float = font.get_string_size("DOCKER  [F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 24.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, dock_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, dock_col)


# --- Loot ---
func _draw_loot_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var loot_col := Color(1.0, 0.7, 0.2)
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.06, 0.04, 0.0, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(loot_col.r, loot_col.g, loot_col.b, 0.3 * pulse), false, 1.0)

	if loot_pickup and loot_pickup.nearest_crate:
		var summary: String = loot_pickup.nearest_crate.get_contents_summary()
		ctrl.draw_string(font, Vector2(0, 13), summary.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM * Color(1, 1, 1, pulse))

	var text_col := Color(loot_col.r, loot_col.g, loot_col.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "SOUTE  [X]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, text_col)

	var tw: float = font.get_string_size("SOUTE  [X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 24.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


# --- Gate ---
func _draw_gate_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var gate_col := NAV_COL_GATE
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.0, 0.02, 0.08, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(gate_col.r, gate_col.g, gate_col.b, 0.3 * pulse), false, 1.0)

	if system_transition:
		var target_name: String = system_transition.get_gate_target_name().to_upper()
		ctrl.draw_string(font, Vector2(0, 13), target_name,
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM * Color(1, 1, 1, pulse))

	var text_col := Color(gate_col.r, gate_col.g, gate_col.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "SAUT  [J]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, text_col)

	var tw: float = font.get_string_size("SAUT  [J]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 24.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


# --- Wormhole ---
func _draw_wormhole_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var wh_col := Color(0.7, 0.2, 1.0)
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.06, 0.0, 0.08, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(wh_col.r, wh_col.g, wh_col.b, 0.3 * pulse), false, 1.0)

	if system_transition:
		var target_name: String = system_transition.get_wormhole_target_name().to_upper()
		ctrl.draw_string(font, Vector2(0, 13), target_name,
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM * Color(1, 1, 1, pulse))

	var text_col := Color(wh_col.r, wh_col.g, wh_col.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "WORMHOLE  [W]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, text_col)

	var tw: float = font.get_string_size("WORMHOLE  [W]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 24.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


# --- Build ---
func _draw_build_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var build_col := Color(1.0, 0.6, 0.1)
	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.06, 0.03, 0.0, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(build_col.r, build_col.g, build_col.b, 0.3 * pulse), false, 1.0)

	if build_target_name != "":
		ctrl.draw_string(font, Vector2(0, 13), build_target_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, UITheme.TEXT_DIM * Color(1, 1, 1, pulse))

	var text_col := Color(build_col.r, build_col.g, build_col.b, pulse)
	ctrl.draw_string(font, Vector2(0, 28), "CONSTRUIRE  [B]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, text_col)

	var tw: float = font.get_string_size("CONSTRUIRE  [B]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 24.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


# --- Scan ---
func _draw_scan_prompt(ctrl: Control) -> void:
	var s := ctrl.size
	var font := UITheme.get_font_medium()
	var cx: float = s.x * 0.5
	var pulse: float = 0.7 + sin(pulse_t * 3.0) * 0.3

	var bg_rect := Rect2(Vector2(10, 0), Vector2(s.x - 20, s.y))
	ctrl.draw_rect(bg_rect, Color(0.0, 0.04, 0.06, 0.6 * pulse))
	ctrl.draw_rect(bg_rect, Color(SCAN_COL.r, SCAN_COL.g, SCAN_COL.b, 0.3 * pulse), false, 1.0)

	var text_col := Color(SCAN_COL.r, SCAN_COL.g, SCAN_COL.b, pulse)
	ctrl.draw_string(font, Vector2(0, 22), "SCAN  [H]",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, text_col)

	var tw: float = font.get_string_size("SCAN  [H]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dy: float = 18.0
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx - tw * 0.5 - 10, dy), 3.0, text_col)
	HudDrawHelpers.draw_diamond(ctrl, Vector2(cx + tw * 0.5 + 10, dy), 3.0, text_col)


func _is_in_belt() -> bool:
	var ship := GameManager.player_ship
	if ship == null:
		return false
	var asteroid_mgr := GameManager.get_node_or_null("AsteroidFieldManager") as AsteroidFieldManager
	if asteroid_mgr == null:
		return false
	var uni_x: float = ship.global_position.x + FloatingOrigin.origin_offset_x
	var uni_z: float = ship.global_position.z + FloatingOrigin.origin_offset_z
	return asteroid_mgr.get_belt_at_position(uni_x, uni_z) != ""
