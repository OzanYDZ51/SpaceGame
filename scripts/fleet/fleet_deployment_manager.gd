class_name FleetDeploymentManager
extends Node

# =============================================================================
# Fleet Deployment Manager — Lifecycle for deploying/retrieving fleet ships
# Child of GameManager. Spawns fleet NPCs, manages AI bridge, handles death.
# =============================================================================

const SPAWN_OFFSET_MIN: float = 1800.0
const SPAWN_OFFSET_MAX: float = 2200.0
const FLEET_FACTION: StringName = &"player_fleet"

var _fleet: PlayerFleet = null
var _deployed_ships: Dictionary = {}  # fleet_index (int) -> ShipController node
var _pos_sync_timer: float = 0.0
const POS_SYNC_INTERVAL: float = 10.0


func initialize(fleet: PlayerFleet) -> void:
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
		var npc: ShipController = _deployed_ships[fleet_index]
		if not is_instance_valid(npc):
			continue
		if fleet_index >= 0 and fleet_index < _fleet.ships.size():
			var fs := _fleet.ships[fleet_index]
			fs.last_known_pos = FloatingOrigin.to_universe_pos(npc.global_position)
			# Save AI state (mining phase, home station, heat, etc.)
			var mining_ai := npc.get_node_or_null("AIMiningBehavior") as AIMiningBehavior
			if mining_ai:
				fs.ai_state = mining_ai.save_state()


func can_deploy(fleet_index: int) -> bool:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return false
	var fs := _fleet.ships[fleet_index]
	# Can't deploy active ship
	if fleet_index == _fleet.active_index:
		return false
	# Must be docked
	if fs.deployment_state != FleetShip.DeploymentState.DOCKED:
		return false
	# Must be in current system
	var current_sys: int = GameManager.current_system_id_safe()
	if fs.docked_system_id != current_sys:
		return false
	return true


func deploy_ship(fleet_index: int, cmd: StringName, params: Dictionary = {}, override_pos: Variant = null) -> bool:
	if not can_deploy(fleet_index):
		push_warning("FleetDeploy: can_deploy FAILED for index %d" % fleet_index)
		return false

	var fs := _fleet.ships[fleet_index]
	var universe: Node3D = GameManager.universe_node
	if universe == null:
		push_warning("FleetDeploy: universe_node is null!")
		return false

	var spawn_pos: Vector3
	var offset := Vector3.ZERO
	if override_pos is Vector3:
		# Use exact position (reconnect / reload with saved position)
		spawn_pos = override_pos
	else:
		# Resolve spawn position from station + random offset
		var station_local_pos := Vector3.ZERO
		var station_id: String = fs.docked_station_id
		if station_id != "":
			var ent := EntityRegistry.get_entity(station_id)
			if not ent.is_empty():
				station_local_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])

		var angle: float = randf() * TAU
		var dist: float = randf_range(SPAWN_OFFSET_MIN, SPAWN_OFFSET_MAX)
		offset = Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		spawn_pos = station_local_pos + offset

	# Spawn NPC via ShipFactory (skip_default_loadout: fleet ships use their own loadout)
	var npc := ShipFactory.spawn_npc_ship(fs.ship_id, &"balanced", spawn_pos, universe, FLEET_FACTION, false, true)
	if npc == null:
		push_error("FleetDeploy: spawn_npc_ship FAILED for ship_id '%s'" % fs.ship_id)
		return false

	# Fleet NPCs must process even when Universe is disabled (player docked)
	npc.process_mode = Node.PROCESS_MODE_ALWAYS

	# Orient ship facing away from station (Godot forward = -Z)
	if offset.length_squared() > 1.0:
		var away_dir := offset.normalized()
		npc.look_at_from_position(spawn_pos, spawn_pos + away_dir, Vector3.UP)

	# Equip weapons from FleetShip loadout (hardpoints are bare thanks to skip_default_loadout)
	var wm := npc.get_node_or_null("WeaponManager") as WeaponManager
	if wm:
		wm.equip_weapons(fs.weapons)

	# Equip shield/engine/modules from FleetShip loadout
	var em := npc.get_node_or_null("EquipmentManager") as EquipmentManager
	if em == null:
		em = EquipmentManager.new()
		em.name = "EquipmentManager"
		npc.add_child(em)
		em.setup(npc.ship_data)
	if fs.shield_name != &"":
		var shield_res := ShieldRegistry.get_shield(fs.shield_name)
		if shield_res:
			em.equip_shield(shield_res)
	if fs.engine_name != &"":
		var engine_res := EngineRegistry.get_engine(fs.engine_name)
		if engine_res:
			em.equip_engine(engine_res)
	for i in fs.modules.size():
		if fs.modules[i] != &"":
			var mod_res := ModuleRegistry.get_module(fs.modules[i])
			if mod_res:
				em.equip_module(i, mod_res)

	# Attach FleetAIBridge
	var bridge := FleetAIBridge.new()
	bridge.name = "FleetAIBridge"
	bridge.fleet_index = fleet_index
	bridge.command = cmd
	bridge.command_params = params
	bridge._station_id = fs.docked_station_id
	npc.add_child(bridge)

	# Attach AIMiningBehavior if mining order
	if cmd == &"mine":
		var mining_behavior := AIMiningBehavior.new()
		mining_behavior.name = "AIMiningBehavior"
		mining_behavior.fleet_index = fleet_index
		mining_behavior.fleet_ship = fs
		npc.add_child(mining_behavior)

	# Connect death signal
	var health := npc.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.ship_destroyed.connect(_on_fleet_npc_died.bind(fleet_index, npc))

	# Register / update as fleet entity in EntityRegistry
	var npc_id := StringName(npc.name)
	var upos: Array = FloatingOrigin.to_universe_pos(spawn_pos)
	var existing_ent := EntityRegistry.get_entity(npc.name)
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
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr:
		var lod_data := lod_mgr.get_ship_data(npc_id)
		if lod_data:
			lod_data.fleet_index = fleet_index

	_deployed_ships[fleet_index] = npc
	_fleet.fleet_changed.emit()

	# Notify squadron manager
	var sq_mgr := GameManager.get_node_or_null("SquadronManager") as SquadronManager
	if sq_mgr:
		sq_mgr.on_ship_deployed(fleet_index, npc)

	return true


