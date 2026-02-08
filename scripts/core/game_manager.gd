class_name GameManagerSystem
extends Node

# =============================================================================
# Game Manager
# Main orchestrator. Initializes systems, loads scenes, manages game state.
# Input actions are defined in code for reliability across keyboard layouts.
# =============================================================================

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
var _death_screen: Control = null
var _death_fade: float = 0.0
var _space_dust: SpaceDust = null
var _ship_net_sync: ShipNetworkSync = null
var _chat_relay: NetworkChatRelay = null
var _server_authority: ServerAuthority = null
var _remote_players: Dictionary = {}  # peer_id -> RemotePlayerShip
var player_inventory: PlayerInventory = null
var _equipment_screen: EquipmentScreen = null
var _loot_screen: LootScreen = null
var _loot_pickup: LootPickupSystem = null
var player_cargo: PlayerCargo = null
var player_economy: PlayerEconomy = null
var _lod_manager: ShipLODManager = null
var _asteroid_field_mgr: AsteroidFieldManager = null
var _mining_system: MiningSystem = null
var _backend_state_loaded: bool = false


func _ready() -> void:
	_setup_input_actions()
	await get_tree().process_frame

	# Auth token is passed by the launcher via CLI: --auth-token <jwt>
	# If present, set it and load backend state after game init.
	# If absent (dev/offline), game starts normally with default values.
	_read_auth_token_from_cli()
	_initialize_game()

	if AuthManager.is_authenticated:
		_load_backend_state()


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


