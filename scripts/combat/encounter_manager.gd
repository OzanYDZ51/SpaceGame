class_name EncounterManager
extends Node

# =============================================================================
# Encounter Manager - Spawns and tracks NPC encounters
# =============================================================================

signal encounter_started(encounter_id: int)
signal encounter_ended(encounter_id: int)
signal ship_destroyed_in_encounter(ship_name: String)

var _active_npc_ids: Array[StringName] = []
var _encounter_counter: int = 0

# Deferred spawn: during initial load, NetworkSyncManager/NpcAuthority don't exist yet.
# We store the pending request and GameManager triggers it after network role is known.
var _deferred_spawn_pending: bool = false
var _deferred_danger_level: int = 0
var _deferred_system_data = null


func clear_all_npcs() -> void:
	var lod_mgr =_get_lod_manager()
	if lod_mgr:
		for npc_id in _active_npc_ids:
			lod_mgr.unregister_ship(npc_id)
	else:
		# Legacy fallback: free nodes directly
		for npc_id in _active_npc_ids:
			var node =get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))
			if node and is_instance_valid(node):
				node.queue_free()
	_active_npc_ids.clear()
	_encounter_counter = 0


func spawn_system_encounters(danger_level: int, system_data) -> void:
	# In multiplayer, only the server spawns NPCs. Clients receive them via NpcAuthority sync.
	# In offline/single-player, is_server() is false but we still need to spawn NPCs.
	if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
		return

	# During initial load, NetworkSyncManager (and NpcAuthority) don't exist yet.
	# Defer spawning until GameManager triggers it after network role is determined.
	if not GameManager.get_node_or_null("NetworkSyncManager"):
		_deferred_spawn_pending = true
		_deferred_danger_level = danger_level
		_deferred_system_data = system_data
		return

	_do_spawn_encounters(danger_level, system_data)


## Called by GameManager after network role is determined.
func spawn_deferred() -> void:
	if not _deferred_spawn_pending:
		return
	_deferred_spawn_pending = false
	_do_spawn_encounters(_deferred_danger_level, _deferred_system_data)


func _do_spawn_encounters(danger_level: int, system_data) -> void:
	# Collect all station positions and scene nodes
	var station_positions: Array[Vector3] = []
	var station_nodes: Array = []  # Node3D or null
	if system_data and system_data.stations.size() > 0:
		for st in system_data.stations:
			var orbit_r: float = st.orbital_radius
			var angle: float = EntityRegistrySystem.compute_orbital_angle(st.orbital_angle, st.orbital_period)
			var station_pos := Vector3(cos(angle) * orbit_r, 0.0, sin(angle) * orbit_r)
			station_positions.append(station_pos)
			# Find the actual station scene node via EntityRegistry
			var station_node: Node3D = null
			var all_stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
			for ent in all_stations:
				if ent.get("node") and is_instance_valid(ent["node"]):
					var ent_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					if ent_pos.distance_to(station_pos) < 500.0:
						station_node = ent["node"]
						break
			station_nodes.append(station_node)

	# Fallback if no stations
	if station_positions.is_empty():
		station_positions.append(Vector3(500, 0, -1500))
		station_nodes.append(null)

	# Get current system_id for encounter key generation
	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0

	var configs := EncounterConfig.get_danger_config(danger_level)
	if danger_level == 5 and configs.size() >= 2:
		# Danger 5: formation near first station
		var st_pos: Vector3 = station_positions[0]
		var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
		var base_pos := st_pos + radial_dir * 2000.0 + Vector3(0, 100, 0)
		spawn_formation(configs[0]["ship"], configs[1]["ship"], configs[1]["count"], base_pos, configs[0]["fac"], station_nodes[0])
	else:
		var cfg_idx: int = 0
		for cfg in configs:
			# Round-robin distribute groups across stations
			var st_idx: int = cfg_idx % station_positions.size()
			var st_pos: Vector3 = station_positions[st_idx]
			var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
			var base_pos := st_pos + radial_dir * 2000.0 + Vector3(0, 100, 0)
			spawn_patrol(cfg["count"], cfg["ship"], base_pos, cfg["radius"], cfg["fac"], system_id, cfg_idx, station_nodes[st_idx])
			cfg_idx += 1