func retrieve_ship(fleet_index: int) -> bool:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return false
	var fs := _fleet.ships[fleet_index]
	if fs.deployment_state != FleetShip.DeploymentState.DEPLOYED:
		return false

	# Notify squadron manager while NPC still valid
	var sq_mgr := GameManager.get_node_or_null("SquadronManager") as SquadronManager
	if sq_mgr:
		sq_mgr.on_ship_retrieved(fleet_index)

	# Despawn NPC and update docked station from FleetAIBridge target
	if _deployed_ships.has(fleet_index):
		var npc_ref = _deployed_ships[fleet_index]
		if is_instance_valid(npc_ref):
			var npc: ShipController = npc_ref
			# Update docked_station_id from bridge (ship may have been sent to a different station)
			var bridge := npc.get_node_or_null("FleetAIBridge") as FleetAIBridge
			if bridge and bridge._station_id != "":
				fs.docked_station_id = bridge._station_id
			EntityRegistry.unregister(npc.name)
			var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
			if lod_mgr:
				lod_mgr.unregister_ship(StringName(npc.name))
			npc.queue_free()
		_deployed_ships.erase(fleet_index)

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
	var fs := _fleet.ships[fleet_index]
	if fs.deployment_state != FleetShip.DeploymentState.DEPLOYED:
		return false
	if not _deployed_ships.has(fleet_index):
		return false

	var npc_ref = _deployed_ships[fleet_index]
	if not is_instance_valid(npc_ref):
		_deployed_ships.erase(fleet_index)
		return false
	var npc: ShipController = npc_ref

	var bridge := npc.get_node_or_null("FleetAIBridge") as FleetAIBridge
	if bridge:
		bridge.apply_command(cmd, params)

	# Manage AIMiningBehavior lifecycle
	var existing_mining := npc.get_node_or_null("AIMiningBehavior") as AIMiningBehavior
	if cmd == &"mine":
		if existing_mining:
			# Mine→Mine: update existing behavior with new params (new belt, new filter)
			existing_mining.update_params(params)
		else:
			var mining_behavior := AIMiningBehavior.new()
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
	var indices := _deployed_ships.keys().duplicate()
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
			var npc: ShipController = npc_ref
			EntityRegistry.unregister(npc.name)
			var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
			if lod_mgr:
				lod_mgr.unregister_ship(StringName(npc.name))
			npc.queue_free()
	_deployed_ships.clear()


func ensure_deployed_visible() -> void:
	for npc in _deployed_ships.values():
		if is_instance_valid(npc):
			npc.visible = true


func redeploy_saved_ships() -> void:
	if _fleet == null:
		return
	if _is_multiplayer_client():
		return  # Server manages fleet NPCs, client sees them via LOD
	var current_sys: int = GameManager.current_system_id_safe()
	for i in _fleet.ships.size():
		var fs := _fleet.ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.docked_system_id == current_sys:
			if i == _fleet.active_index:
				continue
			# Use saved position if available, otherwise fall back to station + random
			var saved_pos: Variant = null
			if fs.last_known_pos.size() == 3:
				saved_pos = FloatingOrigin.to_local_pos(fs.last_known_pos)
			# Reset to DOCKED temporarily so deploy_ship can work
			fs.deployment_state = FleetShip.DeploymentState.DOCKED
			deploy_ship(i, fs.deployed_command, fs.deployed_command_params, saved_pos)


