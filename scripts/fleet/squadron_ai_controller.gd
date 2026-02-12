class_name SquadronAIController
extends Node

# =============================================================================
# Squadron AI Controller — Manages formation + role-based combat for a member
# Attached as child of deployed fleet NPC. Ticks at 10Hz.
# Writes to AIBrain: formation_leader, formation_offset, current_state, target, ignore_threats
# Does NOT modify AIBrain._tick_formation() — reuses existing code.
# =============================================================================

var fleet_index: int = -1
var squadron: Squadron = null
var leader_node: Node3D = null

var _ship: ShipController = null
var _brain: AIBrain = null
var _bridge: FleetAIBridge = null
var _tick_timer: float = 0.0

const TICK_INTERVAL: float = 0.1  # 10Hz
const THREAT_SCAN_RANGE: float = 2000.0
const DEFEND_RANGE: float = 1500.0


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

	# If FleetAIBridge has an active move/patrol/attack command that hasn't arrived,
	# let the bridge handle navigation — don't override to FORMATION
	if _bridge and not _bridge._arrived and _bridge.command in [&"move_to", &"patrol", &"attack", &"return_to_station", &"mine"]:
		return

	# Mining state is handled entirely by AIMiningBehavior — don't override
	if _brain.current_state == AIBrain.State.MINING:
		return

	# Validate leader
	if leader_node == null or not is_instance_valid(leader_node):
		# Leader lost — fall back to patrol
		_brain.formation_leader = null
		_brain.current_state = AIBrain.State.PATROL
		_brain.ignore_threats = false
		return

	# Calculate formation offset
	var member_idx: int = squadron.get_member_index(fleet_index)
	if member_idx < 0:
		return
	var offset := SquadronFormation.get_offset(
		squadron.formation_type, member_idx, squadron.member_fleet_indices.size()
	)

	# Get role
	var role: StringName = squadron.get_role(fleet_index)

	# Role-based behavior
	match role:
		&"follow":
			_tick_follow(offset)
		&"attack":
			_tick_attack(offset)
		&"defend":
			_tick_defend(offset)
		&"intercept":
			_tick_intercept(offset)
		&"mimic":
			_tick_mimic(offset)
		_:
			_tick_follow(offset)


func _tick_follow(offset: Vector3) -> void:
	# Pure formation — AIBrain._tick_formation() handles auto-attack when leader attacks
	_set_formation(offset)
	_brain.ignore_threats = true


func _tick_attack(offset: Vector3) -> void:
	# In formation, but actively scans for threats and engages independently
	if _brain.current_state == AIBrain.State.ATTACK and _brain.target and is_instance_valid(_brain.target):
		# Currently fighting — let it finish
		_brain.ignore_threats = false
		return

	# Scan for nearby threats
	var threat := _find_nearest_threat()
	if threat:
		_brain.target = threat
		_brain.current_state = AIBrain.State.PURSUE
		_brain.ignore_threats = false
		return

	# No threats — stay in formation
	_set_formation(offset)
	_brain.ignore_threats = true


func _tick_defend(offset: Vector3) -> void:
	# Formation + only engage threats that attack leader or squadron members
	if _brain.current_state == AIBrain.State.ATTACK and _brain.target and is_instance_valid(_brain.target):
		_brain.ignore_threats = false
		return

	# Check if leader is being attacked
	var attacker := _find_attacker_of(leader_node)
	if attacker:
		_brain.target = attacker
		_brain.current_state = AIBrain.State.PURSUE
		_brain.ignore_threats = false
		return

	# Stay in formation
	_set_formation(offset)
	_brain.ignore_threats = true


func _tick_intercept(offset: Vector3) -> void:
	# Pursue leader's specific target
	var leader_brain: AIBrain = null
	if leader_node and is_instance_valid(leader_node):
		leader_brain = leader_node.get_node_or_null("AIBrain") as AIBrain

	if leader_brain and leader_brain.target and is_instance_valid(leader_brain.target):
		_brain.target = leader_brain.target
		_brain.current_state = AIBrain.State.PURSUE
		_brain.ignore_threats = false
		return

	# No leader target — stay in formation
	_set_formation(offset)
	_brain.ignore_threats = true


func _tick_mimic(offset: Vector3) -> void:
	# Copy leader's exact state
	var leader_brain: AIBrain = null
	if leader_node and is_instance_valid(leader_node):
		leader_brain = leader_node.get_node_or_null("AIBrain") as AIBrain

	if leader_brain:
		match leader_brain.current_state:
			AIBrain.State.ATTACK, AIBrain.State.PURSUE:
				if leader_brain.target and is_instance_valid(leader_brain.target):
					_brain.target = leader_brain.target
					_brain.current_state = leader_brain.current_state
					_brain.ignore_threats = false
					return
			AIBrain.State.FLEE, AIBrain.State.EVADE:
				_brain.current_state = leader_brain.current_state
				_brain.ignore_threats = true
				return

	# Default: formation
	_set_formation(offset)
	_brain.ignore_threats = true


# =========================================================================
# Helpers
# =========================================================================

func _set_formation(offset: Vector3) -> void:
	_brain.formation_leader = leader_node
	_brain.formation_offset = offset
	if _brain.current_state != AIBrain.State.FORMATION:
		_brain.current_state = AIBrain.State.FORMATION


func _find_nearest_threat() -> Node3D:
	if _ship == null:
		return null
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr == null:
		return null
	var self_id := StringName(_ship.name)
	var results := lod_mgr.get_nearest_ships(_ship.global_position, THREAT_SCAN_RANGE, 5, self_id)
	for entry in results:
		var node: Node3D = entry.get("node")
		if node and is_instance_valid(node) and _is_hostile(node):
			return node
	return null


func _find_attacker_of(target: Node3D) -> Node3D:
	if target == null:
		return null
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr == null:
		return null
	var results := lod_mgr.get_nearest_ships(target.global_position, DEFEND_RANGE, 5, StringName(target.name))
	for entry in results:
		var node: Node3D = entry.get("node")
		if node and is_instance_valid(node) and _is_hostile(node):
			# Check if this hostile is targeting our leader
			var their_brain := node.get_node_or_null("AIBrain") as AIBrain
			if their_brain and their_brain.target == target:
				return node
	return null


func _is_hostile(node: Node3D) -> bool:
	if node is ShipController:
		var sc := node as ShipController
		return sc.faction != &"player_fleet" and sc.faction != &"neutral" and sc.faction != &"friendly"
	return false
