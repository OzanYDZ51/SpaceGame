class_name WSClientSystem
extends Node

# =============================================================================
# WebSocket Client — real-time events from backend
# Autoload: WSClient (optional, added manually if needed)
# =============================================================================

signal connected()
signal disconnected()
signal event_received(event_name: String, data: Dictionary)

var _socket: WebSocketPeer = null
var _connected: bool = false
var _heartbeat_timer: Timer = null
var _reconnect_timer: Timer = null
var _reconnect_attempts: int = 0

const HEARTBEAT_INTERVAL: float = 30.0
const RECONNECT_DELAY: float = 5.0
const MAX_RECONNECT_ATTEMPTS: int = 10


func _ready() -> void:
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.name = "HeartbeatTimer"
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)

	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "ReconnectTimer"
	_reconnect_timer.one_shot = true
	_reconnect_timer.wait_time = RECONNECT_DELAY
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)


func connect_to_backend() -> void:
	if not AuthManager.is_authenticated:
		return

	var ws_url: String = Constants.BACKEND_WS_URL

	ws_url += "?token=" + AuthManager.get_access_token()

	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(ws_url)
	if err != OK:
		print("WSClient: Failed to connect — error %d" % err)
		_schedule_reconnect()
		return

	_reconnect_attempts = 0


func disconnect_from_backend() -> void:
	if _socket:
		_socket.close()
	_connected = false
	_heartbeat_timer.stop()
	_socket = null


func subscribe_to_corporation(corporation_id: String) -> void:
	_send_event("subscribe", {"corporation_id": corporation_id})


func _process(_delta: float) -> void:
	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_heartbeat_timer.start()
				_reconnect_attempts = 0
				connected.emit()
				print("WSClient: Connected")

			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				_handle_message(packet.get_string_from_utf8())

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				_heartbeat_timer.stop()
				disconnected.emit()
				print("WSClient: Disconnected (code=%d)" % _socket.get_close_code())
			_socket = null
			_schedule_reconnect()


func _handle_message(text: String) -> void:
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not (parsed.data is Dictionary):
		return

	var event_type: String = parsed.data.get("type", "")
	var event_data: Dictionary = {}
	if parsed.data.has("data") and parsed.data["data"] is Dictionary:
		event_data = parsed.data["data"]

	if event_type == "pong":
		return  # Heartbeat response, ignore

	event_received.emit(event_type, event_data)


func _send_event(event_type: String, data: Dictionary = {}) -> void:
	if _socket == null or not _connected:
		return

	var payload := JSON.stringify({"type": event_type, "data": data})
	_socket.send_text(payload)


func _send_heartbeat() -> void:
	_send_event("ping")


func _schedule_reconnect() -> void:
	if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("WSClient: Max reconnect attempts reached")
		return
	if not AuthManager.is_authenticated:
		return
	_reconnect_timer.start()


func _attempt_reconnect() -> void:
	_reconnect_attempts += 1
	print("WSClient: Reconnect attempt %d/%d" % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	connect_to_backend()
