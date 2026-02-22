class_name NetworkManagerSystem
extends Node

# =============================================================================
# Network Manager (Autoload) — MMORPG Architecture
#
# Transport: WebSocket (runs over HTTP/TCP — deployable on Railway/PaaS).
#
# Architecture: Single dedicated server on Railway (headless).
# All clients connect via wss://xxx.up.railway.app.
# Server is authoritative (validates, relays).
#
# Refactored into sub-managers under scripts/multiplayer/net/:
#   NetConnection      — WebSocket lifecycle & reconnect
#   NetPeerRegistry    — Peer/player tracking & UUID maps
#   NetChatServer      — Chat buffer, history, routing, backend
#   NetGroupManager    — Ephemeral party system
#   NetPlayerEvents    — Death, respawn, ship change, system change
#   NetCombatServer    — PvP hit validation
#
# CRITICAL: ALL @rpc methods MUST STAY in this file.
# Godot assigns RPC IDs per-node-path in declaration order.
# Moving @rpc decorators out of this file would break all inter-client RPC.
# =============================================================================

signal peer_connected(peer_id: int, player_name: String)
signal peer_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal server_connection_lost(reason: String)  ## Emitted only when a LIVE connection drops (not initial failures)
signal player_state_received(peer_id: int, state)
signal chat_message_received(sender_name: String, channel: int, text: String, corp_tag: String, sender_role: String)
signal whisper_received(sender_name: String, text: String)
signal chat_history_received(history: Array)
signal player_list_updated
signal server_config_received(config: Dictionary)

# Group (party) signals
signal group_invite_received(inviter_name: String, group_id: int)
signal group_updated(group_data: Dictionary)
signal group_dissolved(reason: String)
signal group_error(msg: String)

# System change sync (reliable)
signal player_left_system_received(peer_id: int)
signal player_entered_system_received(peer_id: int, ship_id: StringName)

# Player death/respawn sync (reliable)
signal player_died_received(peer_id: int, death_pos: Array, killer_pid: int, loot: Array)
signal player_respawned_received(peer_id: int, system_id: int)

# Ship change sync (reliable)
signal player_ship_changed_received(peer_id: int, new_ship_id: StringName)

# NPC sync signals
signal npc_batch_received(batch: Array)
signal npc_spawned(data: Dictionary)
signal npc_died(npc_id: String, killer_pid: int, death_pos: Array, loot: Array)

# Fleet sync signals
signal fleet_ship_deployed(owner_pid: int, fleet_index: int, npc_id: String, spawn_data: Dictionary)
signal fleet_ship_retrieved(owner_pid: int, fleet_index: int, npc_id: String)
signal fleet_command_changed(owner_pid: int, fleet_index: int, npc_id: String, cmd: String, params: Dictionary)

# Fleet confirmation signals (server -> requesting client only)
signal fleet_deploy_confirmed(fleet_index: int, npc_id: String)
signal fleet_retrieve_confirmed(fleet_index: int)
signal fleet_command_confirmed(fleet_index: int, cmd: String, params: Dictionary)

# Combat sync signals
signal remote_fire_received(peer_id: int, weapon_name: String, fire_pos: Array, fire_dir: Array)
signal player_damage_received(attacker_pid: int, weapon_name: String, damage_val: float, hit_dir: Array)
signal hit_effect_received(target_id: String, hit_dir: Array, shield_absorbed: bool)

# Mining sync signals
signal remote_mining_beam_received(peer_id: int, is_active: bool, source_pos: Array, target_pos: Array)
signal asteroid_depleted_received(asteroid_id: String)
signal asteroid_health_batch_received(batch: Array)

# Scanner pulse sync
signal remote_scanner_pulse_received(peer_id: int, scan_pos: Array)

# Structure (station) sync signals
@warning_ignore("unused_signal")
signal structure_hit_claimed(sender_pid: int, target_id: String, weapon: String, damage: float, hit_dir: Array)
signal structure_destroyed_received(struct_id: String, killer_pid: int, pos: Array, loot: Array)

# Event sync signals (pirate convoys etc.)
signal event_started_received(event_dict: Dictionary)
signal event_ended_received(event_dict: Dictionary)

# NPC fire relay signal
signal npc_fire_received(npc_id: String, weapon_name: String, fire_pos: Array, fire_dir: Array)

# Cargo crate sync
signal crate_picked_up_received(crate_id: String)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED }

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var local_player_name: String = ""  # Set from AuthManager.username on auth — never a local default
var local_ship_id: StringName = Constants.DEFAULT_SHIP_ID
var local_peer_id: int = -1

