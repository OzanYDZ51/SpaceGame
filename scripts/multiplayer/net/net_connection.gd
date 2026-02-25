class_name NetConnection
extends RefCounted

# =============================================================================
# NetConnection — WebSocket lifecycle & reconnect logic
# Owns the WebSocketMultiplayerPeer and all reconnect state.
# Calls back into NetworkManagerSystem (_nm) for all state changes.
# =============================================================================

var _nm: NetworkManagerSystem  # back-reference to the NM node

var _server_url: String = ""
var _server_port: int = 0
var _reconnect_attempts: int = 0
var _reconnect_timer: float = 0.0
var _peer: WebSocketMultiplayerPeer = null

const MAX_RECONNECT_ATTEMPTS: int = 20
const RECONNECT_DELAY: float = 2.0


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

func get_server_url() -> String:
	return _server_url


func get_peer() -> WebSocketMultiplayerPeer:
	return _peer


## Start the dedicated server (headless, Railway).
func start_server(port: int) -> Error:
	# Railway sets PORT env var dynamically
	var env_port: String = OS.get_environment("PORT")
	if env_port != "":
		var parsed_port: int = env_port.to_int()
		if parsed_port > 0 and parsed_port <= 65535:
			port = parsed_port
		else:
			push_warning("NetConnection: Invalid PORT env '%s', using default %d" % [env_port, port])
	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	_peer.outbound_buffer_size = 1048576  # 1 MB
	_peer.inbound_buffer_size = 262144    # 256 KB
	var err: Error = _peer.create_server(port)
	if err != OK:
		push_error("NetConnection: Failed to start server on port %d: %s" % [port, error_string(err)])
		_nm.connection_failed.emit("Failed to start server: " + error_string(err))
		return err
	_nm.multiplayer.multiplayer_peer = _peer
	_nm.connection_state = NetworkManagerSystem.ConnectionState.CONNECTED
	_nm.local_peer_id = 1
	print("========================================")
	print("  DEDICATED SERVER LISTENING ON PORT %d" % port)
	print("========================================")
	_nm.connection_succeeded.emit()
	return OK


## Connect to the game server as a client.
## If is_reconnect is true, preserves the attempt counter for retry logic.
func connect_to_server(address: String, port: int, is_reconnect: bool = false) -> Error:
	if _nm.connection_state != NetworkManagerSystem.ConnectionState.DISCONNECTED:
		push_warning("NetConnection: Already connected or connecting")
		return ERR_ALREADY_IN_USE
	var url: String
	if address.begins_with("ws://") or address.begins_with("wss://"):
		url = address
	else:
		url = "ws://%s:%d" % [address, port]
	_server_url = url
	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	_peer.outbound_buffer_size = 262144
	_peer.inbound_buffer_size = 1048576
	var err: Error = _peer.create_client(url)
	if err != OK:
		push_error("NetConnection: Failed to connect to %s: %s" % [url, error_string(err)])
		_nm.connection_failed.emit("Connexion échouée: " + error_string(err))
		return err
	_nm.multiplayer.multiplayer_peer = _peer
	_nm.connection_state = NetworkManagerSystem.ConnectionState.CONNECTING
	if not is_reconnect:
		_reconnect_attempts = 0
	return OK


## Close and clean up the WebSocket peer.
func close() -> void:
	if _peer:
		_peer.close()
		_peer = null
	_nm.multiplayer.multiplayer_peer = null
	_reconnect_attempts = 0


## Per-frame tick: drives the reconnect timer countdown.
func tick(delta: float) -> void:
	if _nm.connection_state == NetworkManagerSystem.ConnectionState.DISCONNECTED and _reconnect_attempts > 0:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_attempt_reconnect()


## Called by NM when an initial connection fails. Increments attempt counter.
func on_connection_failed() -> void:
	if _reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
		_reconnect_attempts += 1
		_reconnect_timer = RECONNECT_DELAY
		# Only emit UI-visible message every 5 attempts to avoid spam
		if _reconnect_attempts <= 1 or _reconnect_attempts % 5 == 0:
			_nm.connection_failed.emit("Connexion au serveur... tentative %d/%d" % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
		print("[Net] Connection attempt %d/%d failed, retrying in %.0fs..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS, RECONNECT_DELAY])
	else:
		_nm.connection_failed.emit("Connexion impossible après %d tentatives." % MAX_RECONNECT_ATTEMPTS)


## Called by NM when the live server connection drops. Begins reconnect sequence.
func on_server_disconnected() -> void:
	# Reset counter for a fresh reconnect sequence
	_reconnect_attempts = 1
	_reconnect_timer = RECONNECT_DELAY


# -------------------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------------------

func _attempt_reconnect() -> void:
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		_nm.connection_failed.emit("Reconnexion échouée.")
		_reconnect_attempts = 0
		return
	var url: String = _server_url if _server_url != "" else Constants.NET_GAME_SERVER_URL
	_nm.connect_to_server(url, Constants.NET_DEFAULT_PORT, true)
