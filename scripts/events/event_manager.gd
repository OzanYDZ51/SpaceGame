class_name EventManager
extends Node

# =============================================================================
# Event Manager — Spawns and tracks random events (pirate convoys etc.)
# Child of GameplayIntegrator. Server-only spawning logic.
# Convoys travel long linear routes across the system at max speed.
# =============================================================================

signal event_started(event_data: EventData)
signal event_completed(event_data: EventData)  # leader destroyed
signal event_expired(event_data: EventData)    # timeout
signal event_npc_killed(npc_id: StringName, event_data: EventData)  # individual NPC kill

var _active_events: Dictionary = {}  # event_id -> EventData
var _event_counter: int = 0
var _check_timer: float = 0.0
const CHECK_INTERVAL: float = 5.0

# Periodic respawn: try to spawn a new event every RESPAWN_INTERVAL seconds if none active
var _respawn_timer: float = 0.0
const RESPAWN_INTERVAL: float = 120.0  # 2 minutes
var _current_system_id: int = -1
var _current_danger_level: int = 0

# Client-side event tracking (received via RPC from server)
var _client_events: Dictionary = {}  # event_id -> dict (from server)

# Spawn distance from origin
const MIN_SPAWN_RADIUS: float = 20000.0
const MAX_SPAWN_RADIUS: float = 60000.0
const MIN_CLEARANCE: float = 5000.0  # Extra margin beyond entity radius

# Entity types to avoid when spawning
const _OBSTACLE_TYPES: Array = [
	EntityRegistrySystem.EntityType.STAR,
	EntityRegistrySystem.EntityType.PLANET,
	EntityRegistrySystem.EntityType.STATION,
	EntityRegistrySystem.EntityType.JUMP_GATE,
	EntityRegistrySystem.EntityType.ASTEROID_BELT,
]

# Route travel: convoy flies from A to B across the system
const CONVOY_SPAWN_DIST_MIN: float = 8000.0   # 8 km — spawn closer to player
const CONVOY_SPAWN_DIST_MAX: float = 20000.0  # 20 km
const ROUTE_WAYPOINT_COUNT: int = 5

# Map entity position update
var _position_update_timer: float = 0.0
const POSITION_UPDATE_INTERVAL: float = 0.5


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		if not _active_events.is_empty():
			_check_event_timeouts()
		# Client safety: expire stale events even if server RPC was missed
		if not _client_events.is_empty():
			_check_client_event_timeouts()

	# Periodic respawn attempt when no events are active
	if _current_system_id >= 0 and _active_events.is_empty():
		_respawn_timer += delta
		if _respawn_timer >= RESPAWN_INTERVAL:
			_respawn_timer = 0.0
			_try_spawn_event()

	# Update event marker positions on the map (follow the leader)
	if not _active_events.is_empty() or not _client_events.is_empty():
		_position_update_timer += delta
		if _position_update_timer >= POSITION_UPDATE_INTERVAL:
			_position_update_timer = 0.0
			_update_event_positions()


# =============================================================================
# PUBLIC
# =============================================================================

func on_system_loaded(system_id: int, danger_level: int) -> void:
	_current_system_id = system_id
	_current_danger_level = danger_level
	_respawn_timer = 0.0

	# Only server spawns events
	if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
		return

	_try_spawn_event()


func _try_spawn_event() -> void:
	if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
		return
	if not _active_events.is_empty():
		return
	if _current_system_id < 0:
		return

	var chance: float = EventDefinitions.get_spawn_chance(_current_danger_level)
	if chance <= 0.0:
		return
	if randf() > chance:
		return

	var tier: int = EventDefinitions.roll_tier_for_danger(_current_danger_level)
	_spawn_pirate_convoy(_current_system_id, tier)


func on_system_unloading() -> void:
	_current_system_id = -1
	_current_danger_level = 0
	_respawn_timer = 0.0
	var ids := _active_events.keys().duplicate()
	for eid in ids:
		_cleanup_event(eid, false)

	# Clean up client-side event markers
	for eid in _client_events.keys():
		EntityRegistry.unregister(eid)
	_client_events.clear()


