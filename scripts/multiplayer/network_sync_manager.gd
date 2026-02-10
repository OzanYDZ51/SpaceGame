class_name NetworkSyncManager
extends Node

# =============================================================================
# Network Sync Manager — remote player/NPC management, combat sync, server config.
# Child Node of GameManager. NpcAuthority/ServerAuthority/ShipNetworkSync remain
# as GameManager children for backward compat (15+ files use get_node_or_null).
# =============================================================================

signal server_galaxy_changed(new_galaxy: GalaxyData)

# Injected refs (typed for convenience, actual nodes live under GameManager)
var ship_net_sync: ShipNetworkSync = null
var chat_relay: NetworkChatRelay = null
var server_authority: ServerAuthority = null
var npc_authority: NpcAuthority = null
var discord_rpc: DiscordRPC = null
var event_reporter: EventReporter = null
var lod_manager: ShipLODManager = null
var system_transition: SystemTransition = null
var universe_node: Node3D = null
var galaxy: GalaxyData = null
var screen_manager: UIScreenManager = null
var player_data: PlayerData = null
var fleet_deployment_mgr: FleetDeploymentManager = null

var remote_players: Dictionary = {}  # peer_id -> RemotePlayerShip
var remote_npcs: Dictionary = {}     # npc_id (StringName) -> true


func setup(player_ship: RigidBody3D, game_manager: Node) -> void:
	# Ship network sync (sends local ship position to server)
	ship_net_sync = ShipNetworkSync.new()
	ship_net_sync.name = "ShipNetworkSync"
	player_ship.add_child(ship_net_sync)

	# Chat relay
	chat_relay = NetworkChatRelay.new()
	chat_relay.name = "NetworkChatRelay"
	game_manager.add_child(chat_relay)

	# Server authority (self-destructs on client)
	server_authority = ServerAuthority.new()
	server_authority.name = "ServerAuthority"
	game_manager.add_child(server_authority)

	# NPC authority
	npc_authority = NpcAuthority.new()
	npc_authority.name = "NpcAuthority"
	game_manager.add_child(npc_authority)

	# Discord Rich Presence
	discord_rpc = DiscordRPC.new()
	discord_rpc.name = "DiscordRPC"
	game_manager.add_child(discord_rpc)

	# Event Reporter
	event_reporter = EventReporter.new()
	event_reporter.name = "EventReporter"
	game_manager.add_child(event_reporter)

	# Connect network signals
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.player_state_received.connect(_on_state_received)
	NetworkManager.server_config_received.connect(_on_server_config_received)
	NetworkManager.npc_batch_received.connect(_on_npc_batch_received)
	NetworkManager.npc_spawned.connect(_on_npc_spawned)
	NetworkManager.npc_died.connect(_on_npc_died)
	NetworkManager.fleet_ship_retrieved.connect(_on_remote_fleet_retrieved)
	NetworkManager.remote_fire_received.connect(_on_remote_fire_received)
	NetworkManager.player_died_received.connect(_on_remote_player_died)
	NetworkManager.player_respawned_received.connect(_on_remote_player_respawned)
	NetworkManager.player_ship_changed_received.connect(_on_remote_player_ship_changed)
	NetworkManager.remote_mining_beam_received.connect(_on_remote_mining_beam)
	NetworkManager.asteroid_depleted_received.connect(_on_remote_asteroid_depleted)

	# Auto-connect
	var args := OS.get_cmdline_args()
	var port: int = Constants.NET_DEFAULT_PORT
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = args[i + 1].to_int()
		elif args[i] == "--name" and i + 1 < args.size():
			NetworkManager.local_player_name = args[i + 1]

	if NetworkManager.is_dedicated_server:
		NetworkManager.start_dedicated_server(port)
	else:
		if Constants.NET_GAME_SERVER_URL != "":
			NetworkManager.connect_to_server(Constants.NET_GAME_SERVER_URL)
		else:
			if NetworkManager.is_local_server_running(port):
				NetworkManager.connect_to_server("ws://127.0.0.1:%d" % port)
			else:
				NetworkManager.connect_to_server("ws://%s:%d" % [Constants.NET_PUBLIC_IP, port])


# =============================================================================
# REMOTE PLAYERS
# =============================================================================

