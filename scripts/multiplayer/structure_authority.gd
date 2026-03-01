class_name StructureAuthority
extends Node

# =============================================================================
# Structure Authority — Server-authoritative station damage & sync
# Pattern mirrors NpcAuthority: register, hit validation, batch sync, death.
#
# For the server's loaded system, real station nodes are registered by
# system_transition. For REMOTE systems (where players are but the server
# hasn't loaded the scene), virtual StructureHealth nodes are created so
# the server can validate hits and broadcast health state.
# =============================================================================

# Registry for loaded-system structures: struct_id -> {system_id, station_type, node_ref, pos_x, pos_y, pos_z}
var _structures: Dictionary = {}

# Virtual structures for remote systems: system_id -> {struct_id -> entry}
var _virtual: Dictionary = {}
var _virtual_nodes: Array[Node3D] = []
var _virtual_respawns: Dictionary = {}  # "sys:struct" -> time_remaining

var _batch_timer: float = 0.0
const BATCH_INTERVAL: float = 0.2  # 5Hz (stations don't move)
const VIRTUAL_RESPAWN_TIME: float = 300.0  # 5 minutes

var _peer_systems: Dictionary = {}  # peer_id -> last known system_id (server only)


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if not NetworkManager.structure_hit_claimed.is_connected(_on_hit_claimed):
		NetworkManager.structure_hit_claimed.connect(_on_hit_claimed)


func _process(delta: float) -> void:
	if not NetworkManager.is_server():
		return
	_check_peer_system_changes()
	_update_virtual_respawns(delta)
	_batch_timer -= delta
	if _batch_timer <= 0.0:
		_batch_timer = BATCH_INTERVAL
		_broadcast_batch()


## Register a station with the authority (called on system load).
func register_structure(struct_id: String, system_id: int, station_type: int, node: Node3D,
		upos_x: float = 0.0, upos_y: float = 0.0, upos_z: float = 0.0) -> void:
	_structures[struct_id] = {
		"system_id": system_id,
		"station_type": station_type,
		"node_ref": node,
		"pos_x": upos_x,
		"pos_y": upos_y,
		"pos_z": upos_z,
	}


## Unregister a single structure.
func unregister_structure(struct_id: String) -> void:
	_structures.erase(struct_id)


## Clear all structures for a system (called on system unload).
func clear_system_structures(system_id: int) -> void:
	var to_remove: Array[String] = []
	for sid in _structures:
		if _structures[sid]["system_id"] == system_id:
			to_remove.append(sid)
	for sid in to_remove:
		_structures.erase(sid)
	_free_virtual_system(system_id)


## Clear everything.
func clear_all() -> void:
	_structures.clear()
	_free_all_virtual_nodes()


# =============================================================================
# REMOTE SYSTEM VIRTUAL STRUCTURES (server only)
# =============================================================================

## Track peer system changes and ensure structures exist for their systems.
func _check_peer_system_changes() -> void:
	for pid in NetworkManager.peers:
		var state = NetworkManager.peers[pid]
		if state == null:
			continue
		var prev_sys: int = _peer_systems.get(pid, -1)
		if state.system_id != prev_sys:
			_peer_systems[pid] = state.system_id
			if state.system_id >= 0:
				ensure_system_structures(state.system_id)


## Ensure structures exist for a system (creates virtual nodes if needed).
func ensure_system_structures(system_id: int) -> void:
	# Check if loaded-system structures already cover this system
	for entry in _structures.values():
		if entry["system_id"] == system_id:
			return
	# Check if virtual structures already exist
	if _virtual.has(system_id) and not _virtual[system_id].is_empty():
		return

	var galaxy: GalaxyData = GameManager._galaxy
	if galaxy == null:
		return
	var galaxy_sys: Dictionary = galaxy.get_system(system_id)
	if galaxy_sys.is_empty():
		return

	# Resolve system data: override > procedural
	var sys_data: StarSystemData = SystemDataRegistry.get_override(system_id)
	if sys_data == null:
		sys_data = SystemGenerator.generate(galaxy_sys["seed"])

	var entries: Dictionary = {}
	var vnodes: Array[Node3D] = []
	for i in sys_data.stations.size():
		var sd: StationData = sys_data.stations[i]
		var vnode := Node3D.new()
		vnode.name = "VirtualStation_%d_sys%d" % [i, system_id]
		var health := StructureHealth.new()
		health.name = "StructureHealth"
		health.apply_preset(sd.station_type)
		vnode.add_child(health)
		add_child(vnode)
		vnodes.append(vnode)

		var angle: float = EntityRegistrySystem.compute_orbital_angle(sd.orbital_angle, sd.orbital_period)
		var orbit_r: float = sd.orbital_radius
		entries["Station_%d" % i] = {
			"system_id": system_id,
			"station_type": sd.station_type,
			"node_ref": vnode,
			"pos_x": cos(angle) * orbit_r,
			"pos_y": 0.0,
			"pos_z": sin(angle) * orbit_r,
		}

	_virtual[system_id] = entries
	_virtual_nodes.append_array(vnodes)
	if not entries.is_empty():
		print("[StructAuth] Registered %d virtual structures for system %d" % [entries.size(), system_id])


