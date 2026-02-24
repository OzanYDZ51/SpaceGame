class_name NpcFleetAuthority
extends RefCounted

# =============================================================================
# NPC Fleet Authority - Fleet NPC tracking, deploy/retrieve/command, reconnect.
# Extracted from NpcAuthority. Runs as a RefCounted sub-object.
# =============================================================================

# Fleet NPC tracking: npc_id -> { owner_uuid, owner_pid, fleet_index }
var _fleet_npcs: Dictionary = {}
# owner_uuid -> Array[StringName] npc_ids (persistent across reconnects)
var _fleet_npcs_by_owner: Dictionary = {}
# owner_uuid -> Array[Dictionary] { fleet_index, npc_id, death_time }
var _fleet_deaths_while_offline: Dictionary = {}

var _auth: NpcAuthority = null


func setup(auth: NpcAuthority) -> void:
	_auth = auth


func register_fleet_npc(npc_id: StringName, owner_pid: int, fleet_index: int) -> void:
	var uuid: String = NetworkManager.get_peer_uuid(owner_pid)
	_fleet_npcs[npc_id] = { "owner_uuid": uuid, "owner_pid": owner_pid, "fleet_index": fleet_index }
	var owner_key: String = uuid if uuid != "" else str(owner_pid)
	if not _fleet_npcs_by_owner.has(owner_key):
		_fleet_npcs_by_owner[owner_key] = []
	var owner_list: Array = _fleet_npcs_by_owner[owner_key]
	if not owner_list.has(npc_id):
		owner_list.append(npc_id)


func unregister_fleet_npc(npc_id: StringName) -> void:
	if not _fleet_npcs.has(npc_id):
		return
	var info: Dictionary = _fleet_npcs[npc_id]
	var uuid: String = info.get("owner_uuid", "")
	var owner_pid: int = info.get("owner_pid", -1)
	var owner_key: String = uuid if uuid != "" else str(owner_pid)
	if _fleet_npcs_by_owner.has(owner_key):
		var owner_list: Array = _fleet_npcs_by_owner[owner_key]
		owner_list.erase(npc_id)
		if owner_list.is_empty():
			_fleet_npcs_by_owner.erase(owner_key)
	_fleet_npcs.erase(npc_id)


func is_fleet_npc(npc_id: StringName) -> bool:
	return _fleet_npcs.has(npc_id)


func get_fleet_npc_owner(npc_id: StringName) -> int:
	if _fleet_npcs.has(npc_id):
		return _fleet_npcs[npc_id].get("owner_pid", -1)
	return -1


## Called when a player disconnects. Fleet NPCs persist — only clear the peer_id.
func on_player_disconnected(uuid: String, old_pid: int) -> void:
	if uuid == "":
		return
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				_fleet_npcs[npc_id]["owner_pid"] = -1
	_auth._asteroids.clean_peer_mining_tracking(old_pid)
	print("NpcAuthority: Player %s (pid=%d) disconnected — fleet NPCs persist" % [uuid, old_pid])


## Called when a player reconnects. Re-associate fleet NPCs and send status.
func on_player_reconnected(uuid: String, new_pid: int) -> void:
	if uuid == "":
		return
	if not _auth._backend._fleet_backend_loaded:
		# Enforce max queue size to prevent memory leaks if backend stays down
		if _auth._backend._pending_reconnects.size() >= NpcFleetBackend.MAX_PENDING_RECONNECTS:
			_auth._backend._pending_reconnects.pop_front()
		_auth._backend._pending_reconnects.append({"uuid": uuid, "pid": new_pid, "time": Time.get_ticks_msec() / 1000.0})
		print("NpcAuthority: Queuing reconnect for %s (pid=%d) — backend fleet not loaded yet" % [uuid, new_pid])
		return
	send_fleet_reconnect_status(uuid, new_pid)


## Build and send fleet reconnect status.
func send_fleet_reconnect_status(uuid: String, new_pid: int) -> void:
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				_fleet_npcs[npc_id]["owner_pid"] = new_pid

	var alive_list: Array = []
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				var info: Dictionary = _fleet_npcs[npc_id]
				var entry = {
					"fleet_index": info.get("fleet_index", -1),
					"npc_id": String(npc_id),
					"command": info.get("command", ""),
				}
				if lod_mgr:
					var lod_data = lod_mgr.get_ship_data(npc_id)
					if lod_data:
						var upos = FloatingOrigin.to_universe_pos(lod_data.position)
						entry["pos_x"] = upos[0]
						entry["pos_y"] = upos[1]
						entry["pos_z"] = upos[2]
						if is_instance_valid(lod_data.node_ref):
							var bridge = lod_data.node_ref.get_node_or_null("FleetAICommand")
							if bridge:
								entry["command"] = String(bridge.command)
				alive_list.append(entry)

	var deaths: Array = _fleet_deaths_while_offline.get(uuid, [])
	_fleet_deaths_while_offline.erase(uuid)

	_auth._rpc_fleet_reconnect_status.rpc_id(new_pid, alive_list, deaths)
	print("NpcAuthority: Player %s reconnected (pid=%d) — %d alive, %d died offline" % [uuid, new_pid, alive_list.size(), deaths.size()])


