class_name DockingSystem
extends Node

# =============================================================================
# Docking System - Bay-entry + proximity detection and dock/undock state.
# Added as child of the player ship. Scans EntityRegistry for nearby stations.
# Supports fly-in docking: stations with BayArea emit ship_entered_bay/exited.
# Falls back to distance-based docking for stations without a docking bay.
# =============================================================================

signal dock_available(station_name: String)
signal dock_unavailable()
signal docked(station_name: String)
signal undocked()

const DEFAULT_DOCK_RANGE: float = 5000.0      ## Max distance to dock (meters)
const DEFAULT_DOCK_MAX_SPEED: float = 350.0   ## Max speed to allow docking (m/s)
const DEFAULT_DOCK_MIN_FACING: float = 0.5    ## Min dot product ship→station (0.5 ≈ 60° cone)
const BAY_DOCK_MAX_SPEED: float = 100.0       ## Max speed for bay docking (slower = safer landing)

@export var dock_range: float = DEFAULT_DOCK_RANGE
@export var dock_max_speed: float = DEFAULT_DOCK_MAX_SPEED
@export var dock_min_facing: float = DEFAULT_DOCK_MIN_FACING
@export var scan_interval: float = 0.25   ## Seconds between station scans

var is_docked: bool = false
var can_dock: bool = false
var is_near_station: bool = false
var nearest_station_name: String = ""
var nearest_station_node: Node3D = null

var _ship: Node3D = null
var _check_timer: float = 0.0
var _in_bay: bool = false            ## True if ship is inside a station's docking bay
var _bay_station: Node3D = null      ## The station whose bay we're inside
var _connected_stations: Array = []  ## Stations we've connected bay signals to
var _frozen_station_id: String = ""  ## EntityRegistry ID of station whose orbit is frozen


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

	# Safety: clear stale bay flag if bay station was freed/unloaded
	if _in_bay and (_bay_station == null or not is_instance_valid(_bay_station)):
		_in_bay = false
		_bay_station = null
		if can_dock:
			can_dock = false
			dock_unavailable.emit()

	# Bay docking: if inside a bay, check speed for dock availability
	if _in_bay and _bay_station != null and is_instance_valid(_bay_station):
		var was_available: bool = can_dock
		var speed: float = 0.0
		if _ship is RigidBody3D:
			speed = (_ship as RigidBody3D).linear_velocity.length()
		can_dock = speed < BAY_DOCK_MAX_SPEED
		nearest_station_node = _bay_station
		# Resolve station name from EntityRegistry
		if nearest_station_name.is_empty():
			_resolve_station_name(_bay_station)
		if can_dock and not was_available:
			dock_available.emit(nearest_station_name)
		elif not can_dock and was_available:
			dock_unavailable.emit()
		return

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = scan_interval
		_scan_stations()