func spawn_patrol(count: int, ship_id: StringName, center: Vector3, radius: float, faction: StringName = &"hostile", system_id: int = -1, cfg_idx: int = -1, station_node: Node3D = null) -> void:
	_encounter_counter += 1
	var eid =_encounter_counter

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	var lod_mgr =_get_lod_manager()
	var cam_pos =Vector3.ZERO
	var cam =get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	# Get NpcAuthority for respawn checking
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	var now: float = Time.get_unix_time_from_system()

	for i in count:
		# Check respawn cooldown if encounter key is available
		if system_id >= 0 and cfg_idx >= 0 and npc_auth:
			var encounter_key: String = "%d:enc_%d_%d" % [system_id, cfg_idx, i]
			if npc_auth._destroyed_encounter_npcs.has(encounter_key):
				if now < npc_auth._destroyed_encounter_npcs[encounter_key]:
					continue
				else:
					npc_auth._destroyed_encounter_npcs.erase(encounter_key)

		var angle: float = (float(i) / float(count)) * TAU
		var offset =Vector3(cos(angle) * radius * 0.5, randf_range(-30.0, 30.0), sin(angle) * radius * 0.5)
		var pos: Vector3 = center + offset

		# If LOD manager exists and spawn is far away, use data-only (LOD2)
		# Clamp patrol radius for station guards
		var patrol_radius: float = radius
		if station_node:
			patrol_radius = clampf(radius, 500.0, 1000.0)

		if lod_mgr and cam_pos.distance_to(pos) > ShipLODManager.LOD1_DISTANCE:
			var lod_data = ShipFactory.create_npc_data_only(ship_id, &"balanced", pos, faction)
			if lod_data:
				lod_data.ai_patrol_center = center
				lod_data.ai_patrol_radius = patrol_radius
				lod_data.velocity = Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
				if station_node:
					lod_data.guard_station_name = StringName(station_node.name)
				lod_mgr.register_ship(lod_data.id, lod_data)
				_active_npc_ids.append(lod_data.id)
				_register_npc_on_server(lod_data.id, ship_id, faction)
				_store_encounter_key(lod_data.id, system_id, cfg_idx, i)
		else:
			var ship = ShipFactory.spawn_npc_ship(ship_id, &"balanced", pos, parent, faction)
			if ship:
				var brain = ship.get_node_or_null("AIBrain")
				if brain:
					brain.set_patrol_area(center, patrol_radius)
					if station_node:
						brain.guard_station = station_node
				_active_npc_ids.append(StringName(ship.name))
				ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
				_register_npc_on_server(StringName(ship.name), ship_id, faction, ship)
				_store_encounter_key(StringName(ship.name), system_id, cfg_idx, i)

	encounter_started.emit(eid)


func spawn_free_for_all(count: int, ship_id: StringName, center: Vector3, radius: float) -> void:
	_encounter_counter += 1
	var eid =_encounter_counter

	var lod_mgr =_get_lod_manager()

	for i in count:
		var angle: float = randf() * TAU
		var dist: float = randf_range(radius * 0.1, radius)
		var offset =Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		var pos: Vector3 = center + offset

		# Unique faction per ship — everyone fights everyone
		var unique_faction =StringName("npc_%d" % i)

		# Random initial velocity so LOD2 ships move on radar
		var vel =Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.2, 0.2),
			randf_range(-1.0, 1.0)
		).normalized() * randf_range(30.0, 80.0)

		if lod_mgr:
			# All spawn as data-only (LOD2) — LOD manager promotes nearby ones
			var lod_data = ShipFactory.create_npc_data_only(ship_id, &"aggressive", pos, unique_faction)
			if lod_data:
				lod_data.ai_patrol_center = center
				lod_data.ai_patrol_radius = radius
				lod_data.velocity = vel
				lod_mgr.register_ship(lod_data.id, lod_data)
				_active_npc_ids.append(lod_data.id)
				_register_npc_on_server(lod_data.id, ship_id, unique_faction)
		else:
			# Legacy fallback: no LOD manager
			var parent =get_tree().current_scene.get_node_or_null("Universe")
			if parent == null:
				parent = get_tree().current_scene
			var ship = ShipFactory.spawn_npc_ship(ship_id, &"aggressive", pos, parent, unique_faction)
			if ship:
				var brain = ship.get_node_or_null("AIBrain")
				if brain:
					brain.set_patrol_area(center, radius)
				_active_npc_ids.append(StringName(ship.name))
				ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
				_register_npc_on_server(StringName(ship.name), ship_id, unique_faction)

	encounter_started.emit(eid)


