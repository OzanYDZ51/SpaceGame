class_name MapEntities
extends Control

# =============================================================================
# Map Entity Layer - Draws entity icons, labels, selection, velocity vectors
# All custom-drawn for holographic aesthetic
# =============================================================================

var camera: MapCamera = null
var selected_id: String = ""
var filters: Dictionary = {}  # EntityType -> bool (true = hidden)
var _hover_id: String = ""
var _pulse_t: float = 0.0
var _player_id: String = ""
var preview_entities: Dictionary = {}  # When non-empty, overrides EntityRegistry

const HIT_RADIUS: float = 16.0  # click detection radius in pixels

# Draw order: background entities first, player always on top
var _draw_order: Array = [
	EntityRegistrySystem.EntityType.STAR,
	EntityRegistrySystem.EntityType.PLANET,
	EntityRegistrySystem.EntityType.STATION,
	EntityRegistrySystem.EntityType.JUMP_GATE,
	EntityRegistrySystem.EntityType.SHIP_NPC,
	EntityRegistrySystem.EntityType.SHIP_PLAYER,
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	_pulse_t += delta


func _get_entities() -> Dictionary:
	return preview_entities if not preview_entities.is_empty() else EntityRegistry.get_all()


func _draw() -> void:
	if camera == null:
		return

	var entities: Dictionary = _get_entities()
	var font := ThemeDB.fallback_font

	# Draw selection line first (behind everything)
	if selected_id != "" and _player_id != "" and selected_id != _player_id:
		_draw_selection_line(entities, font)

	# Draw entities in type order (player always on top)
	for draw_type in _draw_order:
		if draw_type == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue  # drawn by renderer
		if filters.get(draw_type, false):
			continue  # filtered out
		for ent in entities.values():
			if ent["type"] == draw_type:
				_draw_entity(ent, font)

	# Off-screen indicator for selected entity
	if selected_id != "":
		_draw_offscreen_indicator(entities, font)

	# Hover tooltip
	if _hover_id != "" and _hover_id != selected_id:
		_draw_hover_tooltip(entities, font)


func _draw_entity(ent: Dictionary, font: Font) -> void:
	var screen_pos: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])

	# Cull off-screen (with margin for labels)
	if screen_pos.x < -50 or screen_pos.x > size.x + 50:
		return
	if screen_pos.y < -50 or screen_pos.y > size.y + 50:
		return

	var ent_type: int = ent["type"]
	var is_selected: bool = ent["id"] == selected_id
	var is_hovered: bool = ent["id"] == _hover_id

	match ent_type:
		EntityRegistrySystem.EntityType.STAR:
			_draw_star(screen_pos, ent, is_selected)
		EntityRegistrySystem.EntityType.PLANET:
			_draw_planet(screen_pos, ent, is_selected, font)
		EntityRegistrySystem.EntityType.STATION:
			_draw_station(screen_pos, ent, is_selected, font)
		EntityRegistrySystem.EntityType.SHIP_PLAYER:
			_draw_player(screen_pos, ent, is_selected, font)
		EntityRegistrySystem.EntityType.JUMP_GATE:
			_draw_jump_gate(screen_pos, ent, is_selected, font)
		EntityRegistrySystem.EntityType.SHIP_NPC:
			_draw_npc_ship(screen_pos, ent, is_selected, font)

	# Selection ring
	if is_selected:
		var pulse: float = sin(_pulse_t * 3.0) * 0.3 + 0.7
		var ring_col := Color(MapColors.SELECTION_RING.r, MapColors.SELECTION_RING.g, MapColors.SELECTION_RING.b, pulse)
		draw_arc(screen_pos, 18.0, 0, TAU, 32, ring_col, 1.5, true)

	# Hover highlight
	if is_hovered and not is_selected:
		draw_arc(screen_pos, 14.0, 0, TAU, 24, MapColors.PRIMARY_DIM, 1.0, true)