func _on_peer_connected(peer_id: int, player_name: String) -> void:
	if peer_id == NetworkManager.local_peer_id:
		return

	var remote := RemotePlayerShip.new()
	remote.peer_id = peer_id
	if NetworkManager.peers.has(peer_id):
		remote.ship_id = NetworkManager.peers[peer_id].ship_id
	remote.set_player_name(player_name)
	remote.name = "RemotePlayer_%d" % peer_id
	if universe_node:
		universe_node.add_child(remote)
	remote_players[peer_id] = remote

	if lod_manager:
		var rdata := ShipLODData.new()
		rdata.id = StringName(remote.name)
		rdata.is_remote_player = true
		rdata.peer_id = peer_id
		rdata.display_name = player_name
		rdata.faction = &"neutral"
		rdata.node_ref = remote
		rdata.current_lod = ShipLODData.LODLevel.LOD0
		lod_manager.register_ship(StringName(remote.name), rdata)

	# Register on system map
	EntityRegistry.register("remote_player_%d" % peer_id, {
		"name": player_name,
		"type": EntityRegistrySystem.EntityType.SHIP_PLAYER,
		"node": remote,
		"color": MapColors.REMOTE_PLAYER,
		"radius": 12.0,
	})

	if NetworkManager.is_server() and npc_authority and system_transition:
		npc_authority.send_all_npcs_to_peer(peer_id, system_transition.current_system_id)


func _on_peer_disconnected(peer_id: int) -> void:
	remove_remote_player(peer_id)


func remove_remote_player(peer_id: int) -> void:
	if remote_players.has(peer_id):
		var remote: RemotePlayerShip = remote_players[peer_id]
		if lod_manager:
			lod_manager.unregister_ship(StringName("RemotePlayer_%d" % peer_id))
		EntityRegistry.unregister("remote_player_%d" % peer_id)
		if is_instance_valid(remote):
			remote.queue_free()
		remote_players.erase(peer_id)


func _on_state_received(peer_id: int, state: NetworkState) -> void:
	var local_sys_id: int = system_transition.current_system_id if system_transition else -1
	if state.system_id != local_sys_id:
		remove_remote_player(peer_id)
		return

	if not remote_players.has(peer_id):
		if NetworkManager.peers.has(peer_id):
			var pname: String = NetworkManager.peers[peer_id].player_name
			_on_peer_connected(peer_id, pname)

	if lod_manager:
		var rid := StringName("RemotePlayer_%d" % peer_id)
		var rdata := lod_manager.get_ship_data(rid)
		if rdata:
			rdata.position = FloatingOrigin.to_local_pos([state.pos_x, state.pos_y, state.pos_z])
			rdata.velocity = state.velocity

	# Update map entity velocity + visibility
	var map_ent_id := "remote_player_%d" % peer_id
	var map_ent := EntityRegistry.get_entity(map_ent_id)
	if not map_ent.is_empty():
		map_ent["vel_x"] = state.velocity.x
		map_ent["vel_z"] = state.velocity.z
		map_ent["extra"]["hidden"] = state.is_docked or state.is_dead

	if remote_players.has(peer_id):
		var remote: RemotePlayerShip = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.receive_state(state)


# =============================================================================
# SERVER CONFIG
# =============================================================================

func _on_server_config_received(config: Dictionary) -> void:
	var server_seed: int = config.get("galaxy_seed", Constants.galaxy_seed)
	var spawn_system: int = config.get("spawn_system_id", -1)

	if server_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = server_seed
		galaxy = GalaxyGenerator.generate(server_seed)
		if system_transition:
			system_transition.galaxy = galaxy
		if screen_manager:
			var map_screen := screen_manager._screens.get("map") as UnifiedMapScreen
			if map_screen:
				map_screen.galaxy = galaxy
		if player_data:
			player_data.station_services = StationServices.new()
			player_data.station_services.init_center_systems(galaxy)
		server_galaxy_changed.emit(galaxy)

	_populate_wormhole_targets()

	if spawn_system >= 0 and galaxy and spawn_system < galaxy.systems.size():
		if system_transition and system_transition.current_system_id != spawn_system:
			system_transition.jump_to_system(spawn_system)


func _populate_wormhole_targets() -> void:
	if galaxy == null or NetworkManager.galaxy_servers.is_empty():
		return
	var servers := NetworkManager.galaxy_servers
	var current_seed: int = Constants.galaxy_seed
	var target_idx: int = 0
	for sys in galaxy.systems:
		if sys.has("wormhole_target"):
			var found := false
			for j in servers.size():
				var candidate: Dictionary = servers[(target_idx + j) % servers.size()]
				if candidate.get("seed", 0) != current_seed:
					sys["wormhole_target"] = {
						"seed": candidate.get("seed", 0),
						"name": candidate.get("name", "Unknown"),
						"url": candidate.get("url", ""),
					}
					found = true
					target_idx += j + 1
					break
			if not found:
				sys["wormhole_target"] = {}


# =============================================================================
# NPC SYNC
# =============================================================================