func get_event(event_id: String) -> EventData:
	return _active_events.get(event_id)


# =============================================================================
# SPAWN LOGIC
# =============================================================================

func _spawn_pirate_convoy(system_id: int, tier: int) -> void:
	_event_counter += 1
	var event_id: String = "evt_%d_%d" % [system_id, _event_counter]

	# Route crosses through the player zone: spawn on one side, destination on the other
	var obstacles := _gather_obstacles()
	var angle: float = randf() * TAU
	var spawn_dist: float = randf_range(CONVOY_SPAWN_DIST_MIN, CONVOY_SPAWN_DIST_MAX)
	var start_pos := Vector3(cos(angle) * spawn_dist, 0.0, sin(angle) * spawn_dist)
	var end_dist: float = randf_range(CONVOY_SPAWN_DIST_MIN, CONVOY_SPAWN_DIST_MAX)
	var end_pos := Vector3(cos(angle + PI) * end_dist, 0.0, sin(angle + PI) * end_dist)

	# Try to avoid obstacles at start/end
	for _attempt in 5:
		if _is_clear_of_obstacles(start_pos, obstacles) and _is_clear_of_obstacles(end_pos, obstacles):
			break
		angle += 0.3
		start_pos = Vector3(cos(angle) * spawn_dist, 0.0, sin(angle) * spawn_dist)
		end_pos = Vector3(cos(angle + PI) * end_dist, 0.0, sin(angle + PI) * end_dist)

	var start_universe: Array = FloatingOrigin.to_universe_pos(start_pos)

	var route_waypoints: Array[Vector3] = []
	for i in ROUTE_WAYPOINT_COUNT:
		var t: float = float(i) / float(ROUTE_WAYPOINT_COUNT - 1)
		var wp: Vector3 = start_pos.lerp(end_pos, t)
		wp.y += randf_range(-150.0, 150.0)
		route_waypoints.append(wp)

	# Create event data
	var evt := EventData.new()
	evt.event_id = event_id
	evt.event_type = &"pirate_convoy"
	evt.tier = tier
	evt.system_id = system_id
	evt.center_x = start_universe[0]
	evt.center_z = start_universe[2]
	evt.waypoints = route_waypoints
	evt.spawn_time = Time.get_unix_time_from_system()
	evt.duration = EventDefinitions.get_event_duration(tier)
	evt.faction = &"pirate"

	# Spawn NPCs
	var definition: Dictionary = EventDefinitions.get_convoy_definition(tier)
	_spawn_convoy_npcs(evt, definition, start_pos, route_waypoints)

	# Save immutable copy of all spawned NPC IDs for reliable cleanup
	evt.all_spawned_ids = evt.npc_ids.duplicate()

	_active_events[event_id] = evt

	# Register event entity on the map
	EntityRegistry.register(event_id, {
		"name": evt.get_display_name(),
		"type": EntityRegistrySystem.EntityType.EVENT,
		"pos_x": start_universe[0],
		"pos_z": start_universe[2],
		"color": evt.get_color(),
		"extra": {
			"event_id": event_id,
			"event_type": "pirate_convoy",
			"event_tier": tier,
		},
	})

	event_started.emit(evt)

	# Broadcast to all clients in this system
	if NetworkManager.is_server():
		var start_dict: Dictionary = evt.to_start_dict()
		for pid in NetworkManager.get_peers_in_system(system_id):
			NetworkManager._rpc_event_started.rpc_id(pid, start_dict)

	print("[EventManager] Pirate convoy T%d spawned — route %.0fkm, %d NPCs" % [tier, start_pos.distance_to(end_pos) / 1000.0, evt.npc_ids.size()])