# =============================================================================
# STAR - Multi-layered corona with animated lens flare
# =============================================================================
func _draw_star(pos: Vector2, ent: Dictionary, _is_selected: bool) -> void:
	var col: Color = ent["color"]
	var base_radius: float = clampf(ent["radius"] * camera.zoom, 6.0, 40.0)

	# Outer corona layers (large diffuse glow)
	var corona_pulse: float = 1.0 + sin(_pulse_t * 0.8) * 0.06
	for layer_i in 5:
		var t: float = float(layer_i) / 4.0  # 0..1
		var r: float = base_radius * lerpf(6.0, 2.0, t) * corona_pulse
		var a: float = lerpf(0.02, 0.06, t)
		var lc := Color(col.r, col.g, col.b, a)
		draw_circle(pos, r, lc)

	# Inner glow ring (brighter corona edge)
	var ring_a: float = 0.12 + sin(_pulse_t * 1.2) * 0.03
	draw_arc(pos, base_radius * 1.6, 0, TAU, 48, Color(col.r, col.g, col.b, ring_a), 2.0, true)

	# Core body
	draw_circle(pos, base_radius, col)

	# Hot white center gradient
	draw_circle(pos, base_radius * 0.65, Color(1.0, 1.0, 0.95, 0.35))
	draw_circle(pos, base_radius * 0.35, Color(1.0, 1.0, 0.98, 0.6))
	draw_circle(pos, base_radius * 0.15, Color(1.0, 1.0, 1.0, 0.8))

	# Primary cross rays (4 cardinal, slow rotate)
	var ray_len: float = base_radius * 3.5
	var ray_alpha: float = 0.18 + sin(_pulse_t * 1.5) * 0.04
	var ray_col := Color(col.r, col.g, col.b, ray_alpha)
	for i in 4:
		var angle: float = (PI / 2.0) * float(i) + _pulse_t * 0.05
		var p_start: Vector2 = pos + Vector2(cos(angle), sin(angle)) * base_radius * 0.6
		var p_end: Vector2 = pos + Vector2(cos(angle), sin(angle)) * ray_len
		draw_line(p_start, p_end, ray_col, 1.5)
		# Thin secondary line beside each ray for "thickness"
		var perp := Vector2(-sin(angle), cos(angle)) * 1.0
		draw_line(p_start + perp, p_end * 0.7 + pos * 0.3 + perp, Color(col.r, col.g, col.b, ray_alpha * 0.4), 1.0)

	# Secondary diagonal rays (4, offset 45deg, shorter, counter-rotate)
	var ray2_len: float = base_radius * 2.0
	var ray2_col := Color(col.r, col.g, col.b, ray_alpha * 0.5)
	for i in 4:
		var angle: float = (PI / 2.0) * float(i) + PI / 4.0 - _pulse_t * 0.03
		var p_start: Vector2 = pos + Vector2(cos(angle), sin(angle)) * base_radius * 0.7
		var p_end: Vector2 = pos + Vector2(cos(angle), sin(angle)) * ray2_len
		draw_line(p_start, p_end, ray2_col, 1.0)

	# Name label
	var font := ThemeDB.fallback_font
	var name_text: String = ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, pos + Vector2(-tw * 0.5, base_radius * 1.8 + 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MapColors.STAR_GOLD)


