class_name DockInstance
extends Node

# =============================================================================
# Dock Instance - Isolated solo context for station docking
# Freezes the space world using process_mode (cascades to all children),
# loads the hangar scene, and cleanly restores everything on undock.
# =============================================================================

signal entered(station_name: String)
signal left()

var is_active: bool = false
var station_name: String = ""
var hangar_scene: HangarScene = null

# Saved state for clean restore
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0


func enter(ctx: Dictionary) -> void:
	if is_active:
		return
	is_active = true
	station_name = ctx.get("station_name", "Station")

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

	# Stop broadcasting player position to server
	var net_sync: Node = ctx.get("net_sync")
	if net_sync:
		net_sync.process_mode = Node.PROCESS_MODE_DISABLED

	# --- 2. REMOVE PLAYER FROM COMBAT ---
	if player_ship.is_in_group("ships"):
		player_ship.remove_from_group("ships")
	_saved_collision_layer = player_ship.collision_layer
	_saved_collision_mask = player_ship.collision_mask
	player_ship.collision_layer = 0
	player_ship.collision_mask = 0
	player_ship.visible = false

	# Stop player targeting
	var targeting := player_ship.get_node_or_null("TargetingSystem") as TargetingSystem
	if targeting:
		targeting.clear_target()
		targeting.process_mode = Node.PROCESS_MODE_DISABLED

	# --- 3. HIDE SPACE LIGHTING ---
	for node_name in ["StarLight", "SystemStar"]:
		var node := main_scene.get_node_or_null(node_name) as Node3D
		if node:
			node.visible = false

	# --- 4. LOAD HANGAR ---
	var hangar_packed: PackedScene = load("res://scenes/station/hangar_interior.tscn")
	hangar_scene = hangar_packed.instantiate() as HangarScene
	main_scene.add_child(hangar_scene)
	hangar_scene.activate()

	# Display player ship model in hangar
	var ship_model := player_ship.get_node_or_null("ShipModel") as ShipModel
	if ship_model:
		hangar_scene.display_ship(ship_model.model_path, ship_model.model_scale)

	# Repair ship while docked
	_repair_ship(player_ship)

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
	player_ship.visible = true
	for node_name in ["StarLight", "SystemStar"]:
		var node := main_scene.get_node_or_null(node_name) as Node3D
		if node:
			node.visible = true

	# --- 3. UNFREEZE WORLD ---
	universe_node.process_mode = Node.PROCESS_MODE_INHERIT
	var lod_manager: Node = ctx.get("lod_manager")
	if lod_manager:
		lod_manager.process_mode = Node.PROCESS_MODE_INHERIT
	var encounter_manager: Node = ctx.get("encounter_manager")
	if encounter_manager:
		encounter_manager.process_mode = Node.PROCESS_MODE_INHERIT
	var net_sync: Node = ctx.get("net_sync")
	if net_sync:
		net_sync.process_mode = Node.PROCESS_MODE_INHERIT

	# --- 4. RESTORE PLAYER COMBAT ---
	if not player_ship.is_in_group("ships"):
		player_ship.add_to_group("ships")
	player_ship.collision_layer = _saved_collision_layer
	player_ship.collision_mask = _saved_collision_mask

	var targeting := player_ship.get_node_or_null("TargetingSystem") as TargetingSystem
	if targeting:
		targeting.process_mode = Node.PROCESS_MODE_INHERIT

	# --- 5. RESTORE CAMERA ---
	var ship_cam := player_ship.get_node_or_null("ShipCamera") as Camera3D
	if ship_cam:
		ship_cam.current = true

	is_active = false
	station_name = ""
	left.emit()


func _repair_ship(ship: Node3D) -> void:
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health == null:
		return
	health.hull_current = health.hull_max
	for i in health.shield_current.size():
		health.shield_current[i] = health.shield_max_per_facing
	health.hull_changed.emit(health.hull_current, health.hull_max)
	for i in 4:
		health.shield_changed.emit(i, health.shield_current[i], health.shield_max_per_facing)
