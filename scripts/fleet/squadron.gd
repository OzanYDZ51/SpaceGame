class_name Squadron
extends RefCounted

# =============================================================================
# Squadron — Groups fleet ships under a leader with formation
# Members always follow the leader. Leader orders propagate to all members.
# =============================================================================

var squadron_id: int = -1
var squadron_name: String = ""
var leader_fleet_index: int = -1  # -1 = player is leader
var member_fleet_indices: Array[int] = []
var formation_type: StringName = &"echelon"


func add_member(fleet_index: int) -> void:
	if fleet_index in member_fleet_indices:
		return
	member_fleet_indices.append(fleet_index)


func remove_member(fleet_index: int) -> void:
	member_fleet_indices.erase(fleet_index)


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
	return {
		"squadron_id": squadron_id,
		"squadron_name": squadron_name,
		"leader_fleet_index": leader_fleet_index,
		"member_fleet_indices": member_fleet_indices.duplicate(),
		"formation_type": String(formation_type),
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
	return sq