## Server handles deploy request from a client.
func handle_fleet_deploy_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary, ship_data: Dictionary = {}) -> void:
	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		return

	var npc_id: StringName
	var ship_id: StringName
	var sys_id: int = GameManager.current_system_id_safe()

	if ship_data.is_empty():
		push_warning("NpcAuthority: Fleet deploy from pid=%d — no ship_data" % sender_pid)
		return
	var result: Dictionary = _spawn_remote_fleet_npc(sender_pid, fleet_index, cmd, params, ship_data, sys_id)
	if result.is_empty():
		return
	npc_id = result["npc_id"]
	ship_id = StringName(ship_data.get("ship_id", ""))

	register_fleet_npc(npc_id, sender_pid, fleet_index)
	_fleet_npcs[npc_id]["command"] = String(cmd)
	var deploy_cargo: Array = ship_data.get("cargo", [])
	var deploy_res: Dictionary = ship_data.get("ship_resources", {})
	if not deploy_cargo.is_empty():
		_fleet_npcs[npc_id]["cargo"] = deploy_cargo
	if not deploy_res.is_empty():
		_fleet_npcs[npc_id]["ship_resources"] = deploy_res

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var spawn_data: Dictionary = {
		"sid": String(ship_id),
		"fac": "player_fleet",
		"cmd": String(cmd),
		"owner_pid": sender_pid,
		"owner_name": _get_peer_name(sender_pid),
	}
	if lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			var upos: Array = FloatingOrigin.to_universe_pos(lod_data.position)
			spawn_data["px"] = upos[0]
			spawn_data["py"] = upos[1]
			spawn_data["pz"] = upos[2]

	_auth.register_npc(npc_id, sys_id, ship_id, &"player_fleet")
	_broadcast_fleet_event_deploy(sender_pid, fleet_index, npc_id, spawn_data, sys_id)
	_auth._broadcaster.notify_spawn_to_peers(npc_id, sys_id)
	NetworkManager._rpc_fleet_deploy_confirmed.rpc_id(sender_pid, fleet_index, String(npc_id))


## Server handles retrieve request.
func handle_fleet_retrieve_request(sender_pid: int, fleet_index: int) -> void:
	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		return

	var sys_id: int = GameManager.current_system_id_safe()
	var npc_id: StringName = _find_fleet_npc_id(sender_pid, fleet_index)
	if npc_id == &"":
		push_warning("NpcAuthority: Fleet retrieve pid=%d idx=%d — NPC not found" % [sender_pid, fleet_index])
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data and is_instance_valid(lod_data.node_ref):
			EntityRegistry.unregister(String(npc_id))
			lod_data.node_ref.queue_free()
		lod_mgr.unregister_ship(npc_id)

	_auth.unregister_npc(npc_id)
	unregister_fleet_npc(npc_id)
	_broadcast_fleet_event_retrieve(sender_pid, fleet_index, npc_id, sys_id)
	NetworkManager._rpc_fleet_retrieve_confirmed.rpc_id(sender_pid, fleet_index)


## Server-side: a fleet NPC autonomously docked at a station.
func handle_fleet_npc_self_docked(npc_id: StringName, fleet_index: int) -> void:
	if not _fleet_npcs.has(npc_id):
		return

	var fleet_info: Dictionary = _fleet_npcs[npc_id]
	var owner_pid: int = fleet_info.get("owner_pid", -1)
	var sys_id: int = GameManager.current_system_id_safe()

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data and is_instance_valid(lod_data.node_ref):
			EntityRegistry.unregister(String(npc_id))
			lod_data.node_ref.queue_free()
		lod_mgr.unregister_ship(npc_id)

	_auth.unregister_npc(npc_id)
	unregister_fleet_npc(npc_id)

	if owner_pid > 0 and owner_pid in _auth.multiplayer.get_peers():
		_broadcast_fleet_event_retrieve(owner_pid, fleet_index, npc_id, sys_id)
		NetworkManager._rpc_fleet_retrieve_confirmed.rpc_id(owner_pid, fleet_index)


