class_name RouteManager
extends Node

# =============================================================================
# Route Manager - Multi-system autopilot state machine
# Manages galaxy-scale navigation: BFS path → fly to gate → auto-jump → repeat
# =============================================================================

enum State { IDLE, FLYING_TO_GATE, WAITING_AT_GATE, JUMPING }

signal route_started(route: Array[int])
signal route_step_changed(current_system: int, next_system: int)
signal route_completed()
signal route_cancelled()

var state: State = State.IDLE
var route: Array[int] = []            # System IDs in order (inclusive from→to)
var route_index: int = 0              # Current position in route
var target_system_id: int = -1        # Final destination
var target_system_name: String = ""   # Final destination name
var next_gate_entity_id: String = ""  # EntityRegistry ID of the gate to next system
var _jump_retry_count: int = 0
var _pending_jump_target_id: int = -1
const MAX_JUMP_RETRIES: int = 8

# Final destination after arrival (autopilot to specific entity/position)
var has_final_dest: bool = false
var final_dest_x: float = 0.0
var final_dest_z: float = 0.0
var final_dest_name: String = ""

# External references (set by GameManager)
var system_transition = null
var galaxy_data = null


func start_route(from_id: int, to_id: int) -> bool:
	if galaxy_data == null or system_transition == null:
		return false

	if from_id == to_id:
		return false

	var path: Array[int] = galaxy_data.find_path(from_id, to_id)
	if path.is_empty():
		return false

	route = path
	route_index = 0
	target_system_id = to_id
	target_system_name = galaxy_data.get_system_name(to_id)
	state = State.IDLE

	route_started.emit(route)
	_advance_to_next_step()
	return true


func start_route_to(from_id: int, to_id: int, dest_x: float, dest_z: float, dest_name: String) -> bool:
	has_final_dest = true
	final_dest_x = dest_x
	final_dest_z = dest_z
	final_dest_name = dest_name
	var ok: bool = start_route(from_id, to_id)
	if not ok:
		_clear_final_dest()
	return ok


func cancel_route() -> void:
	if state == State.IDLE and route.is_empty():
		return

	# Disengage ship autopilot if active
	var ship = GameManager.player_ship
	if ship and ship.autopilot_active:
		ship.disengage_autopilot()

	state = State.IDLE
	route.clear()
	route_index = 0
	target_system_id = -1
	target_system_name = ""
	next_gate_entity_id = ""
	_pending_jump_target_id = -1
	_clear_final_dest()
	route_cancelled.emit()


func is_route_active() -> bool:
	return state != State.IDLE or not route.is_empty()


func get_jumps_remaining() -> int:
	if route.is_empty():
		return 0
	return route.size() - 1 - route_index


func get_jumps_total() -> int:
	if route.is_empty():
		return 0
	return route.size() - 1


func get_current_jump() -> int:
	return route_index


## Called by GameManager when a system finishes loading
func on_system_loaded(system_id: int) -> void:
	if state != State.JUMPING:
		return

	# Verify we're at the expected system
	if route_index + 1 < route.size() and route[route_index + 1] == system_id:
		route_index += 1
	else:
		# Unexpected system — find our position in the route
		for i in route.size():
			if route[i] == system_id:
				route_index = i
				break

	# Check if we've arrived at destination
	if route_index >= route.size() - 1:
		if has_final_dest:
			_engage_final_dest()
		state = State.IDLE
		route_completed.emit()
		route.clear()
		route_index = 0
		target_system_id = -1
		target_system_name = ""
		next_gate_entity_id = ""
		_pending_jump_target_id = -1
		return

	# Continue to next step
	_advance_to_next_step()


func _advance_to_next_step() -> void:
	if route_index >= route.size() - 1:
		# Already at destination
		state = State.IDLE
		route_completed.emit()
		route.clear()
		route_index = 0
		target_system_id = -1
		target_system_name = ""
		next_gate_entity_id = ""
		_pending_jump_target_id = -1
		return

	var current_sys: int = route[route_index]
	var next_sys: int = route[route_index + 1]

	route_step_changed.emit(current_sys, next_sys)

	# Find the gate entity leading to next_sys
	next_gate_entity_id = _find_gate_to_system(next_sys)
	if next_gate_entity_id.is_empty():
		push_warning("RouteManager: No gate found to system %d, cancelling route" % next_sys)
		cancel_route()
		return

	# Engage autopilot to the gate
	var ent: Dictionary = EntityRegistry.get_entity(next_gate_entity_id)
	if ent.is_empty():
		push_warning("RouteManager: Gate entity '%s' not in registry" % next_gate_entity_id)
		cancel_route()
		return

	var ship = GameManager.player_ship
	if ship:
		ship.engage_autopilot(next_gate_entity_id, ent["name"], true)

	state = State.FLYING_TO_GATE