func _on_npc_spawned(data: Dictionary) -> void:
	if NetworkManager.is_server() and not NetworkManager.is_dedicated_server:
		return

	var npc_id := StringName(data.get("nid", ""))
	if npc_id == &"" or remote_npcs.has(npc_id):
		return

	var sid := StringName(data.get("sid", "fighter_mk1"))
	var fac := StringName(data.get("fac", "hostile"))

	var lod_data := ShipLODData.new()
	lod_data.id = npc_id
	lod_data.ship_id = sid
	lod_data.ship_class = ShipRegistry.get_ship_data(sid).ship_class if ShipRegistry.get_ship_data(sid) else &"Fighter"
	lod_data.faction = fac
	lod_data.is_server_npc = true
	lod_data.display_name = String(ShipRegistry.get_ship_data(sid).ship_name) if ShipRegistry.get_ship_data(sid) else String(sid)
	lod_data.position = FloatingOrigin.to_local_pos([data.get("px", 0.0), data.get("py", 0.0), data.get("pz", 0.0)])
	lod_data.hull_ratio = data.get("hull", 1.0)
	lod_data.shield_ratio = data.get("shd", 1.0)
	lod_data.current_lod = ShipLODData.LODLevel.LOD3

	if fac == &"hostile":
		lod_data.color_tint = Color(1.0, 0.55, 0.5)
	elif fac == &"friendly":
		lod_data.color_tint = Color(0.5, 1.0, 0.6)
	elif fac == &"player_fleet":
		lod_data.color_tint = Color(0.5, 0.7, 1.0)
	else:
		lod_data.color_tint = Color(0.8, 0.7, 1.0)

	var sdata := ShipRegistry.get_ship_data(sid)
	if sdata:
		lod_data.model_scale = sdata.model_scale

	if lod_manager:
		lod_manager.register_ship(npc_id, lod_data)
	remote_npcs[npc_id] = true


func _on_npc_batch_received(batch: Array) -> void:
	if NetworkManager.is_server() and not NetworkManager.is_dedicated_server:
		return

	for state_dict in batch:
		var npc_id := StringName(state_dict.get("nid", ""))
		if npc_id == &"":
			continue

		if not remote_npcs.has(npc_id):
			_on_npc_spawned(state_dict)

		if lod_manager:
			var lod_data: ShipLODData = lod_manager.get_ship_data(npc_id)
			if lod_data:
				lod_data.position = FloatingOrigin.to_local_pos(
					[state_dict.get("px", 0.0), state_dict.get("py", 0.0), state_dict.get("pz", 0.0)])
				lod_data.velocity = Vector3(
					state_dict.get("vx", 0.0), state_dict.get("vy", 0.0), state_dict.get("vz", 0.0))
				lod_data.hull_ratio = state_dict.get("hull", 1.0)
				lod_data.shield_ratio = state_dict.get("shd", 1.0)
				lod_data.ai_state = state_dict.get("ai", 0)
				if lod_data.node_ref and is_instance_valid(lod_data.node_ref):
					if lod_data.node_ref is RemoteNPCShip:
						(lod_data.node_ref as RemoteNPCShip).receive_state(state_dict)


func _on_npc_died(npc_id_str: String, killer_pid: int, death_pos: Array, loot: Array) -> void:
	var npc_id := StringName(npc_id_str)

	if lod_manager:
		var lod_data: ShipLODData = lod_manager.get_ship_data(npc_id)
		if lod_data:
			var pos := lod_data.position
			if lod_data.node_ref and is_instance_valid(lod_data.node_ref):
				pos = lod_data.node_ref.global_position
				if lod_data.node_ref is RemoteNPCShip:
					(lod_data.node_ref as RemoteNPCShip).play_death()
				else:
					lod_data.node_ref.queue_free()
			else:
				var explosion := ExplosionEffect.new()
				get_tree().current_scene.add_child(explosion)
				explosion.global_position = pos
			lod_data.is_dead = true
		lod_manager.unregister_ship(npc_id)

	remote_npcs.erase(npc_id)

	if killer_pid == NetworkManager.local_peer_id and not loot.is_empty():
		var local_pos := FloatingOrigin.to_local_pos(death_pos)
		var crate := CargoCrate.new()
		var typed_loot: Array[Dictionary] = []
		for item in loot:
			if item is Dictionary:
				typed_loot.append(item)
		crate.contents = typed_loot
		crate.owner_peer_id = killer_pid
		crate.global_position = local_pos
		if universe_node:
			universe_node.add_child(crate)


func _on_remote_fleet_retrieved(_owner_pid: int, _fleet_idx: int, npc_id_str: String) -> void:
	if NetworkManager.is_server() and not NetworkManager.is_dedicated_server:
		return
	var npc_id := StringName(npc_id_str)
	if lod_manager:
		var lod_data: ShipLODData = lod_manager.get_ship_data(npc_id)
		if lod_data and lod_data.node_ref and is_instance_valid(lod_data.node_ref):
			lod_data.node_ref.queue_free()
		lod_manager.unregister_ship(npc_id)
	remote_npcs.erase(npc_id)


