class_name InputRouter
extends Node

# =============================================================================
# Input Router — handles input action setup and input event routing.
# Child Node of GameManager.
# =============================================================================

signal loot_pickup_requested(crate: CargoCrate)
signal wormhole_jump_requested
signal respawn_requested
signal map_toggled(view: int)
signal screen_toggled(screen_name: String)
signal terminal_requested
signal undock_requested
signal build_requested

# Injected refs
var screen_manager: UIScreenManager = null
var docking_system: DockingSystem = null
var loot_pickup: LootPickupSystem = null
var system_transition: SystemTransition = null
var get_game_state: Callable  # () -> GameState
var construction_proximity_check: Callable  # () -> bool


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
		"build": KEY_B,
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


func _unhandled_input(event: InputEvent) -> void:
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

	if event.is_action_pressed("build") and state == GameManagerSystem.GameState.PLAYING:
		if construction_proximity_check.is_valid() and construction_proximity_check.call():
			build_requested.emit()
			get_viewport().set_input_as_handled()
			return

	# DEBUG: F9 = teleport near nearest planet
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F9:
		if state == GameManagerSystem.GameState.PLAYING:
			_debug_teleport_to_planet()
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


func _debug_teleport_to_planet() -> void:
	# Find nearest planet in EntityRegistry and teleport player 200km from surface
	var ship := GameManager.player_ship as ShipController
	if ship == null:
		return

	var best_id: String = ""
	var best_dist: float = INF
	var cam_x: float = FloatingOrigin.origin_offset_x + ship.global_position.x
	var cam_z: float = FloatingOrigin.origin_offset_z + ship.global_position.z

	for id in EntityRegistry._entities:
		var ent: Dictionary = EntityRegistry._entities[id]
		if ent.get("type") != EntityRegistrySystem.EntityType.PLANET:
			continue
		var dx: float = cam_x - ent.get("pos_x", 0.0)
		var dz: float = cam_z - ent.get("pos_z", 0.0)
		var d: float = sqrt(dx * dx + dz * dz)
		if d < best_dist:
			best_dist = d
			best_id = id

	if best_id == "":
		print("[DEBUG] No planet found in current system")
		return

	var ent: Dictionary = EntityRegistry.get_entity(best_id)
	var planet_x: float = ent.get("pos_x", 0.0)
	var planet_z: float = ent.get("pos_z", 0.0)

	# Teleport: set floating origin so planet is ~200km away from player
	var approach_dist: float = 200_000.0  # 200 km
	var dir_x: float = cam_x - planet_x
	var dir_z: float = cam_z - planet_z
	var dir_len: float = sqrt(dir_x * dir_x + dir_z * dir_z)
	if dir_len < 1.0:
		dir_x = 1.0
		dir_z = 0.0
		dir_len = 1.0
	dir_x /= dir_len
	dir_z /= dir_len

	# New player universe position: planet + approach_dist in the direction we came from
	var new_x: float = planet_x + dir_x * approach_dist
	var new_z: float = planet_z + dir_z * approach_dist

	# Reset origin so player ends up at ~(0,0,0) in scene coords
	FloatingOrigin.origin_offset_x = new_x
	FloatingOrigin.origin_offset_y = 0.0
	FloatingOrigin.origin_offset_z = new_z
	ship.global_position = Vector3.ZERO
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO

	# Force universe shift
	FloatingOrigin.origin_shifted.emit(Vector3.ZERO)

	var planet_name: String = ent.get("name", best_id)
	print("[DEBUG] Teleported near planet: %s (200km away)" % planet_name)