## True when this instance is the server (Railway dedicated).
var _is_server: bool = false

# Multi-galaxy: routing table (sent from server, used by client for wormhole handoff)
var galaxy_servers: Array[Dictionary] = []

# Sub-managers (RefCounted — NOT Node children)
var _connection: NetConnection = null
var _peer_registry: NetPeerRegistry = null
var _chat_server: NetChatServer = null
var _group_mgr: NetGroupManager = null
var _player_events: NetPlayerEvents = null
var _combat_server: NetCombatServer = null


# -------------------------------------------------------------------------
# Property getters — preserve the public API surface
# -------------------------------------------------------------------------

## peer_id -> NetworkState dictionary (all remote players).
var peers: Dictionary:
	get:
		return _peer_registry.peers


## Full ws/wss URL for reconnect display.
var server_url: String:
	get:
		return _connection.get_server_url()


## Local client group id (mirrors server-sent value).
var local_group_id: int:
	get:
		return _group_mgr.local_group_id
	set(v):
		_group_mgr.local_group_id = v


## Local client group data (mirrors server-sent value).
var local_group_data: Dictionary:
	get:
		return _group_mgr.local_group_data
	set(v):
		_group_mgr.local_group_data = v


# =========================================================================
# LIFECYCLE
# =========================================================================

func _ready() -> void:
	_is_server = _check_dedicated_server()
	_parse_galaxy_seed_arg()

	_connection = NetConnection.new(self)
	_peer_registry = NetPeerRegistry.new(self)
	_chat_server = NetChatServer.new(self)
	_group_mgr = NetGroupManager.new(self)
	_player_events = NetPlayerEvents.new(self)
	_combat_server = NetCombatServer.new(self)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_connection.tick(delta)

	if _is_server:
		if not _group_mgr._pending_invites.is_empty():
			_group_mgr.tick(Time.get_unix_time_from_system())
		_chat_server.tick(delta)


func _check_dedicated_server() -> bool:
	var args: Array = OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--headless":
			return true
	return DisplayServer.get_name() == "headless"


func _parse_galaxy_seed_arg() -> void:
	var args: Array = OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--galaxy-seed" and i + 1 < args.size():
			var seed_val: int = args[i + 1].to_int()
			if seed_val != 0:
				Constants.galaxy_seed = seed_val


# =========================================================================
# PUBLIC API
# =========================================================================

