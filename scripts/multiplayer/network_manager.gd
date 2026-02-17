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
# =============================================================================

signal peer_connected(peer_id: int, player_name: String)
signal peer_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal server_connection_lost(reason: String)  ## Emitted only when a LIVE connection drops (not initial failures)
signal player_state_received(peer_id: int, state)
signal chat_message_received(sender_name: String, channel: int, text: String)
signal whisper_received(sender_name: String, text: String)
signal chat_history_received(history: Array)
signal player_list_updated
signal server_config_received(config: Dictionary)

# Player death/respawn sync (reliable)
signal player_died_received(peer_id: int, death_pos: Array)
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

# Structure (station) sync signals
signal structure_hit_claimed(sender_pid: int, target_id: String, weapon: String, damage: float, hit_dir: Array)
signal structure_destroyed_received(struct_id: String, killer_pid: int, pos: Array, loot: Array)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED }

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var local_player_name: String = "Pilote"
var local_ship_id: StringName = Constants.DEFAULT_SHIP_ID
var local_peer_id: int = -1

## True when this instance is the server (Railway dedicated).
var _is_server: bool = false

# peer_id -> NetworkState (all remote players)
var peers: Dictionary = {}

# Server config
var _server_url: String = ""  # Full ws:// or wss:// URL for reconnect
var _server_port: int = Constants.NET_DEFAULT_PORT
var _peer: WebSocketMultiplayerPeer = null
var _reconnect_timer: float = 0.0
var _reconnect_attempts: int = 0
const MAX_RECONNECT_ATTEMPTS: int = 5
const RECONNECT_DELAY: float = 3.0

# PvP kill attribution: target_pid -> { "attacker_pid": int, "weapon": String, "time": float }
var _pvp_last_attacker: Dictionary = {}

# Multi-galaxy: routing table (sent from server, used by client for wormhole handoff)
# Each entry: { "seed": int, "name": String, "url": String }
var galaxy_servers: Array[Dictionary] = []

# Server-side: track each player's last known system (in-memory persistence)
var _player_last_system: Dictionary = {}  # peer_id -> system_id

# UUID ↔ peer_id mapping (server-side, persists across reconnects)
var _uuid_to_peer: Dictionary = {}  # player_uuid (String) -> peer_id (int)
var _peer_to_uuid: Dictionary = {}  # peer_id (int) -> player_uuid (String)

# Chat persistence: in-memory buffer (primary) + backend DB (long-term)
const CHAT_BUFFER_SIZE: int = 200
const CHAT_HISTORY_LIMIT: int = 50  # Max messages sent to clients on connect
var _chat_buffer: Array = []  # [{s, t, ts, ch, sys}] — server-side ring buffer
var _chat_backend_client: ServerBackendClient = null
var _chat_preload_done: bool = false

# Heartbeat: periodically update last_seen_at for connected players (server-side)
const HEARTBEAT_INTERVAL: float = 60.0
var _heartbeat_timer: float = 0.0
var _heartbeat_backend_client: ServerBackendClient = null


func _ready() -> void:
	_is_server = _check_dedicated_server()
	_parse_galaxy_seed_arg()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if connection_state == ConnectionState.DISCONNECTED and _reconnect_attempts > 0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_attempt_reconnect()

	# Server-side heartbeat: update last_seen_at for all connected players
	if _is_server and _heartbeat_backend_client != null:
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = HEARTBEAT_INTERVAL
			_send_heartbeat()


func _check_dedicated_server() -> bool:
	var args =OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--headless":
			return true
	return DisplayServer.get_name() == "headless"


func _parse_galaxy_seed_arg() -> void:
	var args =OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--galaxy-seed" and i + 1 < args.size():
			var seed_val: int = args[i + 1].to_int()
			if seed_val != 0:
				Constants.galaxy_seed = seed_val


# =========================================================================
# PUBLIC API
# =========================================================================

