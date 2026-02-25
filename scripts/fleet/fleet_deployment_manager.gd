class_name FleetDeploymentManager
extends Node

# =============================================================================
# Fleet Deployment Manager — Lifecycle for deploying/retrieving fleet ships
# Child of GameManager. Spawns fleet NPCs, manages AI bridge, handles death.
# =============================================================================

const SPAWN_OFFSET_MIN: float = 1800.0
const SPAWN_OFFSET_MAX: float = 2200.0
const FLEET_FACTION: StringName = &"player_fleet"

var _fleet = null
var _deployed_ships: Dictionary = {}  # fleet_index (int) -> ShipController node
var _pos_sync_timer: float = 0.0
const POS_SYNC_INTERVAL: float = 10.0


func _ready() -> void:
	NetworkManager.fleet_deploy_confirmed.connect(_on_deploy_confirmed)
	NetworkManager.fleet_retrieve_confirmed.connect(_on_retrieve_confirmed)
	NetworkManager.fleet_command_confirmed.connect(_on_command_confirmed)
	NetworkManager.npc_died.connect(_on_network_npc_died)


func initialize(fleet) -> void:
	_fleet = fleet


func _process(delta: float) -> void:
	# Periodically save deployed NPC positions to FleetShip for persistence
	_pos_sync_timer += delta
	if _pos_sync_timer >= POS_SYNC_INTERVAL:
		_pos_sync_timer = 0.0
		_sync_deployed_positions()


func _sync_deployed_positions() -> void:
	if _fleet == null:
		return
	for fleet_index in _deployed_ships:
		var npc = _deployed_ships[fleet_index]
		if not is_instance_valid(npc):
			# NPC was LOD-demoted — try to get position from LOD data
			if fleet_index >= 0 and fleet_index < _fleet.ships.size():
				var fs = _fleet.ships[fleet_index]
				if fs.deployed_npc_id != &"":
					var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
					if lod_mgr:
						var lod_data = lod_mgr.get_ship_data(fs.deployed_npc_id)
						if lod_data:
							fs.last_known_pos = FloatingOrigin.to_universe_pos(lod_data.position)
			continue
		if fleet_index >= 0 and fleet_index < _fleet.ships.size():
			var fs = _fleet.ships[fleet_index]
			fs.last_known_pos = FloatingOrigin.to_universe_pos(npc.global_position)
			# Save AI state (mining phase, home station, heat, etc.)
			var mining_ai = npc.get_node_or_null("AIMiningBehavior")
			if mining_ai:
				fs.ai_state = mining_ai.save_state()


func can_deploy(fleet_index: int) -> bool:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		push_warning("can_deploy: invalid fleet/index (fleet=%s idx=%d size=%d)" % [str(_fleet != null), fleet_index, _fleet.ships.size() if _fleet else 0])
		return false
	var fs = _fleet.ships[fleet_index]
	# Can't deploy active ship
	if fleet_index == _fleet.active_index:
		push_warning("can_deploy: idx=%d is active ship" % fleet_index)
		return false
	# Must be docked
	if fs.deployment_state != FleetShip.DeploymentState.DOCKED:
		push_warning("can_deploy: idx=%d state=%d (not DOCKED)" % [fleet_index, fs.deployment_state])
		return false
	# Must be in current system
	var current_sys: int = GameManager.current_system_id_safe()
	if fs.docked_system_id != current_sys:
		push_warning("can_deploy: idx=%d docked_sys=%d != current_sys=%d" % [fleet_index, fs.docked_system_id, current_sys])
		return false
	return true