## Start the dedicated server (headless, Railway deployment).
func start_dedicated_server(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	var err: Error = _connection.start_server(port)
	if err != OK:
		return err
	_is_server = true
	_chat_server.ensure_chat_backend_client()
	_chat_server.ensure_heartbeat_backend_client()
	_chat_server.preload_and_emit_chat_history()
	return OK


## Connect to the Railway server as a client.
func connect_to_server(address: String, port: int = Constants.NET_DEFAULT_PORT) -> Error:
	return _connection.connect_to_server(address, port)


## Disconnect and clean up everything.
func disconnect_from_server() -> void:
	_connection.close()
	connection_state = ConnectionState.DISCONNECTED
	local_peer_id = -1
	_is_server = false
	_peer_registry.clear()
	_group_mgr.clear_all()
	player_list_updated.emit()


## Returns true if this instance is the server.
func is_server() -> bool:
	return _is_server


func is_connected_to_server() -> bool:
	return connection_state == ConnectionState.CONNECTED


## Get all peer IDs in a given star system (interest management).
func get_peers_in_system(system_id: int) -> Array[int]:
	return _peer_registry.get_peers_in_system(system_id)


## Get the UUID for a peer_id (server-side).
func get_peer_uuid(peer_id: int) -> String:
	return _peer_registry.get_peer_uuid(peer_id)


## Get the peer_id for a UUID (server-side). Returns -1 if offline.
func get_uuid_peer(uuid: String) -> int:
	return _peer_registry.get_uuid_peer(uuid)


# =========================================================================
# MULTIPLAYER CALLBACKS
# =========================================================================

func _on_peer_connected(id: int) -> void:
	if is_server():
		var peer_data: Array = []
		for pid in _peer_registry.peers:
			peer_data.append(_peer_registry.peers[pid].to_dict())
		_rpc_full_peer_list.rpc_id(id, peer_data)


func _on_peer_disconnected(id: int) -> void:
	var left_name: String = "Pilote #%d" % id
	if _peer_registry.peers.has(id):
		left_name = _peer_registry.peers[id].player_name

	if is_server():
		_group_mgr.handle_peer_disconnect(id)

	_peer_registry.remove_peer(id)

	if is_server():
		_rpc_player_left.rpc(id)
		var leave_sys: int = _peer_registry.get_last_system(id, -1)
		_rpc_receive_chat.rpc(left_name, 1, "%s a quitté." % left_name)
		_chat_server.store_message(1, left_name, "%s a quitté." % left_name, leave_sys)

		var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
		if npc_auth:
			var uuid: String = _peer_registry.get_peer_uuid(id)
			if uuid != "":
				npc_auth.on_player_disconnected(uuid, id)

	peer_disconnected.emit(id)
	player_list_updated.emit()


func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	local_peer_id = multiplayer.get_unique_id()
	_connection._reconnect_attempts = 0
	if AuthManager.is_authenticated and AuthManager.username != "":
		local_player_name = AuthManager.username
	var uuid: String = AuthManager.player_id if AuthManager.is_authenticated else ""
	var player_role: String = AuthManager.role if AuthManager.is_authenticated else "player"
	_rpc_register_player.rpc_id(1, local_player_name, String(local_ship_id), uuid, player_role)
	connection_succeeded.emit()


## Re-send player identity to the server (called by AuthManager after auth completes).
func re_register_identity() -> void:
	if not is_connected_to_server() or is_server():
		return
	if not AuthManager.is_authenticated:
		return
	local_player_name = AuthManager.username if AuthManager.username != "" else local_player_name
	var uuid: String = AuthManager.player_id
	var player_role: String = AuthManager.role
	_rpc_register_player.rpc_id(1, local_player_name, String(local_ship_id), uuid, player_role)
	print("[Net] Re-registered identity: name='%s' role='%s'" % [local_player_name, player_role])


func _on_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	_connection.on_connection_failed()


func _on_server_disconnected() -> void:
	connection_state = ConnectionState.DISCONNECTED
	local_peer_id = -1
	_is_server = false
	_group_mgr.clear_local_group()
	var peer_ids: Array = _peer_registry.peers.keys()
	_peer_registry.peers.clear()
	for pid in peer_ids:
		peer_disconnected.emit(pid)
	player_list_updated.emit()
	_connection.on_server_disconnected()
	var reason: String = "Serveur déconnecté. Reconnexion..."
	connection_failed.emit(reason)
	server_connection_lost.emit(reason)


# =========================================================================
# PUBLIC API — Chat & Group (thin wrappers calling RPCs)
# =========================================================================

## Send a chat message to the server.
func send_chat_message(channel: int, text: String) -> void:
	if is_server() or not is_connected_to_server():
		return
	print("[Chat] send_chat_message: ch=%d text='%s' peer=%d" % [channel, text, local_peer_id])
	_rpc_chat_message.rpc_id(1, channel, text)


## Send a whisper to the server.
func send_whisper(target_name: String, text: String) -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_whisper.rpc_id(1, target_name, text)


## Request to invite a player to your group.
func request_group_invite(target_peer_id: int) -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_request_group_invite.rpc_id(1, target_peer_id)


## Respond to an incoming group invite.
func respond_group_invite(accepted: bool) -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_respond_group_invite.rpc_id(1, accepted)


## Request to leave your current group.
func request_leave_group() -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_request_leave_group.rpc_id(1)


## Leader kicks a member from their group.
func request_kick_from_group(target_peer_id: int) -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_request_kick_from_group.rpc_id(1, target_peer_id)


## Check if a peer is in the local player's group (client-side).
func is_peer_in_my_group(peer_id: int) -> bool:
	return _group_mgr.is_peer_in_my_group(peer_id)


## Send an admin command to the server.
func send_admin_command(cmd: String) -> void:
	if not is_connected_to_server() or is_server():
		return
	_rpc_admin_command.rpc_id(1, cmd)


# =========================================================================
# RPCs — ALL @rpc methods MUST stay in this file (order is frozen)
# =========================================================================

## Client -> Server: Register as a new player (or update identity after auth).
@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, ship_id_str: String, player_uuid: String = "", player_role: String = "player") -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()

	var result: Dictionary = _peer_registry.register_or_update(sender_id, player_name, ship_id_str, player_uuid, player_role)

	if result["is_update"]:
		var existing: NetworkState = result["existing"]
		if result["name_changed"]:
			_rpc_player_registered.rpc(sender_id, player_name, ship_id_str, player_role, existing.system_id)
			print("[Server] Identité mise à jour: peer %d → '%s' (role=%s)" % [sender_id, player_name, player_role])
		return

	# First registration
	var spawn_sys: int = result["spawn_sys"]
	var is_reconnect: bool = result["is_reconnect"]
	var old_pid: int = result["old_pid"]

	# Reconnect: broadcast removal of the ghost old peer_id to all clients
	if is_reconnect and old_pid > 0:
		_rpc_player_left.rpc(old_pid)

	var config: Dictionary = {
		"galaxy_seed": Constants.galaxy_seed,
		"spawn_system_id": spawn_sys,
		"galaxies": galaxy_servers,
	}
	_rpc_server_config.rpc_id(sender_id, config)
	_chat_server.send_history_to_peer(sender_id, spawn_sys)

	if is_reconnect and player_uuid != "":
		var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
		if npc_auth:
			npc_auth.on_player_reconnected(player_uuid, sender_id)

	_rpc_player_registered.rpc(sender_id, player_name, ship_id_str, player_role, spawn_sys)

	print("[Server] Joueur '%s' (peer %d) enregistré dans systeme %d%s" % [player_name, sender_id, spawn_sys, " (reconnexion)" if is_reconnect else ""])
	var join_msg: String = "%s a rejoint le secteur (sys %d)." % [player_name, spawn_sys]
	_rpc_receive_chat.rpc(player_name, 1, join_msg)
	_chat_server.store_message(1, player_name, join_msg, spawn_sys)

	player_list_updated.emit()
	peer_connected.emit(sender_id, player_name)