func _update_virtual_respawns(delta: float) -> void:
	var to_revive: Array[String] = []
	for key in _virtual_respawns:
		_virtual_respawns[key] -= delta
		if _virtual_respawns[key] <= 0.0:
			to_revive.append(key)
	for key in to_revive:
		_virtual_respawns.erase(key)
		var sep: int = key.find(":")
		if sep < 0:
			continue
		var sys_id: int = int(key.left(sep))
		var struct_id: String = key.substr(sep + 1)
		if _virtual.has(sys_id) and _virtual[sys_id].has(struct_id):
			var entry: Dictionary = _virtual[sys_id][struct_id]
			var node_ref = entry.get("node_ref")
			if node_ref and is_instance_valid(node_ref):
				var health = node_ref.get_node_or_null("StructureHealth")
				if health:
					health.revive()
					print("[StructAuth] Virtual structure %s in system %d respawned" % [struct_id, sys_id])


func _free_virtual_system(system_id: int) -> void:
	if not _virtual.has(system_id):
		return
	for entry in _virtual[system_id].values():
		var node_ref = entry.get("node_ref")
		if node_ref and is_instance_valid(node_ref):
			_virtual_nodes.erase(node_ref)
			node_ref.queue_free()
	_virtual.erase(system_id)
	# Clean respawn timers for this system
	var prefix: String = "%d:" % system_id
	var to_erase: Array[String] = []
	for key in _virtual_respawns:
		if key.begins_with(prefix):
			to_erase.append(key)
	for key in to_erase:
		_virtual_respawns.erase(key)


func _free_all_virtual_nodes() -> void:
	for vnode in _virtual_nodes:
		if is_instance_valid(vnode):
			vnode.queue_free()
	_virtual_nodes.clear()
	_virtual.clear()
	_virtual_respawns.clear()


# =============================================================================
# HIT VALIDATION (server only)
# =============================================================================
func _on_hit_claimed(sender_pid: int, target_id: String, _weapon: String, damage: float, hit_dir: Array) -> void:
	if not NetworkManager.is_server():
		return
	validate_hit_claim(sender_pid, target_id, _weapon, damage, hit_dir)


func validate_hit_claim(sender_pid: int, target_id: String, _weapon: String, damage: float, hit_dir: Array) -> void:
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		print("[StructAuth] REJECT %s: sender_pid=%d not in peers" % [target_id, sender_pid])
		return

	# Resolve structure entry: loaded structures first, then virtual
	var entry: Dictionary = {}
	var is_virtual: bool = false
	if _structures.has(target_id):
		entry = _structures[target_id]
	else:
		var vs: Dictionary = _virtual.get(sender_state.system_id, {})
		if vs.has(target_id):
			entry = vs[target_id]
			is_virtual = true
	if entry.is_empty():
		print("[StructAuth] REJECT %s: not found in structures or virtual" % target_id)
		return

	var node_ref = entry.get("node_ref")
	if node_ref == null or not is_instance_valid(node_ref):
		print("[StructAuth] REJECT %s: node_ref invalid" % target_id)
		return
	var node: Node3D = node_ref

	var health = node.get_node_or_null("StructureHealth")
	if health == null or health.is_dead():
		return

	# System check — sender must be in the same system as the structure
	var struct_sys: int = entry.get("system_id", -1)
	if sender_state.system_id != struct_sys:
		print("[StructAuth] REJECT %s: system mismatch sender=%d struct=%d" % [target_id, sender_state.system_id, struct_sys])
		return

	# Distance check — use float64 universe coordinates for accuracy
	var dx: float = sender_state.pos_x - entry.get("pos_x", 0.0)
	var dy: float = sender_state.pos_y - entry.get("pos_y", 0.0)
	var dz: float = sender_state.pos_z - entry.get("pos_z", 0.0)
	var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
	if dist > Constants.AI_STRUCTURE_HIT_RANGE:
		print("[StructAuth] REJECT %s: dist=%.0f > %.0f" % [target_id, dist, Constants.AI_STRUCTURE_HIT_RANGE])
		return

	# Damage tolerance check — prevents obvious cheats
	if damage > Constants.AI_STRUCTURE_MAX_DAMAGE or damage < 0.1:
		print("[StructAuth] REJECT %s: damage=%.1f out of range" % [target_id, damage])
		return

	print("[StructAuth] HIT ACCEPTED %s: dmg=%.1f shield=%.0f/%.0f hull=%.0f/%.0f" % [target_id, damage, health.shield_current, health.shield_max, health.hull_current, health.hull_max])

	# Apply damage — resolve attacker node so AIController/GuardBehavior can retaliate
	var dir = Vector3(hit_dir[0], hit_dir[1], hit_dir[2]) if hit_dir.size() >= 3 else Vector3.FORWARD
	var attacker: Node3D = null
	var sync_mgr = GameManager.get_node_or_null("NetworkSyncManager")
	if sync_mgr and sync_mgr.remote_players.has(sender_pid):
		attacker = sync_mgr.remote_players[sender_pid]
	if attacker == null and sender_pid == NetworkManager.local_peer_id:
		var player = GameManager.player_ship
		if player and is_instance_valid(player):
			attacker = player
	health.apply_damage(damage, &"thermal", dir, attacker)

	# If destroyed, broadcast death
	if health.is_dead():
		var loot: Array[Dictionary] = StructureLootTable.roll_drops(entry.get("station_type", 0))
		var pos: Array = [entry.get("pos_x", 0.0), entry.get("pos_y", 0.0), entry.get("pos_z", 0.0)]
		_broadcast_structure_destroyed(target_id, sender_pid, pos, loot, struct_sys)
		if is_virtual:
			_virtual_respawns["%d:%s" % [struct_sys, target_id]] = VIRTUAL_RESPAWN_TIME