func deploy_ship(fleet_index: int, cmd: StringName, params: Dictionary = {}, override_pos: Variant = null) -> bool:
	if not can_deploy(fleet_index):
		push_warning("FleetDeploy: can_deploy FAILED for index %d" % fleet_index)
		return false

	var fs = _fleet.ships[fleet_index]
	var universe: Node3D = GameManager.universe_node
	if universe == null:
		push_warning("FleetDeploy: universe_node is null!")
		return false

	var spawn_pos: Vector3
	var offset =Vector3.ZERO
	if override_pos is Vector3:
		# Use exact position (reconnect / reload with saved position)
		spawn_pos = override_pos
	else:
		# Resolve spawn position from station + random offset
		var station_local_pos =Vector3.ZERO
		var station_id: String = fs.docked_station_id
		# Fallback: if docked_station_id is empty, use the active ship's station
		if station_id == "":
			var active_fs = _fleet.get_active()
			if active_fs and active_fs.docked_station_id != "":
				station_id = active_fs.docked_station_id
				fs.docked_station_id = station_id
		# Last resort: find any station in EntityRegistry
		if station_id == "":
			for ent_val in EntityRegistry.get_all().values():
				if ent_val.get("type", -1) == EntityRegistrySystem.EntityType.STATION:
					station_id = ent_val.get("id", "")
					fs.docked_station_id = station_id
					break
		if station_id != "":
			var ent =EntityRegistry.get_entity(station_id)
			if not ent.is_empty():
				station_local_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])

		var angle: float = randf() * TAU
		var dist: float = randf_range(SPAWN_OFFSET_MIN, SPAWN_OFFSET_MAX)
		offset = Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		spawn_pos = station_local_pos + offset

	# Spawn NPC via ShipFactory (skip_default_loadout: fleet ships use their own loadout)
	var npc = ShipFactory.spawn_npc_ship(fs.ship_id, &"balanced", spawn_pos, universe, FLEET_FACTION, false, true)
	if npc == null:
		push_error("FleetDeploy: spawn_npc_ship FAILED for ship_id '%s'" % fs.ship_id)
		return false

	# Fleet NPCs must process even when Universe is disabled (player docked)
	npc.process_mode = Node.PROCESS_MODE_ALWAYS

	# Orient ship facing away from station (Godot forward = -Z)
	if offset.length_squared() > 1.0:
		var away_dir =offset.normalized()
		npc.look_at_from_position(spawn_pos, spawn_pos + away_dir, Vector3.UP)

	# Equip weapons from FleetShip loadout (hardpoints are bare thanks to skip_default_loadout)
	var wm = npc.get_node_or_null("WeaponManager")
	if wm:
		wm.equip_weapons(fs.weapons)

	# Equip shield/engine/modules from FleetShip loadout
	var em = npc.get_node_or_null("EquipmentManager")
	if em == null:
		em = EquipmentManager.new()
		em.name = "EquipmentManager"
		npc.add_child(em)
		em.setup(npc.ship_data)
	if fs.shield_name != &"":
		var shield_res =ShieldRegistry.get_shield(fs.shield_name)
		if shield_res:
			em.equip_shield(shield_res)
	if fs.engine_name != &"":
		var engine_res =EngineRegistry.get_engine(fs.engine_name)
		if engine_res:
			em.equip_engine(engine_res)
	for i in fs.modules.size():
		if fs.modules[i] != &"":
			var mod_res =ModuleRegistry.get_module(fs.modules[i])
			if mod_res:
				em.equip_module(i, mod_res)

	# Attach FleetAICommand
	var bridge =FleetAICommand.new()
	bridge.name = "FleetAICommand"
	bridge.fleet_index = fleet_index
	bridge.command = cmd
	bridge.command_params = params
	bridge._station_id = fs.docked_station_id
	npc.add_child(bridge)

	# Attach AIMiningBehavior if mining order
	if cmd == &"mine":
		var mining_behavior =AIMiningBehavior.new()
		mining_behavior.name = "AIMiningBehavior"
		mining_behavior.fleet_index = fleet_index
		mining_behavior.fleet_ship = fs
		npc.add_child(mining_behavior)

	# Connect death signal
	var health = npc.get_node_or_null("HealthSystem")
	if health:
		health.ship_destroyed.connect(_on_fleet_npc_died.bind(fleet_index, npc))

	# Register / update as fleet entity in EntityRegistry
	var npc_id =StringName(npc.name)
	var upos: Array = FloatingOrigin.to_universe_pos(spawn_pos)
	var existing_ent =EntityRegistry.get_entity(npc.name)
	if existing_ent.is_empty():
		# Entity wasn't registered yet (LOD skip, timing) — register now
		EntityRegistry.register(npc.name, {
			"name": npc.name,
			"type": EntityRegistrySystem.EntityType.SHIP_FLEET,
			"node": npc,
			"radius": 10.0,
			"color": Color(0.3, 0.5, 1.0),
			"pos_x": upos[0], "pos_y": upos[1], "pos_z": upos[2],
			"extra": {
				"fleet_index": fleet_index,
				"owner_name": "Player",
				"owner_pid": NetworkManager.local_peer_id if NetworkManager.local_peer_id > 0 else 0,
				"command": String(cmd),
				"arrived": false,
				"faction": "player_fleet",
			},
		})
	else:
		# Update extra data on existing entity
		existing_ent["extra"]["fleet_index"] = fleet_index
		existing_ent["extra"]["owner_name"] = "Player"
		existing_ent["extra"]["command"] = String(cmd)
		existing_ent["extra"]["arrived"] = false
		existing_ent["type"] = EntityRegistrySystem.EntityType.SHIP_FLEET
		existing_ent["pos_x"] = upos[0]
		existing_ent["pos_y"] = upos[1]
		existing_ent["pos_z"] = upos[2]

	# Update FleetShip data
	fs.deployment_state = FleetShip.DeploymentState.DEPLOYED
	fs.deployed_npc_id = npc_id
	fs.deployed_command = cmd
	fs.deployed_command_params = params
	fs.last_known_pos = FloatingOrigin.to_universe_pos(spawn_pos)

	# Tag ShipLODData so LOD re-promotion re-equips custom loadout
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			lod_data.fleet_index = fleet_index
			lod_data.owner_pid = NetworkManager.local_peer_id if NetworkManager.local_peer_id > 0 else 0

	_deployed_ships[fleet_index] = npc
	_fleet.fleet_changed.emit()

	# Notify squadron manager
	var sq_mgr = GameManager.get_node_or_null("SquadronManager")
	if sq_mgr:
		sq_mgr.on_ship_deployed(fleet_index, npc)

	return true