func _setup_input_actions() -> void:
	# Define all input actions in code - bypasses project.godot format issues
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
		# Combat
		"target_cycle": KEY_TAB,
		"target_nearest": KEY_T,
		"target_clear": KEY_Y,
		"pip_weapons": KEY_UP,
		"pip_shields": KEY_LEFT,
		"pip_engines": KEY_RIGHT,
		"pip_reset": KEY_DOWN,
		# Docking
		"dock": KEY_F,
		# Multiplayer
		"toggle_multiplayer": KEY_P,
		# Jump gate
		"gate_jump": KEY_J,
		# Wormhole
		"wormhole_jump": KEY_W,
		# Weapon toggles
		"toggle_weapon_1": KEY_1,
		"toggle_weapon_2": KEY_2,
		"toggle_weapon_3": KEY_3,
		"toggle_weapon_4": KEY_4,
		# Mining
		"mine": KEY_B,
	}

	# Mouse button actions (separate because they use InputEventMouseButton)
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
		# Remove existing action if any (from project.godot)
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)

		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action_name]
		InputMap.action_add_event(action_name, event)



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

	# Register Clan screen
	var clan_screen := ClanScreen.new()
	clan_screen.name = "ClanScreen"
	_screen_manager.register_screen("clan", clan_screen)

	# Register Station screen
	_station_screen = StationScreen.new()
	_station_screen.name = "StationScreen"
	_station_screen.undock_requested.connect(_on_undock_requested)
	_station_screen.equipment_requested.connect(_on_equipment_requested)
	_screen_manager.register_screen("station", _station_screen)

	# Register Equipment screen
	_equipment_screen = EquipmentScreen.new()
	_equipment_screen.name = "EquipmentScreen"
	_equipment_screen.equipment_closed.connect(_on_equipment_closed)
	_screen_manager.register_screen("equipment", _equipment_screen)

	# Register Loot screen
	_loot_screen = LootScreen.new()
	_loot_screen.name = "LootScreen"
	_screen_manager.register_screen("loot", _loot_screen)

	# Register Multiplayer connection screen
	var mp_screen := MultiplayerMenuScreen.new()
	mp_screen.name = "MultiplayerMenuScreen"
	_screen_manager.register_screen("multiplayer", mp_screen)

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
	main_scene = get_tree().current_scene

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

	# Create player inventory with starting weapons
	player_inventory = PlayerInventory.new()
	player_inventory.add_weapon(&"Laser Mk1", 2)
	player_inventory.add_weapon(&"Mine Layer", 2)
	player_inventory.add_weapon(&"Laser Mk2", 1)
	player_inventory.add_weapon(&"Plasma Cannon", 1)
	player_inventory.add_weapon(&"Mining Laser Mk1", 1)
	# Starting equipment items
	player_inventory.add_shield(&"Bouclier Basique Mk2", 1)
	player_inventory.add_shield(&"Bouclier Prismatique", 1)
	player_inventory.add_engine(&"Propulseur Standard Mk2", 1)
	player_inventory.add_engine(&"Propulseur de Combat", 1)
	player_inventory.add_module(&"Condensateur d'Energie", 1)
	player_inventory.add_module(&"Dissipateur Thermique", 1)
	player_inventory.add_module(&"Amplificateur de Bouclier", 1)

	# Connect player death signal
	var player_health := player_ship.get_node_or_null("HealthSystem") as HealthSystem
	if player_health:
		player_health.ship_destroyed.connect(_on_player_destroyed)

	# Wire HUD to ship and combat systems
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as FlightHUD
	if hud:
		hud.set_ship(player_ship as ShipController)
		hud.set_health_system(player_ship.get_node_or_null("HealthSystem") as HealthSystem)
		hud.set_energy_system(player_ship.get_node_or_null("EnergySystem") as EnergySystem)
		hud.set_targeting_system(player_ship.get_node_or_null("TargetingSystem") as TargetingSystem)
		hud.set_weapon_manager(player_ship.get_node_or_null("WeaponManager") as WeaponManager)
		hud.set_player_economy(player_economy)

	# Docking system (child of player ship, scans for nearby stations)
	_docking_system = DockingSystem.new()
	_docking_system.name = "DockingSystem"
	player_ship.add_child(_docking_system)
	_docking_system.docked.connect(_on_docked)

	# Dock instance (isolated solo context manager)
	_dock_instance = DockInstance.new()
	_dock_instance.name = "DockInstance"
	add_child(_dock_instance)
	_dock_instance.ship_change_requested.connect(_on_ship_change_requested)

	# Wire docking system to HUD for dock prompt display
	if hud:
		hud.set_docking_system(_docking_system)

	# Player cargo inventory
	player_cargo = PlayerCargo.new()

	# Player economy (hardcoded starting values for testing)
	player_economy = PlayerEconomy.new()
	player_economy.add_credits(1500)
	player_economy.add_resource(&"ice", 10)
	player_economy.add_resource(&"iron", 5)

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

	# Note: system_transition wired to HUD after creation (see below)

	# Wire stellar map
	_stellar_map = main_scene.get_node_or_null("UI/StellarMap") as StellarMap

	# Generate galaxy
	_galaxy = GalaxyGenerator.generate(Constants.galaxy_seed)

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

	# Network setup
	_setup_network()

	current_state = GameState.PLAYING

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
		print("GameManager: No backend state (new player or offline)")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Save before quit
		if AuthManager.is_authenticated:
			SaveManager.trigger_save("game_closing")
			# Give a moment for the save to start
			await get_tree().create_timer(0.5).timeout
		get_tree().quit()


func _setup_visual_effects() -> void:
	# Space dust (ambient particles in Universe, follows camera)
	var camera := player_ship.get_node_or_null("ShipCamera") as Camera3D
	if camera and universe_node:
		_space_dust = SpaceDust.new()
		_space_dust.name = "SpaceDust"
		_space_dust.set_camera(camera)
		universe_node.add_child(_space_dust)


