class_name SquadronManager
extends Node

# =============================================================================
# Squadron Manager — CRUD + order propagation for squadrons
# Child of GameManager.
# =============================================================================

signal squadron_changed

var _fleet = null
var _fleet_deployment_mgr = null


func initialize(fleet, fdm) -> void:
	_fleet = fleet
	_fleet_deployment_mgr = fdm


# =========================================================================
# CRUD
# =========================================================================

func create_squadron(leader_fleet_index: int, sq_name: String = "") -> Squadron:
	if _fleet == null:
		return null
	if _fleet.get_ship_squadron(leader_fleet_index) != null:
		return null

	var sq =Squadron.new()
	sq.squadron_id = _fleet.next_squadron_id()
	sq.squadron_name = sq_name if sq_name != "" else "Escadron %d" % sq.squadron_id
	sq.leader_fleet_index = leader_fleet_index
	sq.formation_type = &"echelon"

	if leader_fleet_index >= 0 and leader_fleet_index < _fleet.ships.size():
		_fleet.ships[leader_fleet_index].squadron_id = sq.squadron_id
		_fleet.ships[leader_fleet_index].squadron_role = &""

	_fleet.squadrons.append(sq)
	squadron_changed.emit()
	return sq


func disband_squadron(squadron_id: int) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return

	for idx in sq.get_all_indices():
		if idx >= 0 and idx < _fleet.ships.size():
			_fleet.ships[idx].squadron_id = -1
			_fleet.ships[idx].squadron_role = &""
		_detach_squadron_controller(idx)

	_fleet.squadrons.erase(sq)
	squadron_changed.emit()


func add_to_squadron(squadron_id: int, fleet_index: int) -> bool:
	if _fleet == null:
		return false
	if fleet_index < 0 or fleet_index >= _fleet.ships.size():
		return false
	if _fleet.ships[fleet_index].deployment_state == FleetShip.DeploymentState.DESTROYED:
		return false
	if _fleet.get_ship_squadron(fleet_index) != null:
		return false
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return false

	sq.add_member(fleet_index)

	if fleet_index >= 0 and fleet_index < _fleet.ships.size():
		_fleet.ships[fleet_index].squadron_id = squadron_id
		_fleet.ships[fleet_index].squadron_role = &""

	# If already deployed, attach AI controller
	if _fleet_deployment_mgr:
		var npc = _fleet_deployment_mgr.get_deployed_npc(fleet_index)
		if npc:
			setup_squadron_controller(fleet_index, npc)

	squadron_changed.emit()
	return true


func remove_from_squadron(fleet_index: int) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_ship_squadron(fleet_index)
	if sq == null:
		return

	# If this is the leader, disband the whole squadron
	if sq.is_leader(fleet_index):
		disband_squadron(sq.squadron_id)
		return

	sq.remove_member(fleet_index)
	if fleet_index >= 0 and fleet_index < _fleet.ships.size():
		_fleet.ships[fleet_index].squadron_id = -1
		_fleet.ships[fleet_index].squadron_role = &""
	_detach_squadron_controller(fleet_index)
	squadron_changed.emit()


func set_formation(squadron_id: int, formation_type: StringName) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return
	sq.formation_type = formation_type
	for idx in sq.member_fleet_indices:
		_refresh_controller(idx, sq)
	squadron_changed.emit()


func get_squadron_for_ship(fleet_index: int) -> Squadron:
	if _fleet == null:
		return null
	return _fleet.get_ship_squadron(fleet_index)


func get_player_squadron() -> Squadron:
	if _fleet == null:
		return null
	return _fleet.get_ship_squadron(-1)


func create_player_squadron(sq_name: String = "Mon Escadron") -> Squadron:
	return create_squadron(-1, sq_name)


func rename_squadron(squadron_id: int, new_name: String) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return
	sq.squadron_name = new_name
	squadron_changed.emit()


func promote_leader(squadron_id: int, new_leader_fleet_index: int) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return
	if sq.is_leader(new_leader_fleet_index) or not sq.is_member(new_leader_fleet_index):
		return

	var old_leader_idx: int = sq.leader_fleet_index

	sq.remove_member(new_leader_fleet_index)
	sq.leader_fleet_index = new_leader_fleet_index
	if old_leader_idx >= 0 and old_leader_idx < _fleet.ships.size():
		sq.add_member(old_leader_idx)

	# Update FleetShip refs
	if new_leader_fleet_index >= 0 and new_leader_fleet_index < _fleet.ships.size():
		_fleet.ships[new_leader_fleet_index].squadron_role = &""
	if old_leader_idx >= 0 and old_leader_idx < _fleet.ships.size():
		_fleet.ships[old_leader_idx].squadron_role = &""

	# Refresh AI controllers
	_detach_squadron_controller(new_leader_fleet_index)
	if old_leader_idx >= 0 and _fleet_deployment_mgr:
		var npc = _fleet_deployment_mgr.get_deployed_npc(old_leader_idx)
		if npc:
			setup_squadron_controller(old_leader_idx, npc)
	for idx in sq.member_fleet_indices:
		_refresh_controller(idx, sq)

	squadron_changed.emit()


