class_name NetworkSyncManager
extends Node

# =============================================================================
# Network Sync Manager — remote player/NPC management, combat sync, server config.
# Child Node of GameManager. NpcAuthority/ServerAuthority/ShipNetworkSync remain
# as GameManager children for backward compat (15+ files use get_node_or_null).
# =============================================================================

signal server_galaxy_changed(new_galaxy)

# Injected refs (untyped to avoid circular dependency on custom class_names)
var ship_net_sync = null
var chat_relay = null
var server_authority = null
var npc_authority = null
var discord_rpc = null
var event_reporter = null
var lod_manager = null
var system_transition = null
var universe_node = null
var galaxy = null
var screen_manager = null
var player_data = null
var fleet_deployment_mgr = null

var remote_players: Dictionary = {}  # peer_id -> RemotePlayerShip
var remote_npcs: Dictionary = {}     # npc_id (StringName) -> true
var _recently_dead_npcs: Dictionary = {}  # npc_id -> death_ticks_ms (prevents ghost re-creation from delayed batch)
var _system_mismatch_grace: Dictionary = {}  # peer_id -> first_mismatch_ticks_ms
const SYSTEM_MISMATCH_GRACE_MS: int = 3000  # 3s grace before removing remote player
const DEAD_NPC_GUARD_MS: int = 10000  # 10s guard against batch re-creation


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
	NetworkManager.fleet_ship_deployed.connect(_on_remote_fleet_deployed)
	NetworkManager.fleet_ship_retrieved.connect(_on_remote_fleet_retrieved)
	NetworkManager.fleet_command_changed.connect(_on_remote_fleet_command_changed)
	NetworkManager.remote_fire_received.connect(_on_remote_fire_received)
	NetworkManager.player_damage_received.connect(_on_player_damage_received)
	NetworkManager.npc_fire_received.connect(_on_npc_fire_received)
	NetworkManager.player_died_received.connect(_on_remote_player_died)
	NetworkManager.player_respawned_received.connect(_on_remote_player_respawned)
	NetworkManager.player_ship_changed_received.connect(_on_remote_player_ship_changed)
	NetworkManager.player_left_system_received.connect(_on_player_left_system)
	NetworkManager.player_entered_system_received.connect(_on_player_entered_system)
	NetworkManager.remote_mining_beam_received.connect(_on_remote_mining_beam)
	NetworkManager.asteroid_depleted_received.connect(_on_remote_asteroid_depleted)
	NetworkManager.asteroid_health_batch_received.connect(_on_asteroid_health_batch)
	NetworkManager.hit_effect_received.connect(_on_hit_effect_received)

	# Parse CLI args
	var args = OS.get_cmdline_args()
	var port: int = Constants.NET_DEFAULT_PORT
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = args[i + 1].to_int()
		elif args[i] == "--name" and i + 1 < args.size():
			NetworkManager.local_player_name = args[i + 1]

	# Server auto-starts immediately; clients connect later via connect_client()
	# after all player data (corporation, backend state) has loaded.
	if NetworkManager.is_server():
		NetworkManager.start_dedicated_server(port)


## Connect to the game server as a client. Called by GameManager after all
## player data (corporation, backend state) is loaded, so the first network
## sync already includes the corporation tag.
func connect_client() -> void:
	if NetworkManager.is_server():
		return
	NetworkManager.connect_to_server(Constants.NET_GAME_SERVER_URL)


# =============================================================================
# REMOTE PLAYERS
# =============================================================================

