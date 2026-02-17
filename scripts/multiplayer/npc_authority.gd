class_name NpcAuthority
extends Node

# =============================================================================
# NPC Authority - Server-side NPC management and combat validation.
# Runs ONLY on the dedicated server.
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

# Asteroid health sync (cooperative mining)
const ASTEROID_HEALTH_BATCH_INTERVAL: float = 0.5  # 2Hz broadcast
const MINING_MAX_DPS: float = 30.0  # Max reasonable mining DPS (tolerance ×1.5 applied)
const ASTEROID_RESPAWN_TIME_CLEANUP: float = 300.0  # 5min stale entry cleanup

var _active: bool = false
var _fleet_backend_loaded: bool = false  # True once _load_deployed_fleet_ships_from_backend() completes
var _pending_reconnects: Array = []  # [{uuid, pid}] queued while backend fleet loads
var _batch_timer: float = 0.0
var _slow_batch_timer: float = 0.0
var _fleet_sync_timer: float = 0.0
const FLEET_SYNC_INTERVAL: float = 30.0
var _backend_client: ServerBackendClient = null

# Asteroid health tracking (server-side, cooperative mining)
var _asteroid_health_timer: float = 0.0
var _asteroid_health: Dictionary = {}    # system_id -> { asteroid_id -> { hp, hm, t } }
var _peer_mining_dps: Dictionary = {}    # peer_id -> { asteroid_id -> { dmg, t0 } }
var _asteroid_health_cleanup_timer: float = 0.0

# npc_id -> { system_id, ship_id, faction, node_ref (if LOD0/1) }
var _npcs: Dictionary = {}
# system_id -> Array[StringName] npc_ids
var _npcs_by_system: Dictionary = {}

# Remote system NPCs: NPCs in systems the server isn't physically in.
# system_id -> Array of npc state dicts (positions stored as system-local coords).
var _remote_npcs: Dictionary = {}
# Peer system tracking: peer_id -> last known system_id (detect system changes).
var _peer_systems: Dictionary = {}

# Encounter respawn tracking: "system_id:encounter_key" -> respawn_unix_timestamp
var _destroyed_encounter_npcs: Dictionary = {}
const ENCOUNTER_RESPAWN_DELAY: float = 300.0  # 5 minutes
var _respawn_cleanup_timer: float = 60.0
var _dead_remote_cleanup_timer: float = 10.0

# Fleet NPC tracking: npc_id -> { owner_uuid, owner_pid, fleet_index }
var _fleet_npcs: Dictionary = {}
# owner_uuid -> Array[StringName] npc_ids (persistent across reconnects)
var _fleet_npcs_by_owner: Dictionary = {}
# owner_uuid -> Array[Dictionary] { fleet_index, npc_id, death_time }
var _fleet_deaths_while_offline: Dictionary = {}


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if NetworkManager.is_server() and not _active:
		_active = true
		# Create backend client for fleet persistence
		_backend_client = ServerBackendClient.new()
		_backend_client.name = "ServerBackendClient"
		add_child(_backend_client)
		_fleet_sync_timer = FLEET_SYNC_INTERVAL
		print("NpcAuthority: Activated (server mode)")
		# Load previously deployed fleet ships from backend (async)
		_load_deployed_fleet_ships_from_backend()


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_batch_timer -= delta
	_slow_batch_timer -= delta
	_fleet_sync_timer -= delta

	# Update remote system NPC positions (simple velocity drift)
	_update_remote_npcs(delta)

	var do_full =_batch_timer <= 0.0
	var do_slow =_slow_batch_timer <= 0.0

	if do_full:
		_batch_timer = BATCH_INTERVAL
	if do_slow:
		_slow_batch_timer = SLOW_SYNC_INTERVAL
		_check_peer_system_changes()

	if do_full or do_slow:
		_broadcast_npc_states(do_full, do_slow)
		_broadcast_remote_npc_states(do_slow)

	# Asteroid health batch broadcast (2Hz)
	_asteroid_health_timer -= delta
	if _asteroid_health_timer <= 0.0:
		_asteroid_health_timer = ASTEROID_HEALTH_BATCH_INTERVAL
		_broadcast_asteroid_health_batch()

	# Periodic stale asteroid health cleanup (every 60s)
	_asteroid_health_cleanup_timer -= delta
	if _asteroid_health_cleanup_timer <= 0.0:
		_asteroid_health_cleanup_timer = 60.0
		_cleanup_stale_asteroid_health()

	# Periodic fleet sync to backend (30s)
	if _fleet_sync_timer <= 0.0:
		_fleet_sync_timer = FLEET_SYNC_INTERVAL
		_sync_fleet_to_backend()

	# Periodic encounter respawn cleanup (every 60s)
	_respawn_cleanup_timer -= delta
	if _respawn_cleanup_timer <= 0.0:
		_respawn_cleanup_timer = 60.0
		_cleanup_expired_respawns()


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
	if _npcs_by_system.has(system_id):
		var ids: Array = _npcs_by_system[system_id].duplicate()
		for npc_id in ids:
			_npcs.erase(npc_id)
		_npcs_by_system.erase(system_id)
	_remote_npcs.erase(system_id)
	clear_system_asteroid_health(system_id)


## Connect NPC weapon_fired signal to relay fire events to remote clients.
func connect_npc_fire_relay(npc_id: StringName, ship_node: Node3D) -> void:
	if not _active or ship_node == null:
		return
	var wm = ship_node.get_node_or_null("WeaponManager")
	if wm == null:
		return
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]
	var sys_id: int = info.get("system_id", -1)
	wm.weapon_fired.connect(func(hardpoint_id: int, weapon_name_str: StringName) -> void:
		_relay_npc_fire(npc_id, sys_id, ship_node, hardpoint_id, weapon_name_str))


