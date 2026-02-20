class_name HudNavMarkers
extends Control

# =============================================================================
# HUD Nav Markers — BSGO-style POI indicators with distance
# =============================================================================

var ship = null

const NAV_EDGE_MARGIN: float = 40.0
const NAV_NPC_RANGE: float = 4000.0
const NAV_COL_STATION: Color = Color(0.2, 0.85, 0.8, 0.85)
const NAV_COL_STAR: Color = Color(1.0, 0.85, 0.4, 0.75)
const NAV_COL_GATE: Color = Color(0.15, 0.6, 1.0, 0.85)
const NAV_COL_BELT: Color = Color(0.7, 0.55, 0.35, 0.7)
const NAV_COL_HOSTILE: Color = Color(1.0, 0.3, 0.2, 0.85)
const NAV_COL_FRIENDLY: Color = Color(0.3, 0.9, 0.4, 0.85)
const NAV_COL_NEUTRAL_NPC: Color = Color(0.6, 0.4, 0.9, 0.85)
const NAV_COL_FLEET: Color = Color(0.4, 0.65, 1.0, 0.9)
const NAV_COL_CONSTRUCTION: Color = Color(0.2, 0.8, 1.0, 0.85)
const NAV_COL_PLANET: Color = Color(0.6, 0.8, 1.0, 0.75)

var _nav_markers: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_nav_markers = HudDrawHelpers.make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_nav_markers.draw.connect(_draw_nav_markers.bind(_nav_markers))
	add_child(_nav_markers)


func redraw() -> void:
	_nav_markers.queue_redraw()


func _draw_nav_markers(ctrl: Control) -> void:
	var cam =get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen_size =ctrl.size
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var cam_pos: Vector3 = cam.global_position
	var font =UITheme.get_font_medium()

	# Use ship position (not camera) for distance calculations
	var ship_pos: Vector3 = ship.global_position if ship else cam_pos
	var ship_upos: Array = FloatingOrigin.to_universe_pos(ship_pos)

	# Stations + Star + Jump Gates + Asteroid Belts
	for ent in EntityRegistry.get_all().values():
		var etype: int = ent["type"]
		if etype != EntityRegistrySystem.EntityType.STATION and etype != EntityRegistrySystem.EntityType.STAR and etype != EntityRegistrySystem.EntityType.JUMP_GATE and etype != EntityRegistrySystem.EntityType.ASTEROID_BELT and etype != EntityRegistrySystem.EntityType.CONSTRUCTION_SITE and etype != EntityRegistrySystem.EntityType.PLANET:
			continue
		var world_pos: Vector3
		var node_ref = ent.get("node")
		if node_ref != null and is_instance_valid(node_ref):
			world_pos = (node_ref as Node3D).global_position
		else:
			if etype == EntityRegistrySystem.EntityType.ASTEROID_BELT:
				var orbit_r: float = ent.get("orbital_radius", 0.0)
				if orbit_r <= 0.0:
					continue
				var angle_to_player: float = atan2(ship_upos[2], ship_upos[0])
				world_pos = FloatingOrigin.to_local_pos([
					cos(angle_to_player) * orbit_r,
					0.0,
					sin(angle_to_player) * orbit_r,
				])
			else:
				world_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		var dx: float = ent["pos_x"] - ship_upos[0]
		var dy: float = ent["pos_y"] - ship_upos[1]
		var dz: float = ent["pos_z"] - ship_upos[2]
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		if etype == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			var orbit_r: float = ent.get("orbital_radius", 0.0)
			var player_dist_from_center: float = sqrt(ship_upos[0] * ship_upos[0] + ship_upos[2] * ship_upos[2])
			dist = absf(player_dist_from_center - orbit_r)
		var marker_col: Color
		match etype:
			EntityRegistrySystem.EntityType.STATION: marker_col = NAV_COL_STATION
			EntityRegistrySystem.EntityType.JUMP_GATE: marker_col = NAV_COL_GATE
			EntityRegistrySystem.EntityType.ASTEROID_BELT: marker_col = NAV_COL_BELT
			EntityRegistrySystem.EntityType.CONSTRUCTION_SITE: marker_col = NAV_COL_CONSTRUCTION
			EntityRegistrySystem.EntityType.PLANET:
				# Use the planet's actual color (coherent with map + impostor)
				var pcol: Color = ent.get("color", NAV_COL_PLANET)
				marker_col = Color(lerpf(pcol.r, 1.0, 0.3), lerpf(pcol.g, 1.0, 0.3), lerpf(pcol.b, 1.0, 0.3), 0.85)
			_: marker_col = NAV_COL_STAR
		_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos, ent["name"], dist, marker_col)

	# NPC ships
	if ship:
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			var nearby = lod_mgr.get_ships_in_radius(cam_pos, NAV_NPC_RANGE)
			var npc_drawn: int = 0
			var _used_spots: Array[Vector2] = []
			for npc_id in nearby:
				if npc_id == &"player_ship":
					continue
				if npc_drawn >= 40:
					break
				var data = lod_mgr.get_ship_data(npc_id)
				if data == null or data.is_dead:
					continue
				var world_pos: Vector3 = data.position
				var dist: float = ship_pos.distance_to(world_pos)
				var to_ent =world_pos - cam_pos
				if to_ent.length() > 0.1:
					var dot_fwd: float = cam_fwd.dot(to_ent.normalized())
					if dot_fwd > 0.1:
						var sp =cam.unproject_position(world_pos)
						var too_close =false
						for used in _used_spots:
							if sp.distance_to(used) < 30.0:
								too_close = true
								break
						if too_close:
							continue
						_used_spots.append(sp)
				var nav_name =data.display_name if not data.display_name.is_empty() else String(data.ship_class)
				if data.faction == &"player_fleet":
					nav_name += " [FLOTTE]"
				var nav_col =_get_faction_nav_color(data.faction)
				_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos, nav_name, dist, nav_col)
				npc_drawn += 1
		else:
			for ship_node in get_tree().get_nodes_in_group("ships"):
				if ship_node == ship or not is_instance_valid(ship_node) or not ship_node is Node3D:
					continue
				var world_pos: Vector3 = (ship_node as Node3D).global_position
				var dist: float = ship_pos.distance_to(world_pos)
				if dist > NAV_NPC_RANGE:
					continue
				_draw_nav_entity(ctrl, font, cam, cam_fwd, cam_pos, screen_size, world_pos,
					_get_npc_name(ship_node), dist, _get_npc_nav_color(ship_node))


