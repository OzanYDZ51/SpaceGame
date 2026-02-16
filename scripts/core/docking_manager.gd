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


func handle_undock() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED:
		return
	# Close station UI
	if screen_manager:
		screen_manager.close_screen("station")

	# Leave isolated solo instance
	dock_instance.leave(_build_dock_context(""))

	# Re-enable ship controls
	var ship = player_ship
	if ship:
		ship.is_player_controlled = true

	# Reposition player near the docked station (random within 5km)
	_reposition_at_station()

	# Show flight HUD
	var hud =main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	# Undock from docking system
	if docking_system:
		docking_system.request_undock()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	undocked.emit()


const UNDOCK_EXIT_DISTANCE: float = 300.0  ## Distance ahead of bay exit

func _reposition_at_station() -> void:
	if player_ship == null:
		return

	# Resolve station node — prefer live node, fallback to EntityRegistry
	var station_node: Node3D = null
	var station_pos: Vector3 = Vector3.ZERO
	var found: bool = false

	if docking_system and docking_system.nearest_station_node != null and is_instance_valid(docking_system.nearest_station_node):
		station_node = docking_system.nearest_station_node
		station_pos = station_node.global_position
		found = true
	else:
		# Fallback: find station from EntityRegistry using docked_station_idx
		var stations = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
		for ent in stations:
			var extra: Dictionary = ent.get("extra", {})
			if extra.get("station_index", -1) == docked_station_idx:
				var node_ref = ent.get("node")
				if node_ref != null and is_instance_valid(node_ref):
					station_node = node_ref
					station_pos = station_node.global_position
				else:
					station_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
				found = true
				break

	if not found:
		return

	# Prefer exiting from bay if station has get_bay_exit_global()
	if station_node and station_node.has_method("get_bay_exit_global"):
		var bay_exit: Vector3 = station_node.get_bay_exit_global()
		# Face away from station center
		var away_dir: Vector3 = (bay_exit - station_pos).normalized()
		if away_dir.length_squared() < 0.01:
			away_dir = Vector3.FORWARD
		var new_pos: Vector3 = bay_exit + away_dir * UNDOCK_EXIT_DISTANCE
		player_ship.global_position = new_pos
		# Orient ship to face away from station
		player_ship.look_at(new_pos + away_dir, Vector3.UP)
	else:
		# Fallback: random position around station
		var angle: float = randf() * TAU
		var dist: float = randf_range(1800.0, 2200.0)
		var offset = Vector3(cos(angle) * dist, randf_range(-100.0, 100.0), sin(angle) * dist)
		player_ship.global_position = station_pos + offset

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
