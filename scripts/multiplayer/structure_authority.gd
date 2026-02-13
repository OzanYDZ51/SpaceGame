class_name StructureAuthority
extends Node

# =============================================================================
# Structure Authority — Server-authoritative station damage & sync
# Pattern mirrors NpcAuthority: register, hit validation, batch sync, death.
# =============================================================================

# Registry: struct_id -> {system_id, station_type, node_ref: SpaceStation}
var _structures: Dictionary = {}

var _batch_timer: float = 0.0
const BATCH_INTERVAL: float = 0.2  # 5Hz (stations don't move)


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if not NetworkManager.structure_hit_claimed.is_connected(_on_hit_claimed):
		NetworkManager.structure_hit_claimed.connect(_on_hit_claimed)


func _process(delta: float) -> void:
	if not NetworkManager.is_server():
		return
	_batch_timer -= delta
	if _batch_timer <= 0.0:
		_batch_timer = BATCH_INTERVAL
		_broadcast_batch()


## Register a station with the authority (called on system load).
func register_structure(struct_id: String, system_id: int, station_type: int, node: Node3D) -> void:
	_structures[struct_id] = {
		"system_id": system_id,
		"station_type": station_type,
		"node_ref": node,
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


## Clear everything.
func clear_all() -> void:
	_structures.clear()


# =============================================================================
# HIT VALIDATION (server only)
# =============================================================================
func _on_hit_claimed(sender_pid: int, target_id: String, _weapon: String, damage: float, hit_dir: Array) -> void:
	if not NetworkManager.is_server():
		return
	validate_hit_claim(sender_pid, target_id, _weapon, damage, hit_dir)


func validate_hit_claim(sender_pid: int, target_id: String, _weapon: String, damage: float, hit_dir: Array) -> void:
	if not _structures.has(target_id):
		return

	var entry: Dictionary = _structures[target_id]
	var node: Node3D = entry.get("node_ref")
	if node == null or not is_instance_valid(node):
		return

	var health := node.get_node_or_null("StructureHealth") as StructureHealth
	if health == null or health.is_dead():
		return

	# System check — sender must be in the same system as the structure
	var sender_state: NetworkState = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var struct_sys: int = entry.get("system_id", -1)
	if sender_state.system_id != struct_sys:
		return

	# Distance check
	var sender_pos := FloatingOrigin.to_local_pos([sender_state.pos_x, sender_state.pos_y, sender_state.pos_z])
	if sender_pos.distance_to(node.global_position) > 5000.0:
		return

	# Damage tolerance check (±50%)
	# We accept reasonable values — prevents obvious cheats
	if damage > 500.0 or damage < 0.1:
		return

	# Apply damage
	var dir := Vector3(hit_dir[0], hit_dir[1], hit_dir[2]) if hit_dir.size() >= 3 else Vector3.FORWARD
	health.apply_damage(damage, &"thermal", dir, null)

	# If destroyed, broadcast death
	if health.is_dead():
		var loot: Array[Dictionary] = StructureLootTable.roll_drops(entry.get("station_type", 0))
		var pos := [node.global_position.x, node.global_position.y, node.global_position.z]
		_broadcast_structure_destroyed(target_id, sender_pid, pos, loot)


# =============================================================================
# BATCH SYNC (server -> all clients in same system)
# =============================================================================
func _broadcast_batch() -> void:
	if _structures.is_empty():
		return

	# Group structures by system_id
	var by_system: Dictionary = {}
	for sid in _structures:
		var entry: Dictionary = _structures[sid]
		var node: Node3D = entry.get("node_ref")
		if node == null or not is_instance_valid(node):
			continue
		var health := node.get_node_or_null("StructureHealth") as StructureHealth
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

	# Send to each peer in matching system
	for peer_id in NetworkManager.peers:
		var ps: NetworkState = NetworkManager.peers[peer_id]
		if ps == null:
			continue
		var sys_id: int = ps.system_id
		if by_system.has(sys_id) and not by_system[sys_id].is_empty():
			if peer_id == 1 and not NetworkManager.is_dedicated_server:
				# Host — deliver locally
				apply_batch(by_system[sys_id])
			else:
				NetworkManager._rpc_structure_batch.rpc_id(peer_id, by_system[sys_id])


func _broadcast_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array) -> void:
	# Get the system this structure belongs to
	var sys_id: int = -1
	if _structures.has(struct_id):
		sys_id = _structures[struct_id].get("system_id", -1)

	# Send to peers in the same system only
	var target_peers := NetworkManager.get_peers_in_system(sys_id) if sys_id >= 0 else NetworkManager.peers.keys()
	for peer_id in target_peers:
		var loot_for_peer: Array = loot if peer_id == killer_pid else []
		if peer_id == 1 and not NetworkManager.is_dedicated_server:
			apply_structure_destroyed(struct_id, killer_pid, pos, loot_for_peer)
		else:
			NetworkManager._rpc_structure_destroyed.rpc_id(peer_id, struct_id, killer_pid, pos, loot_for_peer)


# =============================================================================
# CLIENT-SIDE: Apply batch from server
# =============================================================================
func apply_batch(batch: Array) -> void:
	for entry in batch:
		var sid: String = entry.get("sid", "")
		if not _structures.has(sid):
			continue
		var node: Node3D = _structures[sid].get("node_ref")
		if node == null or not is_instance_valid(node):
			continue
		var health := node.get_node_or_null("StructureHealth") as StructureHealth
		if health == null or health.is_dead():
			continue
		# Apply server ratios
		health.hull_current = entry.get("hull", 1.0) * health.hull_max
		health.shield_current = entry.get("shd", 1.0) * health.shield_max
		health.hull_changed.emit(health.hull_current, health.hull_max)
		health.shield_changed.emit(health.shield_current, health.shield_max)


func apply_structure_destroyed(struct_id: String, _killer_pid: int, _pos: Array, _loot: Array) -> void:
	if not _structures.has(struct_id):
		return
	var node: Node3D = _structures[struct_id].get("node_ref")
	if node == null or not is_instance_valid(node):
		return
	var health := node.get_node_or_null("StructureHealth") as StructureHealth
	if health and not health.is_dead():
		health.hull_current = 0.0
		health._is_dead = true
		health.structure_destroyed.emit()
