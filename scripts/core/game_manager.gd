class_name GameManagerSystem
extends Node

# =============================================================================
# Game Manager
# Main orchestrator. Initializes systems, loads scenes, manages game state.
# Input actions are defined in code for reliability across keyboard layouts.
# =============================================================================

## Emitted after ShipFactory rebuilds the player ship (init + ship change).
## Systems (HUD, MiningSystem, ShipNetworkSync) connect to self-rewire.
signal player_ship_rebuilt(ship: ShipController)

enum GameState { LOADING, PLAYING, PAUSED, MENU, DEAD, DOCKED }

var current_state: GameState = GameState.LOADING
var player_ship: RigidBody3D = null
var universe_node: Node3D = null
var main_scene: Node3D = null
var _music_player: AudioStreamPlayer = null
var _stellar_map: StellarMap = null
var _screen_manager: UIScreenManager = null
var _tooltip_manager: UITooltipManager = null
var _toast_manager: UIToastManager = null
var _encounter_manager: EncounterManager = null
var _clan_manager: ClanManager = null
var _docking_system: DockingSystem = null
var _station_screen: StationScreen = null
var _dock_instance: DockInstance = null
var _system_transition: SystemTransition = null
var _galaxy: GalaxyData = null
var _death_respawn_mgr: DeathRespawnManager = null
var _docking_mgr: DockingManager = null
var _loot_mgr: LootManager = null
var _input_router: InputRouter = null
var _ship_change_mgr: ShipChangeManager = null
var _wormhole_mgr: WormholeManager = null
var _net_sync_mgr: NetworkSyncManager = null
var _discord_rpc: DiscordRPC:
	get: return _net_sync_mgr.discord_rpc if _net_sync_mgr else null
var _npc_authority: NpcAuthority:
	get: return _net_sync_mgr.npc_authority if _net_sync_mgr else null
var _ship_net_sync: ShipNetworkSync:
	get: return _net_sync_mgr.ship_net_sync if _net_sync_mgr else null
var _remote_players: Dictionary:
	get: return _net_sync_mgr.remote_players if _net_sync_mgr else {}
var _remote_npcs: Dictionary:
	get: return _net_sync_mgr.remote_npcs if _net_sync_mgr else {}
var _space_dust: SpaceDust = null
var player_data: PlayerData = null
var player_inventory: PlayerInventory:
	get: return player_data.inventory if player_data else null
var player_cargo: PlayerCargo:
	get: return player_data.cargo if player_data else null
var player_economy: PlayerEconomy:
	get: return player_data.economy if player_data else null
var player_fleet: PlayerFleet:
	get: return player_data.fleet if player_data else null
	set(value):
		if player_data:
			player_data.fleet = value
var station_services: StationServices:
	get: return player_data.station_services if player_data else null
	set(value):
		if player_data:
			player_data.station_services = value
var _equipment_screen: EquipmentScreen = null
var _loot_screen: LootScreen = null
var _loot_pickup: LootPickupSystem = null
var _lod_manager: ShipLODManager = null
var _asteroid_field_mgr: AsteroidFieldManager = null
var _mining_system: MiningSystem = null
var _commerce_screen: CommerceScreen = null
var _commerce_manager: CommerceManager = null
var _route_manager: RouteManager = null
var _fleet_deployment_mgr: FleetDeploymentManager = null
var _backend_state_loaded: bool = false
var _bug_report_screen: BugReportScreen = null
var _fleet_panel: FleetManagementPanel = null


func _ready() -> void:
	await get_tree().process_frame

	# Auth token is passed by the launcher via CLI: --auth-token <jwt>
	# Authentication is REQUIRED — the launcher handles login/register.
	_read_auth_token_from_cli()
	_initialize_game()

	if AuthManager.is_authenticated:
		_load_backend_state()
	else:
		push_warning("GameManager: No auth token — backend features disabled. Use the launcher to play.")


func _read_auth_token_from_cli() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--auth-token" and i + 1 < args.size():
			var token: String = args[i + 1]
			AuthManager.set_token_from_launcher(token)
			print("GameManager: Auth token received from launcher")
			return
	# No token — try restoring from saved session (auto-refresh)
	# AuthManager._try_restore_session() is already called in its _ready()


