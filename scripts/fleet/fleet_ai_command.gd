class_name FleetAICommand
extends Node

# =============================================================================
# Fleet AI Command — Translates fleet orders into AIController behaviors.
# Replaces FleetAIBridge. Same public API for FleetDeploymentManager, etc.
# =============================================================================

var fleet_index: int = -1
var command: StringName = &""
var command_params: Dictionary = {}

var _ship = null
var _ctrl: AIController = null
var _station_id: String = ""
var _returning: bool = false
var _arrived: bool = false
var _attack_target_id: String = ""

const MOVE_ARRIVE_DIST: float = 200.0
const STATION_SAFE_MARGIN: float = 500.0
const DOCK_APPROACH_DIST: float = 1200.0
const IDLE_TIMEOUT: float = 900.0

# Dock approach
var _bay_approach_pos: Vector3 = Vector3.ZERO
var _bay_dock_pos: Vector3 = Vector3.ZERO
var _bay_target_valid: bool = false
var _in_bay: bool = false
var _dock_final_approach: bool = false
var _bay_station_node: Node3D = null
var _bay_signal_connected: bool = false
var _initialized: bool = false
var _idle_timer: float = 0.0

var _nav: AINavigation = null


func _ready() -> void:
	_ship = get_parent()
	call_deferred("_do_init")


func _exit_tree() -> void:
	if _nav and is_instance_valid(_nav):
		_nav.clear_nav_boost()
		_nav.docking_approach = false
	if FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.disconnect(_on_origin_shifted)
	_disconnect_bay_signals()


