class_name NetworkManagerSystem
extends Node

# =============================================================================
# Network Manager (Autoload) — MMORPG Architecture
#
# Two modes:
#   DEV (localhost):  host_and_play() → listen-server on your PC.
#                     Your friend joins your IP.
#   PROD (Railway):   connect_to_server(railway_ip) → dedicated headless server.
#
# In both cases the server is authoritative (validates, relays).
# The host in listen-server is peer_id=1 and plays normally.
# =============================================================================

signal peer_connected(peer_id: int, player_name: String)
signal peer_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal player_state_received(peer_id: int, state: NetworkState)
signal chat_message_received(sender_name: String, channel: int, text: String)
signal player_list_updated

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED }

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var local_player_name: String = "Pilote"
var local_peer_id: int = -1

## True when this instance is acting as the server (listen-server host OR dedicated).
var is_host: bool = false

## True only for headless dedicated server (no local player).
var is_dedicated_server: bool = false

# peer_id -> NetworkState (all remote players)
var peers: Dictionary = {}

# Server config
var _server_ip: String = "127.0.0.1"
var _server_port: int = Constants.NET_DEFAULT_PORT
var _peer: ENetMultiplayerPeer = null
var _reconnect_timer: float = 0.0
var _reconnect_attempts: int = 0
const MAX_RECONNECT_ATTEMPTS: int = 5
const RECONNECT_DELAY: float = 3.0


func _ready() -> void:
	is_dedicated_server = _check_dedicated_server()

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


func _check_dedicated_server() -> bool:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--headless":
			return true
	return DisplayServer.get_name() == "headless"


# =========================================================================
# PUBLIC API
# =========================================================================