func _relay_npc_fire(npc_id: StringName, system_id: int, ship_node: Node3D, hardpoint_id: int, weapon_name_str: StringName) -> void:
	if not _active or ship_node == null or not is_instance_valid(ship_node):
		return
	var wm = ship_node.get_node_or_null("WeaponManager")
	if wm == null or hardpoint_id >= wm.hardpoints.size():
		return
	var hp: Hardpoint = wm.hardpoints[hardpoint_id]
	var muzzle =hp.get_muzzle_transform()
	var fire_pos =FloatingOrigin.to_universe_pos(muzzle.origin)
	var fire_dir =(-muzzle.basis.z).normalized()
	var ship_vel =Vector3.ZERO
	if ship_node is RigidBody3D:
		ship_vel = ship_node.linear_velocity

	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	var dir_arr: Array = [fire_dir.x, fire_dir.y, fire_dir.z, ship_vel.x, ship_vel.y, ship_vel.z]
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_fire.rpc_id(pid, String(npc_id), String(weapon_name_str), fire_pos, dir_arr)


## Notify all peers in a system that an NPC has spawned.
func notify_spawn_to_peers(npc_id: StringName, system_id: int) -> void:
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]

	# Build spawn state from LOD data
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

	var spawn_dict ={
		"nid": String(npc_id),
		"sid": String(info.get("ship_id", "")),
		"fac": String(info.get("faction", "hostile")),
		"px": 0.0, "py": 0.0, "pz": 0.0,
	}
	if lod_data:
		var upos =FloatingOrigin.to_universe_pos(lod_data.position)
		spawn_dict["px"] = upos[0]
		spawn_dict["py"] = upos[1]
		spawn_dict["pz"] = upos[2]

	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_spawned.rpc_id(pid, spawn_dict)


## Send all NPC spawns for a system to a specific peer (join mid-combat).
func send_all_npcs_to_peer(peer_id: int, system_id: int) -> void:
	# Send local system NPCs (managed by LOD manager)
	if _npcs_by_system.has(system_id):
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		var npc_ids: Array = _npcs_by_system[system_id]

		for npc_id in npc_ids:
			if not _npcs.has(npc_id):
				continue
			var info: Dictionary = _npcs[npc_id]
			var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

			var spawn_dict ={
				"nid": String(npc_id),
				"sid": String(info.get("ship_id", "")),
				"fac": String(info.get("faction", "hostile")),
				"px": 0.0, "py": 0.0, "pz": 0.0,
			}
			if lod_data:
				var upos =FloatingOrigin.to_universe_pos(lod_data.position)
				spawn_dict["px"] = upos[0]
				spawn_dict["py"] = upos[1]
				spawn_dict["pz"] = upos[2]
				spawn_dict["hull"] = lod_data.hull_ratio
				spawn_dict["shd"] = lod_data.shield_ratio

			NetworkManager._rpc_npc_spawned.rpc_id(peer_id, spawn_dict)

	# Send remote system NPCs (data-only, not in LOD manager)
	if _remote_npcs.has(system_id):
		for npc_data in _remote_npcs[system_id]:
			NetworkManager._rpc_npc_spawned.rpc_id(peer_id, npc_data)


# =========================================================================
# STATE BROADCASTING
# =========================================================================

func _broadcast_npc_states(full_sync: bool, slow_sync: bool) -> void:
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr == null:
		return

	# Group peers by system
	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate = NetworkManager.peers[pid]
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
			var pstate = NetworkManager.peers.get(pid)
			if pstate == null:
				continue
			var peer_pos =FloatingOrigin.to_local_pos([pstate.pos_x, pstate.pos_y, pstate.pos_z])

			var batch: Array = []
			for npc_id in npc_ids:
				var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
				if lod_data == null or lod_data.is_dead:
					continue
				# Skip mining-docked NPCs (hidden, no position updates needed)
				if lod_data.node_ref and is_instance_valid(lod_data.node_ref) and not lod_data.node_ref.visible:
					continue

				var dist =peer_pos.distance_to(lod_data.position)
				if dist <= FULL_SYNC_DISTANCE and full_sync:
					batch.append(_build_npc_state_dict(npc_id, lod_data))
				elif dist <= MAX_SYNC_DISTANCE and slow_sync:
					batch.append(_build_npc_state_dict(npc_id, lod_data))

			if batch.is_empty():
				continue

			NetworkManager._rpc_npc_batch.rpc_id(pid, batch)


func _build_npc_state_dict(npc_id: StringName, lod_data: ShipLODData) -> Dictionary:
	var upos =FloatingOrigin.to_universe_pos(lod_data.position)
	var rot_rad =lod_data.rotation_basis.get_euler()
	var rot_deg =Vector3(rad_to_deg(rot_rad.x), rad_to_deg(rot_rad.y), rad_to_deg(rot_rad.z))

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

	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return

	var peers_in_sys =NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_remote_fire.rpc_id(pid, sender_pid, weapon_name, fire_pos, fire_dir)


## Server validates a hit claim from a client.
func validate_hit_claim(sender_pid: int, target_npc: String, weapon_name: String, claimed_damage: float, hit_dir: Array) -> void:
	if not _active:
		return

	var npc_id =StringName(target_npc)

	# 1. NPC exists and is alive
	if not _npcs.has(npc_id):
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

	# If NPC is not in the LOD manager, it's a remote system NPC
	if lod_data == null:
		validate_remote_npc_hit(sender_pid, target_npc, claimed_damage, hit_dir)
		return
	if lod_data.is_dead:
		return

	# 2. Distance check: peer must be within range
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peer_pos =FloatingOrigin.to_local_pos([sender_state.pos_x, sender_state.pos_y, sender_state.pos_z])
	var dist =peer_pos.distance_to(lod_data.position)
	if dist > HIT_VALIDATION_RANGE:
		print("NpcAuthority: Hit rejected — peer %d too far (%.0fm)" % [sender_pid, dist])
		return

	# 3. Damage within weapon bounds (±50%)
	var weapon =WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon:
		var expected_dmg: float = weapon.damage_per_hit
		if claimed_damage > expected_dmg * (1.0 + HIT_DAMAGE_TOLERANCE) or claimed_damage < 0.0:
			print("NpcAuthority: Hit rejected — damage %.1f out of bounds for %s" % [claimed_damage, weapon_name])
			return

	# 4. Apply damage on the server's NPC
	var hit_dir_vec =Vector3(hit_dir[0] if hit_dir.size() > 0 else 0.0,
		hit_dir[1] if hit_dir.size() > 1 else 0.0,
		hit_dir[2] if hit_dir.size() > 2 else 0.0)

	var shield_absorbed: bool = false

	# If the NPC has a node (LOD0/1), apply via HealthSystem
	# For LOD0/1: apply_damage triggers ship_destroyed synchronously → ship_factory lambda
	# would broadcast_npc_death with killer_pid=0. We set _player_killing flag so the lambda
	# skips, letting _on_npc_killed handle death with the correct killer_pid.
	if lod_data.node_ref and is_instance_valid(lod_data.node_ref):
		var health = lod_data.node_ref.get_node_or_null("HealthSystem")
		if health:
			_npcs[npc_id]["_player_killing"] = true
			var hit_result =health.apply_damage(claimed_damage, &"thermal", hit_dir_vec, null)
			shield_absorbed = hit_result.get("shield_absorbed", false)
			lod_data.hull_ratio = health.get_hull_ratio()
			lod_data.shield_ratio = health.get_total_shield_ratio()
			if health.is_dead():
				lod_data.is_dead = true
				_on_npc_killed(npc_id, sender_pid, weapon_name)
			elif _npcs.has(npc_id):
				_npcs[npc_id].erase("_player_killing")
	else:
		# Data-only NPC (LOD2/3) — apply damage to ratios
		shield_absorbed = lod_data.shield_ratio > 0.0
		if lod_data.shield_ratio > 0.0:
			lod_data.shield_ratio = maxf(lod_data.shield_ratio - claimed_damage * 0.008, 0.0)
		else:
			lod_data.hull_ratio = maxf(lod_data.hull_ratio - claimed_damage * 0.012, 0.0)
		if lod_data.hull_ratio <= 0.0:
			lod_data.is_dead = true
			_on_npc_killed(npc_id, sender_pid, weapon_name)

	# 5. Broadcast hit effect to other peers (attacker already showed it locally)
	broadcast_hit_effect(target_npc, sender_pid, hit_dir, shield_absorbed, sender_state.system_id)