func _do_init() -> void:
	if _initialized:
		return
	_initialized = true
	_ctrl = _ship.get_node_or_null("AIController") if _ship else null
	_nav = _ship.get_node_or_null("AINavigation") if _ship else null

	if _ctrl:
		_ctrl.idle_after_combat = true
		var wm = _ship.get_node_or_null("WeaponManager") if _ship else null
		var has_weapons: bool = wm != null and wm.has_combat_weapons_in_group(0)
		if not has_weapons:
			_ctrl.weapons_enabled = false
			push_warning("[FleetAICommand] idx=%d (%s) has NO combat weapons — weapons disabled" % [fleet_index, _get_ship_name()])
		apply_command(command, command_params)

	if not FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func apply_command(cmd: StringName, params: Dictionary = {}) -> void:
	command = cmd
	command_params = params
	_returning = false
	_arrived = false
	_attack_target_id = ""
	_idle_timer = 0.0
	_dock_final_approach = false
	if _ctrl == null:
		if _initialized:
			push_warning("FleetAICommand[%d]: _ctrl is null, command ignored!" % fleet_index)
		return

	_ctrl.ignore_threats = (cmd in [&"move_to", &"return_to_station", &"construction", &"mine"])
	_ctrl.target = null
	_ctrl.current_state = AIController.State.IDLE
	if _nav:
		_nav.docking_approach = false

	match cmd:
		&"move_to":
			var target_pos := _resolve_target_pos(params)
			target_pos = _push_target_outside_stations(target_pos)
			if _ship.global_position.distance_to(target_pos) > MOVE_ARRIVE_DIST:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"patrol":
			var cx: float = params.get("center_x", 0.0)
			var cz: float = params.get("center_z", 0.0)
			var radius: float = params.get("radius", 500.0)
			var center_pos := FloatingOrigin.to_local_pos([cx, 0.0, cz])
			_ctrl.set_patrol_area(center_pos, radius)
			_ctrl.current_state = AIController.State.PATROL
		&"attack":
			_attack_target_id = params.get("target_entity_id", "")
			_ctrl.ignore_threats = false
			# Unarmed ship: just move to target position, don't enter combat
			if not _ctrl.weapons_enabled:
				_ctrl.ignore_threats = true
				var target_pos := _resolve_attack_target_pos(params)
				if _ship.global_position.distance_to(target_pos) > MOVE_ARRIVE_DIST:
					_ctrl.set_patrol_area(target_pos, 0.0)
					_ctrl.current_state = AIController.State.PATROL
				else:
					_mark_arrived(target_pos)
				print("[FleetAttack] idx=%d UNARMED — move_to fallback" % fleet_index)
			elif _attack_target_id != "":
				var ent = EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					var target_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					var dist: float = _ship.global_position.distance_to(target_pos)
					var target_node = _find_target_node(_attack_target_id)
					print("[FleetAttack] idx=%d entity found, dist=%.0f detection_range=%.0f target_node=%s" % [fleet_index, dist, _ctrl.detection_range, target_node != null])
					if dist <= _ctrl.detection_range and target_node:
						_ctrl.target = target_node
						_ctrl.current_state = AIController.State.PURSUE
						print("[FleetAttack] -> PURSUE")
					else:
						_ctrl.set_patrol_area(target_pos, 0.0)
						_ctrl.current_state = AIController.State.PATROL
						print("[FleetAttack] -> PATROL toward target")
				else:
					# Entity not in registry — fallback: patrol toward coordinates if available
					var tx: float = params.get("target_x", 0.0)
					var tz: float = params.get("target_z", 0.0)
					if tx != 0.0 or tz != 0.0:
						var fallback_pos := FloatingOrigin.to_local_pos([tx, 0.0, tz])
						_ctrl.set_patrol_area(fallback_pos, 0.0)
						_ctrl.current_state = AIController.State.PATROL
						print("[FleetAttack] entity '%s' not in registry, fallback PATROL to (%.0f, %.0f)" % [_attack_target_id, tx, tz])
					else:
						print("[FleetAttack] entity '%s' not in registry and no fallback coords" % _attack_target_id)
		&"construction":
			var target_pos := _resolve_target_pos(params)
			target_pos = _push_target_outside_stations(target_pos)
			if _ship.global_position.distance_to(target_pos) > MOVE_ARRIVE_DIST:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"mine":
			var cx: float = params.get("center_x", 0.0)
			var cz: float = params.get("center_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([cx, 0.0, cz])
			if _ship.global_position.distance_to(target_pos) > MOVE_ARRIVE_DIST:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL
			else:
				_ctrl.current_state = AIController.State.MINING
				_arrived = true
		&"return_to_station":
			_returning = true
			_in_bay = false
			var new_station: String = params.get("station_id", "")
			if new_station != "":
				_disconnect_bay_signals()
				_station_id = new_station
			if _station_id == "" or EntityRegistry.get_entity(_station_id).is_empty():
				_station_id = _find_nearest_station_id()
			if _station_id != "":
				_resolve_station_dock_targets()
				if _bay_target_valid:
					# Use IDLE + direct fly_toward (handled in _process), NOT PATROL
					# PATROL generates circular waypoints that cause orbiting
					_ctrl.current_state = AIController.State.IDLE


func _process(_delta: float) -> void:
	if _ship == null:
		return
	if not _initialized:
		_do_init()
		return
	if _ctrl == null:
		return

	_update_navigation_boost()

	# Return to station dock approach — 3-phase direct flight
	if _returning and _station_id != "" and _bay_target_valid:
		_refresh_dock_targets()
		# Keep state as IDLE (direct fly_toward control, not AIController behaviors)
		if _ctrl.current_state != AIController.State.IDLE:
			_ctrl.current_state = AIController.State.IDLE

		var dist_to_approach: float = _ship.global_position.distance_to(_bay_approach_pos)

		# Phase 3: In bay or final approach — descend to landing pad
		if _in_bay or _dock_final_approach:
			if _nav:
				_nav.docking_approach = true
			var dist_to_dock: float = _ship.global_position.distance_to(_bay_dock_pos)
			var speed: float = _ship.linear_velocity.length()
			if dist_to_dock < 80.0 and speed < DockingSystem.BAY_DOCK_MAX_SPEED:
				var npc_auth = GameManager.get_node_or_null("NpcAuthority")
				if npc_auth and npc_auth._active:
					npc_auth.handle_fleet_npc_self_docked(StringName(_ship.name), fleet_index)
				return
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if _nav:
				_nav.fly_toward(_bay_dock_pos, 30.0)
			return

		# Phases 1-2: obstacle avoidance ACTIVE (navigate around decorations)
		if _nav:
			_nav.docking_approach = false

		# Phase 2: Near approach (<1200m) — fly to bay entrance, exit cruise
		if dist_to_approach < DOCK_APPROACH_DIST:
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if _nav:
				_nav.fly_toward(_bay_approach_pos, 50.0)
			# Transition to final approach when close to bay entrance
			if dist_to_approach < 80.0:
				_dock_final_approach = true
			return

		# Phase 1: Long range (>1200m) — fly straight toward bay entrance
		if _nav:
			_nav.fly_toward(_bay_approach_pos, 200.0)

	# Monitor arrivals
	_monitor_arrivals()

	# Monitor attack target
	if command == &"attack" and _attack_target_id != "":
		_monitor_attack_target()

	# Auto-resume after combat
	if not _arrived and not _returning and _ctrl.current_state == AIController.State.IDLE:
		_auto_resume()

	# Idle timeout
	_check_idle_timeout(_delta)

	# Safety net: ignore_threats but combat state
	if not _arrived and not _returning and _ctrl.ignore_threats:
		if command in [&"move_to", &"construction", &"mine"]:
			if _ctrl.current_state in [AIController.State.PURSUE, AIController.State.ATTACK]:
				_ctrl.target = null
				_ctrl.current_state = AIController.State.IDLE


func _monitor_arrivals() -> void:
	if command == &"construction" and not _arrived:
		var target_pos := _resolve_target_pos(command_params)
		target_pos = _push_target_outside_stations(target_pos)
		if _ship.global_position.distance_to(target_pos) < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)

	if command == &"mine" and not _arrived:
		var cx: float = command_params.get("center_x", 0.0)
		var cz: float = command_params.get("center_z", 0.0)
		var target_pos := FloatingOrigin.to_local_pos([cx, 0.0, cz])
		if _ship.global_position.distance_to(target_pos) < MOVE_ARRIVE_DIST:
			_arrived = true
			_ctrl.current_state = AIController.State.MINING

	if command == &"move_to" and not _arrived:
		var target_pos := _resolve_target_pos(command_params)
		target_pos = _push_target_outside_stations(target_pos)
		if _ship.global_position.distance_to(target_pos) < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)