func _on_peer_connected(peer_id: int, player_name: String) -> void:
	if peer_id == NetworkManager.local_peer_id:
		return

	var remote =RemotePlayerShip.new()
	remote.peer_id = peer_id
	if NetworkManager.peers.has(peer_id):
		remote.ship_id = NetworkManager.peers[peer_id].ship_id
	remote.set_player_name(player_name)
	remote.name = "RemotePlayer_%d" % peer_id
	# Start hidden — made visible on first receive_state() with valid position.
	# Without this, the puppet flashes at (0,0,0) (near station) until the first
	# network state update arrives with the real position.
	remote.visible = false
	if universe_node:
		universe_node.add_child(remote)
	remote_players[peer_id] = remote

	if lod_manager:
		var rdata =ShipLODData.new()
		rdata.id = StringName(remote.name)
		rdata.is_remote_player = true
		rdata.peer_id = peer_id
		rdata.display_name = player_name
		rdata.faction = &"neutral"
		rdata.node_ref = remote
		rdata.current_lod = ShipLODData.LODLevel.LOD0
		lod_manager.register_ship(StringName(remote.name), rdata)

	# Register on system map (hidden until first state arrives with real position)
	# ID MUST match remote.name ("RemotePlayer_%d") so ShipLODManager._ensure_entity_registered()
	# sees the existing entry and doesn't create a duplicate.
	EntityRegistry.register("RemotePlayer_%d" % peer_id, {
		"name": player_name,
		"type": EntityRegistrySystem.EntityType.SHIP_PLAYER,
		"node": remote,
		"color": MapColors.REMOTE_PLAYER,
		"radius": 12.0,
		"extra": {"hidden": true},
	})

	# Send all NPCs to the new peer after a short delay.
	# The client needs time to receive server_config, jump to the correct system,
	# and finish loading before it can process NPC spawn data.
	# Without this delay, NPCs arrive before the jump → get wiped by on_system_unloading.
	if NetworkManager.is_server() and npc_authority and system_transition:
		_deferred_send_npcs_to_peer(peer_id, system_transition.current_system_id)


func _on_peer_disconnected(peer_id: int) -> void:
	remove_remote_player(peer_id)


func _on_player_left_system(peer_id: int) -> void:
	remove_remote_player(peer_id)


func _on_player_entered_system(peer_id: int, _ship_id: StringName) -> void:
	if peer_id == NetworkManager.local_peer_id:
		return
	# Create puppet if not already present (first state update will position it)
	if not remote_players.has(peer_id):
		var pname: String = "Pilote"
		if NetworkManager.peers.has(peer_id):
			pname = NetworkManager.peers[peer_id].player_name
		_on_peer_connected(peer_id, pname)


func remove_remote_player(peer_id: int) -> void:
	if remote_players.has(peer_id):
		var remote = remote_players[peer_id]
		if lod_manager:
			lod_manager.unregister_ship(StringName("RemotePlayer_%d" % peer_id))
		EntityRegistry.unregister("RemotePlayer_%d" % peer_id)
		if is_instance_valid(remote):
			remote.queue_free()
		remote_players.erase(peer_id)


