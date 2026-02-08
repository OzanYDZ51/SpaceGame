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
				_on_npc_killed(npc_id, sender_pid)
	else:
		# Data-only NPC (LOD2/3) — apply damage to ratios
		if lod_data.shield_ratio > 0.0:
			lod_data.shield_ratio = maxf(lod_data.shield_ratio - claimed_damage * 0.008, 0.0)
		else:
			lod_data.hull_ratio = maxf(lod_data.hull_ratio - claimed_damage * 0.012, 0.0)
		if lod_data.hull_ratio <= 0.0:
			lod_data.is_dead = true
			_on_npc_killed(npc_id, sender_pid)


func _on_npc_killed(npc_id: StringName, killer_pid: int) -> void:
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

	# Broadcast death to all peers in the system
	broadcast_npc_death(npc_id, killer_pid, death_pos, loot, system_id)

	# Unregister from NPC authority
	unregister_npc(npc_id)

	# Unregister from LOD
	if lod_mgr:
		lod_mgr.unregister_ship(npc_id)


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