func retrieve_ship(fleet_index: int) -> bool:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return false
	var fs = _fleet.ships[fleet_index]
	if fs.deployment_state != FleetShip.DeploymentState.DEPLOYED:
		return false

	# Notify squadron manager while NPC still valid
	var sq_mgr = GameManager.get_node_or_null("SquadronManager")
	if sq_mgr:
		sq_mgr.on_ship_retrieved(fleet_index)

	# Despawn NPC and update docked station from FleetAICommand target
	if _deployed_ships.has(fleet_index):
		var npc_ref = _deployed_ships[fleet_index]
		if is_instance_valid(npc_ref):
			var npc = npc_ref
			# Update docked_station_id from bridge (ship may have been sent to a different station)
			var bridge = npc.get_node_or_null("FleetAICommand")
			if bridge and bridge._station_id != "":
				fs.docked_station_id = bridge._station_id
			npc.queue_free()
		_deployed_ships.erase(fleet_index)

	# Always cleanup by npc_id (handles LOD-demoted NPCs where node is freed)
	var npc_id: StringName = fs.deployed_npc_id
	if npc_id != &"":
		EntityRegistry.unregister(String(npc_id))
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			lod_mgr.unregister_ship(npc_id)

	# Update FleetShip data
	fs.deployment_state = FleetShip.DeploymentState.DOCKED
	fs.deployed_npc_id = &""
	fs.deployed_command = &""
	fs.deployed_command_params = {}

	_fleet.fleet_changed.emit()
	return true


