class_name NetworkState
extends RefCounted

# =============================================================================
# Network State - Data structure for a player's replicated state
# All positions are in universe coordinates (float64).
# =============================================================================

var peer_id: int = -1
var player_name: String = ""
var ship_id: StringName = Constants.DEFAULT_SHIP_ID
var ship_class: StringName = &"Fighter"
var system_id: int = 0

# Universe position (float64 precision)
var pos_x: float = 0.0
var pos_y: float = 0.0
var pos_z: float = 0.0

# Physics
var velocity: Vector3 = Vector3.ZERO
var rotation_deg: Vector3 = Vector3.ZERO
var throttle: float = 0.0

# Combat state
var hull_ratio: float = 1.0
var shield_ratios: Array[float] = [1.0, 1.0, 1.0, 1.0]

# Status flags
var is_docked: bool = false
var is_dead: bool = false
var is_cruising: bool = false  ## True when cruise warp is active (phase 2 punch)
var corporation_tag: String = ""
var group_id: int = 0  ## Ephemeral party group (0 = none)

# Timing
var timestamp: float = 0.0


func to_dict() -> Dictionary:
	return {
		"pid": peer_id,
		"name": player_name,
		"ship": ship_id,
		"sys": system_id,
		"px": pos_x,
		"py": pos_y,
		"pz": pos_z,
		"vx": velocity.x,
		"vy": velocity.y,
		"vz": velocity.z,
		"rx": rotation_deg.x,
		"ry": rotation_deg.y,
		"rz": rotation_deg.z,
		"thr": throttle,
		"hull": hull_ratio,
		"shd": shield_ratios,
		"dk": is_docked,
		"dead": is_dead,
		"cr": is_cruising,
		"ctag": corporation_tag,
		"gid": group_id,
		"t": timestamp,
	}


func from_dict(d: Dictionary) -> void:
	peer_id = d.get("pid", -1)
	player_name = d.get("name", "")
	ship_id = StringName(d.get("ship", String(Constants.DEFAULT_SHIP_ID)))
	var sdata := ShipRegistry.get_ship_data(ship_id)
	ship_class = sdata.ship_class if sdata else &"Fighter"
	system_id = d.get("sys", 0)
	pos_x = d.get("px", 0.0)
	pos_y = d.get("py", 0.0)
	pos_z = d.get("pz", 0.0)
	velocity = Vector3(d.get("vx", 0.0), d.get("vy", 0.0), d.get("vz", 0.0))
	rotation_deg = Vector3(d.get("rx", 0.0), d.get("ry", 0.0), d.get("rz", 0.0))
	throttle = d.get("thr", 0.0)
	hull_ratio = d.get("hull", 1.0)
	var shd_arr = d.get("shd", [1.0, 1.0, 1.0, 1.0])
	shield_ratios.assign(shd_arr)
	is_docked = d.get("dk", false)
	is_dead = d.get("dead", false)
	is_cruising = d.get("cr", false)
	corporation_tag = d.get("ctag", "")
	group_id = d.get("gid", 0)
	timestamp = d.get("t", 0.0)


func get_universe_pos() -> Array:
	return [pos_x, pos_y, pos_z]


func set_universe_pos(pos: Array) -> void:
	pos_x = pos[0]
	pos_y = pos[1]
	pos_z = pos[2]