func _setup_ui_managers() -> void:
	var ui_layer := main_scene.get_node_or_null("UI")
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
		var map_screen := UnifiedMapScreen.new()
		map_screen.name = "UnifiedMapScreen"
		map_screen.stellar_map = _stellar_map
		map_screen.galaxy = _galaxy
		map_screen.system_transition = _system_transition
		_stellar_map.view_switch_requested.connect(func(): map_screen.switch_to_view(UnifiedMapScreen.ViewMode.GALAXY))
		_stellar_map.navigate_to_requested.connect(_on_navigate_to_entity)
		_screen_manager.register_screen("map", map_screen)

		# Pass fleet data to both map panels
		if player_fleet and _galaxy:
			_stellar_map.set_fleet(player_fleet, _galaxy)
			map_screen.set_fleet(player_fleet, _galaxy)

		# Connect fleet deploy/retrieve signals from stellar map
		_stellar_map.fleet_deploy_requested.connect(_on_fleet_deploy_from_map)
		_stellar_map.fleet_retrieve_requested.connect(_on_fleet_retrieve_from_map)
		_stellar_map.fleet_command_change_requested.connect(_on_fleet_command_change_from_map)

	# Register Fleet Management Panel (kept for backwards compatibility)
	_fleet_panel = FleetManagementPanel.new()
	_fleet_panel.name = "FleetManagementPanel"
	_screen_manager.register_screen("fleet", _fleet_panel)

	# Connect station long press from stellar map (opens station detail in-map)
	if _stellar_map:
		_stellar_map.station_long_pressed.connect(_on_station_long_pressed)

	# Register Clan screen
	var clan_screen := ClanScreen.new()
	clan_screen.name = "ClanScreen"
	_screen_manager.register_screen("clan", clan_screen)

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

	# Register Loot screen
	_loot_screen = LootScreen.new()
	_loot_screen.name = "LootScreen"
	_screen_manager.register_screen("loot", _loot_screen)

	# Register Multiplayer connection screen
	var mp_screen := MultiplayerMenuScreen.new()
	mp_screen.name = "MultiplayerMenuScreen"
	_screen_manager.register_screen("multiplayer", mp_screen)

	# Register Bug Report screen (F12)
	_bug_report_screen = BugReportScreen.new()
	_bug_report_screen.name = "BugReportScreen"
	_screen_manager.register_screen("bug_report", _bug_report_screen)

	# Tooltip manager
	_tooltip_manager = UITooltipManager.new()
	_tooltip_manager.name = "UITooltipManager"
	ui_layer.add_child(_tooltip_manager)

	# Toast manager
	_toast_manager = UIToastManager.new()
	_toast_manager.name = "UIToastManager"
	ui_layer.add_child(_toast_manager)

	# Transition overlay (on top of everything)
	if _system_transition:
		var overlay := _system_transition.get_transition_overlay()
		if overlay:
			ui_layer.add_child(overlay)