func change_command(fleet_index: int, cmd: StringName, params: Dictionary = {}) -> bool:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return false
	var fs = _fleet.ships[fleet_index]
	if fs.deployment_state != FleetShip.DeploymentState.DEPLOYED:
		return false
	if not _deployed_ships.has(fleet_index):
		return false

	var npc_ref = _deployed_ships[fleet_index]
	if not is_instance_valid(npc_ref):
		_deployed_ships.erase(fleet_index)
		return false
	var npc = npc_ref

	var bridge = npc.get_node_or_null("FleetAICommand")
	if bridge:
		bridge.apply_command(cmd, params)

	# Manage AIMiningBehavior lifecycle
	var existing_mining = npc.get_node_or_null("AIMiningBehavior")
	if cmd == &"mine":
		if existing_mining:
			# Mine→Mine: update existing behavior with new params (new belt, new filter)
			existing_mining.update_params(params)
		else:
			var mining_behavior =AIMiningBehavior.new()
			mining_behavior.name = "AIMiningBehavior"
			mining_behavior.fleet_index = fleet_index
			mining_behavior.fleet_ship = fs
			npc.add_child(mining_behavior)
	elif existing_mining:
		existing_mining.queue_free()

	fs.deployed_command = cmd
	fs.deployed_command_params = params
	update_entity_extra(fleet_index, "command", String(cmd))
	update_entity_extra(fleet_index, "arrived", false)
	_fleet.fleet_changed.emit()
	return true


func auto_retrieve_all() -> void:
	if _fleet == null:
		return
	var indices =_deployed_ships.keys().duplicate()
	for idx in indices:
		retrieve_ship(idx)


## Free all deployed NPC nodes from the scene WITHOUT changing deployment_state.
## Ships remain marked DEPLOYED in their system — they'll respawn via redeploy_saved_ships()
## when the player returns to that system.
func force_sync_positions() -> void:
	_sync_deployed_positions()
	_pos_sync_timer = 0.0


func release_scene_nodes() -> void:
	if _fleet == null:
		return
	_sync_deployed_positions()  # Save positions + AI state before freeing
	for fleet_index in _deployed_ships.keys():
		var npc_ref = _deployed_ships[fleet_index]
		if is_instance_valid(npc_ref):
			npc_ref.queue_free()
		# Always cleanup by npc_id (handles LOD-demoted NPCs where node is freed)
		if fleet_index >= 0 and fleet_index < _fleet.ships.size():
			var fs = _fleet.ships[fleet_index]
			var npc_id: StringName = fs.deployed_npc_id
			if npc_id != &"":
				EntityRegistry.unregister(String(npc_id))
				var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
				if lod_mgr:
					lod_mgr.unregister_ship(npc_id)
	_deployed_ships.clear()


func ensure_deployed_visible() -> void:
	for npc in _deployed_ships.values():
		if is_instance_valid(npc):
			npc.visible = true


func redeploy_saved_ships() -> void:
	# Server manages all fleet NPCs via NpcAuthority + backend persistence.
	# Client never spawns fleet NPCs locally — they come via NPC batch sync.
	pass


func _on_fleet_npc_died(fleet_index: int, _npc: Node) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs = _fleet.ships[fleet_index]

	# Cleanup LOD + EntityRegistry before clearing state (handles LOD-demoted NPCs too)
	var npc_id: StringName = fs.deployed_npc_id
	if npc_id != &"":
		EntityRegistry.unregister(String(npc_id))
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			lod_mgr.unregister_ship(npc_id)

	_clear_fleet_ship_state(fs, fleet_index)


## Network handler: fleet NPC died on the server (multiplayer client path).
## Local deaths go through _on_fleet_npc_died via HealthSystem signal instead.
func _on_network_npc_died(npc_id_str: String, _killer_pid: int, _death_pos: Array, _loot: Array) -> void:
	if _fleet == null:
		return
	var npc_id := StringName(npc_id_str)
	for i in _fleet.ships.size():
		var fs = _fleet.ships[i]
		if fs.deployed_npc_id == npc_id:
			_clear_fleet_ship_state(fs, i)
			break


func _clear_fleet_ship_state(fs, fleet_index: int) -> void:
	var ship_name_copy: String = fs.custom_name
	fs.ship_id = &""
	fs.custom_name = ""
	fs.deployment_state = FleetShip.DeploymentState.DOCKED
	fs.deployed_npc_id = &""
	fs.deployed_command = &""
	fs.deployed_command_params = {}
	fs.docked_station_id = ""
	fs.last_known_pos = []
	fs.ai_state = {}
	fs.weapons.clear()
	fs.modules.clear()
	fs.shield_name = &""
	fs.engine_name = &""
	_deployed_ships.erase(fleet_index)
	_fleet.fleet_changed.emit()
	var sq_mgr = GameManager.get_node_or_null("SquadronManager")
	if sq_mgr:
		sq_mgr.on_member_destroyed(fleet_index)
	if GameManager._notif:
		GameManager._notif.fleet.lost(ship_name_copy)


