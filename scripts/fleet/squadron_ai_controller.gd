class_name SquadronAIController
extends Node

# =============================================================================
# Squadron AI Controller — Formation follow for squadron members
# Attached as child of deployed fleet NPC. Ticks at 10Hz.
# Writes to AIBrain: formation_leader, formation_offset, current_state
# =============================================================================

var fleet_index: int = -1
var squadron: Squadron = null
var leader_node: Node3D = null

var _ship: ShipController = null
var _brain: AIBrain = null
var _bridge: FleetAIBridge = null
var _tick_timer: float = 0.0

const TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL


func _ready() -> void:
	_ship = get_parent() as ShipController
	if _ship:
		_brain = _ship.get_node_or_null("AIBrain") as AIBrain
		_bridge = _ship.get_node_or_null("FleetAIBridge") as FleetAIBridge


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0

	if _brain == null or squadron == null:
		return

	# If FleetAIBridge has an active command that hasn't arrived,
	# let the bridge handle navigation — don't override to FORMATION
	if _bridge and not _bridge._arrived and _bridge.command in [&"move_to", &"patrol", &"attack", &"return_to_station", &"mine"]:
		return

	# Mining state is handled entirely by AIMiningBehavior — don't override
	if _brain.current_state == AIBrain.State.MINING:
		return

	# Validate leader
	if leader_node == null or not is_instance_valid(leader_node):
		_brain.formation_leader = null
		_brain.current_state = AIBrain.State.PATROL
		return

	# Calculate formation offset
	var member_idx: int = squadron.get_member_index(fleet_index)
	if member_idx < 0:
		return
	var offset := SquadronFormation.get_offset(
		squadron.formation_type, member_idx, squadron.member_fleet_indices.size()
	)

	# Follow leader in formation
	_brain.formation_leader = leader_node
	_brain.formation_offset = offset
	if _brain.current_state != AIBrain.State.FORMATION:
		_brain.current_state = AIBrain.State.FORMATION