func _draw_nav_entity(ctrl: Control, font: Font, cam: Camera3D, cam_fwd: Vector3, cam_pos: Vector3, screen_size: Vector2, world_pos: Vector3, ent_name: String, dist: float, col: Color) -> void:
	var dist_str =HudDrawHelpers.format_nav_distance(dist)
	var to_ent: Vector3 = world_pos - cam_pos
	if to_ent.length() < 0.1:
		return
	var dot: float = cam_fwd.dot(to_ent.normalized())
	if dot > 0.1:
		var sp: Vector2 = cam.unproject_position(world_pos)
		if sp.x >= 0 and sp.x <= screen_size.x and sp.y >= 0 and sp.y <= screen_size.y:
			_draw_nav_onscreen(ctrl, font, sp, ent_name, dist_str, col)
			return
	_draw_nav_offscreen(ctrl, font, screen_size, cam, cam_pos, world_pos, ent_name, dist_str, col)


func _draw_nav_onscreen(ctrl: Control, font: Font, sp: Vector2, ent_name: String, dist_str: String, col: Color) -> void:
	HudDrawHelpers.draw_diamond(ctrl, sp, 5.0, col)

	var name_w =font.get_string_size(ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var name_pos =Vector2(sp.x - name_w * 0.5, sp.y - 18)
	ctrl.draw_rect(Rect2(name_pos.x - 4, name_pos.y - 10, name_w + 8, 14), Color(0.0, 0.02, 0.06, 0.5))
	ctrl.draw_string(font, name_pos, ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)

	var dist_w =font.get_string_size(dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dist_pos =Vector2(sp.x - dist_w * 0.5, sp.y + 18)
	ctrl.draw_rect(Rect2(dist_pos.x - 4, dist_pos.y - 11, dist_w + 8, 15), Color(0.0, 0.02, 0.06, 0.5))
	ctrl.draw_string(font, dist_pos, dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _draw_nav_offscreen(ctrl: Control, font: Font, screen_size: Vector2, cam: Camera3D, cam_pos: Vector3, world_pos: Vector3, ent_name: String, dist_str: String, col: Color) -> void:
	var to_ent: Vector3 = (world_pos - cam_pos).normalized()
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var screen_dir =Vector2(to_ent.dot(right), -to_ent.dot(up))
	if screen_dir.length() < 0.001:
		screen_dir = Vector2(0, -1)
	screen_dir = screen_dir.normalized()

	var center =screen_size * 0.5
	var margin =NAV_EDGE_MARGIN
	var half =center - Vector2(margin, margin)

	var edge_pos =center
	if abs(screen_dir.x) > 0.001:
		var tx: float = half.x / abs(screen_dir.x)
		var ty: float = half.y / abs(screen_dir.y) if abs(screen_dir.y) > 0.001 else 1e6
		var t: float = minf(tx, ty)
		edge_pos = center + screen_dir * t
	elif abs(screen_dir.y) > 0.001:
		var t: float = half.y / abs(screen_dir.y)
		edge_pos = center + screen_dir * t

	var arrow_sz: float = 8.0
	var perp =Vector2(-screen_dir.y, screen_dir.x)
	var tip =edge_pos + screen_dir * 4.0
	ctrl.draw_line(tip, tip - screen_dir * arrow_sz + perp * arrow_sz * 0.5, col, 2.0)
	ctrl.draw_line(tip, tip - screen_dir * arrow_sz - perp * arrow_sz * 0.5, col, 2.0)

	var text_offset =-screen_dir * 20.0 + perp * 14.0
	var text_pos =edge_pos + text_offset
	text_pos.x = clampf(text_pos.x, 8.0, screen_size.x - 120.0)
	text_pos.y = clampf(text_pos.y, 16.0, screen_size.y - 16.0)

	ctrl.draw_string(font, text_pos, ent_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	ctrl.draw_string(font, text_pos + Vector2(0, 13), dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _get_npc_nav_color(node: Node) -> Color:
	var faction = node.get("faction")
	if faction == &"hostile":
		return NAV_COL_HOSTILE
	elif faction == &"friendly":
		return NAV_COL_FRIENDLY
	elif faction == &"player_fleet":
		return NAV_COL_FLEET
	return NAV_COL_NEUTRAL_NPC


func _get_faction_nav_color(faction: StringName) -> Color:
	if faction == &"hostile":
		return NAV_COL_HOSTILE
	elif faction == &"friendly":
		return NAV_COL_FRIENDLY
	elif faction == &"player_fleet":
		return NAV_COL_FLEET
	return NAV_COL_NEUTRAL_NPC


func _get_npc_name(node: Node) -> String:
	var data = node.get("ship_data")
	if data and data.ship_class != "":
		return data.ship_class
	return node.name
