class_name MultiplayerMenuScreen
extends UIScreen

# =============================================================================
# Multiplayer Info Screen (P key)
#
# Info-only panel — connection is automatic on game launch.
# Shows: connection status, IP (if hosting), connected player list.
# No connect/disconnect forms needed.
# =============================================================================

var _player_list: UIScrollList = null
var _status_text: String = ""
var _status_color: Color = UITheme.ACCENT
var _local_ip: String = "..."

const CONTENT_TOP: float = 70.0
const PANEL_WIDTH: float = 480.0


func _ready() -> void:
	screen_title = "RÉSEAU"
	screen_mode = ScreenMode.FULLSCREEN
	super._ready()

	_local_ip = NetworkManager.get_local_ip()
	_build_ui()

	NetworkManager.connection_succeeded.connect(_on_connection_changed)
	NetworkManager.connection_failed.connect(func(_r): _on_connection_changed())
	NetworkManager.peer_connected.connect(func(_a, _b): _refresh_player_list())
	NetworkManager.peer_disconnected.connect(func(_a): _refresh_player_list())
	NetworkManager.player_list_updated.connect(_refresh_player_list)


func _build_ui() -> void:
	_player_list = UIScrollList.new()
	_player_list.name = "PlayerList"
	_player_list.row_height = 24.0
	_player_list.item_draw_callback = _draw_player_row
	add_child(_player_list)


func _on_opened() -> void:
	_local_ip = NetworkManager.get_local_ip()
	_update_status()
	_refresh_player_list()


func _process(_delta: float) -> void:
	if not visible:
		return
	_layout_ui()
	queue_redraw()


func _layout_ui() -> void:
	var cx: float = size.x * 0.5
	var left_x: float = cx - PANEL_WIDTH * 0.5

	# Player list starts below the header info area
	var list_y: float = CONTENT_TOP + 130
	_player_list.position = Vector2(left_x, list_y)
	_player_list.size = Vector2(PANEL_WIDTH, size.y - list_y - UITheme.MARGIN_SCREEN - 10)


func _draw() -> void:
	super._draw()
	var font: Font = UITheme.get_font()
	var cx: float = size.x * 0.5
	var left_x: float = cx - PANEL_WIDTH * 0.5
	var y: float = CONTENT_TOP + 10

	# --- Connection status ---
	_update_status()
	draw_string(font, Vector2(0, y), _status_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_BODY, _status_color)
	y += 20

	# --- Mode & IP info ---
	var mode_label ="PRODUCTION" if Constants.NET_GAME_SERVER_URL != "" else "DÉVELOPPEMENT"
	if NetworkManager.is_connected_to_server():
		var server_text ="CONNECTÉ À %s" % NetworkManager._server_url
		draw_string(font, Vector2(0, y), server_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_HEADER, UITheme.ACCENT)
		y += 18
		var info_text ="MODE : %s  |  Peer ID : %d" % [mode_label, NetworkManager.local_peer_id]
		draw_string(font, Vector2(0, y), info_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
	else:
		var target_url =Constants.NET_GAME_SERVER_URL if Constants.NET_GAME_SERVER_URL != "" else "ws://%s:%d" % [Constants.NET_PUBLIC_IP, Constants.NET_DEFAULT_PORT]
		draw_string(font, Vector2(0, y), "Connexion à %s..." % target_url, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_BODY, UITheme.WARNING)
		y += 16
		draw_string(font, Vector2(0, y), "MODE : %s" % mode_label, HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)

	# --- Player list header ---
	var list_header_y: float = _player_list.position.y - 20
	var count: int = _player_list.items.size()
	draw_string(font, Vector2(left_x, list_header_y), "JOUEURS EN LIGNE (%d)" % count, HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)


func _draw_player_row(ctrl: Control, _index: int, rect: Rect2, item: Variant) -> void:
	var font: Font = UITheme.get_font()
	var data: Dictionary = item as Dictionary
	var pname: String = data.get("name", "???")
	var pid: int = data.get("pid", -1)
	var sys_id: int = data.get("sys", -1)
	var is_self: bool = (pid == NetworkManager.local_peer_id)
	var is_hosting: bool = (pid == 1)

	var col =UITheme.ACCENT if is_self else UITheme.TEXT
	var suffix =""
	if is_self:
		suffix = " (toi)"
	elif is_hosting:
		suffix = " (hôte)"
	ctrl.draw_string(font, Vector2(rect.position.x + 8, rect.position.y + rect.size.y - 5), pname + suffix, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 120, UITheme.FONT_SIZE_LABEL, col)
	# Show system ID on the right
	if sys_id >= 0:
		var sys_text := "Sys %d" % sys_id
		var sys_col: Color = UITheme.ACCENT if is_self else UITheme.TEXT_DIM
		ctrl.draw_string(font, Vector2(rect.position.x + rect.size.x - 70, rect.position.y + rect.size.y - 5), sys_text, HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_SMALL, sys_col)


func _update_status() -> void:
	match NetworkManager.connection_state:
		NetworkManager.ConnectionState.DISCONNECTED:
			_status_text = "DÉCONNECTÉ"
			_status_color = UITheme.WARNING
		NetworkManager.ConnectionState.CONNECTING:
			_status_text = "CONNEXION EN COURS..."
			_status_color = UITheme.PRIMARY
		NetworkManager.ConnectionState.CONNECTED:
			var player_count: int = NetworkManager.peers.size() + 1  # peers + self
			_status_text = "EN LIGNE — %d JOUEUR(S)" % player_count
			_status_color = UITheme.ACCENT


func _refresh_player_list() -> void:
	if _player_list == null:
		return
	var items: Array = []

	if NetworkManager.is_connected_to_server():
		# Add self (get our system_id from system_transition)
		var local_sys: int = -1
		if GameManager._system_transition:
			local_sys = GameManager._system_transition.current_system_id
		items.append({"name": NetworkManager.local_player_name, "pid": NetworkManager.local_peer_id, "sys": local_sys})
		# Add all remote peers
		for pid in NetworkManager.peers:
			var state = NetworkManager.peers[pid]
			if state.peer_id != NetworkManager.local_peer_id:
				items.append({"name": state.player_name, "pid": state.peer_id, "sys": state.system_id})

	_player_list.items = items
	_player_list.queue_redraw()


func _on_connection_changed() -> void:
	_update_status()
	_refresh_player_list()
