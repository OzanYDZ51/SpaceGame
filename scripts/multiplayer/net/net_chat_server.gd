class_name NetChatServer
extends RefCounted

# =============================================================================
# NetChatServer — Chat buffer, history, channel routing, backend persistence
# Server-side only (client calls are short-circuit guarded by NM).
# =============================================================================

var _nm: NetworkManagerSystem

# In-memory ring buffer — primary source for history on connect
const CHAT_BUFFER_SIZE: int = 200
const CHAT_HISTORY_LIMIT: int = 50
var _chat_buffer: Array = []  # [{s, t, ts, ch, sys, ctag, rl}]

# Backend persistence (lazy-init, server-only)
var _chat_backend_client: ServerBackendClient = null
var _heartbeat_backend_client: ServerBackendClient = null
var _chat_preload_done: bool = false

# Heartbeat timer
const HEARTBEAT_INTERVAL: float = 60.0
var _heartbeat_timer: float = 0.0


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Backend client setup
# -------------------------------------------------------------------------

## Create chat backend client (idempotent, server-side only).
func ensure_chat_backend_client() -> void:
	if _chat_backend_client != null:
		return
	_chat_backend_client = ServerBackendClient.new()
	_chat_backend_client.name = "ChatBackendClient"
	_nm.add_child(_chat_backend_client)


## Create heartbeat backend client (idempotent, server-side only).
func ensure_heartbeat_backend_client() -> void:
	if _heartbeat_backend_client != null:
		return
	_heartbeat_backend_client = ServerBackendClient.new()
	_heartbeat_backend_client.name = "HeartbeatBackendClient"
	_nm.add_child(_heartbeat_backend_client)
	_heartbeat_timer = HEARTBEAT_INTERVAL


## Get the heartbeat backend client (for NM to check null).
func get_heartbeat_client() -> ServerBackendClient:
	return _heartbeat_backend_client


# -------------------------------------------------------------------------
# Per-frame tick (heartbeat)
# -------------------------------------------------------------------------

func tick(delta: float) -> void:
	if _heartbeat_backend_client == null:
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = HEARTBEAT_INTERVAL
		_send_heartbeat()


# -------------------------------------------------------------------------
# Message storage
# -------------------------------------------------------------------------

## Store a message in the ring buffer and optionally persist to backend.
func store_message(channel: int, sender_name: String, text: String, override_system_id: int = -1, corp_tag: String = "", sender_role: String = "player") -> void:
	if channel == 4:  # PRIVATE — not stored
		return
	if sender_name.is_empty() or text.is_empty():
		return

	# Resolve system_id for SYSTEM channel
	var sys_id: int = 0
	if channel == 1:
		sys_id = override_system_id
		if sys_id < 0:
			var sender_id: int = _nm.multiplayer.get_remote_sender_id()
			if sender_id > 0 and _nm.peers.has(sender_id):
				sys_id = _nm.peers[sender_id].system_id
			elif _nm.peers.has(1):
				sys_id = _nm.peers[1].system_id
		if sys_id < 0:
			sys_id = 0

	var now: Dictionary = Time.get_time_dict_from_system()
	var ts: String = "%02d:%02d" % [now["hour"], now["minute"]]
	var entry: Dictionary = {"s": sender_name, "t": text, "ts": ts, "ch": channel, "sys": sys_id, "ctag": corp_tag, "rl": sender_role}
	_chat_buffer.append(entry)
	if _chat_buffer.size() > CHAT_BUFFER_SIZE:
		_chat_buffer = _chat_buffer.slice(-CHAT_BUFFER_SIZE)

	if _chat_backend_client:
		_chat_backend_client.post_chat_message(channel, sys_id, sender_name, text)


# -------------------------------------------------------------------------
# History delivery
# -------------------------------------------------------------------------

## Send chat history to a newly connected peer (from in-memory buffer — instant).
func send_history_to_peer(peer_id: int, system_id: int) -> void:
	print("[Chat] _send_chat_history: peer=%d sys=%d buffer=%d" % [peer_id, system_id, _chat_buffer.size()])
	if _chat_buffer.is_empty():
		print("[Chat] _send_chat_history: buffer empty, skipping")
		return
	var history: Array = []
	for entry in _chat_buffer:
		var ch: int = entry.get("ch", 0)
		if ch == 1 and entry.get("sys", -1) != system_id:
			continue
		history.append({"s": entry.get("s", ""), "t": entry.get("t", ""), "ts": entry.get("ts", ""), "ch": ch, "ctag": entry.get("ctag", ""), "rl": entry.get("rl", "player")})
	print("[Chat] _send_chat_history: after filter=%d (from %d)" % [history.size(), _chat_buffer.size()])
	if history.is_empty():
		return
	if history.size() > CHAT_HISTORY_LIMIT:
		history = history.slice(-CHAT_HISTORY_LIMIT)
	print("[Chat] _send_chat_history: sending %d messages to peer %d" % [history.size(), peer_id])
	_nm._rpc_chat_history.rpc_id(peer_id, history)


