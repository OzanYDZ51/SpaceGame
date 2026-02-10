class_name MapSquadronLines
extends RefCounted

# =============================================================================
# Map Squadron Lines — Draws formation lines from members to leaders on the map
# Static utility, called from MapEntities._draw()
# =============================================================================


static func draw_squadron_lines(canvas: CanvasItem, camera: MapCamera, entities: Dictionary, squadrons: Array, fleet: PlayerFleet, player_id: String) -> void:
	if camera == null or fleet == null:
		return

	var font: Font = UITheme.get_font()

	for sq_raw in squadrons:
		var sq: Squadron = sq_raw as Squadron
		if sq == null:
			continue

		# Resolve leader screen position
		var leader_sp := _get_ship_screen_pos(sq.leader_fleet_index, fleet, entities, camera, player_id)
		if leader_sp == Vector2(-9999, -9999):
			continue

		# Draw leader star badge
		_draw_leader_badge(canvas, leader_sp, sq)

		# Draw lines from each member to leader
		for member_idx in sq.member_fleet_indices:
			var member_sp := _get_ship_screen_pos(member_idx, fleet, entities, camera, player_id)
			if member_sp == Vector2(-9999, -9999):
				continue

			var role: StringName = sq.get_role(member_idx)
			var role_col := SquadronRoleRegistry.get_role_color(role)
			var line_col := Color(role_col.r, role_col.g, role_col.b, 0.3)

			# Dashed line
			_draw_dashed(canvas, member_sp, leader_sp, line_col, 1.0, 6.0, 4.0)

			# Role badge on member
			var badge_text := "[%s]" % SquadronRoleRegistry.get_role_short(role)
			var tw: float = font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			canvas.draw_string(font, member_sp + Vector2(-tw * 0.5, -12), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, role_col)


static func _get_ship_screen_pos(fleet_index: int, fleet: PlayerFleet, entities: Dictionary, camera: MapCamera, player_id: String) -> Vector2:
	if fleet_index < 0:
		# Player is leader (fleet_index = -1)
		if entities.has(player_id):
			var ent: Dictionary = entities[player_id]
			return camera.universe_to_screen(ent["pos_x"], ent["pos_z"])
		return Vector2(-9999, -9999)

	if fleet_index >= fleet.ships.size():
		return Vector2(-9999, -9999)

	var fs := fleet.ships[fleet_index]

	# Active ship = player entity
	if fleet_index == fleet.active_index:
		if entities.has(player_id):
			var ent: Dictionary = entities[player_id]
			return camera.universe_to_screen(ent["pos_x"], ent["pos_z"])
		return Vector2(-9999, -9999)

	# Deployed = NPC entity
	if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.deployed_npc_id != &"":
		var npc_id := String(fs.deployed_npc_id)
		if entities.has(npc_id):
			var npc_ent: Dictionary = entities[npc_id]
			return camera.universe_to_screen(npc_ent["pos_x"], npc_ent["pos_z"])
		var reg_ent := EntityRegistry.get_entity(npc_id)
		if not reg_ent.is_empty():
			return camera.universe_to_screen(reg_ent["pos_x"], reg_ent["pos_z"])

	return Vector2(-9999, -9999)


static func _draw_leader_badge(canvas: CanvasItem, pos: Vector2, sq: Squadron) -> void:
	# Star icon above leader
	var font: Font = UITheme.get_font()
	var formation_text := SquadronFormation.get_formation_display(sq.formation_type)
	var label := "* %s [%s]" % [sq.squadron_name, formation_text]
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	canvas.draw_string(font, pos + Vector2(-tw * 0.5, -16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, MapColors.SQUADRON_HEADER)


static func _draw_dashed(canvas: CanvasItem, from: Vector2, to: Vector2, col: Color, width: float, dash: float, gap: float) -> void:
	var dir := (to - from)
	var total: float = dir.length()
	if total < 1.0:
		return
	var unit := dir / total
	var pos: float = 0.0
	while pos < total:
		var seg_end: float = minf(pos + dash, total)
		canvas.draw_line(from + unit * pos, from + unit * seg_end, col, width)
		pos = seg_end + gap