func _initialize_game() -> void:
	var scene := get_tree().current_scene
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
	ShipFactory.setup_player_ship(&"fighter_mk1", player_ship as ShipController)

	# Generate galaxy (needed before PlayerData.initialize)
	_galaxy = GalaxyGenerator.generate(Constants.galaxy_seed)

	# Player data facade (economy, inventory, cargo, fleet, station services)
	player_data = PlayerData.new()
	player_data.initialize(_galaxy)

	# Equip starting loadout from fleet data
	var starting_fleet_ship := player_data.get_starting_fleet_ship()
	if starting_fleet_ship:
		var start_wm := player_ship.get_node_or_null("WeaponManager") as WeaponManager
		if start_wm:
			start_wm.equip_weapons(starting_fleet_ship.weapons)
		var start_em := player_ship.get_node_or_null("EquipmentManager") as EquipmentManager
		if start_em:
			if starting_fleet_ship.shield_name != &"":
				var shield_res := ShieldRegistry.get_shield(starting_fleet_ship.shield_name)
				if shield_res:
					start_em.equip_shield(shield_res)
			if starting_fleet_ship.engine_name != &"":
				var engine_res := EngineRegistry.get_engine(starting_fleet_ship.engine_name)
				if engine_res:
					start_em.equip_engine(engine_res)
			for i in starting_fleet_ship.modules.size():
				if starting_fleet_ship.modules[i] != &"":
					var mod_res := ModuleRegistry.get_module(starting_fleet_ship.modules[i])
					if mod_res:
						start_em.equip_module(i, mod_res)
	NetworkManager.local_ship_id = &"fighter_mk1"

	# Docking system (child of player ship, scans for nearby stations)
	_docking_system = DockingSystem.new()
	_docking_system.name = "DockingSystem"
	player_ship.add_child(_docking_system)
	_docking_system.docked.connect(_on_docked)

	# Dock instance (isolated solo context manager)
	_dock_instance = DockInstance.new()
	_dock_instance.name = "DockInstance"
	add_child(_dock_instance)
	# ship_change_requested connected after _ship_change_mgr creation (see below)

	# Wire docking system to HUD for dock prompt display
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as FlightHUD
	if hud:
		hud.set_docking_system(_docking_system)

	# Fleet Deployment Manager
	_fleet_deployment_mgr = FleetDeploymentManager.new()
	_fleet_deployment_mgr.name = "FleetDeploymentManager"
	add_child(_fleet_deployment_mgr)
	_fleet_deployment_mgr.initialize(player_fleet)

	# Commerce manager
	_commerce_manager = CommerceManager.new()
	_commerce_manager.player_economy = player_economy
	_commerce_manager.player_inventory = player_inventory
	_commerce_manager.player_fleet = player_fleet

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
	_ship_change_mgr.get_game_state = func() -> GameState: return current_state
	_ship_change_mgr._on_destroyed_callback = _on_player_destroyed
	_ship_change_mgr._on_autopilot_cancelled_callback = _on_autopilot_cancelled_by_player
	_ship_change_mgr.ship_rebuilt.connect(func(ship: ShipController): player_ship_rebuilt.emit(ship))
	add_child(_ship_change_mgr)
	_dock_instance.ship_change_requested.connect(_ship_change_mgr.handle_ship_change)

	# Wire all ship-dependent systems (signals, HUD, mining, LOD, network)
	_ship_change_mgr.rewire_ship_systems()

	# Wire stellar map
	_stellar_map = main_scene.get_node_or_null("UI/StellarMap") as StellarMap

	# Create system transition manager
	_system_transition = SystemTransition.new()
	_system_transition.name = "SystemTransition"
	_system_transition.galaxy = _galaxy
	add_child(_system_transition)
	_system_transition.system_loaded.connect(_on_system_loaded)
	_system_transition.system_unloading.connect(_on_system_unloading)

	# Wire system transition to HUD for gate prompt display
	var hud_ref := main_scene.get_node_or_null("UI/FlightHUD") as FlightHUD
	if hud_ref:
		hud_ref.set_system_transition(_system_transition)

	# Ship LOD Manager (must exist before encounter manager spawns ships)
	_lod_manager = ShipLODManager.new()
	_lod_manager.name = "ShipLODManager"
	add_child(_lod_manager)
	_lod_manager.initialize(universe_node)

	# Register player ship in LOD system (always LOD0)
	var player_lod := ShipLODData.new()
	player_lod.id = &"player_ship"
	player_lod.ship_id = &"frigate_mk1"
	player_lod.ship_class = &"Frigate"
	player_lod.faction = &"neutral"
	player_lod.display_name = "Player"
	player_lod.node_ref = player_ship
	player_lod.current_lod = ShipLODData.LODLevel.LOD0
	player_lod.position = player_ship.global_position
	_lod_manager.register_ship(&"player_ship", player_lod)
	_lod_manager.set_player_id(&"player_ship")

	# Create projectile pool under LOD manager
	var proj_pool := ProjectilePool.new()
	proj_pool.name = "ProjectilePool"
	_lod_manager.add_child(proj_pool)
	# Pre-warm pools for all projectile types to avoid runtime instantiation
	proj_pool.warm_pool("res://scenes/weapons/laser_bolt.tscn", 150)
	proj_pool.warm_pool("res://scenes/weapons/plasma_bolt.tscn", 80)
	proj_pool.warm_pool("res://scenes/weapons/missile.tscn", 40)
	proj_pool.warm_pool("res://scenes/weapons/railgun_slug.tscn", 30)

	# Asteroid Field Manager (must exist before system loading)
	_asteroid_field_mgr = AsteroidFieldManager.new()
	_asteroid_field_mgr.name = "AsteroidFieldManager"
	add_child(_asteroid_field_mgr)
	_asteroid_field_mgr.initialize(universe_node)

	# Wire mining system to asteroid field manager
	if _mining_system:
		_mining_system.set_asteroid_manager(_asteroid_field_mgr)

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

	# Clan Manager
	_clan_manager = ClanManager.new()
	_clan_manager.name = "ClanManager"
	add_child(_clan_manager)

	# Setup UI framework managers (needs _galaxy and _system_transition)
	_setup_ui_managers()

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
	_wormhole_mgr.wormhole_jump_completed.connect(func(new_gal: GalaxyData, _spawn: int):
		_galaxy = new_gal
	)

	# Input Router
	_input_router = InputRouter.new()
	_input_router.name = "InputRouter"
	_input_router.screen_manager = _screen_manager
	_input_router.docking_system = _docking_system
	_input_router.loot_pickup = _loot_pickup
	_input_router.system_transition = _system_transition
	_input_router.get_game_state = func() -> GameState: return current_state
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

	# Background music
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = load("res://assets/audio/game_background_music.mp3")
	_music_player.volume_db = -35.0
	_music_player.bus = "Master"
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
	_net_sync_mgr.server_galaxy_changed.connect(func(new_gal: GalaxyData):
		_galaxy = new_gal
	)
	# Now that network is set up, inject ship_net_sync into ShipChangeManager + LOD
	if _ship_change_mgr:
		_ship_change_mgr.ship_net_sync = _net_sync_mgr.ship_net_sync
		_ship_change_mgr.lod_manager = _lod_manager

	# Docking Manager (needs screen_manager, station_screen, etc. from _setup_ui_managers)
	_docking_mgr = DockingManager.new()
	_docking_mgr.name = "DockingManager"
	_docking_mgr.player_ship = player_ship
	_docking_mgr.main_scene = main_scene
	_docking_mgr.docking_system = _docking_system
	_docking_mgr.dock_instance = _dock_instance
	_docking_mgr.screen_manager = _screen_manager
	_docking_mgr.toast_manager = _toast_manager
	_docking_mgr.player_data = player_data
	_docking_mgr.commerce_manager = _commerce_manager
	_docking_mgr.commerce_screen = _commerce_screen
	_docking_mgr.equipment_screen = _equipment_screen
	_docking_mgr.station_screen = _station_screen
	_docking_mgr.system_transition = _system_transition
	_docking_mgr.route_manager = _route_manager
	_docking_mgr.fleet_deployment_mgr = _fleet_deployment_mgr
	_docking_mgr.lod_manager = _lod_manager
	_docking_mgr.encounter_manager = _encounter_manager
	_docking_mgr.ship_net_sync = _net_sync_mgr.ship_net_sync if _net_sync_mgr else null
	_docking_mgr.discord_rpc = _net_sync_mgr.discord_rpc if _net_sync_mgr else null
	_docking_mgr.get_game_state = func() -> GameState: return current_state
	add_child(_docking_mgr)
	# Connect station/commerce/equipment screen signals directly to DockingManager
	_station_screen.undock_requested.connect(_docking_mgr.handle_undock)
	_station_screen.equipment_requested.connect(_docking_mgr.handle_equipment_requested)
	_station_screen.commerce_requested.connect(_docking_mgr.handle_commerce_requested)
	_station_screen.repair_requested.connect(_docking_mgr.handle_repair_requested)
	_commerce_screen.commerce_closed.connect(_docking_mgr.handle_commerce_closed)
	_equipment_screen.equipment_closed.connect(_docking_mgr.handle_equipment_closed)
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
		SaveManager.trigger_save("undocked")
	)

	# Loot Manager
	_loot_mgr = LootManager.new()
	_loot_mgr.name = "LootManager"
	_loot_mgr.player_data = player_data
	_loot_mgr.screen_manager = _screen_manager
	_loot_mgr.loot_screen = _loot_screen
	_loot_mgr.toast_manager = _toast_manager
	_loot_mgr.get_game_state = func() -> GameState: return current_state
	add_child(_loot_mgr)

	# Deferred InputRouter connections (need _docking_mgr + _loot_mgr)
	_input_router.terminal_requested.connect(_docking_mgr.open_station_terminal)
	_input_router.undock_requested.connect(_docking_mgr.handle_undock)
	_input_router.loot_pickup_requested.connect(_loot_mgr.open_loot_screen)

	current_state = GameState.PLAYING
	if _discord_rpc:
		_discord_rpc.update_from_game_state(current_state)

	# Start auto-save timer
	SaveManager.start_auto_save()


