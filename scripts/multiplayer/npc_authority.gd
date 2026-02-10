class_name NpcAuthority
extends Node

# =============================================================================
# NPC Authority - Server-side NPC management and combat validation.
# Runs ONLY on the server (listen-server host or dedicated).
# - Registers/unregisters NPCs per system
# - Batches NPC states and broadcasts to clients in the same system
# - Validates hit claims from clients
# - Broadcasts NPC deaths + loot
# =============================================================================

const BATCH_INTERVAL: float = 0.1  # 10Hz NPC state sync
const SLOW_SYNC_INTERVAL: float = 0.5  # 2Hz for distant NPCs
const FULL_SYNC_DISTANCE: float = 5000.0  # <5km = full sync
const MAX_SYNC_DISTANCE: float = 15000.0  # 5-15km = slow sync
const HIT_VALIDATION_RANGE: float = 5000.0
const HIT_DAMAGE_TOLERANCE: float = 0.5  # ±50% damage variance allowed

var _active: bool = false
var _batch_timer: float = 0.0
var _slow_batch_timer: float = 0.0

# npc_id -> { system_id, ship_id, faction, node_ref (if LOD0/1) }
var _npcs: Dictionary = {}
# system_id -> Array[StringName] npc_ids
var _npcs_by_system: Dictionary = {}

# Fleet NPC tracking: npc_id -> { owner_pid, fleet_index }
var _fleet_npcs: Dictionary = {}
# owner_pid -> Array[StringName] npc_ids
var _fleet_npcs_by_owner: Dictionary = {}


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if NetworkManager.is_server() and not _active:
		_active = true
		print("NpcAuthority: Activated (server mode)")


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_batch_timer -= delta
	_slow_batch_timer -= delta

	var do_full := _batch_timer <= 0.0
	var do_slow := _slow_batch_timer <= 0.0

	if do_full:
		_batch_timer = BATCH_INTERVAL
	if do_slow:
		_slow_batch_timer = SLOW_SYNC_INTERVAL

	if do_full or do_slow:
		_broadcast_npc_states(do_full, do_slow)


# =========================================================================
# NPC REGISTRATION
# =========================================================================

func register_npc(npc_id: StringName, system_id: int, ship_id: StringName, faction: StringName) -> void:
	_npcs[npc_id] = {
		"system_id": system_id,
		"ship_id": ship_id,
		"faction": faction,
	}
	if not _npcs_by_system.has(system_id):
		_npcs_by_system[system_id] = []
	var sys_list: Array = _npcs_by_system[system_id]
	if not sys_list.has(npc_id):
		sys_list.append(npc_id)


func unregister_npc(npc_id: StringName) -> void:
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]
	var sys_id: int = info.get("system_id", -1)
	if _npcs_by_system.has(sys_id):
		var sys_list: Array = _npcs_by_system[sys_id]
		sys_list.erase(npc_id)
		if sys_list.is_empty():
			_npcs_by_system.erase(sys_id)
	_npcs.erase(npc_id)


func clear_system_npcs(system_id: int) -> void:
	if not _npcs_by_system.has(system_id):
		return
	var ids: Array = _npcs_by_system[system_id].duplicate()
	for npc_id in ids:
		_npcs.erase(npc_id)
	_npcs_by_system.erase(system_id)


## Notify all peers in a system that an NPC has spawned.
func notify_spawn_to_peers(npc_id: StringName, system_id: int) -> void:
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]

	# Build spawn state from LOD data
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

	var spawn_dict := {
		"nid": String(npc_id),
		"sid": String(info.get("ship_id", "")),
		"fac": String(info.get("faction", "hostile")),
		"px": 0.0, "py": 0.0, "pz": 0.0,
	}
	if lod_data:
		var upos := FloatingOrigin.to_universe_pos(lod_data.position)
		spawn_dict["px"] = upos[0]
		spawn_dict["py"] = upos[1]
		spawn_dict["pz"] = upos[2]

	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == 1 and not NetworkManager.is_dedicated_server:
			# Host — deliver locally
			NetworkManager.npc_spawned.emit(spawn_dict)
		else:
			NetworkManager._rpc_npc_spawned.rpc_id(pid, spawn_dict)


