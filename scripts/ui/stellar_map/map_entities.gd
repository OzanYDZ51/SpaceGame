class_name MapEntities
extends Control

# =============================================================================
# Map Entity Layer - Draws entity icons, labels, selection, velocity vectors
# All custom-drawn for holographic aesthetic
# =============================================================================

var camera = null
var selected_id: String = ""
var selected_ids: Array[String] = []
var filters: Dictionary = {}  # EntityType -> bool (true = hidden)
var _hover_id: String = ""
var _pulse_t: float = 0.0
var _player_id: String = ""
var preview_entities: Dictionary = {}  # When non-empty, overrides EntityRegistry
var preview_system_id: int = -1       # System ID being previewed (-1 = live view)
var trails: MapTrails = null
var marquee: MarqueeSelect = null

# Squadron refs (set by StellarMap)
var _squadron_fleet = null
var _squadron_list: Array = []  # Array[Squadron]

# Construction markers (set by StellarMap)
var construction_markers: Array[Dictionary] = []

# Route lines (ships → destination, set by StellarMap)
var route_ship_ids: Array[String] = []
var route_dest_ux: float = 0.0
var route_dest_uz: float = 0.0
var route_target_entity_id: String = ""  # If set, route tracks this entity's position
var route_is_follow: bool = false  # True = follow (cyan), false + target = attack (red)
var route_virtual_positions: Dictionary = {}  # virtual_id -> [ux, uz] for MP client ships

# Virtual fleet entities (deployed ships without EntityRegistry entries — MP client / timing)
var fleet_virtual_entities: Dictionary = {}  # virtual_id -> entity dict

# Waypoint flash (universe coords, set by StellarMap)
var waypoint_ux: float = 0.0
var waypoint_uz: float = 0.0
var waypoint_timer: float = 0.0
const WAYPOINT_DURATION: float = 2.0

# Hint text
var show_hint: bool = false

const HIT_RADIUS: float = 16.0  # click detection radius in pixels

# Draw order: background entities first, player always on top
var _draw_order: Array = [
	EntityRegistrySystem.EntityType.STAR,
	EntityRegistrySystem.EntityType.PLANET,
	EntityRegistrySystem.EntityType.STATION,
	EntityRegistrySystem.EntityType.JUMP_GATE,
	EntityRegistrySystem.EntityType.SHIP_NPC,
	EntityRegistrySystem.EntityType.SHIP_FLEET,
	EntityRegistrySystem.EntityType.SHIP_PLAYER,
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	_pulse_t += delta


func _get_entities() -> Dictionary:
	if not preview_entities.is_empty():
		return preview_entities
	var base: Dictionary = EntityRegistry.get_all()
	if fleet_virtual_entities.is_empty():
		return base
	# Merge virtual fleet entities (only those missing from real registry)
	var merged: Dictionary = base.duplicate(false)
	for k in fleet_virtual_entities:
		if not merged.has(k):
			merged[k] = fleet_virtual_entities[k]
	return merged


func _draw() -> void:
	if camera == null:
		return

	var entities: Dictionary = _get_entities()
	var font: Font = UITheme.get_font()

	# Draw trails behind everything
	_draw_trails(entities)

	# Draw selection line first (behind everything) — skip if route line is active
	if selected_id != "" and _player_id != "" and selected_id != _player_id and route_ship_ids.is_empty():
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

	# Marquee rectangle (on top of everything)
	if marquee and marquee.active and marquee.is_drag():
		var rect =marquee.get_rect()
		draw_rect(rect, Color(MapColors.PRIMARY.r, MapColors.PRIMARY.g, MapColors.PRIMARY.b, 0.08), true)
		draw_rect(rect, Color(MapColors.PRIMARY.r, MapColors.PRIMARY.g, MapColors.PRIMARY.b, 0.6), false, 1.0)

	# Construction markers
	_draw_construction_markers()

	# Squadron formation lines (member → leader)
	if not _squadron_list.is_empty() and _squadron_fleet:
		MapSquadronLines.draw_squadron_lines(self, camera, entities, _squadron_list, _squadron_fleet, _player_id)

	# Galaxy autopilot route line (player → next gate)
	_draw_galaxy_route_line(entities)

	# Preview route line (arrival gate → final destination in previewed system)
	_draw_preview_route_line(entities)

	# Post-arrival autopilot line (player → final destination, gold dashed)
	_draw_autopilot_line(entities)

	# Fleet route line (dashed) from ship to destination
	_draw_route_line(entities)

	# Waypoint flash
	_draw_waypoint_flash()

	# Hint text
	if show_hint:
		_draw_hint_text(font)


func _draw_entity(ent: Dictionary, font: Font) -> void:
	# Skip hidden entities (e.g. fleet autopilot waypoints)
	if ent.get("extra", {}).get("hidden", false):
		return

	var screen_pos: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])

	# Cull off-screen (with margin for labels)
	if screen_pos.x < -50 or screen_pos.x > size.x + 50:
		return
	if screen_pos.y < -50 or screen_pos.y > size.y + 50:
		return

	var ent_type: int = ent["type"]
	var ent_id: String = ent["id"]
	var is_selected: bool = ent_id == selected_id or ent_id in selected_ids
	var is_hovered: bool = ent_id == _hover_id

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
		EntityRegistrySystem.EntityType.SHIP_FLEET:
			_draw_fleet_ship(screen_pos, ent, is_selected, font)

	# Selection ring
	if is_selected:
		var pulse: float = sin(_pulse_t * 3.0) * 0.3 + 0.7
		var ring_col =Color(MapColors.SELECTION_RING.r, MapColors.SELECTION_RING.g, MapColors.SELECTION_RING.b, pulse)
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
		var lc =Color(col.r, col.g, col.b, a)
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
	var ray_col =Color(col.r, col.g, col.b, ray_alpha)
	for i in 4:
		var angle: float = (PI / 2.0) * float(i) + _pulse_t * 0.05
		var p_start: Vector2 = pos + Vector2(cos(angle), sin(angle)) * base_radius * 0.6
		var p_end: Vector2 = pos + Vector2(cos(angle), sin(angle)) * ray_len
		draw_line(p_start, p_end, ray_col, 1.5)
		# Thin secondary line beside each ray for "thickness"
		var perp =Vector2(-sin(angle), cos(angle)) * 1.0
		draw_line(p_start + perp, p_end * 0.7 + pos * 0.3 + perp, Color(col.r, col.g, col.b, ray_alpha * 0.4), 1.0)

	# Secondary diagonal rays (4, offset 45deg, shorter, counter-rotate)
	var ray2_len: float = base_radius * 2.0
	var ray2_col =Color(col.r, col.g, col.b, ray_alpha * 0.5)
	for i in 4:
		var angle: float = (PI / 2.0) * float(i) + PI / 4.0 - _pulse_t * 0.03
		var p_start: Vector2 = pos + Vector2(cos(angle), sin(angle)) * base_radius * 0.7
		var p_end: Vector2 = pos + Vector2(cos(angle), sin(angle)) * ray2_len
		draw_line(p_start, p_end, ray2_col, 1.0)

	# Name label
	var font: Font = UITheme.get_font()
	var name_text: String = ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, pos + Vector2(-tw * 0.5, base_radius * 1.8 + 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.STAR_GOLD)


