class_name NpcStateBroadcaster
extends RefCounted

# =============================================================================
# NPC State Broadcaster - Batched NPC state sync to clients.
# Extracted from NpcAuthority. Runs as a RefCounted sub-object.
# =============================================================================

const BATCH_INTERVAL: float = 0.033  # 30Hz NPC state sync — ALL NPCs, no distance throttle
const PEER_CHECK_INTERVAL: float = 0.5  # 2Hz peer system-change housekeeping
const MAX_NPCS_PER_BATCH: int = 30  # Cap per RPC to avoid WebSocket buffer overflow

var _auth: NpcAuthority = null
var _batch_timer: float = 0.0
var _peer_check_timer: float = 0.0


func setup(auth: NpcAuthority) -> void:
	_auth = auth


func tick(delta: float) -> void:
	_batch_timer -= delta
	_peer_check_timer -= delta

	if _peer_check_timer <= 0.0:
		_peer_check_timer = PEER_CHECK_INTERVAL
		_auth._check_peer_system_changes()

	if _batch_timer <= 0.0:
		_batch_timer = BATCH_INTERVAL
		_broadcast_npc_states()


## Connect NPC weapon_fired signal to relay fire events to remote clients.
func connect_npc_fire_relay(npc_id: StringName, ship_node: Node3D) -> void:
	if ship_node == null:
		return
	var wm = ship_node.get_node_or_null("WeaponManager")
	if wm == null:
		return
	if not _auth._npcs.has(npc_id):
		return
	var info: Dictionary = _auth._npcs[npc_id]
	var sys_id: int = info.get("system_id", -1)
	wm.weapon_fired.connect(func(hardpoint_id: int, weapon_name_str: StringName) -> void:
		_relay_npc_fire(npc_id, sys_id, ship_node, hardpoint_id, weapon_name_str))


func _relay_npc_fire(npc_id: StringName, system_id: int, ship_node: Node3D, hardpoint_id: int, weapon_name_str: StringName) -> void:
	if ship_node == null or not is_instance_valid(ship_node):
		return
	var wm = ship_node.get_node_or_null("WeaponManager")
	if wm == null or hardpoint_id >= wm.hardpoints.size():
		return
	var hp: Hardpoint = wm.hardpoints[hardpoint_id]
	var muzzle = hp.get_muzzle_transform()
	var fire_pos = FloatingOrigin.to_universe_pos(muzzle.origin)
	# Use the actual fire direction computed by try_fire (not muzzle -Z which
	# is flipped 180° on weapon models with rotated WeaponRoot)
	var fire_dir = hp.last_fire_dir
	var ship_vel = Vector3.ZERO
	if ship_node is RigidBody3D:
		ship_vel = ship_node.linear_velocity

	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	var dir_arr: Array = [fire_dir.x, fire_dir.y, fire_dir.z, ship_vel.x, ship_vel.y, ship_vel.z]
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_fire.rpc_id(pid, String(npc_id), String(weapon_name_str), fire_pos, dir_arr)


## Notify all peers in a system that an NPC has spawned.
func notify_spawn_to_peers(npc_id: StringName, system_id: int) -> void:
	if not _auth._npcs.has(npc_id):
		return
	var info: Dictionary = _auth._npcs[npc_id]

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

	var spawn_dict: Dictionary = {
		"nid": String(npc_id),
		"sid": String(info.get("ship_id", "")),
		"fac": String(info.get("faction", "hostile")),
		"px": 0.0, "py": 0.0, "pz": 0.0,
		"vx": 0.0, "vy": 0.0, "vz": 0.0,
	}
	if lod_data:
		var upos = FloatingOrigin.to_universe_pos(lod_data.position)
		spawn_dict["px"] = upos[0]
		spawn_dict["py"] = upos[1]
		spawn_dict["pz"] = upos[2]
		spawn_dict["vx"] = lod_data.velocity.x
		spawn_dict["vy"] = lod_data.velocity.y
		spawn_dict["vz"] = lod_data.velocity.z
		spawn_dict["hull"] = lod_data.hull_ratio
		spawn_dict["shd"] = lod_data.shield_ratio

	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_spawned.rpc_id(pid, spawn_dict)


