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

# Override system_id for _register_npc_on_server (set by spawn_for_remote_system).
var _override_system_id: int = -1


func clear_all_npcs() -> void:
	var lod_mgr =_get_lod_manager()
	if lod_mgr:
		for npc_id in _active_npc_ids:
			lod_mgr.unregister_ship(npc_id)
	else:
		# Legacy fallback: free nodes directly
		for npc_id in _active_npc_ids:
			var node =get_tree().current_scene.get_node_or_null(NodePath(String(npc_id)))
			if node and is_instance_valid(node):
				node.queue_free()
	_active_npc_ids.clear()
	_encounter_counter = 0


func spawn_system_encounters(danger_level: int, system_data) -> void:
	# Only the server spawns NPCs. Clients receive them via NpcAuthority sync.
	if not NetworkManager.is_server():
		return

	# During initial load, NetworkSyncManager (and NpcAuthority) don't exist yet.
	# Defer spawning until GameManager triggers it after network role is determined.
	if not GameManager.get_node_or_null("NetworkSyncManager"):
		_deferred_spawn_pending = true
		_deferred_danger_level = danger_level
		_deferred_system_data = system_data
		return

	_do_spawn_encounters(danger_level, system_data)


## Called by GameManager after network role is determined.
func spawn_deferred() -> void:
	if not _deferred_spawn_pending:
		return
	_deferred_spawn_pending = false
	_do_spawn_encounters(_deferred_danger_level, _deferred_system_data)


func _do_spawn_encounters(danger_level: int, system_data) -> void:
	# Collect all station positions and scene nodes
	var station_positions: Array[Vector3] = []
	var station_nodes: Array = []  # Node3D or null
	if system_data and system_data.stations.size() > 0:
		for st in system_data.stations:
			var orbit_r: float = st.orbital_radius
			var angle: float = EntityRegistrySystem.compute_orbital_angle(st.orbital_angle, st.orbital_period)
			var station_pos := Vector3(cos(angle) * orbit_r, 0.0, sin(angle) * orbit_r)
			station_positions.append(station_pos)
			# Find the actual station scene node via EntityRegistry
			var station_node: Node3D = null
			var all_stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
			for ent in all_stations:
				if ent.get("node") and is_instance_valid(ent["node"]):
					var ent_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					if ent_pos.distance_to(station_pos) < 500.0:
						station_node = ent["node"]
						break
			station_nodes.append(station_node)

	# Collect gate positions for system-wide routes
	var gate_positions: Array[Vector3] = []
	if system_data and system_data.jump_gates.size() > 0:
		for gd_gate in system_data.jump_gates:
			gate_positions.append(Vector3(gd_gate.pos_x, gd_gate.pos_y, gd_gate.pos_z))

	# Build a list of all key points in the system (stations + gates)
	var key_points: Array[Vector3] = []
	key_points.append_array(station_positions)
	key_points.append_array(gate_positions)

	# Fallback if no stations
	if station_positions.is_empty():
		station_positions.append(Vector3(500, 0, -1500))
		station_nodes.append(null)
	if key_points.is_empty():
		key_points.append(Vector3(500, 0, -1500))

	# Get current system_id for encounter key generation
	var sys_trans = GameManager._system_transition
	var system_id: int = sys_trans.current_system_id if sys_trans else 0

	# Spawn dedicated station guards (faction matches the station)
	_spawn_station_guards(station_positions, station_nodes, system_id)

	var configs := EncounterConfig.get_danger_config(danger_level)
	if danger_level == 5 and configs.size() >= 2:
		# Danger 5: formation near first station
		var st_pos: Vector3 = station_positions[0]
		var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
		var base_pos := st_pos + radial_dir * 2000.0 + Vector3(0, 100, 0)
		spawn_formation(configs[0]["ship"], configs[1]["ship"], configs[1]["count"], base_pos, configs[0]["fac"], station_nodes[0])
	else:
		var cfg_idx: int = 0
		for cfg in configs:
			# Alternate between route patrols and area patrols
			var st_idx: int = cfg_idx % station_positions.size()
			var st_pos: Vector3 = station_positions[st_idx]
			# Even configs get system-wide route patrols (visible traffic)
			# Odd configs get area patrols near stations
			if cfg_idx % 2 == 0 and key_points.size() >= 2:
				var route: Array[Vector3] = _build_system_route(st_pos, key_points)
				spawn_route_patrol(cfg["count"], cfg["ship"], route, cfg["fac"], system_id, cfg_idx)
			else:
				var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
				var base_pos := st_pos + radial_dir * 3000.0 + Vector3(0, 100, 0)
				spawn_patrol(cfg["count"], cfg["ship"], base_pos, maxf(cfg["radius"], 2000.0), cfg["fac"], system_id, cfg_idx, station_nodes[st_idx])
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
			continue
		var st_pos: Vector3 = station_positions[st_idx]
		# Guards patrol OUTSIDE the station model (~2500m radius + margin)
		var offset_dir: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if offset_dir.length_squared() < 0.01:
			offset_dir = Vector3.FORWARD
		var guard_center: Vector3 = st_pos + offset_dir * randf_range(3500.0, 4500.0) + Vector3(0, randf_range(-50, 50), 0)
		spawn_patrol(2, guard_ship, guard_center, 1000.0, guard_faction, system_id, 100 + st_idx, station_node)