# =============================================================================
# PLANET - Type-specific visuals with atmosphere glow
# =============================================================================
func _draw_planet(pos: Vector2, ent: Dictionary, is_selected: bool, font: Font) -> void:
	var col: Color = ent["color"]
	var base_radius: float = clampf(ent["radius"] * camera.zoom, 3.5, 24.0)
	var planet_type: String = ent["extra"].get("planet_type", "rocky")

	# Atmosphere glow derived from planet's actual color (coherent with 3D)
	var atmo_alpha: float = 0.12
	var atmo_col =Color(
		lerpf(col.r, 1.0, 0.3),
		lerpf(col.g, 1.0, 0.3),
		lerpf(col.b, 1.0, 0.3),
		atmo_alpha
	)
	match planet_type:
		"gas_giant": atmo_col.a = atmo_alpha * 1.5
		"lava": atmo_col = Color(lerpf(col.r, 1.0, 0.4), col.g * 0.6, col.b * 0.4, atmo_alpha * 1.2)
		"ice": atmo_col.a = atmo_alpha * 0.8
		"rocky": atmo_col.a = atmo_alpha * 0.5
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
				var band_col =Color(col.r * 0.8, col.g * 0.85, col.b * 0.7, 0.2)
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
	var highlight =Color(1, 1, 1, 0.2)
	draw_circle(pos + Vector2(-base_radius * 0.25, -base_radius * 0.25), base_radius * 0.4, highlight)

	# Shadow (bottom-right terminator)
	var shadow =Color(0, 0, 0, 0.15)
	draw_arc(pos, base_radius, 0.5, PI + 0.5, 16, shadow, maxf(1.5, base_radius * 0.2), true)

	# Rings if applicable
	if ent["extra"].get("has_rings", false):
		# Multi-layer rings
		var ring_col1 =Color(col.r * 0.9, col.g * 0.85, col.b * 0.7, 0.25)
		var ring_col2 =Color(col.r * 0.7, col.g * 0.65, col.b * 0.5, 0.15)
		draw_arc(pos, base_radius * 1.6, -0.35, PI + 0.35, 32, ring_col1, 1.5, true)
		draw_arc(pos, base_radius * 1.9, -0.3, PI + 0.3, 32, ring_col2, 1.0, true)
		draw_arc(pos, base_radius * 2.15, -0.25, PI + 0.25, 24, Color(ring_col2.r, ring_col2.g, ring_col2.b, 0.08), 1.0, true)

	# Label (show if zoom is close enough or selected)
	var show_label: bool = is_selected or camera.zoom > 1e-5 or base_radius > 6.0
	if show_label:
		var name_text: String = ent["name"]
		var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var label_y: float = base_radius + 14.0
		if ent["extra"].get("has_rings", false):
			label_y = base_radius * 2.2 + 8.0
		var label_col =Color(col.r, col.g, col.b, 0.7)
		draw_string(font, pos + Vector2(-tw * 0.5, label_y), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)


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
	var points =PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s, 0),
		pos + Vector2(0, s),
		pos + Vector2(-s, 0),
	])
	draw_colored_polygon(points, col)

	# Inner bright center
	var inner_s: float = s * 0.4
	var inner_points =PackedVector2Array([
		pos + Vector2(0, -inner_s),
		pos + Vector2(inner_s, 0),
		pos + Vector2(0, inner_s),
		pos + Vector2(-inner_s, 0),
	])
	draw_colored_polygon(inner_points, Color(1.0, 1.0, 1.0, 0.3))

	# Border
	var border_points =PackedVector2Array([
		pos + Vector2(0, -s - 1),
		pos + Vector2(s + 1, 0),
		pos + Vector2(0, s + 1),
		pos + Vector2(-s - 1, 0),
		pos + Vector2(0, -s - 1),
	])
	draw_polyline(border_points, Color(col.r, col.g, col.b, 0.6), 1.0)

	# Label always visible for stations
	var name_text: String = ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, pos + Vector2(-tw * 0.5, s + 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.STATION_TEAL)