func _setup_network() -> void:
	# Ship network sync (sends local ship position to server)
	_ship_net_sync = ShipNetworkSync.new()
	_ship_net_sync.name = "ShipNetworkSync"
	player_ship.add_child(_ship_net_sync)

	# Chat relay (bridges ChatPanel <-> NetworkManager)
	_chat_relay = NetworkChatRelay.new()
	_chat_relay.name = "NetworkChatRelay"
	add_child(_chat_relay)

	# Server authority (only runs on dedicated server, self-destructs on client)
	_server_authority = ServerAuthority.new()
	_server_authority.name = "ServerAuthority"
	add_child(_server_authority)

	# Connect network signals for remote player management
	NetworkManager.peer_connected.connect(_on_network_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_network_peer_disconnected)
	NetworkManager.player_state_received.connect(_on_network_state_received)
	NetworkManager.server_config_received.connect(_on_server_config_received)

	# === AUTO-CONNECT ON LAUNCH ===
	# Server is ALWAYS a separate process (--server / --headless).
	# The game client always auto-connects to the appropriate server.
	var args := OS.get_cmdline_args()
	var port: int = Constants.NET_DEFAULT_PORT

	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = args[i + 1].to_int()
		elif args[i] == "--name" and i + 1 < args.size():
			NetworkManager.local_player_name = args[i + 1]

	if NetworkManager.is_dedicated_server:
		# --server / --headless → dedicated server process
		NetworkManager.start_dedicated_server(port)
	else:
		# Game client → auto-connect to the right server
		var server_ip: String
		if Constants.NET_IS_PRODUCTION:
			server_ip = Constants.NET_PRODUCTION_IP
		else:
			# Dev mode: check if a server is running on this machine first
			if NetworkManager.is_local_server_running(port):
				server_ip = "127.0.0.1"
				print("GameManager: Local server detected → connecting to localhost")
			else:
				server_ip = Constants.NET_PUBLIC_IP
				print("GameManager: No local server → connecting to %s" % server_ip)
		NetworkManager.connect_to_server(server_ip, port)


func _on_network_peer_connected(peer_id: int, player_name: String) -> void:
	if peer_id == NetworkManager.local_peer_id:
		return  # Don't create a puppet for ourselves

	# Spawn a remote player ship in the universe
	var remote := RemotePlayerShip.new()
	remote.peer_id = peer_id
	remote.set_player_name(player_name)
	remote.name = "RemotePlayer_%d" % peer_id
	if universe_node:
		universe_node.add_child(remote)
	_remote_players[peer_id] = remote

	# Register in LOD system
	if _lod_manager:
		var rdata := ShipLODData.new()
		rdata.id = StringName(remote.name)
		rdata.is_remote_player = true
		rdata.peer_id = peer_id
		rdata.display_name = player_name
		rdata.faction = &"neutral"
		rdata.node_ref = remote
		rdata.current_lod = ShipLODData.LODLevel.LOD0
		_lod_manager.register_ship(StringName(remote.name), rdata)

	print("GameManager: Spawned remote player '%s' (peer %d)" % [player_name, peer_id])


func _on_network_peer_disconnected(peer_id: int) -> void:
	_remove_remote_player(peer_id)


