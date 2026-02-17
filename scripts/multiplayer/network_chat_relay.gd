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
		print("[ChatRelay] _find_chat_panel: current_scene is NULL")
		return
	var node = main.get_node_or_null("UI/ChatPanel")
	_chat_panel = node as ChatPanel
	if _chat_panel:
		if not _chat_panel.message_sent.is_connected(_on_local_message_sent):
			_chat_panel.message_sent.connect(_on_local_message_sent)
			print("[ChatRelay] Connected message_sent signal OK")
	else:
		print("[ChatRelay] ChatPanel NOT FOUND at UI/ChatPanel")


## Local player typed a message → send to server via NetworkManager public API.
func _on_local_message_sent(channel_name: String, text: String) -> void:
	# Handle whisper commands from ChatPanel
	if channel_name.begins_with("WHISPER:"):
		var target_name: String = channel_name.substr(8)
		NetworkManager.send_whisper(target_name, text)
		return

	var channel: int = _channel_name_to_int(channel_name)
	NetworkManager.send_chat_message(channel, text)


## Server relayed a chat message → display in ChatPanel.
func _on_network_chat_received(sender_name: String, channel: int, text: String, corp_tag: String = "") -> void:
	if _chat_panel == null:
		return
	# Don't duplicate our own messages (already shown locally)
	if sender_name == NetworkManager.local_player_name:
		return

	var color := Color(0.3, 0.85, 1.0)  # Default player color
	if channel == ChatPanel.Channel.SYSTEM:
		color = Color(1.0, 0.85, 0.3)
		sender_name = "SYSTÈME"
		corp_tag = ""
	_chat_panel.add_message(channel, sender_name, text, color, corp_tag)


## Received a whisper from another player.
func _on_whisper_received(sender_name: String, text: String) -> void:
	if _chat_panel == null:
		return
	_last_whisper_from = sender_name
	_chat_panel.show_private_tab(sender_name)
	_chat_panel.add_message(ChatPanel.Channel.PRIVATE, "← " + sender_name, text, Color(0.85, 0.5, 1.0))



## Server sent chat history on connect → load into ChatPanel.
func _on_chat_history_received(history: Array) -> void:
	if _chat_panel == null:
		_find_chat_panel()
	if _chat_panel == null:
		print("[ChatRelay] ChatPanel NOT FOUND — history dropped!")
		return
	_chat_panel.load_history(history)


func _channel_name_to_int(channel_name: String) -> int:
	match channel_name:
		"GÉNÉRAL": return ChatPanel.Channel.GLOBAL
		"SYSTÈME": return ChatPanel.Channel.SYSTEM
		"COMMERCE": return ChatPanel.Channel.TRADE
	# CORP tab name is dynamic (shows the tag), check the current name
	if _chat_panel and channel_name == _chat_panel.CHANNEL_NAMES[ChatPanel.Channel.CORP]:
		return ChatPanel.Channel.CORP
	# PM tab name is dynamic (shows the player name)
	if _chat_panel and channel_name == _chat_panel.CHANNEL_NAMES.get(ChatPanel.Channel.PRIVATE, "MP"):
		return ChatPanel.Channel.PRIVATE
	return ChatPanel.Channel.GLOBAL