# =============================================================================
# JUMP GATE (ring icon at system edge)
# =============================================================================
func _draw_jump_gate(pos: Vector2, ent: Dictionary, _is_selected: bool, font: Font) -> void:
	var col =Color(0.15, 0.6, 1.0, 0.9)
	var s: float = 6.0

	# Check if this is the route gate (departure) or arrival gate (preview)
	var is_route_gate: bool = false
	var is_arrival_gate: bool = false
	var rm = GameManager._route_manager if GameManager else null
	if rm and rm.is_route_active():
		if preview_system_id < 0 and ent["id"] == rm.next_gate_entity_id:
			is_route_gate = true
		elif preview_system_id >= 0 and rm.target_system_id == preview_system_id and rm.route.size() >= 2:
			var penultimate_id: int = rm.route[rm.route.size() - 2]
			if ent.get("extra", {}).get("target_system_id", -1) == penultimate_id:
				is_arrival_gate = true

	# Route gate highlight: pulsing gold ring (departure)
	if is_route_gate:
		var route_pulse: float = sin(_pulse_t * 3.0) * 0.3 + 0.7
		var route_col =Color(1.0, 0.8, 0.0, route_pulse * 0.6)
		draw_arc(pos, s + 6.0 + route_pulse * 3.0, 0, TAU, 24, route_col, 2.5, true)
		draw_arc(pos, s + 2.0, 0, TAU, 20, Color(1.0, 0.8, 0.0, 0.3), 1.5, true)

	# Arrival gate highlight: pulsing cyan ring (preview destination)
	if is_arrival_gate:
		var route_pulse: float = sin(_pulse_t * 3.0) * 0.3 + 0.7
		var route_col =Color(0.0, 0.9, 1.0, route_pulse * 0.6)
		draw_arc(pos, s + 6.0 + route_pulse * 3.0, 0, TAU, 24, route_col, 2.5, true)
		draw_arc(pos, s + 2.0, 0, TAU, 20, Color(0.0, 0.9, 1.0, 0.3), 1.5, true)

	# Outer ring
	draw_arc(pos, s, 0, TAU, 16, col, 2.0, true)

	# Inner glow
	var pulse: float = sin(_pulse_t * 2.5) * 0.3 + 0.5
	draw_circle(pos, s * 0.4, Color(col.r, col.g, col.b, pulse * 0.3))

	# Label with target system name
	var target_name: String = ent.get("extra", {}).get("target_system_name", ent["name"])
	var name_text: String = target_name if target_name.length() < 30 else ent["name"]
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var label_col =Color(1.0, 0.8, 0.0, 0.9) if is_route_gate else (Color(0.0, 0.9, 1.0, 0.9) if is_arrival_gate else Color(col.r, col.g, col.b, 0.7))
	draw_string(font, pos + Vector2(-tw * 0.5, s + 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)

	# Route label (departure or arrival)
	if is_route_gate:
		var route_label ="PROCHAIN SAUT"
		var rtw: float = font.get_string_size(route_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, pos + Vector2(-rtw * 0.5, -s - 8), route_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.0, 0.8))
	elif is_arrival_gate:
		var arrival_label ="ARRIVÉE"
		var atw: float = font.get_string_size(arrival_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, pos + Vector2(-atw * 0.5, -s - 8), arrival_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.0, 0.9, 1.0, 0.8))


