class_name EncounterManager
extends Node

# =============================================================================
# Encounter Manager - Spawns and tracks NPC encounters
# =============================================================================

signal encounter_started(encounter_id: int)
signal encounter_ended(encounter_id: int)
signal ship_destroyed_in_encounter(ship_name: String)

var _active_npc_ids: Array[StringName] = []
var _encounter_counter: int = 0

# Deferred spawn: during initial load, NetworkSyncManager/NpcAuthority don't exist yet.
# We store the pending request and GameManager triggers it after network role is known.
var _deferred_spawn_pending: bool = false
var _deferred_danger_level: int = 0
var _deferred_system_data = null
var _deferred_spawn_time_ms: float = 0.0  # Watchdog: when deferred spawn was requested

# Override system_id for _register_npc_on_server (set by spawn_for_remote_system).
var _override_system_id: int = -1

const DEFERRED_SPAWN_WATCHDOG_MS: float = 10000.0  # 10s timeout
const MAX_GATE_ROUTE_DIST: float = 25000.0  # Clamp gate positions to playable patrol distance
const STATION_SAFE_RADIUS: float = 3500.0  # Min spawn distance from station centers
const CONVOY_MIN_CLEARANCE: float = 10000.0  # Convoys spawn at least 10km from any major object


func _process(_delta: float) -> void:
	# Watchdog: if deferred spawn is still pending after 10s, log warning
	if _deferred_spawn_pending and _deferred_spawn_time_ms > 0.0:
		if Time.get_ticks_msec() - _deferred_spawn_time_ms > DEFERRED_SPAWN_WATCHDOG_MS:
			push_warning("EncounterManager: Deferred spawn still pending after %.0fs — NetworkSyncManager may not exist" % (DEFERRED_SPAWN_WATCHDOG_MS / 1000.0))
			_deferred_spawn_time_ms = Time.get_ticks_msec()  # Reset to avoid spam


func clear_all_npcs() -> void:
	var lod_mgr = _get_lod_manager()
	if lod_mgr:
		for npc_id in _active_npc_ids:
			lod_mgr.unregister_ship(npc_id)
	else:
		for npc_id in _active_npc_ids:
			var node = get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))
			if node and is_instance_valid(node):
				node.queue_free()
	_active_npc_ids.clear()
	_encounter_counter = 0


## Save NPCs to persistence instead of destroying them. Returns the NPC nodes
## (already detached from LOD/authority) so NpcPersistence can reparent them.
func save_npcs_for_persistence(_system_id: int) -> Array[Node]:
	var lod_mgr = _get_lod_manager()
	var npc_nodes: Array[Node] = []

	for npc_id in _active_npc_ids:
		var npc_node: Node = null
		if lod_mgr:
			var lod_data = lod_mgr.get_ship_data(npc_id)
			if lod_data and is_instance_valid(lod_data.node_ref):
				npc_node = lod_data.node_ref
			# Unregister from LOD without freeing the node
			lod_mgr.unregister_ship(npc_id, false)  # false = don't queue_free
		else:
			npc_node = get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))

		if npc_node and is_instance_valid(npc_node):
			npc_nodes.append(npc_node)

	_active_npc_ids.clear()
	_encounter_counter = 0
	return npc_nodes


func spawn_system_encounters(danger_level: int, system_data) -> void:
	# Only the server spawns NPCs. Clients receive them via NpcAuthority sync.
	if not NetworkManager.is_server():
		return

	# During initial load, NetworkSyncManager (and NpcAuthority) don't exist yet.
	# Defer spawning until GameManager triggers it after network role is determined.
	if not GameManager.get_node_or_null("NetworkSyncManager") or not GameManager.get_node_or_null("NpcAuthority"):
		_deferred_spawn_pending = true
		_deferred_danger_level = danger_level
		_deferred_system_data = system_data
		_deferred_spawn_time_ms = Time.get_ticks_msec()
		return

	# Check if we have dormant NPCs from a previous visit
	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0
	var persistence: NpcPersistence = GameManager.get_node_or_null("NpcPersistence")
	if persistence and persistence.has_saved_state(system_id):
		_restore_from_persistence(system_id, persistence)
		return

	_do_spawn_encounters(danger_level, system_data)


## Called by GameManager after network role is determined.
func spawn_deferred() -> void:
	if not _deferred_spawn_pending:
		return
	_deferred_spawn_pending = false
	_do_spawn_encounters(_deferred_danger_level, _deferred_system_data)