# =============================================================================
# PLANET - Type-specific visuals with atmosphere glow
# =============================================================================
func _draw_planet(pos: Vector2, ent: Dictionary, is_selected: bool, font: Font) -> void:
	var col: Color = ent["color"]
	var base_radius: float = clampf(ent["radius"] * camera.zoom, 3.5, 24.0)
	var planet_type: String = ent["extra"].get("planet_type", "rocky")

	# Atmosphere glow (thin halo around planet)
	var atmo_alpha: float = 0.12
	var atmo_col: Color
	match planet_type:
		"ocean": atmo_col = Color(0.3, 0.6, 1.0, atmo_alpha)
		"gas_giant": atmo_col = Color(col.r, col.g * 0.8, col.b * 0.5, atmo_alpha * 1.5)
		"lava": atmo_col = Color(1.0, 0.4, 0.1, atmo_alpha * 1.2)
		"ice": atmo_col = Color(0.6, 0.8, 1.0, atmo_alpha * 0.8)
		_: atmo_col = Color(0.7, 0.6, 0.5, atmo_alpha * 0.5)
	draw_circle(pos, base_radius * 1.6, atmo_col)
	draw_circle(pos, base_radius * 1.25, Color(atmo_col.r, atmo_col.g, atmo_col.b, atmo_col.a * 1.5))

	# Planet body
	draw_circle(pos, base_radius, col)

	# Type-specific surface detail
	match planet_type:
		"gas_giant":
			# Horizontal bands
			var band_count: int = 3 if base_radius > 6.0 else 1
			for b in band_count:
				var by: float = lerpf(-0.6, 0.6, float(b + 1) / float(band_count + 1))
				var band_y: float = pos.y + by * base_radius
				var band_half_w: float = sqrt(maxf(0.0, 1.0 - by * by)) * base_radius * 0.9
				var band_col := Color(col.r * 0.8, col.g * 0.85, col.b * 0.7, 0.2)
				draw_line(
					Vector2(pos.x - band_half_w, band_y),
					Vector2(pos.x + band_half_w, band_y),
					band_col, maxf(1.0, base_radius * 0.12)
				)
		"lava":
			# Hot glow spots
			if base_radius > 5.0:
				var glow_pulse: float = 0.3 + sin(_pulse_t * 2.5) * 0.1
				draw_circle(pos + Vector2(-base_radius * 0.2, base_radius * 0.15), base_radius * 0.25, Color(1.0, 0.6, 0.1, glow_pulse))
				draw_circle(pos + Vector2(base_radius * 0.3, -base_radius * 0.1), base_radius * 0.15, Color(1.0, 0.5, 0.0, glow_pulse * 0.7))
		"ocean":
			# Subtle blue-white swirl highlight
			draw_circle(pos + Vector2(-base_radius * 0.2, -base_radius * 0.15), base_radius * 0.3, Color(0.8, 0.9, 1.0, 0.15))
		"ice":
			# Polar ice cap shine
			draw_circle(pos + Vector2(0, -base_radius * 0.55), base_radius * 0.35, Color(0.9, 0.95, 1.0, 0.2))

	# Specular highlight (top-left light source)
	var highlight := Color(1, 1, 1, 0.2)
	draw_circle(pos + Vector2(-base_radius * 0.25, -base_radius * 0.25), base_radius * 0.4, highlight)

	# Shadow (bottom-right terminator)
	var shadow := Color(0, 0, 0, 0.15)
	draw_arc(pos, base_radius, 0.5, PI + 0.5, 16, shadow, maxf(1.5, base_radius * 0.2), true)

	# Rings if applicable
	if ent["extra"].get("has_rings", false):
		# Multi-layer rings
		var ring_col1 := Color(col.r * 0.9, col.g * 0.85, col.b * 0.7, 0.25)
		var ring_col2 := Color(col.r * 0.7, col.g * 0.65, col.b * 0.5, 0.15)
		draw_arc(pos, base_radius * 1.6, -0.35, PI + 0.35, 32, ring_col1, 1.5, true)
		draw_arc(pos, base_radius * 1.9, -0.3, PI + 0.3, 32, ring_col2, 1.0, true)
		draw_arc(pos, base_radius * 2.15, -0.25, PI + 0.25, 24, Color(ring_col2.r, ring_col2.g, ring_col2.b, 0.08), 1.0, true)

	# Label (show if zoom is close enough or selected)
	var show_label: bool = is_selected or camera.zoom > 1e-5 or base_radius > 6.0
	if show_label:
		var name_text: String = ent["name"]
		var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var label_y: float = base_radius + 14.0
		if ent["extra"].get("has_rings", false):
			label_y = base_radius * 2.2 + 8.0
		draw_string(font, pos + Vector2(-tw * 0.5, label_y), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MapColors.TEXT_DIM)


