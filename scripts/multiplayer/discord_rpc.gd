class_name DiscordRPC
extends Node

# =============================================================================
# Discord Rich Presence State Sender
# Connects to the launcher's TCP bridge (127.0.0.1:27150) and sends game state
# updates every 15 seconds. The launcher forwards these to Discord RPC.
# Fails silently if the launcher isn't running in tray mode.
# =============================================================================

const RPC_PORT: int = 27150
const RPC_HOST: String = "127.0.0.1"
const UPDATE_INTERVAL: float = 15.0

var _tcp: StreamPeerTCP = null
var _connected: bool = false
var _timer: float = 0.0
var _retry_timer: float = 0.0
var _current_state: String = "En vol"
var _current_system: String = "Espace"
var _party_size: int = 1
var _party_max: int = 128


func _ready() -> void:
	_try_connect()


func _process(delta: float) -> void:
	if not _connected:
		_retry_timer += delta
		if _retry_timer >= 30.0:
			_retry_timer = 0.0
			_try_connect()
		return

	# Poll TCP status
	_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_connected = false
		_tcp = null
		return

	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		_send_state()


func _try_connect() -> void:
	_tcp = StreamPeerTCP.new()
	var err := _tcp.connect_to_host(RPC_HOST, RPC_PORT)
	if err != OK:
		_tcp = null
		return

	# Give it a moment to connect
	await get_tree().create_timer(0.5).timeout

	if _tcp == null:
		return

	_tcp.poll()
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_connected = true
		_timer = UPDATE_INTERVAL  # Send immediately
	else:
		_tcp = null


func _send_state() -> void:
	if not _connected or _tcp == null:
		return

	var data := {
		"state": _current_state,
		"details": "Systeme " + _current_system,
		"large_image": "imperion_logo",
		"party_size": _party_size,
		"party_max": _party_max,
	}

	var json_str := JSON.stringify(data) + "\n"
	var err := _tcp.put_data(json_str.to_utf8_buffer())
	if err != OK:
		_connected = false
		_tcp = null


# --- Public API (called by GameManager) ---

func set_state(state: String) -> void:
	_current_state = state

func set_system(system_name: String) -> void:
	_current_system = system_name

func set_party_size(size: int) -> void:
	_party_size = size

func update_from_game_state(game_state: int) -> void:
	# GameState enum: LOADING=0, PLAYING=1, PAUSED=2, MENU=3, DEAD=4, DOCKED=5
	match game_state:
		0: set_state("Chargement")
		1: set_state("En vol")
		2: set_state("En pause")
		3: set_state("Menu")
		4: set_state("Mort")
		5: set_state("Docke")


func cleanup() -> void:
	if _tcp:
		_tcp.disconnect_from_host()
		_tcp = null
	_connected = false
