class_name HudRadar
extends Control

# =============================================================================
# HUD Radar — Holographic tactical scanning display (top-right)
# =============================================================================

var ship = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

const RADAR_RANGE: float = 5000.0
const RADAR_SWEEP_SPEED: float = 1.2
const RADAR_COL_BG: Color = Color(0.0, 0.03, 0.06, 0.7)
const RADAR_COL_RING: Color = Color(0.1, 0.4, 0.5, 0.25)
const RADAR_COL_SWEEP: Color = Color(0.15, 0.85, 0.75, 0.6)
const RADAR_COL_EDGE: Color = Color(0.1, 0.5, 0.6, 0.5)

const NAV_COL_STATION: Color = Color(0.2, 0.85, 0.8, 0.85)
const NAV_COL_STAR: Color = Color(1.0, 0.85, 0.4, 0.75)
const NAV_COL_GATE: Color = Color(0.15, 0.6, 1.0, 0.85)
const NAV_COL_BELT: Color = Color(0.7, 0.55, 0.35, 0.7)
const NAV_COL_CONSTRUCTION: Color = Color(0.2, 0.8, 1.0, 0.85)
const NAV_COL_GROUP: Color = Color(0.3, 1.0, 0.6, 0.9)

var _radar: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_radar = HudDrawHelpers.make_ctrl(1.0, 0.0, 1.0, 0.0, -210, 8, -16, 210)
	_radar.draw.connect(_draw_radar.bind(_radar))
	add_child(_radar)


func redraw() -> void:
	_radar.queue_redraw()


func _get_faction_nav_color(faction: StringName) -> Color:
	if faction == &"hostile":
		return Color(1.0, 0.3, 0.2, 0.85)
	elif faction == &"friendly":
		return Color(0.3, 0.9, 0.4, 0.85)
	elif faction == &"player_fleet":
		return Color(0.4, 0.65, 1.0, 0.9)
	return Color(0.6, 0.4, 0.9, 0.85)


func _get_npc_nav_color(node: Node) -> Color:
	var faction = node.get("faction")
	if faction == &"hostile":
		return Color(1.0, 0.3, 0.2, 0.85)
	elif faction == &"friendly":
		return Color(0.3, 0.9, 0.4, 0.85)
	elif faction == &"player_fleet":
		return Color(0.4, 0.65, 1.0, 0.9)
	return Color(0.6, 0.4, 0.9, 0.85)