func _spawn_convoy_npcs(evt: EventData, definition: Dictionary, start_pos: Vector3, route_waypoints: Array[Vector3]) -> void:
	var parent: Node = get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	var lod_mgr = _get_lod_manager()
	var cam_pos := Vector3.ZERO
	var cam = get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	# Spawn leader (freighter) — route_priority + no cruise
	var leader_id_name: StringName = definition["leader"]
	var leader_result := _spawn_single_npc(leader_id_name, start_pos, evt.faction, route_waypoints, parent, lod_mgr, cam_pos, true)
	var leader_npc_id: StringName = leader_result[0]
	var leader_ship: Node3D = leader_result[1]
	if leader_npc_id != &"":
		evt.leader_id = leader_npc_id
		evt.npc_ids.append(leader_npc_id)
		if leader_ship:
			leader_ship.cruise_disabled = true

	# Spawn escorts — FORMATION following the leader, no cruise
	var escort_idx: int = 0
	for group in definition["escorts"]:
		var ship_id: StringName = group["ship_id"]
		var count: int = group["count"]
		for i in count:
			escort_idx += 1
			var angle: float = TAU * float(escort_idx) / 10.0
			var dist: float = randf_range(200.0, 600.0)
			var offset := Vector3(cos(angle) * dist, randf_range(-50, 50), sin(angle) * dist)
			var pos: Vector3 = start_pos + offset

			# Escorts get no route — they follow the leader in formation
			var escort_result := _spawn_single_npc(ship_id, pos, evt.faction, [], parent, lod_mgr, cam_pos, false)
			var npc_id: StringName = escort_result[0]
			var escort_ship: Node3D = escort_result[1]
			if npc_id != &"":
				evt.npc_ids.append(npc_id)
				if escort_ship:
					escort_ship.cruise_disabled = true
					if leader_ship:
						var escort_brain = escort_ship.get_node_or_null("AIController")
						if escort_brain:
							escort_brain.formation_leader = leader_ship
							escort_brain.formation_offset = offset.normalized() * clampf(dist, 200.0, 400.0)
							escort_brain.current_state = AIController.State.FORMATION


func _spawn_single_npc(ship_id: StringName, pos: Vector3, faction: StringName, route_waypoints: Array[Vector3], parent: Node, lod_mgr, _cam_pos: Vector3, is_leader: bool) -> Array:
	var behavior: StringName = &"balanced" if is_leader else &"aggressive"

	# Always spawn full nodes — all NPCs are real ships with AI + physics
	var ship = ShipFactory.spawn_npc_ship(ship_id, behavior, pos, parent, faction)
	if ship:
		var brain = ship.get_node_or_null("AIController")
		if brain:
			if not route_waypoints.is_empty():
				brain.set_route(route_waypoints)
			if is_leader:
				brain.route_priority = true
		var npc_id := StringName(ship.name)
		ship.tree_exiting.connect(_on_npc_removed.bind(npc_id))
		_register_npc_on_server(npc_id, ship_id, faction, ship)
		# Mark in LOD manager so combat bridge won't target this NPC
		if lod_mgr and lod_mgr._ships.has(npc_id):
			lod_mgr._ships[npc_id].is_event_npc = true
		return [npc_id, ship]
	return [&"", null]


# =============================================================================
# MAP POSITION UPDATE (convoy moves, map marker follows)
# =============================================================================

func _update_event_positions() -> void:
	var lod_mgr = _get_lod_manager()

	# Server/offline: update from authoritative EventData
	for evt in _active_events.values():
		if not evt.is_active or evt.leader_id == &"":
			continue
		var leader_pos: Vector3 = _get_npc_position(evt.leader_id, lod_mgr)
		if leader_pos == Vector3.ZERO:
			continue
		var leader_vel: Vector3 = _get_npc_velocity(evt.leader_id, lod_mgr)
		var upos: Array = FloatingOrigin.to_universe_pos(leader_pos)
		evt.center_x = upos[0]
		evt.center_z = upos[2]
		# Update EntityRegistry directly (dict is by reference)
		var ent: Dictionary = EntityRegistry.get_entity(evt.event_id)
		if not ent.is_empty():
			ent["pos_x"] = upos[0]
			ent["pos_z"] = upos[2]
			# Store velocity for smooth extrapolation between updates
			ent["vel_x"] = float(leader_vel.x)
			ent["vel_y"] = float(leader_vel.y)
			ent["vel_z"] = float(leader_vel.z)

	# Client: update marker position from leader NPC (synced via NpcAuthority)
	for eid in _client_events:
		var cevt: Dictionary = _client_events[eid]
		var lid: StringName = StringName(cevt.get("lid", ""))
		if lid == &"":
			continue
		var leader_pos: Vector3 = _get_npc_position(lid, lod_mgr)
		if leader_pos == Vector3.ZERO:
			continue
		var leader_vel: Vector3 = _get_npc_velocity(lid, lod_mgr)
		var upos: Array = FloatingOrigin.to_universe_pos(leader_pos)
		var ent: Dictionary = EntityRegistry.get_entity(eid)
		if not ent.is_empty():
			ent["pos_x"] = upos[0]
			ent["pos_z"] = upos[2]
			ent["vel_x"] = float(leader_vel.x)
			ent["vel_y"] = float(leader_vel.y)
			ent["vel_z"] = float(leader_vel.z)