func _on_npc_killed(npc_id: StringName, killer_pid: int, weapon_name: String = "") -> void:
	if not _npcs.has(npc_id):
		return

	var info: Dictionary = _npcs[npc_id]
	var system_id: int = info.get("system_id", -1)

	# Get death position (from LOD data or remote NPC dict)
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var death_pos: Array = [0.0, 0.0, 0.0]
	if lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			death_pos = FloatingOrigin.to_universe_pos(lod_data.position)
	if death_pos == [0.0, 0.0, 0.0] and _remote_npcs.has(system_id):
		for rnpc in _remote_npcs[system_id]:
			if rnpc.get("nid", "") == String(npc_id):
				death_pos = [rnpc.get("px", 0.0), rnpc.get("py", 0.0), rnpc.get("pz", 0.0)]
				break

	# Roll loot from ship class
	var ship_data =ShipRegistry.get_ship_data(StringName(info.get("ship_id", "")))
	var loot: Array = []
	if ship_data:
		loot = LootTable.roll_drops_for_ship(ship_data)

	# Report kill to Discord via EventReporter
	_report_kill_event(killer_pid, ship_data, weapon_name, system_id)

	# Record encounter NPC death for respawn tracking
	var encounter_key: String = info.get("encounter_key", "")
	if encounter_key != "":
		_destroyed_encounter_npcs[encounter_key] = Time.get_unix_time_from_system() + ENCOUNTER_RESPAWN_DELAY

	# Broadcast death to all peers in the system
	broadcast_npc_death(npc_id, killer_pid, death_pos, loot, system_id)

	# Unregister from NPC authority
	unregister_npc(npc_id)

	# Unregister from LOD
	if lod_mgr:
		lod_mgr.unregister_ship(npc_id)


func _report_kill_event(killer_pid: int, ship_data: ShipData, weapon_name: String, system_id: int) -> void:
	var reporter = GameManager.get_node_or_null("EventReporter")
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
		var w =WeaponRegistry.get_weapon(StringName(weapon_name))
		if w:
			weapon_display = String(w.weapon_name) if w.weapon_name != &"" else weapon_name

	# System name
	var system_name: String = "Unknown"
	if GameManager._galaxy:
		system_name = GameManager._galaxy.get_system_name(system_id)

	reporter.report_kill(killer_name, victim_name, weapon_display, system_name, system_id)


## Broadcast hit effect to all peers in system (except the attacker who showed it locally).
func broadcast_hit_effect(target_id: String, exclude_pid: int, hit_dir: Array, shield_absorbed: bool, system_id: int) -> void:
	if not _active:
		return
	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == exclude_pid:
			continue
		NetworkManager._rpc_hit_effect.rpc_id(pid, target_id, hit_dir, shield_absorbed)


## Broadcast NPC death to all peers in the NPC's system.
func broadcast_npc_death(npc_id: StringName, killer_pid: int, death_pos: Array, loot: Array, system_id: int = -1) -> void:
	if system_id < 0 and _npcs.has(npc_id):
		system_id = _npcs[npc_id].get("system_id", -1)

	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_died.rpc_id(pid, String(npc_id), killer_pid, death_pos, loot)

	# Track death for offline owners + report to backend + clean up fleet tracking
	if _fleet_npcs.has(npc_id):
		var fleet_info: Dictionary = _fleet_npcs[npc_id]
		var owner_uuid: String = fleet_info.get("owner_uuid", "")
		var owner_pid: int = fleet_info.get("owner_pid", -1)
		var fi: int = fleet_info.get("fleet_index", -1)
		# Report death to backend for persistence
		_report_fleet_death_to_backend(owner_uuid, fi)
		# If owner is offline, record death for notification on reconnect
		if owner_uuid != "" and not NetworkManager.peers.has(owner_pid):
			if not _fleet_deaths_while_offline.has(owner_uuid):
				_fleet_deaths_while_offline[owner_uuid] = []
			_fleet_deaths_while_offline[owner_uuid].append({
				"fleet_index": fi,
				"npc_id": String(npc_id),
				"death_time": Time.get_unix_time_from_system(),
			})
	_unregister_fleet_npc(npc_id)


# =========================================================================
# FLEET NPC MANAGEMENT
# =========================================================================

func register_fleet_npc(npc_id: StringName, owner_pid: int, fleet_index: int) -> void:
	var uuid: String = NetworkManager.get_peer_uuid(owner_pid)
	_fleet_npcs[npc_id] = { "owner_uuid": uuid, "owner_pid": owner_pid, "fleet_index": fleet_index }
	var owner_key: String = uuid if uuid != "" else str(owner_pid)
	if not _fleet_npcs_by_owner.has(owner_key):
		_fleet_npcs_by_owner[owner_key] = []
	var owner_list: Array = _fleet_npcs_by_owner[owner_key]
	if not owner_list.has(npc_id):
		owner_list.append(npc_id)


