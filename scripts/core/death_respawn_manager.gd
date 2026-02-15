class_name DeathRespawnManager
extends Node

# =============================================================================
# Death & Respawn Manager — handles player death, death screen, and respawn.
# Child Node of GameManager.
# =============================================================================

signal player_died
signal player_respawned

var _death_screen: Control = null
var _death_fade: float = 0.0

# Injected refs
var player_ship: RigidBody3D = null
var main_scene: Node3D = null
var galaxy: GalaxyData = null
var system_transition: SystemTransition = null
var route_manager: RouteManager = null
var fleet_deployment_mgr: FleetDeploymentManager = null
var discord_rpc: DiscordRPC = null
var toast_manager: UIToastManager = null
var docking_mgr: DockingManager = null
var docking_system: DockingSystem = null
var ship_change_mgr: ShipChangeManager = null


func _process(delta: float) -> void:
	if _death_screen:
		_death_fade = minf(_death_fade + delta * 1.5, 1.0)
		_death_screen.modulate.a = _death_fade


func handle_player_destroyed() -> void:
	if route_manager:
		route_manager.cancel_route()

	# Mark the active ship as permanently destroyed
	var fleet: PlayerFleet = GameManager.player_fleet
	if fleet:
		var active_fs := fleet.get_active()
		if active_fs:
			active_fs.deployment_state = FleetShip.DeploymentState.DESTROYED

	# Big explosion at player position
	_spawn_death_explosion()

	# Disable player controls & hide ship
	var ship := player_ship as ShipController
	if ship:
		ship.is_player_controlled = false
		ship.throttle_input = Vector3.ZERO
		ship.set_rotation_target(0, 0, 0)
		var act_ctrl := ship.get_node_or_null("ShipActivationController") as ShipActivationController
		if act_ctrl:
			act_ctrl.deactivate(ShipActivationController.DeactivationMode.FULL, true)

	# Hide flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = false

	# Show death screen with fade-in
	_death_fade = 0.0
	_create_death_screen()

	player_died.emit()


func handle_respawn() -> void:
	var fleet: PlayerFleet = GameManager.player_fleet
	if fleet == null:
		return

	# --- Find next usable ship ---
	var next_index: int = _find_respawn_ship(fleet)

	# If no ship at all, grant a free starter
	if next_index < 0:
		next_index = _grant_starter_ship(fleet)

	# Determine target system: nearest repair station to the respawn ship's system
	var respawn_fs := fleet.ships[next_index]
	var ship_sys: int = respawn_fs.docked_system_id
	if ship_sys < 0:
		ship_sys = system_transition.current_system_id if system_transition else 0
	var target_sys: int = ship_sys
	if galaxy:
		target_sys = galaxy.find_nearest_repair_system(target_sys)

	# Update the respawn ship's system to where we're actually going
	respawn_fs.docked_system_id = target_sys

	# Remove death screen
	if _death_screen and is_instance_valid(_death_screen):
		_death_screen.queue_free()
		_death_screen = null

	# Switch to the respawn ship if it's different from active
	if next_index != fleet.active_index and ship_change_mgr:
		ship_change_mgr.rebuild_ship_for_respawn(next_index)
	else:
		fleet.set_active(next_index)

	# Restore player ship
	_repair_ship()

	# Always do a full system reload (even for same system) to ensure
	# floating origin is reset and entities are freshly registered.
	if system_transition:
		system_transition.jump_to_system(target_sys)

	player_respawned.emit()

	# Auto-dock at nearest station
	_auto_dock_at_station()


## Find the best ship to respawn with: 1) first DOCKED, 2) recall a DEPLOYED, 3) -1 (none).
func _find_respawn_ship(fleet: PlayerFleet) -> int:
	# 1. First DOCKED ship (prefer same system, then any)
	var best_docked: int = -1
	var current_sys: int = system_transition.current_system_id if system_transition else 0
	for i in fleet.ships.size():
		if i == fleet.active_index:
			continue
		var fs := fleet.ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
			if best_docked < 0 or fs.docked_system_id == current_sys:
				best_docked = i
				if fs.docked_system_id == current_sys:
					break  # Prefer same system
	if best_docked >= 0:
		return best_docked

	# 2. Recall a DEPLOYED ship (closest system, or just any)
	for i in fleet.ships.size():
		if i == fleet.active_index:
			continue
		var fs := fleet.ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
			# Force-recall: mark as DOCKED
			fs.deployment_state = FleetShip.DeploymentState.DOCKED
			fs.deployed_npc_id = &""
			fs.deployed_command = &""
			fs.deployed_command_params = {}
			# Free the NPC node if it exists
			if fleet_deployment_mgr:
				var npc := fleet_deployment_mgr.get_deployed_npc(i)
				if npc and is_instance_valid(npc):
					EntityRegistry.unregister(npc.name)
					npc.queue_free()
				fleet_deployment_mgr._deployed_ships.erase(i)
			return i

	return -1