# =============================================================================
# STATION (diamond + beacon pulse)
# =============================================================================
func _draw_station(pos: Vector2, ent: Dictionary, _is_selected: bool, font: Font) -> void:
	var s: float = 7.0
	var col: Color = MapColors.STATION_TEAL

	# Beacon pulse ring (expanding outward)
	var pulse_phase: float = fmod(_pulse_t * 0.6, 1.0)
	var pulse_radius: float = s + pulse_phase * 18.0
	var pulse_alpha: float = (1.0 - pulse_phase) * 0.25
	draw_arc(pos, pulse_radius, 0, TAU, 24, Color(col.r, col.g, col.b, pulse_alpha), 1.0, true)

	# Glow halo
	draw_circle(pos, s * 2.2, Color(col.r, col.g, col.b, 0.06))

	# Diamond body
	var points := PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s, 0),
		pos + Vector2(0, s),
		pos + Vector2(-s, 0),
	])
	draw_colored_polygon(points, col)

	# Inner bright center
	var inner_s: float = s * 0.4
	var inner_points := PackedVector2Array([
		pos + Vector2(0, -inner_s),
		pos + Vector2(inner_s, 0),
		pos + Vector2(0, inner_s),
		pos + Vector2(-inner_s, 0),
	])
	draw_colored_polygon(inner_points, Color(1.0, 1.0, 1.0, 0.3))

	# Border
	var border_points := PackedVector2Array([
		pos + Vector2(0, -s - 1),
		pos + Vector2(s + 1, 0),
		pos + Vector2(0, s + 1),
		pos + Vector2(-s - 1, 0),
		pos + Vector2(0, -s - 1),
	])
	draw_polyline(border_points, Color(col.r, col.g, col.b, 0.6), 1.0)

	# Label always visible for stations
	var name_text: String = ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, pos + Vector2(-tw * 0.5, s + 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MapColors.STATION_TEAL)


# =============================================================================
# JUMP GATE (ring icon at system edge)
# =============================================================================
func _draw_jump_gate(pos: Vector2, ent: Dictionary, _is_selected: bool, font: Font) -> void:
	var col := Color(0.15, 0.6, 1.0, 0.9)
	var s: float = 6.0

	# Check if this is the route gate
	var is_route_gate: bool = false
	var rm: RouteManager = GameManager._route_manager if GameManager else null
	if rm and rm.is_route_active() and ent["id"] == rm.next_gate_entity_id:
		is_route_gate = true

	# Route gate highlight: pulsing gold ring
	if is_route_gate:
		var route_pulse: float = sin(_pulse_t * 3.0) * 0.3 + 0.7
		var route_col := Color(1.0, 0.8, 0.0, route_pulse * 0.6)
		draw_arc(pos, s + 6.0 + route_pulse * 3.0, 0, TAU, 24, route_col, 2.5, true)
		draw_arc(pos, s + 2.0, 0, TAU, 20, Color(1.0, 0.8, 0.0, 0.3), 1.5, true)

	# Outer ring
	draw_arc(pos, s, 0, TAU, 16, col, 2.0, true)

	# Inner glow
	var pulse: float = sin(_pulse_t * 2.5) * 0.3 + 0.5
	draw_circle(pos, s * 0.4, Color(col.r, col.g, col.b, pulse * 0.3))

	# Label with target system name
	var target_name: String = ent.get("extra", {}).get("target_system_name", ent["name"])
	var name_text: String = target_name if target_name.length() < 30 else ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var label_col := Color(1.0, 0.8, 0.0, 0.9) if is_route_gate else Color(col.r, col.g, col.b, 0.7)
	draw_string(font, pos + Vector2(-tw * 0.5, s + 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_col)

	# Route label
	if is_route_gate:
		var route_label := "PROCHAIN SAUT"
		var rtw: float = font.get_string_size(route_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, pos + Vector2(-rtw * 0.5, -s - 8), route_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.8, 0.0, 0.8))