## Server handles command change request from a client.
func handle_fleet_command_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary) -> void:
	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		print("[FleetCmd] FleetDeploymentManager not found")
		return

	var sys_id: int = GameManager.current_system_id_safe()
	var npc_id: StringName = _find_fleet_npc_id(sender_pid, fleet_index)
	if npc_id == &"":
		push_warning("NpcAuthority: Fleet command pid=%d idx=%d — NPC not found" % [sender_pid, fleet_index])
		return

	print("[FleetCmd] pid=%d idx=%d cmd=%s npc=%s params=%s" % [sender_pid, fleet_index, cmd, npc_id, params])

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data and is_instance_valid(lod_data.node_ref):
			var npc = lod_data.node_ref
			var bridge = npc.get_node_or_null("FleetAICommand")
			if bridge:
				print("[FleetCmd] Applying command via FleetAICommand bridge")
				bridge.apply_command(cmd, params)
			else:
				print("[FleetCmd] WARNING: FleetAICommand bridge not found on NPC %s" % npc_id)
			var existing_mining = npc.get_node_or_null("AIMiningBehavior")
			if cmd == &"mine":
				if existing_mining:
					existing_mining.update_params(params)
				else:
					var mining_behavior = AIMiningBehavior.new()
					mining_behavior.name = "AIMiningBehavior"
					mining_behavior.fleet_index = fleet_index
					npc.add_child(mining_behavior)
			elif existing_mining:
				existing_mining.queue_free()
		else:
			print("[FleetCmd] WARNING: node_ref invalid for NPC %s (lod_data=%s)" % [npc_id, lod_data != null])

	if _fleet_npcs.has(npc_id):
		_fleet_npcs[npc_id]["command"] = String(cmd)
		_fleet_npcs[npc_id]["command_params"] = params

	_broadcast_fleet_event_command(sender_pid, fleet_index, npc_id, cmd, params, sys_id)
	NetworkManager._rpc_fleet_command_confirmed.rpc_id(sender_pid, fleet_index, String(cmd), params)


## Called by NpcCombatValidator when a fleet NPC is killed.
func on_fleet_npc_killed(npc_id: StringName) -> void:
	if not _fleet_npcs.has(npc_id):
		return
	var fleet_info: Dictionary = _fleet_npcs[npc_id]
	var owner_uuid: String = fleet_info.get("owner_uuid", "")
	var owner_pid: int = fleet_info.get("owner_pid", -1)
	var fi: int = fleet_info.get("fleet_index", -1)

	_auth._backend.report_fleet_death_to_backend(owner_uuid, fi)

	if owner_uuid != "" and not NetworkManager.peers.has(owner_pid):
		if not _fleet_deaths_while_offline.has(owner_uuid):
			_fleet_deaths_while_offline[owner_uuid] = []
		_fleet_deaths_while_offline[owner_uuid].append({
			"fleet_index": fi,
			"npc_id": String(npc_id),
			"death_time": Time.get_unix_time_from_system(),
		})
	unregister_fleet_npc(npc_id)


func _broadcast_fleet_event_deploy(owner_pid: int, fleet_idx: int, npc_id: StringName, spawn_data: Dictionary, system_id: int) -> void:
	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		NetworkManager._rpc_fleet_deployed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), spawn_data)


func _broadcast_fleet_event_retrieve(owner_pid: int, fleet_idx: int, npc_id: StringName, system_id: int) -> void:
	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		NetworkManager._rpc_fleet_retrieved.rpc_id(pid, owner_pid, fleet_idx, String(npc_id))


func _broadcast_fleet_event_command(owner_pid: int, fleet_idx: int, npc_id: StringName, cmd: StringName, params: Dictionary, system_id: int) -> void:
	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		NetworkManager._rpc_fleet_command_changed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), String(cmd), params)


func _get_peer_name(pid: int) -> String:
	if NetworkManager.peers.has(pid):
		return NetworkManager.peers[pid].player_name
	return "Pilote #%d" % pid


func _find_fleet_npc_id(sender_pid: int, fleet_index: int) -> StringName:
	var uuid: String = NetworkManager.get_peer_uuid(sender_pid)
	var owner_key: String = uuid if uuid != "" else str(sender_pid)
	if not _fleet_npcs_by_owner.has(owner_key):
		return &""
	for npc_id in _fleet_npcs_by_owner[owner_key]:
		if _fleet_npcs.has(npc_id):
			if _fleet_npcs[npc_id].get("fleet_index", -1) == fleet_index:
				return npc_id
	return &""