# =============================================================================
# PLAYER (triangle pointing in heading direction)
# =============================================================================
func _draw_player(pos: Vector2, ent: Dictionary, _is_selected: bool, font: Font) -> void:
	var col: Color = ent.get("color", MapColors.PLAYER)
	var is_local: bool = ent["id"] == _player_id

	# Get heading from velocity or default to up
	var heading_angle: float = -PI / 2.0  # default: pointing up
	var vel_x: float = ent["vel_x"]
	var vel_z: float = ent["vel_z"]
	var speed: float = sqrt(vel_x * vel_x + vel_z * vel_z)
	if speed > 1.0:
		heading_angle = atan2(vel_z, vel_x)

	# Triangle
	var s: float = 8.0 if is_local else 6.0
	var p1: Vector2 = pos + Vector2(cos(heading_angle), sin(heading_angle)) * s * 1.5
	var p2: Vector2 = pos + Vector2(cos(heading_angle + 2.4), sin(heading_angle + 2.4)) * s
	var p3: Vector2 = pos + Vector2(cos(heading_angle - 2.4), sin(heading_angle - 2.4)) * s
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)

	# Pulsing ring (local player only)
	if is_local:
		var pulse: float = sin(_pulse_t * 2.0) * 0.3 + 0.7
		var ring_col =Color(col.r, col.g, col.b, pulse * 0.4)
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
	var tw: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, pos + Vector2(-tw * 0.5, 20), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


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
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, pos + Vector2(-tw * 0.5, s + 12), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


# =============================================================================
# FLEET SHIP (blue diamond, distinct from NPC triangles)
# =============================================================================
func _draw_fleet_ship(pos: Vector2, ent: Dictionary, is_selected: bool, font: Font) -> void:
	var col: Color = MapColors.FLEET_SHIP
	var s: float = 6.0

	# Pulsing glow
	var pulse: float = sin(_pulse_t * 2.0) * 0.15 + 0.85
	draw_circle(pos, s * 2.5, Color(col.r, col.g, col.b, 0.06 * pulse))

	# Diamond shape
	var points =PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s * 0.8, 0),
		pos + Vector2(0, s),
		pos + Vector2(-s * 0.8, 0),
	])
	draw_colored_polygon(points, Color(col.r, col.g, col.b, 0.8 * pulse))

	# Inner bright center
	var inner_s: float = s * 0.35
	var inner_points =PackedVector2Array([
		pos + Vector2(0, -inner_s),
		pos + Vector2(inner_s, 0),
		pos + Vector2(0, inner_s),
		pos + Vector2(-inner_s, 0),
	])
	draw_colored_polygon(inner_points, Color(0.8, 0.9, 1.0, 0.4))

	# Border
	var border_points =PackedVector2Array([
		pos + Vector2(0, -s - 1),
		pos + Vector2(s * 0.8 + 1, 0),
		pos + Vector2(0, s + 1),
		pos + Vector2(-s * 0.8 - 1, 0),
		pos + Vector2(0, -s - 1),
	])
	draw_polyline(border_points, Color(col.r, col.g, col.b, 0.6), 1.0)

	# Label
	var show_label: bool = is_selected or camera.zoom > 0.003
	if show_label:
		var label_text: String = ent["name"]
		var extra: Dictionary = ent.get("extra", {})
		var cmd_name: String = extra.get("command", "")
		var status_tag: String = ""
		match cmd_name:
			"move_to":
				var arrived: bool = extra.get("arrived", false)
				status_tag = "[EN POSITION]" if arrived else "[EN ROUTE]"
			"patrol":
				status_tag = "[PATROUILLE]"
			"attack":
				status_tag = "[ATTAQUE]"
			"return_to_station":
				status_tag = "[RAPPEL]"
			"construction":
				var arrived: bool = extra.get("arrived", false)
				status_tag = "[CONSTRUCTION]" if arrived else "[LIVRAISON]"
			"mine":
				var mining_state: String = extra.get("mining_state", "")
				if mining_state == "returning":
					status_tag = "[VENTE]"
				elif mining_state == "docked":
					status_tag = "[DOCKE]"
				elif mining_state == "departing":
					status_tag = "[RETOUR MINE]"
				else:
					status_tag = "[MINAGE]"
		if status_tag != "":
			label_text += " " + status_tag
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, pos + Vector2(-tw * 0.5, s + 14), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


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
	var tw: float = font.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	# Background behind text
	draw_rect(Rect2(mid.x - tw * 0.5 - 4, mid.y - 12, tw + 8, 16), MapColors.BG, true)
	draw_string(font, Vector2(mid.x - tw * 0.5, mid.y), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.SELECTION_LINE * Color(1, 1, 1, 2.5))


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
		draw_string(font, label_pos, dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


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
	var line1_w: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var line2_w: float = font.get_string_size(type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

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
		line3_w = font.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

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
	draw_string(font, Vector2(tx, ty), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MapColors.TEXT)
	ty += 14.0
	draw_string(font, Vector2(tx, ty), type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.TEXT_DIM)
	if dist_text != "":
		ty += 14.0
		draw_string(font, Vector2(tx, ty), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.LABEL_VALUE)


func _type_label(type: int) -> String:
	match type:
		EntityRegistrySystem.EntityType.STAR: return "Étoile"
		EntityRegistrySystem.EntityType.PLANET: return "Planète"
		EntityRegistrySystem.EntityType.STATION: return "Station"
		EntityRegistrySystem.EntityType.SHIP_PLAYER: return "Vaisseau joueur"
		EntityRegistrySystem.EntityType.SHIP_NPC: return "Vaisseau PNJ"
		EntityRegistrySystem.EntityType.SHIP_FLEET: return "Vaisseau flotte"
		EntityRegistrySystem.EntityType.ASTEROID_BELT: return "Ceinture"
		EntityRegistrySystem.EntityType.JUMP_GATE: return "Portail"
		EntityRegistrySystem.EntityType.CONSTRUCTION_SITE: return "Site de construction"
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
		if ent.get("extra", {}).get("hidden", false):
			continue
		var sp: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])
		var d: float = screen_pos.distance_to(sp)
		if d < best_dist:
			best_dist = d
			best_id = ent["id"]
	return best_id