# =============================================================================
# PLAYER (triangle pointing in heading direction)
# =============================================================================
func _draw_player(pos: Vector2, ent: Dictionary, _is_selected: bool, font: Font) -> void:
	var col: Color = MapColors.PLAYER

	# Get heading from velocity or default to up
	var heading_angle: float = -PI / 2.0  # default: pointing up
	var vel_x: float = ent["vel_x"]
	var vel_z: float = ent["vel_z"]
	var speed: float = sqrt(vel_x * vel_x + vel_z * vel_z)
	if speed > 1.0:
		heading_angle = atan2(vel_z, vel_x)

	# Triangle
	var s: float = 8.0
	var p1: Vector2 = pos + Vector2(cos(heading_angle), sin(heading_angle)) * s * 1.5
	var p2: Vector2 = pos + Vector2(cos(heading_angle + 2.4), sin(heading_angle + 2.4)) * s
	var p3: Vector2 = pos + Vector2(cos(heading_angle - 2.4), sin(heading_angle - 2.4)) * s
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)

	# Pulsing ring
	var pulse: float = sin(_pulse_t * 2.0) * 0.3 + 0.7
	var ring_col := Color(col.r, col.g, col.b, pulse * 0.4)
	draw_arc(pos, 14.0, 0, TAU, 24, ring_col, 1.0, true)

	# Velocity vector
	if speed > 5.0:
		var vel_end: Vector2 = pos + Vector2(vel_x, vel_z).normalized() * clampf(speed * 0.05, 10.0, 60.0)
		draw_line(pos, vel_end, Color(col.r, col.g, col.b, 0.4), 1.0)
		# Arrowhead
		var arrow_angle: float = atan2(vel_z, vel_x)
		var a1: Vector2 = vel_end + Vector2(cos(arrow_angle + 2.7), sin(arrow_angle + 2.7)) * 5.0
		var a2: Vector2 = vel_end + Vector2(cos(arrow_angle - 2.7), sin(arrow_angle - 2.7)) * 5.0
		draw_line(vel_end, a1, Color(col.r, col.g, col.b, 0.4), 1.0)
		draw_line(vel_end, a2, Color(col.r, col.g, col.b, 0.4), 1.0)

	# Label
	var name_text: String = ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, pos + Vector2(-tw * 0.5, 20), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


# =============================================================================
# NPC SHIP (triangle pointing in heading direction, faction-colored)
# =============================================================================
func _draw_npc_ship(pos: Vector2, ent: Dictionary, is_selected: bool, font: Font) -> void:
	var col: Color = ent.get("color", MapColors.NPC_SHIP)
	var s: float = 5.0

	# Get heading from velocity
	var heading_angle: float = -PI / 2.0  # default: pointing up
	var vel_x: float = ent["vel_x"]
	var vel_z: float = ent["vel_z"]
	if sqrt(vel_x * vel_x + vel_z * vel_z) > 1.0:
		heading_angle = atan2(vel_z, vel_x)

	# Triangle pointing in heading direction
	var p1: Vector2 = pos + Vector2(cos(heading_angle), sin(heading_angle)) * s * 1.5
	var p2: Vector2 = pos + Vector2(cos(heading_angle + 2.4), sin(heading_angle + 2.4)) * s
	var p3: Vector2 = pos + Vector2(cos(heading_angle - 2.4), sin(heading_angle - 2.4)) * s
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)

	# Show label when selected or zoomed in enough
	var show_label: bool = is_selected or camera.zoom > 0.005
	if show_label:
		var label_text: String = ent["name"]
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, pos + Vector2(-tw * 0.5, s + 12), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