func _on_fleet_npc_died(fleet_index: int, _npc: ShipController) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs := _fleet.ships[fleet_index]
	fs.deployment_state = FleetShip.DeploymentState.DESTROYED
	fs.deployed_npc_id = &""
	fs.deployed_command = &""
	fs.deployed_command_params = {}
	_deployed_ships.erase(fleet_index)

	_fleet.fleet_changed.emit()

	# Notify squadron manager
	var sq_mgr := GameManager.get_node_or_null("SquadronManager") as SquadronManager
	if sq_mgr:
		sq_mgr.on_member_destroyed(fleet_index)

	# Toast notification
	if GameManager._notif:
		GameManager._notif.fleet.lost(fs.custom_name)



func update_entity_extra(fleet_index: int, key: String, value: Variant) -> void:
	if _fleet == null or fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return
	var fs := _fleet.ships[fleet_index]
	if fs.deployed_npc_id == &"":
		return
	var ent := EntityRegistry.get_entity(String(fs.deployed_npc_id))
	if not ent.is_empty():
		ent["extra"][key] = value


func get_deployed_npc(fleet_index: int) -> ShipController:
	if _deployed_ships.has(fleet_index):
		var npc_ref = _deployed_ships[fleet_index]
		if is_instance_valid(npc_ref):
			return npc_ref as ShipController
		_deployed_ships.erase(fleet_index)
	return null


# =========================================================================
# MULTIPLAYER-AWARE PUBLIC API
# =========================================================================
# These methods route through server RPCs when client,
# or execute via NpcAuthority when server.

func request_deploy(fleet_index: int, cmd: StringName, params: Dictionary = {}) -> void:
	if _is_multiplayer_client():
		var params_json := JSON.stringify(params) if not params.is_empty() else ""
		NetworkManager._rpc_request_fleet_deploy.rpc_id(1, fleet_index, String(cmd), params_json)
	else:
		# Server: go through NpcAuthority for proper broadcasting
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			npc_auth.handle_fleet_deploy_request(NetworkManager.local_peer_id, fleet_index, cmd, params)
		else:
			deploy_ship(fleet_index, cmd, params)


func request_retrieve(fleet_index: int) -> void:
	if _is_multiplayer_client():
		NetworkManager._rpc_request_fleet_retrieve.rpc_id(1, fleet_index)
	else:
		# Server: go through NpcAuthority for proper broadcasting
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			npc_auth.handle_fleet_retrieve_request(NetworkManager.local_peer_id, fleet_index)
		else:
			retrieve_ship(fleet_index)


func request_change_command(fleet_index: int, cmd: StringName, params: Dictionary = {}) -> void:
	if _is_multiplayer_client():
		var params_json := JSON.stringify(params) if not params.is_empty() else ""
		NetworkManager._rpc_request_fleet_command.rpc_id(1, fleet_index, String(cmd), params_json)
	else:
		# Server: go through NpcAuthority for proper broadcasting
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			npc_auth.handle_fleet_command_request(NetworkManager.local_peer_id, fleet_index, cmd, params)
		else:
			change_command(fleet_index, cmd, params)


func _is_multiplayer_client() -> bool:
	return NetworkManager.is_connected_to_server() and not NetworkManager.is_server()


## Client-side: apply fleet status from server on reconnect.
## alive = [{ fleet_index, npc_id }], deaths = [{ fleet_index, npc_id, death_time }]
func apply_reconnect_fleet_status(alive: Array, deaths: Array) -> void:
	if _fleet == null:
		return

	# Mark ships that died while we were offline
	for death in deaths:
		var fi: int = int(death.get("fleet_index", -1))
		if fi >= 0 and fi < _fleet.ships.size():
			var fs := _fleet.ships[fi]
			if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
				fs.deployment_state = FleetShip.DeploymentState.DESTROYED
				fs.deployed_npc_id = &""
				fs.deployed_command = &""
				fs.deployed_command_params = {}
				if GameManager._notif:
					GameManager._notif.fleet.lost(fs.custom_name)

	# Confirm alive ships — restore positions from server
	for entry in alive:
		var fi: int = int(entry.get("fleet_index", -1))
		if fi >= 0 and fi < _fleet.ships.size():
			var px: float = float(entry.get("pos_x", 0.0))
			var py: float = float(entry.get("pos_y", 0.0))
			var pz: float = float(entry.get("pos_z", 0.0))
			if px != 0.0 or py != 0.0 or pz != 0.0:
				_fleet.ships[fi].last_known_pos = [px, py, pz]

	# DO NOT mark missing ships as DESTROYED — they may be in a different
	# system or the server may not have loaded them yet.

	_fleet.fleet_changed.emit()
	print("FleetDeploy: Reconnect status — %d alive, %d died offline" % [alive.size(), deaths.size()])