# =============================================================================
# COMBAT SYNC
# =============================================================================

func _on_remote_fire_received(peer_id: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not remote_players.has(peer_id):
		return
	var remote: RemotePlayerShip = remote_players[peer_id]
	if not is_instance_valid(remote):
		return

	var weapon := WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon == null:
		return

	var proj_scene_path: String = weapon.projectile_scene_path
	if proj_scene_path.is_empty():
		return

	var pool: ProjectilePool = null
	if lod_manager:
		pool = lod_manager.get_node_or_null("ProjectilePool") as ProjectilePool

	var bolt: BaseProjectile = null
	if pool:
		bolt = pool.acquire(proj_scene_path)
		if bolt:
			bolt._pool = pool
	if bolt == null:
		var scene: PackedScene = load(proj_scene_path)
		if scene == null:
			return
		bolt = scene.instantiate() as BaseProjectile
		if bolt == null:
			return
		get_tree().current_scene.add_child(bolt)

	bolt.collision_layer = 0
	bolt.collision_mask = 0
	bolt.monitoring = false
	bolt.owner_ship = remote
	bolt.damage = 0.0
	bolt.max_lifetime = weapon.projectile_lifetime

	var dir := Vector3(
		fire_dir[0] if fire_dir.size() > 0 else 0.0,
		fire_dir[1] if fire_dir.size() > 1 else 0.0,
		fire_dir[2] if fire_dir.size() > 2 else 0.0)
	var ship_vel := Vector3(
		fire_dir[3] if fire_dir.size() > 3 else 0.0,
		fire_dir[4] if fire_dir.size() > 4 else 0.0,
		fire_dir[5] if fire_dir.size() > 5 else 0.0)

	var spawn_pos: Vector3
	if is_instance_valid(remote):
		spawn_pos = remote.global_position + dir * 5.0
	else:
		spawn_pos = FloatingOrigin.to_local_pos(fire_pos)
	bolt.global_position = spawn_pos
	bolt.velocity = dir * weapon.projectile_speed + ship_vel
	if dir.length_squared() > 0.001:
		bolt.look_at(spawn_pos + dir, Vector3.UP)


# =============================================================================
# REMOTE PLAYER DEATH / RESPAWN / SHIP CHANGE
# =============================================================================

func _on_remote_player_died(peer_id: int, _death_pos: Array) -> void:
	if remote_players.has(peer_id):
		var remote: RemotePlayerShip = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.show_death_explosion()


func _on_remote_player_respawned(_peer_id: int, _system_id: int) -> void:
	pass


func _on_remote_player_ship_changed(peer_id: int, new_ship_id: StringName) -> void:
	if remote_players.has(peer_id):
		var remote: RemotePlayerShip = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.change_ship_model(new_ship_id)


# =============================================================================
# MINING SYNC
# =============================================================================

func _on_remote_mining_beam(peer_id: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not remote_players.has(peer_id):
		return
	var remote: RemotePlayerShip = remote_players[peer_id]
	if not is_instance_valid(remote):
		return
	if is_active:
		remote.show_mining_beam(source_pos, target_pos)
	else:
		remote.hide_mining_beam()


func _on_remote_asteroid_depleted(asteroid_id_str: String) -> void:
	var gm := GameManager as GameManagerSystem
	if gm == null or gm._asteroid_field_mgr == null:
		return
	var field_mgr: AsteroidFieldManager = gm._asteroid_field_mgr
	var id := StringName(asteroid_id_str)
	field_mgr.on_asteroid_depleted(id)
	# Also deplete the asteroid data if loaded
	var ast := field_mgr.get_asteroid_data(id)
	if ast and not ast.is_depleted:
		ast.is_depleted = true
		ast.health_current = 0.0
		# Update visual if node exists
		if ast.node_ref and is_instance_valid(ast.node_ref) and ast.node_ref is AsteroidNode:
			(ast.node_ref as AsteroidNode)._on_depleted()


# =============================================================================
# SYSTEM TRANSITION HELPERS
# =============================================================================

func on_system_unloading(_system_id: int) -> void:
	# Clear all remote player puppets
	for pid in remote_players.keys():
		remove_remote_player(pid)

	# Clear all server NPC data from LOD
	if lod_manager:
		for npc_id in remote_npcs.keys():
			lod_manager.unregister_ship(npc_id)
	remote_npcs.clear()

	# Clear server NPC authority registry
	if npc_authority and NetworkManager.is_server():
		npc_authority.clear_system_npcs(_system_id)
