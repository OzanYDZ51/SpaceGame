class_name DockingManager
extends Node

# =============================================================================
# Docking Manager — handles dock/undock flow, station screens, commerce, equipment.
# Child Node of GameManager.
# =============================================================================

signal docked(station_name: String)
signal undocked

# Injected refs
var player_ship: RigidBody3D = null
var main_scene: Node3D = null
var docking_system = null
var dock_instance = null
var screen_manager = null
var player_data = null
var commerce_manager = null
var commerce_screen = null
var equipment_screen = null
var shipyard_screen = null
var station_screen = null
var admin_screen = null
var refinery_screen: Control = null  # RefineryScreen (UIScreen)
var storage_screen: Control = null   # StorageScreen (UIScreen)
var system_transition = null
var route_manager = null
var fleet_deployment_mgr = null
var lod_manager = null
var encounter_manager = null
var ship_net_sync = null
var discord_rpc: DiscordRPC = null
var notif: NotificationService = null
var get_game_state: Callable

var docked_station_idx: int = 0
var _docked_death_handler: Node = null  # StructureDeathHandler of docked station


func handle_docked(station_name: String) -> void:
	if route_manager:
		route_manager.cancel_route()

	# Stop ship controls + autopilot
	var ship = player_ship
	if ship:
		ship.disengage_autopilot()
		ship.is_player_controlled = false
		ship.throttle_input = Vector3.ZERO
		ship.set_rotation_target(0, 0, 0)
		ship.linear_velocity = Vector3.ZERO
		ship.angular_velocity = Vector3.ZERO

	# Force NPCs to drop player as target before freezing world
	_clear_npc_targets_on_player()

	# Resolve station index from EntityRegistry
	docked_station_idx = 0
	var resolved_station_id: String = ""
	var stations =EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == station_name:
			var extra: Dictionary = ent.get("extra", {})
			docked_station_idx = extra.get("station_index", 0)
			resolved_station_id = ent.get("id", "")
			break

	# Update active fleet ship's docking info
	var fleet = player_data.fleet if player_data else null
	if fleet:
		var active_fs = fleet.get_active()
		if active_fs:
			active_fs.docked_station_id = resolved_station_id
			active_fs.docked_system_id = GameManager.current_system_id_safe()

	# Connect to station destruction: if our docked station blows up, player dies
	_connect_station_destruction()

	# Hide flight HUD
	var hud =main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = false

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Emit docked BEFORE entering dock instance, so GameManager sets current_state = DOCKED
	# before force_send_now() fires — ensuring remote peers receive is_docked=true
	docked.emit(station_name)

	# Enter isolated solo instance (freezes world, sends final docked state, loads hangar)
	dock_instance.enter(_build_dock_context(station_name))


func handle_undock() -> bool:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return false

	print("[DockMgr] === UNDOCK START === connected=%s" % str(NetworkManager.is_connected_to_server()))

	_disconnect_station_destruction()

	# Automatically find a clear exit position (bay exit + ring around station)
	var exit_info: Dictionary = _compute_exit_position()
	if not exit_info.get("valid", false):
		if notif:
			notif.general.undock_blocked()
		return false

	# Close station UI
	if screen_manager:
		screen_manager.close_screen("station")

	# Leave isolated solo instance (unfreeze world)
	dock_instance.leave(_build_dock_context(""))

	# Re-enable ship controls
	var ship = player_ship
	if ship:
		ship.is_player_controlled = true

	# Teleport to exit position
	_reposition_at_station(exit_info)

	# Show flight HUD
	var hud = main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	# Undock from docking system
	if docking_system:
		docking_system.request_undock()

	# Clear docking info on fleet ship so save state reflects we're in space
	var fleet = player_data.fleet if player_data else null
	if fleet:
		var active_fs = fleet.get_active()
		if active_fs:
			active_fs.docked_station_id = ""
			active_fs.docked_system_id = GameManager.current_system_id_safe()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[DockMgr] === UNDOCK EMIT === connected=%s" % str(NetworkManager.is_connected_to_server()))
	undocked.emit()
	return true


# ---------------------------------------------------------------------------
# Smart undock: ship-size-aware exit distance + multi-candidate clearance
# ---------------------------------------------------------------------------
const UNDOCK_EXIT_MARGIN: float = 100.0      ## Base safety buffer on top of ship size
const UNDOCK_MIN_EXIT_DIST: float = 200.0    ## Minimum exit distance (small ships)
const UNDOCK_CLEARANCE_BUFFER: float = 50.0  ## Extra margin for obstacle check
const UNDOCK_RING_SLOTS: int = 8             ## Candidate positions around station
const UNDOCK_RING_MIN_DIST: float = 1000.0   ## Minimum ring distance from station center