func _on_state_received(peer_id: int, state) -> void:
	if peer_id == NetworkManager.local_peer_id:
		return
	var local_sys_id: int = system_transition.current_system_id if system_transition else -1
	if state.system_id != local_sys_id:
		# Grace period: during simultaneous jumps, the server may briefly tag
		# new-system positions with the old system_id (race between reliable
		# system change RPC and unreliable position updates). Wait 3s before removing.
		var now_ms: int = Time.get_ticks_msec()
		if not _system_mismatch_grace.has(peer_id):
			_system_mismatch_grace[peer_id] = now_ms
		elif now_ms - _system_mismatch_grace[peer_id] > SYSTEM_MISMATCH_GRACE_MS:
			if remote_players.has(peer_id):
				var pname: String = NetworkManager.peers[peer_id].player_name if NetworkManager.peers.has(peer_id) else "?"
				print("[Net] Joueur '%s' (peer %d) dans systeme %d, nous dans %d — masqué" % [pname, peer_id, state.system_id, local_sys_id])
			_system_mismatch_grace.erase(peer_id)
			remove_remote_player(peer_id)
		return
	# System matches — clear any pending grace timer
	_system_mismatch_grace.erase(peer_id)

	if not remote_players.has(peer_id):
		if NetworkManager.peers.has(peer_id):
			var pname: String = NetworkManager.peers[peer_id].player_name
			print("[Net] Joueur '%s' (peer %d) visible dans systeme %d" % [pname, peer_id, local_sys_id])
			_on_peer_connected(peer_id, pname)

	if lod_manager:
		var rid =StringName("RemotePlayer_%d" % peer_id)
		var rdata = lod_manager.get_ship_data(rid)
		if rdata:
			rdata.position = FloatingOrigin.to_local_pos([state.pos_x, state.pos_y, state.pos_z])
			rdata.velocity = state.velocity
			rdata.is_docked = state.is_docked
			rdata.is_dead = state.is_dead

	# Update map entity position + velocity + visibility
	var map_ent_id ="RemotePlayer_%d" % peer_id
	var map_ent =EntityRegistry.get_entity(map_ent_id)
	if not map_ent.is_empty():
		map_ent["pos_x"] = state.pos_x
		map_ent["pos_y"] = state.pos_y
		map_ent["pos_z"] = state.pos_z
		map_ent["vel_x"] = state.velocity.x
		map_ent["vel_y"] = state.velocity.y
		map_ent["vel_z"] = state.velocity.z
		map_ent["extra"]["hidden"] = state.is_docked or state.is_dead

	if remote_players.has(peer_id):
		var remote = remote_players[peer_id]
		# After LOD demotion (LOD1→LOD2), the old node was freed. When re-promoted
		# (LOD2→LOD1), a new node is created but remote_players keeps the stale ref.
		# Re-fetch from LOD data so the new node receives state updates.
		if not is_instance_valid(remote) and lod_manager:
			var rid = StringName("RemotePlayer_%d" % peer_id)
			var rdata = lod_manager.get_ship_data(rid)
			if rdata and is_instance_valid(rdata.node_ref):
				remote = rdata.node_ref
				remote_players[peer_id] = remote
		if is_instance_valid(remote):
			remote.receive_state(state)


# =============================================================================
# SERVER CONFIG
# =============================================================================

func _on_server_config_received(config: Dictionary) -> void:
	var server_seed: int = config.get("galaxy_seed", Constants.galaxy_seed)

	if server_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = server_seed
		galaxy = GalaxyGenerator.generate(server_seed)
		if system_transition:
			system_transition.galaxy = galaxy
		if screen_manager:
			var map_screen = screen_manager._screens.get("map")
			if map_screen:
				map_screen.galaxy = galaxy
		if player_data:
			player_data.station_services = StationServices.new()
			player_data.station_services.init_center_systems(galaxy)
		server_galaxy_changed.emit(galaxy)

	_populate_wormhole_targets()

	# NOTE: spawn_system_id from server config is intentionally IGNORED.
	# The backend (PostgreSQL) is the sole source of truth for player position.
	# _load_backend_state() → apply_save_state() handles system + position restore.
	# Jumping here caused race conditions: server config arriving after backend
	# state would call jump_to_system → _position_player, destroying the
	# correctly restored position.