func spawn_ambush(ship_ids: Array[StringName], range_dist: float, faction: StringName = &"hostile") -> void:
	_encounter_counter += 1
	var player =GameManager.player_ship
	if player == null:
		return

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	for ship_id in ship_ids:
		var offset =Vector3(
			randf_range(-range_dist, range_dist),
			randf_range(-range_dist * 0.3, range_dist * 0.3),
			randf_range(-range_dist, range_dist)
		)
		var pos: Vector3 = player.global_position + offset

		var ship = ShipFactory.spawn_npc_ship(ship_id, &"aggressive", pos, parent, faction)
		if ship:
			_active_npc_ids.append(StringName(ship.name))
			ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
			_register_npc_on_server(StringName(ship.name), ship_id, faction, ship)

	encounter_started.emit(_encounter_counter)


func spawn_formation(leader_id: StringName, wingman_id: StringName, wingman_count: int, pos: Vector3, faction: StringName = &"hostile", station_node: Node3D = null) -> void:
	_encounter_counter += 1

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	# Spawn leader
	var leader = ShipFactory.spawn_npc_ship(leader_id, &"aggressive", pos, parent, faction)
	if leader == null:
		return
	var leader_brain = leader.get_node_or_null("AIBrain")
	if leader_brain and station_node:
		leader_brain.guard_station = station_node
	_active_npc_ids.append(StringName(leader.name))
	leader.tree_exiting.connect(_on_npc_removed.bind(StringName(leader.name)))
	_register_npc_on_server(StringName(leader.name), leader_id, faction, leader)

	# Spawn wingmen in formation
	for i in wingman_count:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var row: int = i / 2 + 1
		var offset =Vector3(side * 60.0 * row, 0.0, 40.0 * row)
		var wing_pos: Vector3 = pos + offset

		var wingman = ShipFactory.spawn_npc_ship(wingman_id, &"balanced", wing_pos, parent, faction)
		if wingman:
			var brain = wingman.get_node_or_null("AIBrain")
			if brain:
				brain.formation_leader = leader
				brain.formation_offset = offset
				brain.current_state = AIBrain.State.FORMATION
				if station_node:
					brain.guard_station = station_node
			_active_npc_ids.append(StringName(wingman.name))
			wingman.tree_exiting.connect(_on_npc_removed.bind(StringName(wingman.name)))
			_register_npc_on_server(StringName(wingman.name), wingman_id, faction, wingman)

	encounter_started.emit(_encounter_counter)


func get_active_npc_count() -> int:
	return _active_npc_ids.size()


func _on_npc_removed(npc_id: StringName) -> void:
	_active_npc_ids.erase(npc_id)
	ship_destroyed_in_encounter.emit(String(npc_id))
	if _active_npc_ids.is_empty():
		encounter_ended.emit(_encounter_counter)


func _get_lod_manager():
	var mgr = GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr.has_method("register_npc"):
		return mgr
	return null


## Store encounter key on NpcAuthority's NPC record for respawn tracking.
func _store_encounter_key(npc_id: StringName, system_id: int, cfg_idx: int, spawn_idx: int) -> void:
	if system_id < 0 or cfg_idx < 0:
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth and npc_auth._npcs.has(npc_id):
		npc_auth._npcs[npc_id]["encounter_key"] = "%d:enc_%d_%d" % [system_id, cfg_idx, spawn_idx]


## Register NPC with NpcAuthority (server only) and notify connected clients.
func _register_npc_on_server(npc_id: StringName, sid: StringName, fac: StringName, ship_node: Node3D = null) -> void:
	if not NetworkManager.is_server():
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth == null:
		return
	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0
	npc_auth.register_npc(npc_id, system_id, sid, fac)
	npc_auth.notify_spawn_to_peers(npc_id, system_id)
	# Connect weapon fire relay for remote clients to see NPC shots
	if ship_node:
		npc_auth.connect_npc_fire_relay(npc_id, ship_node)
