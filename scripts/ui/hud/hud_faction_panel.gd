class_name HudFactionPanel
extends Control

# =============================================================================
# HUD Faction Panel — Displays player faction emblem + reputation bars.
# Bottom-left, below the economy panel. Uses _draw() pattern.
# Each faction shows its geometric emblem icon beside the name and bar.
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
const EMBLEM_R: float = 10.0  # Mini emblem radius for rep rows
const HEADER_EMBLEM_R: float = 14.0  # Player faction emblem radius

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

	# Player faction: emblem + name
	var emblem_cx: float = x + HEADER_EMBLEM_R + 2.0
	var emblem_cy: float = y - 4.0
	_draw_faction_emblem(ctrl, Vector2(emblem_cx, emblem_cy), HEADER_EMBLEM_R, fac_res.color_primary, fac_res.faction_id, true)
	var name_x: float = emblem_cx + HEADER_EMBLEM_R + 8.0
	ctrl.draw_string(font, Vector2(name_x, y), fac_res.faction_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_HEADER)
	y += 22.0

	# Reputation bars for all factions
	var factions: Array[FactionResource] = faction_manager.get_all_factions()
	for fac in factions:
		_draw_rep_row(ctrl, font_sm, x, y, w, fac)
		y += 32.0

	# Adjust panel height dynamically
	var needed_h: float = y + 6.0
	if absf(ctrl.size.y - needed_h) > 2.0:
		ctrl.offset_bottom = PANEL_Y + needed_h


func _draw_rep_row(ctrl: Control, font: Font, x: float, y: float, w: float, fac: FactionResource) -> void:
	var rep: float = faction_manager.get_reputation(fac.faction_id)
	var standing: StringName = faction_manager.get_standing(fac.faction_id)
	var standing_label: String = STANDING_LABELS.get(standing, "---")
	var standing_col: Color = faction_manager.get_reputation_color(fac.faction_id)

	# Mini emblem
	var ecx: float = x + EMBLEM_R + 1.0
	var ecy: float = y - 3.0
	_draw_faction_emblem(ctrl, Vector2(ecx, ecy), EMBLEM_R, fac.color_primary, fac.faction_id, false)

	# Faction name (after emblem) + standing label (right)
	var text_x: float = ecx + EMBLEM_R + 6.0
	ctrl.draw_string(font, Vector2(text_x, y), fac.faction_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, fac.color_primary)
	ctrl.draw_string(font, Vector2(x + w - 60, y), standing_label, HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_TINY, standing_col)

	# Bar: -100 to +100 mapped to 0..1
	var ratio: float = (rep + 100.0) / 200.0
	var bar_y: float = y + 4.0
	var bar_x: float = text_x
	var bar_w: float = w - (text_x - x)
	HudDrawHelpers.draw_bar(ctrl, Vector2(bar_x, bar_y), bar_w, ratio, standing_col)


# =============================================================================
# FACTION EMBLEMS — Geometric faction symbols drawn procedurally.
# Used here in the HUD and also in the Faction Selection Screen.
# =============================================================================

## Draw a faction emblem at the given center and radius.
## filled=true draws the filled polygon, false draws outline only (for mini icons).
static func _draw_faction_emblem(ctrl: Control, center: Vector2, radius: float, col: Color, faction_id: StringName, filled: bool) -> void:
	match faction_id:
		&"nova_terra":
			_draw_emblem_nova_terra(ctrl, center, radius, col, filled)
		&"kharsis":
			_draw_emblem_kharsis(ctrl, center, radius, col, filled)
		&"pirate":
			_draw_emblem_pirate(ctrl, center, radius, col, filled)
		_:
			_draw_emblem_default(ctrl, center, radius, col, filled)


## Nova Terra — 6-pointed star / federation shield
static func _draw_emblem_nova_terra(ctrl: Control, center: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts: PackedVector2Array = []
	for i in 6:
		var angle: float = -PI * 0.5 + TAU * float(i) / 6.0
		var rv: float = r if i % 2 == 0 else r * 0.5
		pts.append(center + Vector2(cos(angle) * rv, sin(angle) * rv))
	if filled:
		ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5 if filled else 1.0)
	# Inner circle
	_draw_circle(ctrl, center, r * 0.35, col, 12, filled)


## Kharsis — Angular aggressive / dominion crest
static func _draw_emblem_kharsis(ctrl: Control, center: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts: PackedVector2Array = [
		center + Vector2(0, -r),
		center + Vector2(r * 0.8, -r * 0.3),
		center + Vector2(r * 0.5, r * 0.8),
		center + Vector2(0, r * 0.4),
		center + Vector2(-r * 0.5, r * 0.8),
		center + Vector2(-r * 0.8, -r * 0.3),
	]
	if filled:
		ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5 if filled else 1.0)
	# Inner cross
	ctrl.draw_line(center + Vector2(0, -r * 0.45), center + Vector2(0, r * 0.25), col, 1.5 if filled else 1.0)
	ctrl.draw_line(center + Vector2(-r * 0.35, 0), center + Vector2(r * 0.35, 0), col, 1.5 if filled else 1.0)


## Pirates — Skull-like / danger symbol (diamond + cross)
static func _draw_emblem_pirate(ctrl: Control, center: Vector2, r: float, col: Color, filled: bool) -> void:
	# Outer diamond
	var pts: PackedVector2Array = [
		center + Vector2(0, -r),
		center + Vector2(r, 0),
		center + Vector2(0, r),
		center + Vector2(-r, 0),
	]
	if filled:
		ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5 if filled else 1.0)
	# Inner X (crossed bones)
	var s: float = r * 0.4
	ctrl.draw_line(center + Vector2(-s, -s), center + Vector2(s, s), col, 1.5 if filled else 1.0)
	ctrl.draw_line(center + Vector2(s, -s), center + Vector2(-s, s), col, 1.5 if filled else 1.0)


## Default — Simple circle for unknown factions
static func _draw_emblem_default(ctrl: Control, center: Vector2, r: float, col: Color, filled: bool) -> void:
	_draw_circle(ctrl, center, r, col, 16, filled)


static func _draw_circle(ctrl: Control, center: Vector2, r: float, col: Color, segments: int, filled: bool) -> void:
	var pts: PackedVector2Array = []
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(angle) * r, sin(angle) * r))
	if filled:
		ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.2))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5 if filled else 1.0)