## Start the dedicated server (headless, no local player).
## Used for production Railway deployment.
func start_dedicated_server(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	# Railway sets PORT env var dynamically
	var env_port: String = OS.get_environment("PORT")
	if env_port != "":
		var parsed_port =env_port.to_int()
		if parsed_port > 0 and parsed_port <= 65535:
			port = parsed_port
		else:
			push_warning("NetworkManager: Invalid PORT env '%s', using default %d" % [env_port, port])
	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	var err =_peer.create_server(port)
	if err != OK:
		push_error("NetworkManager: Failed to start dedicated server on port %d: %s" % [port, error_string(err)])
		connection_failed.emit("Failed to start server: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTED
	local_peer_id = 1
	_is_server = true
	print("========================================")
	print("  DEDICATED SERVER LISTENING ON PORT %d" % port)
	print("========================================")
	_ensure_chat_backend_client()
	_ensure_heartbeat_backend_client()
	_heartbeat_timer = HEARTBEAT_INTERVAL
	_preload_and_emit_chat_history()
	connection_succeeded.emit()
	return OK


## Connect to the Railway server as a client.
## address: A full WebSocket URL (e.g., "wss://gameserver-production-49ba.up.railway.app")
func connect_to_server(address: String, port: int = Constants.NET_DEFAULT_PORT) -> Error:
	if connection_state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected or connecting")
		return ERR_ALREADY_IN_USE

	# Build WebSocket URL
	var url: String
	if address.begins_with("ws://") or address.begins_with("wss://"):
		url = address
	else:
		url = "ws://%s:%d" % [address, port]

	_server_url = url
	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	var err =_peer.create_client(url)
	if err != OK:
		push_error("NetworkManager: Failed to connect to %s: %s" % [url, error_string(err)])
		connection_failed.emit("Connexion échouée: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTING
	_reconnect_attempts = 0
	return OK


## Disconnect and clean up everything.
func disconnect_from_server() -> void:
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	connection_state = ConnectionState.DISCONNECTED
	_reconnect_attempts = 0
	local_peer_id = -1
	_is_server = false
	peers.clear()
	_uuid_to_peer.clear()
	_peer_to_uuid.clear()
	_chat_buffer.clear()
	player_list_updated.emit()


## Returns true if this instance is the server.
func is_server() -> bool:
	return _is_server


func is_connected_to_server() -> bool:
	return connection_state == ConnectionState.CONNECTED


## Get all peer IDs in a given star system (interest management).
func get_peers_in_system(system_id: int) -> Array[int]:
	var result: Array[int] = []
	for pid in peers:
		var state = peers[pid]
		if state.system_id == system_id:
			result.append(pid)
	return result


## Get the UUID for a peer_id (server-side).
func get_peer_uuid(peer_id: int) -> String:
	return _peer_to_uuid.get(peer_id, "")


## Get the peer_id for a UUID (server-side). Returns -1 if offline.
func get_uuid_peer(uuid: String) -> int:
	return _uuid_to_peer.get(uuid, -1)


# =========================================================================
# MULTIPLAYER CALLBACKS
# =========================================================================

func _on_peer_connected(id: int) -> void:
	if is_server():
		# Send full peer list to the new peer
		var peer_data: Array = []
		for pid in peers:
			peer_data.append(peers[pid].to_dict())
		_rpc_full_peer_list.rpc_id(id, peer_data)


func _on_peer_disconnected(id: int) -> void:
	var left_name ="Pilote #%d" % id
	if peers.has(id):
		left_name = peers[id].player_name
		peers.erase(id)
	# Keep _player_last_system[id] for reconnect persistence (don't erase)
	# Keep _peer_to_uuid / _uuid_to_peer for fleet NPC reconnect (don't erase)

	if is_server():
		_rpc_player_left.rpc(id)
		# Broadcast system chat: player left
		var leave_sys: int = _player_last_system.get(id, -1)
		_rpc_receive_chat.rpc(left_name, 1, "%s a quitté." % left_name)
		_store_chat_message(1, left_name, "%s a quitté." % left_name, leave_sys)

		# Notify NpcAuthority about disconnect (fleet NPCs persist)
		var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
		if npc_auth:
			var uuid: String = _peer_to_uuid.get(id, "")
			if uuid != "":
				npc_auth.on_player_disconnected(uuid, id)

	peer_disconnected.emit(id)
	player_list_updated.emit()


func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	local_peer_id = multiplayer.get_unique_id()
	_reconnect_attempts = 0
	# Use AuthManager username as source of truth (local_player_name may be stale)
	if AuthManager.is_authenticated and AuthManager.username != "":
		local_player_name = AuthManager.username
	# Register with the server (include UUID for fleet persistence)
	var uuid: String = AuthManager.player_id if AuthManager.is_authenticated else ""
	_rpc_register_player.rpc_id(1, local_player_name, String(local_ship_id), uuid)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	if _reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
		_reconnect_attempts += 1
		_reconnect_timer = RECONNECT_DELAY
		connection_failed.emit("Connexion échouée. Tentative %d/%d..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	else:
		connection_failed.emit("Connexion impossible après %d tentatives." % MAX_RECONNECT_ATTEMPTS)


func _on_server_disconnected() -> void:
	connection_state = ConnectionState.DISCONNECTED
	local_peer_id = -1
	_is_server = false
	# Emit peer_disconnected for each peer so NetworkSyncManager can clean up puppets
	var peer_ids =peers.keys()
	peers.clear()
	for pid in peer_ids:
		peer_disconnected.emit(pid)
	player_list_updated.emit()
	_reconnect_attempts += 1
	_reconnect_timer = RECONNECT_DELAY
	var reason := "Serveur déconnecté. Reconnexion..."
	connection_failed.emit(reason)
	server_connection_lost.emit(reason)


func _attempt_reconnect() -> void:
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		connection_failed.emit("Reconnexion échouée.")
		_reconnect_attempts = 0
		return
	if _server_url != "":
		connect_to_server(_server_url)
	else:
		connect_to_server(Constants.NET_GAME_SERVER_URL)


# =========================================================================
# RPCs
# =========================================================================

## Client -> Server: Register as a new player.
@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, ship_id_str: String, player_uuid: String = "") -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var state =NetworkState.new()
	state.peer_id = sender_id
	state.player_name = player_name
	state.ship_id = StringName(ship_id_str)
	var sdata: ShipData = ShipRegistry.get_ship_data(state.ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"

	# Track UUID ↔ peer mapping
	var is_reconnect: bool = false
	if player_uuid != "":
		# Clean up old peer mapping for this UUID (reconnect case)
		if _uuid_to_peer.has(player_uuid):
			var old_pid: int = _uuid_to_peer[player_uuid]
			if old_pid != sender_id:
				# Transfer last known system to new peer_id
				if _player_last_system.has(old_pid):
					_player_last_system[sender_id] = _player_last_system[old_pid]
					_player_last_system.erase(old_pid)
				_peer_to_uuid.erase(old_pid)
				peers.erase(old_pid)  # Safety: remove stale peer entry
				# Notify all clients to remove the ghost of the old peer_id
				_rpc_player_left.rpc(old_pid)
				is_reconnect = true
		_uuid_to_peer[player_uuid] = sender_id
		_peer_to_uuid[sender_id] = player_uuid

	# Send server config to the new client (galaxy seed, spawn system, routing)
	# For new players, default to the host's current system (not -1)
	var default_sys: int = GameManager.current_system_id_safe() if GameManager else 0
	var spawn_sys: int = _player_last_system.get(sender_id, default_sys)
	# Set the client's system_id NOW so NPC batch filtering includes them immediately
	state.system_id = spawn_sys
	peers[sender_id] = state

	var config ={
		"galaxy_seed": Constants.galaxy_seed,
		"spawn_system_id": spawn_sys,
		"galaxies": galaxy_servers,
	}
	_rpc_server_config.rpc_id(sender_id, config)

	# Send chat history to the new client
	_send_chat_history(sender_id, spawn_sys)

	# Handle reconnect: re-associate fleet NPCs with the new peer_id
	if is_reconnect and player_uuid != "":
		var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
		if npc_auth:
			npc_auth.on_player_reconnected(player_uuid, sender_id)

	# Notify ALL clients (including new one) about this player
	_rpc_player_registered.rpc(sender_id, player_name, ship_id_str)

	# Broadcast system chat: player joined (include system ID for diagnostics)
	print("[Server] Joueur '%s' (peer %d) enregistré dans systeme %d%s" % [player_name, sender_id, spawn_sys, " (reconnexion)" if is_reconnect else ""])
	var join_msg := "%s a rejoint le secteur (sys %d)." % [player_name, spawn_sys]
	_rpc_receive_chat.rpc(player_name, 1, join_msg)
	_store_chat_message(1, player_name, join_msg, spawn_sys)

	player_list_updated.emit()

	# Emit peer_connected on the SERVER so NetworkSyncManager can create
	# the RemotePlayerShip and send NPCs to the new client via _deferred_send_npcs_to_peer.
	# (The _rpc_player_registered RPC returns early on the server because
	# the peer was already added to peers dict above, so peer_connected
	# would never fire on the server without this explicit emit.)
	peer_connected.emit(sender_id, player_name)


## Server -> All clients: A new player has joined.
@rpc("authority", "reliable")
func _rpc_player_registered(pid: int, pname: String, ship_id_str: String) -> void:
	# Never add ourselves to our own peers dict (causes ghost self-player)
	if pid == local_peer_id:
		return
	if peers.has(pid):
		return
	var state =NetworkState.new()
	state.peer_id = pid
	state.player_name = pname
	state.ship_id = StringName(ship_id_str)
	var sdata: ShipData = ShipRegistry.get_ship_data(state.ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"
	peers[pid] = state

	peer_connected.emit(pid, pname)
	player_list_updated.emit()


## Server -> All clients: A player has left.
@rpc("authority", "reliable")
func _rpc_player_left(pid: int) -> void:
	if peers.has(pid):
		peers.erase(pid)
	peer_disconnected.emit(pid)
	player_list_updated.emit()


## Server -> Single client: Full list of all connected players.
@rpc("authority", "reliable")
func _rpc_full_peer_list(peer_data: Array) -> void:
	for d in peer_data:
		var state =NetworkState.new()
		state.from_dict(d)
		if state.peer_id != local_peer_id:
			peers[state.peer_id] = state
			peer_connected.emit(state.peer_id, state.player_name)
	player_list_updated.emit()


## Client -> Server: Position/state update (20Hz).
@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_state(state_dict: Dictionary) -> void:
	var sender_id =multiplayer.get_remote_sender_id()

	if is_server():
		if not peers.has(sender_id):
			return
		var state = peers[sender_id]
		# Preserve server-authoritative fields that the client state sync doesn't send
		var saved_name: String = state.player_name
		state.from_dict(state_dict)
		state.peer_id = sender_id
		state.player_name = saved_name
		# Track last known system for reconnect persistence
		_player_last_system[sender_id] = state.system_id
		# ServerAuthority handles broadcasting to other peers (system-filtered).
		# Do NOT relay here — it would duplicate bandwidth and cause cross-system ghosts.


## Server -> Client: Another player's state update.
@rpc("authority", "unreliable_ordered")
func _rpc_receive_remote_state(pid: int, state_dict: Dictionary) -> void:
	var state =NetworkState.new()
	state.from_dict(state_dict)
	state.peer_id = pid

	if peers.has(pid):
		# Preserve player_name from registration (state sync doesn't include it)
		state.player_name = peers[pid].player_name
		peers[pid] = state

	player_state_received.emit(pid, state)


## Public API: send a chat message to the server. Called by NetworkChatRelay.
func send_chat_message(channel: int, text: String) -> void:
	if is_server() or not is_connected_to_server():
		return
	print("[Chat] send_chat_message: ch=%d text='%s' peer=%d" % [channel, text, local_peer_id])
	_rpc_chat_message.rpc_id(1, channel, text)


## Public API: send a whisper to the server.
func send_whisper(target_name: String, text: String) -> void:
	if is_server() or not is_connected_to_server():
		return
	_rpc_whisper.rpc_id(1, target_name, text)


## Client -> Server: Chat message (scoped by channel).
@rpc("any_peer", "reliable")
func _rpc_chat_message(channel: int, text: String) -> void:
	print("[Chat] _rpc_chat_message received: ch=%d text='%s' is_server=%s" % [channel, text, is_server()])
	if text.strip_edges().is_empty():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var sender_name ="Unknown"
	if peers.has(sender_id):
		sender_name = peers[sender_id].player_name
	print("[Chat] sender_id=%d sender_name='%s' peers_count=%d" % [sender_id, sender_name, peers.size()])

	if is_server():
		_store_chat_message(channel, sender_name, text)
		# Channel-scoped routing — never relay back to sender (they already showed it locally)
		match channel:
			1:  # SYSTEM → only peers in same system
				var sender_sys: int = peers[sender_id].system_id if peers.has(sender_id) else -1
				var sys_peers = get_peers_in_system(sender_sys)
				print("[Chat] SYSTEM relay: sender_sys=%d peers_in_sys=%s" % [sender_sys, str(sys_peers)])
				for pid in sys_peers:
					if pid == sender_id:
						continue
					_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)
				return
			_:  # GLOBAL, TRADE, CORP, etc. → broadcast to all except sender
				print("[Chat] GLOBAL relay: all peers=%s" % [str(peers.keys())])
				for pid in peers:
					if pid == sender_id:
						continue
					print("[Chat] Relaying to peer %d" % pid)
					_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)


## Server -> All/Some clients: Chat message broadcast.
@rpc("authority", "reliable")
func _rpc_receive_chat(sender_name: String, channel: int, text: String) -> void:
	chat_message_received.emit(sender_name, channel, text)


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
	var sender_id =multiplayer.get_remote_sender_id()
	var sender_name ="Unknown"
	if peers.has(sender_id):
		sender_name = peers[sender_id].player_name

	# Find target peer by name
	var target_pid: int = _find_peer_by_name(target_name)
	if target_pid == -1:
		_rpc_receive_whisper.rpc_id(sender_id, "SYSTÈME", "Joueur '%s' introuvable." % target_name)
		return

	_rpc_receive_whisper.rpc_id(target_pid, sender_name, text)


## Server -> Client: Whisper received.
@rpc("authority", "reliable")
func _rpc_receive_whisper(sender_name: String, text: String) -> void:
	whisper_received.emit(sender_name, text)


## Store a chat message: buffer in RAM first (always), then persist to backend (fire-and-forget).
func _store_chat_message(channel: int, sender_name: String, text: String, override_system_id: int = -1) -> void:
	if not is_server():
		return
	if channel == 4:  # PRIVATE — not stored
		return
	if sender_name.is_empty() or text.is_empty():
		return

	# Resolve system_id for SYSTEM channel
	var sys_id: int = 0
	if channel == 1:
		sys_id = override_system_id
		if sys_id < 0:
			var sender_id = multiplayer.get_remote_sender_id()
			if sender_id > 0 and peers.has(sender_id):
				sys_id = peers[sender_id].system_id
			elif peers.has(1):
				sys_id = peers[1].system_id
		if sys_id < 0:
			sys_id = 0

	# 1) Always buffer in RAM (primary source for history on connect)
	var now: Dictionary = Time.get_time_dict_from_system()
	var ts: String = "%02d:%02d" % [now["hour"], now["minute"]]
	var entry: Dictionary = {"s": sender_name, "t": text, "ts": ts, "ch": channel, "sys": sys_id}
	_chat_buffer.append(entry)
	if _chat_buffer.size() > CHAT_BUFFER_SIZE:
		_chat_buffer = _chat_buffer.slice(-CHAT_BUFFER_SIZE)

	# 2) Persist to backend DB (fire-and-forget, optional)
	if _chat_backend_client:
		_chat_backend_client.post_chat_message(channel, sys_id, sender_name, text)


## Send chat history to a newly connected client (from in-memory buffer — instant, no HTTP).
func _send_chat_history(peer_id: int, system_id: int) -> void:
	print("[Chat] _send_chat_history: peer=%d sys=%d buffer=%d" % [peer_id, system_id, _chat_buffer.size()])
	if _chat_buffer.is_empty():
		print("[Chat] _send_chat_history: buffer empty, skipping")
		return
	# Filter: include all non-SYSTEM messages + SYSTEM messages matching this system_id
	var history: Array = []
	for entry in _chat_buffer:
		var ch: int = entry.get("ch", 0)
		if ch == 1 and entry.get("sys", -1) != system_id:
			continue  # SYSTEM channel from a different system — skip
		history.append({"s": entry.get("s", ""), "t": entry.get("t", ""), "ts": entry.get("ts", ""), "ch": ch})
	print("[Chat] _send_chat_history: after filter=%d (from %d)" % [history.size(), _chat_buffer.size()])
	if history.is_empty():
		return
	# Limit to the last N messages to avoid huge RPC payloads
	if history.size() > CHAT_HISTORY_LIMIT:
		history = history.slice(-CHAT_HISTORY_LIMIT)
	print("[Chat] _send_chat_history: sending %d messages to peer %d" % [history.size(), peer_id])
	_rpc_chat_history.rpc_id(peer_id, history)


## Async helper: preload from backend DB, then send history to any clients that connected while loading.
## Called from start_dedicated_server() — runs in the background.
func _preload_and_emit_chat_history() -> void:
	print("[Chat] Starting async preload from backend...")
	await _preload_chat_from_backend()
	print("[Chat] Preload done (buffer=%d, preload_ok=%s)" % [_chat_buffer.size(), str(_chat_preload_done)])

	# Send history to any clients that connected while preloading
	for pid in peers:
		if pid == 1:
			continue  # peer 1 is the server itself
		var sys_id: int = peers[pid].system_id if peers.has(pid) else 0
		_send_chat_history(pid, sys_id)


## Preload chat history from backend DB into the in-memory buffer (server startup).
## If backend is unavailable, buffer stays empty — new messages accumulate normally.
func _preload_chat_from_backend() -> void:
	if not _chat_backend_client:
		print("[Chat] No backend client — skipping preload")
		return
	# Use system_id=-1 as sentinel: backend loads ALL SYSTEM messages without filtering
	var backend_msgs: Array = await _chat_backend_client.get_chat_history([0, 1, 2, 3], -1, CHAT_BUFFER_SIZE)
	if backend_msgs.is_empty():
		print("[Chat] Backend returned 0 messages (empty or unreachable)")
		return
	_chat_buffer.clear()
	for msg in backend_msgs:
		var ts: String = ""
		var created: String = msg.get("created_at", "")
		if created.length() >= 16:
			ts = created.substr(11, 5)  # Extract HH:MM from ISO timestamp
		var ch: int = msg.get("channel", 0)
		var sys: int = msg.get("system_id", 0)
		_chat_buffer.append({"s": msg.get("sender_name", ""), "t": msg.get("text", ""), "ts": ts, "ch": ch, "sys": sys})
	_chat_preload_done = true
	print("[Chat] Preloaded %d messages from backend DB" % _chat_buffer.size())


## Create the backend client for chat persistence (server-side only, idempotent).
func _ensure_chat_backend_client() -> void:
	if _chat_backend_client != null:
		return
	_chat_backend_client = ServerBackendClient.new()
	_chat_backend_client.name = "ChatBackendClient"
	add_child(_chat_backend_client)


## Create the backend client for heartbeat (server-side only, idempotent).
func _ensure_heartbeat_backend_client() -> void:
	if _heartbeat_backend_client != null:
		return
	_heartbeat_backend_client = ServerBackendClient.new()
	_heartbeat_backend_client.name = "HeartbeatBackendClient"
	add_child(_heartbeat_backend_client)


## Send heartbeat with all connected player UUIDs to the backend.
func _send_heartbeat() -> void:
	if _heartbeat_backend_client == null:
		return
	var uuids: Array = []
	for pid in _peer_to_uuid:
		if peers.has(pid):
			var uuid: String = _peer_to_uuid[pid]
			if uuid != "":
				uuids.append(uuid)
	if uuids.is_empty():
		return
	_heartbeat_backend_client.send_heartbeat(uuids)


## Find a peer ID by player name (server-side only).
func _find_peer_by_name(player_name: String) -> int:
	for pid in peers:
		var state = peers[pid]
		if state.player_name.to_lower() == player_name.to_lower():
			return pid
	return -1


## Server -> Single client: Server configuration (galaxy seed, spawn system, routing table).
@rpc("authority", "reliable")
func _rpc_server_config(config: Dictionary) -> void:
	galaxy_servers = config.get("galaxies", [])
	server_config_received.emit(config)


# =========================================================================
# NPC SYNC RPCs
# =========================================================================

## Server -> Client: Batch of NPC state updates (10Hz close, 2Hz far).
@rpc("authority", "unreliable_ordered")
func _rpc_npc_batch(batch: Array) -> void:
	npc_batch_received.emit(batch)


## Server -> Client: A new NPC has spawned (reliable, single event).
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

## Client -> Server: Player fired a weapon.
@rpc("any_peer", "reliable")
func _rpc_fire_event(weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
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
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.validate_hit_claim(sender_id, target_npc, weapon_name, damage_val, hit_dir)


## Any peer -> Server: Player claims a hit on another player.
@rpc("any_peer", "reliable")
func _rpc_player_hit_claim(target_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	# Validate basic bounds
	if damage_val < 0.0 or damage_val > 500.0:
		return
	if not peers.has(target_pid) or not peers.has(sender_id):
		return
	# Check same system
	var sender_state = peers[sender_id]
	var target_state = peers[target_pid]
	if sender_state.system_id != target_state.system_id:
		return
	# Reject hits on docked or dead players
	if target_state.is_docked or target_state.is_dead:
		return
	# Distance validation
	var sender_pos =Vector3(sender_state.pos_x, sender_state.pos_y, sender_state.pos_z)
	var target_pos =Vector3(target_state.pos_x, target_state.pos_y, target_state.pos_z)
	if sender_pos.distance_to(target_pos) > 3000.0:
		return
	# Weapon damage bounds — reject unknown weapons entirely
	var weapon =WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon == null:
		return
	if damage_val > weapon.damage_per_hit * 1.5:
		return
	# Track last attacker for PvP kill attribution
	_pvp_last_attacker[target_pid] = { "attacker_pid": sender_id, "weapon": weapon_name, "time": Time.get_unix_time_from_system() }
	# Relay damage to target player
	_rpc_receive_player_damage.rpc_id(target_pid, sender_id, weapon_name, damage_val, hit_dir)
	# Broadcast hit effect to observers (exclude attacker + target — they handle it locally)
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var target_label ="player_%d" % target_pid
		var peers_in_sys =get_peers_in_system(sender_state.system_id)
		for pid in peers_in_sys:
			if pid == sender_id or pid == target_pid:
				continue
			_rpc_hit_effect.rpc_id(pid, target_label, hit_dir, false)


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

signal npc_fire_received(npc_id: String, weapon_name: String, fire_pos: Array, fire_dir: Array)

## Server -> Client: An NPC fired a weapon (visual only).
@rpc("authority", "unreliable_ordered")
func _rpc_npc_fire(npc_id_str: String, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	npc_fire_received.emit(npc_id_str, weapon_name, fire_pos, fire_dir)


# =========================================================================
# PLAYER DEATH / RESPAWN RPCs (reliable)
# =========================================================================

## Client -> Server: I just died.
@rpc("any_peer", "reliable")
func _rpc_player_died(death_pos: Array) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	# Relay to all peers in the same system
	var state = peers.get(sender_id)
	if state == null:
		return
	state.is_dead = true
	for pid in get_peers_in_system(state.system_id):
		if pid == sender_id:
			continue
		_rpc_receive_player_died.rpc_id(pid, sender_id, death_pos)

	# Report PvP kill to Discord if a player attacker was recorded recently (< 15s)
	_report_pvp_kill(sender_id, state)

func _report_pvp_kill(victim_pid: int, victim_state) -> void:
	if not _pvp_last_attacker.has(victim_pid):
		return
	var info: Dictionary = _pvp_last_attacker[victim_pid]
	_pvp_last_attacker.erase(victim_pid)
	# Only count if the last hit was within 15 seconds
	var elapsed: float = Time.get_unix_time_from_system() - info["time"]
	if elapsed > 15.0:
		return
	var attacker_pid: int = info["attacker_pid"]
	var weapon_name: String = info["weapon"]

	var reporter = GameManager.get_node_or_null("EventReporter")
	if reporter == null:
		return

	var killer_name: String = "Pilote"
	if peers.has(attacker_pid):
		killer_name = peers[attacker_pid].player_name
	var victim_name: String = "Pilote"
	if victim_state:
		victim_name = victim_state.player_name

	var weapon_display: String = weapon_name
	if weapon_name != "":
		var w = WeaponRegistry.get_weapon(StringName(weapon_name))
		if w:
			weapon_display = String(w.weapon_name) if w.weapon_name != &"" else weapon_name

	var system_name: String = "Unknown"
	if GameManager._galaxy:
		system_name = GameManager._galaxy.get_system_name(victim_state.system_id)

	print("[PvP] Kill report: %s -> %s (%s) in %s" % [killer_name, victim_name, weapon_display, system_name])
	reporter.report_kill(killer_name, victim_name, weapon_display, system_name, victim_state.system_id)


## Server -> Client: A player has died (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_died(pid: int, death_pos: Array) -> void:
	player_died_received.emit(pid, death_pos)

## Client -> Server: I just respawned.
@rpc("any_peer", "reliable")
func _rpc_player_respawned(system_id: int) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var state = peers.get(sender_id)
	if state:
		state.is_dead = false
		state.system_id = system_id
	# Relay to all peers in the target system
	for pid in get_peers_in_system(system_id):
		if pid == sender_id:
			continue
		_rpc_receive_player_respawned.rpc_id(pid, sender_id, system_id)

## Server -> Client: A player has respawned (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_respawned(pid: int, system_id: int) -> void:
	player_respawned_received.emit(pid, system_id)


# =========================================================================
# SHIP CHANGE RPCs (reliable)
# =========================================================================

## Client -> Server: I changed my ship.
@rpc("any_peer", "reliable")
func _rpc_player_ship_changed(new_ship_id_str: String) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var new_sid =StringName(new_ship_id_str)
	var state = peers.get(sender_id)
	if state:
		state.ship_id = new_sid
		var sdata: ShipData = ShipRegistry.get_ship_data(new_sid)
		state.ship_class = sdata.ship_class if sdata else &"Fighter"
	# Relay to all connected peers
	for pid in peers:
		if pid == sender_id:
			continue
		_rpc_receive_player_ship_changed.rpc_id(pid, sender_id, new_ship_id_str)

## Server -> Client: A player changed their ship (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_ship_changed(pid: int, new_ship_id_str: String) -> void:
	var new_sid =StringName(new_ship_id_str)
	if peers.has(pid):
		peers[pid].ship_id = new_sid
		var sdata: ShipData = ShipRegistry.get_ship_data(new_sid)
		peers[pid].ship_class = sdata.ship_class if sdata else &"Fighter"
	player_ship_changed_received.emit(pid, new_sid)


# =========================================================================
# FLEET DEPLOYMENT RPCs
# =========================================================================

## Client -> Server: Request to deploy a fleet ship.
## ship_data_json contains the client's ship loadout for server-side NPC spawning.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_deploy(fleet_index: int, cmd_str: String, params_json: String, ship_data_json: String = "") -> void:
	if not is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var npc_auth = GameManager.get_node_or_null("NpcAuthority") as Node
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
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		npc_auth.handle_fleet_retrieve_request(sender_id, fleet_index)


## Client -> Server: Request to change fleet ship command.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_command(fleet_index: int, cmd_str: String, params_json: String) -> void:
	if not is_server():
		return
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
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
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
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
	var sender_id =multiplayer.get_remote_sender_id()
	var npc_auth =GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var sender_state = peers.get(sender_id)
		if sender_state:
			npc_auth.broadcast_asteroid_depleted(asteroid_id_str, sender_state.system_id, sender_id)


## Server -> Client: An asteroid was depleted by another player.
@rpc("authority", "reliable")
func _rpc_receive_asteroid_depleted(asteroid_id_str: String) -> void:
	asteroid_depleted_received.emit(asteroid_id_str)


## Client -> Server: batch of mining damage claims (0.5s interval).
## claims: [{ "aid": asteroid_id, "dmg": damage, "hm": health_max }]
@rpc("any_peer", "unreliable_ordered")
func _rpc_mining_damage_claim(claims: Array) -> void:
	if not is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth:
		npc_auth.handle_mining_damage_claims(sender_id, claims)


## Server -> Client: batch of asteroid health ratios (2Hz).
## batch: [{ "aid": asteroid_id, "hp": health_ratio 0.0-1.0 }]
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
	var sender_id =multiplayer.get_remote_sender_id()
	# Basic validation: sender must exist and damage must be in bounds
	if not peers.has(sender_id):
		return
	if damage < 0.0 or damage > 500.0:
		return
	# Reject unknown weapons
	var weapon_check = WeaponRegistry.get_weapon(StringName(weapon))
	if weapon_check == null:
		return
	structure_hit_claimed.emit(sender_id, target_id, weapon, damage, hit_dir)


## Server -> Client: Batch sync of structure health ratios.
@rpc("authority", "unreliable_ordered")
func _rpc_structure_batch(batch: Array) -> void:
	var struct_auth =GameManager.get_node_or_null("StructureAuthority") as Node
	if struct_auth:
		struct_auth.apply_batch(batch)


## Server -> Client: A structure was destroyed.
@rpc("authority", "reliable")
func _rpc_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array) -> void:
	var struct_auth =GameManager.get_node_or_null("StructureAuthority") as Node
	if struct_auth:
		struct_auth.apply_structure_destroyed(struct_id, killer_pid, pos, loot)
	structure_destroyed_received.emit(struct_id, killer_pid, pos, loot)
