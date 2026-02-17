class_name DockInstance
extends Node

# =============================================================================
# Dock Instance - Isolated solo context for station docking
# Freezes the space world using process_mode (cascades to all children),
# loads the hangar scene, and cleanly restores everything on undock.
# =============================================================================

signal entered(station_name: String)
signal left()
signal ship_change_requested(fleet_index: int)

var is_active: bool = false
var station_name: String = ""
var hangar_scene = null


func enter(ctx: Dictionary) -> void:
	if is_active:
		return
	is_active = true
	station_name = ctx.get("station_name", "Station")
	print("[DockInstance] ENTER: station=%s connected=%s" % [station_name, str(NetworkManager.is_connected_to_server())])

	var player_ship: RigidBody3D = ctx["player_ship"]
	var universe_node: Node3D = ctx["universe_node"]
	var main_scene: Node3D = ctx["main_scene"]

	# --- 1. FREEZE WORLD (one line per subtree) ---
	# Cascades to ALL children: NPCs, remote players, dust, stations, etc.
	universe_node.process_mode = Node.PROCESS_MODE_DISABLED
	universe_node.visible = false

	# Freeze GameManager world systems (LOD, encounters) if provided
	var lod_manager: Node = ctx.get("lod_manager")
	if lod_manager:
		lod_manager.process_mode = Node.PROCESS_MODE_DISABLED

	var encounter_manager: Node = ctx.get("encounter_manager")
	if encounter_manager:
		encounter_manager.process_mode = Node.PROCESS_MODE_DISABLED

	# Send "docked" state so remote puppets hide immediately.
	# Keep ShipNetworkSync alive (ALWAYS) so it continues sending is_docked=true
	# at 20Hz — this keeps the WebSocket connection alive through NAT/proxy timeouts.
	var net_sync: Node = ctx.get("net_sync")
	if not is_instance_valid(net_sync):
		net_sync = player_ship.get_node_or_null("ShipNetworkSync")
	if net_sync and is_instance_valid(net_sync):
		if net_sync.has_method("force_send_now"):
			net_sync.force_send_now()
		net_sync.process_mode = Node.PROCESS_MODE_ALWAYS

	# --- 2. DEACTIVATE PLAYER SHIP ---
	var act_ctrl = player_ship.get_node_or_null("ShipActivationController")
	if act_ctrl:
		act_ctrl.deactivate(ShipActivationController.DeactivationMode.FULL)

	# --- 3. HIDE SPACE LIGHTING ---
	for node_name in ["StarLight", "SystemStar"]:
		var node =main_scene.get_node_or_null(node_name) as Node3D
		if node:
			node.visible = false

	# --- 4. LOAD HANGAR (skip on dedicated server or if asset missing) ---
	if not OS.has_feature("dedicated_server"):
		var hangar_packed = load("res://scenes/station/hangar_interior.tscn") as PackedScene
		if hangar_packed:
			hangar_scene = hangar_packed.instantiate()
			main_scene.add_child(hangar_scene)
			hangar_scene.activate()

			# Display player ship model in hangar (with equipped weapons)
			var ship_model = player_ship.get_node_or_null("ShipModel")
			var wm = player_ship.get_node_or_null("WeaponManager")
			if ship_model:
				var hp_configs: Array[Dictionary] = []
				var weapon_names: Array[StringName] = []
				if wm:
					for hp in wm.hardpoints:
						hp_configs.append({"position": hp.position, "rotation_degrees": hp.rotation_degrees, "id": hp.slot_id, "size": hp.slot_size, "is_turret": hp.is_turret})
						weapon_names.append(hp.mounted_weapon.weapon_name if hp.mounted_weapon else &"")
				# Get root_basis from HardpointRoot node for correct weapon positioning
				var root_basis: Basis = Basis.IDENTITY
				var hp_root =player_ship.get_node_or_null("HardpointRoot") as Node3D
				if hp_root:
					root_basis = hp_root.transform.basis

				hangar_scene.display_ship(ship_model.model_path, ship_model.model_scale, hp_configs, weapon_names, ship_model.model_rotation_degrees, root_basis)

			# Setup ship selection cycling (A/D keys) — only owned ships
			var fleet_indices: Array = _get_switchable_fleet_indices()
			var active_idx: int = GameManager.player_fleet.active_index if GameManager.player_fleet else 0
			hangar_scene.setup_ship_selection(active_idx, fleet_indices)
			if not hangar_scene.ship_selected.is_connected(_on_hangar_ship_selected):
				hangar_scene.ship_selected.connect(_on_hangar_ship_selected)

			# Refresh hangar list when fleet changes (e.g. buying a new ship)
			if GameManager.player_fleet and not GameManager.player_fleet.fleet_changed.is_connected(_on_fleet_changed):
				GameManager.player_fleet.fleet_changed.connect(_on_fleet_changed)
		else:
			push_warning("DockInstance: hangar_interior.tscn failed to load — skipping hangar visuals")

	entered.emit(station_name)


