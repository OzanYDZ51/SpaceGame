class_name ApiClientSystem
extends Node

# =============================================================================
# API Client — HTTP request pool for backend communication
# Autoload: ApiClient
# =============================================================================

const POOL_SIZE: int = 4
const REQUEST_TIMEOUT: float = 10.0

var access_token: String = ""
var _http_pool: Array[HTTPRequest] = []
var _request_queue: Array[Dictionary] = []
var _pending: int = 0

var base_url: String:
	get:
		if Constants.BACKEND_URL_PROD != "":
			return Constants.BACKEND_URL_PROD
		return Constants.BACKEND_URL_DEV


func _ready() -> void:
	for i in POOL_SIZE:
		var http := HTTPRequest.new()
		http.name = "HTTPPool_%d" % i
		http.timeout = REQUEST_TIMEOUT
		add_child(http)
		_http_pool.append(http)


func set_token(token: String) -> void:
	access_token = token


func clear_token() -> void:
	access_token = ""


# --- Public API methods (all return Signal via await) ---

func get_async(path: String, use_auth: bool = true) -> Dictionary:
	return await _request("GET", path, {}, use_auth)


func post_async(path: String, body: Dictionary = {}, use_auth: bool = true) -> Dictionary:
	return await _request("POST", path, body, use_auth)


func put_async(path: String, body: Dictionary = {}, use_auth: bool = true) -> Dictionary:
	return await _request("PUT", path, body, use_auth)


func delete_async(path: String, use_auth: bool = true) -> Dictionary:
	return await _request("DELETE", path, {}, use_auth)


# --- Internal ---

func _request(method: String, path: String, body: Dictionary, use_auth: bool) -> Dictionary:
	var http := _get_available_http()
	if http == null:
		# Queue the request
		var promise := {}
		_request_queue.append({
			"method": method,
			"path": path,
			"body": body,
			"use_auth": use_auth,
			"promise": promise,
		})
		# Wait until it's processed
		while not promise.has("result"):
			await get_tree().process_frame
		return promise["result"]

	return await _execute_request(http, method, path, body, use_auth)


func _execute_request(http: HTTPRequest, method: String, path: String, body: Dictionary, use_auth: bool) -> Dictionary:
	_pending += 1

	var url: String = base_url + path
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if use_auth and access_token != "":
		headers.append("Authorization: Bearer " + access_token)

	var http_method: int
	match method:
		"GET": http_method = HTTPClient.METHOD_GET
		"POST": http_method = HTTPClient.METHOD_POST
		"PUT": http_method = HTTPClient.METHOD_PUT
		"DELETE": http_method = HTTPClient.METHOD_DELETE
		_: http_method = HTTPClient.METHOD_GET

	var body_str: String = ""
	if method in ["POST", "PUT"] and not body.is_empty():
		body_str = JSON.stringify(body)

	var err := http.request(url, headers, http_method, body_str)
	if err != OK:
		_pending -= 1
		_process_queue()
		return {"error": "request_failed", "status_code": 0}

	var response: Array = await http.request_completed
	_pending -= 1

	# response: [result, response_code, headers, body]
	var result_code: int = response[0]
	var status_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	_process_queue()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"error": "network_error", "status_code": 0}

	var parsed := JSON.new()
	var json_err := parsed.parse(response_body.get_string_from_utf8())
	if json_err != OK:
		return {"error": "invalid_json", "status_code": status_code}

	var data: Dictionary = {}
	if parsed.data is Dictionary:
		data = parsed.data
	data["_status_code"] = status_code
	return data


func _get_available_http() -> HTTPRequest:
	for http in _http_pool:
		if http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED or \
		   http.get_http_client_status() == HTTPClient.STATUS_CONNECTED:
			return http
	return null


func _process_queue() -> void:
	while not _request_queue.is_empty():
		var http := _get_available_http()
		if http == null:
			break
		var req: Dictionary = _request_queue.pop_front()
		var result := await _execute_request(http, req["method"], req["path"], req["body"], req["use_auth"])
		req["promise"]["result"] = result