## Restore dormant NPCs from persistence back into the scene.
func _restore_from_persistence(system_id: int, persistence: NpcPersistence) -> void:
	var universe: Node3D = GameManager.universe_node
	if universe == null:
		return

	var restored_nodes: Array[Node] = persistence.restore_system(system_id, universe)
	if restored_nodes.is_empty():
		return

	var lod_mgr = _get_lod_manager()
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")

	for npc in restored_nodes:
		if npc == null or not is_instance_valid(npc):
			continue
		var npc_id := StringName(npc.name)
		_active_npc_ids.append(npc_id)

		# Re-register in LOD system
		if lod_mgr and npc.get("ship_data"):
			var lod_data := ShipLODData.new()
			lod_data.id = npc_id
			lod_data.ship_id = npc.ship_data.ship_id
			lod_data.ship_class = npc.ship_data.ship_class
			lod_data.faction = npc.faction if "faction" in npc else &"hostile"
			lod_data.node_ref = npc
			lod_data.position = npc.global_position
			if npc is RigidBody3D:
				lod_data.velocity = npc.linear_velocity
			lod_data.rotation_basis = npc.global_transform.basis
			# Read health if available
			var health = npc.get_node_or_null("HealthSystem")
			if health:
				lod_data.hull_ratio = health.get_hull_ratio()
				lod_data.shield_ratio = health.get_total_shield_ratio()
			lod_mgr.register_ship(npc_id, lod_data)

		# Re-register with NPC authority
		if npc_auth and npc.get("ship_data"):
			var ship_id: StringName = npc.ship_data.ship_id
			var fac: StringName = npc.faction if "faction" in npc else &"hostile"
			npc_auth.register_npc(npc_id, system_id, ship_id, fac)
			npc_auth.notify_spawn_to_peers(npc_id, system_id)
			npc_auth.connect_npc_fire_relay(npc_id, npc)

		# Re-register in EntityRegistry
		var upos: Array = FloatingOrigin.to_universe_pos(npc.global_position)
		EntityRegistry.register(npc.name, {
			"name": npc.name,
			"type": EntityRegistrySystem.EntityType.SHIP_NPC,
			"node": npc,
			"radius": 10.0,
			"color": Color.RED,
			"pos_x": upos[0], "pos_y": upos[1], "pos_z": upos[2],
		})

	print("EncounterManager: Restored %d NPCs from persistence for system %d" % [restored_nodes.size(), system_id])


## Admin reset: clear active NPC list (nodes already freed by NpcAuthority) and re-spawn.
func admin_clear_and_respawn() -> void:
	_active_npc_ids.clear()
	_encounter_counter = 0
	# Re-spawn using the stored system data from the initial load
	if _deferred_system_data != null:
		_do_spawn_encounters(_deferred_danger_level, _deferred_system_data)