func get_entities_in_rect(screen_rect: Rect2) -> Array[String]:
	var result: Array[String] = []
	if camera == null:
		return result
	var entities: Dictionary = _get_entities()
	for ent in entities.values():
		if ent["type"] == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue
		if filters.get(ent["type"], false):
			continue
		if ent.get("extra", {}).get("hidden", false):
			continue
		var sp: Vector2 = camera.universe_to_screen(ent["pos_x"], ent["pos_z"])
		if screen_rect.has_point(sp):
			result.append(ent["id"])
	return result


func get_construction_marker_at(screen_pos: Vector2) -> Dictionary:
	if camera == null or construction_markers.is_empty():
		return {}
	var best_marker: Dictionary = {}
	var best_dist: float = HIT_RADIUS
	for marker in construction_markers:
		var sp: Vector2 = camera.universe_to_screen(marker["pos_x"], marker["pos_z"])
		var d: float = screen_pos.distance_to(sp)
		if d < best_dist:
			best_dist = d
			best_marker = marker
	return best_marker


func update_hover(screen_pos: Vector2) -> bool:
	var new_id =get_entity_at(screen_pos)
	if new_id == _hover_id:
		return false
	_hover_id = new_id
	return true


# =============================================================================
# TRAILS
# =============================================================================
func _draw_trails(entities: Dictionary) -> void:
	if trails == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for id in trails._trails:
		var arr: PackedFloat64Array = trails._trails[id]
		if arr.size() < 6:
			continue
		# Determine trail color from entity type
		var trail_col: Color = MapColors.NPC_SHIP
		if entities.has(id):
			var ent: Dictionary = entities[id]
			if ent["type"] == EntityRegistrySystem.EntityType.SHIP_PLAYER:
				trail_col = MapColors.PLAYER
			elif ent["type"] == EntityRegistrySystem.EntityType.SHIP_FLEET:
				trail_col = MapColors.FLEET_SHIP
			else:
				trail_col = ent.get("color", MapColors.NPC_SHIP)

		var point_count: int = int(arr.size() / 3.0)
		for i in range(point_count - 1):
			var x1: float = arr[i * 3]
			var z1: float = arr[i * 3 + 1]
			var t1: float = arr[i * 3 + 2]
			var x2: float = arr[(i + 1) * 3]
			var z2: float = arr[(i + 1) * 3 + 1]

			var p1: Vector2 = camera.universe_to_screen(x1, z1)
			var p2: Vector2 = camera.universe_to_screen(x2, z2)

			# Skip if both points off screen
			if (p1.x < -50 and p2.x < -50) or (p1.x > size.x + 50 and p2.x > size.x + 50):
				continue
			if (p1.y < -50 and p2.y < -50) or (p1.y > size.y + 50 and p2.y > size.y + 50):
				continue

			var age: float = now - t1
			var alpha: float = clampf(1.0 - age / MapTrails.MAX_TRAIL_TIME, 0.05, 0.45)
			draw_line(p1, p2, Color(trail_col.r, trail_col.g, trail_col.b, alpha), 1.0)