func leave(ctx: Dictionary) -> void:
	if not is_active:
		return

	var player_ship: RigidBody3D = ctx["player_ship"]
	var universe_node: Node3D = ctx["universe_node"]
	var main_scene: Node3D = ctx["main_scene"]

	# --- 1. REMOVE HANGAR ---
	if hangar_scene:
		hangar_scene.deactivate()
		hangar_scene.queue_free()
		hangar_scene = null

	# --- 2. RESTORE SPACE VISUALS ---
	universe_node.visible = true
	for node_name in ["StarLight", "SystemStar"]:
		var node =main_scene.get_node_or_null(node_name) as Node3D
		if node:
			node.visible = true

	# --- 3. UNFREEZE WORLD ---
	universe_node.process_mode = Node.PROCESS_MODE_INHERIT
	var lod_manager: Node = ctx.get("lod_manager")
	if lod_manager:
		lod_manager.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		push_warning("DockInstance.leave: lod_manager is NULL — LOD stays DISABLED!")
	var encounter_manager: Node = ctx.get("encounter_manager")
	if encounter_manager:
		encounter_manager.process_mode = Node.PROCESS_MODE_INHERIT
	# Restore network sync to normal mode.
	# NOTE: Do NOT call force_send_now() here — current_state is still DOCKED at this point.
	# The proper force_send_now (with is_docked=false) happens in the GM undock handler
	# AFTER current_state = PLAYING.
	var net_sync: Node = ctx.get("net_sync")
	if not is_instance_valid(net_sync):
		net_sync = player_ship.get_node_or_null("ShipNetworkSync")
	if net_sync and is_instance_valid(net_sync):
		net_sync.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		push_warning("DockInstance.leave: net_sync is NULL — ShipNetworkSync NOT restored!")

	print("[DockInstance] LEAVE: universe_pm=%d lod_pm=%d enc_pm=%d connected=%s" % [
		universe_node.process_mode,
		lod_manager.process_mode if lod_manager else -1,
		encounter_manager.process_mode if encounter_manager else -1,
		str(NetworkManager.is_connected_to_server()),
	])

	# --- 4. RESTORE PLAYER SHIP ---
	var act_ctrl = player_ship.get_node_or_null("ShipActivationController")
	if act_ctrl:
		act_ctrl.activate()

	# --- 5. RESTORE CAMERA ---
	var ship_cam =player_ship.get_node_or_null("ShipCamera") as Camera3D
	if ship_cam:
		ship_cam.current = true

	# Disconnect fleet change listener
	if GameManager.player_fleet and GameManager.player_fleet.fleet_changed.is_connected(_on_fleet_changed):
		GameManager.player_fleet.fleet_changed.disconnect(_on_fleet_changed)

	is_active = false
	station_name = ""
	left.emit()


func _on_hangar_ship_selected(fleet_index: int) -> void:
	ship_change_requested.emit(fleet_index)


func _on_fleet_changed() -> void:
	if hangar_scene == null or not is_active:
		return
	var fleet_indices: Array = _get_switchable_fleet_indices()
	var active_idx: int = GameManager.player_fleet.active_index if GameManager.player_fleet else 0
	hangar_scene.refresh_ship_list(active_idx, fleet_indices)


func _get_switchable_fleet_indices() -> Array:
	var result: Array[int] = []
	if GameManager.player_fleet == null:
		return result
	# Only show ships docked at THIS station
	var current_station_id: String = ""
	var active_fs = GameManager.player_fleet.get_active()
	if active_fs:
		current_station_id = active_fs.docked_station_id
	for i in GameManager.player_fleet.ships.size():
		var fs =GameManager.player_fleet.ships[i]
		if i == GameManager.player_fleet.active_index:
			result.append(i)  # Always include active ship
		elif fs.deployment_state == FleetShip.DeploymentState.DOCKED and fs.docked_station_id == current_station_id:
			result.append(i)
	return result


func repair_ship(ship: Node3D) -> void:
	var health = ship.get_node_or_null("HealthSystem")
	if health == null:
		return
	health.hull_current = health.hull_max
	for i in health.shield_current.size():
		health.shield_current[i] = health.shield_max_per_facing
	health.hull_changed.emit(health.hull_current, health.hull_max)
	for i in 4:
		health.shield_changed.emit(i, health.shield_current[i], health.shield_max_per_facing)
