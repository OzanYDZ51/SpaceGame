class_name NpcAuthority
extends Node

# =============================================================================
# NPC Authority - Thin coordinator for server-side NPC management.
# Runs ONLY on the dedicated server.
# Delegates to sub-managers:
#   _broadcaster  → NpcStateBroadcaster  (state sync, fire relay)
#   _combat       → NpcCombatValidator   (hit validation, kills, loot)
#   _fleet        → NpcFleetAuthority    (fleet tracking, deploy/retrieve/command)
#   _backend      → NpcFleetBackend      (backend sync, persistence)
#   _asteroids    → NpcAsteroidAuthority  (asteroid health, mining validation)
# =============================================================================

@warning_ignore("unused_signal")
signal npc_killed(npc_id: StringName, killer_pid: int)

const ENCOUNTER_RESPAWN_DELAY: float = Constants.NPC_ENCOUNTER_RESPAWN_DELAY
const ENCOUNTER_RESPAWN_MAX_DELAY: float = Constants.NPC_ENCOUNTER_RESPAWN_MAX

var _active: bool = false

# Sub-managers (RefCounted)
var _broadcaster: NpcStateBroadcaster = null
var _combat: NpcCombatValidator = null
var _fleet: NpcFleetAuthority = null
var _backend: NpcFleetBackend = null
var _asteroids: NpcAsteroidAuthority = null

# npc_id -> { system_id, ship_id, faction, node_ref (if LOD0/1) }
var _npcs: Dictionary = {}
# system_id -> Array[StringName] npc_ids
var _npcs_by_system: Dictionary = {}

# Peer system tracking: peer_id -> last known system_id
var _peer_systems: Dictionary = {}

# Encounter respawn tracking: "system_id:encounter_key" -> { time: unix_timestamp, kills: int }
var _destroyed_encounter_npcs: Dictionary = {}
var _respawn_cleanup_timer: float = 60.0

# Virtual station tracking: system_id -> Array[String] of virtual station entity IDs
var _virtual_stations: Dictionary = {}


func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_check_activation)
	_check_activation()


func _check_activation() -> void:
	if NetworkManager.is_server() and not _active:
		_active = true

		# Create backend client
		var backend_client = ServerBackendClient.new()
		backend_client.name = "ServerBackendClient"
		add_child(backend_client)

		# Create sub-managers
		_broadcaster = NpcStateBroadcaster.new()
		_broadcaster.setup(self)

		_combat = NpcCombatValidator.new()
		_combat.setup(self)

		_fleet = NpcFleetAuthority.new()
		_fleet.setup(self)

		_backend = NpcFleetBackend.new()
		_backend.setup(self, backend_client)

		_asteroids = NpcAsteroidAuthority.new()
		_asteroids.setup(self)

		print("NpcAuthority: Activated (server mode)")
		_backend.load_deployed_fleet_ships_from_backend()


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_broadcaster.tick(delta)
	_asteroids.tick(delta)
	_backend.tick(delta)

	# Periodic encounter respawn cleanup (every 60s)
	_respawn_cleanup_timer -= delta
	if _respawn_cleanup_timer <= 0.0:
		_respawn_cleanup_timer = 60.0
		_cleanup_expired_respawns()
		_combat.cleanup_stale_hits()


# =========================================================================
# NPC REGISTRATION
# =========================================================================

func register_npc(npc_id: StringName, system_id: int, ship_id: StringName, faction: StringName) -> void:
	_npcs[npc_id] = {
		"system_id": system_id,
		"ship_id": ship_id,
		"faction": faction,
	}
	if not _npcs_by_system.has(system_id):
		_npcs_by_system[system_id] = []
	var sys_list: Array = _npcs_by_system[system_id]
	if not sys_list.has(npc_id):
		sys_list.append(npc_id)


func unregister_npc(npc_id: StringName) -> void:
	if not _npcs.has(npc_id):
		return
	var info: Dictionary = _npcs[npc_id]
	var sys_id: int = info.get("system_id", -1)
	if _npcs_by_system.has(sys_id):
		var sys_list: Array = _npcs_by_system[sys_id]
		sys_list.erase(npc_id)
		if sys_list.is_empty():
			_npcs_by_system.erase(sys_id)
	_npcs.erase(npc_id)


func clear_system_npcs(system_id: int) -> void:
	if _npcs_by_system.has(system_id):
		var ids: Array = _npcs_by_system[system_id].duplicate()
		for npc_id in ids:
			_npcs.erase(npc_id)
		_npcs_by_system.erase(system_id)
	_asteroids.clear_system_asteroid_health(system_id)
	if _virtual_stations.has(system_id):
		for vst_id in _virtual_stations[system_id]:
			EntityRegistry.unregister(vst_id)
		_virtual_stations.erase(system_id)


