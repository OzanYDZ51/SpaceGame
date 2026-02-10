class_name FleetAIBridge
extends Node

# =============================================================================
# Fleet AI Bridge — Translates fleet commands to AIBrain states
# Attached as child of deployed fleet NPC (sibling of AIBrain/AIPilot)
# =============================================================================

var fleet_index: int = -1
var command: StringName = &""
var command_params: Dictionary = {}

var _ship: ShipController = null
var _brain: AIBrain = null
var _home_position: Vector3 = Vector3.ZERO
var _station_id: String = ""
var _returning: bool = false
var _threat_timer: float = 0.0
var _arrived: bool = false

const RETURN_ARRIVE_DIST: float = 500.0
const MOVE_ARRIVE_DIST: float = 200.0
const THREAT_TIMEOUT: float = 15.0


func _ready() -> void:
	_ship = get_parent() as ShipController
	await get_tree().process_frame
	_brain = _ship.get_node_or_null("AIBrain") as AIBrain if _ship else null
	if _brain:
		apply_command(command, command_params)


func apply_command(cmd: StringName, params: Dictionary = {}) -> void:
	command = cmd
	command_params = params
	_returning = false
	_arrived = false
	_threat_timer = 0.0
	if _brain == null:
		return

	match cmd:
		&"move_to":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			_home_position = target_pos
			_brain.set_patrol_area(target_pos, 50.0)
			_brain.current_state = AIBrain.State.PATROL
		&"patrol":
			var center_x: float = params.get("center_x", 0.0)
			var center_z: float = params.get("center_z", 0.0)
			var radius: float = params.get("radius", 500.0)
			var center_pos := FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			_home_position = center_pos
			_brain.set_patrol_area(center_pos, radius)
			_brain.current_state = AIBrain.State.PATROL
		&"return_to_station":
			_returning = true
			_station_id = params.get("station_id", "")
			_brain.current_state = AIBrain.State.PATROL


func _process(delta: float) -> void:
	if _brain == null or _ship == null:
		return

	# Threat response: if attacked while on non-combat command, let brain handle it,
	# then resume command after threat clears
	if _brain.current_state in [AIBrain.State.PURSUE, AIBrain.State.ATTACK, AIBrain.State.EVADE]:
		if command in [&"move_to", &"patrol"]:
			_threat_timer += delta
			if _threat_timer > THREAT_TIMEOUT or not _brain._is_target_valid():
				# Threat over, resume command
				_threat_timer = 0.0
				apply_command(command, command_params)
		return

	_threat_timer = 0.0

	# Return to station logic
	if _returning and _station_id != "":
		var ent := EntityRegistry.get_entity(_station_id)
		if not ent.is_empty():
			var station_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			var dist: float = _ship.global_position.distance_to(station_pos)
			if dist < RETURN_ARRIVE_DIST:
				# Arrived — request retrieval
				var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
				if fdm:
					fdm.retrieve_ship(fleet_index)
				return
			# Fly toward station
			_brain.set_patrol_area(station_pos, 50.0)

	# Move-to arrival check
	if command == &"move_to" and not _arrived:
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_arrived = true
			# Hold position at destination
			_brain.set_patrol_area(target_pos, 50.0)
			# Update EntityRegistry extra for map display
			var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
			if fdm:
				fdm.update_entity_extra(fleet_index, "arrived", true)
