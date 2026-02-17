class_name EventManager
extends Node

# =============================================================================
# Event Manager — Spawns and tracks random events (pirate convoys etc.)
# Child of GameplayIntegrator. Server-only spawning logic.
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

# Spawn distance from origin
const MIN_SPAWN_RADIUS: float = 20000.0
const MAX_SPAWN_RADIUS: float = 60000.0
const MIN_DIST_FROM_OBJECTS: float = 10000.0
const WAYPOINT_RADIUS_MIN: float = 5000.0
const WAYPOINT_RADIUS_MAX: float = 15000.0


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		if not _active_events.is_empty():
			_check_event_timeouts()

	# Periodic respawn attempt when no events are active
	if _current_system_id >= 0 and _active_events.is_empty():
		_respawn_timer += delta
		if _respawn_timer >= RESPAWN_INTERVAL:
			_respawn_timer = 0.0
			_try_spawn_event()


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


func get_event(event_id: String) -> EventData:
	return _active_events.get(event_id)


# =============================================================================
# SPAWN LOGIC
# =============================================================================

func _spawn_pirate_convoy(system_id: int, tier: int) -> void:
	_event_counter += 1
	var event_id: String = "evt_%d_%d" % [system_id, _event_counter]

	# Pick spawn position — polar random, far from origin
	var center := _find_safe_spawn_position()
	var center_universe: Array = FloatingOrigin.to_universe_pos(center)

	# Generate 2-3 waypoints around center
	var wp_count: int = 2 + (tier - 1)  # tier1=2, tier2=3, tier3=3
	wp_count = clampi(wp_count, 2, 3)
	var waypoints: Array[Vector3] = []
	for i in wp_count:
		var angle: float = TAU * float(i) / float(wp_count) + randf() * 0.5
		var dist: float = randf_range(WAYPOINT_RADIUS_MIN, WAYPOINT_RADIUS_MAX)
		waypoints.append(center + Vector3(cos(angle) * dist, randf_range(-200, 200), sin(angle) * dist))

	# Create event data
	var evt := EventData.new()
	evt.event_id = event_id
	evt.event_type = &"pirate_convoy"
	evt.tier = tier
	evt.system_id = system_id
	evt.center_x = center_universe[0]
	evt.center_z = center_universe[2]
	evt.waypoints = waypoints
	evt.spawn_time = Time.get_unix_time_from_system()
	evt.duration = EventDefinitions.get_event_duration(tier)
	evt.faction = &"pirate"

	# Spawn NPCs
	var definition: Dictionary = EventDefinitions.get_convoy_definition(tier)
	_spawn_convoy_npcs(evt, definition, center)

	_active_events[event_id] = evt

	# Register event entity on the map
	EntityRegistry.register(event_id, {
		"name": evt.get_display_name(),
		"type": EntityRegistrySystem.EntityType.EVENT,
		"pos_x": center_universe[0],
		"pos_z": center_universe[2],
		"color": evt.get_color(),
		"extra": {
			"event_id": event_id,
			"event_type": "pirate_convoy",
			"event_tier": tier,
		},
	})

	event_started.emit(evt)
	print("[EventManager] Pirate convoy T%d spawned at %.0f, %.0f (%d NPCs)" % [tier, center.x, center.z, evt.npc_ids.size()])


func _spawn_convoy_npcs(evt: EventData, definition: Dictionary, center: Vector3) -> void:
	var parent: Node = get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	var lod_mgr = _get_lod_manager()
	var cam_pos := Vector3.ZERO
	var cam = get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	# Spawn leader (freighter)
	var leader_id_name: StringName = definition["leader"]
	var leader_pos: Vector3 = center
	var leader_npc_id := _spawn_single_npc(leader_id_name, leader_pos, evt.faction, center, evt.waypoints, parent, lod_mgr, cam_pos, true)
	if leader_npc_id != &"":
		evt.leader_id = leader_npc_id
		evt.npc_ids.append(leader_npc_id)

	# Spawn escorts
	var escort_idx: int = 0
	for group in definition["escorts"]:
		var ship_id: StringName = group["ship_id"]
		var count: int = group["count"]
		for i in count:
			escort_idx += 1
			var angle: float = TAU * float(escort_idx) / 10.0
			var dist: float = randf_range(200.0, 600.0)
			var offset := Vector3(cos(angle) * dist, randf_range(-50, 50), sin(angle) * dist)
			var pos: Vector3 = center + offset

			var npc_id := _spawn_single_npc(ship_id, pos, evt.faction, center, evt.waypoints, parent, lod_mgr, cam_pos, false)
			if npc_id != &"":
				evt.npc_ids.append(npc_id)


