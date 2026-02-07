class_name NetworkChatRelay
extends Node

# =============================================================================
# Network Chat Relay - Bridges ChatPanel <-> NetworkManager for multiplayer.
# Listens to ChatPanel.message_sent and sends over network.
# Listens to NetworkManager.chat_message_received and displays locally.
# =============================================================================

var _chat_panel: ChatPanel = null


func _ready() -> void:
	# Find ChatPanel in the scene tree (it's under UI CanvasLayer)
	await get_tree().process_frame
	_find_chat_panel()

	# Listen for network chat messages
	NetworkManager.chat_message_received.connect(_on_network_chat_received)


func _find_chat_panel() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	_chat_panel = main.get_node_or_null("UI/ChatPanel") as ChatPanel
	if _chat_panel:
		_chat_panel.message_sent.connect(_on_local_message_sent)


## Local player typed a message → send to server (or handle locally if host).
func _on_local_message_sent(channel_name: String, text: String) -> void:
	if not NetworkManager.is_connected_to_server():
		return
	var channel: int = _channel_name_to_int(channel_name)
	if NetworkManager.is_host:
		# Host: relay directly to all clients
		NetworkManager._rpc_receive_chat.rpc(NetworkManager.local_player_name, channel, text)
	else:
		# Client: send to server
		NetworkManager._rpc_chat_message.rpc_id(1, channel, text)


## Server relayed a chat message → display in ChatPanel.
func _on_network_chat_received(sender_name: String, channel: int, text: String) -> void:
	if _chat_panel == null:
		return
	# Don't duplicate our own messages (already shown locally)
	if sender_name == NetworkManager.local_player_name:
		return
	var color := Color(0.3, 0.85, 1.0)  # Default player color
	_chat_panel.add_message(channel, sender_name, text, color)


func _channel_name_to_int(channel_name: String) -> int:
	match channel_name:
		"GÉNÉRAL": return ChatPanel.Channel.GLOBAL
		"SYSTÈME": return ChatPanel.Channel.SYSTEM
		"CLAN": return ChatPanel.Channel.CLAN
		"COMMERCE": return ChatPanel.Channel.TRADE
		"MP": return ChatPanel.Channel.PRIVATE
	return ChatPanel.Channel.GLOBAL