func _find_gate_to_system(target_sys_id: int) -> String:
	var entities: Dictionary = EntityRegistry.get_all()
	for ent_id in entities:
		var ent: Dictionary = entities[ent_id]
		if ent["type"] == EntityRegistrySystem.EntityType.JUMP_GATE:
			var extra: Dictionary = ent.get("extra", {})
			if extra.get("target_system_id", -1) == target_sys_id:
				return ent_id
	return ""


## Called when player enters gate proximity (from SystemTransition gate signals)
func on_gate_proximity(target_id: int) -> void:
	if state != State.FLYING_TO_GATE:
		return

	# Verify this is the gate we're heading to
	if route_index + 1 < route.size() and route[route_index + 1] == target_id:
		_pending_jump_target_id = target_id
		state = State.WAITING_AT_GATE
		_jump_retry_count = 0
		# Auto-jump after a short delay
		get_tree().create_timer(1.0).timeout.connect(_auto_jump)


func _auto_jump() -> void:
	if state != State.WAITING_AT_GATE:
		return

	if system_transition == null or not system_transition.can_gate_jump():
		_jump_retry_count += 1
		if _jump_retry_count > MAX_JUMP_RETRIES:
			# Too many retries — cancel route
			push_warning("RouteManager: Auto-jump failed after %d retries, cancelling" % _jump_retry_count)
			cancel_route()
			return
		# Re-engage autopilot to fly back to the gate if we drifted out
		if _jump_retry_count >= 3 and next_gate_entity_id != "":
			var ship = GameManager.player_ship
			if ship and not ship.autopilot_active:
				var ent: Dictionary = EntityRegistry.get_entity(next_gate_entity_id)
				if not ent.is_empty():
					ship.engage_autopilot(next_gate_entity_id, ent["name"], true)
					state = State.FLYING_TO_GATE
					return
		# Retry
		get_tree().create_timer(0.5).timeout.connect(_auto_jump)
		return

	state = State.JUMPING
	system_transition.initiate_gate_jump(_pending_jump_target_id)


func _engage_final_dest() -> void:
	# Wait one frame for entities to register after system load
	await get_tree().process_frame
	var ship = GameManager.player_ship
	if ship == null:
		_clear_final_dest()
		return

	# Find the closest entity to the final destination
	var best_id: String = ""
	var best_dist: float = INF
	var entities: Dictionary = EntityRegistry.get_all()
	for ent_id in entities:
		var ent: Dictionary = entities[ent_id]
		var etype: int = ent.get("type", -1)
		# Skip player ships and hidden entities
		if etype == EntityRegistrySystem.EntityType.SHIP_PLAYER:
			continue
		if ent.get("extra", {}).get("hidden", false):
			continue
		var dx: float = ent["pos_x"] - final_dest_x
		var dz: float = ent["pos_z"] - final_dest_z
		var dist: float = dx * dx + dz * dz
		if dist < best_dist:
			best_dist = dist
			best_id = ent_id

	if best_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(best_id)
		var ent_name: String = ent.get("name", final_dest_name)
		var is_gate: bool = ent.get("type", -1) == EntityRegistrySystem.EntityType.JUMP_GATE
		ship.engage_autopilot(best_id, ent_name, is_gate)
	elif final_dest_name != "":
		# No entity found — create a temporary waypoint
		var wp_id: String = "route_final_wp_%d" % Time.get_ticks_msec()
		EntityRegistry.register(wp_id, {
			"name": final_dest_name,
			"type": EntityRegistrySystem.EntityType.SHIP_PLAYER,
			"pos_x": final_dest_x,
			"pos_y": 0.0,
			"pos_z": final_dest_z,
			"node": null,
			"radius": 0.0,
			"color": Color.TRANSPARENT,
			"extra": {"hidden": true},
		})
		ship.engage_autopilot(wp_id, final_dest_name, true)
	else:
		push_warning("RouteManager: No entity found near final destination (%.0f, %.0f)" % [final_dest_x, final_dest_z])

	_clear_final_dest()


func _clear_final_dest() -> void:
	has_final_dest = false
	final_dest_x = 0.0
	final_dest_z = 0.0
	final_dest_name = ""
