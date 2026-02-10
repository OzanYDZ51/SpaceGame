class_name NetworkManagerSystem
extends Node

# =============================================================================
# Network Manager (Autoload) — MMORPG Architecture
#
# Transport: WebSocket (runs over HTTP/TCP — deployable on Railway/PaaS).
#
# Two modes:
#   DEV (localhost):  host_and_play() → listen-server on your PC.
#                     Client connects via ws://127.0.0.1:7777
#   PROD (Railway):   connect_to_server(railway_url) → dedicated headless server.
#                     Client connects via wss://xxx.up.railway.app
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
signal whisper_received(sender_name: String, text: String)
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

# Combat sync signals
signal remote_fire_received(peer_id: int, weapon_name: String, fire_pos: Array, fire_dir: Array)
signal player_damage_received(attacker_pid: int, weapon_name: String, damage_val: float, hit_dir: Array)

# Mining sync signals
signal remote_mining_beam_received(peer_id: int, is_active: bool, source_pos: Array, target_pos: Array)
signal asteroid_depleted_received(asteroid_id: String)

# Structure (station) sync signals
signal structure_hit_claimed(sender_pid: int, target_id: String, weapon: String, damage: float, hit_dir: Array)
signal structure_destroyed_received(struct_id: String, killer_pid: int, pos: Array, loot: Array)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED }

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var local_player_name: String = "Pilote"
var local_ship_id: StringName = &"fighter_mk1"
var local_peer_id: int = -1

## True when this instance is acting as the server (listen-server host OR dedicated).
var is_host: bool = false

## True only for headless dedicated server (no local player).
var is_dedicated_server: bool = false

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

# Multi-galaxy: routing table (sent from server, used by client for wormhole handoff)
# Each entry: { "seed": int, "name": String, "url": String }
var galaxy_servers: Array[Dictionary] = []

# Server-side: track each player's last known system (in-memory persistence)
var _player_last_system: Dictionary = {}  # peer_id -> system_id


func _ready() -> void:
	is_dedicated_server = _check_dedicated_server()
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


func _check_dedicated_server() -> bool:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--headless":
			return true
	return DisplayServer.get_name() == "headless"


func _parse_galaxy_seed_arg() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--galaxy-seed" and i + 1 < args.size():
			var seed_val: int = args[i + 1].to_int()
			if seed_val != 0:
				Constants.galaxy_seed = seed_val


# =========================================================================
# PUBLIC API
# =========================================================================