func _load_backend_state() -> void:
	if not AuthManager.is_authenticated:
		return
	var state: Dictionary = await SaveManager.load_player_state()
	if not state.is_empty() and not state.has("error"):
		SaveManager.apply_state(state)
		_backend_state_loaded = true
		print("GameManager: Backend state loaded and applied")
	else:
		print("GameManager: No backend state (new player)")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Save before quit (no await — _notification must not be a coroutine)
		if AuthManager.is_authenticated:
			SaveManager.trigger_save("game_closing")
		# Quit is deferred so the save request has time to start
		get_tree().quit.call_deferred()


func _setup_visual_effects() -> void:
	# Space dust (ambient particles in Universe, follows camera)
	var camera := player_ship.get_node_or_null("ShipCamera") as Camera3D
	if camera and universe_node:
		_space_dust = SpaceDust.new()
		_space_dust.name = "SpaceDust"
		_space_dust.set_camera(camera)
		universe_node.add_child(_space_dust)


func _on_system_unloading(system_id: int) -> void:
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.auto_retrieve_all()
	SaveManager.trigger_save("system_jump")
	if _net_sync_mgr:
		_net_sync_mgr.on_system_unloading(system_id)


func _on_system_loaded(system_id: int) -> void:
	# Update stellar map with new system info
	if _stellar_map and _system_transition.current_system_data:
		_stellar_map.set_system_name(_system_transition.current_system_data.system_name)

	# Update Discord RPC with current system name
	if _discord_rpc and _system_transition.current_system_data:
		_discord_rpc.set_system(_system_transition.current_system_data.system_name)

	# Notify route manager (continues multi-system autopilot)
	if _route_manager:
		_route_manager.on_system_loaded(system_id)

	# Redeploy fleet ships that were deployed in this system (from save)
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.redeploy_saved_ships()


