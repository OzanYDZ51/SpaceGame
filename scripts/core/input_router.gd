class_name InputRouter
extends Node

# =============================================================================
# Input Router — handles input action setup and input event routing.
# Child Node of GameManager.
# =============================================================================

signal dock_requested
signal loot_pickup_requested(crate: CargoCrate)
signal gate_jump_requested
signal wormhole_jump_requested
signal respawn_requested
signal map_toggled(view: int)
signal screen_toggled(screen_name: String)
signal terminal_requested
signal undock_requested

# Injected refs
var screen_manager: UIScreenManager = null
var docking_system: DockingSystem = null
var loot_pickup: LootPickupSystem = null
var system_transition: SystemTransition = null
var get_game_state: Callable  # () -> GameState


func _ready() -> void:
	_setup_input_actions()


func _setup_input_actions() -> void:
	var actions := {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"strafe_left": KEY_A,
		"strafe_right": KEY_D,
		"strafe_up": KEY_SPACE,
		"strafe_down": KEY_CTRL,
		"roll_left": KEY_Q,
		"roll_right": KEY_E,
		"boost": KEY_SHIFT,
		"toggle_cruise": KEY_C,
		"toggle_camera": KEY_V,
		"toggle_flight_assist": KEY_Z,
		"toggle_mouse_capture": KEY_ESCAPE,
		"toggle_map": KEY_M,
		"toggle_clan": KEY_N,
		"toggle_galaxy_map": KEY_G,
		"target_cycle": KEY_TAB,
		"target_nearest": KEY_T,
		"target_clear": KEY_Y,
		"pip_weapons": KEY_UP,
		"pip_shields": KEY_LEFT,
		"pip_engines": KEY_RIGHT,
		"pip_reset": KEY_DOWN,
		"dock": KEY_F,
		"toggle_multiplayer": KEY_P,
		"gate_jump": KEY_J,
		"wormhole_jump": KEY_W,
		"toggle_weapon_1": KEY_1,
		"toggle_weapon_2": KEY_2,
		"toggle_weapon_3": KEY_3,
		"toggle_weapon_4": KEY_4,
	}

	var mouse_actions := {
		"fire_primary": MOUSE_BUTTON_LEFT,
		"fire_secondary": MOUSE_BUTTON_RIGHT,
	}
	for action_name in mouse_actions:
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		InputMap.add_action(action_name)
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = mouse_actions[action_name]
		InputMap.action_add_event(action_name, mouse_event)

	for action_name in actions:
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action_name]
		InputMap.action_add_event(action_name, event)


func _input(event: InputEvent) -> void:
	# Skip all game keybinds when a text field has focus
	if event is InputEventKey:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return

	var state: int = get_game_state.call() if get_game_state.is_valid() else 0

	# Respawn on R when dead
	if state == GameManagerSystem.GameState.DEAD:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
			respawn_requested.emit()
		return

	# Map keys (M/G) always work
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_M:
			map_toggled.emit(UnifiedMapScreen.ViewMode.SYSTEM)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_G:
			map_toggled.emit(UnifiedMapScreen.ViewMode.GALAXY)
			get_viewport().set_input_as_handled()
			return

	# Multiplayer screen (P)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_P:
		if screen_manager:
			var top := screen_manager.get_top_screen()
			if top == null or top == screen_manager._screens.get("multiplayer"):
				screen_toggled.emit("multiplayer")
				get_viewport().set_input_as_handled()
				return

	# Bug report screen (F12)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F12:
		if screen_manager:
			var top := screen_manager.get_top_screen()
			if top == null or top == screen_manager._screens.get("bug_report"):
				screen_toggled.emit("bug_report")
				get_viewport().set_input_as_handled()
				return

	# Clan screen (N)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_N:
		if screen_manager:
			var top := screen_manager.get_top_screen()
			if top == null or top == screen_manager._screens.get("clan"):
				screen_toggled.emit("clan")
				get_viewport().set_input_as_handled()
				return

	# Only process flight inputs when no screen is open
	if screen_manager and screen_manager.is_any_screen_open():
		return

	# === DOCKED STATE ===
	if state == GameManagerSystem.GameState.DOCKED:
		if event.is_action_pressed("dock"):
			terminal_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("toggle_mouse_capture"):
			undock_requested.emit()
			get_viewport().set_input_as_handled()
			return
		return

	# === PLAYING STATE ===
	if event.is_action_pressed("dock") and state == GameManagerSystem.GameState.PLAYING:
		if docking_system and docking_system.can_dock:
			docking_system.request_dock()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_X:
		if loot_pickup and loot_pickup.can_pickup and state == GameManagerSystem.GameState.PLAYING:
			var crate := loot_pickup.request_pickup()
			if crate:
				loot_pickup_requested.emit(crate)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("gate_jump") and state == GameManagerSystem.GameState.PLAYING:
		if system_transition and system_transition.can_gate_jump():
			system_transition.initiate_gate_jump(system_transition.get_gate_target_id())
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("wormhole_jump") and state == GameManagerSystem.GameState.PLAYING:
		if system_transition and system_transition.can_wormhole_jump():
			wormhole_jump_requested.emit()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("toggle_mouse_capture"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