func _do_spawn_encounters(danger_level: int, system_data) -> void:
	# Resolve the system's default station faction from galaxy data
	var sys_trans = GameManager._system_transition
	var system_id_for_fac: int = sys_trans.current_system_id if sys_trans else 0
	var default_faction: StringName = &"nova_terra"
	if sys_trans and sys_trans.galaxy:
		var galaxy_sys_fac: StringName = sys_trans.galaxy.get_system(system_id_for_fac).get("faction", &"neutral")
		default_faction = SystemTransition._map_system_faction(galaxy_sys_fac)

	# Collect all station positions, scene nodes, and factions.
	# Use actual scene node positions (not orbital math) — floating origin shifts may have
	# moved everything since the system was loaded, especially for deferred spawns.
	var station_positions: Array[Vector3] = []
	var station_nodes: Array = []  # Node3D or null
	var station_factions: Array[StringName] = []
	var universe: Node3D = GameManager.universe_node
	if system_data and system_data.stations.size() > 0:
		for st_i in system_data.stations.size():
			var station_node: Node3D = null
			if universe:
				station_node = universe.get_node_or_null("Station_%d" % st_i)
			if station_node and is_instance_valid(station_node):
				station_positions.append(station_node.global_position)
			else:
				# Fallback: compute from orbital math (remote systems without scene nodes)
				var st: StationData = system_data.stations[st_i]
				var angle: float = EntityRegistrySystem.compute_orbital_angle(st.orbital_angle, st.orbital_period)
				station_positions.append(Vector3(cos(angle) * st.orbital_radius, 0.0, sin(angle) * st.orbital_radius))
			station_nodes.append(station_node)
			if station_node and "faction" in station_node:
				station_factions.append(station_node.faction)
			else:
				station_factions.append(default_faction)

	# Collect gate positions for system-wide routes.
	# Use actual scene node positions when available, fallback to data for remote systems.
	var gate_positions: Array[Vector3] = []
	if system_data and system_data.jump_gates.size() > 0:
		for gd_i in system_data.jump_gates.size():
			var raw_gate: Vector3
			var gate_node: Node3D = null
			if universe:
				gate_node = universe.get_node_or_null("JumpGate_%d" % gd_i)
			if gate_node and is_instance_valid(gate_node):
				raw_gate = gate_node.global_position
			else:
				var gd_gate = system_data.jump_gates[gd_i]
				raw_gate = Vector3(gd_gate.pos_x, gd_gate.pos_y, gd_gate.pos_z)
			var gate_dist: float = raw_gate.length()
			if gate_dist > MAX_GATE_ROUTE_DIST:
				raw_gate = raw_gate.normalized() * MAX_GATE_ROUTE_DIST
			gate_positions.append(raw_gate)

	# Build a list of all key points in the system (stations + gates)
	var key_points: Array[Vector3] = []
	key_points.append_array(station_positions)
	key_points.append_array(gate_positions)

	# Fallback if no stations — far enough from star center (0,0,0)
	if station_positions.is_empty():
		station_positions.append(Vector3(5000, 0, -15000))
		station_nodes.append(null)
		station_factions.append(default_faction)
	if key_points.is_empty():
		key_points.append(Vector3(5000, 0, -15000))

	# Get current system_id for encounter key generation
	var system_id: int = system_id_for_fac

	# Spawn dedicated station guards (faction matches the station)
	_spawn_station_guards(station_positions, station_nodes, system_id, station_factions)

	# Encounters use hostile/pirate faction — not the station's defensive faction
	var encounter_faction: StringName = &"pirate"
	if sys_trans and sys_trans.galaxy:
		var sys_fac: StringName = sys_trans.galaxy.get_system(system_id_for_fac).get("faction", &"neutral")
		if sys_fac in [&"hostile", &"lawless", &"pirate"]:
			encounter_faction = &"pirate"
		elif sys_fac == &"kharsis":
			encounter_faction = &"kharsis"
		else:
			encounter_faction = &"pirate"  # Neutral/allied systems still spawn pirate threats

	var configs := EncounterConfig.get_danger_config(danger_level, encounter_faction)
	var used_cfg_indices: Array[int] = []

	# --- Danger 5: combat formation (heavy ship + mid wingmen) ---
	if danger_level == 5 and configs.size() >= 2:
		var st_pos: Vector3 = station_positions[0]
		var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
		var base_pos := st_pos + radial_dir * 2000.0
		spawn_formation(configs[0]["ship"], configs[1]["ship"], configs[1]["count"], base_pos, configs[0]["fac"], station_nodes[0] if not station_nodes.is_empty() else null)
		used_cfg_indices.append(0)
		used_cfg_indices.append(1)

	# --- Convoy formations: group freighter + escort as a real formation ---
	for c_idx in configs.size():
		if used_cfg_indices.has(c_idx):
			continue
		var _ship_data_check = ShipRegistry.get_ship_data(configs[c_idx]["ship"])
		if _ship_data_check == null or _ship_data_check.ship_class != &"Freighter":
			continue
		# Found a freighter — pair with adjacent config as escort
		var escort_idx: int = -1
		if c_idx + 1 < configs.size() and not used_cfg_indices.has(c_idx + 1):
			escort_idx = c_idx + 1
		elif c_idx - 1 >= 0 and not used_cfg_indices.has(c_idx - 1):
			escort_idx = c_idx - 1
		var leader_cfg: Dictionary = configs[c_idx]
		var st_idx: int = c_idx % station_positions.size()
		var st_pos: Vector3 = station_positions[st_idx]
		var escort_ship: StringName = &""
		var escort_count: int = 0
		if escort_idx >= 0:
			escort_ship = configs[escort_idx]["ship"]
			escort_count = configs[escort_idx]["count"]
			used_cfg_indices.append(escort_idx)
		# Build route for convoy to traverse the system
		var convoy_route: Array[Vector3] = []
		if key_points.size() >= 2:
			convoy_route = _build_system_route(st_pos, key_points)
		# Spawn at a random position in open space (far from stations/planets)
		var base_pos: Vector3
		if key_points.size() >= 2:
			base_pos = _pick_open_space_position(key_points)
		else:
			var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
			base_pos = st_pos + radial_dir * 3000.0
		spawn_formation(leader_cfg["ship"], escort_ship, escort_count, base_pos, leader_cfg["fac"], station_nodes[st_idx] if st_idx < station_nodes.size() else null, convoy_route)
		used_cfg_indices.append(c_idx)

	# --- Remaining configs: route patrols / area patrols ---
	var cfg_idx: int = 0
	for cfg in configs:
		if not used_cfg_indices.has(cfg_idx):
			var st_idx: int = cfg_idx % station_positions.size()
			var st_pos: Vector3 = station_positions[st_idx]
			if cfg_idx % 2 == 0 and key_points.size() >= 2:
				var route: Array[Vector3] = _build_system_route(st_pos, key_points)
				spawn_route_patrol(cfg["count"], cfg["ship"], route, cfg["fac"], system_id, cfg_idx)
			else:
				var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
				var base_pos := st_pos + radial_dir * 5000.0
				spawn_patrol(cfg["count"], cfg["ship"], base_pos, maxf(cfg["radius"], 2000.0), cfg["fac"], system_id, cfg_idx, station_nodes[st_idx] if st_idx < station_nodes.size() else null)
		cfg_idx += 1


