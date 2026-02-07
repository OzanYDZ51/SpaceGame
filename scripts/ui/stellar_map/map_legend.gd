class_name MapLegend
extends Control

# =============================================================================
# Map Legend - Keyboard shortcuts overlay
# Semi-transparent panel at bottom-left. Auto-fades after 5s. Toggle with H.
# =============================================================================

var _fade_timer: float = 0.0
var _visible_flag: bool = false

const FADE_DELAY: float = 5.0
const FADE_DURATION: float = 1.0
const PANEL_WIDTH: float = 280.0
const ROW_HEIGHT: float = 16.0

const SHORTCUTS: Array = [
	["M / Échap", "Fermer la carte"],
	["1-5", "Niveaux de zoom"],
	["F", "Suivre le joueur"],
	["O", "Masquer les orbites"],
	["P", "Masquer les planètes"],
	["T", "Masquer les stations"],
	["N", "Masquer les PNJ"],
	["Molette", "Zoom"],
	["Clic milieu", "Panoramique"],
	["Clic gauche", "Sélectionner"],
	["Clic droit", "Recentrer"],
	["Double-clic", "Centrer + Zoom"],
	["/", "Recherche"],
	["H", "Aide"],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not _visible_flag:
		return
	_fade_timer += delta
	if _fade_timer > FADE_DELAY + FADE_DURATION:
		_visible_flag = false
		visible = false
	queue_redraw()


func show_legend() -> void:
	_visible_flag = true
	_fade_timer = 0.0
	visible = true
	queue_redraw()


func toggle() -> void:
	if _visible_flag:
		_visible_flag = false
		visible = false
	else:
		show_legend()


func _draw() -> void:
	if not _visible_flag:
		return

	var font := ThemeDB.fallback_font

	# Compute alpha (fade out after FADE_DELAY)
	var alpha: float = 1.0
	if _fade_timer > FADE_DELAY:
		alpha = 1.0 - clampf((_fade_timer - FADE_DELAY) / FADE_DURATION, 0.0, 1.0)

	var panel_h: float = 30.0 + SHORTCUTS.size() * ROW_HEIGHT
	var px: float = 16.0
	var py: float = size.y - panel_h - 50.0

	# Background
	var bg := Color(MapColors.BG_PANEL.r, MapColors.BG_PANEL.g, MapColors.BG_PANEL.b, MapColors.BG_PANEL.a * alpha)
	draw_rect(Rect2(px, py, PANEL_WIDTH, panel_h), bg)
	var border := Color(MapColors.PANEL_BORDER.r, MapColors.PANEL_BORDER.g, MapColors.PANEL_BORDER.b, MapColors.PANEL_BORDER.a * alpha)
	draw_rect(Rect2(px, py, PANEL_WIDTH, panel_h), border, false, 1.0)

	# Title
	var title_col := Color(MapColors.TEXT_HEADER.r, MapColors.TEXT_HEADER.g, MapColors.TEXT_HEADER.b, MapColors.TEXT_HEADER.a * alpha)
	draw_string(font, Vector2(px + 10, py + 18), "RACCOURCIS CLAVIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, title_col)

	# Rows
	var y: float = py + 34.0
	var key_col := Color(MapColors.LABEL_VALUE.r, MapColors.LABEL_VALUE.g, MapColors.LABEL_VALUE.b, MapColors.LABEL_VALUE.a * alpha)
	var desc_col := Color(MapColors.TEXT_DIM.r, MapColors.TEXT_DIM.g, MapColors.TEXT_DIM.b, MapColors.TEXT_DIM.a * alpha)

	for shortcut in SHORTCUTS:
		draw_string(font, Vector2(px + 10, y), shortcut[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, key_col)
		draw_string(font, Vector2(px + 110, y), shortcut[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, desc_col)
		y += ROW_HEIGHT
