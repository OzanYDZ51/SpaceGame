class_name AuthManagerSystem
extends Node

# =============================================================================
# Auth Manager — handles login/register/JWT/session
# Autoload: AuthManager
# =============================================================================

signal login_succeeded(player_data: Dictionary)
signal login_failed(error: String)
signal register_succeeded(player_data: Dictionary)
signal register_failed(error: String)
signal session_expired()
signal logged_out()

var player_id: String = ""
var username: String = ""
var is_authenticated: bool = false

var _access_token: String = ""
var _refresh_token: String = ""
var _refresh_timer: Timer = null
var _token_file: String = "user://auth.cfg"

const ACCESS_TOKEN_LIFETIME: float = 14.0 * 60.0  # Refresh 1 min before expiry (14 min)


func _ready() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.name = "RefreshTimer"
	_refresh_timer.one_shot = true
	_refresh_timer.timeout.connect(_on_refresh_timer)
	add_child(_refresh_timer)

	# Try to restore session from saved tokens
	_try_restore_session()


# --- Public API ---

func register(p_username: String, email: String, password: String) -> void:
	var result := await ApiClient.post_async("/api/v1/auth/register", {
		"username": p_username,
		"email": email,
		"password": password,
	}, false)

	if result.get("_status_code", 0) == 201 and result.has("access_token"):
		_handle_auth_success(result)
		register_succeeded.emit(result.get("player", {}))
	else:
		var error: String = result.get("error", "registration failed")
		register_failed.emit(error)


func login(p_username: String, password: String) -> void:
	var result := await ApiClient.post_async("/api/v1/auth/login", {
		"username": p_username,
		"password": password,
	}, false)

	var status: int = result.get("_status_code", 0)
	if (status == 200 or status == 201) and result.has("access_token"):
		_handle_auth_success(result)
		login_succeeded.emit(result.get("player", {}))
	else:
		var error: String = result.get("error", "login failed")
		login_failed.emit(error)


func set_token_from_launcher(access_token: String) -> void:
	## Called by GameManager when the launcher passes a JWT via CLI.
	## The launcher handles login/register; we just receive the token.
	_access_token = access_token
	ApiClient.set_token(_access_token)
	_parse_jwt_claims(_access_token)
	is_authenticated = true
	_start_refresh_timer()
	# Try to get refresh token from saved file (launcher may have saved it)
	var config := ConfigFile.new()
	if config.load(_token_file) == OK:
		_refresh_token = config.get_value("auth", "refresh_token", "")
	print("AuthManager: Token set from launcher — player=%s (id=%s)" % [username, player_id])


func logout() -> void:
	if _refresh_token != "":
		await ApiClient.post_async("/api/v1/auth/logout", {"refresh_token": _refresh_token})

	_clear_session()
	logged_out.emit()


func get_access_token() -> String:
	return _access_token


# --- Internal ---

func _handle_auth_success(result: Dictionary) -> void:
	_access_token = result.get("access_token", "")
	_refresh_token = result.get("refresh_token", "")

	var player: Dictionary = result.get("player", {})
	player_id = str(player.get("id", ""))
	username = str(player.get("username", ""))
	is_authenticated = true

	ApiClient.set_token(_access_token)
	_save_tokens()
	_start_refresh_timer()

	print("AuthManager: Logged in as '%s' (id=%s)" % [username, player_id])


func _start_refresh_timer() -> void:
	_refresh_timer.stop()
	_refresh_timer.wait_time = ACCESS_TOKEN_LIFETIME
	_refresh_timer.start()


func _on_refresh_timer() -> void:
	if _refresh_token == "":
		return

	var result := await ApiClient.post_async("/api/v1/auth/refresh", {
		"refresh_token": _refresh_token,
	}, false)

	if result.has("access_token"):
		_access_token = result.get("access_token", "")
		_refresh_token = result.get("refresh_token", _refresh_token)
		ApiClient.set_token(_access_token)
		_save_tokens()
		_start_refresh_timer()
		print("AuthManager: Token refreshed successfully")
	else:
		print("AuthManager: Token refresh failed — session expired")
		_clear_session()
		session_expired.emit()


func _try_restore_session() -> void:
	var config := ConfigFile.new()
	if config.load(_token_file) != OK:
		return

	_refresh_token = config.get_value("auth", "refresh_token", "")
	if _refresh_token == "":
		return

	print("AuthManager: Restoring session from saved tokens...")

	# Try to refresh the token
	var result := await ApiClient.post_async("/api/v1/auth/refresh", {
		"refresh_token": _refresh_token,
	}, false)

	if result.has("access_token"):
		_access_token = result.get("access_token", "")
		_refresh_token = result.get("refresh_token", _refresh_token)

		# We need to fetch the player data since refresh doesn't return it
		ApiClient.set_token(_access_token)
		var state := await ApiClient.get_async("/api/v1/player/state")
		if state.get("_status_code", 0) == 200:
			# We need the player profile too for player_id and username
			# Parse the JWT to get sub and username
			_parse_jwt_claims(_access_token)
			is_authenticated = true
			_save_tokens()
			_start_refresh_timer()
			login_succeeded.emit({"id": player_id, "username": username})
			print("AuthManager: Session restored for '%s'" % username)
			return

	print("AuthManager: Session restore failed, tokens cleared")
	_clear_session()


func _parse_jwt_claims(token: String) -> void:
	# JWT format: header.payload.signature
	var parts := token.split(".")
	if parts.size() < 2:
		return
	# Decode base64url payload
	var payload := parts[1]
	# Pad to multiple of 4
	while payload.length() % 4 != 0:
		payload += "="
	# Replace base64url chars
	payload = payload.replace("-", "+").replace("_", "/")
	var decoded := Marshalls.base64_to_utf8(payload)
	var parsed := JSON.new()
	if parsed.parse(decoded) == OK and parsed.data is Dictionary:
		player_id = str(parsed.data.get("sub", ""))
		username = str(parsed.data.get("username", ""))


func _save_tokens() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "refresh_token", _refresh_token)
	config.save(_token_file)


func _clear_session() -> void:
	_access_token = ""
	_refresh_token = ""
	player_id = ""
	username = ""
	is_authenticated = false
	_refresh_timer.stop()
	ApiClient.clear_token()

	# Delete saved tokens
	if FileAccess.file_exists(_token_file):
		DirAccess.remove_absolute(_token_file)