# =============================================================================
# GALAXY AUTOPILOT ROUTE LINE (player → next gate on system map)
# =============================================================================
func _draw_galaxy_route_line(entities: Dictionary) -> void:
	if camera == null or _player_id == "" or preview_system_id >= 0:
		return
	var rm = GameManager._route_manager if GameManager else null
	if rm == null or not rm.is_route_active() or rm.next_gate_entity_id == "":
		return

	# Get player screen position
	var player_ent: Dictionary = entities.get(_player_id, {})
	if player_ent.is_empty():
		player_ent = EntityRegistry.get_entity(_player_id)
	if player_ent.is_empty():
		return
	var from_sp =camera.universe_to_screen(player_ent["pos_x"], player_ent["pos_z"])

	# Get gate screen position
	var gate_ent: Dictionary = entities.get(rm.next_gate_entity_id, {})
	if gate_ent.is_empty():
		gate_ent = EntityRegistry.get_entity(rm.next_gate_entity_id)
	if gate_ent.is_empty():
		return
	var to_sp =camera.universe_to_screen(gate_ent["pos_x"], gate_ent["pos_z"])

	# Dashed cyan line
	var pulse: float = sin(_pulse_t * 2.0) * 0.15 + 0.85
	var col =Color(0.0, 0.9, 1.0, 0.4 * pulse)
	_draw_dashed_line(from_sp, to_sp, col, 2.0, 10.0, 6.0)

	# Destination label near the gate
	var font: Font = UITheme.get_font()
	var dest_name: String = rm.target_system_name
	if dest_name.length() > 20:
		dest_name = dest_name.substr(0, 18) + ".."
	var label ="→ " + dest_name
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var label_pos =to_sp + Vector2(-tw * 0.5, -22)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.9, 1.0, 0.6 * pulse))


# =============================================================================
# PREVIEW ROUTE LINE (arrival gate → final destination in previewed system)
# =============================================================================
func _draw_preview_route_line(entities: Dictionary) -> void:
	if camera == null or preview_system_id < 0:
		return
	var rm = GameManager._route_manager if GameManager else null
	if rm == null or not rm.is_route_active() or rm.target_system_id != preview_system_id:
		return
	if rm.route.size() < 2:
		return

	# Find arrival gate (gate connecting back to penultimate system)
	var penultimate_id: int = rm.route[rm.route.size() - 2]
	var arrival_gate_ent: Dictionary = {}
	for ent in entities.values():
		if ent["type"] == EntityRegistrySystem.EntityType.JUMP_GATE:
			if ent.get("extra", {}).get("target_system_id", -1) == penultimate_id:
				arrival_gate_ent = ent
				break
	if arrival_gate_ent.is_empty():
		return

	# Determine destination point: explicit final_dest or nearest station fallback
	var dest_x: float = 0.0
	var dest_z: float = 0.0
	var dest_name: String = ""
	if rm.has_final_dest:
		dest_x = rm.final_dest_x
		dest_z = rm.final_dest_z
		dest_name = rm.final_dest_name
	else:
		# Fallback: find nearest station to arrival gate
		var best_dist_sq: float = INF
		for ent in entities.values():
			if ent["type"] != EntityRegistrySystem.EntityType.STATION:
				continue
			var dx: float = ent["pos_x"] - arrival_gate_ent["pos_x"]
			var dz: float = ent["pos_z"] - arrival_gate_ent["pos_z"]
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				dest_x = ent["pos_x"]
				dest_z = ent["pos_z"]
				dest_name = ent["name"]
		if best_dist_sq == INF:
			return  # No station found — arrival gate highlight alone is sufficient

	var from_sp: Vector2 = camera.universe_to_screen(arrival_gate_ent["pos_x"], arrival_gate_ent["pos_z"])
	var to_sp: Vector2 = camera.universe_to_screen(dest_x, dest_z)

	# Dashed cyan line
	var pulse: float = sin(_pulse_t * 2.0) * 0.15 + 0.85
	var col: Color = Color(0.0, 0.9, 1.0, 0.4 * pulse)
	_draw_dashed_line(from_sp, to_sp, col, 2.0, 10.0, 6.0)

	# Destination label
	if dest_name != "":
		var font: Font = UITheme.get_font()
		var label_name: String = dest_name
		if label_name.length() > 20:
			label_name = label_name.substr(0, 18) + ".."
		var label: String = "→ " + label_name
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var label_pos: Vector2 = to_sp + Vector2(-tw * 0.5, -22)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.9, 1.0, 0.6 * pulse))

	# Destination marker (small pulsing diamond)
	var ds: float = 5.0
	var marker_col: Color = Color(0.0, 0.9, 1.0, 0.6 * pulse)
	var diamond: PackedVector2Array = PackedVector2Array([
		to_sp + Vector2(0, -ds), to_sp + Vector2(ds, 0),
		to_sp + Vector2(0, ds), to_sp + Vector2(-ds, 0),
	])
	var colors: PackedColorArray = PackedColorArray([marker_col, marker_col, marker_col, marker_col])
	draw_primitive(diamond, colors, PackedVector2Array())


