class_name NpcFleetBackend
extends RefCounted

# =============================================================================
# NPC Fleet Backend - Backend sync, fleet persistence (server → Go backend).
# Extracted from NpcAuthority. Runs as a RefCounted sub-object.
# Includes exponential backoff retry logic for failed sync operations.
# =============================================================================

const FLEET_SYNC_INTERVAL: float = 30.0
const MAX_RETRY_COUNT: int = 3
const RETRY_BASE_DELAY: float = 1.0  # 1s, 2s, 4s

var _fleet_sync_timer: float = FLEET_SYNC_INTERVAL
var _fleet_backend_loaded: bool = false
var _pending_reconnects: Array = []  # [{uuid, pid}] queued while backend fleet loads
var _backend_client: ServerBackendClient = null

# Retry queue for failed sync operations
var _failed_updates: Array = []  # Array of { "data": Array, "retries": int, "next_retry": float }

var _auth: NpcAuthority = null


func setup(auth: NpcAuthority, backend_client: ServerBackendClient) -> void:
	_auth = auth
	_backend_client = backend_client
	_fleet_sync_timer = FLEET_SYNC_INTERVAL


func tick(delta: float) -> void:
	_fleet_sync_timer -= delta
	if _fleet_sync_timer <= 0.0:
		_fleet_sync_timer = FLEET_SYNC_INTERVAL
		_sync_fleet_to_backend()

	# Retry failed updates
	if not _failed_updates.is_empty():
		_process_retry_queue()


## Collect positions/health of all fleet NPCs and batch-sync to backend.
func _sync_fleet_to_backend() -> void:
	if _backend_client == null or _auth._fleet._fleet_npcs.is_empty():
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr == null:
		return

	var updates: Array = []
	for npc_id in _auth._fleet._fleet_npcs:
		var fleet_info: Dictionary = _auth._fleet._fleet_npcs[npc_id]
		var uuid: String = fleet_info.get("owner_uuid", "")
		if uuid == "":
			continue
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data == null or lod_data.is_dead:
			continue
		var upos = FloatingOrigin.to_universe_pos(lod_data.position)
		var cmd: String = fleet_info.get("command", "")
		var cmd_params: Dictionary = fleet_info.get("command_params", {})
		if is_instance_valid(lod_data.node_ref):
			var bridge = lod_data.node_ref.get_node_or_null("FleetAICommand")
			if bridge:
				cmd = String(bridge.command)
				fleet_info["command"] = cmd
				cmd_params = bridge.command_params
				fleet_info["command_params"] = cmd_params
		updates.append({
			"player_id": uuid,
			"fleet_index": fleet_info.get("fleet_index", -1),
			"pos_x": upos[0],
			"pos_y": upos[1],
			"pos_z": upos[2],
			"hull_ratio": lod_data.hull_ratio,
			"shield_ratio": lod_data.shield_ratio,
			"command": cmd,
			"command_params": cmd_params,
		})

	if updates.is_empty():
		return

	var ok: bool = await _backend_client.sync_fleet_positions(updates)
	if not ok:
		push_warning("NpcAuthority: Fleet position sync failed (%d updates) — queuing retry" % updates.size())
		_failed_updates.append({ "data": updates, "retries": 0, "next_retry": Time.get_ticks_msec() / 1000.0 + RETRY_BASE_DELAY })


## Report a fleet NPC death to the backend with retry.
func report_fleet_death_to_backend(uuid: String, fleet_index: int) -> void:
	if _backend_client == null or uuid == "":
		return
	var ok: bool = await _backend_client.report_fleet_death(uuid, fleet_index)
	if not ok:
		push_error("NpcAuthority: Fleet death NOT persisted for %s index %d — will retry" % [uuid, fleet_index])
		# Queue a single-item retry
		_failed_updates.append({
			"data": [{"type": "death", "player_id": uuid, "fleet_index": fleet_index}],
			"retries": 0,
			"next_retry": Time.get_ticks_msec() / 1000.0 + RETRY_BASE_DELAY,
		})


## Process retry queue with exponential backoff.
func _process_retry_queue() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []

	for i in _failed_updates.size():
		var entry: Dictionary = _failed_updates[i]
		if now < entry["next_retry"]:
			continue
		if entry["retries"] >= MAX_RETRY_COUNT:
			push_error("NpcAuthority: Giving up on backend sync after %d retries" % MAX_RETRY_COUNT)
			to_remove.append(i)
			continue

		entry["retries"] += 1
		var delay: float = RETRY_BASE_DELAY * pow(2.0, entry["retries"])
		entry["next_retry"] = now + delay

		# Determine retry type
		var data: Array = entry["data"]
		if not data.is_empty() and data[0].has("type") and data[0]["type"] == "death":
			var d: Dictionary = data[0]
			var ok: bool = await _backend_client.report_fleet_death(d["player_id"], d["fleet_index"])
			if ok:
				to_remove.append(i)
		else:
			var ok: bool = await _backend_client.sync_fleet_positions(data)
			if ok:
				to_remove.append(i)

	# Remove resolved entries (reverse order)
	to_remove.reverse()
	for idx in to_remove:
		_failed_updates.remove_at(idx)


