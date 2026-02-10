class_name Squadron
extends RefCounted

# =============================================================================
# Squadron — Groups fleet ships under a leader with roles and formation
# =============================================================================

var squadron_id: int = -1
var squadron_name: String = ""
var leader_fleet_index: int = -1  # -1 = player is leader
var member_fleet_indices: Array[int] = []
var formation_type: StringName = &"echelon"
var member_roles: Dictionary = {}  # fleet_index (int) -> StringName role


func add_member(fleet_index: int, role: StringName = &"follow") -> void:
	if fleet_index in member_fleet_indices:
		return
	member_fleet_indices.append(fleet_index)
	member_roles[fleet_index] = role


func remove_member(fleet_index: int) -> void:
	member_fleet_indices.erase(fleet_index)
	member_roles.erase(fleet_index)


func set_role(fleet_index: int, role: StringName) -> void:
	if fleet_index in member_fleet_indices:
		member_roles[fleet_index] = role


func get_role(fleet_index: int) -> StringName:
	return member_roles.get(fleet_index, &"follow")


func is_leader(fleet_index: int) -> bool:
	return fleet_index == leader_fleet_index


func is_member(fleet_index: int) -> bool:
	return fleet_index in member_fleet_indices


func get_member_index(fleet_index: int) -> int:
	return member_fleet_indices.find(fleet_index)


func get_all_indices() -> Array[int]:
	var result: Array[int] = []
	if leader_fleet_index >= 0:
		result.append(leader_fleet_index)
	result.append_array(member_fleet_indices)
	return result


func serialize() -> Dictionary:
	var roles_out: Dictionary = {}
	for k in member_roles:
		roles_out[str(k)] = String(member_roles[k])
	return {
		"squadron_id": squadron_id,
		"squadron_name": squadron_name,
		"leader_fleet_index": leader_fleet_index,
		"member_fleet_indices": member_fleet_indices.duplicate(),
		"formation_type": String(formation_type),
		"member_roles": roles_out,
	}


static func deserialize(data: Dictionary) -> Squadron:
	var sq := Squadron.new()
	sq.squadron_id = int(data.get("squadron_id", -1))
	sq.squadron_name = data.get("squadron_name", "")
	sq.leader_fleet_index = int(data.get("leader_fleet_index", -1))
	var members: Array = data.get("member_fleet_indices", [])
	for m in members:
		sq.member_fleet_indices.append(int(m))
	sq.formation_type = StringName(data.get("formation_type", "echelon"))
	var roles: Dictionary = data.get("member_roles", {})
	for k in roles:
		sq.member_roles[int(k)] = StringName(roles[k])
	return sq