## Grant a free starter ship when all ships are destroyed.
func _grant_starter_ship(fleet: PlayerFleet) -> int:
	var starter_fs := FleetShip.create_bare(Constants.DEFAULT_SHIP_ID)
	if starter_fs == null:
		push_error("DeathRespawnManager: Failed to create starter ship!")
		return 0
	starter_fs.custom_name = "Vaisseau de secours"
	starter_fs.deployment_state = FleetShip.DeploymentState.DOCKED
	var sys_id: int = system_transition.current_system_id if system_transition else 0
	starter_fs.docked_system_id = sys_id
	var idx := fleet.add_ship(starter_fs)

	# Toast notification
	if GameManager._notif:
		GameManager._notif.toast("VAISSEAU DE SECOURS ATTRIBUÉ")

	return idx


func _auto_dock_at_station() -> void:
	var station_name: String = ""
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)

	# Prefer repair station
	for ent in stations:
		var extra: Dictionary = ent.get("extra", {})
		if extra.get("station_type", "") == "repair":
			station_name = ent.get("name", "")
			break

	# Any station
	if station_name == "" and stations.size() > 0:
		station_name = stations[0].get("name", "Station")

	# Read from system data if registry empty
	if station_name == "" and system_transition and system_transition.current_system_data:
		var sys_stations: Array = system_transition.current_system_data.stations
		if sys_stations.size() > 0:
			station_name = sys_stations[0].station_name

	# No station — jump to home system which always has one
	if station_name == "" and galaxy and system_transition:
		system_transition.jump_to_system(galaxy.player_home_system)
		stations = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
		if stations.size() > 0:
			station_name = stations[0].get("name", "Station")

	docking_system.is_docked = true
	docking_mgr.handle_docked(station_name)


func _spawn_death_explosion() -> void:
	if player_ship == null:
		return
	var pos: Vector3 = player_ship.global_position
	var scene_root := get_tree().current_scene

	# Main explosion (big)
	var main_exp := ExplosionEffect.new()
	scene_root.add_child(main_exp)
	main_exp.global_position = pos
	main_exp.scale = Vector3.ONE * 4.0

	# Secondary explosions with slight delays and offsets
	for i in 5:
		var timer := get_tree().create_timer(0.15 * (i + 1))
		var offset := Vector3(
			randf_range(-15.0, 15.0),
			randf_range(-10.0, 10.0),
			randf_range(-15.0, 15.0)
		)
		var scale_mult: float = randf_range(1.5, 3.0)
		timer.timeout.connect(_spawn_delayed_explosion.bind(pos + offset, scale_mult))


func _spawn_delayed_explosion(pos: Vector3, scale_mult: float) -> void:
	var explosion := ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * scale_mult


func _create_death_screen() -> void:
	_death_screen = Control.new()
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.modulate.a = 0.0

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.02, 0.7)
	_death_screen.add_child(overlay)

	var title := Label.new()
	title.text = "VAISSEAU DÉTRUIT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -60
	title.offset_bottom = 0
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1, 1.0))
	_death_screen.add_child(title)

	var prompt := Label.new()
	prompt.text = "Appuyez sur [R] pour respawn à la station la plus proche"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 20
	prompt.offset_bottom = 60
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85, 0.8))
	_death_screen.add_child(prompt)

	var ui_layer := main_scene.get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_death_screen)
	else:
		main_scene.add_child(_death_screen)


func _repair_ship() -> void:
	var ship := player_ship as ShipController
	if ship == null:
		return

	# Restore ship via activation controller (collision, visibility, group, map, targeting)
	var act_ctrl := ship.get_node_or_null("ShipActivationController") as ShipActivationController
	if act_ctrl:
		act_ctrl.activate()

	ship.is_player_controlled = true
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO

	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.revive()

	var energy := ship.get_node_or_null("EnergySystem") as EnergySystem
	if energy:
		energy.energy_current = energy.energy_max
		energy.reset_pips()

	ship.speed_mode = Constants.SpeedMode.NORMAL
	ship.combat_locked = false
	ship.cruise_warp_active = false
	ship.cruise_time = 0.0