func _spawn_single_npc(ship_id: StringName, pos: Vector3, faction: StringName, patrol_center: Vector3, _waypoints: Array[Vector3], parent: Node, lod_mgr, cam_pos: Vector3, is_leader: bool) -> StringName:
	var patrol_radius: float = WAYPOINT_RADIUS_MAX
	var behavior: StringName = &"balanced" if is_leader else &"balanced"

	# On dedicated server, always spawn full nodes
	var spawn_data_only: bool = lod_mgr != null and not NetworkManager.is_server() and cam_pos.distance_to(pos) > ShipLODManager.LOD1_DISTANCE
	if spawn_data_only:
		var lod_data = ShipFactory.create_npc_data_only(ship_id, behavior, pos, faction)
		if lod_data:
			lod_data.ai_patrol_center = patrol_center
			lod_data.ai_patrol_radius = patrol_radius
			lod_data.velocity = Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			lod_mgr.register_ship(lod_data.id, lod_data)
			_register_npc_on_server(lod_data.id, ship_id, faction)
			return lod_data.id
	else:
		var ship = ShipFactory.spawn_npc_ship(ship_id, behavior, pos, parent, faction)
		if ship:
			var brain = ship.get_node_or_null("AIBrain")
			if brain:
				brain.set_patrol_area(patrol_center, patrol_radius)
			var npc_id := StringName(ship.name)
			ship.tree_exiting.connect(_on_npc_removed.bind(npc_id))
			_register_npc_on_server(npc_id, ship_id, faction, ship)
			return npc_id
	return &""


# =============================================================================
# NPC DEATH / REMOVAL TRACKING
# =============================================================================

func _on_npc_removed(npc_id: StringName) -> void:
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
			_cleanup_event(evt.event_id, true)
			return

		# If all escorts are dead, event is also done
		if evt.npc_ids.is_empty():
			evt.is_active = false
			_cleanup_event(evt.event_id, true)
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
		# Safety net: check if leader NPC still exists (handles edge cases)
		if evt.leader_id != &"" and not _npc_exists(evt.leader_id):
			evt.npc_ids.erase(evt.leader_id)
			event_npc_killed.emit(evt.leader_id, evt)
			completed_ids.append(evt.event_id)
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
			completed_ids.append(evt.event_id)

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


func _cleanup_event(event_id: String, was_completed: bool) -> void:
	var evt: EventData = _active_events.get(event_id)
	if evt == null:
		return

	evt.is_active = false

	# Despawn remaining NPCs
	var lod_mgr = _get_lod_manager()
	for npc_id in evt.npc_ids:
		if lod_mgr:
			lod_mgr.unregister_ship(npc_id)
		else:
			var node = get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))
			if node and is_instance_valid(node):
				node.queue_free()

	# Unregister map entity
	EntityRegistry.unregister(event_id)

	if was_completed:
		event_completed.emit(evt)
		print("[EventManager] Event %s COMPLETED (leader destroyed)" % event_id)
	else:
		event_expired.emit(evt)
		print("[EventManager] Event %s expired/cleaned up" % event_id)

	_active_events.erase(event_id)


# =============================================================================
# HELPERS
# =============================================================================

func _find_safe_spawn_position() -> Vector3:
	var candidate := Vector3.ZERO
	for _attempt in 10:
		var angle: float = randf() * TAU
		var dist: float = randf_range(MIN_SPAWN_RADIUS, MAX_SPAWN_RADIUS)
		candidate = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if _is_far_from_objects(candidate):
			return candidate
	return candidate


func _is_far_from_objects(pos: Vector3) -> bool:
	# Check distance to stations
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		var sp := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		if sp.distance_to(pos) < MIN_DIST_FROM_OBJECTS:
			return false

	# Check distance to planets
	var planets := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET)
	for ent in planets:
		var pp := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		if pp.distance_to(pos) < MIN_DIST_FROM_OBJECTS:
			return false

	return true


func _get_lod_manager():
	var mgr = GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr.has_method("register_ship"):
		return mgr
	return null


func _register_npc_on_server(npc_id: StringName, sid: StringName, fac: StringName, ship_node: Node3D = null) -> void:
	if not NetworkManager.is_server():
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth == null:
		return
	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0
	npc_auth.register_npc(npc_id, system_id, sid, fac)
	npc_auth.notify_spawn_to_peers(npc_id, system_id)
	if ship_node:
		npc_auth.connect_npc_fire_relay(npc_id, ship_node)