func _spawn_station_guards(station_positions: Array[Vector3], station_nodes: Array, system_id: int, station_factions: Array[StringName] = []) -> void:
	var guard_ship: StringName = _get_guard_ship_id()
	for st_idx in station_positions.size():
		var station_node = station_nodes[st_idx] if st_idx < station_nodes.size() else null
		var guard_faction: StringName
		if station_node != null:
			guard_faction = station_node.faction if "faction" in station_node else &"nova_terra"
		elif st_idx < station_factions.size():
			guard_faction = station_factions[st_idx]
		else:
			guard_faction = &"nova_terra"  # Fallback — always spawn guards
		var st_pos: Vector3 = station_positions[st_idx]
		# Guards patrol near the station (outside model radius but within detection range)
		var offset_dir: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if offset_dir.length_squared() < 0.01:
			offset_dir = Vector3.FORWARD
		var guard_center: Vector3 = st_pos + offset_dir * randf_range(800.0, 1500.0)
		print("EncounterManager: Spawning 2 guards (faction=%s, ship=%s) for station %d (node=%s)" % [guard_faction, guard_ship, st_idx, station_node != null])
		spawn_patrol(2, guard_ship, guard_center, 1500.0, guard_faction, system_id, 100 + st_idx, station_node)


func _get_guard_ship_id() -> StringName:
	for sid in ShipRegistry.get_all_ship_ids():
		var data = ShipRegistry.get_ship_data(sid)
		if data and data.npc_tier == 0:
			return sid
	return Constants.DEFAULT_SHIP_ID


## Push a position outside all large entity exclusion zones (stations, planets, stars).
func _is_respawn_on_cooldown(system_id: int, cfg_idx: int, i: int) -> bool:
	if system_id < 0 or cfg_idx < 0:
		return false
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth == null:
		return false
	var encounter_key: String = "%d:enc_%d_%d" % [system_id, cfg_idx, i]
	if npc_auth._destroyed_encounter_npcs.has(encounter_key):
		var entry = npc_auth._destroyed_encounter_npcs[encounter_key]
		var respawn_time: float = entry["time"] if entry is Dictionary else float(entry)
		if Time.get_unix_time_from_system() < respawn_time:
			return true
		npc_auth._destroyed_encounter_npcs.erase(encounter_key)
	return false


func _push_spawn_from_obstacles(pos: Vector3) -> Vector3:
	# Stations
	var stations: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		var ent_pos: Vector3 = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		var excl_r: float = STATION_SAFE_RADIUS
		var to_pos: Vector3 = pos - ent_pos
		var dist: float = to_pos.length()
		if dist < excl_r:
			if dist < 1.0:
				to_pos = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_pos = to_pos.normalized()
			pos = ent_pos + to_pos * (excl_r + 200.0)

	# Planets
	var planets: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET)
	for ent in planets:
		var ent_pos: Vector3 = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		var planet_r: float = ent.get("radius", 5000.0)
		var excl_r: float = maxf(planet_r * 1.2 + 500.0, 5000.0)
		var to_pos: Vector3 = pos - ent_pos
		var dist: float = to_pos.length()
		if dist < excl_r:
			if dist < 1.0:
				to_pos = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_pos = to_pos.normalized()
			pos = ent_pos + to_pos * (excl_r + 200.0)

	# Stars
	var stars: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR)
	for ent in stars:
		var ent_pos: Vector3 = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		var star_r: float = ent.get("radius", 50000.0)
		var excl_r: float = maxf(star_r * 1.5, 50000.0)
		var to_pos: Vector3 = pos - ent_pos
		var dist: float = to_pos.length()
		if dist < excl_r:
			if dist < 1.0:
				to_pos = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_pos = to_pos.normalized()
			pos = ent_pos + to_pos * (excl_r + 200.0)

	return pos