func _remove_remote_player(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		var remote: RemotePlayerShip = _remote_players[peer_id]
		if _lod_manager:
			_lod_manager.unregister_ship(StringName("RemotePlayer_%d" % peer_id))
		if is_instance_valid(remote):
			remote.queue_free()
		_remote_players.erase(peer_id)
		print("GameManager: Removed remote player (peer %d)" % peer_id)


func _on_network_state_received(peer_id: int, state: NetworkState) -> void:
	# Filter: only show players in the same star system
	var local_sys_id: int = _system_transition.current_system_id if _system_transition else -1
	if state.system_id != local_sys_id:
		# Player is in a different system — remove their puppet if it exists
		_remove_remote_player(peer_id)
		return

	if not _remote_players.has(peer_id):
		# Late arrival: create the puppet if we don't have it yet
		if NetworkManager.peers.has(peer_id):
			var pname: String = NetworkManager.peers[peer_id].player_name
			_on_network_peer_connected(peer_id, pname)

	# Update LOD data for remote player (works even if LOD2 / no node)
	if _lod_manager:
		var rid := StringName("RemotePlayer_%d" % peer_id)
		var rdata := _lod_manager.get_ship_data(rid)
		if rdata:
			rdata.position = FloatingOrigin.to_local_pos([state.pos_x, state.pos_y, state.pos_z])
			rdata.velocity = state.velocity

	if _remote_players.has(peer_id):
		var remote: RemotePlayerShip = _remote_players[peer_id]
		if is_instance_valid(remote):
			remote.receive_state(state)


func _on_server_config_received(config: Dictionary) -> void:
	var server_seed: int = config.get("galaxy_seed", Constants.galaxy_seed)
	var spawn_system: int = config.get("spawn_system_id", -1)

	# Re-generate galaxy if seed differs
	if server_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = server_seed
		_galaxy = GalaxyGenerator.generate(server_seed)
		if _system_transition:
			_system_transition.galaxy = _galaxy
		# Update map screen with new galaxy
		if _screen_manager:
			var map_screen := _screen_manager._screens.get("map") as UnifiedMapScreen
			if map_screen:
				map_screen.galaxy = _galaxy
		print("GameManager: Galaxy regenerated with seed %d from server" % server_seed)

	# Populate wormhole targets from the server's galaxy routing table
	_populate_wormhole_targets()

	# Jump to server-assigned spawn system if valid
	if spawn_system >= 0 and spawn_system < _galaxy.systems.size():
		if _system_transition and _system_transition.current_system_id != spawn_system:
			_system_transition.jump_to_system(spawn_system)
			print("GameManager: Jumped to server-assigned system %d" % spawn_system)


func _populate_wormhole_targets() -> void:
	# Fill wormhole_target dicts in galaxy systems with server routing info.
	# Each wormhole system gets a random (seeded) target from the routing table.
	if _galaxy == null or NetworkManager.galaxy_servers.is_empty():
		return
	var servers := NetworkManager.galaxy_servers
	var current_seed: int = Constants.galaxy_seed
	var target_idx: int = 0
	for sys in _galaxy.systems:
		if sys.has("wormhole_target"):
			# Find a server that is NOT the current galaxy
			var found := false
			for j in servers.size():
				var candidate: Dictionary = servers[(target_idx + j) % servers.size()]
				if candidate.get("seed", 0) != current_seed:
					sys["wormhole_target"] = {
						"seed": candidate.get("seed", 0),
						"name": candidate.get("name", "Unknown"),
						"ip": candidate.get("ip", ""),
						"port": candidate.get("port", Constants.NET_DEFAULT_PORT),
					}
					found = true
					target_idx += j + 1
					break
			if not found:
				sys["wormhole_target"] = {}  # No valid target


func _on_system_unloading(_system_id: int) -> void:
	SaveManager.trigger_save("system_jump")
	# Clear all remote player puppets — they'll be re-created when we receive
	# states in the new system (filtered by system_id).
	for pid in _remote_players.keys():
		_remove_remote_player(pid)


func _on_system_loaded(_system_id: int) -> void:
	# Update stellar map with new system info
	if _stellar_map and _system_transition.current_system_data:
		_stellar_map.set_system_name(_system_transition.current_system_data.system_name)


func _on_navigate_to_entity(entity_id: String) -> void:
	var ent: Dictionary = EntityRegistry.get_entity(entity_id)
	if ent.is_empty():
		return
	var ship := player_ship as ShipController
	if ship == null or current_state != GameState.PLAYING:
		return

	# Engage autopilot
	ship.engage_autopilot(entity_id, ent["name"])

	# Close the map
	if _screen_manager:
		_screen_manager.close_top()


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
		# Map is open
		if map_screen.current_view == view:
			# Same view key pressed again → close
			_screen_manager.close_screen("map")
		else:
			# Different view → switch
			map_screen.switch_to_view(view)
	else:
		# Map is closed → open in requested view
		map_screen.set_initial_view(view)
		_screen_manager.open_screen("map")


func _process(delta: float) -> void:
	if current_state == GameState.DEAD and _death_screen:
		_death_fade = minf(_death_fade + delta * 1.5, 1.0)
		_death_screen.modulate.a = _death_fade

	# Sync hangar prompt visibility with screen state
	if current_state == GameState.DOCKED and _dock_instance and _dock_instance.hangar_scene and _screen_manager:
		_dock_instance.hangar_scene.terminal_open = _screen_manager.is_any_screen_open()


func _input(event: InputEvent) -> void:
	# Respawn on R when dead
	if current_state == GameState.DEAD:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
			_respawn_at_nearest_repair_station()
		return

	# Map keys (M/G) always work — open/switch/close the unified map
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_M:
			_handle_map_toggle(UnifiedMapScreen.ViewMode.SYSTEM)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_G:
			_handle_map_toggle(UnifiedMapScreen.ViewMode.GALAXY)
			get_viewport().set_input_as_handled()
			return

	# Multiplayer screen (P) — toggle
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_P:
		if _screen_manager:
			var top := _screen_manager.get_top_screen()
			if top == null or top == _screen_manager._screens.get("multiplayer"):
				_screen_manager.toggle_screen("multiplayer")
				get_viewport().set_input_as_handled()
				return

	# Clan screen (N) — only when no screen is open or clan is the top screen
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_N:
		if _screen_manager:
			var top := _screen_manager.get_top_screen()
			if top == null or top == _screen_manager._screens.get("clan"):
				_screen_manager.toggle_screen("clan")
				get_viewport().set_input_as_handled()
				return

	# Only process flight inputs when no screen is open
	if _screen_manager and _screen_manager.is_any_screen_open():
		return

	# === DOCKED STATE (hangar view, no screen open) ===
	if current_state == GameState.DOCKED:
		if event.is_action_pressed("dock"):  # F → open station terminal
			_open_station_terminal()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("toggle_mouse_capture"):  # Escape → undock
			_on_undock_requested()
			get_viewport().set_input_as_handled()
			return
		return  # No other inputs in hangar view

	# === PLAYING STATE ===
	# Dock at station with F key
	if event.is_action_pressed("dock") and current_state == GameState.PLAYING:
		if _docking_system and _docking_system.can_dock:
			_docking_system.request_dock()
			get_viewport().set_input_as_handled()
			return

	# Loot pickup with X key
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_X:
		if _loot_pickup and _loot_pickup.can_pickup and current_state == GameState.PLAYING:
			var crate := _loot_pickup.request_pickup()
			if crate:
				_open_loot_screen(crate)
			get_viewport().set_input_as_handled()
			return

	# Mining with B key (hold to mine, release to stop)
	if event.is_action_pressed("mine") and current_state == GameState.PLAYING:
		if _mining_system and _mining_system.scan_target != null:
			_mining_system.start_mining()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_released("mine"):
		if _mining_system and _mining_system.is_mining:
			_mining_system.stop_mining()

	# Jump gate with J key
	if event.is_action_pressed("gate_jump") and current_state == GameState.PLAYING:
		if _system_transition and _system_transition.can_gate_jump():
			_system_transition.initiate_gate_jump(_system_transition.get_gate_target_id())
			get_viewport().set_input_as_handled()
			return

	# Wormhole with W key
	if event.is_action_pressed("wormhole_jump") and current_state == GameState.PLAYING:
		if _system_transition and _system_transition.can_wormhole_jump():
			_initiate_wormhole_jump()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("toggle_mouse_capture"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Left click recaptures mouse when released
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# =============================================================================
# PLAYER DEATH
# =============================================================================
func _on_player_destroyed() -> void:
	if current_state == GameState.DEAD:
		return
	current_state = GameState.DEAD
	SaveManager.trigger_save("player_death")

	# Big explosion at player position
	_spawn_death_explosion()

	# Disable player controls & hide ship
	var ship := player_ship as ShipController
	if ship:
		ship.is_player_controlled = false
		ship.throttle_input = Vector3.ZERO
		ship.set_rotation_target(0, 0, 0)
		ship.freeze = true
		var model := ship.get_node_or_null("ShipModel") as Node3D
		if model:
			model.visible = false
		# Disable collision so projectiles pass through the wreck
		ship.collision_layer = 0
		ship.collision_mask = 0

	# Hide flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = false

	# Show death screen with fade-in
	_death_fade = 0.0
	_create_death_screen()


func _spawn_death_explosion() -> void:
	if player_ship == null:
		return
	var pos: Vector3 = player_ship.global_position
	var scene_root := get_tree().current_scene

	# Main explosion (big)
	var main_exp := ExplosionEffect.new()
	scene_root.add_child(main_exp)
	main_exp.global_position = pos
	main_exp.scale = Vector3.ONE * 4.0

	# Secondary explosions with slight delays and offsets
	for i in 5:
		var timer := get_tree().create_timer(0.15 * (i + 1))
		var offset := Vector3(
			randf_range(-15.0, 15.0),
			randf_range(-10.0, 10.0),
			randf_range(-15.0, 15.0)
		)
		var scale_mult: float = randf_range(1.5, 3.0)
		timer.timeout.connect(_spawn_delayed_explosion.bind(pos + offset, scale_mult))


func _spawn_delayed_explosion(pos: Vector3, scale_mult: float) -> void:
	var explosion := ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * scale_mult


func _create_death_screen() -> void:
	_death_screen = Control.new()
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.modulate.a = 0.0

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.02, 0.7)
	_death_screen.add_child(overlay)

	# "VAISSEAU DÉTRUIT" title
	var title := Label.new()
	title.text = "VAISSEAU DÉTRUIT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -60
	title.offset_bottom = 0
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1, 1.0))
	_death_screen.add_child(title)

	# Restart prompt
	var prompt := Label.new()
	prompt.text = "Appuyez sur [R] pour respawn à la station de réparation"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 20
	prompt.offset_bottom = 60
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85, 0.8))
	_death_screen.add_child(prompt)

	var ui_layer := main_scene.get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_death_screen)
	else:
		main_scene.add_child(_death_screen)