## Send all NPC spawns for a system to a specific peer (join mid-combat).
func send_all_npcs_to_peer(peer_id: int, system_id: int) -> void:
	if not _npcs_by_system.has(system_id):
		return

	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	var npc_ids: Array = _npcs_by_system[system_id]

	for npc_id in npc_ids:
		if not _npcs.has(npc_id):
			continue
		var info: Dictionary = _npcs[npc_id]
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

		var spawn_dict := {
			"nid": String(npc_id),
			"sid": String(info.get("ship_id", "")),
			"fac": String(info.get("faction", "hostile")),
			"px": 0.0, "py": 0.0, "pz": 0.0,
		}
		if lod_data:
			var upos := FloatingOrigin.to_universe_pos(lod_data.position)
			spawn_dict["px"] = upos[0]
			spawn_dict["py"] = upos[1]
			spawn_dict["pz"] = upos[2]
			spawn_dict["hull"] = lod_data.hull_ratio
			spawn_dict["shd"] = lod_data.shield_ratio

		if peer_id == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.npc_spawned.emit(spawn_dict)
		else:
			NetworkManager._rpc_npc_spawned.rpc_id(peer_id, spawn_dict)


# =========================================================================
# STATE BROADCASTING
# =========================================================================

func _broadcast_npc_states(full_sync: bool, slow_sync: bool) -> void:
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr == null:
		return

	# Group peers by system
	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate: NetworkState = NetworkManager.peers[pid]
		if not peers_by_sys.has(pstate.system_id):
			peers_by_sys[pstate.system_id] = []
		peers_by_sys[pstate.system_id].append(pid)

	for system_id in _npcs_by_system:
		if not peers_by_sys.has(system_id):
			continue

		var peer_ids: Array = peers_by_sys[system_id]
		var npc_ids: Array = _npcs_by_system[system_id]

		# Build batch per peer (distance-filtered)
		for pid in peer_ids:
			var pstate: NetworkState = NetworkManager.peers.get(pid)
			if pstate == null:
				continue
			var peer_pos := FloatingOrigin.to_local_pos([pstate.pos_x, pstate.pos_y, pstate.pos_z])

			var batch: Array = []
			for npc_id in npc_ids:
				var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
				if lod_data == null or lod_data.is_dead:
					continue

				var dist := peer_pos.distance_to(lod_data.position)
				if dist <= FULL_SYNC_DISTANCE and full_sync:
					batch.append(_build_npc_state_dict(npc_id, lod_data))
				elif dist <= MAX_SYNC_DISTANCE and slow_sync:
					batch.append(_build_npc_state_dict(npc_id, lod_data))

			if batch.is_empty():
				continue

			if pid == 1 and not NetworkManager.is_dedicated_server:
				NetworkManager.npc_batch_received.emit(batch)
			else:
				NetworkManager._rpc_npc_batch.rpc_id(pid, batch)


func _build_npc_state_dict(npc_id: StringName, lod_data: ShipLODData) -> Dictionary:
	var upos := FloatingOrigin.to_universe_pos(lod_data.position)
	var rot_rad := lod_data.rotation_basis.get_euler()
	var rot_deg := Vector3(rad_to_deg(rot_rad.x), rad_to_deg(rot_rad.y), rad_to_deg(rot_rad.z))

	# If the NPC has a node, use its rotation_degrees directly (more accurate)
	if lod_data.node_ref and is_instance_valid(lod_data.node_ref):
		rot_deg = lod_data.node_ref.rotation_degrees

	return {
		"nid": String(npc_id),
		"sid": String(lod_data.ship_id),
		"fac": String(lod_data.faction),
		"px": upos[0],
		"py": upos[1],
		"pz": upos[2],
		"vx": lod_data.velocity.x,
		"vy": lod_data.velocity.y,
		"vz": lod_data.velocity.z,
		"rx": rot_deg.x,
		"ry": rot_deg.y,
		"rz": rot_deg.z,
		"hull": lod_data.hull_ratio,
		"shd": lod_data.shield_ratio,
		"thr": 0.5,
		"ai": lod_data.ai_state,
		"tid": String(lod_data.ai_target_id),
		"t": Time.get_ticks_msec() / 1000.0,
	}


# =========================================================================
# COMBAT VALIDATION
# =========================================================================