# =========================================================================
# FORWARDING: State Broadcasting
# =========================================================================

func connect_npc_fire_relay(npc_id: StringName, ship_node: Node3D) -> void:
	if not _active or _broadcaster == null:
		return
	_broadcaster.connect_npc_fire_relay(npc_id, ship_node)


func notify_spawn_to_peers(npc_id: StringName, system_id: int) -> void:
	if _broadcaster:
		_broadcaster.notify_spawn_to_peers(npc_id, system_id)


func send_all_npcs_to_peer(peer_id: int, system_id: int) -> void:
	if _broadcaster:
		_broadcaster.send_all_npcs_to_peer(peer_id, system_id)


func relay_fire_event(sender_pid: int, weapon_name: String, fire_pos: Array, fire_dir: Array) -> void:
	if not _active:
		return
	if _broadcaster:
		_broadcaster.relay_fire_event(sender_pid, weapon_name, fire_pos, fire_dir)


func relay_scanner_pulse(sender_pid: int, scan_pos: Array) -> void:
	if not _active:
		return
	if _broadcaster:
		_broadcaster.relay_scanner_pulse(sender_pid, scan_pos)


func broadcast_hit_effect(target_id: String, exclude_pid: int, hit_dir: Array, shield_absorbed: bool, system_id: int) -> void:
	if not _active:
		return
	if _broadcaster:
		_broadcaster.broadcast_hit_effect(target_id, exclude_pid, hit_dir, shield_absorbed, system_id)


# =========================================================================
# FORWARDING: Combat Validation
# =========================================================================

func validate_hit_claim(sender_pid: int, target_npc: String, weapon_name: String, claimed_damage: float, hit_dir: Array) -> void:
	if not _active:
		return
	if _combat:
		_combat.validate_hit_claim(sender_pid, target_npc, weapon_name, claimed_damage, hit_dir)


func _on_npc_killed(npc_id: StringName, killer_pid: int, weapon_name: String = "", killer_npc_id: String = "", cached_death_pos: Array = []) -> void:
	if _combat:
		_combat._on_npc_killed(npc_id, killer_pid, weapon_name, killer_npc_id, cached_death_pos)


func broadcast_npc_death(npc_id: StringName, killer_pid: int, death_pos: Array, loot: Array, system_id: int = -1) -> void:
	if _combat:
		_combat._broadcast_npc_death(npc_id, killer_pid, death_pos, loot, system_id)


func _get_effective_hp(ship_id: StringName) -> Dictionary:
	if _combat:
		return _combat.get_effective_hp(ship_id)
	return {"shield_total": 500.0, "hull_total": 1000.0}


# =========================================================================
# FORWARDING: Fleet Management
# =========================================================================

func register_fleet_npc(npc_id: StringName, owner_pid: int, fleet_index: int) -> void:
	if _fleet:
		_fleet.register_fleet_npc(npc_id, owner_pid, fleet_index)


func is_fleet_npc(npc_id: StringName) -> bool:
	return _fleet.is_fleet_npc(npc_id) if _fleet else false


func get_fleet_npc_owner(npc_id: StringName) -> int:
	return _fleet.get_fleet_npc_owner(npc_id) if _fleet else -1


func on_player_disconnected(uuid: String, old_pid: int) -> void:
	if _fleet:
		_fleet.on_player_disconnected(uuid, old_pid)


func on_player_reconnected(uuid: String, new_pid: int) -> void:
	if _fleet:
		_fleet.on_player_reconnected(uuid, new_pid)


func handle_fleet_deploy_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary, ship_data: Dictionary = {}) -> void:
	if not _active:
		return
	if _fleet:
		_fleet.handle_fleet_deploy_request(sender_pid, fleet_index, cmd, params, ship_data)


func handle_fleet_retrieve_request(sender_pid: int, fleet_index: int) -> void:
	if not _active:
		return
	if _fleet:
		_fleet.handle_fleet_retrieve_request(sender_pid, fleet_index)


func handle_fleet_npc_self_docked(npc_id: StringName, fleet_index: int) -> void:
	if not _active:
		return
	if _fleet:
		_fleet.handle_fleet_npc_self_docked(npc_id, fleet_index)


func handle_fleet_command_request(sender_pid: int, fleet_index: int, cmd: StringName, params: Dictionary) -> void:
	if not _active:
		return
	if _fleet:
		_fleet.handle_fleet_command_request(sender_pid, fleet_index, cmd, params)