# =============================================================================
# RESPAWN
# =============================================================================
func _respawn_at_nearest_repair_station() -> void:
	if current_state != GameState.DEAD:
		return

	# Find target system via BFS
	var target_sys: int = current_system_id_safe()
	if _galaxy:
		target_sys = _galaxy.find_nearest_repair_system(target_sys)

	# Remove death screen
	if _death_screen and is_instance_valid(_death_screen):
		_death_screen.queue_free()
		_death_screen = null

	# Restore player ship
	_repair_ship()

	# Jump to target system (or reposition if same system)
	if _system_transition and target_sys != _system_transition.current_system_id:
		_system_transition.jump_to_system(target_sys)
	elif _system_transition:
		_system_transition._position_player()

	# Restore HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_state = GameState.PLAYING
	SaveManager.trigger_save("respawned")


func _repair_ship() -> void:
	var ship := player_ship as ShipController
	if ship == null:
		return

	# Unfreeze and show
	ship.freeze = false
	ship.is_player_controlled = true
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.collision_layer = Constants.LAYER_SHIPS
	ship.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_PROJECTILES

	var model := ship.get_node_or_null("ShipModel") as Node3D
	if model:
		model.visible = true

	# Repair hull and shields
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.hull_current = health.hull_max
		for i in health.shield_current.size():
			health.shield_current[i] = health.shield_max_per_facing