## Server -> All clients: A new player has joined.
@rpc("authority", "reliable")
func _rpc_player_registered(pid: int, pname: String, ship_id_str: String, player_role: String = "player", sys_id: int = 0) -> void:
	if pid == local_peer_id:
		return
	if _peer_registry.peers.has(pid):
		var existing: NetworkState = _peer_registry.peers[pid]
		existing.player_name = pname
		existing.role = player_role
		if sys_id > 0:
			existing.system_id = sys_id
		return
	var state: NetworkState = NetworkState.new()
	state.peer_id = pid
	state.player_name = pname
	state.ship_id = StringName(ship_id_str)
	state.role = player_role
	state.system_id = sys_id
	var sdata: ShipData = ShipRegistry.get_ship_data(state.ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"
	_peer_registry.peers[pid] = state
	peer_connected.emit(pid, pname)
	player_list_updated.emit()


## Server -> All clients: A player has left.
@rpc("authority", "reliable")
func _rpc_player_left(pid: int) -> void:
	if _peer_registry.peers.has(pid):
		_peer_registry.peers.erase(pid)
	peer_disconnected.emit(pid)
	player_list_updated.emit()


## Server -> Single client: Full list of all connected players.
@rpc("authority", "reliable")
func _rpc_full_peer_list(peer_data: Array) -> void:
	for d in peer_data:
		var state: NetworkState = NetworkState.new()
		state.from_dict(d)
		if state.peer_id != local_peer_id:
			_peer_registry.peers[state.peer_id] = state
			peer_connected.emit(state.peer_id, state.player_name)
	player_list_updated.emit()


## Client -> Server: Position/state update (20Hz).
@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_state(state_dict: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if is_server():
		if not _peer_registry.peers.has(sender_id):
			return
		var state: NetworkState = _peer_registry.peers[sender_id]
		var saved_name: String = state.player_name
		var saved_role: String = state.role
		var saved_group_id: int = state.group_id
		var saved_system_id: int = state.system_id
		var saved_ship_id: StringName = state.ship_id
		state.from_dict(state_dict)
		state.peer_id = sender_id
		state.player_name = saved_name
		state.role = saved_role
		state.group_id = saved_group_id
		state.system_id = saved_system_id
		state.ship_id = saved_ship_id
		_peer_registry.update_last_system(sender_id, state.system_id)


## Server -> Client: Another player's state update.
@rpc("authority", "unreliable_ordered")
func _rpc_receive_remote_state(pid: int, state_dict: Dictionary) -> void:
	if _peer_registry.peers.has(pid):
		var state: NetworkState = _peer_registry.peers[pid]
		var saved_name: String = state.player_name
		var saved_role: String = state.role
		var saved_group_id: int = state.group_id
		var saved_ship_id: StringName = state.ship_id
		state.from_dict(state_dict)
		state.peer_id = pid
		state.player_name = saved_name
		state.role = saved_role
		state.group_id = saved_group_id
		state.ship_id = saved_ship_id
		player_state_received.emit(pid, state)
	else:
		var state: NetworkState = NetworkState.new()
		state.from_dict(state_dict)
		state.peer_id = pid
		player_state_received.emit(pid, state)


## Client -> Server: Chat message (scoped by channel).
@rpc("any_peer", "reliable")
func _rpc_chat_message(channel: int, text: String) -> void:
	print("[Chat] _rpc_chat_message received: ch=%d text='%s' is_server=%s" % [channel, text, is_server()])
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_chat_server.route_chat(sender_id, channel, text)


## Server -> All/Some clients: Chat message broadcast.
@rpc("authority", "reliable")
func _rpc_receive_chat(sender_name: String, channel: int, text: String, corp_tag: String = "", sender_role: String = "player") -> void:
	chat_message_received.emit(sender_name, channel, text, corp_tag, sender_role)


## Server -> Client: Chat history on connect.
@rpc("authority", "reliable")
func _rpc_chat_history(history: Array) -> void:
	print("[Chat] Client received chat history: %d messages" % history.size())
	chat_history_received.emit(history)


## Client -> Server: Whisper (private message) to a named player.
@rpc("any_peer", "reliable")
func _rpc_whisper(target_name: String, text: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_chat_server.handle_whisper(sender_id, target_name, text)


## Server -> Client: Whisper received.
@rpc("authority", "reliable")
func _rpc_receive_whisper(sender_name: String, text: String) -> void:
	whisper_received.emit(sender_name, text)


## Server -> Single client: Server configuration (galaxy seed, spawn system, routing table).
@rpc("authority", "reliable")
func _rpc_server_config(config: Dictionary) -> void:
	galaxy_servers = config.get("galaxies", [])
	server_config_received.emit(config)


# =========================================================================
# NPC SYNC RPCs
# =========================================================================

## Server -> Client: Batch of NPC state updates.
@rpc("authority", "unreliable_ordered")
func _rpc_npc_batch(batch: Array) -> void:
	npc_batch_received.emit(batch)


## Server -> Client: A new NPC has spawned.
@rpc("authority", "reliable")
func _rpc_npc_spawned(npc_dict: Dictionary) -> void:
	npc_spawned.emit(npc_dict)


## Server -> Client: An NPC has died.
@rpc("authority", "reliable")
func _rpc_npc_died(npc_id_str: String, killer_pid: int, death_pos: Array, loot: Array) -> void:
	npc_died.emit(npc_id_str, killer_pid, death_pos, loot)


# =========================================================================
# COMBAT SYNC RPCs
# =========================================================================

## Client -> Server: Player fired a weapon (visual only, loss-tolerant).
@rpc("any_peer", "unreliable_ordered")
func _rpc_fire_event(weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.relay_fire_event(sender_id, weapon_name, fire_pos, fire_dir)


## Server -> Client: Another player fired a weapon (visual only).
@rpc("authority", "unreliable_ordered")
func _rpc_remote_fire(peer_id: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	remote_fire_received.emit(peer_id, weapon_name, fire_pos, fire_dir)


## Client -> Server: Player claims a hit on an NPC.
@rpc("any_peer", "reliable")
func _rpc_hit_claim(target_npc: String, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.validate_hit_claim(sender_id, target_npc, weapon_name, damage_val, hit_dir)


## Any peer -> Server: Player claims a hit on another player.
@rpc("any_peer", "reliable")
func _rpc_player_hit_claim(target_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_combat_server.validate_hit(sender_id, target_pid, weapon_name, damage_val, hit_dir)


## Server -> Target client: You've been hit by another player.
@rpc("authority", "reliable")
func _rpc_receive_player_damage(attacker_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	player_damage_received.emit(attacker_pid, weapon_name, damage_val, hit_dir)


## Server -> Client: A hit effect should be displayed on target (visual only).
@rpc("authority", "unreliable_ordered")
func _rpc_hit_effect(target_id: String, hit_dir: Array, shield_absorbed: bool) -> void:
	hit_effect_received.emit(target_id, hit_dir, shield_absorbed)


# =========================================================================
# NPC FIRE RELAY RPCs
# =========================================================================

## Server -> Client: An NPC fired a weapon (visual only).
@rpc("authority", "unreliable_ordered")
func _rpc_npc_fire(npc_id_str: String, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	npc_fire_received.emit(npc_id_str, weapon_name, fire_pos, fire_dir)


# =========================================================================
# PLAYER DEATH / RESPAWN RPCs (reliable)
# =========================================================================

## Client -> Server: I just died (includes cargo for PvP loot drop).
@rpc("any_peer", "reliable")
func _rpc_player_died(death_pos: Array, cargo_loot: Array = []) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_player_events.handle_death(sender_id, death_pos, cargo_loot)


## Server -> Client: A player has died (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_died(pid: int, death_pos: Array, killer_pid: int, loot: Array) -> void:
	player_died_received.emit(pid, death_pos, killer_pid, loot)


## Client -> Server: I just respawned.
@rpc("any_peer", "reliable")
func _rpc_player_respawned(system_id: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_player_events.handle_respawn(sender_id, system_id)


## Server -> Client: A player has respawned (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_respawned(pid: int, system_id: int) -> void:
	player_respawned_received.emit(pid, system_id)


# =========================================================================
# CARGO CRATE SYNC RPCs (reliable)
# =========================================================================

## Client -> Server: I picked up a cargo crate.
@rpc("any_peer", "reliable")
func _rpc_crate_picked_up(crate_id: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var state = peers.get(sender_id)
	if state == null:
		return
	for pid in get_peers_in_system(state.system_id):
		if pid == sender_id:
			continue
		_rpc_receive_crate_picked_up.rpc_id(pid, crate_id)


## Server -> Client: A cargo crate was picked up (destroy it locally).
@rpc("authority", "reliable")
func _rpc_receive_crate_picked_up(crate_id: String) -> void:
	crate_picked_up_received.emit(crate_id)


# =========================================================================
# SHIP CHANGE RPCs (reliable)
# =========================================================================

## Client -> Server: I changed my ship.
@rpc("any_peer", "reliable")
func _rpc_player_ship_changed(new_ship_id_str: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_player_events.handle_ship_change(sender_id, new_ship_id_str)


## Server -> Client: A player changed their ship (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_ship_changed(pid: int, new_ship_id_str: String) -> void:
	var new_sid: StringName = StringName(new_ship_id_str)
	if _peer_registry.peers.has(pid):
		_peer_registry.peers[pid].ship_id = new_sid
		var sdata: ShipData = ShipRegistry.get_ship_data(new_sid)
		_peer_registry.peers[pid].ship_class = sdata.ship_class if sdata else &"Fighter"
	player_ship_changed_received.emit(pid, new_sid)


# =========================================================================
# SYSTEM CHANGE RPCs (reliable instant notification)
# =========================================================================

## Client -> Server: I just changed star system (via jump gate/wormhole).
@rpc("any_peer", "reliable")
func _rpc_player_system_changed(old_system_id: int, new_system_id: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_player_events.handle_system_change(sender_id, old_system_id, new_system_id)


## Server -> Client: A player left your system (remove puppet immediately).
@rpc("authority", "reliable")
func _rpc_receive_player_left_system(pid: int) -> void:
	player_left_system_received.emit(pid)


## Server -> Client: A player entered your system (create puppet).
@rpc("authority", "reliable")
func _rpc_receive_player_entered_system(pid: int, ship_id_str: String) -> void:
	if _peer_registry.peers.has(pid):
		_peer_registry.peers[pid].ship_id = StringName(ship_id_str)
		var local_sys: int = GameManager.current_system_id_safe() if GameManager else 0
		_peer_registry.peers[pid].system_id = local_sys
	player_entered_system_received.emit(pid, StringName(ship_id_str))


# =========================================================================
# FLEET DEPLOYMENT RPCs
# =========================================================================

## Client -> Server: Request to deploy a fleet ship.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_deploy(fleet_index: int, cmd_str: String, params_json: String, ship_data_json: String = "") -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var params: Dictionary = {}
		if params_json != "":
			var parsed = JSON.parse_string(params_json)
			if parsed is Dictionary:
				params = parsed
		var ship_data: Dictionary = {}
		if ship_data_json != "":
			var parsed_sd = JSON.parse_string(ship_data_json)
			if parsed_sd is Dictionary:
				ship_data = parsed_sd
		npc_auth.handle_fleet_deploy_request(sender_id, fleet_index, StringName(cmd_str), params, ship_data)


## Client -> Server: Request to retrieve a fleet ship.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_retrieve(fleet_index: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.handle_fleet_retrieve_request(sender_id, fleet_index)


## Client -> Server: Request to change fleet ship command.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_command(fleet_index: int, cmd_str: String, params_json: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var params: Dictionary = {}
		if params_json != "":
			var parsed = JSON.parse_string(params_json)
			if parsed is Dictionary:
				params = parsed
		npc_auth.handle_fleet_command_request(sender_id, fleet_index, StringName(cmd_str), params)


## Server -> Client: A fleet ship has been deployed.
@rpc("authority", "reliable")
func _rpc_fleet_deployed(owner_pid: int, fleet_idx: int, npc_id_str: String, spawn_data: Dictionary) -> void:
	fleet_ship_deployed.emit(owner_pid, fleet_idx, npc_id_str, spawn_data)


## Server -> Client: A fleet ship has been retrieved (despawned).
@rpc("authority", "reliable")
func _rpc_fleet_retrieved(owner_pid: int, fleet_idx: int, npc_id_str: String) -> void:
	fleet_ship_retrieved.emit(owner_pid, fleet_idx, npc_id_str)


## Server -> Client: A fleet ship's command has changed.
@rpc("authority", "reliable")
func _rpc_fleet_command_changed(owner_pid: int, fleet_idx: int, npc_id_str: String, cmd_str: String, params: Dictionary) -> void:
	fleet_command_changed.emit(owner_pid, fleet_idx, npc_id_str, cmd_str, params)


## Server -> Requesting client: Deploy confirmed with assigned NPC ID.
@rpc("authority", "reliable")
func _rpc_fleet_deploy_confirmed(fleet_index: int, npc_id_str: String) -> void:
	fleet_deploy_confirmed.emit(fleet_index, npc_id_str)


## Server -> Requesting client: Retrieve confirmed.
@rpc("authority", "reliable")
func _rpc_fleet_retrieve_confirmed(fleet_index: int) -> void:
	fleet_retrieve_confirmed.emit(fleet_index)


## Server -> Requesting client: Command change confirmed.
@rpc("authority", "reliable")
func _rpc_fleet_command_confirmed(fleet_index: int, cmd_str: String, params: Dictionary) -> void:
	fleet_command_confirmed.emit(fleet_index, cmd_str, params)


# =========================================================================
# MINING SYNC RPCs
# =========================================================================

## Client -> Server: Mining beam state (10Hz, visual only).
@rpc("any_peer", "unreliable_ordered")
func _rpc_mining_beam(is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.relay_mining_beam(sender_id, is_active, source_pos, target_pos)


## Server -> Client: Another player's mining beam state.
@rpc("authority", "unreliable_ordered")
func _rpc_remote_mining_beam(peer_id: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	remote_mining_beam_received.emit(peer_id, is_active, source_pos, target_pos)


## Client -> Server: An asteroid was depleted by this player.
@rpc("any_peer", "reliable")
func _rpc_asteroid_depleted(asteroid_id_str: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var sender_state = _peer_registry.peers.get(sender_id)
		if sender_state:
			npc_auth.broadcast_asteroid_depleted(asteroid_id_str, sender_state.system_id, sender_id)


## Server -> Client: An asteroid was depleted by another player.
@rpc("authority", "reliable")
func _rpc_receive_asteroid_depleted(asteroid_id_str: String) -> void:
	asteroid_depleted_received.emit(asteroid_id_str)


## Client -> Server: batch of mining damage claims (0.5s interval).
@rpc("any_peer", "reliable")
func _rpc_mining_damage_claim(claims: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth:
		npc_auth.handle_mining_damage_claims(sender_id, claims)


## Server -> Client: batch of asteroid health ratios (2Hz).
@rpc("authority", "unreliable_ordered")
func _rpc_asteroid_health_batch(batch: Array) -> void:
	asteroid_health_batch_received.emit(batch)


# =============================================================================
# STRUCTURE (STATION) SYNC
# =============================================================================

## Client -> Server: A projectile hit a station.
@rpc("any_peer", "reliable")
func _rpc_structure_hit_claim(target_id: String, weapon: String, damage: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_combat_server.validate_structure_hit(sender_id, target_id, weapon, damage, hit_dir)


## Server -> Client: Batch sync of structure health ratios.
@rpc("authority", "unreliable_ordered")
func _rpc_structure_batch(batch: Array) -> void:
	var struct_auth: Node = GameManager.get_node_or_null("StructureAuthority") as Node
	if struct_auth:
		struct_auth.apply_batch(batch)


## Server -> Client: A structure was destroyed.
@rpc("authority", "reliable")
func _rpc_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array) -> void:
	var struct_auth: Node = GameManager.get_node_or_null("StructureAuthority") as Node
	if struct_auth:
		struct_auth.apply_structure_destroyed(struct_id, killer_pid, pos, loot)
	structure_destroyed_received.emit(struct_id, killer_pid, pos, loot)


# =============================================================================
# EVENT SYNC (pirate convoys etc.)
# =============================================================================

## Server -> Client: An event started in your system.
@rpc("authority", "reliable")
func _rpc_event_started(event_dict: Dictionary) -> void:
	event_started_received.emit(event_dict)


## Server -> Client: An event ended in your system.
@rpc("authority", "reliable")
func _rpc_event_ended(event_dict: Dictionary) -> void:
	event_ended_received.emit(event_dict)


# =============================================================================
# EPHEMERAL GROUP (PARTY) SYSTEM RPCs
# =============================================================================

## Client -> Server: Request to invite another player.
@rpc("any_peer", "reliable")
func _rpc_request_group_invite(target_pid: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_group_mgr.handle_invite(sender_id, target_pid)


## Client -> Server: Accept or decline an invite.
@rpc("any_peer", "reliable")
func _rpc_respond_group_invite(accepted: bool) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_group_mgr.handle_response(sender_id, accepted)


## Client -> Server: Leave group.
@rpc("any_peer", "reliable")
func _rpc_request_leave_group() -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_group_mgr.handle_leave(sender_id)


## Client -> Server: Leader kicks a member.
@rpc("any_peer", "reliable")
func _rpc_request_kick_from_group(target_pid: int) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_group_mgr.handle_kick(sender_id, target_pid)


## Server -> Client: You've been invited to a group.
@rpc("authority", "reliable")
func _rpc_receive_group_invite(inviter_name: String, _gid: int) -> void:
	group_invite_received.emit(inviter_name, _gid)


## Server -> Client: Group state update (members list).
@rpc("authority", "reliable")
func _rpc_receive_group_update(gdata: Dictionary) -> void:
	_group_mgr.apply_group_update(gdata)
	group_updated.emit(gdata)


## Server -> Client: Your group has been dissolved.
@rpc("authority", "reliable")
func _rpc_receive_group_dissolved(reason: String) -> void:
	_group_mgr.clear_local_group()
	group_dissolved.emit(reason)


## Server -> Client: Error message (does NOT dissolve the group).
@rpc("authority", "reliable")
func _rpc_receive_group_error(msg: String) -> void:
	group_error.emit(msg)
	chat_message_received.emit("SYSTÈME", 1, msg, "", "player")


# =============================================================================
# ADMIN COMMANDS — kept at END of file so @rpc IDs don't shift existing methods
# =============================================================================

## Client -> Server: Admin command (role verified server-side).
@rpc("any_peer", "reliable")
func _rpc_admin_command(cmd: String) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var sender_state = _peer_registry.peers.get(sender_id)
	if sender_state == null or sender_state.role != "admin":
		push_warning("[NetworkManager] Admin command '%s' from non-admin peer %d — rejected" % [cmd, sender_id])
		return
	match cmd:
		"reset_npcs":
			var npc_auth = GameManager.get_node_or_null("NpcAuthority")
			if npc_auth:
				npc_auth.admin_reset_all_npcs()
			_rpc_receive_chat.rpc("♛ ADMIN", 0, "Réinitialisation des PNJ effectuée.", "", "admin")


## Server -> Clients: All NPCs have been reset by admin. Clear remote NPC nodes.
@rpc("authority", "reliable")
func _rpc_admin_npcs_reset() -> void:
	var sync_mgr = GameManager.get_node_or_null("NetworkSyncManager")
	if sync_mgr and sync_mgr.has_method("clear_all_remote_npcs"):
		sync_mgr.clear_all_remote_npcs()


# =============================================================================
# SCANNER PULSE SYNC (visual wavefront for other players)
# =============================================================================

## Client -> Server: Player triggered a scanner pulse.
@rpc("any_peer", "reliable")
func _rpc_scanner_pulse(scan_pos: Array) -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth: Node = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.relay_scanner_pulse(sender_id, scan_pos)


## Server -> Client: Another player triggered a scanner pulse (visual only).
@rpc("authority", "reliable")
func _rpc_remote_scanner_pulse(peer_id: int, scan_pos: Array) -> void:
	remote_scanner_pulse_received.emit(peer_id, scan_pos)