## Load previously deployed fleet ships from the backend on server startup.
func load_deployed_fleet_ships_from_backend() -> void:
	if _backend_client == null:
		_fleet_backend_loaded = true
		_process_pending_reconnects()
		return

	var ships: Array = await _backend_client.get_deployed_fleet_ships()
	if ships.is_empty():
		print("NpcAuthority: No deployed fleet ships to restore from backend")
		_fleet_backend_loaded = true
		_process_pending_reconnects()
		return

	var universe: Node3D = GameManager.universe_node
	if universe == null:
		push_warning("NpcAuthority: No Universe node — cannot restore fleet ships")
		_fleet_backend_loaded = true
		_process_pending_reconnects()
		return

	var restored: int = 0
	print("NpcAuthority: Restoring %d deployed fleet ships from backend..." % ships.size())
	for ship_data in ships:
		var player_id: String = ship_data.get("player_id", "")
		var fleet_index: int = int(ship_data.get("fleet_index", -1))
		var ship_id: String = ship_data.get("ship_id", "")
		var system_id: int = int(ship_data.get("system_id", 0))
		var pos_x: float = float(ship_data.get("pos_x", 0.0))
		var pos_y: float = float(ship_data.get("pos_y", 0.0))
		var pos_z: float = float(ship_data.get("pos_z", 0.0))
		var hull: float = float(ship_data.get("hull_ratio", 1.0))
		var shield: float = float(ship_data.get("shield_ratio", 1.0))
		var command: String = ship_data.get("command", "")
		var faction: StringName = &"player_fleet"

		var effective_ship_id := StringName(ship_id)
		if ShipRegistry.get_ship_data(effective_ship_id) == null:
			push_warning("NpcAuthority: Fleet restore — ship '%s' is retired, using default '%s'" % [ship_id, Constants.DEFAULT_SHIP_ID])
			effective_ship_id = Constants.DEFAULT_SHIP_ID

		var spawn_pos := Vector3(pos_x, pos_y, pos_z)
		var npc = ShipFactory.spawn_npc_ship(effective_ship_id, &"balanced", spawn_pos, universe, faction)
		if npc == null:
			push_error("NpcAuthority: Fleet ship restore FAILED for %s" % effective_ship_id)
			continue

		var npc_id := StringName(npc.name)

		_auth.register_npc(npc_id, system_id, effective_ship_id, faction)

		_auth._fleet._fleet_npcs[npc_id] = { "owner_uuid": player_id, "owner_pid": -1, "fleet_index": fleet_index, "command": command, "command_params": {} }
		if not _auth._fleet._fleet_npcs_by_owner.has(player_id):
			_auth._fleet._fleet_npcs_by_owner[player_id] = []
		_auth._fleet._fleet_npcs_by_owner[player_id].append(npc_id)

		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			var lod_data = lod_mgr.get_ship_data(npc_id)
			if lod_data:
				lod_data.hull_ratio = hull
				lod_data.shield_ratio = shield
				lod_data.fleet_index = fleet_index

		_auth._broadcaster.connect_npc_fire_relay(npc_id, npc)

		if command != "":
			var raw_params = ship_data.get("command_params", {})
			var cmd_params: Dictionary = raw_params if raw_params is Dictionary else {}
			if command == "mine" and cmd_params.get("center_x", 0.0) == 0.0 and cmd_params.get("center_z", 0.0) == 0.0:
				cmd_params = {"center_x": pos_x, "center_z": pos_z, "resource_filter": []}

			var bridge = FleetAICommand.new()
			bridge.name = "FleetAICommand"
			bridge.fleet_index = fleet_index
			bridge.command = StringName(command)
			bridge.command_params = cmd_params
			npc.add_child(bridge)

			if command == "mine":
				var mining_behavior = AIMiningBehavior.new()
				mining_behavior.name = "AIMiningBehavior"
				mining_behavior.fleet_index = fleet_index
				npc.add_child(mining_behavior)

			_auth._fleet._fleet_npcs[npc_id]["command_params"] = cmd_params

		restored += 1

	print("NpcAuthority: Restored %d fleet NPCs as real nodes from backend" % restored)
	_fleet_backend_loaded = true
	_process_pending_reconnects()


## Process any reconnections that were queued while backend fleet was loading.
func _process_pending_reconnects() -> void:
	if _pending_reconnects.is_empty():
		return
	print("NpcAuthority: Processing %d pending reconnects" % _pending_reconnects.size())
	for entry in _pending_reconnects:
		_auth._fleet.send_fleet_reconnect_status(entry["uuid"], entry["pid"])
	_pending_reconnects.clear()