func _unregister_fleet_npc(npc_id: StringName) -> void:
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
	# Fleet NPCs stay alive — just mark owner_pid as -1 (offline)
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				_fleet_npcs[npc_id]["owner_pid"] = -1
	# Clean up mining DPS tracking for this peer
	clean_peer_mining_tracking(old_pid)
	print("NpcAuthority: Player %s (pid=%d) disconnected — fleet NPCs persist" % [uuid, old_pid])


## Called when a player reconnects. Re-associate fleet NPCs and send status.
func on_player_reconnected(uuid: String, new_pid: int) -> void:
	if uuid == "":
		return

	# If backend fleet data hasn't loaded yet, queue this reconnect for later
	if not _fleet_backend_loaded:
		_pending_reconnects.append({"uuid": uuid, "pid": new_pid})
		print("NpcAuthority: Queuing reconnect for %s (pid=%d) — backend fleet not loaded yet" % [uuid, new_pid])
		return

	_send_fleet_reconnect_status(uuid, new_pid)


## Actually build and send the fleet reconnect status.
func _send_fleet_reconnect_status(uuid: String, new_pid: int) -> void:
	# Re-associate owner_pid for all fleet NPCs
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				_fleet_npcs[npc_id]["owner_pid"] = new_pid

	# Build alive fleet status (include positions for reconnect)
	var alive_list: Array = []
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if _fleet_npcs_by_owner.has(uuid):
		for npc_id in _fleet_npcs_by_owner[uuid]:
			if _fleet_npcs.has(npc_id):
				var info: Dictionary = _fleet_npcs[npc_id]
				var entry ={
					"fleet_index": info.get("fleet_index", -1),
					"npc_id": String(npc_id),
				}
				# Include universe position from LOD data
				if lod_mgr:
					var lod_data = lod_mgr.get_ship_data(npc_id)
					if lod_data:
						var upos =FloatingOrigin.to_universe_pos(lod_data.position)
						entry["pos_x"] = upos[0]
						entry["pos_y"] = upos[1]
						entry["pos_z"] = upos[2]
				alive_list.append(entry)

	# Get deaths that happened while offline
	var deaths: Array = _fleet_deaths_while_offline.get(uuid, [])
	_fleet_deaths_while_offline.erase(uuid)

	# Send status to the reconnected client
	_rpc_fleet_reconnect_status.rpc_id(new_pid, alive_list, deaths)

	print("NpcAuthority: Player %s reconnected (pid=%d) — %d alive, %d died offline" % [uuid, new_pid, alive_list.size(), deaths.size()])


## Server -> Client: Fleet status on reconnect (alive NPCs + offline deaths).
@rpc("authority", "reliable")
func _rpc_fleet_reconnect_status(alive: Array, deaths: Array) -> void:
	# Client-side: update local fleet data
	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr:
		fleet_mgr.apply_reconnect_fleet_status(alive, deaths)


## Server handles deploy request from a client (or host).
## ship_data is required for remote clients (ship_id, weapons, equipment, station).
func handle_fleet_deploy_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary, ship_data: Dictionary = {}) -> void:
	if not _active:
		return

	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		return

	var npc_id: StringName
	var ship_id: StringName
	var sys_id: int = GameManager.current_system_id_safe()

	# Spawn NPC using ship_data from RPC
	if ship_data.is_empty():
		push_warning("NpcAuthority: Fleet deploy from pid=%d — no ship_data" % sender_pid)
		return
	var result: Dictionary = _spawn_remote_fleet_npc(sender_pid, fleet_index, cmd, params, ship_data, sys_id)
	if result.is_empty():
		return
	npc_id = result["npc_id"]
	ship_id = StringName(ship_data.get("ship_id", ""))

	# Register as fleet NPC for tracking
	register_fleet_npc(npc_id, sender_pid, fleet_index)

	# Build spawn data for broadcast
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var spawn_data: Dictionary = {
		"sid": String(ship_id),
		"fac": "player_fleet",
		"cmd": String(cmd),
		"owner_name": _get_peer_name(sender_pid),
	}
	if lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			var upos: Array = FloatingOrigin.to_universe_pos(lod_data.position)
			spawn_data["px"] = upos[0]
			spawn_data["py"] = upos[1]
			spawn_data["pz"] = upos[2]

	# Register with NPC authority for state sync
	register_npc(npc_id, sys_id, ship_id, &"player_fleet")

	# Broadcast to all peers in system
	_broadcast_fleet_event_deploy(sender_pid, fleet_index, npc_id, spawn_data, sys_id)

	# Notify spawn for NPC state sync
	notify_spawn_to_peers(npc_id, sys_id)

	# Send confirmation to requesting client
	NetworkManager._rpc_fleet_deploy_confirmed.rpc_id(sender_pid, fleet_index, String(npc_id))


## Server handles retrieve request from a client (or host).
func handle_fleet_retrieve_request(sender_pid: int, fleet_index: int) -> void:
	if not _active:
		return

	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		return

	var sys_id: int = GameManager.current_system_id_safe()

	# Look up NPC by owner + fleet_index
	var npc_id: StringName = _find_fleet_npc_id(sender_pid, fleet_index)
	if npc_id == &"":
		push_warning("NpcAuthority: Fleet retrieve pid=%d idx=%d — NPC not found" % [sender_pid, fleet_index])
		return

	# Despawn the NPC node
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data and lod_data.node_ref and is_instance_valid(lod_data.node_ref):
			EntityRegistry.unregister(String(npc_id))
			lod_data.node_ref.queue_free()
		lod_mgr.unregister_ship(npc_id)

	unregister_npc(npc_id)
	_unregister_fleet_npc(npc_id)
	_broadcast_fleet_event_retrieve(sender_pid, fleet_index, npc_id, sys_id)

	# Send confirmation to requesting client
	NetworkManager._rpc_fleet_retrieve_confirmed.rpc_id(sender_pid, fleet_index)


