class_name GameManagerSystem
extends Node

# =============================================================================
# Game Manager
# Main orchestrator. Initializes systems, loads scenes, manages game state.
# Input actions are defined in code for reliability across keyboard layouts.
# =============================================================================

## Emitted after ShipFactory rebuilds the player ship (init + ship change).
## Systems (HUD, MiningSystem, ShipNetworkSync) connect to self-rewire.
signal player_ship_rebuilt(ship)

const GameState = Constants.GameState

var current_state: int = Constants.GameState.LOADING
var player_ship: RigidBody3D = null
var universe_node: Node3D = null
var main_scene: Node3D = null
var _music_player: AudioStreamPlayer = null
var _stellar_map = null
var _screen_manager = null
var _tooltip_manager = null
var _toast_manager = null
var _encounter_manager = null
var _corporation_manager = null
var _docking_system = null
var _station_screen = null
var _dock_instance = null
var _system_transition = null
var _galaxy = null
var _death_respawn_mgr = null
var _docking_mgr = null
var _loot_mgr = null
var _input_router = null
var _ship_change_mgr = null
var _wormhole_mgr = null
var _net_sync_mgr = null
var _discord_rpc: DiscordRPC:
	get: return _net_sync_mgr.discord_rpc if _net_sync_mgr else null
var _vfx_manager = null
var player_data = null
var player_inventory:
	get: return player_data.inventory if player_data else null
var player_cargo:
	get: return player_data.cargo if player_data else null
var player_economy:
	get: return player_data.economy if player_data else null
var player_fleet:
	get: return player_data.fleet if player_data else null
	set(value):
		if player_data:
			player_data.fleet = value
var station_services:
	get: return player_data.station_services if player_data else null
	set(value):
		if player_data:
			player_data.station_services = value
var _equipment_screen = null
var _shipyard_screen = null
var _refinery_screen = null
var _storage_screen: Control = null  # StorageScreen
var _refinery_manager = null
var _loot_screen = null
var _loot_pickup = null
var _lod_manager = null
var _asteroid_field_mgr = null
var _mining_system = null
var _commerce_screen = null
var _commerce_manager = null
var _route_manager = null
var _fleet_deployment_mgr = null
var _squadron_mgr = null
var _player_autopilot_wp: String = ""
var _backend_state_loaded: bool = false
var _bug_report_screen = null
var _notif = null
var _structure_auth = null
var _construction_mgr = null
var _planet_lod_mgr = null
var _planet_approach_mgr = null
var _asteroid_scanner = null
var _build_available: bool = false
var _build_beacon_name: String = ""
var _build_marker_id: int = -1
var _construction_screen = null
var _admin_screen = null
var _pause_screen = null
var _options_screen = null
var _gameplay_integrator = null
var station_equipments: Dictionary = {}  # "system_N_station_M" -> StationEquipment


var _quitting: bool = false


func _ready() -> void:
	# Prevent instant quit — we need time to save before exiting
	get_tree().auto_accept_quit = false

	await get_tree().process_frame

	# Auth token is passed by the launcher via CLI: --auth-token <jwt>
	# Authentication is REQUIRED — the launcher handles login/register.
	_read_auth_token_from_cli()

	# Editor dev auto-login: when running from F5 without launcher, auto-authenticate
	if not AuthManager.is_authenticated and OS.has_feature("editor"):
		await _dev_auto_login()

	_initialize_game()

	if AuthManager.is_authenticated:
		# Show black overlay while loading backend state to avoid seeing
		# the default spawn position before the saved position is restored.
		_show_loading_overlay()
		await _load_backend_state()
		_hide_loading_overlay()
		await _show_faction_selection()
	else:
		push_warning("GameManager: No auth token — backend features disabled. Use the launcher to play.")


func _read_auth_token_from_cli() -> void:
	var args =OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--auth-token" and i + 1 < args.size():
			var token: String = args[i + 1]
			AuthManager.set_token_from_launcher(token)
			break
	# Set multiplayer display name from authenticated username
	if AuthManager.is_authenticated and AuthManager.username != "":
		NetworkManager.local_player_name = AuthManager.username


## Auto-login with a dev account when running from the Godot editor (F5).
## Tries login first, then register if the account doesn't exist yet.
func _dev_auto_login() -> void:
	const DEV_USER: String = "dev"
	const DEV_EMAIL: String = "dev@local.dev"
	const DEV_PASS: String = "dev123"

	print("GameManager: [DEV] Auto-login attempt against %s ..." % ApiClient.base_url)

	# Try login
	var result =await ApiClient.post_async("/api/v1/auth/login", {
		"username": DEV_USER, "password": DEV_PASS,
	}, false)
	var status: int = result.get("_status_code", 0)

	# Account doesn't exist yet — register it
	if status != 200 and status != 201:
		print("GameManager: [DEV] Login failed (%d), trying register..." % status)
		result = await ApiClient.post_async("/api/v1/auth/register", {
			"username": DEV_USER, "email": DEV_EMAIL, "password": DEV_PASS,
		}, false)
		status = result.get("_status_code", 0)

	if (status == 200 or status == 201) and result.has("access_token"):
		var token: String = result.get("access_token", "")
		AuthManager.set_token_from_launcher(token)
		# Save refresh token so next editor run restores the session instantly
		var refresh: String = result.get("refresh_token", "")
		if refresh != "":
			AuthManager._refresh_token = refresh
			AuthManager._save_tokens()
		NetworkManager.local_player_name = AuthManager.username
		print("GameManager: [DEV] Logged in as '%s' (id=%s)" % [AuthManager.username, AuthManager.player_id])
	else:
		push_warning("GameManager: [DEV] Auto-login failed: %s" % result.get("error", "backend unreachable?"))