## Server -> Client: Fleet status on reconnect.
@rpc("authority", "reliable")
func _rpc_fleet_reconnect_status(alive: Array, deaths: Array) -> void:
	var fleet_mgr = GameManager.get_node_or_null("FleetDeploymentManager")
	if fleet_mgr:
		fleet_mgr.apply_reconnect_fleet_status(alive, deaths)


# =========================================================================
# FORWARDING: Asteroid / Mining
# =========================================================================

func relay_mining_beam(sender_pid: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	if not _active:
		return
	if _asteroids:
		_asteroids.relay_mining_beam(sender_pid, is_active, source_pos, target_pos)


func broadcast_asteroid_depleted(asteroid_id: String, system_id: int, sender_pid: int) -> void:
	if not _active:
		return
	if _asteroids:
		_asteroids.broadcast_asteroid_depleted(asteroid_id, system_id, sender_pid)


func handle_mining_damage_claims(sender_pid: int, claims: Array) -> void:
	if not _active:
		return
	if _asteroids:
		_asteroids.handle_mining_damage_claims(sender_pid, claims)


func send_asteroid_health_to_peer(peer_id: int, system_id: int) -> void:
	if _asteroids:
		_asteroids.send_asteroid_health_to_peer(peer_id, system_id)


func clear_system_asteroid_health(system_id: int) -> void:
	if _asteroids:
		_asteroids.clear_system_asteroid_health(system_id)


func clean_peer_mining_tracking(peer_id: int) -> void:
	if _asteroids:
		_asteroids.clean_peer_mining_tracking(peer_id)


func apply_ai_mining_damage(system_id: int, asteroid_id: String, damage: float, health_max: float) -> void:
	if not _active:
		return
	if _asteroids:
		_asteroids.apply_ai_mining_damage(system_id, asteroid_id, damage, health_max)


# =========================================================================
# REMOTE SYSTEM NPC SPAWNING
# =========================================================================

func ensure_system_npcs(system_id: int) -> void:
	if not _active:
		return
	if _npcs_by_system.has(system_id) and not _npcs_by_system[system_id].is_empty():
		return
	var encounter_mgr = GameManager.get_node_or_null("EncounterManager")
	if encounter_mgr:
		encounter_mgr.spawn_for_remote_system(system_id)


func _cleanup_expired_respawns() -> void:
	var now: float = Time.get_unix_time_from_system()
	var expired: Array = []
	for key in _destroyed_encounter_npcs:
		var entry = _destroyed_encounter_npcs[key]
		var respawn_time: float = entry["time"] if entry is Dictionary else float(entry)
		if now >= respawn_time:
			expired.append(key)
	for key in expired:
		_destroyed_encounter_npcs.erase(key)


func _check_peer_system_changes() -> void:
	for pid in NetworkManager.peers:
		var state = NetworkManager.peers[pid]
		var prev_sys: int = _peer_systems.get(pid, -1)
		if state.system_id != prev_sys:
			_peer_systems[pid] = state.system_id
			if state.system_id >= 0:
				ensure_system_npcs(state.system_id)


# =============================================================================
# ADMIN COMMANDS
# =============================================================================

func admin_reset_all_npcs() -> void:
	print("[NpcAuthority] admin_reset_all_npcs: clearing %d NPCs (%d fleet)" % [_npcs.size(), _fleet._fleet_npcs.size() if _fleet else 0])

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")

	if _active:
		var all_ids: Array = _npcs.keys().duplicate()
		for npc_id in all_ids:
			if lod_mgr:
				lod_mgr.unregister_ship(npc_id)
			else:
				EntityRegistry.unregister(String(npc_id))

		_npcs.clear()
		_npcs_by_system.clear()
		if _fleet:
			_fleet._fleet_npcs.clear()
			_fleet._fleet_npcs_by_owner.clear()
		_destroyed_encounter_npcs.clear()

		for pid in NetworkManager.peers:
			NetworkManager._rpc_admin_npcs_reset.rpc_id(pid)
	else:
		if lod_mgr:
			var all_ids: Array[StringName] = lod_mgr.get_all_ship_ids()
			for npc_id in all_ids:
				if str(npc_id).begins_with("NPC_"):
					lod_mgr.unregister_ship(npc_id)
		_destroyed_encounter_npcs.clear()

	var enc_mgr = GameManager.get_node_or_null("EncounterManager")
	if enc_mgr:
		enc_mgr.admin_clear_and_respawn()

	print("[NpcAuthority] admin_reset_all_npcs: done")