# =============================================================================
# BATCH SYNC (server -> all clients in same system)
# =============================================================================
func _broadcast_batch() -> void:
	if _structures.is_empty() and _virtual.is_empty():
		return

	# Group structures by system_id
	var by_system: Dictionary = {}

	# Loaded-system structures
	for sid in _structures:
		var entry: Dictionary = _structures[sid]
		var node_ref = entry.get("node_ref")
		if node_ref == null or not is_instance_valid(node_ref):
			continue
		var node: Node3D = node_ref
		var health = node.get_node_or_null("StructureHealth")
		if health == null:
			continue
		var sys_id: int = entry["system_id"]
		if not by_system.has(sys_id):
			by_system[sys_id] = []
		by_system[sys_id].append({
			"sid": sid,
			"hull": snappedi(health.get_hull_ratio() * 1000, 1) / 1000.0,
			"shd": snappedi(health.get_shield_ratio() * 1000, 1) / 1000.0,
		})

	# Virtual structures (remote systems)
	for sys_id in _virtual:
		for sid in _virtual[sys_id]:
			var entry: Dictionary = _virtual[sys_id][sid]
			var node_ref = entry.get("node_ref")
			if node_ref == null or not is_instance_valid(node_ref):
				continue
			var health = node_ref.get_node_or_null("StructureHealth")
			if health == null:
				continue
			if not by_system.has(sys_id):
				by_system[sys_id] = []
			by_system[sys_id].append({
				"sid": sid,
				"hull": snappedi(health.get_hull_ratio() * 1000, 1) / 1000.0,
				"shd": snappedi(health.get_shield_ratio() * 1000, 1) / 1000.0,
			})

	# Send to each peer in matching system
	for peer_id in NetworkManager.peers:
		var ps = NetworkManager.peers[peer_id]
		if ps == null:
			continue
		var sys_id: int = ps.system_id
		if by_system.has(sys_id) and not by_system[sys_id].is_empty():
			NetworkManager._rpc_structure_batch.rpc_id(peer_id, by_system[sys_id])


func _broadcast_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array, sys_id: int = -1) -> void:
	# Send to peers in the same system only
	var target_peers = NetworkManager.get_peers_in_system(sys_id) if sys_id >= 0 else NetworkManager.peers.keys()
	for peer_id in target_peers:
		var loot_for_peer: Array = loot if peer_id == killer_pid else []
		NetworkManager._rpc_structure_destroyed.rpc_id(peer_id, struct_id, killer_pid, pos, loot_for_peer)


# =============================================================================
# CLIENT-SIDE: Apply batch from server
# =============================================================================
func apply_batch(batch: Array) -> void:
	for entry in batch:
		var sid: String = entry.get("sid", "")
		if not _structures.has(sid):
			continue
		var node_ref = _structures[sid].get("node_ref")
		if node_ref == null or not is_instance_valid(node_ref):
			continue
		var node: Node3D = node_ref
		var health = node.get_node_or_null("StructureHealth")
		if health == null or health.is_dead():
			continue
		# Apply server ratios
		health.hull_current = entry.get("hull", 1.0) * health.hull_max
		health.shield_current = entry.get("shd", 1.0) * health.shield_max
		health.hull_changed.emit(health.hull_current, health.hull_max)
		health.shield_changed.emit(health.shield_current, health.shield_max)


func apply_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array) -> void:
	if not _structures.has(struct_id):
		return
	var node_ref = _structures[struct_id].get("node_ref")
	if node_ref == null or not is_instance_valid(node_ref):
		return
	var node: Node3D = node_ref
	var health = node.get_node_or_null("StructureHealth")
	if health and not health.is_dead():
		health.hull_current = 0.0
		health._is_dead = true
		health.structure_destroyed.emit()
	# Spawn synced loot crate for ALL clients
	if not loot.is_empty():
		var crate := CargoCrate.new()
		crate.sync_id = "crate_struct_%s" % struct_id
		crate.contents.assign(loot)
		crate.owner_peer_id = killer_pid
		var universe = GameManager.universe_node
		if universe:
			universe.add_child(crate)
			crate.global_position = FloatingOrigin.to_local_pos(pos) + Vector3(0, 50, 0)