## Server receives a fire event from a client — relay to other clients.
func relay_fire_event(sender_pid: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not _active:
		return

	var sender_state: NetworkState = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return

	var peers_in_sys := NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.remote_fire_received.emit(sender_pid, weapon_name, fire_pos, fire_dir)
		else:
			NetworkManager._rpc_remote_fire.rpc_id(pid, sender_pid, weapon_name, fire_pos, fire_dir)


## Server validates a hit claim from a client.
func validate_hit_claim(sender_pid: int, target_npc: String, weapon_name: String, claimed_damage: float, hit_dir: Array) -> void:
	if not _active:
		return

	var npc_id := StringName(target_npc)

	# 1. NPC exists and is alive
	if not _npcs.has(npc_id):
		return

	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr == null:
		return

	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
	if lod_data == null or lod_data.is_dead:
		return

	# 2. Distance check: peer must be within range
	var sender_state: NetworkState = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peer_pos := FloatingOrigin.to_local_pos([sender_state.pos_x, sender_state.pos_y, sender_state.pos_z])
	var dist := peer_pos.distance_to(lod_data.position)
	if dist > HIT_VALIDATION_RANGE:
		print("NpcAuthority: Hit rejected — peer %d too far (%.0fm)" % [sender_pid, dist])
		return

	# 3. Damage within weapon bounds (±50%)
	var weapon := WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon:
		var expected_dmg: float = weapon.damage_per_hit
		if claimed_damage > expected_dmg * (1.0 + HIT_DAMAGE_TOLERANCE) or claimed_damage < 0.0:
			print("NpcAuthority: Hit rejected — damage %.1f out of bounds for %s" % [claimed_damage, weapon_name])
			return

	# 4. Apply damage on the server's NPC
	var hit_dir_vec := Vector3(hit_dir[0] if hit_dir.size() > 0 else 0.0,
		hit_dir[1] if hit_dir.size() > 1 else 0.0,
		hit_dir[2] if hit_dir.size() > 2 else 0.0)

	# If the NPC has a node (LOD0/1), apply via HealthSystem
	# For LOD0/1: apply_damage triggers ship_destroyed → ship_factory lambda handles
	# broadcast + unregister (checks _npcs.has to avoid double broadcast).
	# We call _on_npc_killed to broadcast with correct killer_pid BEFORE the lambda runs.
	if lod_data.node_ref and is_instance_valid(lod_data.node_ref):
		var health := lod_data.node_ref.get_node_or_null("HealthSystem") as HealthSystem
		if health:
			health.apply_damage(claimed_damage, &"thermal", hit_dir_vec, null)
			lod_data.hull_ratio = health.get_hull_ratio()
			lod_data.shield_ratio = health.get_total_shield_ratio()
			if health.is_dead():
				lod_data.is_dead = true
				_on_npc_killed(npc_id, sender_pid, weapon_name)
	else:
		# Data-only NPC (LOD2/3) — apply damage to ratios
		if lod_data.shield_ratio > 0.0:
			lod_data.shield_ratio = maxf(lod_data.shield_ratio - claimed_damage * 0.008, 0.0)
		else:
			lod_data.hull_ratio = maxf(lod_data.hull_ratio - claimed_damage * 0.012, 0.0)
		if lod_data.hull_ratio <= 0.0:
			lod_data.is_dead = true
			_on_npc_killed(npc_id, sender_pid, weapon_name)


func _on_npc_killed(npc_id: StringName, killer_pid: int, weapon_name: String = "") -> void:
	if not _npcs.has(npc_id):
		return

	var info: Dictionary = _npcs[npc_id]
	var system_id: int = info.get("system_id", -1)

	# Get death position
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	var death_pos: Array = [0.0, 0.0, 0.0]
	if lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			death_pos = FloatingOrigin.to_universe_pos(lod_data.position)

	# Roll loot from ship class
	var ship_data := ShipRegistry.get_ship_data(StringName(info.get("ship_id", "")))
	var loot: Array = []
	if ship_data:
		loot = LootTable.roll_drops(ship_data.ship_class)

	# Report kill to Discord via EventReporter
	_report_kill_event(killer_pid, ship_data, weapon_name, system_id)

	# Broadcast death to all peers in the system
	broadcast_npc_death(npc_id, killer_pid, death_pos, loot, system_id)

	# Unregister from NPC authority
	unregister_npc(npc_id)

	# Unregister from LOD
	if lod_mgr:
		lod_mgr.unregister_ship(npc_id)


func _report_kill_event(killer_pid: int, ship_data: ShipData, weapon_name: String, system_id: int) -> void:
	var reporter := GameManager.get_node_or_null("EventReporter") as EventReporter
	if reporter == null:
		return

	# Killer name
	var killer_name: String = "Pilote"
	if NetworkManager.peers.has(killer_pid):
		killer_name = NetworkManager.peers[killer_pid].player_name

	# Victim name
	var victim_name: String = "NPC"
	if ship_data:
		victim_name = ship_data.ship_name

	# Weapon display name
	var weapon_display: String = weapon_name
	if weapon_name != "":
		var w := WeaponRegistry.get_weapon(StringName(weapon_name))
		if w:
			weapon_display = String(w.weapon_name) if w.weapon_name != &"" else weapon_name

	# System name
	var system_name: String = "Unknown"
	if GameManager._galaxy:
		system_name = GameManager._galaxy.get_system_name(system_id)

	reporter.report_kill(killer_name, victim_name, weapon_display, system_name, system_id)


## Broadcast NPC death to all peers in the NPC's system.
func broadcast_npc_death(npc_id: StringName, killer_pid: int, death_pos: Array, loot: Array, system_id: int = -1) -> void:
	if system_id < 0 and _npcs.has(npc_id):
		system_id = _npcs[npc_id].get("system_id", -1)

	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.npc_died.emit(String(npc_id), killer_pid, death_pos, loot)
		else:
			NetworkManager._rpc_npc_died.rpc_id(pid, String(npc_id), killer_pid, death_pos, loot)

	# Clean up fleet tracking if this was a fleet NPC
	_unregister_fleet_npc(npc_id)


# =========================================================================
# FLEET NPC MANAGEMENT
# =========================================================================

func register_fleet_npc(npc_id: StringName, owner_pid: int, fleet_index: int) -> void:
	_fleet_npcs[npc_id] = { "owner_pid": owner_pid, "fleet_index": fleet_index }
	if not _fleet_npcs_by_owner.has(owner_pid):
		_fleet_npcs_by_owner[owner_pid] = []
	var owner_list: Array = _fleet_npcs_by_owner[owner_pid]
	if not owner_list.has(npc_id):
		owner_list.append(npc_id)


func _unregister_fleet_npc(npc_id: StringName) -> void:
	if not _fleet_npcs.has(npc_id):
		return
	var info: Dictionary = _fleet_npcs[npc_id]
	var owner_pid: int = info.get("owner_pid", -1)
	if _fleet_npcs_by_owner.has(owner_pid):
		var owner_list: Array = _fleet_npcs_by_owner[owner_pid]
		owner_list.erase(npc_id)
		if owner_list.is_empty():
			_fleet_npcs_by_owner.erase(owner_pid)
	_fleet_npcs.erase(npc_id)


func is_fleet_npc(npc_id: StringName) -> bool:
	return _fleet_npcs.has(npc_id)


func get_fleet_npc_owner(npc_id: StringName) -> int:
	if _fleet_npcs.has(npc_id):
		return _fleet_npcs[npc_id].get("owner_pid", -1)
	return -1


## Server handles deploy request from a client (or host).
func handle_fleet_deploy_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary) -> void:
	if not _active:
		return

	# Server-side: execute the deploy via FleetDeploymentManager
	var fleet_mgr := GameManager.get_node_or_null("FleetDeploymentManager") as FleetDeploymentManager
	if fleet_mgr == null:
		return

	# Only the host (pid=1) has fleet data on this server instance.
	# Remote client fleet deploy requires per-player fleet storage (future).
	if sender_pid != 1 and not NetworkManager.is_dedicated_server:
		push_warning("NpcAuthority: Fleet deploy from remote client pid=%d rejected — server lacks per-player fleet data" % sender_pid)
		return

	var success := fleet_mgr.deploy_ship(fleet_index, cmd, params)
	if not success:
		return

	# Get the spawned NPC info
	var fleet: PlayerFleet = GameManager.player_fleet
	if fleet == null or fleet_index >= fleet.ships.size():
		return
	var fs := fleet.ships[fleet_index]
	var npc_id := fs.deployed_npc_id

	# Register as fleet NPC
	register_fleet_npc(npc_id, sender_pid, fleet_index)

	# Build spawn data for broadcast
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	var spawn_data := {
		"sid": String(fs.ship_id),
		"fac": "player_fleet",
		"cmd": String(cmd),
		"owner_name": _get_peer_name(sender_pid),
	}
	if lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			var upos := FloatingOrigin.to_universe_pos(lod_data.position)
			spawn_data["px"] = upos[0]
			spawn_data["py"] = upos[1]
			spawn_data["pz"] = upos[2]

	# Also register with standard NPC authority for state sync
	var sys_id: int = GameManager.current_system_id_safe()
	register_npc(npc_id, sys_id, StringName(fs.ship_id), &"player_fleet")

	# Broadcast to all peers in system
	_broadcast_fleet_event_deploy(sender_pid, fleet_index, npc_id, spawn_data, sys_id)

	# Notify spawn for NPC state sync
	notify_spawn_to_peers(npc_id, sys_id)


