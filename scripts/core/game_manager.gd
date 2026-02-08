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
var _lod_manager: ShipLODManager = null


func _ready() -> void:
	_setup_input_actions()
	await get_tree().process_frame
	_initialize_game()


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
		# Weapon toggles
		"toggle_weapon_1": KEY_1,
		"toggle_weapon_2": KEY_2,
		"toggle_weapon_3": KEY_3,
		"toggle_weapon_4": KEY_4,
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
	ShipFactory.setup_player_ship(&"frigate_mk1", player_ship as ShipController)

	# Create player inventory with starting weapons
	player_inventory = PlayerInventory.new()
	player_inventory.add_weapon(&"Laser Mk1", 2)
	player_inventory.add_weapon(&"Mine Layer", 2)
	player_inventory.add_weapon(&"Laser Mk2", 1)
	player_inventory.add_weapon(&"Plasma Cannon", 1)
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

	# Docking system (child of player ship, scans for nearby stations)
	_docking_system = DockingSystem.new()
	_docking_system.name = "DockingSystem"
	player_ship.add_child(_docking_system)
	_docking_system.docked.connect(_on_docked)

	# Dock instance (isolated solo context manager)
	_dock_instance = DockInstance.new()
	_dock_instance.name = "DockInstance"
	add_child(_dock_instance)

	# Wire docking system to HUD for dock prompt display
	if hud:
		hud.set_docking_system(_docking_system)

	# Player cargo inventory
	player_cargo = PlayerCargo.new()

	# Loot pickup system (child of player ship, scans for nearby crates)
	_loot_pickup = LootPickupSystem.new()
	_loot_pickup.name = "LootPickupSystem"
	player_ship.add_child(_loot_pickup)

	# Wire loot pickup to HUD for loot prompt display
	if hud:
		hud.set_loot_pickup_system(_loot_pickup)

	# Note: system_transition wired to HUD after creation (see below)

	# Wire stellar map
	_stellar_map = main_scene.get_node_or_null("UI/StellarMap") as StellarMap

	# Generate galaxy
	_galaxy = GalaxyGenerator.generate(Constants.GALAXY_SEED)

	# Create system transition manager
	_system_transition = SystemTransition.new()
	_system_transition.name = "SystemTransition"
	_system_transition.galaxy = _galaxy
	add_child(_system_transition)
	_system_transition.system_loaded.connect(_on_system_loaded)

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
	if _remote_players.has(peer_id):
		var remote: RemotePlayerShip = _remote_players[peer_id]
		# Unregister from LOD system
		if _lod_manager:
			_lod_manager.unregister_ship(StringName("RemotePlayer_%d" % peer_id))
		if is_instance_valid(remote):
			remote.queue_free()
		_remote_players.erase(peer_id)
		print("GameManager: Removed remote player (peer %d)" % peer_id)


func _on_network_state_received(peer_id: int, state: NetworkState) -> void:
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
			# Convert universe float64 pos to local scene pos
			rdata.position = FloatingOrigin.to_local_pos([state.pos_x, state.pos_y, state.pos_z])
			rdata.velocity = state.velocity

	if _remote_players.has(peer_id):
		var remote: RemotePlayerShip = _remote_players[peer_id]
		if is_instance_valid(remote):
			remote.receive_state(state)


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
	# Restart on R when dead
	if current_state == GameState.DEAD:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()
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

	# Jump gate with J key
	if event.is_action_pressed("gate_jump") and current_state == GameState.PLAYING:
		if _system_transition and _system_transition.can_gate_jump():
			_system_transition.initiate_gate_jump(_system_transition.get_gate_target_id())
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
	prompt.text = "Appuyez sur [R] pour recommencer"
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
# DOCKING
# =============================================================================
func _on_docked(station_name: String) -> void:
	if current_state == GameState.DOCKED:
		return
	current_state = GameState.DOCKED

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
		if ship_model:
			_equipment_screen.setup_ship_viewer(ship_model.model_path, ship_model.model_scale)
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
	# Transfer selected items to player cargo
	if player_cargo and not selected_items.is_empty():
		player_cargo.add_items(selected_items)
	# Destroy the crate
	if crate and is_instance_valid(crate):
		crate._destroy()
	# Re-capture mouse for flight
	if current_state == GameState.PLAYING:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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