## Send all NPC spawns for a system to a specific peer (join mid-combat).
func send_all_npcs_to_peer(peer_id: int, system_id: int) -> void:
	if _auth._npcs_by_system.has(system_id):
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		var npc_ids: Array = _auth._npcs_by_system[system_id]

		for npc_id in npc_ids:
			if not _auth._npcs.has(npc_id):
				continue
			var info: Dictionary = _auth._npcs[npc_id]
			var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

			var spawn_dict: Dictionary = {
				"nid": String(npc_id),
				"sid": String(info.get("ship_id", "")),
				"fac": String(info.get("faction", "hostile")),
				"px": 0.0, "py": 0.0, "pz": 0.0,
				"vx": 0.0, "vy": 0.0, "vz": 0.0,
			}
			if lod_data:
				var upos = FloatingOrigin.to_universe_pos(lod_data.position)
				spawn_dict["px"] = upos[0]
				spawn_dict["py"] = upos[1]
				spawn_dict["pz"] = upos[2]
				spawn_dict["vx"] = lod_data.velocity.x
				spawn_dict["vy"] = lod_data.velocity.y
				spawn_dict["vz"] = lod_data.velocity.z
				spawn_dict["hull"] = lod_data.hull_ratio
				spawn_dict["shd"] = lod_data.shield_ratio

			NetworkManager._rpc_npc_spawned.rpc_id(peer_id, spawn_dict)

	# Send active events to late-joining peer (map markers + HUD)
	var gi = GameManager.get_node_or_null("GameplayIntegrator")
	if gi and gi.event_manager:
		gi.event_manager.send_active_events_to_peer(peer_id)


func _broadcast_npc_states() -> void:
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

	for system_id in _auth._npcs_by_system:
		if not peers_by_sys.has(system_id):
			continue

		var peer_ids: Array = peers_by_sys[system_id]
		var npc_ids: Array = _auth._npcs_by_system[system_id]

		# Build batch once per system — all NPCs at full 30Hz, no distance throttle
		var batch: Array = []
		for npc_id in npc_ids:
			var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
			if lod_data == null or lod_data.is_dead:
				continue
			if is_instance_valid(lod_data.node_ref) and not lod_data.node_ref.visible:
				continue
			batch.append(_build_npc_state_dict(npc_id, lod_data))

		if batch.is_empty():
			continue

		# Send to all peers in this system
		for pid in peer_ids:
			if batch.size() <= MAX_NPCS_PER_BATCH:
				NetworkManager._rpc_npc_batch.rpc_id(pid, batch)
			else:
				for chunk_start in range(0, batch.size(), MAX_NPCS_PER_BATCH):
					var chunk: Array = batch.slice(chunk_start, chunk_start + MAX_NPCS_PER_BATCH)
					NetworkManager._rpc_npc_batch.rpc_id(pid, chunk)


func _build_npc_state_dict(npc_id: StringName, lod_data: ShipLODData) -> Dictionary:
	var upos = FloatingOrigin.to_universe_pos(lod_data.position)
	var rot_rad = lod_data.rotation_basis.get_euler()
	var rot_deg = Vector3(rad_to_deg(rot_rad.x), rad_to_deg(rot_rad.y), rad_to_deg(rot_rad.z))

	var hull: float = lod_data.hull_ratio
	var shd: float = lod_data.shield_ratio
	var ai: int = lod_data.ai_state
	var tid: StringName = lod_data.ai_target_id

	if is_instance_valid(lod_data.node_ref):
		rot_deg = lod_data.node_ref.rotation_degrees
		var health = lod_data.node_ref.get_node_or_null("HealthSystem")
		if health:
			hull = health.get_hull_ratio()
			shd = health.get_total_shield_ratio()
		var brain = lod_data.node_ref.get_node_or_null("AIBrain")
		if brain:
			ai = brain.current_state
			if brain.target and is_instance_valid(brain.target):
				tid = StringName(brain.target.name)
			else:
				tid = &""

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
		"hull": hull,
		"shd": shd,
		"thr": 0.5,
		"ai": ai,
		"tid": String(tid),
		"t": Time.get_ticks_msec() / 1000.0,
	}


## Server receives a fire event from a client — relay to other clients.
func relay_fire_event(sender_pid: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peers_in_sys = NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_remote_fire.rpc_id(pid, sender_pid, weapon_name, fire_pos, fire_dir)


## Broadcast hit effect to all peers in system (except the attacker who showed it locally).
func broadcast_hit_effect(target_id: String, exclude_pid: int, hit_dir: Array, shield_absorbed: bool, system_id: int) -> void:
	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == exclude_pid:
			continue
		NetworkManager._rpc_hit_effect.rpc_id(pid, target_id, hit_dir, shield_absorbed)


## Relay a scanner pulse to all peers in the sender's system (except the sender).
func relay_scanner_pulse(sender_pid: int, scan_pos: Array) -> void:
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peers_in_sys = NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_remote_scanner_pulse.rpc_id(pid, sender_pid, scan_pos)