## Pick a random position in open space within the bounding box of key_points,
## at least CONVOY_MIN_CLEARANCE from any station, planet or star.
func _pick_open_space_position(key_points: Array[Vector3]) -> Vector3:
	# Compute bounding range from key points
	var min_x: float = INF; var max_x: float = -INF
	var min_z: float = INF; var max_z: float = -INF
	for kp in key_points:
		min_x = minf(min_x, kp.x); max_x = maxf(max_x, kp.x)
		min_z = minf(min_z, kp.z); max_z = maxf(max_z, kp.z)
	# Expand bounds by 20% so convoys aren't stuck inside the tight key_point box
	var pad_x: float = maxf((max_x - min_x) * 0.2, 5000.0)
	var pad_z: float = maxf((max_z - min_z) * 0.2, 5000.0)
	min_x -= pad_x; max_x += pad_x
	min_z -= pad_z; max_z += pad_z

	# Collect obstacle positions + exclusion radii
	var obstacles: Array[Array] = []  # [[Vector3, float], ...]
	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION):
		obstacles.append([FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), CONVOY_MIN_CLEARANCE])
	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET):
		var r: float = ent.get("radius", 5000.0)
		obstacles.append([FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), maxf(r * 1.5, CONVOY_MIN_CLEARANCE)])
	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR):
		var r: float = ent.get("radius", 50000.0)
		obstacles.append([FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), maxf(r * 1.5, 50000.0)])

	# Try up to 20 random positions, pick the first one that clears all obstacles
	for _attempt in 20:
		var candidate := Vector3(randf_range(min_x, max_x), 0.0, randf_range(min_z, max_z))
		var clear: bool = true
		for obs in obstacles:
			if candidate.distance_to(obs[0] as Vector3) < (obs[1] as float):
				clear = false
				break
		if clear:
			return candidate

	# Fallback: use midpoint of two random key_points pushed away from obstacles
	var fallback := (key_points[0] + key_points[randi() % key_points.size()]) * 0.5
	fallback += Vector3(randf_range(-5000, 5000), 0.0, randf_range(-5000, 5000))
	return _push_spawn_from_obstacles(fallback)


func spawn_patrol(count: int, ship_id: StringName, center: Vector3, radius: float, faction: StringName = &"hostile", system_id: int = -1, cfg_idx: int = -1, station_node: Node3D = null) -> void:
	_encounter_counter += 1
	var eid =_encounter_counter

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	# Push patrol center away from large obstacles (stations, planets, stars)
	# Skip push for station guards — they SHOULD be near their station
	if station_node == null:
		center = _push_spawn_from_obstacles(center)

	for i in count:
		if _is_respawn_on_cooldown(system_id, cfg_idx, i):
			continue

		var angle: float = (float(i) / float(count)) * TAU
		var offset =Vector3(cos(angle) * radius * 0.5, 0.0, sin(angle) * radius * 0.5)
		var pos: Vector3 = center + offset if station_node else _push_spawn_from_obstacles(center + offset)

		# Clamp patrol radius for station guards
		var patrol_radius: float = radius
		if station_node:
			patrol_radius = clampf(radius, 500.0, 1000.0)

		# Always spawn full nodes — all NPCs are real ships with AI + physics
		var ship = ShipFactory.spawn_npc_ship(ship_id, &"balanced", pos, parent, faction)
		if ship:
			var brain = ship.get_node_or_null("AIController")
			if brain:
				brain.set_patrol_area(center, patrol_radius)
				if station_node:
					brain.guard_station = station_node
			_active_npc_ids.append(StringName(ship.name))
			ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
			_register_npc_on_server(StringName(ship.name), ship_id, faction, ship)
			_store_encounter_key(StringName(ship.name), system_id, cfg_idx, i)

	encounter_started.emit(eid)


## Spawn NPCs that follow a system-wide route between key points (stations/gates).
## Creates visible traffic on the system map.
func spawn_route_patrol(count: int, ship_id: StringName, route: Array[Vector3], faction: StringName = &"hostile", system_id: int = -1, cfg_idx: int = -1) -> void:
	_encounter_counter += 1
	var eid = _encounter_counter

	var parent = get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	for i in count:
		if _is_respawn_on_cooldown(system_id, cfg_idx, i):
			continue

		# Stagger start positions along the route
		var start_idx: int = i % route.size()
		var pos: Vector3 = route[start_idx] + Vector3(randf_range(-200, 200), 0.0, randf_range(-200, 200))

		# Always spawn full nodes — all NPCs are real ships with AI + physics
		var ship = ShipFactory.spawn_npc_ship(ship_id, &"balanced", pos, parent, faction)
		if ship:
			var brain = ship.get_node_or_null("AIController")
			if brain:
				brain.set_patrol_area(route[0], 50000.0)
				brain.waypoints_compat = route.duplicate()
				brain.current_waypoint_compat = start_idx
				brain.route_priority = false  # Can break route for combat
			_active_npc_ids.append(StringName(ship.name))
			ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
			_register_npc_on_server(StringName(ship.name), ship_id, faction, ship)
			_store_encounter_key(StringName(ship.name), system_id, cfg_idx, i)

	encounter_started.emit(eid)