func _draw_autopilot_line(entities: Dictionary) -> void:
	if camera == null or _player_id == "":
		return
	# Only draw when ship has autopilot active and no galaxy route is active
	var ship = GameManager.player_ship
	if ship == null or not ship.autopilot_active:
		return
	var rm = GameManager._route_manager if GameManager else null
	if rm != null and rm.is_route_active():
		return  # Galaxy route line handles this case
	# Get autopilot target entity
	var target_id: String = ship.autopilot_target_id
	if target_id == "":
		return
	var target_ent: Dictionary = entities.get(target_id, {})
	if target_ent.is_empty():
		target_ent = EntityRegistry.get_entity(target_id)
	if target_ent.is_empty():
		return
	# Get player screen position
	var player_ent: Dictionary = entities.get(_player_id, {})
	if player_ent.is_empty():
		player_ent = EntityRegistry.get_entity(_player_id)
	if player_ent.is_empty():
		return
	var from_sp: Vector2 = camera.universe_to_screen(player_ent["pos_x"], player_ent["pos_z"])
	var to_sp: Vector2 = camera.universe_to_screen(target_ent["pos_x"], target_ent["pos_z"])
	# Gold dashed line
	var pulse: float = sin(_pulse_t * 2.0) * 0.15 + 0.85
	var col: Color = Color(1.0, 0.8, 0.0, 0.4 * pulse)
	_draw_dashed_line(from_sp, to_sp, col, 2.0, 10.0, 6.0)
	# Destination label
	var dest_name: String = ship.autopilot_target_name
	if dest_name.length() > 20:
		dest_name = dest_name.substr(0, 18) + ".."
	if dest_name != "" and dest_name != "Destination":
		var font: Font = UITheme.get_font()
		var label: String = "→ " + dest_name
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var label_pos: Vector2 = to_sp + Vector2(-tw * 0.5, -22)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.0, 0.6 * pulse))


# =============================================================================
# FLEET ROUTE LINE + WAYPOINT + HINT (overlay drawn on top of entities)
# =============================================================================
func _draw_route_line(entities: Dictionary) -> void:
	if route_ship_ids.is_empty() or camera == null:
		return
	# Track moving target if attack order
	var default_dest_ux: float = route_dest_ux
	var default_dest_uz: float = route_dest_uz
	if route_target_entity_id != "":
		var target_ent =EntityRegistry.get_entity(route_target_entity_id)
		if not target_ent.is_empty():
			default_dest_ux = target_ent["pos_x"]
			default_dest_uz = target_ent["pos_z"]
		else:
			# Target dead — clear route
			route_ship_ids.clear()
			route_target_entity_id = ""
			return
	var is_tracking: bool = route_target_entity_id != ""
	var base_col: Color
	if route_is_follow:
		base_col = Color(0.2, 0.8, 1.0)  # Cyan for follow
	elif is_tracking:
		base_col = Color(1.0, 0.2, 0.15)  # Red for attack
	else:
		base_col = UITheme.PRIMARY
	var col =Color(base_col.r, base_col.g, base_col.b, 0.5)
	var last_dest_sp =camera.universe_to_screen(default_dest_ux, default_dest_uz)
	for ship_id in route_ship_ids:
		var from_sp: Vector2
		var ship_ent: Dictionary = {}
		# Check virtual positions first (MP client fallback for ships without local entity)
		if route_virtual_positions.has(ship_id):
			var vpos: Array = route_virtual_positions[ship_id]
			from_sp = camera.universe_to_screen(vpos[0], vpos[1])
			# Use empty ship_ent — no mining state overrides for virtual ships
		else:
			if entities.has(ship_id):
				ship_ent = entities[ship_id]
			else:
				ship_ent = EntityRegistry.get_entity(ship_id)
			if ship_ent.is_empty():
				continue
			from_sp = camera.universe_to_screen(ship_ent["pos_x"], ship_ent["pos_z"])
		# Per-ship destination override (mining autonomous travel)
		var ship_dux =default_dest_ux
		var ship_duz =default_dest_uz
		var extra: Dictionary = ship_ent.get("extra", {})
		var ms: String = extra.get("mining_state", "")
		if ms == "docked":
			continue  # No route line while docked at station
		if ms != "":
			ship_dux = extra.get("active_dest_ux", default_dest_ux)
			ship_duz = extra.get("active_dest_uz", default_dest_uz)
		var to_sp =camera.universe_to_screen(ship_dux, ship_duz)
		_draw_dashed_line(from_sp, to_sp, col, 1.5, 8.0, 6.0)
		last_dest_sp = to_sp
	# Destination marker (small diamond)
	var ds: float = 5.0
	var marker_col =Color(base_col.r, base_col.g, base_col.b, 0.6)
	var diamond =PackedVector2Array([
		last_dest_sp + Vector2(0, -ds), last_dest_sp + Vector2(ds, 0),
		last_dest_sp + Vector2(0, ds), last_dest_sp + Vector2(-ds, 0),
	])
	var colors =PackedColorArray([marker_col, marker_col, marker_col, marker_col])
	draw_primitive(diamond, colors, PackedVector2Array())