## Server handles retrieve request from a client (or host).
func handle_fleet_retrieve_request(sender_pid: int, fleet_index: int) -> void:
	if not _active:
		return

	if sender_pid != 1 and not NetworkManager.is_dedicated_server:
		push_warning("NpcAuthority: Fleet retrieve from remote client pid=%d rejected" % sender_pid)
		return

	var fleet_mgr := GameManager.get_node_or_null("FleetDeploymentManager") as FleetDeploymentManager
	if fleet_mgr == null:
		return

	var fleet: PlayerFleet = GameManager.player_fleet
	if fleet == null or fleet_index >= fleet.ships.size():
		return
	var fs := fleet.ships[fleet_index]
	var npc_id := fs.deployed_npc_id
	var sys_id: int = GameManager.current_system_id_safe()

	var success := fleet_mgr.retrieve_ship(fleet_index)
	if not success:
		return

	# Clean up NPC authority tracking
	unregister_npc(npc_id)
	_unregister_fleet_npc(npc_id)

	# Broadcast retrieval to all peers in system
	_broadcast_fleet_event_retrieve(sender_pid, fleet_index, npc_id, sys_id)


## Server handles command change request from a client (or host).
func handle_fleet_command_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary) -> void:
	if not _active:
		return

	if sender_pid != 1 and not NetworkManager.is_dedicated_server:
		push_warning("NpcAuthority: Fleet command from remote client pid=%d rejected" % sender_pid)
		return

	var fleet_mgr := GameManager.get_node_or_null("FleetDeploymentManager") as FleetDeploymentManager
	if fleet_mgr == null:
		return

	var fleet: PlayerFleet = GameManager.player_fleet
	if fleet == null or fleet_index >= fleet.ships.size():
		return
	var fs := fleet.ships[fleet_index]
	var npc_id := fs.deployed_npc_id
	var sys_id: int = GameManager.current_system_id_safe()

	var success := fleet_mgr.change_command(fleet_index, cmd, params)
	if not success:
		return

	# Broadcast command change to all peers in system
	_broadcast_fleet_event_command(sender_pid, fleet_index, npc_id, cmd, params, sys_id)