func _monitor_attack_target() -> void:
	var ent = EntityRegistry.get_entity(_attack_target_id)
	if ent.is_empty():
		_attack_target_id = ""
		_ctrl.current_state = AIController.State.IDLE
		_clear_completed_command()
		return
	var target_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
	var dist: float = _ship.global_position.distance_to(target_pos)
	match _ctrl.current_state:
		AIController.State.PATROL:
			_ctrl.set_patrol_area(target_pos, 0.0)
			if dist <= _ctrl.detection_range:
				var target_node = _find_target_node(_attack_target_id)
				if target_node:
					_ctrl.target = target_node
					_ctrl.current_state = AIController.State.PURSUE
		AIController.State.IDLE:
			var target_node = _find_target_node(_attack_target_id)
			if dist <= _ctrl.detection_range and target_node:
				_ctrl.target = target_node
				_ctrl.current_state = AIController.State.PURSUE
			else:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL


func _auto_resume() -> void:
	match command:
		&"patrol":
			_ctrl.current_state = AIController.State.PATROL
		&"move_to", &"construction":
			var target_pos := _resolve_target_pos(command_params)
			target_pos = _push_target_outside_stations(target_pos)
			if _ship.global_position.distance_to(target_pos) < MOVE_ARRIVE_DIST:
				_mark_arrived(target_pos)
			else:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL
		&"mine":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([cx, 0.0, cz])
			if _ship.global_position.distance_to(target_pos) < MOVE_ARRIVE_DIST:
				_arrived = true
				_ctrl.current_state = AIController.State.MINING
			else:
				_ctrl.set_patrol_area(target_pos, 0.0)
				_ctrl.current_state = AIController.State.PATROL


func _check_idle_timeout(dt: float) -> void:
	if command not in [&"patrol", &"mine", &"return_to_station"] and _initialized:
		var currently_idle: bool = (
			(_arrived and command in [&"move_to", &"construction"])
			or (command == &"attack" and _attack_target_id == "" and _ctrl.current_state == AIController.State.IDLE)
			or command == &""
		)
		if currently_idle:
			_idle_timer += dt
			if _idle_timer >= IDLE_TIMEOUT:
				_idle_timer = 0.0
				var npc_auth = GameManager.get_node_or_null("NpcAuthority")
				if npc_auth and npc_auth._active:
					npc_auth.handle_fleet_npc_self_docked(StringName(_ship.name), fleet_index)
		else:
			_idle_timer = 0.0


