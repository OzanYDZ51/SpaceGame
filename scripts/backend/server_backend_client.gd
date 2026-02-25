class_name ServerBackendClient
extends Node

# =============================================================================
# Server Backend Client — HTTP client for the Godot game server (headless)
# to communicate with the Go backend. Authenticated via SERVER_KEY header.
# Used for fleet persistence (sync positions, report deaths, load deployed).
# =============================================================================

const REQUEST_TIMEOUT: float = 15.0
const MAX_RETRIES: int = 3
var _retry_delays := [2.0, 5.0, 10.0]


func _get_base_url() -> String:
	return Constants.BACKEND_URL


func _get_server_key() -> String:
	var env_key: String = OS.get_environment("SERVER_KEY")
	if env_key != "":
		return env_key
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--server-key" and i + 1 < args.size():
			return args[i + 1]
	return "dev-server-key"


func _make_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-Server-Key: " + _get_server_key(),
	])


## Internal: execute an HTTP request with automatic retries and response logging.
## Deaths use max_retries=3, position syncs use max_retries=1.
func _request_with_retry(method_name: String, url: String, http_method: int, json_str: String = "", max_retries: int = MAX_RETRIES) -> bool:
	for attempt in range(max_retries + 1):
		if attempt > 0:
			var delay: float = _retry_delays[mini(attempt - 1, _retry_delays.size() - 1)]
			await get_tree().create_timer(delay).timeout

		var http := HTTPRequest.new()
		http.timeout = REQUEST_TIMEOUT
		add_child(http)

		var err: Error
		if json_str != "":
			err = http.request(url, _make_headers(), http_method, json_str)
		else:
			err = http.request(url, _make_headers(), http_method)

		if err != OK:
			http.queue_free()
			push_error("ServerBackendClient: %s attempt %d/%d — request error: %s" % [method_name, attempt + 1, max_retries + 1, error_string(err)])
			continue

		var result: Array = await http.request_completed
		http.queue_free()

		var response_code: int = result[1]
		var body_str: String = result[3].get_string_from_utf8() if result[3].size() > 0 else ""

		if response_code == 200:
			if attempt > 0:
				print("ServerBackendClient: %s succeeded on retry %d" % [method_name, attempt])
			return true

		# Distinguish client error (4xx) from server error (5xx)
		if response_code >= 400 and response_code < 500:
			push_error("ServerBackendClient: %s — client error HTTP %d: %s (no retry)" % [method_name, response_code, body_str])
			return false  # Client errors won't succeed on retry

		push_error("ServerBackendClient: %s attempt %d/%d — HTTP %d: %s" % [method_name, attempt + 1, max_retries + 1, response_code, body_str])

	push_error("ServerBackendClient: %s FAILED after %d attempts" % [method_name, max_retries + 1])
	return false


## GET /api/v1/server/fleet/deployed → all deployed fleet ships across all players.
func get_deployed_fleet_ships() -> Array:
	var url: String = _get_base_url() + "/api/v1/server/fleet/deployed"
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var err := http.request(url, _make_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		push_error("ServerBackendClient: GET deployed failed: %s" % error_string(err))
		return []

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body_str: String = result[3].get_string_from_utf8() if result[3].size() > 0 else ""
	if response_code != 200:
		push_error("ServerBackendClient: GET deployed returned %d: %s" % [response_code, body_str])
		return []

	var parsed = JSON.parse_string(body_str)
	if parsed is Dictionary:
		return parsed.get("ships", [])
	return []


## PUT /api/v1/server/fleet/sync → batch update positions/health for deployed ships.
## Uses 1 retry (position syncs are periodic, next cycle will catch up).
func sync_fleet_positions(updates: Array) -> bool:
	if updates.is_empty():
		return true
	var url: String = _get_base_url() + "/api/v1/server/fleet/sync"
	var json_str := JSON.stringify({"updates": updates})
	return await _request_with_retry("PUT fleet/sync", url, HTTPClient.METHOD_PUT, json_str, 1)


## POST /api/v1/server/fleet/death → report a fleet ship as destroyed.
## Uses full retries (3) — deaths must never be lost.
func report_fleet_death(player_uuid: String, fleet_index: int) -> bool:
	var url: String = _get_base_url() + "/api/v1/server/fleet/death"
	var json_str := JSON.stringify({
		"player_id": player_uuid,
		"fleet_index": fleet_index,
	})
	return await _request_with_retry("POST fleet/death", url, HTTPClient.METHOD_POST, json_str, MAX_RETRIES)


# =============================================================================
# HEARTBEAT
# =============================================================================

## POST /api/v1/server/heartbeat → update last_seen_at for connected players.
## Fire-and-forget, 1 retry.
func send_heartbeat(player_uuids: Array) -> bool:
	if player_uuids.is_empty():
		return true
	var url: String = _get_base_url() + "/api/v1/server/heartbeat"
	var json_str := JSON.stringify({"player_ids": player_uuids})
	return await _request_with_retry("POST heartbeat", url, HTTPClient.METHOD_POST, json_str, 1)


# =============================================================================
# CHAT PERSISTENCE
# =============================================================================

## POST /api/v1/server/chat/messages → store a chat message (fire-and-forget, 1 retry).
func post_chat_message(channel: int, system_id: int, sender_name: String, text: String) -> bool:
	var url: String = _get_base_url() + "/api/v1/server/chat/messages"
	var json_str := JSON.stringify({
		"channel": channel,
		"system_id": system_id,
		"sender_name": sender_name,
		"text": text,
	})
	return await _request_with_retry("POST chat/messages", url, HTTPClient.METHOD_POST, json_str, 1)


## GET /api/v1/server/chat/history → retrieve recent messages for given channels.
## Returns Array of Dictionaries with keys: sender_name, text, channel, created_at.
func get_chat_history(channels: Array, system_id: int, limit: int = 50) -> Array:
	var ch_str: String = ",".join(channels.map(func(c): return str(c)))
	var url: String = _get_base_url() + "/api/v1/server/chat/history?channels=%s&system_id=%d&limit=%d" % [ch_str, system_id, limit]
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var err := http.request(url, _make_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		push_error("ServerBackendClient: GET chat/history failed: %s" % error_string(err))
		return []

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body_str: String = result[3].get_string_from_utf8() if result[3].size() > 0 else ""
	if response_code != 200:
		push_error("ServerBackendClient: GET chat/history returned %d: %s" % [response_code, body_str])
		return []

	var parsed = JSON.parse_string(body_str)
	if parsed is Dictionary:
		return parsed.get("messages", [])
	return []