func _get_ship_half_extent() -> float:
	## Returns the player ship's half-extent from its visual AABB.
	var ship_model = player_ship.get_node_or_null("ShipModel")
	var aabb: AABB = ship_model.get_visual_aabb()
	return aabb.size.length() * 0.5


func _compute_exit_distance(ship_half: float) -> float:
	## Compute how far from the exit point the ship should be placed.
	## Margin grows with ship size — larger ships get more clearance.
	var margin: float = maxf(UNDOCK_EXIT_MARGIN, ship_half * 0.5)
	return maxf(ship_half + margin, UNDOCK_MIN_EXIT_DIST)


func _compute_exit_position() -> Dictionary:
	## Automatically finds a clear exit position near the docked station.
	## Tries bay exit first, then a ring of positions around the station.
	## Distance scales with ship size. Returns first unblocked candidate.
	## Result: {valid, position, away_dir, ship_half_extent, use_bay}.
	var ship_half: float = _get_ship_half_extent()
	var exit_dist: float = _compute_exit_distance(ship_half)

	# Resolve station node from DockingSystem or EntityRegistry
	var station_node: Node3D = null
	var station_pos: Vector3 = Vector3.ZERO

	if docking_system and is_instance_valid(docking_system.nearest_station_node):
		station_node = docking_system.nearest_station_node
		station_pos = station_node.global_position
	else:
		var stations = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
		for ent in stations:
			var extra: Dictionary = ent.get("extra", {})
			if extra.get("station_index", -1) == docked_station_idx:
				station_node = ent.get("node")
				station_pos = station_node.global_position if is_instance_valid(station_node) else FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
				break

	# Build candidate exit positions ordered by priority
	var candidates: Array[Dictionary] = []

	# Priority 1: Bay exit (straight out of the docking bay)
	if is_instance_valid(station_node) and station_node.has_method("get_bay_exit_global"):
		var bay_exit: Vector3 = station_node.get_bay_exit_global()
		var away_dir: Vector3 = (bay_exit - station_pos).normalized()
		candidates.append({
			"valid": true,
			"position": bay_exit + away_dir * exit_dist,
			"away_dir": away_dir,
			"ship_half_extent": ship_half,
			"use_bay": true,
		})

	# Priority 2: Ring of positions around station (horizontal plane)
	# Distance scales with ship size so large ships spawn further out
	var ring_dist: float = maxf(exit_dist + 800.0, UNDOCK_RING_MIN_DIST)
	for i in UNDOCK_RING_SLOTS:
		var angle: float = i * TAU / float(UNDOCK_RING_SLOTS)
		var offset := Vector3(cos(angle) * ring_dist, 0.0, sin(angle) * ring_dist)
		var pos: Vector3 = station_pos + offset
		pos.y += randf_range(-50.0, 50.0)
		candidates.append({
			"valid": true,
			"position": pos,
			"away_dir": offset.normalized(),
			"ship_half_extent": ship_half,
			"use_bay": false,
		})

	# Return the first candidate with a clear exit zone
	for candidate in candidates:
		if _is_exit_clear(candidate):
			return candidate

	# All slots occupied
	return {"valid": false}


func _is_exit_clear(exit_info: Dictionary) -> bool:
	## Check if the exit position is free of other ships using EntityRegistry.
	## Works while docked (world frozen) because EntityRegistry has float64 positions.
	var local_pos: Vector3 = exit_info["position"]
	var ship_half: float = exit_info["ship_half_extent"]
	var block_radius: float = ship_half * 2.0 + UNDOCK_CLEARANCE_BUFFER
	var block_radius_sq: float = block_radius * block_radius

	# Convert exit position to universe coordinates
	var exit_ux: float = local_pos.x + FloatingOrigin.origin_offset_x
	var exit_uy: float = local_pos.y + FloatingOrigin.origin_offset_y
	var exit_uz: float = local_pos.z + FloatingOrigin.origin_offset_z

	# Check against all ship types
	var types: Array = [
		EntityRegistrySystem.EntityType.SHIP_PLAYER,
		EntityRegistrySystem.EntityType.SHIP_NPC,
		EntityRegistrySystem.EntityType.SHIP_FLEET,
	]
	for etype in types:
		var entities: Array[Dictionary] = EntityRegistry.get_by_type(etype)
		for ent in entities:
			if ent.get("id", "") == "player_ship":
				continue
			var dx: float = ent["pos_x"] - exit_ux
			var dy: float = ent["pos_y"] - exit_uy
			var dz: float = ent["pos_z"] - exit_uz
			if dx * dx + dy * dy + dz * dz < block_radius_sq:
				return false
	return true