func _get_npc_position(npc_id: StringName, lod_mgr = null) -> Vector3:
	if lod_mgr == null:
		lod_mgr = _get_lod_manager()
	if lod_mgr and lod_mgr._ships.has(npc_id):
		var data = lod_mgr._ships[npc_id]
		if is_instance_valid(data.node_ref):
			return data.node_ref.global_position
		return data.position
	return Vector3.ZERO


func _get_npc_velocity(npc_id: StringName, lod_mgr = null) -> Vector3:
	if lod_mgr == null:
		lod_mgr = _get_lod_manager()
	if lod_mgr and lod_mgr._ships.has(npc_id):
		var data = lod_mgr._ships[npc_id]
		if is_instance_valid(data.node_ref) and data.node_ref is RigidBody3D:
			return (data.node_ref as RigidBody3D).linear_velocity
		return data.velocity
	return Vector3.ZERO


# =============================================================================
# NPC DEATH / REMOVAL TRACKING
# =============================================================================

## Called by NpcAuthority.npc_killed signal — works for ALL NPCs (data-only + full node).
## For full-node NPCs, _on_npc_removed (via tree_exiting) may fire later in the same
## frame. The is_active guard and npc_ids.has() check prevent double processing.
func _on_server_npc_killed(npc_id: StringName, killer_pid: int) -> void:
	_on_npc_removed(npc_id, killer_pid)


func _on_npc_removed(npc_id: StringName, killer_pid: int = 0) -> void:
	for evt in _active_events.values():
		if not evt.is_active:
			continue
		if npc_id not in evt.npc_ids:
			continue

		evt.npc_ids.erase(npc_id)
		event_npc_killed.emit(npc_id, evt)

		# Check if it's the leader
		if npc_id == evt.leader_id:
			evt.is_active = false
			_cleanup_event(evt.event_id, true, killer_pid)
			return

		# If all escorts are dead, event is also done
		if evt.npc_ids.is_empty():
			evt.is_active = false
			_cleanup_event(evt.event_id, true, killer_pid)
			return


# =============================================================================
# TIMEOUT / CLEANUP
# =============================================================================

func _check_event_timeouts() -> void:
	var expired_ids: Array[String] = []
	var completed_ids: Array[String] = []

	for evt in _active_events.values():
		if not evt.is_active:
			continue
		if evt.is_expired():
			expired_ids.append(evt.event_id)
			continue
		# Safety net: if leader NPC vanished without a kill signal, treat as expired
		# (no rewards). This prevents free credits from edge-case removals.
		if evt.leader_id != &"" and not _npc_exists(evt.leader_id):
			print("[EventManager] WARNING: Safety net — leader %s vanished without kill signal, expiring event %s" % [evt.leader_id, evt.event_id])
			expired_ids.append(evt.event_id)
			continue
		# Check for dead escorts too
		var dead_ids: Array[StringName] = []
		for npc_id in evt.npc_ids:
			if not _npc_exists(npc_id):
				dead_ids.append(npc_id)
		for did in dead_ids:
			evt.npc_ids.erase(did)
			event_npc_killed.emit(did, evt)
		if evt.npc_ids.is_empty():
			print("[EventManager] WARNING: Safety net — all NPCs vanished without kill signal, expiring event %s" % evt.event_id)
			expired_ids.append(evt.event_id)

	for eid in expired_ids:
		_cleanup_event(eid, false)
	for eid in completed_ids:
		_cleanup_event(eid, true)