## Server handles command change request from a client (or host).
func handle_fleet_command_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary) -> void:
	if not _active:
		return

	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr == null:
		return

	var sys_id: int = GameManager.current_system_id_safe()

	# Look up NPC and update its AI
	var npc_id: StringName = _find_fleet_npc_id(sender_pid, fleet_index)
	if npc_id == &"":
		push_warning("NpcAuthority: Fleet command pid=%d idx=%d — NPC not found" % [sender_pid, fleet_index])
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		var lod_data = lod_mgr.get_ship_data(npc_id)
		if lod_data and lod_data.node_ref and is_instance_valid(lod_data.node_ref):
			var npc = lod_data.node_ref
			var bridge = npc.get_node_or_null("FleetAIBridge")
			if bridge:
				bridge.apply_command(cmd, params)
			# Manage AIMiningBehavior lifecycle
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

	_broadcast_fleet_event_command(sender_pid, fleet_index, npc_id, cmd, params, sys_id)

	# Send confirmation to requesting client
	NetworkManager._rpc_fleet_command_confirmed.rpc_id(sender_pid, fleet_index, String(cmd), params)


func _broadcast_fleet_event_deploy(owner_pid: int, fleet_idx: int, npc_id: StringName, spawn_data: Dictionary, system_id: int) -> void:
	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue  # Owner already sees it locally
		NetworkManager._rpc_fleet_deployed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), spawn_data)


func _broadcast_fleet_event_retrieve(owner_pid: int, fleet_idx: int, npc_id: StringName, system_id: int) -> void:
	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		NetworkManager._rpc_fleet_retrieved.rpc_id(pid, owner_pid, fleet_idx, String(npc_id))


func _broadcast_fleet_event_command(owner_pid: int, fleet_idx: int, npc_id: StringName, cmd: StringName, params: Dictionary, system_id: int) -> void:
	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == owner_pid:
			continue
		NetworkManager._rpc_fleet_command_changed.rpc_id(pid, owner_pid, fleet_idx, String(npc_id), String(cmd), params)


func _get_peer_name(pid: int) -> String:
	if NetworkManager.peers.has(pid):
		return NetworkManager.peers[pid].player_name
	return "Pilote #%d" % pid


## Find a fleet NPC ID by owner peer_id and fleet_index.
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
## Returns { "npc_id": StringName } on success, empty dict on failure.
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

	# Spawn NPC via ShipFactory (skip_default_loadout = true)
	var npc = ShipFactory.spawn_npc_ship(ship_id, &"balanced", spawn_pos, universe, &"player_fleet", false, true)
	if npc == null:
		push_error("NpcAuthority: Remote fleet spawn FAILED for ship_id '%s'" % ship_id_str)
		return {}

	npc.process_mode = Node.PROCESS_MODE_ALWAYS

	# Orient facing away
	if offset.length_squared() > 1.0:
		var away_dir := offset.normalized()
		npc.look_at_from_position(spawn_pos, spawn_pos + away_dir, Vector3.UP)

	# Equip weapons from ship_data
	var wm = npc.get_node_or_null("WeaponManager")
	if wm:
		var weapons: Array = ship_data.get("weapons", [])
		var weapons_sn: Array[StringName] = []
		for w in weapons:
			weapons_sn.append(StringName(w))
		wm.equip_weapons(weapons_sn)

	# Equip shield/engine/modules from ship_data
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

	# Attach FleetAIBridge
	var bridge = FleetAIBridge.new()
	bridge.name = "FleetAIBridge"
	bridge.fleet_index = fleet_index
	bridge.command = cmd
	bridge.command_params = params
	bridge._station_id = station_id
	npc.add_child(bridge)

	# Attach AIMiningBehavior if mining order
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


# =========================================================================
# REMOTE SYSTEM NPC MANAGEMENT
# Server spawns data-only NPCs for systems it's not physically in,
# so clients in those systems still see NPCs.
# =========================================================================

## Ensure NPCs exist for a system. Spawns them server-side if needed.
func ensure_system_npcs(system_id: int) -> void:
	if not _active:
		return
	# Already has local NPCs (server is in this system)
	if _npcs_by_system.has(system_id) and not _npcs_by_system[system_id].is_empty():
		return
	# Already has remote NPCs
	if _remote_npcs.has(system_id):
		return
	_spawn_remote_system_npcs(system_id)


func _spawn_remote_system_npcs(system_id: int) -> void:
	var sys_trans = GameManager._system_transition
	if sys_trans == null:
		return
	var galaxy = sys_trans.galaxy
	if galaxy == null:
		return
	var galaxy_sys: Dictionary = galaxy.get_system(system_id)
	if galaxy_sys.is_empty():
		return

	var danger_level: int = galaxy_sys.get("danger_level", 0)

	# Resolve system data (override > procedural)
	var system_data: StarSystemData = SystemDataRegistry.get_override(system_id)
	if system_data == null:
		var connections = sys_trans._build_connection_list(system_id)
		system_data = SystemGenerator.generate(galaxy_sys["seed"], connections)

	# Base position near first station
	var base_pos =Vector3(500, 0, -1500)
	if system_data.stations.size() > 0:
		var st: StationData = system_data.stations[0]
		var st_angle =EntityRegistrySystem.compute_orbital_angle(st.orbital_angle, st.orbital_period)
		var station_pos =Vector3(
			cos(st_angle) * st.orbital_radius, 0.0,
			sin(st_angle) * st.orbital_radius)
		var radial_dir =station_pos.normalized() if station_pos.length_squared() > 1.0 else Vector3.FORWARD
		base_pos = station_pos + radial_dir * 2000.0 + Vector3(0, 100, 0)

	# Spawn config from danger level (shared with EncounterManager)
	var configs =EncounterConfig.get_danger_config(danger_level)

	var npcs: Array = []
	var cfg_idx: int = 0
	var now: float = Time.get_unix_time_from_system()
	for config in configs:
		var count: int = config["count"]
		var ship_id: StringName = config["ship"]
		var faction: StringName = config["fac"]
		var radius: float = config["radius"]
		for i in count:
			# Deterministic encounter key for respawn tracking
			var encounter_key: String = "%d:enc_%d_%d" % [system_id, cfg_idx, i]

			# Skip NPCs still on respawn cooldown
			if _destroyed_encounter_npcs.has(encounter_key):
				if now < _destroyed_encounter_npcs[encounter_key]:
					continue
				else:
					_destroyed_encounter_npcs.erase(encounter_key)

			var angle: float = (float(i) / float(count)) * TAU
			var offset =Vector3(cos(angle) * radius * 0.5, randf_range(-30.0, 30.0), sin(angle) * radius * 0.5)
			var pos =base_pos + offset
			var vel =Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			var npc_id =StringName("NPC_%s_%d" % [ship_id, randi() % 100000])

			npcs.append({
				"nid": String(npc_id),
				"sid": String(ship_id),
				"fac": String(faction),
				"px": pos.x, "py": pos.y, "pz": pos.z,
				"vx": vel.x, "vy": vel.y, "vz": vel.z,
				"rx": 0.0, "ry": randf() * 360.0, "rz": 0.0,
				"hull": 1.0, "shd": 1.0,
				"thr": 0.5, "ai": RemoteNpcAI.State.PATROL, "tid": "",
				"t": Time.get_ticks_msec() / 1000.0,
			})
			register_npc(npc_id, system_id, ship_id, faction)
			# Store encounter key on the NPC registration for death tracking
			_npcs[npc_id]["encounter_key"] = encounter_key
		cfg_idx += 1

	_remote_npcs[system_id] = npcs
	print("NpcAuthority: Spawned %d remote NPCs for system %d" % [npcs.size(), system_id])