func _on_station_long_pressed(station_id: String) -> void:
	# Open station detail directly in the map (no screen switch)
	if _stellar_map == null or player_fleet == null:
		return
	_stellar_map._open_station_detail(station_id)


func _on_fleet_deploy_from_map(fleet_index: int, command: StringName, params: Dictionary) -> void:
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.request_deploy(fleet_index, command, params)


func _on_fleet_retrieve_from_map(fleet_index: int) -> void:
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.request_retrieve(fleet_index)


func _on_fleet_command_change_from_map(fleet_index: int, command: StringName, params: Dictionary) -> void:
	if _fleet_deployment_mgr:
		_fleet_deployment_mgr.request_change_command(fleet_index, command, params)


func _on_navigate_to_entity(entity_id: String) -> void:
	var ent: Dictionary = EntityRegistry.get_entity(entity_id)
	if ent.is_empty():
		return
	var ship := player_ship as ShipController
	if ship == null or current_state != GameState.PLAYING:
		return

	# Manual navigation cancels any active route
	if _route_manager and _route_manager.is_route_active():
		_route_manager.cancel_route()

	# Engage autopilot
	ship.engage_autopilot(entity_id, ent["name"])

	# Close the map
	if _screen_manager:
		_screen_manager.close_top()


# =============================================================================
# GALAXY ROUTE (multi-system autopilot)
# =============================================================================
func start_galaxy_route(target_sys_id: int) -> void:
	if _route_manager == null or _system_transition == null or _galaxy == null:
		return

	var current_sys: int = _system_transition.current_system_id
	if current_sys == target_sys_id:
		if _toast_manager:
			_toast_manager.show_toast("DEJA SUR PLACE")
		return

	var success: bool = _route_manager.start_route(current_sys, target_sys_id)
	if not success:
		if _toast_manager:
			_toast_manager.show_toast("AUCUNE ROUTE TROUVEE")
		return

	var sys_name: String = _galaxy.get_system_name(target_sys_id)
	var jumps: int = _route_manager.get_jumps_total()
	if _toast_manager:
		_toast_manager.show_toast("ROUTE VERS %s — %d saut%s" % [sys_name, jumps, "s" if jumps > 1 else ""])


func _on_route_completed() -> void:
	if _toast_manager:
		_toast_manager.show_toast("DESTINATION ATTEINTE")


func _on_route_cancelled() -> void:
	pass  # Silent cancel (user initiated or system event)


func _on_autopilot_cancelled_by_player() -> void:
	if _route_manager and _route_manager.is_route_active():
		_route_manager.cancel_route()
		if _toast_manager:
			_toast_manager.show_toast("ROUTE ANNULEE")


func _handle_map_toggle(view: int) -> void:
	if _screen_manager == null:
		return
	var screen: UIScreen = _screen_manager._screens.get("map")
	if screen == null:
		return
	var map_screen := screen as UnifiedMapScreen
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


# Used by SaveManager.apply_state for ship change after fleet restore
func _on_ship_change_requested(fleet_index: int) -> void:
	if _ship_change_mgr:
		_ship_change_mgr.handle_ship_change(fleet_index)
