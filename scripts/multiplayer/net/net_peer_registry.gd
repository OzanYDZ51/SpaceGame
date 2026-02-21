class_name NetPeerRegistry
extends RefCounted

# =============================================================================
# NetPeerRegistry — Player/peer tracking
# Owns the authoritative peer dictionaries and UUID ↔ peer mappings.
# The `peers` dict is exposed as a property; callers use it directly (read)
# and call registry methods for mutations.
# =============================================================================

var _nm: NetworkManagerSystem

# peer_id -> NetworkState (all remote players) — public, accessed directly by NM
var peers: Dictionary = {}

# Server-side UUID ↔ peer_id mappings (persist across reconnects)
var _uuid_to_peer: Dictionary = {}  # player_uuid (String) -> peer_id (int)
var _peer_to_uuid: Dictionary = {}  # peer_id (int) -> player_uuid (String)

# Server-side in-memory persistence: peer_id -> system_id
var _player_last_system: Dictionary = {}


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Register or update an existing peer's identity.
## Returns the NetworkState for this sender, and a bool for is_reconnect.
func register_or_update(sender_id: int, player_name: String, ship_id_str: String, player_uuid: String, player_role: String) -> Dictionary:
	# --- Identity update: peer already registered ---
	if peers.has(sender_id):
		var existing: NetworkState = peers[sender_id]
		var name_changed: bool = existing.player_name != player_name
		existing.player_name = player_name
		existing.role = player_role
		if player_uuid != "":
			_uuid_to_peer[player_uuid] = sender_id
			_peer_to_uuid[sender_id] = player_uuid
		return {"existing": existing, "name_changed": name_changed, "is_reconnect": false, "is_update": true}

	# --- First registration: new peer ---
	var state: NetworkState = NetworkState.new()
	state.peer_id = sender_id
	state.player_name = player_name
	state.ship_id = StringName(ship_id_str)
	state.role = player_role
	var sdata: ShipData = ShipRegistry.get_ship_data(state.ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"

	var is_reconnect: bool = false
	var old_pid: int = -1
	if player_uuid != "":
		if _uuid_to_peer.has(player_uuid):
			old_pid = _uuid_to_peer[player_uuid]
			if old_pid != sender_id:
				# Transfer last known system to new peer_id
				if _player_last_system.has(old_pid):
					_player_last_system[sender_id] = _player_last_system[old_pid]
					_player_last_system.erase(old_pid)
				_peer_to_uuid.erase(old_pid)
				peers.erase(old_pid)
				is_reconnect = true
			else:
				old_pid = -1
		_uuid_to_peer[player_uuid] = sender_id
		_peer_to_uuid[sender_id] = player_uuid

	# Determine spawn system
	var default_sys: int = GameManager.current_system_id_safe() if GameManager else 0
	var spawn_sys: int = _player_last_system.get(sender_id, default_sys)
	state.system_id = spawn_sys
	peers[sender_id] = state

	return {"state": state, "spawn_sys": spawn_sys, "is_reconnect": is_reconnect, "old_pid": old_pid, "is_update": false}


## Remove a peer from the registry (on disconnect). Does NOT erase UUID maps (reconnect persistence).
func remove_peer(pid: int) -> void:
	peers.erase(pid)
	# Intentionally keep _player_last_system[pid] for reconnect persistence
	# Intentionally keep _peer_to_uuid / _uuid_to_peer for fleet NPC reconnect


## Clear all peer state (used on full disconnect).
func clear() -> void:
	peers.clear()
	_uuid_to_peer.clear()
	_peer_to_uuid.clear()


## Get all peer IDs whose system_id matches the given system.
func get_peers_in_system(sys_id: int) -> Array[int]:
	var result: Array[int] = []
	for pid in peers:
		if peers[pid].system_id == sys_id:
			result.append(pid)
	return result


## Get UUID for a peer_id (server-side).
func get_peer_uuid(pid: int) -> String:
	return _peer_to_uuid.get(pid, "")


## Get peer_id for a UUID (server-side). Returns -1 if offline.
func get_uuid_peer(uuid: String) -> int:
	return _uuid_to_peer.get(uuid, -1)


## Find a peer by player name (case-insensitive). Returns -1 if not found.
func find_peer_by_name(player_name: String) -> int:
	for pid in peers:
		if peers[pid].player_name.to_lower() == player_name.to_lower():
			return pid
	return -1


## Update last known system for a peer (called during state sync).
func update_last_system(pid: int, sys_id: int) -> void:
	_player_last_system[pid] = sys_id


## Get last known system for a peer.
func get_last_system(pid: int, default_val: int = -1) -> int:
	return _player_last_system.get(pid, default_val)


## Get all peer_id -> uuid pairs (for heartbeat).
func get_peer_to_uuid() -> Dictionary:
	return _peer_to_uuid
