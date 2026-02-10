class_name DockingSystem
extends Node

# =============================================================================
# Docking System - Proximity detection and dock/undock state management
# Added as child of the player ship. Scans EntityRegistry for nearby stations.
# =============================================================================

signal dock_available(station_name: String)
signal dock_unavailable()
signal docked(station_name: String)
signal undocked()

@export var dock_range: float = 300.0     ## Max distance to dock (meters)
@export var dock_max_speed: float = 50.0  ## Max speed to allow docking (m/s)
@export var scan_interval: float = 0.25   ## Seconds between station scans

var is_docked: bool = false
var can_dock: bool = false
var nearest_station_name: String = ""
var nearest_station_node: Node3D = null

var _ship: Node3D = null
var _check_timer: float = 0.0


func _ready() -> void:
	_ship = get_parent() as Node3D


func _process(delta: float) -> void:
	if is_docked or _ship == null:
		return

	# Safety: clear stale station ref (e.g. freed during system transition)
	if nearest_station_node != null and not is_instance_valid(nearest_station_node):
		nearest_station_node = null
		if can_dock:
			can_dock = false
			dock_unavailable.emit()

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = scan_interval
		_scan_stations()


func _scan_stations() -> void:
	var entities: Dictionary = EntityRegistry.get_all()
	var best_dist: float = INF
	var best_node: Node3D = null
	var best_name: String = ""

	for ent in entities.values():
		if ent["type"] != EntityRegistrySystem.EntityType.STATION:
			continue
		# Use untyped var to safely handle freed node references
		var node_ref = ent.get("node")
		if node_ref == null or not is_instance_valid(node_ref):
			continue
		var node: Node3D = node_ref
		# Can't dock at a destroyed station
		var sh := node.get_node_or_null("StructureHealth") as StructureHealth
		if sh and sh.is_dead():
			continue
		var dist: float = _ship.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_node = node
			best_name = ent.get("name", "Station")

	var was_available: bool = can_dock

	if best_node and best_dist < dock_range:
		var speed: float = 0.0
		if _ship is RigidBody3D:
			speed = (_ship as RigidBody3D).linear_velocity.length()
		can_dock = speed < dock_max_speed
		nearest_station_node = best_node
		nearest_station_name = best_name
		if can_dock and not was_available:
			dock_available.emit(best_name)
		elif not can_dock and was_available:
			dock_unavailable.emit()
	else:
		if was_available:
			dock_unavailable.emit()
		can_dock = false
		nearest_station_node = null
		nearest_station_name = ""


func request_dock() -> bool:
	if not can_dock or is_docked:
		return false
	is_docked = true
	docked.emit(nearest_station_name)
	return true


func request_undock() -> void:
	if not is_docked:
		return
	is_docked = false
	can_dock = false
	_check_timer = 1.0  # Brief delay before scanning again
	undocked.emit()
