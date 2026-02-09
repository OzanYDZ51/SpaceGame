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
var _prev_command: StringName = &""  # For resuming after threat response
var _threat_timer: float = 0.0

const RETURN_ARRIVE_DIST: float = 500.0
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
	_threat_timer = 0.0
	if _brain == null:
		return

	match cmd:
		&"hold_position":
			var pos: Vector3 = _ship.global_position if _ship else Vector3.ZERO
			if params.has("position"):
				pos = params["position"]
			_home_position = pos
			_brain.set_patrol_area(pos, 50.0)
			_brain.current_state = AIBrain.State.PATROL
		&"follow_player":
			_brain.formation_leader = GameManager.player_ship
			var idx: int = params.get("formation_index", fleet_index)
			# Stagger formation offset based on index
			var side: float = -1.0 if idx % 2 == 0 else 1.0
			var row: int = idx / 2
			_brain.formation_offset = Vector3(side * (80.0 + row * 40.0), 0.0, 60.0 + row * 50.0)
			_brain.current_state = AIBrain.State.FORMATION
		&"patrol":
			var center: Vector3 = params.get("center", _ship.global_position if _ship else Vector3.ZERO)
			var radius: float = params.get("radius", 500.0)
			_home_position = center
			_brain.set_patrol_area(center, radius)
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
		if command in [&"hold_position", &"patrol", &"follow_player"]:
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