## Build a system-wide route that passes through multiple key points (stations, gates).
## Creates a looping path that NPCs will visibly traverse on the system map.
func _build_system_route(start_pos: Vector3, key_points: Array[Vector3]) -> Array[Vector3]:
	var route: Array[Vector3] = []
	route.append(start_pos)

	# Sort key points by distance from start (nearest-neighbor order)
	var remaining: Array[Vector3] = key_points.duplicate()
	# Remove the start point itself if it's in the list
	for k in remaining.size():
		if remaining[k].distance_to(start_pos) < 1000.0:
			remaining.remove_at(k)
			break

	var current: Vector3 = start_pos
	while not remaining.is_empty() and route.size() < 6:
		var best_idx: int = 0
		var best_dist: float = INF
		for j in remaining.size():
			var d: float = current.distance_to(remaining[j])
			if d < best_dist:
				best_dist = d
				best_idx = j
		# Add waypoint offset from the actual station/gate (patrol around it)
		var target: Vector3 = remaining[best_idx]
		var offset_dir: Vector3 = (target - current).normalized().cross(Vector3.UP)
		route.append(target + offset_dir * randf_range(1000.0, 3000.0))
		current = remaining[best_idx]
		remaining.remove_at(best_idx)

	# Add midway points between distant waypoints for smoother travel
	if route.size() >= 2:
		var last: Vector3 = route[-1]
		var first: Vector3 = route[0]
		var mid: Vector3 = (last + first) * 0.5 + Vector3(randf_range(-5000, 5000), 0, randf_range(-5000, 5000))
		route.append(mid)

	return route


func spawn_free_for_all(count: int, ship_id: StringName, center: Vector3, radius: float) -> void:
	_encounter_counter += 1
	var eid =_encounter_counter

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	for i in count:
		var angle: float = randf() * TAU
		var dist: float = randf_range(radius * 0.1, radius)
		var offset =Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		var pos: Vector3 = center + offset

		# Unique faction per ship — everyone fights everyone
		var unique_faction =StringName("npc_%d" % i)

		# Always spawn full nodes — all NPCs are real ships with AI + physics
		var ship = ShipFactory.spawn_npc_ship(ship_id, &"aggressive", pos, parent, unique_faction)
		if ship:
			var brain = ship.get_node_or_null("AIController")
			if brain:
				brain.set_patrol_area(center, radius)
			_active_npc_ids.append(StringName(ship.name))
			ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
			_register_npc_on_server(StringName(ship.name), ship_id, unique_faction, ship)

	encounter_started.emit(eid)


func spawn_ambush(ship_ids: Array[StringName], range_dist: float, faction: StringName = &"hostile") -> void:
	_encounter_counter += 1
	var player =GameManager.player_ship
	if player == null:
		return

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	for ship_id in ship_ids:
		var offset =Vector3(
			randf_range(-range_dist, range_dist),
			randf_range(-range_dist * 0.3, range_dist * 0.3),
			randf_range(-range_dist, range_dist)
		)
		var pos: Vector3 = player.global_position + offset

		var ship = ShipFactory.spawn_npc_ship(ship_id, &"aggressive", pos, parent, faction)
		if ship:
			_active_npc_ids.append(StringName(ship.name))
			ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
			_register_npc_on_server(StringName(ship.name), ship_id, faction, ship)

	encounter_started.emit(_encounter_counter)


func spawn_formation(leader_id: StringName, wingman_id: StringName, wingman_count: int, pos: Vector3, faction: StringName = &"hostile", station_node: Node3D = null, route: Array[Vector3] = []) -> void:
	_encounter_counter += 1

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	# Push spawn position away from obstacles (star, planets, stations)
	pos = _push_spawn_from_obstacles(pos)

	# Spawn leader
	var leader = ShipFactory.spawn_npc_ship(leader_id, &"aggressive", pos, parent, faction)
	if leader == null:
		return
	var leader_brain = leader.get_node_or_null("AIController")
	if leader_brain:
		if route.size() >= 2:
			leader_brain.set_route(route)
			leader_brain.route_priority = true
		else:
			leader_brain.set_patrol_area(pos, 2000.0)
		# Only set guard_station if the convoy's faction matches the station's faction
		# (prevents pirate convoys from alerting enemy station guards when attacked)
		if station_node and "faction" in station_node and station_node.faction == faction:
			leader_brain.guard_station = station_node
	_active_npc_ids.append(StringName(leader.name))
	leader.tree_exiting.connect(_on_npc_removed.bind(StringName(leader.name)))
	_register_npc_on_server(StringName(leader.name), leader_id, faction, leader)

	# Spawn wingmen in side-by-side formation
	for i in wingman_count:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var row: int = i / 2 + 1
		var offset =Vector3(side * 120.0 * row, 0.0, 15.0 * row)
		var wing_pos: Vector3 = _push_spawn_from_obstacles(pos + offset)

		var wingman = ShipFactory.spawn_npc_ship(wingman_id, &"aggressive", wing_pos, parent, faction)
		if wingman:
			var brain = wingman.get_node_or_null("AIController")
			if brain:
				brain.formation_leader = leader
				brain.formation_offset = offset
				brain.current_state = AIController.State.FORMATION
				# Only set guard_station if faction matches station faction
				if station_node and "faction" in station_node and station_node.faction == faction:
					brain.guard_station = station_node
			_active_npc_ids.append(StringName(wingman.name))
			wingman.tree_exiting.connect(_on_npc_removed.bind(StringName(wingman.name)))
			_register_npc_on_server(StringName(wingman.name), wingman_id, faction, wingman)

	encounter_started.emit(_encounter_counter)