## AI-driven update for remote system NPCs.
## NPCs in systems with players get full AI; empty systems get simple drift.
func _update_remote_npcs(delta: float) -> void:
	# Build peers-by-system lookup once
	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate = NetworkManager.peers[pid]
		if pstate.is_dead:
			continue
		if not peers_by_sys.has(pstate.system_id):
			peers_by_sys[pstate.system_id] = {}
		peers_by_sys[pstate.system_id][pid] = pstate

	for system_id in _remote_npcs:
		var npcs: Array = _remote_npcs[system_id]
		var peers = peers_by_sys.get(system_id, {})

		if peers.is_empty():
			# No players — simple drift only
			for npc in npcs:
				if npc.get("is_dead", false):
					continue
				npc["px"] += npc.get("vx", 0.0) * delta
				npc["py"] += npc.get("vy", 0.0) * delta
				npc["pz"] += npc.get("vz", 0.0) * delta
				npc["t"] = Time.get_ticks_msec() / 1000.0
		else:
			# Players present — full AI simulation
			for npc in npcs:
				if npc.get("is_dead", false):
					continue
				RemoteNpcAI.tick(npc, peers, npcs, delta)
				# Handle fire events
				var fire = npc.get("_pending_fire")
				if fire:
					_relay_remote_npc_fire(fire, system_id, peers)
					npc.erase("_pending_fire")

	# Periodic cleanup of dead remote NPCs to prevent memory leak
	_dead_remote_cleanup_timer -= delta
	if _dead_remote_cleanup_timer <= 0.0:
		_dead_remote_cleanup_timer = 10.0
		for sys_id in _remote_npcs:
			_remote_npcs[sys_id] = _remote_npcs[sys_id].filter(
				func(n): return not n.get("is_dead", false))


## Relay a remote NPC fire event: send visual fire to peers + apply damage to target.
func _relay_remote_npc_fire(fire: Dictionary, system_id: int, peers: Dictionary) -> void:
	var npc_id: String = fire.get("npc_id", "")
	var target_pid: int = fire.get("target_pid", -1)
	var fire_pos: Array = fire.get("pos", [0.0, 0.0, 0.0])
	var fire_dir: Array = fire.get("dir", [0.0, 0.0, -1.0])
	var damage: float = fire.get("damage", 10.0)
	var dist: float = fire.get("dist", 999.0)

	# Cap damage based on ship's lod_combat_dps
	var npc_ship_id: String = ""
	for rnpc in _remote_npcs.get(system_id, []):
		if rnpc.get("nid", "") == npc_id:
			npc_ship_id = rnpc.get("sid", "")
			break
	if npc_ship_id != "":
		var sd = ShipRegistry.get_ship_data(StringName(npc_ship_id))
		if sd:
			damage = minf(damage, sd.lod_combat_dps)

	# Send fire visual to all peers in this system
	for pid in peers:
		NetworkManager._rpc_npc_fire.rpc_id(pid, npc_id, "remote_npc", fire_pos, fire_dir)

	# Apply damage to target player (server-authoritative)
	if target_pid < 0 or not NetworkManager.peers.has(target_pid):
		return
	var target_state = NetworkManager.peers[target_pid]
	if target_state.is_docked or target_state.is_dead:
		return

	# Hit probability based on distance (100% at close range, 30% at max engagement)
	var hit_chance: float = clampf(1.0 - (dist / RemoteNpcAI.ENGAGEMENT_RANGE) * 0.7, 0.3, 1.0)
	if randf() > hit_chance:
		return

	# Calculate hit direction relative to target
	var hit_dir: Array = [-fire_dir[0], -fire_dir[1], -fire_dir[2]]

	# Send damage to target
	NetworkManager._rpc_receive_player_damage.rpc_id(target_pid, -1, "remote_npc", damage, hit_dir)

	# Send hit effect to other peers
	var target_label: String = "player_%d" % target_pid
	for pid in peers:
		if pid == target_pid:
			continue
		NetworkManager._rpc_hit_effect.rpc_id(pid, target_label, hit_dir, false)


## Handle remote NPC getting hit by a player (validates and applies damage to dict).
func validate_remote_npc_hit(sender_pid: int, target_npc_id: String, damage: float, hit_dir: Array) -> void:
	# Find the NPC in remote systems
	var npc_id := StringName(target_npc_id)
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]
	var system_id: int = info.get("system_id", -1)
	if not _remote_npcs.has(system_id):
		return

	var npcs: Array = _remote_npcs[system_id]
	for npc in npcs:
		if npc.get("nid", "") != target_npc_id:
			continue
		if npc.get("is_dead", false):
			return

		# Apply damage
		var shield_absorbed: bool = npc.get("shd", 0.0) > 0.0
		if npc.get("shd", 0.0) > 0.0:
			npc["shd"] = maxf(npc.get("shd", 1.0) - damage * 0.008, 0.0)
		else:
			npc["hull"] = maxf(npc.get("hull", 1.0) - damage * 0.012, 0.0)

		if npc.get("hull", 0.0) <= 0.0:
			npc["is_dead"] = true
			_on_npc_killed(npc_id, sender_pid)

		# Broadcast hit effect
		broadcast_hit_effect(target_npc_id, sender_pid, hit_dir, shield_absorbed, system_id)

		# Trigger evasion on hit
		if npc.get("ai", 0) == RemoteNpcAI.State.ATTACK and randf() < 0.3:
			npc["ai"] = RemoteNpcAI.State.EVADE
			npc["_evade_timer"] = RemoteNpcAI.EVADE_DURATION
		return