func _setup_ui_managers() -> void:
	var ui_layer =main_scene.get_node_or_null("UI")
	if ui_layer == null:
		push_warning("GameManager: UI CanvasLayer not found, skipping UI managers")
		return

	# Screen manager (handles screen stack, input routing)
	_screen_manager = UIScreenManager.new()
	_screen_manager.name = "UIScreenManager"
	ui_layer.add_child(_screen_manager)

	# Register unified map screen (SYSTEM + GALAXY views)
	if _stellar_map:
		_stellar_map.managed_externally = true
		var map_screen =UnifiedMapScreen.new()
		map_screen.name = "UnifiedMapScreen"
		map_screen.stellar_map = _stellar_map
		map_screen.galaxy = _galaxy
		map_screen.system_transition = _system_transition
		_stellar_map.view_switch_requested.connect(func(): map_screen.switch_to_view(UnifiedMapScreen.ViewMode.GALAXY))
		_screen_manager.register_screen("map", map_screen)

		# Pass fleet data to both map panels
		if player_fleet and _galaxy:
			_stellar_map.set_fleet(player_fleet, _galaxy)
			map_screen.set_fleet(player_fleet, _galaxy)

		# Connect fleet order signal from stellar map
		_stellar_map.fleet_order_requested.connect(_on_fleet_order_from_map)

		# Connect galaxy route from preview mode (right-click in previewed system)
		_stellar_map.galaxy_route_requested.connect(_on_galaxy_route_from_preview.bind(map_screen))

		# Pass squadron data to map
		if _squadron_mgr:
			_stellar_map.set_squadron_manager(_squadron_mgr)
			_stellar_map.squadron_action_requested.connect(_on_squadron_action)

	# Register Corporation screen
	var corporation_screen =CorporationScreen.new()
	corporation_screen.name = "CorporationScreen"
	_screen_manager.register_screen("corporation", corporation_screen)

	# Register Station screen (signal connections deferred to after _docking_mgr creation)
	_station_screen = StationScreen.new()
	_station_screen.name = "StationScreen"
	_screen_manager.register_screen("station", _station_screen)

	# Register Commerce screen (signal connections deferred)
	_commerce_screen = CommerceScreen.new()
	_commerce_screen.name = "CommerceScreen"
	_screen_manager.register_screen("commerce", _commerce_screen)

	# Register Equipment screen (signal connections deferred)
	_equipment_screen = EquipmentScreen.new()
	_equipment_screen.name = "EquipmentScreen"
	_screen_manager.register_screen("equipment", _equipment_screen)

	# Register Shipyard screen (signal connections deferred)
	_shipyard_screen = ShipyardScreen.new()
	_shipyard_screen.name = "ShipyardScreen"
	_screen_manager.register_screen("shipyard", _shipyard_screen)

	# Register Loot screen
	_loot_screen = LootScreen.new()
	_loot_screen.name = "LootScreen"
	_screen_manager.register_screen("loot", _loot_screen)

	# Register Construction screen
	_construction_screen = ConstructionScreen.new()
	_construction_screen.name = "ConstructionScreen"
	_construction_screen.construction_completed.connect(_on_construction_completed)
	_screen_manager.register_screen("construction", _construction_screen)

	# Register Station Admin screen
	_admin_screen = StationAdminScreen.new()
	_admin_screen.name = "StationAdminScreen"
	_screen_manager.register_screen("admin", _admin_screen)

	# Register Refinery screen
	_refinery_screen = RefineryScreen.new()
	_refinery_screen.name = "RefineryScreen"
	_screen_manager.register_screen("refinery", _refinery_screen)

	# Register Storage screen (ENTREPOT)
	var StorageScreenClass =load("res://scripts/ui/screens/station/storage/storage_screen.gd")
	_storage_screen = StorageScreenClass.new()
	_storage_screen.name = "StorageScreen"
	_screen_manager.register_screen("storage", _storage_screen)

	# Register Multiplayer connection screen
	var mp_screen =MultiplayerMenuScreen.new()
	mp_screen.name = "MultiplayerMenuScreen"
	_screen_manager.register_screen("multiplayer", mp_screen)

	# Register Bug Report screen (F12)
	_bug_report_screen = BugReportScreen.new()
	_bug_report_screen.name = "BugReportScreen"
	_screen_manager.register_screen("bug_report", _bug_report_screen)

	# Register Pause screen (ESC)
	_pause_screen = PauseScreen.new()
	_pause_screen.name = "PauseScreen"
	_screen_manager.register_screen("pause", _pause_screen)
	_pause_screen.options_requested.connect(func():
		if _screen_manager:
			_screen_manager.open_screen("options")
	)
	_pause_screen.quit_requested.connect(func():
		_graceful_quit()
	)

	# Register Options screen (opened from pause menu)
	_options_screen = OptionsScreen.new()
	_options_screen.name = "OptionsScreen"
	_screen_manager.register_screen("options", _options_screen)

	# Tooltip manager
	_tooltip_manager = UITooltipManager.new()
	_tooltip_manager.name = "UITooltipManager"
	ui_layer.add_child(_tooltip_manager)

	# Toast manager
	_toast_manager = UIToastManager.new()
	_toast_manager.name = "UIToastManager"
	ui_layer.add_child(_toast_manager)

	# Notification service (centralized toast dispatch)
	_notif = NotificationService.new()
	_notif.name = "NotificationService"
	add_child(_notif)
	_notif.initialize(_toast_manager)

	# Transition overlay (on top of everything)
	if _system_transition:
		var overlay = _system_transition.get_transition_overlay()
		if overlay:
			ui_layer.add_child(overlay)


## Re-set fleet reference on map panels (after backend replaces the fleet via deserialize).
func _refresh_fleet_on_maps() -> void:
	if player_fleet == null or _galaxy == null:
		return
	if _stellar_map:
		_stellar_map.set_fleet(player_fleet, _galaxy)
	if _screen_manager:
		var map_screen = _screen_manager._screens.get("map")
		if map_screen:
			map_screen.set_fleet(player_fleet, _galaxy)