## Spawn real NPC nodes for a remote system (server-side, called by NpcAuthority).
## Creates full ShipController nodes with AI, physics, and combat — same as local spawns.
func spawn_for_remote_system(system_id: int) -> void:
	var sys_trans = GameManager._system_transition
	if sys_trans == null:
		return
	var galaxy = sys_trans.galaxy
	if galaxy == null:
		return
	var galaxy_sys: Dictionary = galaxy.get_system(system_id)
	if galaxy_sys.is_empty():
		return

	var danger_level: int = galaxy_sys.get("danger_level", 0)

	# Resolve system data (override > procedural)
	var system_data: StarSystemData = SystemDataRegistry.get_override(system_id)
	if system_data == null:
		var connections: Array[Dictionary] = sys_trans._build_connection_list(system_id)
		system_data = SystemGenerator.generate(galaxy_sys["seed"], connections)

	# Compute station positions (pure math, no scene nodes needed)
	var station_positions: Array[Vector3] = []
	var station_factions: Array[StringName] = []
	var galaxy_sys_fac: StringName = StringName(galaxy_sys.get("faction", "neutral"))
	var default_faction: StringName = SystemTransition._map_system_faction(galaxy_sys_fac)

	if system_data and system_data.stations.size() > 0:
		for st in system_data.stations:
			var orbit_r: float = st.orbital_radius
			var angle: float = EntityRegistrySystem.compute_orbital_angle(st.orbital_angle, st.orbital_period)
			station_positions.append(Vector3(cos(angle) * orbit_r, 0.0, sin(angle) * orbit_r))
			station_factions.append(default_faction)

	# Compute gate positions (clamped to playable patrol distance — gates are at system scale).
	var gate_positions: Array[Vector3] = []
	if system_data and system_data.jump_gates.size() > 0:
		for gd_gate in system_data.jump_gates:
			var raw_gate := Vector3(gd_gate.pos_x, gd_gate.pos_y, gd_gate.pos_z)
			var gate_dist: float = raw_gate.length()
			if gate_dist > MAX_GATE_ROUTE_DIST:
				raw_gate = raw_gate.normalized() * MAX_GATE_ROUTE_DIST
			gate_positions.append(raw_gate)

	var key_points: Array[Vector3] = []
	key_points.append_array(station_positions)
	key_points.append_array(gate_positions)

	if station_positions.is_empty():
		station_positions.append(Vector3(5000, 0, -15000))
		station_factions.append(default_faction)
	if key_points.is_empty():
		key_points.append(Vector3(5000, 0, -15000))

	# Register virtual stations in EntityRegistry so AIController environment awareness works.
	# Without these, _update_environment() can't find stations → no push-away, no avoidance.
	var virtual_station_ids: Array[String] = []
	for st_idx in station_positions.size():
		var st_pos: Vector3 = station_positions[st_idx]
		var vst_id: String = "vstation_%d_%d" % [system_id, st_idx]
		var fac_name: StringName = station_factions[st_idx] if st_idx < station_factions.size() else default_faction
		# Use universe coordinates (origin_offset + scene pos). On dedicated server
		# origin_offset ≈ 0, so these match scene positions closely.
		var ux: float = FloatingOrigin.origin_offset_x + float(st_pos.x)
		var uy: float = FloatingOrigin.origin_offset_y + float(st_pos.y)
		var uz: float = FloatingOrigin.origin_offset_z + float(st_pos.z)
		EntityRegistry.register(vst_id, {
			"name": "VirtualStation_%d_%d" % [system_id, st_idx],
			"type": EntityRegistry.EntityType.STATION,
			"pos_x": ux,
			"pos_y": uy,
			"pos_z": uz,
			"node": null,
			"radius": 300.0,
			"color": Color.GRAY,
			"extra": {"faction": String(fac_name), "virtual": true},
		})
		virtual_station_ids.append(vst_id)

	# Store virtual station IDs on NpcAuthority for cleanup
	var npc_auth_ref = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth_ref:
		npc_auth_ref._virtual_stations[system_id] = virtual_station_ids

	# Set override so _register_npc_on_server uses the correct system_id
	_override_system_id = system_id

	# Spawn station guards (no scene nodes, use computed factions)
	_spawn_station_guards(station_positions, [], system_id, station_factions)

	# Encounters use faction based on system affiliation
	var encounter_faction: StringName = &"pirate"
	if galaxy_sys_fac == &"kharsis":
		encounter_faction = &"kharsis"

	# Spawn encounters based on danger level
	var configs := EncounterConfig.get_danger_config(danger_level, encounter_faction)
	var used_cfg_indices: Array[int] = []

	# --- Danger 5: combat formation ---
	if danger_level == 5 and configs.size() >= 2:
		var st_pos: Vector3 = station_positions[0]
		var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
		var base_pos := st_pos + radial_dir * 2000.0
		spawn_formation(configs[0]["ship"], configs[1]["ship"], configs[1]["count"], base_pos, configs[0]["fac"], null)
		used_cfg_indices.append(0)
		used_cfg_indices.append(1)

	# --- Convoy formations: group freighter + escort ---
	for c_idx in configs.size():
		if used_cfg_indices.has(c_idx):
			continue
		var _ship_data_check = ShipRegistry.get_ship_data(configs[c_idx]["ship"])
		if _ship_data_check == null or _ship_data_check.ship_class != &"Freighter":
			continue
		var escort_idx: int = -1
		if c_idx + 1 < configs.size() and not used_cfg_indices.has(c_idx + 1):
			escort_idx = c_idx + 1
		elif c_idx - 1 >= 0 and not used_cfg_indices.has(c_idx - 1):
			escort_idx = c_idx - 1
		var leader_cfg: Dictionary = configs[c_idx]
		var st_idx: int = c_idx % station_positions.size()
		var st_pos: Vector3 = station_positions[st_idx]
		var escort_ship: StringName = &""
		var escort_count: int = 0
		if escort_idx >= 0:
			escort_ship = configs[escort_idx]["ship"]
			escort_count = configs[escort_idx]["count"]
			used_cfg_indices.append(escort_idx)
		var convoy_route: Array[Vector3] = []
		if key_points.size() >= 2:
			convoy_route = _build_system_route(st_pos, key_points)
		# Spawn at a random position in open space (far from stations/planets)
		var base_pos: Vector3
		if key_points.size() >= 2:
			base_pos = _pick_open_space_position(key_points)
		else:
			var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
			base_pos = st_pos + radial_dir * 3000.0
		spawn_formation(leader_cfg["ship"], escort_ship, escort_count, base_pos, leader_cfg["fac"], null, convoy_route)
		used_cfg_indices.append(c_idx)

	# --- Remaining configs: route patrols / area patrols ---
	var cfg_idx: int = 0
	for cfg in configs:
		if not used_cfg_indices.has(cfg_idx):
			var st_idx: int = cfg_idx % station_positions.size()
			var st_pos: Vector3 = station_positions[st_idx]
			if cfg_idx % 2 == 0 and key_points.size() >= 2:
				var route: Array[Vector3] = _build_system_route(st_pos, key_points)
				spawn_route_patrol(cfg["count"], cfg["ship"], route, cfg["fac"], system_id, cfg_idx)
			else:
				var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
				var base_pos := st_pos + radial_dir * 3000.0
				spawn_patrol(cfg["count"], cfg["ship"], base_pos, maxf(cfg["radius"], 2000.0), cfg["fac"], system_id, cfg_idx, null)
		cfg_idx += 1

	_override_system_id = -1
	print("EncounterManager: Spawned real NPCs for remote system %d (danger %d)" % [system_id, danger_level])


