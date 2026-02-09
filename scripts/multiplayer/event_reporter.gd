class_name EventReporter
extends Node

# =============================================================================
# Event Reporter
# Sends notable game events to the backend API for Discord integration.
# Only active on the game server (headless) — clients don't send events directly.
# Uses ApiClient to POST to /api/v1/server/event.
# =============================================================================

var _enabled: bool = false


func _ready() -> void:
	# Only enable on the server (headless mode)
	_enabled = NetworkManager.is_server() if NetworkManager else false
	if not _enabled:
		set_process(false)


func enable_for_server() -> void:
	_enabled = true


# --- Kill Events ---

func report_kill(killer_name: String, victim_name: String, weapon: String, system_name: String, system_id: int) -> void:
	if not _enabled:
		return
	_send_event({
		"type": "kill",
		"killer": killer_name,
		"victim": victim_name,
		"weapon": weapon,
		"system": system_name,
		"system_id": system_id,
	})


# --- Discovery Events ---

func report_discovery(player_name: String, what: String, system_name: String, system_id: int) -> void:
	if not _enabled:
		return
	_send_event({
		"type": "discovery",
		"actor_name": player_name,
		"target_name": what,
		"system": system_name,
		"system_id": system_id,
	})


# --- Clan Events ---

func report_clan_event(event_type: String, clan_name: String, details: String) -> void:
	if not _enabled:
		return
	_send_event({
		"type": event_type,
		"actor_name": clan_name,
		"details": details,
	})


# --- Internal ---

func _send_event(data: Dictionary) -> void:
	if not AuthManager or not AuthManager.is_authenticated:
		return
	# Use ApiClient to POST to server event endpoint
	# ApiClient uses the server key, not JWT, for server-to-server calls
	var url: String = Constants.BACKEND_URL_PROD if Constants.GAME_VERSION != "dev" else Constants.BACKEND_URL_DEV
	url += "/api/v1/server/event"

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Server-Key: " + _get_server_key(),
	])

	var json_str := JSON.stringify(data)
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, headers, HTTPClient.METHOD_POST, json_str)
	# Fire and forget — clean up after timeout
	http.timeout = 10.0
	http.request_completed.connect(func(_result, _code, _headers, _body): http.queue_free())


func _get_server_key() -> String:
	# Server key is passed as env var or CLI arg on the headless server
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--server-key" and i + 1 < args.size():
			return args[i + 1]
	return "dev-server-key"
