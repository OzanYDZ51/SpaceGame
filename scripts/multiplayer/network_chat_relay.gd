class_name NetworkChatRelay
extends Node

# =============================================================================
# Network Chat Relay - Bridges ChatPanel <-> NetworkManager for multiplayer.
# Listens to ChatPanel.message_sent and sends over network.
# Listens to NetworkManager signals and displays locally.
# =============================================================================

var _chat_panel: ChatPanel = null
var _last_whisper_from: String = ""


func _ready() -> void:
	# Find ChatPanel in the scene tree (it's under UI CanvasLayer)
	await get_tree().process_frame
	_find_chat_panel()

	# Listen for network chat messages
	NetworkManager.chat_message_received.connect(_on_network_chat_received)
	NetworkManager.whisper_received.connect(_on_whisper_received)
	NetworkManager.chat_history_received.connect(_on_chat_history_received)

	# Note: join/leave messages are broadcast by the server via SYSTEM channel chat RPCs.
	# No need to listen to peer_connected/peer_disconnected here.


func _find_chat_panel() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	_chat_panel = main.get_node_or_null("UI/ChatPanel") as ChatPanel
	if _chat_panel:
		_chat_panel.message_sent.connect(_on_local_message_sent)


## Local player typed a message → send to server.
func _on_local_message_sent(channel_name: String, text: String) -> void:
	if not NetworkManager.is_connected_to_server():
		return

	# Handle whisper commands from ChatPanel
	if channel_name.begins_with("WHISPER:"):
		var target_name: String = channel_name.substr(8)
		_send_whisper(target_name, text)
		return

	var channel: int = _channel_name_to_int(channel_name)
	NetworkManager._rpc_chat_message.rpc_id(1, channel, text)


## Server relayed a chat message → display in ChatPanel.
func _on_network_chat_received(sender_name: String, channel: int, text: String) -> void:
	if _chat_panel == null:
		return
	# Don't duplicate our own messages (already shown locally)
	if sender_name == NetworkManager.local_player_name:
		return

	var color := Color(0.3, 0.85, 1.0)  # Default player color
	if channel == ChatPanel.Channel.SYSTEM:
		color = Color(1.0, 0.85, 0.3)
		sender_name = "SYSTÈME"
	_chat_panel.add_message(channel, sender_name, text, color)


## Send a whisper (private message) to a specific player.
func _send_whisper(target_name: String, text: String) -> void:
	if not NetworkManager.is_connected_to_server():
		return
	NetworkManager._rpc_whisper.rpc_id(1, target_name, text)


## Received a whisper from another player.
func _on_whisper_received(sender_name: String, text: String) -> void:
	if _chat_panel == null:
		return
	_last_whisper_from = sender_name
	_chat_panel._private_target = sender_name
	_chat_panel.add_message(ChatPanel.Channel.PRIVATE, "← " + sender_name, text, Color(0.85, 0.5, 1.0))



## Server sent chat history on connect → load into ChatPanel.
func _on_chat_history_received(history: Array) -> void:
	if _chat_panel == null:
		_find_chat_panel()
	if _chat_panel == null:
		return
	_chat_panel.load_history(history)


func _channel_name_to_int(channel_name: String) -> int:
	match channel_name:
		"GÉNÉRAL": return ChatPanel.Channel.GLOBAL
		"SYSTÈME": return ChatPanel.Channel.SYSTEM
		"CLAN": return ChatPanel.Channel.CLAN
		"COMMERCE": return ChatPanel.Channel.TRADE
		"MP": return ChatPanel.Channel.PRIVATE
	return ChatPanel.Channel.GLOBAL