func _on_deploy_confirmed(fleet_index: int, npc_id_str: String) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs = _fleet.ships[fleet_index]
	fs.deployment_state = FleetShip.DeploymentState.DEPLOYED
	fs.deployed_npc_id = StringName(npc_id_str)
	print("[FleetDeploy] deploy CONFIRMED idx=%d npc_id=%s" % [fleet_index, npc_id_str])
	# Resolve position from station (best effort for map)
	if fs.docked_station_id != "":
		var ent = EntityRegistry.get_entity(fs.docked_station_id)
		if not ent.is_empty():
			fs.last_known_pos = [ent["pos_x"], ent["pos_y"], ent["pos_z"]]
	# Ensure EntityRegistry has correct fleet type + owner_pid (the NPC spawn via
	# _on_npc_spawned may have registered before owner_pid was available)
	var fleet_ent = EntityRegistry.get_entity(npc_id_str)
	if not fleet_ent.is_empty():
		fleet_ent["type"] = EntityRegistrySystem.EntityType.SHIP_FLEET
		if not fleet_ent.has("extra"):
			fleet_ent["extra"] = {}
		fleet_ent["extra"]["owner_pid"] = NetworkManager.local_peer_id if NetworkManager.local_peer_id > 0 else 0
		fleet_ent["extra"]["fleet_index"] = fleet_index
		fleet_ent["extra"]["faction"] = "player_fleet"
	# Tag LOD data with fleet_index for proper LOD transitions
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(StringName(npc_id_str))
		if lod_data:
			lod_data.fleet_index = fleet_index
			lod_data.owner_pid = NetworkManager.local_peer_id if NetworkManager.local_peer_id > 0 else 0
	_fleet.fleet_changed.emit()


func _on_retrieve_confirmed(fleet_index: int) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs = _fleet.ships[fleet_index]
	fs.deployment_state = FleetShip.DeploymentState.DOCKED
	fs.deployed_npc_id = &""
	fs.deployed_command = &""
	fs.deployed_command_params = {}
	_fleet.fleet_changed.emit()


func _on_command_confirmed(fleet_index: int, cmd_str: String, params: Dictionary) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs = _fleet.ships[fleet_index]
	fs.deployed_command = StringName(cmd_str)
	fs.deployed_command_params = params
	_fleet.fleet_changed.emit()


func update_entity_extra(fleet_index: int, key: String, value: Variant) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs = _fleet.ships[fleet_index]
	if fs.deployed_npc_id == &"":
		return
	var ent =EntityRegistry.get_entity(String(fs.deployed_npc_id))
	if not ent.is_empty():
		ent["extra"][key] = value


func get_deployed_npc(fleet_index: int):
	if _deployed_ships.has(fleet_index):
		var npc_ref = _deployed_ships[fleet_index]
		if is_instance_valid(npc_ref):
			return npc_ref
		_deployed_ships.erase(fleet_index)
	return null


# =========================================================================
# PUBLIC API — All requests go through server RPCs
# =========================================================================

func request_deploy(fleet_index: int, cmd: StringName, params: Dictionary = {}) -> void:
	var ship_data: Dictionary = _serialize_ship_data(fleet_index)
	if ship_data.is_empty():
		push_warning("FleetDeploy: request_deploy — serialize failed for index %d" % fleet_index)
		return
	if not NetworkManager.is_connected_to_server():
		push_warning("FleetDeploy: request_deploy — NOT connected to server!")
		return
	# Send to server — NO local state change, wait for _on_deploy_confirmed
	var params_json: String = JSON.stringify(params) if not params.is_empty() else ""
	var ship_data_json: String = JSON.stringify(ship_data)
	print("[FleetDeploy] request_deploy idx=%d cmd=%s connected=%s" % [fleet_index, cmd, str(NetworkManager.is_connected_to_server())])
	NetworkManager._rpc_request_fleet_deploy.rpc_id(1, fleet_index, String(cmd), params_json, ship_data_json)