func current_system_id_safe() -> int:
	if _system_transition:
		return _system_transition.current_system_id
	return 0


# =============================================================================
# WORMHOLE INTER-GALAXY JUMP
# =============================================================================
func _initiate_wormhole_jump() -> void:
	var wormhole := _system_transition.get_active_wormhole()
	if wormhole == null:
		return

	var target_seed: int = wormhole.target_galaxy_seed
	var target_ip: String = wormhole.target_server_ip
	var target_port: int = wormhole.target_server_port

	if target_ip.is_empty():
		print("GameManager: Wormhole has no target server configured")
		return

	# 1. Start fade out
	if _system_transition._transition_overlay:
		_system_transition._transition_overlay.visible = true
		_system_transition._transition_overlay.modulate.a = 0.0
	_system_transition._is_transitioning = true
	_system_transition._transition_phase = 1
	_system_transition._transition_alpha = 0.0
	_system_transition._transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_system_transition.transition_started.emit()

	# Wait for fade to complete
	await _system_transition.transition_finished
	# At this point transition_finished won't fire since we'll break the chain.
	# Instead, use a timer to wait for fade-out.
	await get_tree().create_timer(0.6).timeout

	# 2. Save state before disconnecting (critical)
	await SaveManager.save_player_state(true)

	# 3. Disconnect from current server
	NetworkManager.disconnect_from_server()

	# 3. Switch galaxy
	Constants.galaxy_seed = target_seed
	_galaxy = GalaxyGenerator.generate(target_seed)
	if _system_transition:
		_system_transition.galaxy = _galaxy

	# Update map
	if _screen_manager:
		var map_screen := _screen_manager._screens.get("map") as UnifiedMapScreen
		if map_screen:
			map_screen.galaxy = _galaxy

	# 4. Connect to new server
	NetworkManager.connect_to_server(target_ip, target_port)

	# 5. Wait for connection + config
	var connected: bool = false
	var config_received: bool = false
	var timeout: float = 10.0

	var on_connected := func():
		connected = true
	var on_config := func(_cfg: Dictionary):
		config_received = true

	NetworkManager.connection_succeeded.connect(on_connected, CONNECT_ONE_SHOT)
	NetworkManager.server_config_received.connect(on_config, CONNECT_ONE_SHOT)

	while not (connected and config_received) and timeout > 0:
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1

	# 6. Jump to spawn system in new galaxy
	var spawn_sys: int = _galaxy.player_home_system
	_system_transition.jump_to_system(spawn_sys)

	# 7. Fade in
	_system_transition._transition_phase = 3
	_system_transition._transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("GameManager: Wormhole jump complete — galaxy seed %d, system %d" % [target_seed, spawn_sys])