func _initialize_game() -> void:
	var scene =get_tree().current_scene
	if not scene is Node3D:
		return
	main_scene = scene

	universe_node = main_scene.get_node_or_null("Universe")
	if universe_node == null:
		push_error("GameManager: Universe node not found!")
		return

	player_ship = main_scene.get_node_or_null("PlayerShip")
	if player_ship == null:
		push_error("GameManager: PlayerShip not found!")
		return

	# Configure floating origin
	FloatingOrigin.set_tracked_node(player_ship)
	FloatingOrigin.set_universe_node(universe_node)

	# Setup player ship with combat systems
	ShipFactory.setup_player_ship(Constants.DEFAULT_SHIP_ID, player_ship)

	# Generate galaxy (needed before PlayerData.initialize)
	_galaxy = GalaxyGenerator.generate(Constants.galaxy_seed)

	# Player data facade (economy, inventory, cargo, fleet, station services)
	player_data = PlayerData.new()
	player_data.initialize(_galaxy)

	# Equip starting loadout from fleet data
	var starting_fleet_ship = player_data.get_starting_fleet_ship()
	if starting_fleet_ship:
		var start_wm = player_ship.get_node_or_null("WeaponManager")
		if start_wm:
			start_wm.equip_weapons(starting_fleet_ship.weapons)
		var start_em = player_ship.get_node_or_null("EquipmentManager")
		if start_em:
			if starting_fleet_ship.shield_name != &"":
				var shield_res =ShieldRegistry.get_shield(starting_fleet_ship.shield_name)
				if shield_res:
					start_em.equip_shield(shield_res)
			if starting_fleet_ship.engine_name != &"":
				var engine_res =EngineRegistry.get_engine(starting_fleet_ship.engine_name)
				if engine_res:
					start_em.equip_engine(engine_res)
			for i in starting_fleet_ship.modules.size():
				if starting_fleet_ship.modules[i] != &"":
					var mod_res =ModuleRegistry.get_module(starting_fleet_ship.modules[i])
					if mod_res:
						start_em.equip_module(i, mod_res)
	NetworkManager.local_ship_id = Constants.DEFAULT_SHIP_ID

	# Docking system (child of player ship, scans for nearby stations)
	_docking_system = DockingSystem.new()
	_docking_system.name = "DockingSystem"
	player_ship.add_child(_docking_system)
	_docking_system.docked.connect(_on_docked)

	# Ship activation controller (centralized deactivate/activate for dock, death, cruise warp)
	var _activation_ctrl =ShipActivationController.new()
	_activation_ctrl.name = "ShipActivationController"
	player_ship.add_child(_activation_ctrl)

	# Dock instance (isolated solo context manager)
	_dock_instance = DockInstance.new()
	_dock_instance.name = "DockInstance"
	add_child(_dock_instance)
	# ship_change_requested connected after _ship_change_mgr creation (see below)

	# Wire docking system to HUD for dock prompt display
	var hud = main_scene.get_node_or_null("UI/FlightHUD")
	if hud:
		hud.set_docking_system(_docking_system)

	# Fleet Deployment Manager
	_fleet_deployment_mgr = FleetDeploymentManager.new()
	_fleet_deployment_mgr.name = "FleetDeploymentManager"
	add_child(_fleet_deployment_mgr)
	_fleet_deployment_mgr.initialize(player_fleet)

	# Squadron Manager
	_squadron_mgr = SquadronManager.new()
	_squadron_mgr.name = "SquadronManager"
	add_child(_squadron_mgr)
	_squadron_mgr.initialize(player_fleet, _fleet_deployment_mgr)

	# Commerce manager
	_commerce_manager = CommerceManager.new()
	_commerce_manager.player_economy = player_economy
	_commerce_manager.player_inventory = player_inventory
	_commerce_manager.player_fleet = player_fleet
	_commerce_manager.player_data = player_data

	# Refinery manager (lives in player_data for save/load, GameManager keeps ref for tick)
	_refinery_manager = player_data.refinery_manager

	# Wire economy to HUD (must be after player_data creation)
	if hud:
		hud.set_player_economy(player_economy)

	# Loot pickup system (child of player ship, scans for nearby crates)
	_loot_pickup = LootPickupSystem.new()
	_loot_pickup.name = "LootPickupSystem"
	player_ship.add_child(_loot_pickup)

	# Wire loot pickup to HUD for loot prompt display
	if hud:
		hud.set_loot_pickup_system(_loot_pickup)

	# Mining system (child of player ship, handles mining mechanics)
	_mining_system = MiningSystem.new()
	_mining_system.name = "MiningSystem"
	player_ship.add_child(_mining_system)

	# Wire mining system to HUD
	if hud:
		hud.set_mining_system(_mining_system)

	# Ship Change Manager (rewires ship-dependent systems)
	_ship_change_mgr = ShipChangeManager.new()
	_ship_change_mgr.name = "ShipChangeManager"
	_ship_change_mgr.player_ship = player_ship
	_ship_change_mgr.main_scene = main_scene
	_ship_change_mgr.player_data = player_data
	_ship_change_mgr.mining_system = _mining_system
	_ship_change_mgr.get_game_state = func() -> int: return current_state
	_ship_change_mgr._on_destroyed_callback = _on_player_destroyed
	_ship_change_mgr._on_autopilot_cancelled_callback = _on_autopilot_cancelled_by_player
	_ship_change_mgr.ship_rebuilt.connect(func(ship): player_ship_rebuilt.emit(ship))
	add_child(_ship_change_mgr)
	_dock_instance.ship_change_requested.connect(_ship_change_mgr.handle_ship_change)

	# Wire all ship-dependent systems (signals, HUD, mining, LOD, network)
	_ship_change_mgr.rewire_ship_systems()

	# Wire stellar map
	_stellar_map = main_scene.get_node_or_null("UI/StellarMap")

	# Construction Manager (shared between map and GameManager)
	_construction_mgr = ConstructionManager.new()
	if _stellar_map:
		_stellar_map.set_construction_manager(_construction_mgr)
		_stellar_map.construction_marker_placed.connect(_on_construction_marker_placed)

	# Create system transition manager
	_system_transition = SystemTransition.new()
	_system_transition.name = "SystemTransition"
	_system_transition.galaxy = _galaxy
	add_child(_system_transition)
	_system_transition.system_loaded.connect(_on_system_loaded)
	_system_transition.system_unloading.connect(_on_system_unloading)

	# Wire system transition to HUD for gate prompt display
	var hud_ref = main_scene.get_node_or_null("UI/FlightHUD")
	if hud_ref:
		hud_ref.set_system_transition(_system_transition)

	# Ship LOD Manager (must exist before encounter manager spawns ships)
	_lod_manager = ShipLODManager.new()
	_lod_manager.name = "ShipLODManager"
	add_child(_lod_manager)
	_lod_manager.initialize(universe_node)

	# Register player ship in LOD system (always LOD0)
	var player_lod =ShipLODData.new()
	player_lod.id = &"player_ship"
	player_lod.ship_id = player_ship.ship_data.ship_id if player_ship.ship_data else Constants.DEFAULT_SHIP_ID
	player_lod.ship_class = player_ship.ship_data.ship_class if player_ship.ship_data else &"Fighter"
	player_lod.faction = &"nova_terra"
	player_lod.display_name = NetworkManager.local_player_name
	player_lod.node_ref = player_ship
	player_lod.current_lod = ShipLODData.LODLevel.LOD0
	player_lod.position = player_ship.global_position
	_lod_manager.register_ship(&"player_ship", player_lod)
	_lod_manager.set_player_id(&"player_ship")

	# Create projectile pool under LOD manager
	var proj_pool =ProjectilePool.new()
	proj_pool.name = "ProjectilePool"
	_lod_manager.add_child(proj_pool)
	# Pre-warm pools for all projectile types to avoid runtime instantiation
	proj_pool.warm_pool("res://scenes/weapons/laser_bolt.tscn", 200)

	# Asteroid Field Manager (must exist before system loading)
	_asteroid_field_mgr = AsteroidFieldManager.new()
	_asteroid_field_mgr.name = "AsteroidFieldManager"
	add_child(_asteroid_field_mgr)
	_asteroid_field_mgr.initialize(universe_node)

	# Planet LOD Manager (must exist before system loading)
	_planet_lod_mgr = PlanetLODManager.new()
	_planet_lod_mgr.name = "PlanetLODManager"
	add_child(_planet_lod_mgr)

	# Planet Approach Manager (gravity, drag, zone transitions)
	_planet_approach_mgr = PlanetApproachManager.new()
	_planet_approach_mgr.name = "PlanetApproachManager"
	add_child(_planet_approach_mgr)
	_planet_approach_mgr.set_ship(player_ship)

	# Wire atmosphere environment transitions (fog, sky, light changes on planet surface)
	if main_scene.get("world_env") != null:
		var space_env = main_scene
		var env: Environment = space_env.world_env.environment if space_env.world_env else null
		var dir_light: DirectionalLight3D = space_env.star_light
		if env:
			_planet_approach_mgr.setup_atmosphere_environment(env, dir_light)

	# Wire planetary HUD
	var hud_planet = main_scene.get_node_or_null("UI/FlightHUD")
	if hud_planet:
		hud_planet.set_planet_approach_manager(_planet_approach_mgr)

	# Wire mining system to asteroid field manager
	if _mining_system:
		_mining_system.set_asteroid_manager(_asteroid_field_mgr)

	# Asteroid Scanner
	_asteroid_scanner = AsteroidScanner.new()
	_asteroid_scanner.name = "AsteroidScanner"
	add_child(_asteroid_scanner)
	_asteroid_scanner.initialize(_asteroid_field_mgr, player_ship, universe_node)
	if _notif:
		_asteroid_scanner.set_notification_service(_notif)
	var hud_scan = main_scene.get_node_or_null("UI/FlightHUD")
	if hud_scan:
		hud_scan.set_asteroid_scanner(_asteroid_scanner)

	# Route Manager (multi-system autopilot)
	_route_manager = RouteManager.new()
	_route_manager.name = "RouteManager"
	_route_manager.system_transition = _system_transition
	_route_manager.galaxy_data = _galaxy
	add_child(_route_manager)
	_route_manager.route_completed.connect(_on_route_completed)
	_route_manager.route_cancelled.connect(_on_route_cancelled)
	_system_transition.gate_proximity_entered.connect(_route_manager.on_gate_proximity)

	# Death & Respawn Manager
	_death_respawn_mgr = DeathRespawnManager.new()
	_death_respawn_mgr.name = "DeathRespawnManager"
	_death_respawn_mgr.player_ship = player_ship
	_death_respawn_mgr.main_scene = main_scene
	_death_respawn_mgr.galaxy = _galaxy
	_death_respawn_mgr.system_transition = _system_transition
	_death_respawn_mgr.route_manager = _route_manager
	_death_respawn_mgr.fleet_deployment_mgr = _fleet_deployment_mgr
	add_child(_death_respawn_mgr)
	_death_respawn_mgr.player_died.connect(func():
		current_state = GameState.DEAD
		if _discord_rpc:
			_discord_rpc.update_from_game_state(current_state)
		SaveManager.trigger_save("player_death")
	)
	_death_respawn_mgr.player_respawned.connect(func():
		current_state = GameState.PLAYING
		if _discord_rpc:
			_discord_rpc.update_from_game_state(current_state)
		SaveManager.trigger_save("respawned")
	)

	# Encounter Manager (must exist before system loading)
	_encounter_manager = EncounterManager.new()
	_encounter_manager.name = "EncounterManager"
	add_child(_encounter_manager)

	# Corporation Manager
	_corporation_manager = CorporationManager.new()
	_corporation_manager.name = "CorporationManager"
	add_child(_corporation_manager)

	# Setup UI framework managers (needs _galaxy and _system_transition)
	_setup_ui_managers()

	# Gameplay systems integrator (missions, factions, POI, economy)
	_gameplay_integrator = GameplayIntegrator.new()
	_gameplay_integrator.name = "GameplayIntegrator"
	add_child(_gameplay_integrator)
	_gameplay_integrator.initialize({
		"screen_manager": _screen_manager,
		"station_screen": _station_screen,
		"encounter_manager": _encounter_manager,
		"notif": _notif,
		"player_data": player_data,
	})

	# Wire faction manager to HUD
	var hud_fac = main_scene.get_node_or_null("UI/FlightHUD")
	if hud_fac and _gameplay_integrator.faction_manager:
		hud_fac.set_faction_manager(_gameplay_integrator.faction_manager)

	# Load starting system (replaces hardcoded seed=42)
	_system_transition.jump_to_system(_galaxy.player_home_system)

	# Configure stellar map
	if _stellar_map:
		_stellar_map.set_player_id("player_ship")

	# Wormhole Manager
	_wormhole_mgr = WormholeManager.new()
	_wormhole_mgr.name = "WormholeManager"
	_wormhole_mgr.system_transition = _system_transition
	_wormhole_mgr.route_manager = _route_manager
	_wormhole_mgr.fleet_deployment_mgr = _fleet_deployment_mgr
	_wormhole_mgr.screen_manager = _screen_manager
	_wormhole_mgr.player_data = player_data
	add_child(_wormhole_mgr)
	_wormhole_mgr.wormhole_jump_completed.connect(func(new_gal, _spawn: int):
		_galaxy = new_gal
	)

	# Input Router
	_input_router = InputRouter.new()
	_input_router.name = "InputRouter"
	_input_router.screen_manager = _screen_manager
	_input_router.docking_system = _docking_system
	_input_router.loot_pickup = _loot_pickup
	_input_router.system_transition = _system_transition
	_input_router.get_game_state = func() -> int: return current_state
	add_child(_input_router)
	_input_router.respawn_requested.connect(func():
		if _death_respawn_mgr:
			_death_respawn_mgr.handle_respawn()
	)
	_input_router.map_toggled.connect(_handle_map_toggle)
	_input_router.screen_toggled.connect(func(sn: String):
		if _screen_manager:
			_screen_manager.toggle_screen(sn)
	)
	_input_router.wormhole_jump_requested.connect(func():
		if _wormhole_mgr:
			_wormhole_mgr.initiate_wormhole_jump()
	)
	# terminal_requested, undock_requested, loot_pickup_requested connected after
	# _docking_mgr and _loot_mgr are created (see below)

	# Capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Audio buses (must exist before music player)
	_setup_audio_buses()

	# Background music (skip on server — no audio needed)
	if not NetworkManager.is_server():
		_music_player = AudioStreamPlayer.new()
		_music_player.stream = load("res://assets/audio/game_background_music.mp3")
		_music_player.volume_db = -35.0
		_music_player.bus = "Music"
		_music_player.name = "BackgroundMusic"
		add_child(_music_player)
		_music_player.finished.connect(_music_player.play)
		_music_player.play()

	# Visual effects
	_setup_visual_effects()

	# Network Sync Manager (creates ShipNetworkSync, ServerAuthority, NpcAuthority, etc.)
	_net_sync_mgr = NetworkSyncManager.new()
	_net_sync_mgr.name = "NetworkSyncManager"
	_net_sync_mgr.lod_manager = _lod_manager
	_net_sync_mgr.system_transition = _system_transition
	_net_sync_mgr.universe_node = universe_node
	_net_sync_mgr.galaxy = _galaxy
	_net_sync_mgr.screen_manager = _screen_manager
	_net_sync_mgr.player_data = player_data
	_net_sync_mgr.fleet_deployment_mgr = _fleet_deployment_mgr
	add_child(_net_sync_mgr)
	_net_sync_mgr.setup(player_ship, self)
	_net_sync_mgr.server_galaxy_changed.connect(func(new_gal):
		_galaxy = new_gal
	)

	# Spawn initial NPCs (deferred from system load — NpcAuthority needed first).
	# Only the server spawns NPCs; clients receive them via NpcAuthority sync.
	if NetworkManager.is_server():
		if _encounter_manager:
			_encounter_manager.spawn_deferred()
	# Now that network is set up, inject ship_net_sync into ShipChangeManager + LOD
	if _ship_change_mgr:
		_ship_change_mgr.ship_net_sync = _net_sync_mgr.ship_net_sync
		_ship_change_mgr.lod_manager = _lod_manager

	# Structure Authority (server-authoritative station damage sync)
	_structure_auth = StructureAuthority.new()
	_structure_auth.name = "StructureAuthority"
	add_child(_structure_auth)

	# Docking Manager (needs screen_manager, station_screen, etc. from _setup_ui_managers)
	_docking_mgr = DockingManager.new()
	_docking_mgr.name = "DockingManager"
	_docking_mgr.player_ship = player_ship
	_docking_mgr.main_scene = main_scene
	_docking_mgr.docking_system = _docking_system
	_docking_mgr.dock_instance = _dock_instance
	_docking_mgr.screen_manager = _screen_manager
	_docking_mgr.notif = _notif
	_docking_mgr.player_data = player_data
	_docking_mgr.commerce_manager = _commerce_manager
	_docking_mgr.commerce_screen = _commerce_screen
	_docking_mgr.equipment_screen = _equipment_screen
	_docking_mgr.shipyard_screen = _shipyard_screen
	_docking_mgr.station_screen = _station_screen
	_docking_mgr.admin_screen = _admin_screen
	_docking_mgr.refinery_screen = _refinery_screen
	_docking_mgr.storage_screen = _storage_screen
	_docking_mgr.system_transition = _system_transition
	_docking_mgr.route_manager = _route_manager
	_docking_mgr.fleet_deployment_mgr = _fleet_deployment_mgr
	_docking_mgr.lod_manager = _lod_manager
	_docking_mgr.encounter_manager = _encounter_manager
	_docking_mgr.ship_net_sync = _net_sync_mgr.ship_net_sync if _net_sync_mgr else null
	_docking_mgr.discord_rpc = _net_sync_mgr.discord_rpc if _net_sync_mgr else null
	_docking_mgr.get_game_state = func() -> int: return current_state
	add_child(_docking_mgr)
	# Inject docking + ship change refs into death/respawn manager for auto-dock on respawn
	if _death_respawn_mgr:
		_death_respawn_mgr.docking_mgr = _docking_mgr
		_death_respawn_mgr.docking_system = _docking_system
		_death_respawn_mgr.ship_change_mgr = _ship_change_mgr
	# Connect station/commerce/equipment screen signals directly to DockingManager
	_station_screen.undock_requested.connect(_docking_mgr.handle_undock)
	_station_screen.equipment_requested.connect(_docking_mgr.handle_equipment_requested)
	_station_screen.commerce_requested.connect(_docking_mgr.handle_commerce_requested)
	_station_screen.repair_requested.connect(_docking_mgr.handle_repair_requested)
	_station_screen.shipyard_requested.connect(_docking_mgr.handle_shipyard_requested)
	_station_screen.station_equipment_requested.connect(_docking_mgr.handle_station_equipment_requested)
	_station_screen.administration_requested.connect(_docking_mgr.handle_administration_requested)
	_station_screen.refinery_requested.connect(_docking_mgr.handle_refinery_requested)
	_station_screen.storage_requested.connect(_docking_mgr.handle_storage_requested)
	_commerce_screen.commerce_closed.connect(_docking_mgr.handle_commerce_closed)
	_equipment_screen.equipment_closed.connect(_docking_mgr.handle_equipment_closed)
	_shipyard_screen.shipyard_closed.connect(_docking_mgr.handle_shipyard_closed)
	_admin_screen.closed.connect(_docking_mgr.handle_admin_closed)
	_admin_screen.station_renamed.connect(_on_station_renamed)
	_refinery_screen.refinery_closed.connect(_docking_mgr.handle_refinery_closed)
	_storage_screen.storage_closed.connect(_docking_mgr.handle_storage_closed)
	_docking_mgr.docked.connect(func(_sn: String):
		current_state = GameState.DOCKED
		if _discord_rpc:
			_discord_rpc.update_from_game_state(current_state)
		SaveManager.trigger_save("docked")
	)
	_docking_mgr.undocked.connect(func():
		current_state = GameState.PLAYING
		if _discord_rpc:
			_discord_rpc.update_from_game_state(current_state)
		# Safety: ensure fleet NPCs are visible after undock
		if _fleet_deployment_mgr:
			_fleet_deployment_mgr.ensure_deployed_visible()
		# Force immediate network sync so remote peers see us undocked right away
		if _net_sync_mgr and _net_sync_mgr.ship_net_sync:
			_net_sync_mgr.ship_net_sync.force_send_now()
		# Force LOD re-evaluation so NPCs/players appear without 0.2s delay
		if _lod_manager:
			_lod_manager.force_immediate_evaluation()
		SaveManager.trigger_save("undocked")

		# Diagnostic: verify all systems are running after undock
		print("[GM-Undock] state=%d connected=%s universe_pm=%d lod_pm=%d remote_players=%d remote_npcs=%d" % [
			current_state,
			str(NetworkManager.is_connected_to_server()),
			universe_node.process_mode if universe_node else -1,
			_lod_manager.process_mode if _lod_manager else -1,
			_net_sync_mgr.remote_players.size() if _net_sync_mgr else 0,
			_net_sync_mgr.remote_npcs.size() if _net_sync_mgr else 0,
		])
	)

	# Loot Manager
	_loot_mgr = LootManager.new()
	_loot_mgr.name = "LootManager"
	_loot_mgr.player_data = player_data
	_loot_mgr.screen_manager = _screen_manager
	_loot_mgr.loot_screen = _loot_screen
	_loot_mgr.notif = _notif
	_loot_mgr.get_game_state = func() -> int: return current_state
	add_child(_loot_mgr)

	# Deferred InputRouter connections (need _docking_mgr + _loot_mgr)
	_input_router.terminal_requested.connect(_docking_mgr.open_station_terminal)
	_input_router.undock_requested.connect(_docking_mgr.handle_undock)
	_input_router.loot_pickup_requested.connect(_loot_mgr.open_loot_screen)
	_input_router.build_requested.connect(_on_build_requested)
	_input_router.construction_proximity_check = func() -> bool: return _build_available
	if _asteroid_scanner:
		_input_router.scanner_pulse_requested.connect(_asteroid_scanner.trigger_scan)

	# Load user settings (audio volumes, key rebinds) — after InputRouter sets up actions
	if _options_screen:
		_options_screen.load_settings()

	# Reload backend state on reconnect (not first connect — that's handled in _ready)
	NetworkManager.connection_succeeded.connect(_on_network_reconnected)

	current_state = GameState.PLAYING
	if _discord_rpc:
		_discord_rpc.update_from_game_state(current_state)

	# Start auto-save timer
	SaveManager.start_auto_save()