# =============================================================================
# HELPERS
# =============================================================================
func _get_ship_name() -> String:
	if GameManager.player_data and GameManager.player_data.fleet:
		var fleet = GameManager.player_data.fleet
		if fleet_index >= 0 and fleet_index < fleet.ships.size():
			var ship_name: String = fleet.ships[fleet_index].custom_name
			if ship_name != "":
				return ship_name
	return "Vaisseau #%d" % fleet_index


func _resolve_attack_target_pos(params: Dictionary) -> Vector3:
	var ent = EntityRegistry.get_entity(params.get("target_entity_id", ""))
	if not ent.is_empty():
		return FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
	var tx: float = params.get("target_x", 0.0)
	var tz: float = params.get("target_z", 0.0)
	if tx != 0.0 or tz != 0.0:
		return FloatingOrigin.to_local_pos([tx, 0.0, tz])
	return _ship.global_position


func _resolve_target_pos(params: Dictionary) -> Vector3:
	var tx: float = params.get("target_x", 0.0)
	var tz: float = params.get("target_z", 0.0)
	return FloatingOrigin.to_local_pos([tx, 0.0, tz])


func _mark_arrived(_target_pos: Vector3) -> void:
	_arrived = true
	if _ship:
		_ship.ai_navigation_active = false
		_ship.set_throttle(Vector3.ZERO)
	if _ctrl:
		_ctrl.current_state = AIController.State.IDLE
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "arrived", true)


func _clear_completed_command() -> void:
	command = &""
	command_params = {}
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm and fdm._fleet:
		var ships: Array = fdm._fleet.ships
		if fleet_index >= 0 and fleet_index < ships.size():
			ships[fleet_index].deployed_command = &""
			ships[fleet_index].deployed_command_params = {}
			fdm._fleet.fleet_changed.emit()


func _push_target_outside_stations(target_pos: Vector3) -> Vector3:
	var stations: Array = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for st in stations:
		var st_pos: Vector3 = FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		var to_target: Vector3 = target_pos - st_pos
		var dist: float = to_target.length()
		if dist < STATION_SAFE_MARGIN:
			if dist < 1.0:
				to_target = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			else:
				to_target = to_target.normalized()
			return st_pos + to_target * STATION_SAFE_MARGIN
	return target_pos


func _find_nearest_station_id() -> String:
	if _ship == null:
		return ""
	var ship_upos: Array = FloatingOrigin.to_universe_pos(_ship.global_position)
	var best_id: String = ""
	var best_dist_sq: float = INF
	for ent in EntityRegistry.get_all().values():
		if ent.get("type", -1) != EntityRegistrySystem.EntityType.STATION:
			continue
		var dx: float = ent["pos_x"] - ship_upos[0]
		var dz: float = ent["pos_z"] - ship_upos[2]
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = ent.get("id", "")
	return best_id


func _find_target_node(entity_id: String) -> Node3D:
	var ent = EntityRegistry.get_entity(entity_id)
	if not ent.is_empty():
		var n = ent.get("node")
		if n and is_instance_valid(n):
			return n
	var tree = get_tree()
	if tree == null:
		return null
	var eid_sn := StringName(entity_id)
	for ship in tree.get_nodes_in_group("ships"):
		if ship.name == eid_sn:
			return ship
		if ship.get(&"npc_id") == eid_sn:
			return ship
	return null


func _resolve_station_dock_targets() -> void:
	_bay_target_valid = false
	if _station_id == "":
		return
	var ent: Dictionary = EntityRegistry.get_entity(_station_id)
	if ent.is_empty():
		return
	var station_node = ent.get("node")
	if station_node and is_instance_valid(station_node):
		_bay_approach_pos = station_node.get_bay_exit_global() if station_node.has_method("get_bay_exit_global") else station_node.global_position
		_bay_dock_pos = station_node.get_landing_pos_global() if station_node.has_method("get_landing_pos_global") else _bay_approach_pos
		_bay_target_valid = true
		_connect_bay_signals(station_node)
	else:
		_bay_approach_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		_bay_dock_pos = _bay_approach_pos
		_bay_target_valid = true