func _populate_wormhole_targets() -> void:
	if galaxy == null or NetworkManager.galaxy_servers.is_empty():
		return
	var servers =NetworkManager.galaxy_servers
	var current_seed: int = Constants.galaxy_seed
	var target_idx: int = 0
	for sys in galaxy.systems:
		if sys.has("wormhole_target"):
			var found =false
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
	var npc_id =StringName(data.get("nid", ""))
	if npc_id == &"" or remote_npcs.has(npc_id):
		return

	var sid =StringName(data.get("sid", String(Constants.DEFAULT_SHIP_ID)))
	var fac =StringName(data.get("fac", "hostile"))

	var lod_data =ShipLODData.new()
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

	var sdata =ShipRegistry.get_ship_data(sid)
	if sdata:
		lod_data.model_scale = sdata.model_scale

	# Set fleet owner on LOD data for PvP targeting
	if fac == &"player_fleet":
		lod_data.owner_pid = int(data.get("owner_pid", 0))

	if lod_manager:
		lod_manager.register_ship(npc_id, lod_data)
	remote_npcs[npc_id] = true

	# Tag fleet NPCs in EntityRegistry so the map can distinguish own vs foreign
	if fac == &"player_fleet":
		var ent = EntityRegistry.get_entity(String(npc_id))
		if not ent.is_empty():
			ent["type"] = EntityRegistrySystem.EntityType.SHIP_FLEET
			if not ent.has("extra"):
				ent["extra"] = {}
			ent["extra"]["owner_name"] = data.get("owner_name", "")
			ent["extra"]["owner_pid"] = data.get("owner_pid", -1)
			ent["extra"]["command"] = data.get("cmd", "")
			ent["extra"]["faction"] = "player_fleet"


func _on_npc_batch_received(batch: Array) -> void:
	# Periodic cleanup of stale dead-NPC guard entries
	var now_ms: int = Time.get_ticks_msec()
	if not _recently_dead_npcs.is_empty() and (now_ms % 5000) < 50:
		var stale: Array[StringName] = []
		for did: StringName in _recently_dead_npcs:
			if now_ms - _recently_dead_npcs[did] > DEAD_NPC_GUARD_MS:
				stale.append(did)
		for did in stale:
			_recently_dead_npcs.erase(did)

	for state_dict in batch:
		var npc_id =StringName(state_dict.get("nid", ""))
		if npc_id == &"":
			continue

		# Prevent ghost re-creation: delayed batch packets can arrive AFTER
		# the reliable _rpc_npc_died, causing a dead NPC to be re-spawned.
		if _recently_dead_npcs.has(npc_id):
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
				if is_instance_valid(lod_data.node_ref):
					if lod_data.node_ref is RemoteNPCShip:
						lod_data.node_ref.receive_state(state_dict)

		# Update EntityRegistry so stellar map stays current even while docked.
		# lod_manager._process() is disabled when docked, so positions won't update otherwise.
		var ent: Dictionary = EntityRegistry.get_entity(String(npc_id))
		if not ent.is_empty():
			ent["pos_x"] = state_dict.get("px", 0.0)
			ent["pos_y"] = state_dict.get("py", 0.0)
			ent["pos_z"] = state_dict.get("pz", 0.0)
			ent["vel_x"] = state_dict.get("vx", 0.0)
			ent["vel_y"] = state_dict.get("vy", 0.0)
			ent["vel_z"] = state_dict.get("vz", 0.0)


func _on_npc_died(npc_id_str: String, killer_pid: int, death_pos: Array, loot: Array) -> void:
	var npc_id =StringName(npc_id_str)

	# Guard: prevent delayed batch packets from re-creating this NPC as a ghost
	_recently_dead_npcs[npc_id] = Time.get_ticks_msec()

	# Credit kill to mission/reputation system BEFORE LOD cleanup
	# Only for multiplayer CLIENTS — host already gets credit via EncounterManager signal
	if killer_pid == NetworkManager.local_peer_id and not NetworkManager.is_server():
		var faction: StringName = &"hostile"
		var ship_class: StringName = &""
		if lod_manager:
			var kill_lod: ShipLODData = lod_manager.get_ship_data(npc_id)
			if kill_lod:
				faction = kill_lod.faction
				ship_class = kill_lod.ship_class
		var gi = GameManager.get_node_or_null("GameplayIntegrator")
		if gi:
			gi.on_npc_kill_credited(npc_id_str, faction, ship_class)

	if lod_manager:
		var lod_data: ShipLODData = lod_manager.get_ship_data(npc_id)
		if lod_data:
			var pos =lod_data.position
			if is_instance_valid(lod_data.node_ref):
				pos = lod_data.node_ref.global_position
				if lod_data.node_ref is RemoteNPCShip:
					lod_data.node_ref.play_death()
				else:
					lod_data.node_ref.queue_free()
			else:
				var explosion =ExplosionEffect.new()
				get_tree().current_scene.add_child(explosion)
				explosion.global_position = pos
			lod_data.is_dead = true
		lod_manager.unregister_ship(npc_id)

	remote_npcs.erase(npc_id)

	if killer_pid == NetworkManager.local_peer_id and not loot.is_empty():
		var local_pos =FloatingOrigin.to_local_pos(death_pos)
		var crate =CargoCrate.new()
		var typed_loot: Array[Dictionary] = []
		for item in loot:
			if item is Dictionary:
				typed_loot.append(item)
		crate.contents = typed_loot
		crate.owner_peer_id = killer_pid
		if universe_node:
			universe_node.add_child(crate)
			crate.global_position = local_pos