# =============================================================================
# SELECTION LINE (dashed line from player to selected entity)
# =============================================================================
func _draw_selection_line(entities: Dictionary, font: Font) -> void:
	if not entities.has(_player_id) or not entities.has(selected_id):
		return

	var player: Dictionary = entities[_player_id]
	var target: Dictionary = entities[selected_id]

	var p1: Vector2 = camera.universe_to_screen(player["pos_x"], player["pos_z"])
	var p2: Vector2 = camera.universe_to_screen(target["pos_x"], target["pos_z"])

	# Dashed line
	var dir: Vector2 = (p2 - p1)
	var length: float = dir.length()
	if length < 5.0:
		return
	dir = dir.normalized()
	var dash_len: float = 8.0
	var gap_len: float = 6.0
	var traveled: float = 0.0
	while traveled < length:
		var seg_start: float = traveled
		var seg_end: float = minf(traveled + dash_len, length)
		draw_line(
			p1 + dir * seg_start,
			p1 + dir * seg_end,
			MapColors.SELECTION_LINE, 1.0
		)
		traveled += dash_len + gap_len

	# Distance label at midpoint
	var dx: float = target["pos_x"] - player["pos_x"]
	var dz: float = target["pos_z"] - player["pos_z"]
	var dist: float = sqrt(dx * dx + dz * dz)
	var mid: Vector2 = (p1 + p2) * 0.5
	var dist_text: String = camera.format_distance(dist)
	var tw: float = font.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	# Background behind text
	draw_rect(Rect2(mid.x - tw * 0.5 - 4, mid.y - 12, tw + 8, 16), MapColors.BG, true)
	draw_string(font, Vector2(mid.x - tw * 0.5, mid.y), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MapColors.SELECTION_LINE * Color(1, 1, 1, 2.5))


