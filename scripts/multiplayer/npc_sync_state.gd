class_name NPCSyncState
extends RefCounted

# =============================================================================
# NPC Sync State - Compact data class for NPC state replication.
# Uses short dictionary keys to minimize bandwidth.
# =============================================================================

var npc_id: StringName = &""
var ship_id: StringName = &""
var faction: StringName = &"hostile"

# Universe position (float64 precision)
var pos_x: float = 0.0
var pos_y: float = 0.0
var pos_z: float = 0.0

# Physics
var velocity: Vector3 = Vector3.ZERO
var rotation_deg: Vector3 = Vector3.ZERO

# Combat
var hull_ratio: float = 1.0
var shield_ratio: float = 1.0

# AI
var throttle: float = 0.0
var ai_state: int = 0
var target_id: StringName = &""

# Timing
var timestamp: float = 0.0


func to_dict() -> Dictionary:
	return {
		"nid": npc_id,
		"sid": ship_id,
		"fac": faction,
		"px": pos_x,
		"py": pos_y,
		"pz": pos_z,
		"vx": velocity.x,
		"vy": velocity.y,
		"vz": velocity.z,
		"rx": rotation_deg.x,
		"ry": rotation_deg.y,
		"rz": rotation_deg.z,
		"hull": hull_ratio,
		"shd": shield_ratio,
		"thr": throttle,
		"ai": ai_state,
		"tid": target_id,
		"t": timestamp,
	}


func from_dict(d: Dictionary) -> void:
	npc_id = StringName(d.get("nid", ""))
	ship_id = StringName(d.get("sid", ""))
	faction = StringName(d.get("fac", "hostile"))
	pos_x = d.get("px", 0.0)
	pos_y = d.get("py", 0.0)
	pos_z = d.get("pz", 0.0)
	velocity = Vector3(d.get("vx", 0.0), d.get("vy", 0.0), d.get("vz", 0.0))
	rotation_deg = Vector3(d.get("rx", 0.0), d.get("ry", 0.0), d.get("rz", 0.0))
	hull_ratio = d.get("hull", 1.0)
	shield_ratio = d.get("shd", 1.0)
	throttle = d.get("thr", 0.0)
	ai_state = d.get("ai", 0)
	target_id = StringName(d.get("tid", ""))
	timestamp = d.get("t", 0.0)


func get_universe_pos() -> Array:
	return [pos_x, pos_y, pos_z]