## Remove expired entries from the encounter respawn tracker.
func _cleanup_expired_respawns() -> void:
	var now: float = Time.get_unix_time_from_system()
	var expired: Array = []
	for key in _destroyed_encounter_npcs:
		if now >= _destroyed_encounter_npcs[key]:
			expired.append(key)
	for key in expired:
		_destroyed_encounter_npcs.erase(key)


## Broadcast state of NPCs in remote systems (not managed by LOD manager).
func _broadcast_remote_npc_states(slow_sync: bool) -> void:
	if not slow_sync:
		return  # Remote NPCs only need slow sync (2Hz)

	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate = NetworkManager.peers[pid]
		if not peers_by_sys.has(pstate.system_id):
			peers_by_sys[pstate.system_id] = []
		peers_by_sys[pstate.system_id].append(pid)

	for system_id in _remote_npcs:
		if not peers_by_sys.has(system_id):
			continue
		var peer_ids: Array = peers_by_sys[system_id]
		var npcs: Array = _remote_npcs[system_id]
		if npcs.is_empty():
			continue

		# Filter out dead NPCs from broadcast
		var alive_npcs: Array = npcs.filter(func(n): return not n.get("is_dead", false))
		if alive_npcs.is_empty():
			continue

		for pid in peer_ids:
			NetworkManager._rpc_npc_batch.rpc_id(pid, alive_npcs)


## Detect when peers change systems and spawn NPCs for the new system.
func _check_peer_system_changes() -> void:
	for pid in NetworkManager.peers:
		var state = NetworkManager.peers[pid]
		var prev_sys: int = _peer_systems.get(pid, -1)
		if state.system_id != prev_sys:
			_peer_systems[pid] = state.system_id
			if state.system_id >= 0:
				ensure_system_npcs(state.system_id)


# =========================================================================
# MINING SYNC
# =========================================================================