## Spawn a fleet NPC for a remote client using ship data from the RPC.
func _spawn_remote_fleet_npc(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary, ship_data: Dictionary, _system_id: int) -> Dictionary:
	var universe: Node3D = GameManager.universe_node
	if universe == null:
		push_warning("NpcAuthority: Cannot spawn remote fleet NPC — no universe node")
		return {}

	var ship_id_str: String = ship_data.get("ship_id", "")
	if ship_id_str == "":
		push_warning("NpcAuthority: Remote fleet deploy — empty ship_id")
		return {}
	var ship_id := StringName(ship_id_str)
	if ShipRegistry.get_ship_data(ship_id) == null:
		push_warning("NpcAuthority: Fleet deploy — ship '%s' is retired, using default '%s'" % [ship_id_str, Constants.DEFAULT_SHIP_ID])
		ship_id = Constants.DEFAULT_SHIP_ID

	# Resolve spawn position near docked station
	var spawn_pos := Vector3.ZERO
	var station_id: String = ship_data.get("docked_station_id", "")
	if station_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(station_id)
		if not ent.is_empty():
			spawn_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
	var angle: float = randf() * TAU
	var dist: float = randf_range(1800.0, 2200.0)
	var offset := Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
	spawn_pos += offset

	var npc = ShipFactory.spawn_npc_ship(ship_id, &"balanced", spawn_pos, universe, &"player_fleet", false, true)
	if npc == null:
		push_error("NpcAuthority: Remote fleet spawn FAILED for ship_id '%s'" % ship_id_str)
		return {}

	npc.process_mode = Node.PROCESS_MODE_ALWAYS

	if offset.length_squared() > 1.0:
		var away_dir := offset.normalized()
		npc.look_at_from_position(spawn_pos, spawn_pos + away_dir, Vector3.UP)

	# Equip weapons
	var wm = npc.get_node_or_null("WeaponManager")
	if wm:
		var weapons: Array = ship_data.get("weapons", [])
		var weapons_sn: Array[StringName] = []
		for w in weapons:
			weapons_sn.append(StringName(w))
		wm.equip_weapons(weapons_sn)

	# Equip shield/engine/modules
	var em = npc.get_node_or_null("EquipmentManager")
	if em == null:
		em = EquipmentManager.new()
		em.name = "EquipmentManager"
		npc.add_child(em)
		em.setup(npc.ship_data)
	var shield_name: String = ship_data.get("shield_name", "")
	if shield_name != "":
		var shield_res = ShieldRegistry.get_shield(StringName(shield_name))
		if shield_res:
			em.equip_shield(shield_res)
	var engine_name: String = ship_data.get("engine_name", "")
	if engine_name != "":
		var engine_res = EngineRegistry.get_engine(StringName(engine_name))
		if engine_res:
			em.equip_engine(engine_res)
	var modules: Array = ship_data.get("modules", [])
	for i in modules.size():
		if modules[i] != "":
			var mod_res = ModuleRegistry.get_module(StringName(modules[i]))
			if mod_res:
				em.equip_module(i, mod_res)

	# Attach FleetAICommand
	var bridge = FleetAICommand.new()
	bridge.name = "FleetAICommand"
	bridge.fleet_index = fleet_index
	bridge.command = cmd
	bridge.command_params = params
	bridge._station_id = station_id
	npc.add_child(bridge)

	if cmd == &"mine":
		var mining_behavior = AIMiningBehavior.new()
		mining_behavior.name = "AIMiningBehavior"
		mining_behavior.fleet_index = fleet_index
		npc.add_child(mining_behavior)

	# Register in EntityRegistry
	var npc_id := StringName(npc.name)
	var upos: Array = FloatingOrigin.to_universe_pos(spawn_pos)
	EntityRegistry.register(npc.name, {
		"name": npc.name,
		"type": EntityRegistrySystem.EntityType.SHIP_FLEET,
		"node": npc,
		"radius": 10.0,
		"color": Color(0.3, 0.5, 1.0),
		"pos_x": upos[0], "pos_y": upos[1], "pos_z": upos[2],
		"extra": {
			"fleet_index": fleet_index,
			"owner_pid": sender_pid,
			"owner_name": _get_peer_name(sender_pid),
			"command": String(cmd),
			"arrived": false,
			"faction": "player_fleet",
		},
	})

	# Tag ShipLODData
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			lod_data.fleet_index = fleet_index

	return {"npc_id": npc_id}