func _npc_exists(npc_id: StringName) -> bool:
	# Check LOD manager first (most authoritative for LOD-managed ships)
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr:
		if lod_mgr._ships.has(npc_id):
			var data = lod_mgr._ships[npc_id]
			if data.is_dead:
				return false
			# Promoted to full node but node was freed (killed)
			if data.node_ref != null and not is_instance_valid(data.node_ref):
				return false
			return true
		# Not in LOD manager — might have been unregistered (dead)
		return false
	# Fallback: check EntityRegistry
	var ent: Dictionary = EntityRegistry.get_entity(String(npc_id))
	return not ent.is_empty()


func _cleanup_event(event_id: String, was_completed: bool, killer_pid: int = 0) -> void:
	var evt: EventData = _active_events.get(event_id)
	if evt == null:
		return

	evt.is_active = false

	# Despawn ALL NPCs that were ever spawned for this event — use all_spawned_ids
	# (npc_ids gets mutated by _on_npc_removed when individual NPCs die, so killed
	# NPCs would be missing from it, leaving ghost markers on the map).
	var lod_mgr = _get_lod_manager()
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	var is_server: bool = NetworkManager.is_server()

	var ids_to_clean: Array[StringName] = evt.all_spawned_ids if not evt.all_spawned_ids.is_empty() else evt.npc_ids
	for npc_id in ids_to_clean:
		# Broadcast despawn to clients so they remove their puppet (prevents ghost NPCs)
		if is_server and npc_auth and npc_auth._npcs.has(npc_id):
			var death_pos: Array = [0.0, 0.0, 0.0]
			if lod_mgr:
				var ld: ShipLODData = lod_mgr.get_ship_data(npc_id)
				if ld:
					death_pos = FloatingOrigin.to_universe_pos(ld.position)
			npc_auth.broadcast_npc_death(npc_id, 0, death_pos, [], evt.system_id)
			npc_auth.unregister_npc(npc_id)

		if lod_mgr:
			lod_mgr.unregister_ship(npc_id)
		else:
			var node = get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))
			if node and is_instance_valid(node):
				node.queue_free()

		# Safety: always ensure EntityRegistry entry is gone (even if LOD manager
		# already cleaned it — unregister is a no-op for missing IDs)
		EntityRegistry.unregister(String(npc_id))

	# Unregister map entity
	EntityRegistry.unregister(event_id)

	# Broadcast event end to all clients in this system
	if is_server:
		var bonus: int = EventDefinitions.get_leader_bonus_credits(evt.tier) if was_completed else 0
		var end_dict: Dictionary = EventData.make_end_dict(
			event_id, String(evt.event_type), evt.tier,
			was_completed, killer_pid, bonus, evt.system_id
		)
		for pid in NetworkManager.get_peers_in_system(evt.system_id):
			NetworkManager._rpc_event_ended.rpc_id(pid, end_dict)

	if was_completed:
		event_completed.emit(evt)
		print("[EventManager] Event %s COMPLETED (leader destroyed, killer_pid=%d)" % [event_id, killer_pid])
	else:
		event_expired.emit(evt)
		print("[EventManager] Event %s expired/cleaned up" % event_id)

	_active_events.erase(event_id)


# =============================================================================
# HELPERS
# =============================================================================

func _find_safe_spawn_position() -> Vector3:
	var obstacles := _gather_obstacles()

	# Adapt spawn radius if player is too close to a large obstacle
	var min_dist: float = MIN_SPAWN_RADIUS
	var max_dist: float = MAX_SPAWN_RADIUS
	for obs in obstacles:
		var player_dist: float = obs[0].length()  # distance from player to obstacle center
		var exclusion: float = obs[1]              # radius + clearance
		if player_dist < exclusion:
			var needed: float = exclusion - player_dist + MIN_CLEARANCE
			min_dist = maxf(min_dist, needed)
			max_dist = maxf(max_dist, needed + 40000.0)

	var candidate := Vector3.ZERO
	for _attempt in 20:
		var angle: float = randf() * TAU
		var dist: float = randf_range(min_dist, max_dist)
		candidate = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if _is_clear_of_obstacles(candidate, obstacles):
			return candidate
	return candidate