func request_retrieve(fleet_index: int) -> void:
	if not NetworkManager.is_connected_to_server():
		push_warning("FleetDeploy: request_retrieve — NOT connected to server!")
		return
	NetworkManager._rpc_request_fleet_retrieve.rpc_id(1, fleet_index)


func request_change_command(fleet_index: int, cmd: StringName, params: Dictionary = {}) -> void:
	if not NetworkManager.is_connected_to_server():
		push_warning("FleetDeploy: request_change_command — NOT connected to server!")
		return
	var params_json: String = JSON.stringify(params) if not params.is_empty() else ""
	NetworkManager._rpc_request_fleet_command.rpc_id(1, fleet_index, String(cmd), params_json)


## Client-side: apply fleet status from server on reconnect.
## Server is the source of truth for deployment state.
## alive = [{ fleet_index, npc_id, pos_x, pos_y, pos_z }], deaths = [{ fleet_index, npc_id, death_time }]
func apply_reconnect_fleet_status(alive: Array, deaths: Array) -> void:
	if _fleet == null:
		return

	# Build lookup sets
	var alive_map: Dictionary = {}  # fleet_index -> entry
	for entry in alive:
		alive_map[int(entry.get("fleet_index", -1))] = entry
	var death_set: Dictionary = {}
	for death in deaths:
		death_set[int(death.get("fleet_index", -1))] = true

	# Apply server state
	for i in _fleet.ships.size():
		var fs = _fleet.ships[i]
		if alive_map.has(i):
			# Server says this ship is alive and deployed
			var entry: Dictionary = alive_map[i]
			fs.deployment_state = FleetShip.DeploymentState.DEPLOYED
			var npc_id_str: String = entry.get("npc_id", "")
			if npc_id_str != "":
				fs.deployed_npc_id = StringName(npc_id_str)
			var px: float = float(entry.get("pos_x", 0.0))
			var py: float = float(entry.get("pos_y", 0.0))
			var pz: float = float(entry.get("pos_z", 0.0))
			if px != 0.0 or py != 0.0 or pz != 0.0:
				fs.last_known_pos = [px, py, pz]
			var cmd_str: String = entry.get("command", "")
			if cmd_str != "":
				fs.deployed_command = StringName(cmd_str)
		elif death_set.has(i):
			# Server says this ship died while we were offline
			if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
				fs.deployment_state = FleetShip.DeploymentState.DESTROYED
				fs.deployed_npc_id = &""
				fs.deployed_command = &""
				fs.deployed_command_params = {}
				if GameManager._notif:
					GameManager._notif.fleet.lost(fs.custom_name)
		else:
			# Server doesn't mention this ship
			if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
				# Client thought it was deployed but server has no record
				# → Reset to DOCKED (not DESTROYED — ship isn't lost, just not deployed)
				fs.deployment_state = FleetShip.DeploymentState.DOCKED
				fs.deployed_npc_id = &""
				fs.deployed_command = &""
				fs.deployed_command_params = {}

	_fleet.fleet_changed.emit()
	print("FleetDeploy: Reconnect status — %d alive, %d died offline" % [alive.size(), deaths.size()])


## Serialize a FleetShip's data for sending to the server via RPC.
func _serialize_ship_data(fleet_index: int) -> Dictionary:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return {}
	var fs = _fleet.ships[fleet_index]
	var weapons_arr: Array = []
	for w in fs.weapons:
		weapons_arr.append(String(w))
	var modules_arr: Array = []
	for m in fs.modules:
		modules_arr.append(String(m))
	var cargo_items: Array = []
	if fs.cargo:
		cargo_items = fs.cargo.serialize()
	var res_out: Dictionary = {}
	for res_id in fs.ship_resources:
		var qty: int = fs.ship_resources.get(res_id, 0)
		if qty > 0:
			res_out[String(res_id)] = qty
	return {
		"ship_id": String(fs.ship_id),
		"weapons": weapons_arr,
		"shield_name": String(fs.shield_name),
		"engine_name": String(fs.engine_name),
		"modules": modules_arr,
		"docked_station_id": fs.docked_station_id,
		"custom_name": fs.custom_name,
		"cargo": cargo_items,
		"ship_resources": res_out,
	}
