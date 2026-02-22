class_name SquadronAICommand
extends Node

# =============================================================================
# Squadron AI Command — Formation follow for squadron members.
# Replaces SquadronAIController. Talks to AIController instead of AIBrain.
# =============================================================================

var fleet_index: int = -1
var squadron = null
var leader_node: Node3D = null

var _ship = null
var _ctrl: AIController = null
var _bridge: FleetAICommand = null
var _tick_timer: float = 0.0

const TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL


func _ready() -> void:
	_ship = get_parent()
	if _ship:
		_ctrl = _ship.get_node_or_null("AIController")
		_bridge = _ship.get_node_or_null("FleetAICommand")


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0

	if _ctrl == null or squadron == null:
		return

	# If FleetAICommand has an active command that hasn't arrived, let it handle navigation
	if _bridge and not _bridge._arrived and _bridge.command in [&"move_to", &"patrol", &"attack", &"return_to_station", &"mine"]:
		return

	# Mining state is handled entirely by AIMiningBehavior
	if _ctrl.current_state == AIController.State.MINING:
		return

	# Validate leader
	if leader_node == null or not is_instance_valid(leader_node):
		_ctrl.formation_leader = null
		_ctrl.current_state = AIController.State.PATROL
		return

	# Calculate formation offset
	var member_idx: int = squadron.get_member_index(fleet_index)
	if member_idx < 0:
		return
	var offset := SquadronFormation.get_offset(
		squadron.formation_type, member_idx, squadron.member_fleet_indices.size()
	)

	# Follow leader in formation
	_ctrl.formation_leader = leader_node
	_ctrl.formation_offset = offset
	if _ctrl.current_state != AIController.State.FORMATION:
		_ctrl.current_state = AIController.State.FORMATION