func _scan_stations() -> void:
	var entities: Dictionary = EntityRegistry.get_all()
	var best_dist: float = INF
	var best_node: Node3D = null
	var best_name: String = ""

	var ship_upos: Array = FloatingOrigin.to_universe_pos(_ship.global_position)

	for ent in entities.values():
		if ent["type"] != EntityRegistrySystem.EntityType.STATION:
			continue
		# Use untyped var to safely handle freed node references
		var node_ref = ent.get("node")
		if node_ref != null and not is_instance_valid(node_ref):
			node_ref = null
		# Try to resolve node from Universe if EntityRegistry ref is stale
		if node_ref == null:
			var universe: Node3D = GameManager.universe_node
			var idx: int = ent.get("extra", {}).get("station_index", -1)
			if universe and idx >= 0:
				node_ref = universe.get_node_or_null("Station_%d" % idx)
				if node_ref != null and is_instance_valid(node_ref):
					ent["node"] = node_ref  # Fix stale ref in registry
		if node_ref == null:
			continue
		var node: Node3D = node_ref
		# Can't dock at a destroyed station
		var sh = node.get_node_or_null("StructureHealth")
		if sh and sh.is_dead():
			continue
		# Use float64 universe coordinates for distance — immune to floating origin desync
		var dx: float = ent["pos_x"] - ship_upos[0]
		var dy: float = ent["pos_y"] - ship_upos[1]
		var dz: float = ent["pos_z"] - ship_upos[2]
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		if dist < best_dist:
			best_dist = dist
			best_node = node
			best_name = ent.get("name", "Station")

		# Connect bay signals if station has them and we haven't yet
		_try_connect_bay_signals(node)

	var was_available: bool = can_dock

	# Freeze/unfreeze orbit of nearby station to prevent physics desync
	var best_entity_id: String = ""
	if best_node:
		for ent in entities.values():
			if ent.get("node") == best_node and ent["type"] == EntityRegistrySystem.EntityType.STATION:
				best_entity_id = ent["id"]
				break
	if best_entity_id != "" and best_dist < dock_range:
		if _frozen_station_id != best_entity_id:
			if _frozen_station_id != "":
				EntityRegistry.unfreeze_orbit(_frozen_station_id)
			EntityRegistry.freeze_orbit(best_entity_id)
			_frozen_station_id = best_entity_id
	elif _frozen_station_id != "":
		EntityRegistry.unfreeze_orbit(_frozen_station_id)
		_frozen_station_id = ""

	# Stations with docking bays use bay-entry detection instead
	if best_node and best_node.has_signal("ship_entered_bay"):
		# Safety: clear stale bay flag if player is far beyond dock range
		if _in_bay and best_dist > dock_range:
			_in_bay = false
			_bay_station = null
		nearest_station_node = best_node
		nearest_station_name = best_name
		is_near_station = best_dist < dock_range
		if not _in_bay and was_available:
			dock_unavailable.emit()
			can_dock = false
		return

	# Fallback: distance-based docking for stations without a bay
	if best_node and best_dist < dock_range:
		is_near_station = true
		var speed: float = 0.0
		if _ship is RigidBody3D:
			speed = (_ship as RigidBody3D).linear_velocity.length()
		# Must face the station (ship forward is -Z)
		var to_station = (best_node.global_position - _ship.global_position).normalized()
		var forward = -_ship.global_basis.z.normalized()
		var facing = forward.dot(to_station) > dock_min_facing
		can_dock = speed < dock_max_speed and facing
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
		is_near_station = false
		nearest_station_node = null
		nearest_station_name = ""


func _try_connect_bay_signals(station: Node3D) -> void:
	if station in _connected_stations:
		return
	if not station.has_signal("ship_entered_bay"):
		return
	if not station.ship_entered_bay.is_connected(_on_ship_entered_bay.bind(station)):
		station.ship_entered_bay.connect(_on_ship_entered_bay.bind(station))
	if not station.ship_exited_bay.is_connected(_on_ship_exited_bay.bind(station)):
		station.ship_exited_bay.connect(_on_ship_exited_bay.bind(station))
	_connected_stations.append(station)


func _on_ship_entered_bay(ship: Node3D, station: Node3D) -> void:
	if ship != _ship:
		return
	_in_bay = true
	_bay_station = station
	_resolve_station_name(station)


func _on_ship_exited_bay(ship: Node3D, _station: Node3D) -> void:
	if ship != _ship:
		return
	_in_bay = false
	_bay_station = null
	if can_dock:
		can_dock = false
		dock_unavailable.emit()


func _resolve_station_name(station: Node3D) -> void:
	# Try to get station name from the SpaceStation node directly
	if station.has_method("get") or "station_name" in station:
		nearest_station_name = station.station_name
		return
	# Fallback: search EntityRegistry
	var entities: Dictionary = EntityRegistry.get_all()
	for ent in entities.values():
		if ent.get("node") == station:
			nearest_station_name = ent.get("name", "Station")
			return


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
	# Clear bay state — the ship is always teleported outside the bay before
	# request_undock() is called (via _reposition_at_station in DockingManager).
	# Keeping _in_bay=true would cause stale state after respawn because the
	# frozen Area3D never tracked the body, so body_exited never fires.
	_in_bay = false
	_bay_station = null
	_check_timer = 0.0
	undocked.emit()


## Call when changing systems to clean up stale station connections
func clear_station_connections() -> void:
	if _frozen_station_id != "":
		EntityRegistry.unfreeze_orbit(_frozen_station_id)
		_frozen_station_id = ""
	_connected_stations.clear()
	_in_bay = false
	_bay_station = null
	nearest_station_node = null
	nearest_station_name = ""
	can_dock = false
	is_near_station = false
	_check_timer = 0.0  # Force immediate rescan on next frame