func _reposition_at_station(exit_info: Dictionary) -> void:
	player_ship.global_position = exit_info["position"]
	var away: Vector3 = exit_info["away_dir"]
	var up := Vector3.UP
	if absf(away.dot(up)) > 0.99:
		up = Vector3.FORWARD
	player_ship.look_at(exit_info["position"] + away, up)
	player_ship.linear_velocity = Vector3.ZERO
	player_ship.angular_velocity = Vector3.ZERO


func handle_commerce_requested() -> void:
	if commerce_screen == null or screen_manager == null or commerce_manager == null:
		return
	var stype: int = 0
	var sname: String = dock_instance.station_name if dock_instance else "STATION"
	var resolved_station_id: String = ""
	var stations =EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == sname:
			resolved_station_id = ent.get("id", "")
			var extra: Dictionary = ent.get("extra", {})
			var type_str: String = extra.get("station_type", "repair")
			match type_str:
				"repair": stype = 0
				"trade": stype = 1
				"military": stype = 2
				"mining": stype = 3
			break
	commerce_screen.setup(commerce_manager, stype, sname, resolved_station_id)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("commerce")


func handle_commerce_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func handle_shipyard_requested() -> void:
	if shipyard_screen == null or screen_manager == null or commerce_manager == null:
		return
	var stype: int = 0
	var sname: String = dock_instance.station_name if dock_instance else "STATION"
	var resolved_station_id: String = ""
	var stations =EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == sname:
			resolved_station_id = ent.get("id", "")
			var extra: Dictionary = ent.get("extra", {})
			var type_str: String = extra.get("station_type", "repair")
			match type_str:
				"repair": stype = 0
				"trade": stype = 1
				"military": stype = 2
				"mining": stype = 3
			break
	shipyard_screen.setup(commerce_manager, stype, sname, resolved_station_id)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("shipyard")


func handle_shipyard_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func handle_equipment_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func handle_repair_requested() -> void:
	if dock_instance and player_ship:
		dock_instance.repair_ship(player_ship)

	# Recover destroyed fleet ships → DOCKED at this station
	var fleet = player_data.fleet if player_data else null
	var recovered_count: int = 0
	if fleet:
		var active_fs = fleet.get_active()
		var station_id: String = active_fs.docked_station_id if active_fs else ""
		var system_id: int = active_fs.docked_system_id if active_fs else -1

		for i in fleet.ships.size():
			if i == fleet.active_index:
				continue
			var fs =fleet.ships[i]
			if fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
				fs.deployment_state = FleetShip.DeploymentState.DOCKED
				fs.docked_station_id = station_id
				fs.docked_system_id = system_id
				fs.deployed_npc_id = &""
				fs.deployed_command = &""
				fs.deployed_command_params = {}
				recovered_count += 1

		if recovered_count > 0:
			fleet.fleet_changed.emit()

	if notif:
		notif.general.repair(recovered_count)


func handle_equipment_requested() -> void:
	if equipment_screen == null or screen_manager == null:
		return
	equipment_screen.player_inventory = player_data.inventory if player_data else null
	equipment_screen.player_fleet = player_data.fleet if player_data else null
	var wm = player_ship.get_node_or_null("WeaponManager")
	equipment_screen.weapon_manager = wm
	var em = player_ship.get_node_or_null("EquipmentManager")
	equipment_screen.equipment_manager = em
	var ship_model = player_ship.get_node_or_null("ShipModel")
	var ship_ctrl = player_ship
	var center_off =ship_ctrl.center_offset if ship_ctrl else Vector3.ZERO
	var root_basis: Basis = Basis.IDENTITY
	var hp_root = player_ship.get_node_or_null("HardpointRoot")
	if hp_root:
		root_basis = hp_root.transform.basis
	if ship_model:
		equipment_screen.setup_ship_viewer(ship_model.model_path, ship_model.model_scale, center_off, ship_model.model_rotation_degrees, root_basis)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("equipment")


func handle_station_equipment_requested() -> void:
	if equipment_screen == null or screen_manager == null:
		return
	# Resolve docked station's StationEquipment
	var station_eq = _get_docked_station_equipment()
	if station_eq == null:
		return
	var adapter =StationEquipAdapter.create(station_eq, player_data.inventory if player_data else null)
	equipment_screen.station_equip_adapter = adapter
	equipment_screen.player_inventory = player_data.inventory if player_data else null
	equipment_screen.player_fleet = player_data.fleet if player_data else null
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("equipment")


func _get_docked_station_equipment() -> StationEquipment:
	var universe =main_scene.get_node_or_null("Universe") if main_scene else null
	if universe == null:
		return null
	var station_node = universe.get_node_or_null("Station_%d" % docked_station_idx)
	if station_node and station_node.station_equipment:
		return station_node.station_equipment
	# Fallback: create from GameManager cache
	var sys_id: int = system_transition.current_system_id if system_transition else 0
	var key ="system_%d_station_%d" % [sys_id, docked_station_idx]
	if GameManager.station_equipments.has(key):
		return GameManager.station_equipments[key]
	return null