## Host & Play (listen-server): start a server on your PC and play as peer_id=1.
## Your friend joins your LAN/public IP. This is the DEV/localhost mode.
func host_and_play(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()

	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
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
	state.ship_id = local_ship_id
	var sdata := ShipRegistry.get_ship_data(local_ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"
	peers[1] = state

	connection_succeeded.emit()
	player_list_updated.emit()
	return OK


## Start a pure dedicated server (headless, no local player).
## Used for production Railway deployment.
func start_dedicated_server(port: int = Constants.NET_DEFAULT_PORT) -> Error:
	# Railway sets PORT env var dynamically
	var env_port: String = OS.get_environment("PORT")
	if env_port != "":
		port = env_port.to_int()
	_server_port = port
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		push_error("NetworkManager: Failed to start dedicated server on port %d: %s" % [port, error_string(err)])
		connection_failed.emit("Failed to start server: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTED
	local_peer_id = 1
	is_host = true
	is_dedicated_server = true
	connection_succeeded.emit()
	return OK


## Connect to a remote server as a client (join a host or a Railway server).
## address can be:
##   - A full URL: "ws://127.0.0.1:7777" or "wss://imperion.up.railway.app"
##   - An IP/hostname: "127.0.0.1" (port appended as ws://ip:port)
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
	var err := _peer.create_client(url)
	if err != OK:
		push_error("NetworkManager: Failed to connect to %s: %s" % [url, error_string(err)])
		connection_failed.emit("Connexion échouée: " + error_string(err))
		return err

	multiplayer.multiplayer_peer = _peer
	connection_state = ConnectionState.CONNECTING
	is_host = false
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
	is_host = false
	peers.clear()
	player_list_updated.emit()


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
## Tries to bind the same port — if it fails, the server is using it.
func is_local_server_running(port: int = Constants.NET_DEFAULT_PORT) -> bool:
	var test := TCPServer.new()
	var err := test.listen(port)
	if err != OK:
		return true  # Port in use → local server running
	test.stop()
	return false


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
	var left_name := "Pilote #%d" % id
	if peers.has(id):
		left_name = peers[id].player_name
		peers.erase(id)
	# Keep _player_last_system[id] for reconnect persistence (don't erase)

	if is_server():
		_rpc_player_left.rpc(id)
		# Broadcast system chat: player left
		_rpc_receive_chat.rpc(left_name, 1, "%s a quitté." % left_name)
		if not is_dedicated_server:
			chat_message_received.emit(left_name, 1, "%s a quitté." % left_name)

	peer_disconnected.emit(id)
	player_list_updated.emit()


func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	local_peer_id = multiplayer.get_unique_id()
	_reconnect_attempts = 0
	# Register with the server
	_rpc_register_player.rpc_id(1, local_player_name, String(local_ship_id))
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
	is_host = false
	# Emit peer_disconnected for each peer so NetworkSyncManager can clean up puppets
	var peer_ids := peers.keys()
	peers.clear()
	for pid in peer_ids:
		peer_disconnected.emit(pid)
	player_list_updated.emit()
	_reconnect_attempts = 1
	_reconnect_timer = RECONNECT_DELAY
	connection_failed.emit("Serveur déconnecté. Reconnexion...")


func _attempt_reconnect() -> void:
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		connection_failed.emit("Reconnexion échouée.")
		_reconnect_attempts = 0
		return
	if _server_url != "":
		connect_to_server(_server_url)
	else:
		connect_to_server("127.0.0.1", _server_port)


# =========================================================================
# RPCs
# =========================================================================

## Client -> Server: Register as a new player.
@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String, ship_id_str: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var state := NetworkState.new()
	state.peer_id = sender_id
	state.player_name = player_name
	state.ship_id = StringName(ship_id_str)
	var sdata := ShipRegistry.get_ship_data(state.ship_id)
	state.ship_class = sdata.ship_class if sdata else &"Fighter"

	# Send server config to the new client (galaxy seed, spawn system, routing)
	# For new players, default to the host's current system (not -1)
	var default_sys: int = GameManager.current_system_id_safe() if GameManager else 0
	var spawn_sys: int = _player_last_system.get(sender_id, default_sys)
	# Set the client's system_id NOW so NPC batch filtering includes them immediately
	state.system_id = spawn_sys
	peers[sender_id] = state

	var config := {
		"galaxy_seed": Constants.galaxy_seed,
		"spawn_system_id": spawn_sys,
		"galaxies": galaxy_servers,
	}
	_rpc_server_config.rpc_id(sender_id, config)

	# Notify ALL clients (including new one) about this player
	_rpc_player_registered.rpc(sender_id, player_name, ship_id_str)

	# Broadcast system chat: player joined
	_rpc_receive_chat.rpc(player_name, 1, "%s a rejoint le secteur." % player_name)
	if not is_dedicated_server:
		chat_message_received.emit(player_name, 1, "%s a rejoint le secteur." % player_name)

	# Also notify locally on the host (for GameManager to spawn puppet)
	if not is_dedicated_server:
		peer_connected.emit(sender_id, player_name)

	player_list_updated.emit()


## Server -> All clients: A new player has joined.
@rpc("authority", "reliable")
func _rpc_player_registered(pid: int, pname: String, ship_id_str: String) -> void:
	if peers.has(pid):
		return
	var state := NetworkState.new()
	state.peer_id = pid
	state.player_name = pname
	state.ship_id = StringName(ship_id_str)
	var sdata := ShipRegistry.get_ship_data(state.ship_id)
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
		# Track last known system for reconnect persistence
		_player_last_system[sender_id] = state.system_id
		# ServerAuthority handles broadcasting to other peers (system-filtered).
		# Do NOT relay here — it would duplicate bandwidth and cause cross-system ghosts.


## Server -> Client: Another player's state update.
@rpc("authority", "unreliable_ordered")
func _rpc_receive_remote_state(pid: int, state_dict: Dictionary) -> void:
	var state := NetworkState.new()
	state.from_dict(state_dict)
	state.peer_id = pid

	if peers.has(pid):
		peers[pid] = state

	player_state_received.emit(pid, state)


## Client/Host -> Server: Chat message (scoped by channel).
@rpc("any_peer", "reliable")
func _rpc_chat_message(channel: int, text: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_name := "Unknown"
	if peers.has(sender_id):
		sender_name = peers[sender_id].player_name

	if is_server():
		# Channel-scoped routing — never relay back to sender (they already showed it locally)
		match channel:
			1:  # SYSTEM → only peers in same system
				var sender_sys: int = peers[sender_id].system_id if peers.has(sender_id) else -1
				for pid in get_peers_in_system(sender_sys):
					if pid == sender_id:
						continue
					if pid == 1 and not is_dedicated_server:
						chat_message_received.emit(sender_name, channel, text)
					else:
						_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)
				return
			_:  # GLOBAL, TRADE, CLAN, etc. → broadcast to all except sender
				for pid in peers:
					if pid == sender_id:
						continue
					if pid == 1 and not is_dedicated_server:
						chat_message_received.emit(sender_name, channel, text)
					else:
						_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)


## Server -> All/Some clients: Chat message broadcast.
@rpc("authority", "reliable")
func _rpc_receive_chat(sender_name: String, channel: int, text: String) -> void:
	chat_message_received.emit(sender_name, channel, text)


## Client -> Server: Whisper (private message) to a named player.
@rpc("any_peer", "reliable")
func _rpc_whisper(target_name: String, text: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_name := "Unknown"
	if peers.has(sender_id):
		sender_name = peers[sender_id].player_name

	# Find target peer by name
	var target_pid: int = _find_peer_by_name(target_name)
	if target_pid == -1:
		# Target not found — notify sender
		if sender_id == 1 and not is_dedicated_server:
			whisper_received.emit("SYSTÈME", "Joueur '%s' introuvable." % target_name)
		else:
			_rpc_receive_whisper.rpc_id(sender_id, "SYSTÈME", "Joueur '%s' introuvable." % target_name)
		return

	# Deliver to target
	if target_pid == 1 and not is_dedicated_server:
		whisper_received.emit(sender_name, text)
	else:
		_rpc_receive_whisper.rpc_id(target_pid, sender_name, text)


## Server -> Client: Whisper received.
@rpc("authority", "reliable")
func _rpc_receive_whisper(sender_name: String, text: String) -> void:
	whisper_received.emit(sender_name, text)


## Host helper: deliver a whisper when the host is the sender.
func _deliver_whisper_from_host(target_name: String, text: String) -> void:
	var target_pid: int = _find_peer_by_name(target_name)
	if target_pid == -1:
		whisper_received.emit("SYSTÈME", "Joueur '%s' introuvable." % target_name)
		return
	if target_pid == 1:
		# Whispering to self (host)
		whisper_received.emit(local_player_name, text)
	else:
		_rpc_receive_whisper.rpc_id(target_pid, local_player_name, text)


## Host sends a chat message using the same scoped routing as client messages.
func _relay_chat_from_host(channel: int, text: String) -> void:
	var sender_name: String = local_player_name
	match channel:
		1:  # SYSTEM → only peers in same system
			var host_sys: int = peers[1].system_id if peers.has(1) else -1
			for pid in get_peers_in_system(host_sys):
				if pid == 1:
					continue  # Host already showed message locally
				_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)
		_:  # GLOBAL, TRADE, CLAN → all clients (host already showed locally)
			for pid in peers:
				if pid == 1:
					continue
				_rpc_receive_chat.rpc_id(pid, sender_name, channel, text)


## Find a peer ID by player name (server-side only).
func _find_peer_by_name(player_name: String) -> int:
	for pid in peers:
		var state: NetworkState = peers[pid]
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
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
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
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
	if npc_auth:
		npc_auth.validate_hit_claim(sender_id, target_npc, weapon_name, damage_val, hit_dir)


## Any peer -> Server: Player claims a hit on another player.
@rpc("any_peer", "reliable")
func _rpc_player_hit_claim(target_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# Validate basic bounds
	if damage_val < 0.0 or damage_val > 500.0:
		return
	if not peers.has(target_pid) or not peers.has(sender_id):
		return
	# Check same system
	var sender_state: NetworkState = peers[sender_id]
	var target_state: NetworkState = peers[target_pid]
	if sender_state.system_id != target_state.system_id:
		return
	# Distance validation
	var sender_pos := Vector3(sender_state.pos_x, sender_state.pos_y, sender_state.pos_z)
	var target_pos := Vector3(target_state.pos_x, target_state.pos_y, target_state.pos_z)
	if sender_pos.distance_to(target_pos) > 3000.0:
		return
	# Weapon damage bounds
	var weapon := WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon and damage_val > weapon.damage_per_hit * 1.5:
		return
	# Relay damage to target player
	if target_pid == 1 and not is_dedicated_server:
		player_damage_received.emit(sender_id, weapon_name, damage_val, hit_dir)
	else:
		_rpc_receive_player_damage.rpc_id(target_pid, sender_id, weapon_name, damage_val, hit_dir)


## Server -> Target client: You've been hit by another player.
@rpc("authority", "reliable")
func _rpc_receive_player_damage(attacker_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	player_damage_received.emit(attacker_pid, weapon_name, damage_val, hit_dir)


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
	var sender_id := multiplayer.get_remote_sender_id()
	# Relay to all peers in the same system
	var state: NetworkState = peers.get(sender_id)
	if state == null:
		return
	state.is_dead = true
	for pid in get_peers_in_system(state.system_id):
		if pid == sender_id:
			continue
		if pid == 1 and not is_dedicated_server:
			player_died_received.emit(sender_id, death_pos)
		else:
			_rpc_receive_player_died.rpc_id(pid, sender_id, death_pos)

## Server -> Client: A player has died (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_died(pid: int, death_pos: Array) -> void:
	player_died_received.emit(pid, death_pos)

## Client -> Server: I just respawned.
@rpc("any_peer", "reliable")
func _rpc_player_respawned(system_id: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var state: NetworkState = peers.get(sender_id)
	if state:
		state.is_dead = false
		state.system_id = system_id
	# Relay to all peers in the target system
	for pid in get_peers_in_system(system_id):
		if pid == sender_id:
			continue
		if pid == 1 and not is_dedicated_server:
			player_respawned_received.emit(sender_id, system_id)
		else:
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
	var sender_id := multiplayer.get_remote_sender_id()
	var new_sid := StringName(new_ship_id_str)
	var state: NetworkState = peers.get(sender_id)
	if state:
		state.ship_id = new_sid
		var sdata := ShipRegistry.get_ship_data(new_sid)
		state.ship_class = sdata.ship_class if sdata else &"Fighter"
	# Relay to all connected peers
	for pid in peers:
		if pid == sender_id:
			continue
		if pid == 1 and not is_dedicated_server:
			player_ship_changed_received.emit(sender_id, new_sid)
		else:
			_rpc_receive_player_ship_changed.rpc_id(pid, sender_id, new_ship_id_str)

## Server -> Client: A player changed their ship (reliable notification).
@rpc("authority", "reliable")
func _rpc_receive_player_ship_changed(pid: int, new_ship_id_str: String) -> void:
	var new_sid := StringName(new_ship_id_str)
	if peers.has(pid):
		peers[pid].ship_id = new_sid
		var sdata := ShipRegistry.get_ship_data(new_sid)
		peers[pid].ship_class = sdata.ship_class if sdata else &"Fighter"
	player_ship_changed_received.emit(pid, new_sid)


# =========================================================================
# FLEET DEPLOYMENT RPCs
# =========================================================================

## Client -> Server: Request to deploy a fleet ship.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_deploy(fleet_index: int, cmd_str: String, params_json: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
	if npc_auth:
		npc_auth.handle_fleet_deploy_request(sender_id, fleet_index, StringName(cmd_str), JSON.parse_string(params_json) if params_json != "" else {})


## Client -> Server: Request to retrieve a fleet ship.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_retrieve(fleet_index: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
	if npc_auth:
		npc_auth.handle_fleet_retrieve_request(sender_id, fleet_index)


## Client -> Server: Request to change fleet ship command.
@rpc("any_peer", "reliable")
func _rpc_request_fleet_command(fleet_index: int, cmd_str: String, params_json: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
	if npc_auth:
		npc_auth.handle_fleet_command_request(sender_id, fleet_index, StringName(cmd_str), JSON.parse_string(params_json) if params_json != "" else {})


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


# =========================================================================
# MINING SYNC RPCs
# =========================================================================

## Client -> Server: Mining beam state (10Hz, visual only).
@rpc("any_peer", "unreliable_ordered")
func _rpc_mining_beam(is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
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
	var sender_id := multiplayer.get_remote_sender_id()
	var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
	if npc_auth:
		var sender_state: NetworkState = peers.get(sender_id)
		if sender_state:
			npc_auth.broadcast_asteroid_depleted(asteroid_id_str, sender_state.system_id, sender_id)


## Server -> Client: An asteroid was depleted by another player.
@rpc("authority", "reliable")
func _rpc_receive_asteroid_depleted(asteroid_id_str: String) -> void:
	asteroid_depleted_received.emit(asteroid_id_str)


# =============================================================================
# STRUCTURE (STATION) SYNC
# =============================================================================

## Client -> Server: A projectile hit a station.
@rpc("any_peer", "reliable")
func _rpc_structure_hit_claim(target_id: String, weapon: String, damage: float, hit_dir: Array) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	structure_hit_claimed.emit(sender_id, target_id, weapon, damage, hit_dir)


## Server -> Client: Batch sync of structure health ratios.
@rpc("authority", "unreliable_ordered")
func _rpc_structure_batch(batch: Array) -> void:
	var struct_auth := GameManager.get_node_or_null("StructureAuthority") as StructureAuthority
	if struct_auth:
		struct_auth.apply_batch(batch)


## Server -> Client: A structure was destroyed.
@rpc("authority", "reliable")
func _rpc_structure_destroyed(struct_id: String, killer_pid: int, pos: Array, loot: Array) -> void:
	var struct_auth := GameManager.get_node_or_null("StructureAuthority") as StructureAuthority
	if struct_auth:
		struct_auth.apply_structure_destroyed(struct_id, killer_pid, pos, loot)
	structure_destroyed_received.emit(struct_id, killer_pid, pos, loot)