func _get_guard_ship_id() -> StringName:
	for sid in ShipRegistry.get_all_ship_ids():
		var data = ShipRegistry.get_ship_data(sid)
		if data and data.npc_tier == 0:
			return sid
	return Constants.DEFAULT_SHIP_ID


const STATION_SAFE_RADIUS: float = 3500.0  ## Min spawn distance from station centers


## Push a position outside all large entity exclusion zones (stations, planets, stars).
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


func spawn_patrol(count: int, ship_id: StringName, center: Vector3, radius: float, faction: StringName = &"hostile", system_id: int = -1, cfg_idx: int = -1, station_node: Node3D = null) -> void:
	_encounter_counter += 1
	var eid =_encounter_counter

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	var lod_mgr =_get_lod_manager()
	var cam_pos =Vector3.ZERO
	var cam =get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	# Push patrol center away from large obstacles (stations, planets, stars)
	center = _push_spawn_from_obstacles(center)

	# Get NpcAuthority for respawn checking
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	var now: float = Time.get_unix_time_from_system()

	for i in count:
		# Check respawn cooldown if encounter key is available
		if system_id >= 0 and cfg_idx >= 0 and npc_auth:
			var encounter_key: String = "%d:enc_%d_%d" % [system_id, cfg_idx, i]
			if npc_auth._destroyed_encounter_npcs.has(encounter_key):
				if now < npc_auth._destroyed_encounter_npcs[encounter_key]:
					continue
				else:
					npc_auth._destroyed_encounter_npcs.erase(encounter_key)

		var angle: float = (float(i) / float(count)) * TAU
		var offset =Vector3(cos(angle) * radius * 0.5, randf_range(-30.0, 30.0), sin(angle) * radius * 0.5)
		var pos: Vector3 = center + offset

		# If LOD manager exists and spawn is far away, use data-only (LOD2)
		# Clamp patrol radius for station guards
		var patrol_radius: float = radius
		if station_node:
			patrol_radius = clampf(radius, 500.0, 1000.0)

		# On dedicated server, always spawn full nodes — no rendering overhead
		# and camera distance is meaningless on headless (cam_pos always zero).
		var spawn_data_only: bool = lod_mgr != null and not NetworkManager.is_server() and cam_pos.distance_to(pos) > ShipLODManager.LOD1_DISTANCE
		if spawn_data_only:
			var lod_data = ShipFactory.create_npc_data_only(ship_id, &"balanced", pos, faction)
			if lod_data:
				lod_data.ai_patrol_center = center
				lod_data.ai_patrol_radius = patrol_radius
				lod_data.velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(100.0, 200.0)
				if station_node:
					lod_data.guard_station_name = StringName(station_node.name)
				lod_mgr.register_ship(lod_data.id, lod_data)
				_active_npc_ids.append(lod_data.id)
				_register_npc_on_server(lod_data.id, ship_id, faction)
				_store_encounter_key(lod_data.id, system_id, cfg_idx, i)
		else:
			var ship = ShipFactory.spawn_npc_ship(ship_id, &"balanced", pos, parent, faction)
			if ship:
				var brain = ship.get_node_or_null("AIBrain")
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

	var lod_mgr = _get_lod_manager()
	var cam_pos = Vector3.ZERO
	var cam = get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	var now: float = Time.get_unix_time_from_system()

	for i in count:
		if system_id >= 0 and cfg_idx >= 0 and npc_auth:
			var encounter_key: String = "%d:enc_%d_%d" % [system_id, cfg_idx, i]
			if npc_auth._destroyed_encounter_npcs.has(encounter_key):
				if now < npc_auth._destroyed_encounter_npcs[encounter_key]:
					continue
				else:
					npc_auth._destroyed_encounter_npcs.erase(encounter_key)

		# Stagger start positions along the route
		var start_idx: int = i % route.size()
		var pos: Vector3 = route[start_idx] + Vector3(randf_range(-200, 200), randf_range(-50, 50), randf_range(-200, 200))

		var spawn_data_only: bool = lod_mgr != null and not NetworkManager.is_server() and cam_pos.distance_to(pos) > ShipLODManager.LOD1_DISTANCE
		if spawn_data_only:
			var lod_data = ShipFactory.create_npc_data_only(ship_id, &"balanced", pos, faction)
			if lod_data:
				lod_data.ai_route_waypoints = route.duplicate()
				lod_data.ai_patrol_center = route[0]
				lod_data.ai_patrol_radius = 50000.0  # Large radius (system-wide)
				lod_data.velocity = (route[(start_idx + 1) % route.size()] - pos).normalized() * randf_range(200.0, 400.0)
				lod_mgr.register_ship(lod_data.id, lod_data)
				_active_npc_ids.append(lod_data.id)
				_register_npc_on_server(lod_data.id, ship_id, faction)
				_store_encounter_key(lod_data.id, system_id, cfg_idx, i)
		else:
			var ship = ShipFactory.spawn_npc_ship(ship_id, &"balanced", pos, parent, faction)
			if ship:
				var brain = ship.get_node_or_null("AIBrain")
				if brain:
					brain.set_patrol_area(route[0], 50000.0)
					brain._waypoints = route.duplicate()
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

	var lod_mgr =_get_lod_manager()

	for i in count:
		var angle: float = randf() * TAU
		var dist: float = randf_range(radius * 0.1, radius)
		var offset =Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		var pos: Vector3 = center + offset

		# Unique faction per ship — everyone fights everyone
		var unique_faction =StringName("npc_%d" % i)

		# Random initial velocity so LOD2 ships move on radar
		var vel =Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.2, 0.2),
			randf_range(-1.0, 1.0)
		).normalized() * randf_range(100.0, 200.0)

		if lod_mgr:
			# All spawn as data-only (LOD2) — LOD manager promotes nearby ones
			var lod_data = ShipFactory.create_npc_data_only(ship_id, &"aggressive", pos, unique_faction)
			if lod_data:
				lod_data.ai_patrol_center = center
				lod_data.ai_patrol_radius = radius
				lod_data.velocity = vel
				lod_mgr.register_ship(lod_data.id, lod_data)
				_active_npc_ids.append(lod_data.id)
				_register_npc_on_server(lod_data.id, ship_id, unique_faction)
		else:
			# Legacy fallback: no LOD manager
			var parent =get_tree().current_scene.get_node_or_null("Universe")
			if parent == null:
				parent = get_tree().current_scene
			var ship = ShipFactory.spawn_npc_ship(ship_id, &"aggressive", pos, parent, unique_faction)
			if ship:
				var brain = ship.get_node_or_null("AIBrain")
				if brain:
					brain.set_patrol_area(center, radius)
				_active_npc_ids.append(StringName(ship.name))
				ship.tree_exiting.connect(_on_npc_removed.bind(StringName(ship.name)))
				_register_npc_on_server(StringName(ship.name), ship_id, unique_faction)

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