## Called on every successful connection (initial + reconnects).
## Skips the first connect (handled by _ready → _load_backend_state).
func _on_network_reconnected() -> void:
	if not _backend_state_loaded:
		return  # First connect — _ready handles this
	print("[GameManager] Network reconnected — reloading backend state")
	_load_backend_state()


func _show_loading_overlay() -> void:
	if _system_transition:
		var overlay: ColorRect = _system_transition.get_transition_overlay()
		if overlay:
			overlay.visible = true
			overlay.modulate.a = 1.0
			overlay.mouse_filter = Control.MOUSE_FILTER_STOP


func _hide_loading_overlay() -> void:
	if _system_transition:
		var overlay: ColorRect = _system_transition.get_transition_overlay()
		if overlay:
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tw := create_tween()
			tw.tween_property(overlay, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_callback(func(): overlay.visible = false)


func _show_faction_selection() -> void:
	if _gameplay_integrator == null or _gameplay_integrator.faction_manager == null:
		return
	var fm = _gameplay_integrator.faction_manager

	var faction_screen := FactionSelectionScreen.new()
	var playable: Array[FactionResource] = []
	for f in fm.get_all_factions():
		if f.is_playable:
			playable.append(f)
	faction_screen.setup(playable, fm.player_faction)

	var ui_layer = main_scene.get_node_or_null("UI")
	if ui_layer == null:
		return
	ui_layer.add_child(faction_screen)
	faction_screen.open()

	# Release mouse so user can click
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var selected: StringName = await faction_screen.faction_selected
	fm.set_player_faction(selected)

	# Update player LOD faction
	if _lod_manager and _lod_manager._ships.has(&"player_ship"):
		_lod_manager._ships[&"player_ship"].faction = selected

	SaveManager.trigger_save("faction_selected")

	faction_screen.close()
	await get_tree().create_timer(0.4).timeout
	faction_screen.queue_free()

	# Re-capture mouse for flight
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _load_backend_state() -> void:
	if not AuthManager.is_authenticated:
		return
	var state: Dictionary = await SaveManager.load_player_state()
	if not state.is_empty() and not state.has("error"):
		SaveManager.apply_state(state)
		_backend_state_loaded = true

		# Update network ship ID to match restored ship
		if player_ship and player_ship.ship_data:
			NetworkManager.local_ship_id = player_ship.ship_data.ship_id

		# Re-register with server if already connected (corrects ship_id + system)
		if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
			var uuid: String = AuthManager.player_id if AuthManager.is_authenticated else ""
			NetworkManager._rpc_register_player.rpc_id(1, NetworkManager.local_player_name, String(NetworkManager.local_ship_id), uuid)

		# Fleet reference was replaced by deserialize — reconnect map panels
		_refresh_fleet_on_maps()
		# Redeploy fleet ships that were deployed in the current system.
		# apply_state() restores fleet data (positions, commands, deployment_state)
		# but the system already loaded before the backend responded, so
		# _on_system_loaded().redeploy_saved_ships() ran with the default fleet.
		if _fleet_deployment_mgr:
			_fleet_deployment_mgr.redeploy_saved_ships()

		# Restore docked state if the player was docked when they disconnected.
		# apply_state only restores position/fleet — it doesn't re-enter the dock.
		_try_restore_docked_state(state)


## Re-enter dock if the player was docked when they saved/disconnected.
## Reads the active FleetShip's deployment_state + docked_station_id (persisted in fleet JSONB).
func _try_restore_docked_state(_state: Dictionary) -> void:
	if current_state == GameState.DOCKED:
		return

	# Check if active fleet ship was DOCKED with a known station
	if player_fleet == null:
		return
	var active_fs = player_fleet.get_active()
	if active_fs == null:
		return
	if active_fs.deployment_state != FleetShip.DeploymentState.DOCKED:
		return
	if active_fs.docked_station_id == "":
		return

	# Resolve station name from EntityRegistry
	var station_name: String = ""
	var ent: Dictionary = EntityRegistry.get_entity(active_fs.docked_station_id)
	station_name = ent.get("name", "")

	# Fallback: find the nearest station in the current system
	if station_name == "":
		var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
		var best_dist: float = INF
		var ship_pos: Vector3 = player_ship.global_position if player_ship else Vector3.ZERO
		for st_ent in stations:
			var node = st_ent.get("node")
			if node == null or not is_instance_valid(node):
				continue
			var dist: float = ship_pos.distance_to(node.global_position)
			if dist < best_dist:
				best_dist = dist
				station_name = st_ent.get("name", "")

	if station_name == "":
		push_warning("[GameManager] Cannot restore docked state — no station found for id '%s'" % active_fs.docked_station_id)
		return

	print("[GameManager] Restoring docked state at station: %s" % station_name)
	if _docking_mgr:
		_docking_mgr.handle_docked(station_name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _quitting:
			return
		_quitting = true
		_graceful_quit()


## Saves player state and waits for completion before quitting.
## auto_accept_quit = false keeps the game alive until save finishes.
func _graceful_quit() -> void:
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.force_sync_positions()
	if AuthManager.is_authenticated:
		# Fire the save — await gives it time to complete the HTTP PUT
		var saved: bool = await SaveManager.save_player_state(true)
		if saved:
			print("[GameManager] Closing save completed successfully.")
		else:
			print("[GameManager] Closing save failed — quitting anyway.")
	get_tree().quit()


func _setup_audio_buses() -> void:
	# Create Music bus (child of Master) for background music
	AudioServer.add_bus()
	var music_idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(music_idx, "Music")
	AudioServer.set_bus_send(music_idx, "Master")

	# Create SFX bus (child of Master) for weapon/effect sounds
	AudioServer.add_bus()
	var sfx_idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(sfx_idx, "SFX")
	AudioServer.set_bus_send(sfx_idx, "Master")


func _setup_visual_effects() -> void:
	_vfx_manager = VFXManager.new()
	_vfx_manager.name = "VFXManager"
	add_child(_vfx_manager)
	var camera = player_ship.get_node_or_null("ShipCamera")
	_vfx_manager.initialize(player_ship, camera, universe_node, main_scene)
	player_ship_rebuilt.connect(_vfx_manager.on_ship_rebuilt)


func _on_system_unloading(system_id: int) -> void:
	_cleanup_player_autopilot_wp()
	_build_available = false
	if _gameplay_integrator:
		_gameplay_integrator.on_system_unloading()
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.release_scene_nodes()
	SaveManager.trigger_save("system_jump")
	if _net_sync_mgr:
		_net_sync_mgr.on_system_unloading(system_id)


func _on_system_loaded(system_id: int) -> void:
	# Update stellar map with new system info
	if _stellar_map and _system_transition.current_system_data:
		_stellar_map.set_system_name(_system_transition.current_system_data.system_name)
	# Clear stale route lines from previous system
	if _stellar_map:
		_stellar_map._clear_route_line()

	# Update Discord RPC with current system name
	if _discord_rpc and _system_transition.current_system_data:
		_discord_rpc.set_system(_system_transition.current_system_data.system_name)

	# Notify route manager (continues multi-system autopilot)
	if _route_manager:
		_route_manager.on_system_loaded(system_id)

	# Ensure all DOCKED fleet ships have a valid docked_system_id
	# (starting ship is created before system loads; old saves may lack this field)
	if player_fleet:
		for i in player_fleet.ships.size():
			var fs = player_fleet.ships[i]
			if fs.deployment_state == FleetShip.DeploymentState.DOCKED and fs.docked_system_id < 0:
				fs.docked_system_id = system_id

	# Redeploy fleet ships that were deployed in this system (from save)
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.redeploy_saved_ships()

	# Respawn construction beacons for this system
	_respawn_construction_beacons(system_id)

	# Notify gameplay integrator (POIs, missions, etc.)
	if _gameplay_integrator:
		var danger: int = 1
		if _galaxy:
			var sys_dict: Dictionary = _galaxy.get_system(system_id)
			danger = int(sys_dict.get("danger_level", 1))
		_gameplay_integrator.on_system_loaded(system_id, danger)

	# Update nebula wisps with new system's environment colors/opacity
	if _vfx_manager and main_scene.get("world_env") != null:
		var space_env = main_scene
		_vfx_manager.configure_nebula_environment(space_env._current_env_data)


func _on_fleet_order_from_map(fleet_index: int, order_id: StringName, params: Dictionary) -> void:
	if player_fleet == null or fleet_index < 0 or fleet_index >= player_fleet.ships.size():
		push_warning("FleetOrder: invalid fleet_index=%d (fleet size=%d, fleet=%s)" % [fleet_index, player_fleet.ships.size() if player_fleet else -1, str(player_fleet != null)])
		return

	# Active ship = engage player autopilot to destination
	if fleet_index == player_fleet.active_index:
		# If docked, undock first then autopilot after a frame
		if current_state == GameState.DOCKED and _docking_mgr:
			if not _docking_mgr.handle_undock():
				return  # Exit blocked, abort fleet order
			# Wait one frame for undock to finish (state → PLAYING)
			await get_tree().process_frame
		_autopilot_player_to(params)
		# Propagate to squadron members if player is a squadron leader
		if _squadron_mgr:
			var sq = player_fleet.get_ship_squadron(fleet_index)
			if sq and (sq.is_leader(fleet_index) or sq.leader_fleet_index < 0):
				_squadron_mgr.propagate_leader_order(sq.squadron_id, order_id, params)
		return

	if _fleet_deployment_mgr == null:
		push_warning("FleetOrder: _fleet_deployment_mgr is null!")
		return
	var fs = player_fleet.ships[fleet_index]
	print("[FleetOrder] idx=%d order=%s state=%d sys=%d cur_sys=%d" % [fleet_index, order_id, fs.deployment_state, fs.docked_system_id, current_system_id_safe()])
	var _route_x: float = params.get("target_x", params.get("center_x", 0.0))
	var _route_z: float = params.get("target_z", params.get("center_z", 0.0))

	# Guard: fleet operations require server connection
	if not NetworkManager.is_connected_to_server():
		_notif.fleet.deploy_failed("PAS DE CONNEXION AU SERVEUR")
		push_warning("FleetOrder: NOT connected to server — cannot send fleet RPC!")
		return

	if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
		if not _fleet_deployment_mgr.can_deploy(fleet_index):
			if fs.docked_system_id != current_system_id_safe():
				_notif.fleet.deploy_failed("VAISSEAU DANS UN AUTRE SYSTEME")
			else:
				_notif.fleet.deploy_failed("DEPLOIEMENT IMPOSSIBLE")
			return
		_fleet_deployment_mgr.request_deploy(fleet_index, order_id, params)
		_notif.fleet.deployed(fs.custom_name)
	elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		_fleet_deployment_mgr.request_change_command(fleet_index, order_id, params)
		if _stellar_map:
			_stellar_map._set_route_lines([fleet_index] as Array[int], _route_x, _route_z)

	# Propagate to squadron members if this ship is a leader
	if _squadron_mgr and fs.squadron_id >= 0:
		var sq = player_fleet.get_squadron(fs.squadron_id)
		if sq and sq.is_leader(fleet_index):
			_squadron_mgr.propagate_leader_order(sq.squadron_id, order_id, params)

	if fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
		_notif.fleet.destroyed()


func _on_squadron_action(action: StringName, data: Dictionary) -> void:
	if _squadron_mgr == null or player_fleet == null:
		return
	match action:
		&"create":
			var leader_idx: int = int(data.get("leader", -1))
			var members: Array = data.get("members", [])
			var sq_name: String = data.get("name", "")
			var sq = _squadron_mgr.create_squadron(leader_idx, sq_name)
			if sq:
				for m in members:
					_squadron_mgr.add_to_squadron(sq.squadron_id, int(m))
				_notif.squadron.created(sq.squadron_name)
		&"disband":
			var sq_id: int = int(data.get("squadron_id", -1))
			_squadron_mgr.disband_squadron(sq_id)
			_notif.squadron.disbanded()
		&"add_member":
			var sq_id: int = int(data.get("squadron_id", -1))
			var fleet_idx: int = int(data.get("fleet_index", -1))
			_squadron_mgr.add_to_squadron(sq_id, fleet_idx)
		&"remove_member":
			var fleet_idx: int = int(data.get("fleet_index", -1))
			_squadron_mgr.remove_from_squadron(fleet_idx)
		&"reset_to_follow":
			var fleet_idx: int = int(data.get("fleet_index", -1))
			_squadron_mgr.reset_to_follow(fleet_idx)
		&"rename":
			var sq_id: int = int(data.get("squadron_id", -1))
			var new_name: String = data.get("name", "")
			if new_name != "":
				_squadron_mgr.rename_squadron(sq_id, new_name)
				_notif.squadron.renamed(new_name)
		&"promote_leader":
			var sq_id: int = int(data.get("squadron_id", -1))
			var fleet_idx: int = int(data.get("fleet_index", -1))
			_squadron_mgr.promote_leader(sq_id, fleet_idx)
			if player_fleet and fleet_idx >= 0 and fleet_idx < player_fleet.ships.size():
				_notif.squadron.new_leader(player_fleet.ships[fleet_idx].custom_name)
		&"create_player":
			if _squadron_mgr.get_player_squadron() != null:
				_notif.toast("ESCADRON DEJA ACTIF")
			else:
				var sq = _squadron_mgr.create_player_squadron()
				if sq:
					_notif.squadron.created(sq.squadron_name)
		&"set_formation":
			var sq_id: int = int(data.get("squadron_id", -1))
			var formation_type: StringName = StringName(data.get("formation_type", "echelon"))
			_squadron_mgr.set_formation(sq_id, formation_type)
			_notif.toast("FORMATION: %s" % SquadronFormation.get_formation_display(formation_type))
		&"add_and_deploy":
			var fleet_idx: int = int(data.get("fleet_index", -1))
			if fleet_idx < 0 or fleet_idx >= player_fleet.ships.size():
				return
			var sq = _squadron_mgr.get_player_squadron()
			if sq == null:
				_notif.toast("AUCUN ESCADRON ACTIF")
				return
			var fs = player_fleet.ships[fleet_idx]
			if fs.squadron_id >= 0 or fleet_idx == player_fleet.active_index:
				return
			if fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
				return
			if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
				if fs.docked_system_id != current_system_id_safe():
					_notif.toast("VAISSEAU TROP LOIN")
					return
				if _fleet_deployment_mgr:
					_fleet_deployment_mgr.request_deploy(fleet_idx, &"move_to", {})
					_notif.fleet.deployed(fs.custom_name)
			_squadron_mgr.add_to_squadron(sq.squadron_id, fleet_idx)


func _autopilot_player_to(params: Dictionary) -> void:
	var ship = player_ship
	if ship == null or current_state != GameState.PLAYING:
		return
	# Clean up previous temp waypoint
	_cleanup_player_autopilot_wp()
	# Cancel any active route
	if _route_manager and _route_manager.is_route_active():
		_route_manager.cancel_route()
	# If targeting a known entity (planet, station, gate), autopilot to it directly
	var entity_id: String = params.get("entity_id", "")
	if entity_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(entity_id)
		if not ent.is_empty():
			var ent_type: int = ent.get("type", -1)
			var is_gate: bool = ent_type == EntityRegistrySystem.EntityType.JUMP_GATE
			ship.engage_autopilot(entity_id, ent.get("name", "Destination"), is_gate)
			return
	# Fallback: register a temporary waypoint entity for autopilot
	var target_x: float = params.get("target_x", 0.0)
	var target_z: float = params.get("target_z", 0.0)
	_player_autopilot_wp = "player_wp_%d" % Time.get_ticks_msec()
	EntityRegistry.register(_player_autopilot_wp, {
		"name": "Destination",
		"type": EntityRegistrySystem.EntityType.SHIP_PLAYER,
		"pos_x": target_x,
		"pos_y": 0.0,
		"pos_z": target_z,
		"node": null,
		"radius": 0.0,
		"color": Color.TRANSPARENT,
		"extra": {"hidden": true},
	})
	# is_gate=true → 30m arrival (not 10km), smooth approach
	ship.engage_autopilot(_player_autopilot_wp, "Destination", true)


func _cleanup_player_autopilot_wp() -> void:
	if _player_autopilot_wp != "":
		EntityRegistry.unregister(_player_autopilot_wp)
		_player_autopilot_wp = ""



# =============================================================================
# GALAXY ROUTE (multi-system autopilot)
# =============================================================================
func start_galaxy_route(target_sys_id: int) -> void:
	if _route_manager == null or _system_transition == null or _galaxy == null:
		return

	var current_sys: int = _system_transition.current_system_id
	if current_sys == target_sys_id:
		_notif.nav.already_here()
		return

	var success: bool = _route_manager.start_route(current_sys, target_sys_id)
	if not success:
		_notif.nav.route_not_found()
		return

	var sys_name: String = _galaxy.get_system_name(target_sys_id)
	var jumps: int = _route_manager.get_jumps_total()
	_notif.nav.route_started(sys_name, jumps)


func start_galaxy_route_to(target_sys_id: int, dest_x: float, dest_z: float, dest_name: String) -> void:
	if _route_manager == null or _system_transition == null or _galaxy == null:
		return

	var current_sys: int = _system_transition.current_system_id
	if current_sys == target_sys_id:
		_notif.nav.already_here()
		return

	var success: bool = _route_manager.start_route_to(current_sys, target_sys_id, dest_x, dest_z, dest_name)
	if not success:
		_notif.nav.route_not_found()
		return

	var sys_name: String = _galaxy.get_system_name(target_sys_id)
	var jumps: int = _route_manager.get_jumps_total()
	_notif.nav.route_started(sys_name, jumps)


func _on_galaxy_route_from_preview(system_id: int, dest_x: float, dest_z: float, dest_name: String, map_screen: Control) -> void:
	start_galaxy_route_to(system_id, dest_x, dest_z, dest_name)
	# Switch to galaxy view (keeps map open so user can see the route path
	# and re-preview the destination to see the arrival route line)
	if map_screen and map_screen.has_method("switch_to_view"):
		map_screen.switch_to_view(1)  # ViewMode.GALAXY


func _on_route_completed() -> void:
	_notif.nav.route_completed()


func _on_route_cancelled() -> void:
	pass  # Silent cancel (user initiated or system event)


func _on_autopilot_cancelled_by_player() -> void:
	if _route_manager and _route_manager.is_route_active():
		_route_manager.cancel_route()
		_notif.nav.route_cancelled()


func _handle_map_toggle(view: int) -> void:
	if _screen_manager == null:
		return
	var screen: UIScreen = _screen_manager._screens.get("map")
	if screen == null:
		return
	var map_screen = screen
	if map_screen == null:
		return
	if screen in _screen_manager._screen_stack:
		if map_screen.current_view == view:
			_screen_manager.close_screen("map")
		else:
			map_screen.switch_to_view(view)
	else:
		map_screen.set_initial_view(view)
		_screen_manager.open_screen("map")


func _process(_delta: float) -> void:
	# Tick refinery queues (processes jobs in real-time)
	if _refinery_manager:
		_refinery_manager.tick()

	# Sync hangar prompt visibility with screen state
	if current_state == GameState.DOCKED and _dock_instance and _dock_instance.hangar_scene and _screen_manager:
		_dock_instance.hangar_scene.terminal_open = _screen_manager.is_any_screen_open()



# =============================================================================
# PLAYER DEATH (delegated to DeathRespawnManager)
# =============================================================================
func _on_player_destroyed() -> void:
	if current_state == GameState.DEAD:
		return
	current_state = GameState.DEAD
	if _death_respawn_mgr:
		_death_respawn_mgr.handle_player_destroyed()


func current_system_id_safe() -> int:
	if _system_transition:
		return _system_transition.current_system_id
	return 0


# =============================================================================
# DOCKING (thin relay — DockingSystem.docked fires before _docking_mgr exists at init)
# =============================================================================
func _on_docked(station_name: String) -> void:
	if current_state == GameState.DOCKED:
		return
	if _docking_mgr:
		_docking_mgr.handle_docked(station_name)


# =============================================================================
# CONSTRUCTION BEACONS
# =============================================================================
func _on_construction_marker_placed(marker: Dictionary) -> void:
	_spawn_construction_beacon(marker)


func _spawn_construction_beacon(marker: Dictionary) -> void:
	if universe_node == null:
		return
	var beacon =ConstructionBeacon.new()
	beacon.name = "ConstructionBeacon_%d" % marker["id"]
	universe_node.add_child(beacon)
	beacon.setup(marker)
	beacon.player_nearby.connect(_on_beacon_player_nearby)
	beacon.player_left.connect(_on_beacon_player_left)

	EntityRegistry.register("construction_%d" % marker["id"], {
		"name": marker["display_name"],
		"type": EntityRegistrySystem.EntityType.CONSTRUCTION_SITE,
		"node": beacon,
		"pos_x": marker["pos_x"],
		"pos_y": 0.0,
		"pos_z": marker["pos_z"],
		"radius": 10.0,
		"color": Color(1.0, 0.6, 0.1, 0.9),
	})


func _respawn_construction_beacons(system_id: int) -> void:
	if _construction_mgr == null:
		return
	var markers = _construction_mgr.get_markers_for_system(system_id)
	for marker in markers:
		_spawn_construction_beacon(marker)


func _on_beacon_player_nearby(marker_id: int, beacon_name: String) -> void:
	_build_available = true
	_build_beacon_name = beacon_name
	_build_marker_id = marker_id
	var hud = main_scene.get_node_or_null("UI/FlightHUD")
	if hud:
		hud.set_build_state(true, beacon_name)


func _on_beacon_player_left() -> void:
	_build_available = false
	_build_beacon_name = ""
	_build_marker_id = -1
	var hud = main_scene.get_node_or_null("UI/FlightHUD")
	if hud:
		hud.set_build_state(false, "")


func _on_build_requested() -> void:
	if not _build_available or _build_marker_id < 0:
		return
	if _construction_mgr == null or _construction_screen == null or _screen_manager == null:
		return

	var marker = _construction_mgr.get_marker(_build_marker_id)
	if marker.is_empty():
		return

	_construction_screen.setup(marker, player_economy)
	_screen_manager.open_screen("construction")


func _on_construction_completed(marker_id: int) -> void:
	if _construction_mgr == null or universe_node == null:
		return

	var marker = _construction_mgr.get_marker(marker_id)
	if marker.is_empty():
		return

	# Spawn station at beacon position
	var station =SpaceStation.new()
	station.station_name = marker.get("display_name", "Station")
	station.station_type = 0  # REPAIR — dockable immediately
	station.transform = Transform3D.IDENTITY
	station.position = FloatingOrigin.to_local_pos(
		[marker.get("pos_x", 0.0), 0.0, marker.get("pos_z", 0.0)])
	station.scale = Vector3(0.24, 0.24, 0.24)

	# Station equipment for persistence within session
	var sys_id: int = _system_transition.current_system_id if _system_transition else 0
	var eq_key ="system_%d_built_%d" % [sys_id, marker_id]
	station.station_equipment = StationEquipment.create_empty(eq_key, 0)
	station_equipments[eq_key] = station.station_equipment

	universe_node.add_child(station)

	# Register in EntityRegistry so DockingSystem can find it
	var station_entity_id ="built_station_%d" % marker_id
	EntityRegistry.register(station_entity_id, {
		"name": station.station_name,
		"type": EntityRegistrySystem.EntityType.STATION,
		"node": station,
		"system_id": sys_id,
		"pos_x": marker.get("pos_x", 0.0),
		"pos_z": marker.get("pos_z", 0.0),
		"station_type": 0,
	})

	# Remove beacon
	var beacon_entity_id ="construction_%d" % marker_id
	var beacon_entity =EntityRegistry.get_entity(beacon_entity_id)
	var beacon_node: Node = beacon_entity.get("node")
	if beacon_node and is_instance_valid(beacon_node):
		beacon_node.queue_free()
	EntityRegistry.unregister(beacon_entity_id)
	_construction_mgr.remove_marker(marker_id)

	# Reset build state
	_build_available = false
	_build_beacon_name = ""
	_build_marker_id = -1
	var hud = main_scene.get_node_or_null("UI/FlightHUD")
	if hud:
		hud.set_build_state(false, "")

	# Notification
	if _notif:
		_notif.toast("STATION CONSTRUITE: " + station.station_name)


func _on_station_renamed(new_name: String) -> void:
	if _dock_instance:
		_dock_instance.station_name = new_name




# Used by SaveManager.apply_state for ship change after fleet restore
func _on_ship_change_requested(fleet_index: int) -> void:
	if _ship_change_mgr:
		_ship_change_mgr.handle_ship_change(fleet_index)