# =============================================================================
# OFF-SCREEN INDICATOR (arrow at screen edge for selected entity)
# =============================================================================
func _draw_offscreen_indicator(entities: Dictionary, font: Font) -> void:
	if not entities.has(selected_id):
		return
	var ent: Dictionary = entities[selected_id]
	var screen_pos: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])

	# Check if on-screen (with margin)
	var margin: float = 40.0
	if screen_pos.x >= margin and screen_pos.x <= size.x - margin \
		and screen_pos.y >= margin and screen_pos.y <= size.y - margin:
		return  # on-screen, no indicator needed

	# Clamp to screen edge
	var center: Vector2 = size * 0.5
	var dir: Vector2 = (screen_pos - center).normalized()
	# Find edge intersection
	var clamped: Vector2 = screen_pos
	clamped.x = clampf(clamped.x, margin, size.x - margin)
	clamped.y = clampf(clamped.y, margin, size.y - margin)

	# Draw arrow triangle pointing outward
	var arrow_size: float = 10.0
	var arrow_angle: float = dir.angle()
	var ap1: Vector2 = clamped + Vector2(cos(arrow_angle), sin(arrow_angle)) * arrow_size
	var ap2: Vector2 = clamped + Vector2(cos(arrow_angle + 2.4), sin(arrow_angle + 2.4)) * arrow_size * 0.6
	var ap3: Vector2 = clamped + Vector2(cos(arrow_angle - 2.4), sin(arrow_angle - 2.4)) * arrow_size * 0.6
	var col: Color = MapColors.SELECTION_RING
	draw_colored_polygon(PackedVector2Array([ap1, ap2, ap3]), col)

	# Distance label next to arrow
	if _player_id != "" and entities.has(_player_id):
		var player: Dictionary = entities[_player_id]
		var dx: float = ent["pos_x"] - player["pos_x"]
		var dz: float = ent["pos_z"] - player["pos_z"]
		var dist: float = sqrt(dx * dx + dz * dz)
		var dist_text: String = camera.format_distance(dist)
		# Offset label perpendicular to arrow direction
		var label_offset: Vector2 = Vector2(-dir.y, dir.x) * 14.0 - dir * 5.0
		var label_pos: Vector2 = clamped + label_offset
		label_pos.x = clampf(label_pos.x, 5.0, size.x - 80.0)
		label_pos.y = clampf(label_pos.y, 12.0, size.y - 5.0)
		draw_string(font, label_pos, dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


# =============================================================================
# HOVER TOOLTIP
# =============================================================================
func _draw_hover_tooltip(entities: Dictionary, font: Font) -> void:
	if not entities.has(_hover_id):
		return
	var ent: Dictionary = entities[_hover_id]
	var screen_pos: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])

	var name_text: String = ent.get("name", "???")
	var type_text: String = _type_label(ent["type"])
	var line1_w: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var line2_w: float = font.get_string_size(type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x

	# Distance from player
	var dist_text: String = ""
	if _player_id != "" and entities.has(_player_id):
		var player: Dictionary = entities[_player_id]
		var dx: float = ent["pos_x"] - player["pos_x"]
		var dz: float = ent["pos_z"] - player["pos_z"]
		var dist: float = sqrt(dx * dx + dz * dz)
		dist_text = camera.format_distance(dist)

	var line3_w: float = 0.0
	if dist_text != "":
		line3_w = font.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x

	var box_w: float = maxf(maxf(line1_w, line2_w), line3_w) + 16.0
	var box_h: float = 40.0 if dist_text == "" else 54.0
	var box_pos: Vector2 = screen_pos + Vector2(20, -box_h * 0.5)

	# Keep on screen
	if box_pos.x + box_w > size.x - 10:
		box_pos.x = screen_pos.x - box_w - 20
	if box_pos.y < 10:
		box_pos.y = 10
	if box_pos.y + box_h > size.y - 10:
		box_pos.y = size.y - box_h - 10

	# Background
	draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), MapColors.BG_PANEL)
	draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), MapColors.PANEL_BORDER, false, 1.0)

	# Text
	var tx: float = box_pos.x + 8.0
	var ty: float = box_pos.y + 14.0
	draw_string(font, Vector2(tx, ty), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MapColors.TEXT)
	ty += 14.0
	draw_string(font, Vector2(tx, ty), type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, MapColors.TEXT_DIM)
	if dist_text != "":
		ty += 14.0
		draw_string(font, Vector2(tx, ty), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, MapColors.LABEL_VALUE)


func _type_label(type: int) -> String:
	match type:
		EntityRegistrySystem.EntityType.STAR: return "Étoile"
		EntityRegistrySystem.EntityType.PLANET: return "Planète"
		EntityRegistrySystem.EntityType.STATION: return "Station"
		EntityRegistrySystem.EntityType.SHIP_PLAYER: return "Vaisseau joueur"
		EntityRegistrySystem.EntityType.SHIP_NPC: return "Vaisseau PNJ"
		EntityRegistrySystem.EntityType.ASTEROID_BELT: return "Ceinture"
		EntityRegistrySystem.EntityType.JUMP_GATE: return "Portail"
	return "Inconnu"


# =============================================================================
# HIT DETECTION
# =============================================================================
func get_entity_at(screen_pos: Vector2) -> String:
	if camera == null:
		return ""
	var best_id: String = ""
	var best_dist: float = HIT_RADIUS
	var entities: Dictionary = _get_entities()
	for ent in entities.values():
		if ent["type"] == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue
		if filters.get(ent["type"], false):
			continue  # filtered out
		var sp: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])
		var d: float = screen_pos.distance_to(sp)
		if d < best_dist:
			best_dist = d
			best_id = ent["id"]
	return best_id


func update_hover(screen_pos: Vector2) -> bool:
	var new_id := get_entity_at(screen_pos)
	if new_id == _hover_id:
		return false
	_hover_id = new_id
	return true