## Async: preload from backend DB at server startup, then deliver to waiting clients.
func preload_and_emit_chat_history() -> void:
	print("[Chat] Starting async preload from backend...")
	await _preload_chat_from_backend()
	print("[Chat] Preload done (buffer=%d, preload_ok=%s)" % [_chat_buffer.size(), str(_chat_preload_done)])
	for pid in _nm.peers:
		if pid == 1:
			continue
		var sys_id: int = _nm.peers[pid].system_id if _nm.peers.has(pid) else 0
		send_history_to_peer(pid, sys_id)


# -------------------------------------------------------------------------
# Channel routing
# -------------------------------------------------------------------------

## Route a chat message from sender_id to the appropriate channel recipients.
## Called from NM's _rpc_chat_message after capturing remote_sender_id.
func route_chat(sender_id: int, channel: int, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var sender_name: String = "Unknown"
	var sender_ctag: String = ""
	var sender_role: String = "player"
	if _nm.peers.has(sender_id):
		sender_name = _nm.peers[sender_id].player_name
		sender_ctag = _nm.peers[sender_id].corporation_tag
		sender_role = _nm.peers[sender_id].role
	print("[Chat] sender_id=%d sender_name='%s' peers_count=%d" % [sender_id, sender_name, _nm.peers.size()])

	store_message(channel, sender_name, text, -1, sender_ctag, sender_role)

	match channel:
		1:  # SYSTEM → peers in same system
			var sender_sys: int = _nm.peers[sender_id].system_id if _nm.peers.has(sender_id) else -1
			var sys_peers: Array[int] = _nm.get_peers_in_system(sender_sys)
			print("[Chat] SYSTEM relay: sender_sys=%d peers_in_sys=%s" % [sender_sys, str(sys_peers)])
			for pid in sys_peers:
				if pid == sender_id:
					continue
				_nm._rpc_receive_chat.rpc_id(pid, sender_name, channel, text, sender_ctag, sender_role)
		5:  # GROUP → peers in same group
			var gid: int = _nm._group_mgr._player_group.get(sender_id, 0)
			if gid > 0 and _nm._group_mgr._groups.has(gid):
				var members: Array = _nm._group_mgr._groups[gid]["members"]
				for pid in members:
					if pid == sender_id:
						continue
					_nm._rpc_receive_chat.rpc_id(pid, sender_name, channel, text, sender_ctag, sender_role)
		2:  # CORP → peers with same corporation_tag
			var sender_tag: String = _nm.peers[sender_id].corporation_tag if _nm.peers.has(sender_id) else ""
			if sender_tag == "":
				return
			for pid in _nm.peers:
				if pid == sender_id:
					continue
				if _nm.peers[pid].corporation_tag == sender_tag:
					_nm._rpc_receive_chat.rpc_id(pid, sender_name, channel, text, sender_ctag, sender_role)
		_:  # GLOBAL, TRADE, etc. → all except sender
			print("[Chat] GLOBAL relay: all peers=%s" % [str(_nm.peers.keys())])
			for pid in _nm.peers:
				if pid == sender_id:
					continue
				print("[Chat] Relaying to peer %d" % pid)
				_nm._rpc_receive_chat.rpc_id(pid, sender_name, channel, text, sender_ctag, sender_role)


## Handle a whisper from sender_id to a named target.
func handle_whisper(sender_id: int, target_name: String, text: String) -> void:
	var sender_name: String = "Unknown"
	if _nm.peers.has(sender_id):
		sender_name = _nm.peers[sender_id].player_name
	var target_pid: int = _nm._peer_registry.find_peer_by_name(target_name)
	if target_pid == -1:
		_nm._rpc_receive_whisper.rpc_id(sender_id, "SYSTÈME", "Joueur '%s' introuvable." % target_name)
		return
	_nm._rpc_receive_whisper.rpc_id(target_pid, sender_name, text)


# -------------------------------------------------------------------------
# Private helpers
# -------------------------------------------------------------------------

func _preload_chat_from_backend() -> void:
	if not _chat_backend_client:
		print("[Chat] No backend client — skipping preload")
		return
	var backend_msgs: Array = await _chat_backend_client.get_chat_history([0, 1, 2, 3], -1, CHAT_BUFFER_SIZE)
	if backend_msgs.is_empty():
		print("[Chat] Backend returned 0 messages (empty or unreachable)")
		return
	_chat_buffer.clear()
	for msg in backend_msgs:
		var ts: String = ""
		var created: String = msg.get("created_at", "")
		if created.length() >= 16:
			ts = created.substr(11, 5)
		var ch: int = msg.get("channel", 0)
		var sys: int = msg.get("system_id", 0)
		_chat_buffer.append({"s": msg.get("sender_name", ""), "t": msg.get("text", ""), "ts": ts, "ch": ch, "sys": sys})
	_chat_preload_done = true
	print("[Chat] Preloaded %d messages from backend DB" % _chat_buffer.size())


func _send_heartbeat() -> void:
	if _heartbeat_backend_client == null:
		return
	var uuids: Array = []
	var peer_to_uuid: Dictionary = _nm._peer_registry.get_peer_to_uuid()
	for pid in peer_to_uuid:
		if _nm.peers.has(pid):
			var uuid: String = peer_to_uuid[pid]
			if uuid != "":
				uuids.append(uuid)
	if uuids.is_empty():
		return
	_heartbeat_backend_client.send_heartbeat(uuids)