func spawn_formation(leader_id: StringName, wingman_id: StringName, wingman_count: int, pos: Vector3, faction: StringName = &"hostile", station_node: Node3D = null) -> void:
	_encounter_counter += 1

	var parent =get_tree().current_scene.get_node_or_null("Universe")
	if parent == null:
		parent = get_tree().current_scene

	# Spawn leader
	var leader = ShipFactory.spawn_npc_ship(leader_id, &"aggressive", pos, parent, faction)
	if leader == null:
		return
	var leader_brain = leader.get_node_or_null("AIBrain")
	if leader_brain and station_node:
		leader_brain.guard_station = station_node
	_active_npc_ids.append(StringName(leader.name))
	leader.tree_exiting.connect(_on_npc_removed.bind(StringName(leader.name)))
	_register_npc_on_server(StringName(leader.name), leader_id, faction, leader)

	# Spawn wingmen in formation
	for i in wingman_count:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var row: int = i / 2 + 1
		var offset =Vector3(side * 60.0 * row, 0.0, 40.0 * row)
		var wing_pos: Vector3 = pos + offset

		var wingman = ShipFactory.spawn_npc_ship(wingman_id, &"balanced", wing_pos, parent, faction)
		if wingman:
			var brain = wingman.get_node_or_null("AIBrain")
			if brain:
				brain.formation_leader = leader
				brain.formation_offset = offset
				brain.current_state = AIBrain.State.FORMATION
				if station_node:
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

	# Compute gate positions
	var gate_positions: Array[Vector3] = []
	if system_data and system_data.jump_gates.size() > 0:
		for gd_gate in system_data.jump_gates:
			gate_positions.append(Vector3(gd_gate.pos_x, gd_gate.pos_y, gd_gate.pos_z))

	var key_points: Array[Vector3] = []
	key_points.append_array(station_positions)
	key_points.append_array(gate_positions)

	if station_positions.is_empty():
		station_positions.append(Vector3(500, 0, -1500))
		station_factions.append(default_faction)
	if key_points.is_empty():
		key_points.append(Vector3(500, 0, -1500))

	# Register virtual stations in EntityRegistry so AIBrain environment awareness works.
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
		if not npc_auth_ref.has_meta("virtual_stations"):
			npc_auth_ref.set_meta("virtual_stations", {})
		var vs_dict: Dictionary = npc_auth_ref.get_meta("virtual_stations")
		vs_dict[system_id] = virtual_station_ids

	# Set override so _register_npc_on_server uses the correct system_id
	_override_system_id = system_id

	# Spawn station guards (no scene nodes, use computed factions)
	_spawn_station_guards(station_positions, [], system_id, station_factions)

	# Spawn encounters based on danger level
	var configs := EncounterConfig.get_danger_config(danger_level)
	if danger_level == 5 and configs.size() >= 2:
		var st_pos: Vector3 = station_positions[0]
		var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
		var base_pos := st_pos + radial_dir * 2000.0 + Vector3(0, 100, 0)
		spawn_formation(configs[0]["ship"], configs[1]["ship"], configs[1]["count"], base_pos, configs[0]["fac"], null)
	else:
		var cfg_idx: int = 0
		for cfg in configs:
			var st_idx: int = cfg_idx % station_positions.size()
			var st_pos: Vector3 = station_positions[st_idx]
			if cfg_idx % 2 == 0 and key_points.size() >= 2:
				var route: Array[Vector3] = _build_system_route(st_pos, key_points)
				spawn_route_patrol(cfg["count"], cfg["ship"], route, cfg["fac"], system_id, cfg_idx)
			else:
				var radial_dir := st_pos.normalized() if st_pos.length_squared() > 1.0 else Vector3.FORWARD
				var base_pos := st_pos + radial_dir * 3000.0 + Vector3(0, 100, 0)
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