func _broadcast_fleet_event_deploy(owner_pid: int, fleet_idx: int, npc_id: StringName, spawn_data: Dictionary, system_id: int) -> void:
	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue  # Owner already sees it locally
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.fleet_ship_deployed.emit(owner_pid, fleet_idx, String(npc_id), spawn_data)
		else:
			NetworkManager._rpc_fleet_deployed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), spawn_data)


func _broadcast_fleet_event_retrieve(owner_pid: int, fleet_idx: int, npc_id: StringName, system_id: int) -> void:
	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.fleet_ship_retrieved.emit(owner_pid, fleet_idx, String(npc_id))
		else:
			NetworkManager._rpc_fleet_retrieved.rpc_id(pid, owner_pid, fleet_idx, String(npc_id))


func _broadcast_fleet_event_command(owner_pid: int, fleet_idx: int, npc_id: StringName, cmd: StringName, params: Dictionary, system_id: int) -> void:
	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.fleet_command_changed.emit(owner_pid, fleet_idx, String(npc_id), String(cmd), params)
		else:
			NetworkManager._rpc_fleet_command_changed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), String(cmd), params)


func _get_peer_name(pid: int) -> String:
	if NetworkManager.peers.has(pid):
		return NetworkManager.peers[pid].player_name
	return "Pilote #%d" % pid


# =========================================================================
# MINING SYNC
# =========================================================================

## Relay a mining beam state to all peers in the sender's system.
func relay_mining_beam(sender_pid: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not _active:
		return
	var sender_state: NetworkState = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peers_in_sys := NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.remote_mining_beam_received.emit(sender_pid, is_active, source_pos, target_pos)
		else:
			NetworkManager._rpc_remote_mining_beam.rpc_id(pid, sender_pid, is_active, source_pos, target_pos)


## Broadcast asteroid depletion to all peers in the system.
func broadcast_asteroid_depleted(asteroid_id: String, system_id: int, sender_pid: int) -> void:
	if not _active:
		return
	var peers_in_sys := NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		if pid == 1 and not NetworkManager.is_dedicated_server:
			NetworkManager.asteroid_depleted_received.emit(asteroid_id)
		else:
			NetworkManager._rpc_receive_asteroid_depleted.rpc_id(pid, asteroid_id)