## Host & Play (listen-server): start a server on your PC and play as peer_id=1.
## Your friend joins your LAN/public IP. This is the DEV/localhost mode.
func host_and_play(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	_server_port = port
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, Constants.NET_MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to host on port %d: %s" % [port, error_string(err)])
		connection_failed.emit("Impossible d'héberger: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTED
	local_peer_id = 1
	is_host = true
	is_dedicated_server = false

	# Register ourselves as a player on the server
	var state := NetworkState.new()
	state.peer_id = 1
	state.player_name = local_player_name
	state.ship_class = &"Fighter"
	peers[1] = state

	print("NetworkManager: Hosting on port %d as '%s' — share your IP for friends to join!" % [port, local_player_name])
	connection_succeeded.emit()
	player_list_updated.emit()
	return OK


## Start a pure dedicated server (headless, no local player).
## Used for production Railway deployment.
func start_dedicated_server(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	_server_port = port
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, Constants.NET_MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to start dedicated server on port %d: %s" % [port, error_string(err)])
		connection_failed.emit("Failed to start server: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTED
	local_peer_id = 1
	is_host = true
	is_dedicated_server = true
	print("NetworkManager: Dedicated server started on port %d (max %d)" % [port, Constants.NET_MAX_PLAYERS])
	connection_succeeded.emit()
	return OK


## Connect to a remote server as a client (join a host or a Railway server).
func connect_to_server(ip: String, port: int = Constants.NET_DEFAULT_PORT) -> Error:
	if connection_state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected or connecting")
		return ERR_ALREADY_IN_USE

	_server_ip = ip
	_server_port = port
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		push_error("NetworkManager: Failed to connect to %s:%d: %s" % [ip, port, error_string(err)])
		connection_failed.emit("Connexion échouée: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTING
	is_host = false
	_reconnect_attempts = 0
	print("NetworkManager: Connecting to %s:%d..." % [ip, port])
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
	is_host = false
	peers.clear()
	player_list_updated.emit()
	print("NetworkManager: Disconnected")


## Returns true if this instance is running the server logic (host or dedicated).
func is_server() -> bool:
	return is_host


func is_connected_to_server() -> bool:
	return connection_state == ConnectionState.CONNECTED


## Get all peer IDs in a given star system (interest management).
func get_peers_in_system(system_id: int) -> Array[int]:
	var result: Array[int] = []
	for pid in peers:
		var state: NetworkState = peers[pid]
		if state.system_id == system_id:
			result.append(pid)
	return result


## Get the machine's local LAN IP (for sharing with friends).
func get_local_ip() -> String:
	var addrs := IP.get_local_addresses()
	for addr in addrs:
		# Filter out loopback and IPv6, prefer 192.168.x.x or 10.x.x.x
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	# Fallback
	for addr in addrs:
		if addr != "127.0.0.1" and ":" not in addr:
			return addr
	return "127.0.0.1"


## Check if a server is already running on localhost (same machine).
## Tries to bind the same port on all interfaces — if it fails, the server is using it.
func is_local_server_running(port: int = Constants.NET_DEFAULT_PORT) -> bool:
	var test := UDPServer.new()
	var err := test.listen(port)
	if err != OK:
		return true  # Port in use → local server running
	test.stop()
	return false


# =========================================================================
# MULTIPLAYER CALLBACKS
# =========================================================================

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected: %d" % id)
	if is_server():
		# Send full peer list to the new peer
		var peer_data: Array = []
		for pid in peers:
			peer_data.append(peers[pid].to_dict())
		_rpc_full_peer_list.rpc_id(id, peer_data)


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % id)
	if peers.has(id):
		peers.erase(id)

	if is_server():
		_rpc_player_left.rpc(id)

	peer_disconnected.emit(id)
	player_list_updated.emit()


func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	local_peer_id = multiplayer.get_unique_id()
	_reconnect_attempts = 0
	print("NetworkManager: Connected! Peer ID = %d" % local_peer_id)

	# Register with the server
	_rpc_register_player.rpc_id(1, local_player_name, "Fighter")
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	print("NetworkManager: Connection failed")
	if _reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
		_reconnect_attempts += 1
		_reconnect_timer = RECONNECT_DELAY
		connection_failed.emit("Connexion échouée. Tentative %d/%d..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	else:
		connection_failed.emit("Connexion impossible après %d tentatives." % MAX_RECONNECT_ATTEMPTS)


func _on_server_disconnected() -> void:
	connection_state = ConnectionState.DISCONNECTED
	local_peer_id = -1
	is_host = false
	peers.clear()
	player_list_updated.emit()
	print("NetworkManager: Server disconnected")
	_reconnect_attempts = 1
	_reconnect_timer = RECONNECT_DELAY
	connection_failed.emit("Serveur déconnecté. Reconnexion...")


func _attempt_reconnect() -> void:
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		connection_failed.emit("Reconnexion échouée.")
		_reconnect_attempts = 0
		return
	print("NetworkManager: Reconnect attempt %d/%d" % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	connect_to_server(_server_ip, _server_port)


# =========================================================================
# RPCs
# =========================================================================

## Client -> Server: Register as a new player.
@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, ship_class: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	print("NetworkManager: Player '%s' registered (peer %d, ship %s)" % [player_name, sender_id, ship_class])

	var state := NetworkState.new()
	state.peer_id = sender_id
	state.player_name = player_name
	state.ship_class = StringName(ship_class)
	peers[sender_id] = state

	# Notify ALL clients (including new one) about this player
	_rpc_player_registered.rpc(sender_id, player_name, ship_class)

	# Also notify locally on the host (for GameManager to spawn puppet)
	if not is_dedicated_server:
		peer_connected.emit(sender_id, player_name)

	player_list_updated.emit()


## Server -> All clients: A new player has joined.
@rpc("authority", "reliable")
func _rpc_player_registered(pid: int, pname: String, ship_class: String) -> void:
	if peers.has(pid):
		return
	var state := NetworkState.new()
	state.peer_id = pid
	state.player_name = pname
	state.ship_class = StringName(ship_class)
	peers[pid] = state

	print("NetworkManager: Player '%s' (peer %d) registered" % [pname, pid])
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
		var state := NetworkState.new()
		state.from_dict(d)
		if state.peer_id != local_peer_id:
			peers[state.peer_id] = state
			peer_connected.emit(state.peer_id, state.player_name)
	player_list_updated.emit()


## Client -> Server: Position/state update (20Hz).
@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_state(state_dict: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if is_server():
		if not peers.has(sender_id):
			return
		var state: NetworkState = peers[sender_id]
		state.from_dict(state_dict)
		state.peer_id = sender_id

		# Relay to all other peers (including host if host != sender)
		for pid in peers:
			if pid == sender_id:
				continue
			if pid == 1 and not is_dedicated_server:
				# Host is local — emit signal directly instead of RPC to self
				player_state_received.emit(sender_id, state)
			else:
				_rpc_receive_remote_state.rpc_id(pid, sender_id, state_dict)


## Server -> Client: Another player's state update.
@rpc("authority", "unreliable_ordered")
func _rpc_receive_remote_state(pid: int, state_dict: Dictionary) -> void:
	var state := NetworkState.new()
	state.from_dict(state_dict)
	state.peer_id = pid

	if peers.has(pid):
		peers[pid] = state

	player_state_received.emit(pid, state)


## Client/Host -> Server: Chat message.
@rpc("any_peer", "reliable")
func _rpc_chat_message(channel: int, text: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_name := "Unknown"
	if peers.has(sender_id):
		sender_name = peers[sender_id].player_name

	if is_server():
		# Relay to all clients
		_rpc_receive_chat.rpc(sender_name, channel, text)
		# Also deliver locally on host
		if not is_dedicated_server:
			chat_message_received.emit(sender_name, channel, text)


## Server -> All clients: Chat message broadcast.
@rpc("authority", "reliable")
func _rpc_receive_chat(sender_name: String, channel: int, text: String) -> void:
	chat_message_received.emit(sender_name, channel, text)