func _draw_waypoint_flash() -> void:
	if waypoint_timer <= 0.0 or camera == null:
		return
	var sp =camera.universe_to_screen(waypoint_ux, waypoint_uz)
	var wf_alpha: float = waypoint_timer / WAYPOINT_DURATION
	var wf_pulse: float = sin(Time.get_ticks_msec() / 200.0) * 0.3 + 0.7
	var wf_radius: float = 8.0 + (1.0 - wf_alpha) * 20.0
	var wf_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, wf_alpha * wf_pulse * 0.6)
	draw_arc(sp, wf_radius, 0, TAU, 24, wf_col, 2.0, true)
	draw_circle(sp, 3.0, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, wf_alpha * 0.8))


func _draw_hint_text(font: Font) -> void:
	var hint ="Clic droit = Deplacer | Maintenir = Ordres/Construction"
	var hint_y: float = size.y - 60.0
	var hint_x: float = size.x * 0.5
	var tw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
	draw_rect(Rect2(hint_x - tw * 0.5 - 8, hint_y - 14, tw + 16, 20), Color(0.0, 0.02, 0.05, 0.8))
	var h_pulse: float = sin(Time.get_ticks_msec() / 400.0) * 0.15 + 0.85
	draw_string(font, Vector2(hint_x - tw * 0.5, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, h_pulse))


# =============================================================================
# CONSTRUCTION MARKERS (cyan pulsing blueprint markers)
# =============================================================================
func _draw_construction_markers() -> void:
	if construction_markers.is_empty() or camera == null:
		return
	var font: Font = UITheme.get_font()
	var col =MapColors.CONSTRUCTION_STATION
	var ghost_col =MapColors.CONSTRUCTION_GHOST

	for marker in construction_markers:
		var sp: Vector2 = camera.universe_to_screen(marker["pos_x"], marker["pos_z"])

		# Cull off-screen
		if sp.x < -60 or sp.x > size.x + 60 or sp.y < -60 or sp.y > size.y + 60:
			continue

		var age: float = Time.get_ticks_msec() / 1000.0 - marker["timestamp"]
		var pulse: float = sin(age * 2.5) * 0.25 + 0.75

		# Outer ghost ring (pulsing)
		var ring_r: float = 22.0 + pulse * 4.0
		draw_arc(sp, ring_r, 0, TAU, 32, Color(ghost_col.r, ghost_col.g, ghost_col.b, ghost_col.a * pulse), 1.5, true)

		# Dashed circle (blueprint style) — draw segments
		var dash_count: int = 16
		for d in dash_count:
			var a0: float = TAU * float(d) / float(dash_count)
			var a1: float = TAU * float(d + 0.5) / float(dash_count)
			draw_arc(sp, 14.0, a0, a1, 4, Color(col.r, col.g, col.b, 0.6 * pulse), 1.5, true)

		# Center cross (X marker)
		var cs: float = 5.0
		draw_line(sp + Vector2(-cs, -cs), sp + Vector2(cs, cs), Color(col.r, col.g, col.b, 0.8), 2.0)
		draw_line(sp + Vector2(cs, -cs), sp + Vector2(-cs, cs), Color(col.r, col.g, col.b, 0.8), 2.0)

		# Center dot
		draw_circle(sp, 2.5, col)

		# Label: display name
		var label_text: String = marker["display_name"]
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, sp + Vector2(-tw * 0.5, 30), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

		# Tag: [CONSTRUCTION]
		var tag ="[CONSTRUCTION]"
		var tag_w: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, sp + Vector2(-tag_w * 0.5, 43), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.r, col.g, col.b, 0.6))


func _draw_dashed_line(from: Vector2, to: Vector2, col: Color, width: float, dash_len: float, gap_len: float) -> void:
	var dir =(to - from)
	var total_len: float = dir.length()
	if total_len < 1.0:
		return
	var unit =dir / total_len
	var pos: float = 0.0
	while pos < total_len:
		var seg_end: float = minf(pos + dash_len, total_len)
		draw_line(from + unit * pos, from + unit * seg_end, col, width)
		pos = seg_end + gap_len