func open_station_terminal() -> void:
	if station_screen:
		station_screen.set_station_name(dock_instance.station_name if dock_instance else "")
		var sys_id: int = system_transition.current_system_id if system_transition else 0
		station_screen.setup(player_data.station_services if player_data else null, sys_id, docked_station_idx, player_data.economy if player_data else null)
	if screen_manager:
		screen_manager.open_screen("station")


func handle_administration_requested() -> void:
	if admin_screen == null or screen_manager == null:
		return
	# Resolve docked station node + entity ID
	var sname: String = dock_instance.station_name if dock_instance else ""
	var station_node = null
	var entity_id: String = ""
	var universe =main_scene.get_node_or_null("Universe") if main_scene else null
	if universe:
		station_node = universe.get_node_or_null("Station_%d" % docked_station_idx)
	# Search EntityRegistry for entity ID
	var stations =EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == sname:
			entity_id = ent.get("id", "")
			# If no node from Universe, try node ref from entity
			if station_node == null:
				station_node = ent.get("node")
			break
	if station_node == null:
		return
	admin_screen.setup(station_node, entity_id)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("admin")


func handle_admin_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func handle_refinery_requested() -> void:
	if refinery_screen == null or screen_manager == null or player_data == null:
		return
	var sname: String = dock_instance.station_name if dock_instance else "STATION"
	var sys_id: int = system_transition.current_system_id if system_transition else 0
	var station_key: String = RefineryManager.make_key(sys_id, docked_station_idx)
	refinery_screen.setup(player_data, station_key, sname)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("refinery")


func handle_refinery_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func handle_storage_requested() -> void:
	if storage_screen == null or screen_manager == null or player_data == null:
		return
	var sname: String = dock_instance.station_name if dock_instance else "STATION"
	var sys_id: int = system_transition.current_system_id if system_transition else 0
	var station_key: String = RefineryManager.make_key(sys_id, docked_station_idx)
	storage_screen.setup(player_data, station_key, sname)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("storage")


func handle_storage_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	open_station_terminal()


func _clear_npc_targets_on_player() -> void:
	for npc in get_tree().get_nodes_in_group("ships"):
		if npc == player_ship:
			continue
		var targeting = npc.get_node_or_null("TargetingSystem")
		if targeting and targeting.current_target == player_ship:
			targeting.clear_target()
		var brain = npc.get_node_or_null("AIBrain")
		if brain:
			brain.target = null


func _build_dock_context(station_name: String) -> Dictionary:
	return {
		"station_name": station_name,
		"player_ship": player_ship,
		"universe_node": main_scene.get_node_or_null("Universe") if main_scene else null,
		"main_scene": main_scene,
		"lod_manager": lod_manager,
		"encounter_manager": encounter_manager,
		"net_sync": ship_net_sync,
	}


# =============================================================================
# STATION DESTRUCTION WHILE DOCKED
# =============================================================================

func _connect_station_destruction() -> void:
	_disconnect_station_destruction()
	var universe = main_scene.get_node_or_null("Universe") if main_scene else null
	if universe == null:
		return
	var station_node = universe.get_node_or_null("Station_%d" % docked_station_idx)
	if station_node == null:
		return
	var death_handler = station_node.get_node_or_null("StructureDeathHandler")
	if death_handler and death_handler.has_signal("station_destroyed"):
		_docked_death_handler = death_handler
		death_handler.station_destroyed.connect(_on_docked_station_destroyed)


func _disconnect_station_destruction() -> void:
	if _docked_death_handler and is_instance_valid(_docked_death_handler):
		if _docked_death_handler.station_destroyed.is_connected(_on_docked_station_destroyed):
			_docked_death_handler.station_destroyed.disconnect(_on_docked_station_destroyed)
	_docked_death_handler = null


func _on_docked_station_destroyed(_station_name: String) -> void:
	print("DockingManager: Docked station '%s' destroyed — ejecting player!" % _station_name)
	_disconnect_station_destruction()

	# Close all open station UI screens
	if screen_manager:
		while screen_manager.is_any_screen_open():
			screen_manager.close_top()

	# Force leave dock instance (unfreeze world)
	if dock_instance:
		dock_instance.leave(_build_dock_context(""))

	# Clear docked state
	if docking_system:
		docking_system.is_docked = false

	# Show flight HUD briefly before death
	var hud = main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	# Re-enable ship so the death handler can process it
	var ship = player_ship
	if ship:
		ship.is_player_controlled = true
		var act_ctrl = ship.get_node_or_null("ShipActivationController")
		if act_ctrl:
			act_ctrl.activate()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	undocked.emit()

	# Kill the player — triggers death screen → respawn at nearest alive station
	GameManager._on_player_destroyed()
