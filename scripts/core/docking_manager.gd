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
var docking_system: DockingSystem = null
var dock_instance: DockInstance = null
var screen_manager: UIScreenManager = null
var player_data: PlayerData = null
var commerce_manager: CommerceManager = null
var commerce_screen: CommerceScreen = null
var equipment_screen: EquipmentScreen = null
var station_screen: StationScreen = null
var admin_screen: StationAdminScreen = null
var system_transition: SystemTransition = null
var route_manager: RouteManager = null
var fleet_deployment_mgr: FleetDeploymentManager = null
var lod_manager: ShipLODManager = null
var encounter_manager: EncounterManager = null
var ship_net_sync: ShipNetworkSync = null
var discord_rpc: DiscordRPC = null
var notif: NotificationService = null
var get_game_state: Callable

var docked_station_idx: int = 0


func handle_docked(station_name: String) -> void:
	if route_manager:
		route_manager.cancel_route()

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

	# Resolve station index from EntityRegistry
	docked_station_idx = 0
	var resolved_station_id: String = ""
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == station_name:
			var extra: Dictionary = ent.get("extra", {})
			docked_station_idx = extra.get("station_index", 0)
			resolved_station_id = ent.get("id", "")
			break

	# Update active fleet ship's docking info
	var fleet: PlayerFleet = player_data.fleet if player_data else null
	if fleet:
		var active_fs := fleet.get_active()
		if active_fs:
			active_fs.docked_station_id = resolved_station_id
			active_fs.docked_system_id = GameManager.current_system_id_safe()

	# Hide flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
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
	if state_val != GameManagerSystem.GameState.DOCKED:
		return
	# Close station UI
	if screen_manager:
		screen_manager.close_screen("station")

	# Leave isolated solo instance
	dock_instance.leave(_build_dock_context(""))

	# Re-enable ship controls
	var ship := player_ship as ShipController
	if ship:
		ship.is_player_controlled = true

	# Reposition player near the docked station (random within 5km)
	_reposition_at_station()

	# Show flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	# Undock from docking system
	if docking_system:
		docking_system.request_undock()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	undocked.emit()


const UNDOCK_RADIUS: float = 5000.0  ## Spawn within 5km of station

func _reposition_at_station() -> void:
	if docking_system == null or player_ship == null:
		return
	var station_node: Node3D = docking_system.nearest_station_node
	if station_node == null or not is_instance_valid(station_node):
		return

	# Random direction on the XZ plane, random distance within radius
	var angle: float = randf() * TAU
	var dist: float = randf_range(UNDOCK_RADIUS * 0.3, UNDOCK_RADIUS)
	var offset := Vector3(cos(angle) * dist, randf_range(-200.0, 200.0), sin(angle) * dist)
	var new_pos: Vector3 = station_node.global_position + offset

	player_ship.global_position = new_pos
	player_ship.linear_velocity = Vector3.ZERO
	player_ship.angular_velocity = Vector3.ZERO


func handle_commerce_requested() -> void:
	if commerce_screen == null or screen_manager == null or commerce_manager == null:
		return
	var stype: int = 0
	var sname: String = dock_instance.station_name if dock_instance else "STATION"
	var resolved_station_id: String = ""
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
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
	if state_val != GameManagerSystem.GameState.DOCKED:
		return
	open_station_terminal()


func handle_equipment_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != GameManagerSystem.GameState.DOCKED:
		return
	open_station_terminal()


func handle_repair_requested() -> void:
	if dock_instance and player_ship:
		dock_instance.repair_ship(player_ship)
		if notif:
			notif.general.repair()


func handle_equipment_requested() -> void:
	if equipment_screen == null or screen_manager == null:
		return
	equipment_screen.player_inventory = player_data.inventory if player_data else null
	equipment_screen.player_fleet = player_data.fleet if player_data else null
	var wm := player_ship.get_node_or_null("WeaponManager") as WeaponManager
	equipment_screen.weapon_manager = wm
	var em := player_ship.get_node_or_null("EquipmentManager") as EquipmentManager
	equipment_screen.equipment_manager = em
	var ship_model := player_ship.get_node_or_null("ShipModel") as ShipModel
	var ship_ctrl := player_ship as ShipController
	var center_off := ship_ctrl.center_offset if ship_ctrl else Vector3.ZERO
	var root_basis: Basis = Basis.IDENTITY
	var hp_root := player_ship.get_node_or_null("HardpointRoot") as Node3D
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
	var station_eq: StationEquipment = _get_docked_station_equipment()
	if station_eq == null:
		return
	var adapter := StationEquipAdapter.create(station_eq, player_data.inventory if player_data else null)
	equipment_screen.station_equip_adapter = adapter
	equipment_screen.player_inventory = player_data.inventory if player_data else null
	equipment_screen.player_fleet = player_data.fleet if player_data else null
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("equipment")


func _get_docked_station_equipment() -> StationEquipment:
	var universe := main_scene.get_node_or_null("Universe") if main_scene else null
	if universe == null:
		return null
	var station_node: SpaceStation = universe.get_node_or_null("Station_%d" % docked_station_idx) as SpaceStation
	if station_node and station_node.station_equipment:
		return station_node.station_equipment
	# Fallback: create from GameManager cache
	var sys_id: int = system_transition.current_system_id if system_transition else 0
	var key := "system_%d_station_%d" % [sys_id, docked_station_idx]
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
	var station_node: SpaceStation = null
	var entity_id: String = ""
	var universe := main_scene.get_node_or_null("Universe") if main_scene else null
	if universe:
		station_node = universe.get_node_or_null("Station_%d" % docked_station_idx) as SpaceStation
	# Search EntityRegistry for entity ID
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == sname:
			entity_id = ent.get("id", "")
			# If no node from Universe, try node ref from entity
			if station_node == null:
				station_node = ent.get("node") as SpaceStation
			break
	if station_node == null:
		return
	admin_screen.setup(station_node, entity_id)
	screen_manager.close_screen("station")
	await get_tree().process_frame
	screen_manager.open_screen("admin")


func handle_admin_closed() -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != GameManagerSystem.GameState.DOCKED:
		return
	open_station_terminal()


func _clear_npc_targets_on_player() -> void:
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
		"universe_node": main_scene.get_node_or_null("Universe") if main_scene else null,
		"main_scene": main_scene,
		"lod_manager": lod_manager,
		"encounter_manager": encounter_manager,
		"net_sync": ship_net_sync,
	}