## Build a list of [local_pos: Vector3, exclusion_radius: float] for all spatial entities.
func _gather_obstacles() -> Array:
	var result: Array = []
	for etype in _OBSTACLE_TYPES:
		for ent in EntityRegistry.get_by_type(etype):
			var lp := FloatingOrigin.to_local_pos([ent["pos_x"], ent.get("pos_y", 0.0), ent["pos_z"]])
			var radius: float = ent.get("radius", 0.0)
			result.append([lp, radius + MIN_CLEARANCE])
	return result


func _is_clear_of_obstacles(pos: Vector3, obstacles: Array) -> bool:
	for obs in obstacles:
		if pos.distance_to(obs[0]) < obs[1]:
			return false
	return true


func _get_lod_manager():
	var mgr = GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr.has_method("register_ship"):
		return mgr
	return null


# =============================================================================
# CLIENT-SIDE EVENT TRACKING (received via RPC)
# =============================================================================

## Called when the server broadcasts an event start to this client.
func on_client_event_started(event_dict: Dictionary) -> void:
	var eid: String = event_dict.get("eid", "")
	if eid == "":
		return
	_client_events[eid] = event_dict

	# Register map marker
	EntityRegistry.register(eid, {
		"name": event_dict.get("name", "ÉVÉNEMENT"),
		"type": EntityRegistrySystem.EntityType.EVENT,
		"pos_x": event_dict.get("cx", 0.0),
		"pos_z": event_dict.get("cz", 0.0),
		"color": Color.from_string(event_dict.get("color", "ffff00"), Color.YELLOW),
		"extra": {
			"event_id": eid,
			"event_type": event_dict.get("type", "pirate_convoy"),
			"event_tier": event_dict.get("tier", 1),
		},
	})
	print("[EventManager] Client received event start: %s" % eid)


## Called when the server broadcasts an event end to this client.
func on_client_event_ended(event_dict: Dictionary) -> void:
	var eid: String = event_dict.get("eid", "")
	if eid == "":
		return
	_client_events.erase(eid)
	EntityRegistry.unregister(eid)
	print("[EventManager] Client received event end: %s (done=%s)" % [eid, str(event_dict.get("done", false))])


## Client safety net: expire stale events if the server's _rpc_event_ended was missed.
func _check_client_event_timeouts() -> void:
	var now: float = Time.get_unix_time_from_system()
	var expired: Array[String] = []
	for eid: String in _client_events:
		var cevt: Dictionary = _client_events[eid]
		var t0: float = cevt.get("t0", 0.0)
		var dur: float = cevt.get("dur", 600.0)
		# 15s grace period beyond official duration for network delays
		if t0 > 0.0 and now > t0 + dur + 15.0:
			expired.append(eid)
	for eid in expired:
		_client_events.erase(eid)
		EntityRegistry.unregister(eid)
		print("[EventManager] Client safety: expired stale event %s" % eid)


## Server-side: send all active events to a peer that just joined (mid-event join).
func send_active_events_to_peer(peer_id: int) -> void:
	for evt in _active_events.values():
		if not evt.is_active:
			continue
		var start_dict: Dictionary = evt.to_start_dict()
		NetworkManager._rpc_event_started.rpc_id(peer_id, start_dict)


var _npc_auth_connected: bool = false

func _register_npc_on_server(npc_id: StringName, sid: StringName, fac: StringName, ship_node: Node3D = null) -> void:
	if not NetworkManager.is_server():
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth == null:
		return

	# Connect to NpcAuthority death signal once — catches data-only NPC kills
	# that don't emit tree_exiting (no node to free).
	if not _npc_auth_connected:
		npc_auth.npc_killed.connect(_on_server_npc_killed)
		_npc_auth_connected = true

	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0
	npc_auth.register_npc(npc_id, system_id, sid, fac)
	npc_auth.notify_spawn_to_peers(npc_id, system_id)
	if ship_node:
		npc_auth.connect_npc_fire_relay(npc_id, ship_node)
