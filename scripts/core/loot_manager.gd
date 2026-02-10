class_name LootManager
extends Node

# =============================================================================
# Loot Manager — handles loot screen open/close and loot collection.
# Child Node of GameManager.
# =============================================================================

# Injected refs
var player_data: PlayerData = null
var screen_manager: UIScreenManager = null
var loot_screen: LootScreen = null
var toast_manager: UIToastManager = null
var get_game_state: Callable  # () -> GameState


func open_loot_screen(crate: CargoCrate) -> void:
	if loot_screen == null or screen_manager == null:
		return
	loot_screen.set_contents(crate.contents)
	if loot_screen.loot_collected.is_connected(_on_loot_collected):
		loot_screen.loot_collected.disconnect(_on_loot_collected)
	loot_screen.loot_collected.connect(_on_loot_collected.bind(crate), CONNECT_ONE_SHOT)
	screen_manager.open_screen("loot")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_loot_collected(selected_items: Array[Dictionary], crate: CargoCrate) -> void:
	var economy: PlayerEconomy = player_data.economy if player_data else null
	var cargo: PlayerCargo = player_data.cargo if player_data else null

	var cargo_items: Array[Dictionary] = []
	for item in selected_items:
		var item_type: String = item.get("type", "")
		var qty: int = item.get("quantity", 1)
		if item_type == "credits" and economy:
			economy.add_credits(qty)
		elif player_data:
			var res_id: StringName = _loot_type_to_resource(item_type)
			if res_id != &"" and PlayerEconomy.RESOURCE_DEFS.has(res_id):
				player_data.add_active_ship_resource(res_id, qty)
			else:
				cargo_items.append(item)
		else:
			cargo_items.append(item)
	if cargo and not cargo_items.is_empty():
		cargo.add_items(cargo_items)
	if crate and is_instance_valid(crate):
		crate._destroy()
	SaveManager.mark_dirty()
	if get_game_state.is_valid() and get_game_state.call() == GameManagerSystem.GameState.PLAYING:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


static func _loot_type_to_resource(loot_type: String) -> StringName:
	match loot_type:
		"water": return &"ice"
		"iron": return &"iron"
	return &""