func get_active_npc_count() -> int:
	return _active_npc_ids.size()


func _on_npc_removed(npc_id: StringName) -> void:
	_active_npc_ids.erase(npc_id)
	ship_destroyed_in_encounter.emit(String(npc_id))
	if _active_npc_ids.is_empty():
		encounter_ended.emit(_encounter_counter)


func _get_lod_manager():
	var mgr = GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr.has_method("register_ship"):
		return mgr
	return null


## Store encounter key on NpcAuthority's NPC record for respawn tracking.
func _store_encounter_key(npc_id: StringName, system_id: int, cfg_idx: int, spawn_idx: int) -> void:
	if system_id < 0 or cfg_idx < 0:
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth and npc_auth._npcs.has(npc_id):
		npc_auth._npcs[npc_id]["encounter_key"] = "%d:enc_%d_%d" % [system_id, cfg_idx, spawn_idx]


## Register NPC with NpcAuthority (server only) and notify connected clients.
func _register_npc_on_server(npc_id: StringName, sid: StringName, fac: StringName, ship_node: Node3D = null) -> void:
	if not NetworkManager.is_server():
		return
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth == null:
		return
	var system_id: int
	if _override_system_id >= 0:
		system_id = _override_system_id
	else:
		var sys_trans = GameManager._system_transition
		system_id = sys_trans.current_system_id if sys_trans else 0
	npc_auth.register_npc(npc_id, system_id, sid, fac)
	npc_auth.notify_spawn_to_peers(npc_id, system_id)
	# Connect weapon fire relay for remote clients to see NPC shots
	if ship_node:
		npc_auth.connect_npc_fire_relay(npc_id, ship_node)
