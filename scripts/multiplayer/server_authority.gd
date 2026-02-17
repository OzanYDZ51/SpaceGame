class_name ServerAuthority
extends Node

# =============================================================================
# Server Authority - Runs on the dedicated server.
# Validates client actions, manages game state, broadcasts world updates.
# Stays dormant until NetworkManager.is_server() becomes true.
#
# Phase 1: Position relay (server stores + forwards player positions).
# Future: Combat validation, NPC management, economy.
# =============================================================================

var _world_broadcast_timer: float = 0.0
var _active: bool = false


func _ready() -> void:
	# Don't self-destruct; wait for the player to host or for dedicated mode.
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if NetworkManager.is_server() and not _active:
		_active = true
		print("ServerAuthority: Activated (server mode)")


func _physics_process(delta: float) -> void:
	if not _active or not NetworkManager.is_server():
		return

	_world_broadcast_timer -= delta
	if _world_broadcast_timer <= 0.0:
		_world_broadcast_timer = 1.0 / Constants.NET_TICK_RATE
		_broadcast_world_state()


## Broadcasts all player states to all connected clients.
## Each client only receives states of players in the same system.
func _broadcast_world_state() -> void:
	var peers =NetworkManager.peers
	if peers.size() < 2:
		return  # Need at least 2 players to broadcast

	# Group peers by system
	var by_system: Dictionary = {}  # system_id -> Array[int peer_ids]
	for pid in peers:
		var state = peers[pid]
		if not by_system.has(state.system_id):
			by_system[state.system_id] = []
		by_system[state.system_id].append(pid)

	# For each system, send all peer states to all peers in that system
	for system_id in by_system:
		var system_peers: Array = by_system[system_id]
		if system_peers.size() < 2:
			continue

		for pid in system_peers:
			for other_pid in system_peers:
				if other_pid == pid:
					continue
				if not NetworkManager.peers.has(other_pid):
					continue
				var state = NetworkManager.peers[other_pid]
				if pid == 1 and not NetworkManager.is_dedicated_server:
					# Host is local — deliver via signal, not RPC
					NetworkManager.player_state_received.emit(other_pid, state)
				else:
					NetworkManager._rpc_receive_remote_state.rpc_id(pid, other_pid, state.to_dict())