func _draw_radar(ctrl: Control) -> void:
	if ship == null:
		return
	var cam =get_viewport().get_camera_3d()
	if cam == null:
		return
	var font =UITheme.get_font_medium()
	var s =ctrl.size
	var center =Vector2(s.x * 0.5, s.y * 0.5 + 10)
	var radar_r: float = minf(s.x, s.y) * 0.5 - 20.0
	var ship_basis =ship.global_transform.basis
	var scale_factor: float = radar_r / RADAR_RANGE

	# Background
	ctrl.draw_circle(center, radar_r + 2, RADAR_COL_BG)

	# Range rings
	for ring_t in [0.333, 0.666]:
		ctrl.draw_arc(center, radar_r * ring_t, 0, TAU, 16, RADAR_COL_RING, 1.0, true)

	# Cross lines
	ctrl.draw_line(center + Vector2(0, -radar_r), center + Vector2(0, radar_r), RADAR_COL_RING, 1.0)
	ctrl.draw_line(center + Vector2(-radar_r, 0), center + Vector2(radar_r, 0), RADAR_COL_RING, 1.0)

	# Edge circle + ticks
	ctrl.draw_arc(center, radar_r, 0, TAU, 32, RADAR_COL_EDGE, 1.5, true)
	for i in 12:
		var angle =float(i) * TAU / 12.0 - PI * 0.5
		var inner =center + Vector2(cos(angle), sin(angle)) * (radar_r - 4)
		var outer =center + Vector2(cos(angle), sin(angle)) * radar_r
		ctrl.draw_line(inner, outer, RADAR_COL_EDGE, 1.0)

	# Sonar ping
	var ping_t =fmod(pulse_t * 0.3, 1.0)
	var ping_r =ping_t * radar_r
	var ping_alpha =(1.0 - ping_t) * 0.12
	ctrl.draw_arc(center, ping_r, 0, TAU, 16, Color(RADAR_COL_SWEEP.r, RADAR_COL_SWEEP.g, RADAR_COL_SWEEP.b, ping_alpha), 1.0, true)

	# Sweep line with trail
	var sweep_angle =fmod(pulse_t * RADAR_SWEEP_SPEED, TAU) - PI * 0.5
	for i in 10:
		var ta =sweep_angle - float(i) * 0.08
		var alpha =(1.0 - float(i) / 10.0) * 0.2
		ctrl.draw_line(center, center + Vector2(cos(ta), sin(ta)) * radar_r,
			Color(RADAR_COL_SWEEP.r, RADAR_COL_SWEEP.g, RADAR_COL_SWEEP.b, alpha), 1.0)
	ctrl.draw_line(center, center + Vector2(cos(sweep_angle), sin(sweep_angle)) * radar_r, RADAR_COL_SWEEP, 2.0)

	# Entity blips: Stations + Jump Gates + Star
	for ent in EntityRegistry.get_all().values():
		var etype: int = ent["type"]
		if etype == EntityRegistrySystem.EntityType.STATION:
			var snode = ent.get("node")
			if snode != null and is_instance_valid(snode):
				var rel =(snode as Node3D).global_position - ship.global_position
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, NAV_COL_STATION, 4.0, true)
		elif etype == EntityRegistrySystem.EntityType.JUMP_GATE:
			var gnode = ent.get("node")
			if gnode != null and is_instance_valid(gnode):
				var rel =(gnode as Node3D).global_position - ship.global_position
				if rel.length() > RADAR_RANGE:
					var lx: float = rel.dot(ship_basis.x)
					var lz: float = rel.dot(ship_basis.z)
					if Vector2(lx, lz).length() > 0.01:
						var dir =Vector2(lx, lz).normalized()
						HudDrawHelpers.draw_diamond(ctrl, center + dir * (radar_r - 6), 3.0, NAV_COL_GATE)
				else:
					_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, NAV_COL_GATE, 4.0, true)
		elif etype == EntityRegistrySystem.EntityType.STAR:
			var star_local =Vector3(
				-FloatingOrigin.origin_offset_x,
				-FloatingOrigin.origin_offset_y,
				-FloatingOrigin.origin_offset_z
			) - ship.global_position
			if star_local.length() > 0.01:
				var lx: float = star_local.dot(ship_basis.x)
				var lz: float = star_local.dot(ship_basis.z)
				var dir =Vector2(lx, lz).normalized()
				HudDrawHelpers.draw_diamond(ctrl, center + dir * (radar_r - 6), 3.0, NAV_COL_STAR)
		elif etype == EntityRegistrySystem.EntityType.CONSTRUCTION_SITE:
			var cnode = ent.get("node")
			if cnode != null and is_instance_valid(cnode):
				var rel =(cnode as Node3D).global_position - ship.global_position
				if rel.length() > RADAR_RANGE:
					var lx: float = rel.dot(ship_basis.x)
					var lz: float = rel.dot(ship_basis.z)
					if Vector2(lx, lz).length() > 0.01:
						var dir =Vector2(lx, lz).normalized()
						HudDrawHelpers.draw_diamond(ctrl, center + dir * (radar_r - 6), 3.0, NAV_COL_CONSTRUCTION)
				else:
					_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, NAV_COL_CONSTRUCTION, 4.0, true)

	# NPC ship blips
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var all_ids = lod_mgr.get_ships_in_radius(ship.global_position, RADAR_RANGE * 2.0)
		for npc_id in all_ids:
			if npc_id == &"player_ship":
				continue
			var data = lod_mgr.get_ship_data(npc_id)
			if data == null or data.is_dead:
				continue
			var rel: Vector3 = data.position - ship.global_position
			var col: Color
			if data.peer_id > 0 and NetworkManager.is_peer_in_my_group(data.peer_id):
				col = NAV_COL_GROUP
			else:
				col = _get_faction_nav_color(data.faction)
			if rel.length() > RADAR_RANGE:
				var lx: float = rel.dot(ship_basis.x)
				var lz: float = rel.dot(ship_basis.z)
				if Vector2(lx, lz).length() > 0.01:
					var dir =Vector2(lx, lz).normalized()
					ctrl.draw_circle(center + dir * (radar_r - 3), 2.0, Color(col.r, col.g, col.b, 0.4))
			else:
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, col, 3.0, false)
	else:
		for ship_node in get_tree().get_nodes_in_group("ships"):
			if ship_node == ship or not is_instance_valid(ship_node) or not ship_node is Node3D:
				continue
			var rel: Vector3 = (ship_node as Node3D).global_position - ship.global_position
			var col: Color
			if ship_node is RemotePlayerShip and NetworkManager.is_peer_in_my_group(ship_node.peer_id):
				col = NAV_COL_GROUP
			else:
				col = _get_npc_nav_color(ship_node)
			if rel.length() > RADAR_RANGE:
				var lx: float = rel.dot(ship_basis.x)
				var lz: float = rel.dot(ship_basis.z)
				if Vector2(lx, lz).length() > 0.01:
					var dir =Vector2(lx, lz).normalized()
					ctrl.draw_circle(center + dir * (radar_r - 3), 2.0, Color(col.r, col.g, col.b, 0.4))
			else:
				_draw_radar_blip(ctrl, center, radar_r, scale_factor, ship_basis, rel, col, 3.0, false)

	# Nearby asteroid blips (scanned = resource color, unscanned = neutral tan)
	var asteroid_mgr = GameManager.get_node_or_null("AsteroidFieldManager")
	if asteroid_mgr:
		var nearby_asteroids =asteroid_mgr.get_asteroids_in_radius(ship.global_position, RADAR_RANGE)
		var unscanned_col =Color(NAV_COL_BELT.r, NAV_COL_BELT.g, NAV_COL_BELT.b, 0.35)
		for ast_data in nearby_asteroids:
			var rel: Vector3 = ast_data.position - ship.global_position
			var lx: float = rel.dot(ship_basis.x)
			var lz: float = rel.dot(ship_basis.z)
			var radar_pos =Vector2(lx, lz) * scale_factor
			if radar_pos.length() > radar_r - 4:
				radar_pos = radar_pos.normalized() * (radar_r - 4)
			var blip_col: Color = unscanned_col
			if ast_data.is_scanned and ast_data.has_resource:
				blip_col = Color(ast_data.resource_color.r, ast_data.resource_color.g, ast_data.resource_color.b, 0.7)
			ctrl.draw_circle(center + radar_pos, 1.5, blip_col)

	# Scanner pulse rings on radar
	var scanner = GameManager.get_node_or_null("AsteroidScanner")
	if scanner:
		var pulses =scanner.get_active_pulses_info()
		var scan_col =Color(0.0, 0.85, 0.95, 0.6)
		for pinfo in pulses:
			var pulse_pos: Vector3 = pinfo["position"]
			var pulse_r: float = pinfo["radius"]
			# Pulse center relative to ship
			var rel: Vector3 = pulse_pos - ship.global_position
			var lx: float = rel.dot(ship_basis.x)
			var lz: float = rel.dot(ship_basis.z)
			var radar_center =center + Vector2(lx, lz) * scale_factor
			# Radius in radar pixels
			var radar_pulse_r: float = pulse_r * scale_factor
			if radar_pulse_r > 1.0:
				var ring_alpha: float = 0.6 * (1.0 - clampf(pulse_r / 5000.0, 0.0, 1.0) * 0.5)
				var col =Color(scan_col.r, scan_col.g, scan_col.b, ring_alpha)
				ctrl.draw_arc(radar_center, minf(radar_pulse_r, radar_r), 0.0, TAU, 64, col, 1.5, true)

	# Player icon
	var tri_sz =5.0
	ctrl.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -tri_sz),
		center + Vector2(tri_sz * 0.6, tri_sz * 0.4),
		center + Vector2(-tri_sz * 0.6, tri_sz * 0.4),
	]), UITheme.PRIMARY)

	# Header
	ctrl.draw_string(font, Vector2(0, 14), "RADAR", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), UITheme.FONT_SIZE_LABEL, UITheme.HEADER)

	# Belt status
	if asteroid_mgr:
		var uni_x: float = ship.global_position.x + FloatingOrigin.origin_offset_x
		var uni_z: float = ship.global_position.z + FloatingOrigin.origin_offset_z
		var belt_name: String = asteroid_mgr.get_belt_at_position(uni_x, uni_z)
		if belt_name != "":
			ctrl.draw_string(font, Vector2(0, s.y - 16), belt_name, HORIZONTAL_ALIGNMENT_CENTER, int(s.x), UITheme.FONT_SIZE_SMALL, NAV_COL_BELT)

	# Range label
	ctrl.draw_string(font, Vector2(0, s.y - 4), HudDrawHelpers.format_nav_distance(RADAR_RANGE), HORIZONTAL_ALIGNMENT_CENTER, int(s.x), UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Scanline
	var sly: float = fmod(scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), UITheme.SCANLINE, 1.0)


func _draw_radar_blip(ctrl: Control, center: Vector2, radar_r: float, scale_factor: float, ship_basis: Basis, rel: Vector3, col: Color, sz: float, is_station: bool) -> void:
	var local_x: float = rel.dot(ship_basis.x)
	var local_z: float = rel.dot(ship_basis.z)
	var radar_pos =Vector2(local_x, local_z) * scale_factor
	if radar_pos.length() > radar_r - 4:
		radar_pos = radar_pos.normalized() * (radar_r - 4)
	var pos =center + radar_pos
	ctrl.draw_circle(pos, sz + 2, Color(col.r, col.g, col.b, 0.15))
	if is_station:
		HudDrawHelpers.draw_diamond(ctrl, pos, sz, col)
	else:
		ctrl.draw_circle(pos, sz, col)