func _on_remote_fleet_deployed(_owner_pid: int, _fleet_idx: int, _npc_id_str: String, spawn_data: Dictionary) -> void:
	_on_npc_spawned(spawn_data)


func _on_remote_fleet_retrieved(_owner_pid: int, _fleet_idx: int, npc_id_str: String) -> void:
	var npc_id =StringName(npc_id_str)
	if lod_manager:
		var lod_data: ShipLODData = lod_manager.get_ship_data(npc_id)
		if lod_data and is_instance_valid(lod_data.node_ref):
			lod_data.node_ref.queue_free()
		lod_manager.unregister_ship(npc_id)
	remote_npcs.erase(npc_id)


func _on_remote_fleet_command_changed(_owner_pid: int, _fleet_idx: int, _npc_id_str: String, _cmd: String, _params: Dictionary) -> void:
	pass


# =============================================================================
# COMBAT SYNC
# =============================================================================

func _on_remote_fire_received(peer_id: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not remote_players.has(peer_id):
		return
	var remote = remote_players[peer_id]
	if not is_instance_valid(remote):
		return

	var weapon =WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon == null:
		return

	var proj_scene_path: String = weapon.projectile_scene_path
	if proj_scene_path.is_empty():
		return

	var pool = null
	if lod_manager:
		pool = lod_manager.get_node_or_null("ProjectilePool")

	var bolt = null
	if pool:
		bolt = pool.acquire(proj_scene_path)
		if bolt:
			bolt._pool = pool
	if bolt == null:
		var scene: PackedScene = load(proj_scene_path)
		if scene == null:
			return
		bolt = scene.instantiate()
		if bolt == null:
			return
		get_tree().current_scene.add_child(bolt)

	bolt.collision_layer = 0
	bolt.collision_mask = 0
	bolt.set_deferred("monitoring", false)
	bolt.owner_ship = remote
	bolt.damage = 0.0
	bolt.max_lifetime = weapon.projectile_lifetime

	var dir =Vector3(
		fire_dir[0] if fire_dir.size() > 0 else 0.0,
		fire_dir[1] if fire_dir.size() > 1 else 0.0,
		fire_dir[2] if fire_dir.size() > 2 else 0.0)
	var ship_vel =Vector3(
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
	var look_target: Vector3 = spawn_pos + dir
	if dir.length_squared() > 0.001 and not spawn_pos.is_equal_approx(look_target):
		bolt.look_at(look_target, Vector3.UP)


# =============================================================================
# PVP DAMAGE — Server validated, applied on target client
# =============================================================================

func _on_player_damage_received(attacker_pid: int, _weapon_name: String, damage_val: float, hit_dir: Array) -> void:
	var player_ship = GameManager.player_ship
	if player_ship == null:
		return
	var health = player_ship.get_node_or_null("HealthSystem")
	if health == null or health.is_dead():
		return
	var dir_vec =Vector3(
		hit_dir[0] if hit_dir.size() > 0 else 0.0,
		hit_dir[1] if hit_dir.size() > 1 else 0.0,
		hit_dir[2] if hit_dir.size() > 2 else 0.0)
	# Find attacker node for damage attribution
	var attacker: Node3D = remote_players.get(attacker_pid)
	var hit_result =health.apply_damage(damage_val, &"thermal", dir_vec, attacker)

	# Spawn hit effect on our own ship (same visual as NPC projectile impact)
	var intensity =clampf(damage_val / 25.0, 0.5, 3.0)
	var hit_pos =player_ship.global_position + dir_vec * 2.0
	if hit_result.get("shield_absorbed", false):
		var effect =ShieldHitEffect.new()
		player_ship.add_child(effect)
		effect.setup(hit_pos, player_ship, hit_result.get("shield_ratio", 0.0), intensity)
	else:
		var effect =HullHitEffect.new()
		get_tree().current_scene.add_child(effect)
		effect.global_position = hit_pos
		var hit_normal =dir_vec.normalized() if dir_vec.length_squared() > 0.001 else Vector3.UP
		effect.setup(hit_normal, intensity)


# =============================================================================
# HIT EFFECT BROADCAST — Show hit effects on targets for observer clients
# =============================================================================

func _on_hit_effect_received(target_id: String, hit_dir: Array, shield_absorbed: bool) -> void:
	var target_node: Node3D = null

	# Player target: "player_<pid>"
	if target_id.begins_with("player_"):
		var pid =target_id.trim_prefix("player_").to_int()
		if remote_players.has(pid) and is_instance_valid(remote_players[pid]):
			target_node = remote_players[pid]
	else:
		# NPC target
		if lod_manager:
			var lod_data: ShipLODData = lod_manager.get_ship_data(StringName(target_id))
			if lod_data and is_instance_valid(lod_data.node_ref):
				target_node = lod_data.node_ref

	if target_node == null or not is_instance_valid(target_node):
		return

	var dir_vec =Vector3(
		hit_dir[0] if hit_dir.size() > 0 else 0.0,
		hit_dir[1] if hit_dir.size() > 1 else 0.0,
		hit_dir[2] if hit_dir.size() > 2 else 0.0)
	var hit_pos =target_node.global_position + dir_vec * 2.0

	if shield_absorbed:
		var effect =ShieldHitEffect.new()
		target_node.add_child(effect)
		effect.setup(hit_pos, target_node, 0.5, 1.0)
	else:
		var effect =HullHitEffect.new()
		get_tree().current_scene.add_child(effect)
		effect.global_position = hit_pos
		var hit_normal =dir_vec.normalized() if dir_vec.length_squared() > 0.001 else Vector3.UP
		effect.setup(hit_normal, 1.0)


# =============================================================================
# NPC FIRE RELAY — Visual projectiles from server NPCs on remote clients
# =============================================================================

func _on_npc_fire_received(_npc_id_str: String, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	var weapon =WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon == null:
		return

	var proj_scene_path: String = weapon.projectile_scene_path
	if proj_scene_path.is_empty():
		return

	var pool = null
	if lod_manager:
		pool = lod_manager.get_node_or_null("ProjectilePool")

	var bolt = null
	if pool:
		bolt = pool.acquire(proj_scene_path)
		if bolt:
			bolt._pool = pool
	if bolt == null:
		var scene: PackedScene = load(proj_scene_path)
		if scene == null:
			return
		bolt = scene.instantiate()
		if bolt == null:
			return
		get_tree().current_scene.add_child(bolt)

	# Visual-only projectile (no collision, no damage)
	bolt.collision_layer = 0
	bolt.collision_mask = 0
	bolt.set_deferred("monitoring", false)
	bolt.owner_ship = null
	bolt.damage = 0.0
	bolt.max_lifetime = weapon.projectile_lifetime

	var dir =Vector3(
		fire_dir[0] if fire_dir.size() > 0 else 0.0,
		fire_dir[1] if fire_dir.size() > 1 else 0.0,
		fire_dir[2] if fire_dir.size() > 2 else 0.0)
	var ship_vel =Vector3(
		fire_dir[3] if fire_dir.size() > 3 else 0.0,
		fire_dir[4] if fire_dir.size() > 4 else 0.0,
		fire_dir[5] if fire_dir.size() > 5 else 0.0)

	var spawn_pos: Vector3 = FloatingOrigin.to_local_pos(fire_pos)
	bolt.global_position = spawn_pos
	bolt.velocity = dir * weapon.projectile_speed + ship_vel
	var look_target: Vector3 = spawn_pos + dir
	if dir.length_squared() > 0.001 and not spawn_pos.is_equal_approx(look_target):
		bolt.look_at(look_target, Vector3.UP)


# =============================================================================
# REMOTE PLAYER DEATH / RESPAWN / SHIP CHANGE
# =============================================================================

func _on_remote_player_died(peer_id: int, _death_pos: Array) -> void:
	if remote_players.has(peer_id):
		var remote = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.show_death_explosion()


func _on_remote_player_respawned(_peer_id: int, _system_id: int) -> void:
	pass


func _on_remote_player_ship_changed(peer_id: int, new_ship_id: StringName) -> void:
	if remote_players.has(peer_id):
		var remote = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.change_ship_model(new_ship_id)
	# Update LOD data with new ship info
	if lod_manager:
		var rid =StringName("RemotePlayer_%d" % peer_id)
		var rdata = lod_manager.get_ship_data(rid)
		if rdata:
			rdata.ship_id = new_ship_id
			var sdata =ShipRegistry.get_ship_data(new_ship_id)
			if sdata:
				rdata.ship_class = sdata.ship_class
				rdata.model_scale = sdata.model_scale


# =============================================================================
# MINING SYNC
# =============================================================================

func _on_remote_mining_beam(peer_id: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not remote_players.has(peer_id):
		return
	var remote = remote_players[peer_id]
	if not is_instance_valid(remote):
		return
	if is_active:
		remote.show_mining_beam(source_pos, target_pos)
	else:
		remote.hide_mining_beam()


func _on_remote_asteroid_depleted(asteroid_id_str: String) -> void:
	var field_mgr = GameManager._asteroid_field_mgr
	if field_mgr == null:
		return
	var id =StringName(asteroid_id_str)
	field_mgr.on_asteroid_depleted(id)
	# Also deplete the asteroid data if loaded
	var ast = field_mgr.get_asteroid_data(id)
	if ast and not ast.is_depleted:
		ast.is_depleted = true
		ast.health_current = 0.0
		# Update visual if node exists
		if is_instance_valid(ast.node_ref) and ast.node_ref.has_method("_on_depleted"):
			ast.node_ref._on_depleted()


func _on_asteroid_health_batch(batch: Array) -> void:
	var field_mgr = GameManager._asteroid_field_mgr
	if field_mgr == null:
		return
	field_mgr.apply_server_health_batch(batch)


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


## Sends all NPCs to a peer after a short delay so the client has time to finish
## its system jump before receiving NPC data. Uses a SceneTreeTimer (1 second).
func _deferred_send_npcs_to_peer(peer_id: int, _fallback_system_id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	if not NetworkManager.peers.has(peer_id):
		return  # Peer disconnected during the delay
	# Use the peer's CURRENT system (may differ from initial assignment because
	# the client loads its actual system from the backend, overriding spawn_sys).
	var peer_sys: int = NetworkManager.peers[peer_id].system_id
	if peer_sys < 0:
		return  # Peer hasn't reported a valid system yet
	if npc_authority:
		# Ensure NPCs exist for the peer's system (spawns remote NPCs if needed)
		npc_authority.ensure_system_npcs(peer_sys)
		npc_authority.send_all_npcs_to_peer(peer_id, peer_sys)
		# Send current asteroid health state (cooperative mining sync)
		npc_authority.send_asteroid_health_to_peer(peer_id, peer_sys)
