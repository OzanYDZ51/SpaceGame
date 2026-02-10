class_name WormholeManager
extends Node

# =============================================================================
# Wormhole Manager — handles inter-galaxy wormhole jump sequence.
# Child Node of GameManager.
# =============================================================================

signal wormhole_jump_started
signal wormhole_jump_completed(galaxy: GalaxyData, spawn_system: int)

# Injected refs
var system_transition: SystemTransition = null
var route_manager: RouteManager = null
var fleet_deployment_mgr: FleetDeploymentManager = null
var screen_manager: UIScreenManager = null
var player_data: PlayerData = null


func initiate_wormhole_jump() -> void:
	if route_manager:
		route_manager.cancel_route()
	if fleet_deployment_mgr:
		fleet_deployment_mgr.auto_retrieve_all()
	var wormhole := system_transition.get_active_wormhole()
	if wormhole == null:
		return

	var target_seed: int = wormhole.target_galaxy_seed
	var target_url: String = wormhole.target_server_url

	if target_url.is_empty():
		print("WormholeManager: No target server configured")
		return

	wormhole_jump_started.emit()

	# 1. Start fade out
	if system_transition._transition_overlay:
		system_transition._transition_overlay.visible = true
		system_transition._transition_overlay.modulate.a = 0.0
	system_transition._is_transitioning = true
	system_transition._transition_phase = 1
	system_transition._transition_alpha = 0.0
	system_transition._transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	system_transition.transition_started.emit()

	await system_transition.transition_finished
	await get_tree().create_timer(0.6).timeout

	# 2. Save state before disconnecting
	await SaveManager.save_player_state(true)

	# 3. Disconnect from current server
	var original_seed: int = Constants.galaxy_seed
	NetworkManager.disconnect_from_server()

	# 4. Switch galaxy
	Constants.galaxy_seed = target_seed
	var new_galaxy := GalaxyGenerator.generate(target_seed)
	if system_transition:
		system_transition.galaxy = new_galaxy

	# Re-init station services
	if player_data:
		player_data.station_services = StationServices.new()
		player_data.station_services.init_center_systems(new_galaxy)

	# Update map
	if screen_manager:
		var map_screen := screen_manager._screens.get("map") as UnifiedMapScreen
		if map_screen:
			map_screen.galaxy = new_galaxy

	# 5. Connect to new server
	NetworkManager.connect_to_server(target_url)

	# 6. Wait for connection + config
	var state: Array = [false, false]
	var timeout: float = 10.0

	var on_connected := func():
		state[0] = true
	var on_config := func(_cfg: Dictionary):
		state[1] = true

	NetworkManager.connection_succeeded.connect(on_connected, CONNECT_ONE_SHOT)
	NetworkManager.server_config_received.connect(on_config, CONNECT_ONE_SHOT)

	while not (state[0] and state[1]) and timeout > 0:
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1

	# Check if connection succeeded
	if not (state[0] and state[1]):
		push_error("WormholeManager: Connection to target galaxy timed out!")
		# Revert galaxy seed to original
		Constants.galaxy_seed = original_seed
		# Fade in to show error state, don't jump to invalid system
		system_transition._is_transitioning = false
		system_transition._transition_phase = 3
		system_transition._transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	# 7. Jump to spawn system in new galaxy
	var spawn_sys: int = new_galaxy.player_home_system
	system_transition.jump_to_system(spawn_sys)

	# 8. Fade in
	system_transition._transition_phase = 3
	system_transition._transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("WormholeManager: Jump complete — galaxy seed %d, system %d" % [target_seed, spawn_sys])

	wormhole_jump_completed.emit(new_galaxy, spawn_sys)
