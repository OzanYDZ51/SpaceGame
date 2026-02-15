class_name ServerBackendClient
extends Node

# =============================================================================
# Server Backend Client — HTTP client for the Godot game server (headless)
# to communicate with the Go backend. Authenticated via SERVER_KEY header.
# Used for fleet persistence (sync positions, report deaths, load deployed).
# =============================================================================

const REQUEST_TIMEOUT: float = 15.0


func _get_base_url() -> String:
	if Constants.BACKEND_URL_PROD != "":
		return Constants.BACKEND_URL_PROD
	return Constants.BACKEND_URL_DEV


func _get_server_key() -> String:
	var env_key: String = OS.get_environment("SERVER_KEY")
	if env_key != "":
		return env_key
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--server-key" and i + 1 < args.size():
			return args[i + 1]
	return "dev-server-key"


func _make_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-Server-Key: " + _get_server_key(),
	])


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
	if response_code != 200:
		push_error("ServerBackendClient: GET deployed returned %d" % response_code)
		return []

	var body: PackedByteArray = result[3]
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed.get("ships", [])
	return []


## PUT /api/v1/server/fleet/sync → batch update positions/health for deployed ships.
func sync_fleet_positions(updates: Array) -> bool:
	if updates.is_empty():
		return true

	var url: String = _get_base_url() + "/api/v1/server/fleet/sync"
	var json_str := JSON.stringify({"updates": updates})
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var err := http.request(url, _make_headers(), HTTPClient.METHOD_PUT, json_str)
	if err != OK:
		http.queue_free()
		push_error("ServerBackendClient: PUT sync failed: %s" % error_string(err))
		return false

	var result: Array = await http.request_completed
	http.queue_free()
	return result[1] == 200


## POST /api/v1/server/fleet/death → report a fleet ship as destroyed.
func report_fleet_death(player_uuid: String, fleet_index: int) -> bool:
	var url: String = _get_base_url() + "/api/v1/server/fleet/death"
	var json_str := JSON.stringify({
		"player_id": player_uuid,
		"fleet_index": fleet_index,
	})
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var err := http.request(url, _make_headers(), HTTPClient.METHOD_POST, json_str)
	if err != OK:
		http.queue_free()
		push_error("ServerBackendClient: POST death failed: %s" % error_string(err))
		return false

	var result: Array = await http.request_completed
	http.queue_free()
	return result[1] == 200
