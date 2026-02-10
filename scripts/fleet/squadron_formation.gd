class_name SquadronFormation
extends RefCounted

# =============================================================================
# Squadron Formation — Calculates member offsets in leader's local space
# Forward = -Z (Godot convention)
# =============================================================================

const FORMATIONS: Array[Dictionary] = [
	{"id": &"echelon", "display": "ECHELON"},
	{"id": &"vee", "display": "V"},
	{"id": &"line", "display": "LIGNE"},
	{"id": &"column", "display": "COLONNE"},
	{"id": &"spread", "display": "DISPERSION"},
]


static func get_available_formations() -> Array[Dictionary]:
	return FORMATIONS


static func get_formation_display(formation_id: StringName) -> String:
	for f in FORMATIONS:
		if f["id"] == formation_id:
			return f["display"]
	return "ECHELON"


## Returns offset in leader's local space for the given member index.
## member_index: 0-based index within members (excluding leader).
## member_count: total members (excluding leader).
static func get_offset(formation_type: StringName, member_index: int, member_count: int, spacing: float = 150.0) -> Vector3:
	match formation_type:
		&"echelon":
			return _echelon(member_index, spacing)
		&"vee":
			return _vee(member_index, spacing)
		&"line":
			return _line(member_index, member_count, spacing)
		&"column":
			return _column(member_index, spacing)
		&"spread":
			return _spread(member_index, member_count, spacing)
	return _echelon(member_index, spacing)


# Staggered triangle: alternating left/right, each row further back
static func _echelon(idx: int, spacing: float) -> Vector3:
	var row: int = idx + 1
	var side: float = -1.0 if (idx % 2 == 0) else 1.0
	var lateral: float = side * ((row + 1) / 2) * spacing
	var back: float = row * spacing * 0.7  # +Z = behind leader
	return Vector3(lateral, 0.0, back)


# V shape: two arms diverging behind leader
static func _vee(idx: int, spacing: float) -> Vector3:
	var side: float = -1.0 if (idx % 2 == 0) else 1.0
	var depth: int = (idx / 2) + 1
	var lateral: float = side * depth * spacing
	var back: float = depth * spacing * 0.8
	return Vector3(lateral, 0.0, back)


# Lateral line (wing-to-wing), centered on leader
static func _line(idx: int, count: int, spacing: float) -> Vector3:
	var half: float = count / 2.0
	var pos: float = (idx + 1)
	var side: float = -1.0 if (idx % 2 == 0) else 1.0
	var slot: int = (idx / 2) + 1
	return Vector3(side * slot * spacing, 0.0, 0.0)


# Single file behind leader
static func _column(idx: int, spacing: float) -> Vector3:
	return Vector3(0.0, 0.0, (idx + 1) * spacing)


# Circle around leader
static func _spread(idx: int, count: int, spacing: float) -> Vector3:
	if count <= 0:
		return Vector3.ZERO
	var angle: float = (float(idx) / float(count)) * TAU
	return Vector3(cos(angle) * spacing, 0.0, sin(angle) * spacing)