# =============================================================================
# DOCKING
# =============================================================================
func _on_docked(station_name: String) -> void:
	if current_state == GameState.DOCKED:
		return
	current_state = GameState.DOCKED
	SaveManager.trigger_save("docked")

	# Stop ship controls + autopilot
	var ship := player_ship as ShipController
	if ship:
		ship.disengage_autopilot()
		ship.is_player_controlled = false
		ship.throttle_input = Vector3.ZERO
		ship.set_rotation_target(0, 0, 0)
		ship.linear_velocity = Vector3.ZERO
		ship.angular_velocity = Vector3.ZERO

	# Force NPCs to drop player as target before freezing world
	_clear_npc_targets_on_player()

	# Enter isolated solo instance (freezes world, loads hangar, repairs ship)
	_dock_instance.enter(_build_dock_context(station_name))

	# Hide flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = false

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_equipment_closed() -> void:
	# Return to station terminal after closing equipment screen
	if current_state == GameState.DOCKED:
		_open_station_terminal()


func _on_equipment_requested() -> void:
	if _equipment_screen and _screen_manager:
		_equipment_screen.player_inventory = player_inventory
		var wm := player_ship.get_node_or_null("WeaponManager") as WeaponManager
		_equipment_screen.weapon_manager = wm
		var em := player_ship.get_node_or_null("EquipmentManager") as EquipmentManager
		_equipment_screen.equipment_manager = em
		# Pass ship model info for the 3D viewer
		var ship_model := player_ship.get_node_or_null("ShipModel") as ShipModel
		var ship_ctrl := player_ship as ShipController
		var center_off := ship_ctrl.center_offset if ship_ctrl else Vector3.ZERO
		if ship_model:
			_equipment_screen.setup_ship_viewer(ship_model.model_path, ship_model.model_scale, center_off)
		# Close station screen first, then open equipment
		_screen_manager.close_screen("station")
		# Small delay to let close transition start, then open equipment
		await get_tree().process_frame
		_screen_manager.open_screen("equipment")


func _open_station_terminal() -> void:
	if _station_screen:
		_station_screen.set_station_name(_dock_instance.station_name if _dock_instance else "")
	if _screen_manager:
		_screen_manager.open_screen("station")


func _open_loot_screen(crate: CargoCrate) -> void:
	if _loot_screen == null or _screen_manager == null:
		return
	_loot_screen.set_contents(crate.contents)
	# Disconnect previous if any
	if _loot_screen.loot_collected.is_connected(_on_loot_collected):
		_loot_screen.loot_collected.disconnect(_on_loot_collected)
	_loot_screen.loot_collected.connect(_on_loot_collected.bind(crate), CONNECT_ONE_SHOT)
	_screen_manager.open_screen("loot")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_loot_collected(selected_items: Array[Dictionary], crate: CargoCrate) -> void:
	# Extract credits and economy resources; rest goes to cargo
	var cargo_items: Array[Dictionary] = []
	for item in selected_items:
		var item_type: String = item.get("type", "")
		var qty: int = item.get("quantity", 1)
		if item_type == "credits" and player_economy:
			player_economy.add_credits(qty)
		elif player_economy:
			# Map loot types to economy resource ids
			var res_id: StringName = _loot_type_to_resource(item_type)
			if res_id != &"" and PlayerEconomy.RESOURCE_DEFS.has(res_id):
				player_economy.add_resource(res_id, qty)
			else:
				cargo_items.append(item)
		else:
			cargo_items.append(item)
	if player_cargo and not cargo_items.is_empty():
		player_cargo.add_items(cargo_items)
	# Destroy the crate
	if crate and is_instance_valid(crate):
		crate._destroy()
	# Mark dirty for periodic save (loot collected)
	SaveManager.mark_dirty()
	# Re-capture mouse for flight
	if current_state == GameState.PLAYING:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


