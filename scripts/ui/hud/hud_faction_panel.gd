class_name HudFactionPanel
extends Control

# =============================================================================
# HUD Faction Panel — Displays player faction + reputation bars.
# Bottom-left, below the economy panel. Uses _draw() pattern.
# =============================================================================

var faction_manager: FactionManager = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _panel: Control = null
var _bg_alpha: float = 0.0
var _bg_target: float = 0.0

const PANEL_X: float = 16.0
const PANEL_Y: float = 200.0  # Below economy panel
const PANEL_W: float = 214.0
const PANEL_H: float = 150.0
const BAR_W: float = 100.0

# Standing display names (French)
const STANDING_LABELS: Dictionary = {
	&"allied": "ALLIE",
	&"friendly": "AMICAL",
	&"neutral": "NEUTRE",
	&"hostile": "HOSTILE",
	&"enemy": "ENNEMI",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = HudDrawHelpers.make_ctrl(0.0, 0.0, 0.0, 0.0, PANEL_X, PANEL_Y, PANEL_X + PANEL_W, PANEL_Y + PANEL_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.mouse_entered.connect(func(): _bg_target = 1.0)
	_panel.mouse_exited.connect(func(): _bg_target = 0.0)
	_panel.draw.connect(_draw_panel.bind(_panel))
	add_child(_panel)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_panel.visible = not is_cockpit


func redraw_slow() -> void:
	_bg_alpha = move_toward(_bg_alpha, _bg_target, 0.15)
	_panel.queue_redraw()


func _draw_panel(ctrl: Control) -> void:
	if faction_manager == null:
		return

	var player_fac: StringName = faction_manager.player_faction
	if player_fac == &"":
		return

	var fac_res: FactionResource = faction_manager.get_player_faction_resource()
	if fac_res == null:
		return

	# Background
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y, maxf(0.35, _bg_alpha))

	var font: Font = UITheme.get_font_medium()
	var font_sm: Font = UITheme.get_font()
	var x: float = 10.0
	var w: float = PANEL_W - 20.0

	# Header: FACTION
	var y: float = HudDrawHelpers.draw_section_header(ctrl, font, x, 16.0, w, "FACTION")

	# Player faction name + color square
	var sq_size: float = 10.0
	ctrl.draw_rect(Rect2(x, y - 9, sq_size, sq_size), fac_res.color_primary)
	ctrl.draw_string(font, Vector2(x + sq_size + 6, y), fac_res.faction_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_HEADER)
	y += 18.0

	# Reputation bars for all factions
	var factions: Array[FactionResource] = faction_manager.get_all_factions()
	for fac in factions:
		_draw_rep_bar(ctrl, font_sm, x, y, w, fac)
		y += 30.0

	# Adjust panel height dynamically
	var needed_h: float = y + 8.0
	if absf(ctrl.size.y - needed_h) > 2.0:
		ctrl.offset_bottom = PANEL_Y + needed_h


func _draw_rep_bar(ctrl: Control, font: Font, x: float, y: float, w: float, fac: FactionResource) -> void:
	var rep: float = faction_manager.get_reputation(fac.faction_id)
	var standing: StringName = faction_manager.get_standing(fac.faction_id)
	var standing_label: String = STANDING_LABELS.get(standing, "---")
	var standing_col: Color = faction_manager.get_reputation_color(fac.faction_id)

	# Faction name (left) + standing label (right)
	ctrl.draw_string(font, Vector2(x, y), fac.faction_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, fac.color_primary)
	ctrl.draw_string(font, Vector2(x + w - BAR_W, y), standing_label, HORIZONTAL_ALIGNMENT_RIGHT, BAR_W, UITheme.FONT_SIZE_TINY, standing_col)

	# Bar: -100 to +100 mapped to 0..1
	var ratio: float = (rep + 100.0) / 200.0
	var bar_y: float = y + 4.0
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, bar_y), BAR_W + w - BAR_W - x, ratio, standing_col)
