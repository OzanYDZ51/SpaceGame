class_name EventReporter
extends Node

# =============================================================================
# Event Reporter
# Sends notable game events to the backend API for Discord integration.
# Active on the dedicated game server (headless).
# Checks server status lazily on each send — no timing issues with init order.
# Uses X-Server-Key auth (server-to-server), not player JWT.
# =============================================================================


# --- Kill Events ---

func report_kill(killer_name: String, victim_name: String, weapon: String, system_name: String, system_id: int) -> void:
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
	_send_event({
		"type": "discovery",
		"actor_name": player_name,
		"target_name": what,
		"system": system_name,
		"system_id": system_id,
	})


# --- Clan Events ---

func report_clan_event(event_type: String, clan_name: String, details: String) -> void:
	_send_event({
		"type": event_type,
		"actor_name": clan_name,
		"details": details,
	})


# --- Internal ---

func _send_event(data: Dictionary) -> void:
	# Only send events from the server (host or dedicated)
	if not NetworkManager or not NetworkManager.is_server():
		return
	var server_key := _get_server_key()
	if server_key == "":
		return
	var url: String = Constants.BACKEND_URL_PROD if Constants.GAME_VERSION != "dev" else Constants.BACKEND_URL_DEV
	url += "/api/v1/server/event"

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Server-Key: " + server_key,
	])

	var json_str := JSON.stringify(data)
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, headers, HTTPClient.METHOD_POST, json_str)
	# Fire and forget — clean up after timeout
	http.timeout = 10.0
	http.request_completed.connect(func(_result, _code, _headers, _body): http.queue_free())


func _get_server_key() -> String:
	# Check environment variable first (Railway deployment)
	var env_key: String = OS.get_environment("SERVER_KEY")
	if env_key != "":
		return env_key
	# Then check CLI arg (local dev: --server-key <key>)
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--server-key" and i + 1 < args.size():
			return args[i + 1]
	return "dev-server-key"
