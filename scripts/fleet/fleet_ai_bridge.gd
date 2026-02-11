class_name FleetAIBridge
extends Node

# =============================================================================
# Fleet AI Bridge — Translates fleet commands to AIBrain states
# Attached as child of deployed fleet NPC (sibling of AIBrain/AIPilot)
#
# Navigation uses AIBrain PATROL exclusively (ShipController autopilot is
# player-only and doesn't work for NPCs).
# Fleet ships on mission ignore threats — they fly to destination without
# getting distracted by enemies.
# =============================================================================

var fleet_index: int = -1
var command: StringName = &""
var command_params: Dictionary = {}

var _ship: ShipController = null
var _brain: AIBrain = null
var _station_id: String = ""
var _returning: bool = false
var _arrived: bool = false
var _attack_target_id: String = ""

const RETURN_ARRIVE_DIST: float = 500.0
const MOVE_ARRIVE_DIST: float = 200.0

var _initialized: bool = false


func _ready() -> void:
	_ship = get_parent() as ShipController
	# If tree is disabled (player is docked), defer init until _process fires.
	if _ship and not _ship.can_process():
		return
	await get_tree().process_frame
	_do_init()


func _exit_tree() -> void:
	if FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.disconnect(_on_origin_shifted)


func _do_init() -> void:
	if _initialized:
		return
	_initialized = true
	_brain = _ship.get_node_or_null("AIBrain") as AIBrain if _ship else null

	if _brain:
		# Fleet ships on mission don't react to enemies (no wasted time fighting)
		_brain.ignore_threats = true
		# Check if ship has combat weapons — disable if unarmed
		var wm := _ship.get_node_or_null("WeaponManager") as WeaponManager if _ship else null
		var has_weapons: bool = wm != null and wm.has_combat_weapons_in_group(0)
		if not has_weapons:
			_brain.weapons_enabled = false
		apply_command(command, command_params)

	# Correct waypoints when floating origin shifts (local coords become stale)
	if not FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func apply_command(cmd: StringName, params: Dictionary = {}) -> void:
	command = cmd
	command_params = params
	_returning = false
	_arrived = false
	_attack_target_id = ""
	if _brain == null:
		if _initialized:
			push_warning("FleetAIBridge[%d]: _brain is null, command ignored!" % fleet_index)
		# Not yet initialized — command stored, will be applied in _do_init()
		return

	# All mission commands: ignore threats, focus on destination
	_brain.ignore_threats = (cmd in [&"move_to", &"patrol", &"return_to_station", &"construction"])
	_brain.target = null

	match cmd:
		&"move_to":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > MOVE_ARRIVE_DIST:
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"patrol":
			var center_x: float = params.get("center_x", 0.0)
			var center_z: float = params.get("center_z", 0.0)
			var radius: float = params.get("radius", 500.0)
			var center_pos := FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			_brain.set_patrol_area(center_pos, radius)
			_brain.current_state = AIBrain.State.PATROL
		&"attack":
			_attack_target_id = params.get("target_entity_id", "")
			if _attack_target_id != "":
				var ent := EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					var target_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					_brain.set_patrol_area(target_pos, 50.0)
					var target_node: Node3D = ent.get("node", null) as Node3D if ent.get("node") else null
					if target_node and is_instance_valid(target_node):
						_brain.target = target_node
						_brain.current_state = AIBrain.State.PURSUE
					else:
						_brain.current_state = AIBrain.State.PATROL
		&"construction":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > MOVE_ARRIVE_DIST:
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"return_to_station":
			_returning = true
			# Preserve existing _station_id (set during deployment) if params don't include one
			var new_station: String = params.get("station_id", "")
			if new_station != "":
				_station_id = new_station
			if _station_id != "":
				var ent := EntityRegistry.get_entity(_station_id)
				if not ent.is_empty():
					var station_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					var dist: float = _ship.global_position.distance_to(station_pos)
					if dist > RETURN_ARRIVE_DIST:
						_brain.set_patrol_area(station_pos, 50.0)
						_brain.current_state = AIBrain.State.PATROL
					else:
						# Already close — retrieve immediately
						var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
						if fdm:
							fdm.retrieve_ship(fleet_index)


func _process(_delta: float) -> void:
	if _ship == null:
		return
	# Deferred init: tree was disabled when spawned (player was docked)
	if not _initialized:
		_do_init()
		return
	if _brain == null:
		return

	# Monitor return_to_station arrival
	if _returning and _station_id != "":
		var ent := EntityRegistry.get_entity(_station_id)
		if not ent.is_empty():
			var station_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			var dist: float = _ship.global_position.distance_to(station_pos)
			if dist < RETURN_ARRIVE_DIST:
				var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
				if fdm:
					fdm.retrieve_ship(fleet_index)
				return
			# Keep brain patrolling toward station (position updates with floating origin)
			if _brain.current_state == AIBrain.State.IDLE:
				_brain.set_patrol_area(station_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL

	# Monitor construction arrival (same as move_to)
	if command == &"construction" and not _arrived:
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)

	# Monitor move_to arrival
	if command == &"move_to" and not _arrived:
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)

	# Monitor attack target
	if command == &"attack" and _attack_target_id != "":
		var ent := EntityRegistry.get_entity(_attack_target_id)
		if ent.is_empty():
			# Target destroyed — stay in patrol zone, keep fighting nearby enemies
			_attack_target_id = ""
		else:
			# Update patrol area to track moving target
			var target_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			_brain.set_patrol_area(target_pos, 50.0)
			# If target has a node and brain lost its target, re-acquire
			var target_node: Node3D = ent.get("node", null) as Node3D if ent.get("node") else null
			if target_node and is_instance_valid(target_node) and _brain.target == null:
				_brain.target = target_node
				_brain.current_state = AIBrain.State.PURSUE


func _mark_arrived(target_pos: Vector3) -> void:
	_arrived = true
	if _brain:
		_brain.set_patrol_area(target_pos, 50.0)
	var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "arrived", true)


func _on_origin_shifted(_delta: Vector3) -> void:
	# Floating origin shifted — local waypoints in AIBrain are now stale.
	# Refresh patrol area using universe coords from command_params.
	if _brain == null or command == &"":
		return
	match command:
		&"move_to", &"construction":
			var tx: float = command_params.get("target_x", 0.0)
			var tz: float = command_params.get("target_z", 0.0)
			_brain.set_patrol_area(FloatingOrigin.to_local_pos([tx, 0.0, tz]), 50.0)
		&"patrol":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			var radius: float = command_params.get("radius", 500.0)
			_brain.set_patrol_area(FloatingOrigin.to_local_pos([cx, 0.0, cz]), radius)
		&"attack":
			if _attack_target_id != "":
				var ent := EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					_brain.set_patrol_area(FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), 50.0)
		&"return_to_station":
			if _station_id != "":
				var ent := EntityRegistry.get_entity(_station_id)
				if not ent.is_empty():
					_brain.set_patrol_area(FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), 50.0)