## Relay a mining beam state to all peers in the sender's system.
func relay_mining_beam(sender_pid: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not _active:
		return
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peers_in_sys =NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_remote_mining_beam.rpc_id(pid, sender_pid, is_active, source_pos, target_pos)


## Broadcast asteroid depletion to all peers in the system.
func broadcast_asteroid_depleted(asteroid_id: String, system_id: int, sender_pid: int) -> void:
	if not _active:
		return
	var peers_in_sys =NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_receive_asteroid_depleted.rpc_id(pid, asteroid_id)


# =========================================================================
# ASTEROID HEALTH TRACKING (cooperative mining sync)
# =========================================================================

## Server receives batched mining damage claims from a client.
func handle_mining_damage_claims(sender_pid: int, claims: Array) -> void:
	if not _active:
		return
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	# Reject if player is docked or dead
	if sender_state.is_docked or sender_state.is_dead:
		return

	var system_id: int = sender_state.system_id
	var now: float = Time.get_ticks_msec() / 1000.0

	for claim in claims:
		if not claim is Dictionary:
			continue
		var asteroid_id: String = claim.get("aid", "")
		var damage: float = claim.get("dmg", 0.0)
		var health_max: float = claim.get("hm", 100.0)

		if asteroid_id == "" or damage <= 0.0:
			continue

		# DPS validation: track accumulated damage per peer per asteroid (2s window)
		if not _peer_mining_dps.has(sender_pid):
			_peer_mining_dps[sender_pid] = {}
		var peer_tracking: Dictionary = _peer_mining_dps[sender_pid]
		if not peer_tracking.has(asteroid_id):
			peer_tracking[asteroid_id] = { "dmg": 0.0, "t0": now }
		var track: Dictionary = peer_tracking[asteroid_id]

		var elapsed: float = now - track["t0"]
		if elapsed > 2.0:
			# Reset window
			track["dmg"] = damage
			track["t0"] = now
		else:
			track["dmg"] += damage

		# Check DPS: reject if exceeds MINING_MAX_DPS * 1.5
		var window_dps: float = track["dmg"] / maxf(elapsed, 0.1)
		if window_dps > MINING_MAX_DPS * 1.5:
			continue

		_apply_asteroid_damage(system_id, asteroid_id, damage, now, health_max)


## Apply validated mining damage to server-side asteroid health tracker.
func _apply_asteroid_damage(system_id: int, asteroid_id: String, damage: float, timestamp: float, health_max_hint: float) -> void:
	if not _asteroid_health.has(system_id):
		_asteroid_health[system_id] = {}
	var sys_health: Dictionary = _asteroid_health[system_id]

	if not sys_health.has(asteroid_id):
		# Lazy init: first claim creates the entry, clamp health_max [50, 800]
		var hm: float = clampf(health_max_hint, 50.0, 800.0)
		sys_health[asteroid_id] = { "hp": hm, "hm": hm, "t": timestamp }

	var entry: Dictionary = sys_health[asteroid_id]
	entry["hp"] = maxf(entry["hp"] - damage, 0.0)
	entry["t"] = timestamp

	# Depletion: broadcast reliable + mark entry
	if entry["hp"] <= 0.0:
		broadcast_asteroid_depleted(asteroid_id, system_id, -1)


## Broadcast asteroid health ratios to all peers (2Hz, per-system).
func _broadcast_asteroid_health_batch() -> void:
	if _asteroid_health.is_empty():
		return

	# Group peers by system
	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate = NetworkManager.peers[pid]
		if not peers_by_sys.has(pstate.system_id):
			peers_by_sys[pstate.system_id] = []
		peers_by_sys[pstate.system_id].append(pid)

	for system_id in _asteroid_health:
		if not peers_by_sys.has(system_id):
			continue
		var sys_health: Dictionary = _asteroid_health[system_id]
		if sys_health.is_empty():
			continue

		# Build batch of damaged asteroids (hp_ratio < 1.0)
		var batch: Array = []
		for asteroid_id in sys_health:
			var entry: Dictionary = sys_health[asteroid_id]
			var hm: float = entry["hm"]
			if hm <= 0.0:
				continue
			var ratio: float = entry["hp"] / hm
			if ratio >= 1.0:
				continue
			batch.append({ "aid": asteroid_id, "hp": ratio })

		if batch.is_empty():
			continue

		var peer_ids: Array = peers_by_sys[system_id]
		for pid in peer_ids:
			NetworkManager._rpc_asteroid_health_batch.rpc_id(pid, batch)


## Send current asteroid health state to a newly joined peer.
func send_asteroid_health_to_peer(peer_id: int, system_id: int) -> void:
	if not _asteroid_health.has(system_id):
		return
	var sys_health: Dictionary = _asteroid_health[system_id]
	if sys_health.is_empty():
		return

	var batch: Array = []
	for asteroid_id in sys_health:
		var entry: Dictionary = sys_health[asteroid_id]
		var hm: float = entry["hm"]
		if hm <= 0.0:
			continue
		var ratio: float = entry["hp"] / hm
		if ratio >= 1.0:
			continue
		batch.append({ "aid": asteroid_id, "hp": ratio })

	if batch.is_empty():
		return

	NetworkManager._rpc_asteroid_health_batch.rpc_id(peer_id, batch)


## Clear asteroid health data when a system unloads.
func clear_system_asteroid_health(system_id: int) -> void:
	_asteroid_health.erase(system_id)


## Clean up DPS tracking when a peer disconnects.
func clean_peer_mining_tracking(peer_id: int) -> void:
	_peer_mining_dps.erase(peer_id)


## AI fleet mining damage: update server tracker (called from AIMiningBehavior on server).
func apply_ai_mining_damage(system_id: int, asteroid_id: String, damage: float, health_max: float) -> void:
	if not _active:
		return
	_apply_asteroid_damage(system_id, asteroid_id, damage, Time.get_ticks_msec() / 1000.0, health_max)


## Remove asteroid health entries older than respawn time (5min).
func _cleanup_stale_asteroid_health() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for system_id in _asteroid_health.keys():
		var sys_health: Dictionary = _asteroid_health[system_id]
		var expired: Array = []
		for asteroid_id in sys_health:
			var entry: Dictionary = sys_health[asteroid_id]
			if now - entry["t"] > ASTEROID_RESPAWN_TIME_CLEANUP:
				expired.append(asteroid_id)
		for asteroid_id in expired:
			sys_health.erase(asteroid_id)
		if sys_health.is_empty():
			_asteroid_health.erase(system_id)


# =========================================================================
# FLEET BACKEND SYNC (server → Go backend, 30s interval)
# =========================================================================

## Collect positions/health of all fleet NPCs and batch-sync to backend.
func _sync_fleet_to_backend() -> void:
	if _backend_client == null or _fleet_npcs.is_empty():
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr == null:
		return

	var updates: Array = []
	for npc_id in _fleet_npcs:
		var fleet_info: Dictionary = _fleet_npcs[npc_id]
		var uuid: String = fleet_info.get("owner_uuid", "")
		if uuid == "":
			continue
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data == null or lod_data.is_dead:
			continue
		var upos =FloatingOrigin.to_universe_pos(lod_data.position)
		updates.append({
			"player_id": uuid,
			"fleet_index": fleet_info.get("fleet_index", -1),
			"pos_x": upos[0],
			"pos_y": upos[1],
			"pos_z": upos[2],
			"hull_ratio": lod_data.hull_ratio,
			"shield_ratio": lod_data.shield_ratio,
		})

	if updates.is_empty():
		return

	var ok: bool = await _backend_client.sync_fleet_positions(updates)
	if not ok:
		push_warning("NpcAuthority: Fleet position sync failed (%d updates)" % updates.size())


## Report a fleet NPC death to the backend.
func _report_fleet_death_to_backend(uuid: String, fleet_index: int) -> void:
	if _backend_client == null or uuid == "":
		return
	var ok: bool = await _backend_client.report_fleet_death(uuid, fleet_index)
	if not ok:
		push_error("NpcAuthority: Fleet death NOT persisted for %s index %d" % [uuid, fleet_index])


## Load previously deployed fleet ships from the backend on server startup.
func _load_deployed_fleet_ships_from_backend() -> void:
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
		var _command: String = ship_data.get("command", "")
		var faction: StringName = &"player_fleet"

		# Register as data-only NPC (will get a real node when a player enters the system)
		var npc_id =StringName("FleetNPC_%s_%d" % [player_id.left(8), fleet_index])

		# Register in NPC authority
		register_npc(npc_id, system_id, StringName(ship_id), faction)
		_fleet_npcs[npc_id] = { "owner_uuid": player_id, "owner_pid": -1, "fleet_index": fleet_index }
		if not _fleet_npcs_by_owner.has(player_id):
			_fleet_npcs_by_owner[player_id] = []
		_fleet_npcs_by_owner[player_id].append(npc_id)

		# Store as remote NPC data for state broadcasting
		if not _remote_npcs.has(system_id):
			_remote_npcs[system_id] = []
		_remote_npcs[system_id].append({
			"nid": String(npc_id),
			"sid": ship_id,
			"fac": String(faction),
			"px": pos_x, "py": pos_y, "pz": pos_z,
			"vx": 0.0, "vy": 0.0, "vz": 0.0,
			"rx": 0.0, "ry": 0.0, "rz": 0.0,
			"hull": hull, "shd": shield,
			"thr": 0.5, "ai": RemoteNpcAI.State.PATROL, "tid": "",
			"t": Time.get_ticks_msec() / 1000.0,
		})

	print("NpcAuthority: Restored %d fleet NPCs from backend" % ships.size())
	_fleet_backend_loaded = true
	_process_pending_reconnects()


## Process any reconnections that were queued while backend fleet was loading.
func _process_pending_reconnects() -> void:
	if _pending_reconnects.is_empty():
		return
	print("NpcAuthority: Processing %d pending reconnects" % _pending_reconnects.size())
	for entry in _pending_reconnects:
		_send_fleet_reconnect_status(entry["uuid"], entry["pid"])
	_pending_reconnects.clear()