static func _loot_type_to_resource(loot_type: String) -> StringName:
	match loot_type:
		"water": return &"ice"
		"iron": return &"iron"
	return &""


func _on_undock_requested() -> void:
	if current_state != GameState.DOCKED:
		return

	# Close station UI
	if _screen_manager:
		_screen_manager.close_screen("station")

	# Leave isolated solo instance (restores world, removes hangar, restores combat)
	_dock_instance.leave(_build_dock_context(""))

	# Re-enable ship controls
	var ship := player_ship as ShipController
	if ship:
		ship.is_player_controlled = true

	# Show flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	# Undock from docking system
	if _docking_system:
		_docking_system.request_undock()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_state = GameState.PLAYING
	SaveManager.trigger_save("undocked")


# =============================================================================
# DOCKING HELPERS
# =============================================================================
func _clear_npc_targets_on_player() -> void:
	# Force all NPCs to drop the player as their current target
	for npc in get_tree().get_nodes_in_group("ships"):
		if npc == player_ship:
			continue
		var targeting := npc.get_node_or_null("TargetingSystem") as TargetingSystem
		if targeting and targeting.current_target == player_ship:
			targeting.clear_target()
		var brain := npc.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.target = null


func _build_dock_context(station_name: String) -> Dictionary:
	return {
		"station_name": station_name,
		"player_ship": player_ship,
		"universe_node": universe_node,
		"main_scene": main_scene,
		"lod_manager": _lod_manager,
		"encounter_manager": _encounter_manager,
		"net_sync": _ship_net_sync,
	}


func _on_ship_change_requested(ship_id: StringName) -> void:
	if current_state != GameState.DOCKED or player_ship == null:
		return

	var data := ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("GameManager: Unknown ship_id '%s' for ship change" % ship_id)
		return

	var ship := player_ship as ShipController

	# Strip old combat components
	for comp_name in ["HealthSystem", "EnergySystem", "WeaponManager", "TargetingSystem", "EquipmentManager"]:
		var comp := ship.get_node_or_null(comp_name)
		if comp:
			ship.remove_child(comp)
			comp.free()

	# Strip old ShipModel and CollisionShape3D (ShipFactory replaces them)
	var old_model := ship.get_node_or_null("ShipModel")
	if old_model:
		ship.remove_child(old_model)
		old_model.free()
	var old_col := ship.get_node_or_null("CollisionShape3D")
	if old_col:
		ship.remove_child(old_col)
		old_col.free()

	# Rebuild with new ship
	ShipFactory.setup_player_ship(ship_id, ship)

	# Repair the new ship (full hull + shields)
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.hull_current = health.hull_max
		for i in health.shield_current.size():
			health.shield_current[i] = health.shield_max_per_facing

	# Rewire HUD to new combat systems
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as FlightHUD
	if hud:
		hud.set_ship(ship)
		hud.set_health_system(ship.get_node_or_null("HealthSystem") as HealthSystem)
		hud.set_energy_system(ship.get_node_or_null("EnergySystem") as EnergySystem)
		hud.set_targeting_system(ship.get_node_or_null("TargetingSystem") as TargetingSystem)
		hud.set_weapon_manager(ship.get_node_or_null("WeaponManager") as WeaponManager)

	# Reconnect player death signal
	if health:
		if not health.ship_destroyed.is_connected(_on_player_destroyed):
			health.ship_destroyed.connect(_on_player_destroyed)

	# Update LOD player data
	if _lod_manager:
		var player_lod := _lod_manager.get_ship_data(&"player_ship")
		if player_lod:
			player_lod.ship_id = data.ship_id
			player_lod.ship_class = data.ship_class

	SaveManager.trigger_save("ship_changed")
	print("GameManager: Ship changed to '%s' (%s)" % [data.ship_name, ship_id])