## Reset a member's individual command so it goes back to following the leader.
func reset_to_follow(fleet_index: int) -> void:
	if _fleet == null or _fleet_deployment_mgr == null:
		return
	var sq = _fleet.get_ship_squadron(fleet_index)
	if sq == null or sq.is_leader(fleet_index):
		return
	# Clear the bridge command so SquadronAICommand resumes formation
	var npc = _fleet_deployment_mgr.get_deployed_npc(fleet_index)
	if npc:
		var bridge = npc.get_node_or_null("FleetAICommand")
		if bridge:
			bridge._arrived = true
			bridge.command = &""
		# Re-attach controller if missing
		var ctrl = npc.get_node_or_null("SquadronAICommand")
		if ctrl == null:
			setup_squadron_controller(fleet_index, npc)
	# Clear deployed command on FleetShip
	if fleet_index >= 0 and fleet_index < _fleet.ships.size():
		_fleet.ships[fleet_index].deployed_command = &""
		_fleet.ships[fleet_index].deployed_command_params = {}


# =========================================================================
# Order propagation — leader issues an order, members follow
# =========================================================================

func propagate_leader_order(squadron_id: int, order_id: StringName, params: Dictionary) -> void:
	if _fleet == null or _fleet_deployment_mgr == null:
		return
	var sq = _fleet.get_squadron(squadron_id)
	if sq == null:
		return

	for member_idx in sq.member_fleet_indices:
		var fs = _fleet.ships[member_idx] if member_idx < _fleet.ships.size() else null
		if fs == null:
			continue

		if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
			# Deploy docked members — setup_squadron_controller() will clear
			# their FleetAICommand on deploy so they follow in formation
			_fleet_deployment_mgr.request_deploy(member_idx, order_id, params)
		elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
			# Clear FleetAICommand so SquadronAICommand takes over and
			# members follow the leader in formation instead of going to
			# the same absolute destination independently
			var npc = _fleet_deployment_mgr.get_deployed_npc(member_idx)
			if npc:
				var bridge = npc.get_node_or_null("FleetAICommand")
				if bridge:
					bridge._arrived = true
					bridge.command = &""
			fs.deployed_command = &""
			fs.deployed_command_params = {}


# =========================================================================
# AI controller hooks (called by FleetDeploymentManager)
# =========================================================================

func on_ship_deployed(fleet_index: int, npc: Node) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_ship_squadron(fleet_index)
	if sq == null:
		return
	if sq.is_leader(fleet_index):
		# Leader just deployed — set up controllers for members deployed before the leader
		for member_idx in sq.member_fleet_indices:
			if _fleet_deployment_mgr:
				var member_npc = _fleet_deployment_mgr.get_deployed_npc(member_idx)
				if member_npc:
					setup_squadron_controller(member_idx, member_npc)
		return
	setup_squadron_controller(fleet_index, npc)


func on_ship_retrieved(fleet_index: int) -> void:
	_detach_squadron_controller(fleet_index)


func on_member_destroyed(fleet_index: int) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_ship_squadron(fleet_index)
	if sq == null:
		return

	if sq.is_leader(fleet_index):
		for idx in sq.member_fleet_indices:
			_detach_squadron_controller(idx)
		disband_squadron(sq.squadron_id)
	else:
		sq.remove_member(fleet_index)
		if fleet_index >= 0 and fleet_index < _fleet.ships.size():
			_fleet.ships[fleet_index].squadron_id = -1
			_fleet.ships[fleet_index].squadron_role = &""
		squadron_changed.emit()


# =========================================================================
# Internal — SquadronAICommand attach/detach
# =========================================================================

func setup_squadron_controller(fleet_index: int, npc: Node) -> void:
	if _fleet == null:
		return
	var sq = _fleet.get_ship_squadron(fleet_index)
	if sq == null or sq.is_leader(fleet_index):
		return

	var leader_node: Node3D = _resolve_leader_node(sq)
	if leader_node == null:
		return

	var existing = npc.get_node_or_null("SquadronAICommand")
	if existing:
		existing.queue_free()

	var ctrl =SquadronAICommand.new()
	ctrl.name = "SquadronAICommand"
	ctrl.fleet_index = fleet_index
	ctrl.squadron = sq
	ctrl.leader_node = leader_node
	npc.add_child(ctrl)

	# Clear FleetAICommand command so SquadronAICommand takes priority immediately
	var bridge = npc.get_node_or_null("FleetAICommand")
	if bridge:
		bridge._arrived = true
		bridge.command = &""
	if fleet_index >= 0 and fleet_index < _fleet.ships.size():
		_fleet.ships[fleet_index].deployed_command = &""
		_fleet.ships[fleet_index].deployed_command_params = {}


func _detach_squadron_controller(fleet_index: int) -> void:
	if _fleet_deployment_mgr == null:
		return
	var npc = _fleet_deployment_mgr.get_deployed_npc(fleet_index)
	if npc == null:
		return
	var ctrl = npc.get_node_or_null("SquadronAICommand")
	if ctrl:
		ctrl.queue_free()
	var brain = npc.get_node_or_null("AIController")
	if brain and brain.current_state == AIController.State.FORMATION:
		brain.formation_leader = null
		brain.current_state = AIController.State.PATROL


func _refresh_controller(fleet_index: int, sq) -> void:
	if _fleet_deployment_mgr == null:
		return
	var npc = _fleet_deployment_mgr.get_deployed_npc(fleet_index)
	if npc == null:
		return
	var ctrl = npc.get_node_or_null("SquadronAICommand")
	if ctrl:
		ctrl.squadron = sq
		ctrl.leader_node = _resolve_leader_node(sq)


func _resolve_leader_node(sq):
	if sq.leader_fleet_index < 0:
		return GameManager.player_ship
	if _fleet and sq.leader_fleet_index == _fleet.active_index:
		return GameManager.player_ship
	if _fleet_deployment_mgr:
		return _fleet_deployment_mgr.get_deployed_npc(sq.leader_fleet_index)
	return null