func _refresh_dock_targets() -> void:
	if _station_id == "":
		return
	var ent: Dictionary = EntityRegistry.get_entity(_station_id)
	if ent.is_empty():
		return
	var station_node = ent.get("node")
	if station_node and is_instance_valid(station_node):
		if station_node.has_method("get_bay_exit_global"):
			_bay_approach_pos = station_node.get_bay_exit_global()
		if station_node.has_method("get_landing_pos_global"):
			_bay_dock_pos = station_node.get_landing_pos_global()


func _connect_bay_signals(station_node: Node3D) -> void:
	if _bay_signal_connected:
		return
	if not station_node.has_signal("ship_entered_bay"):
		return
	station_node.ship_entered_bay.connect(_on_bay_entered)
	station_node.ship_exited_bay.connect(_on_bay_exited)
	_bay_station_node = station_node
	_bay_signal_connected = true


func _disconnect_bay_signals() -> void:
	if not _bay_signal_connected:
		return
	if _bay_station_node and is_instance_valid(_bay_station_node):
		if _bay_station_node.ship_entered_bay.is_connected(_on_bay_entered):
			_bay_station_node.ship_entered_bay.disconnect(_on_bay_entered)
		if _bay_station_node.ship_exited_bay.is_connected(_on_bay_exited):
			_bay_station_node.ship_exited_bay.disconnect(_on_bay_exited)
	_bay_station_node = null
	_bay_signal_connected = false
	_in_bay = false


func _on_bay_entered(ship: Node3D) -> void:
	if ship == _ship:
		_in_bay = true


func _on_bay_exited(ship: Node3D) -> void:
	if ship == _ship:
		_in_bay = false


func _on_origin_shifted(_delta_shift: Vector3) -> void:
	if _ctrl == null or command == &"":
		return
	match command:
		&"move_to", &"construction":
			var tx: float = command_params.get("target_x", 0.0)
			var tz: float = command_params.get("target_z", 0.0)
			_ctrl.set_patrol_area(FloatingOrigin.to_local_pos([tx, 0.0, tz]), 0.0)
		&"mine":
			if not _arrived:
				var cx: float = command_params.get("center_x", 0.0)
				var cz: float = command_params.get("center_z", 0.0)
				_ctrl.set_patrol_area(FloatingOrigin.to_local_pos([cx, 0.0, cz]), 0.0)
		&"patrol":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			var radius: float = command_params.get("radius", 500.0)
			_ctrl.shift_patrol_waypoints(FloatingOrigin.to_local_pos([cx, 0.0, cz]), radius)
		&"attack":
			if _attack_target_id != "" and _ctrl.current_state == AIController.State.PATROL:
				var ent = EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					_ctrl.set_patrol_area(FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), 0.0)
		&"return_to_station":
			if _station_id != "" and _bay_target_valid:
				_resolve_station_dock_targets()


func _update_navigation_boost() -> void:
	if _nav == null:
		return
	if command == &"mine" and _arrived:
		return
	if _arrived or command == &"":
		_nav.clear_nav_boost()
		if _ship.linear_velocity.length() > AINavigation.NAV_BOOST_MIN_SPEED:
			_ship._gate_approach_speed_cap = AINavigation.NAV_BOOST_MIN_SPEED
		return

	var target_pos: Vector3
	match command:
		&"move_to", &"construction":
			target_pos = _resolve_target_pos(command_params)
		&"mine":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			target_pos = FloatingOrigin.to_local_pos([cx, 0.0, cz])
		&"return_to_station":
			if not _bay_target_valid:
				_nav.clear_nav_boost()
				return
			target_pos = _bay_approach_pos
		&"attack":
			if _attack_target_id != "":
				var ent := EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					target_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
				else:
					_nav.clear_nav_boost()
					return
			else:
				_nav.clear_nav_boost()
				return
		_:
			_nav.clear_nav_boost()
			return

	_nav.update_nav_boost(target_pos)
