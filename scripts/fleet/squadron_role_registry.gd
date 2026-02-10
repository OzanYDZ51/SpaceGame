class_name SquadronRoleRegistry
extends RefCounted

# =============================================================================
# Squadron Role Registry — Static registry of squadron member roles
# =============================================================================

const ROLES: Array[Dictionary] = [
	{"id": &"follow", "display": "SUIVRE", "color": Color(0.4, 0.65, 1.0)},
	{"id": &"attack", "display": "ATTAQUER", "color": Color(1.0, 0.4, 0.3)},
	{"id": &"defend", "display": "DEFENDRE", "color": Color(0.3, 1.0, 0.5)},
	{"id": &"intercept", "display": "INTERCEPTER", "color": Color(1.0, 0.7, 0.2)},
	{"id": &"mimic", "display": "COPIER", "color": Color(0.7, 0.55, 1.0)},
]


static func get_all_roles() -> Array[Dictionary]:
	return ROLES


static func get_role_display_name(role_id: StringName) -> String:
	for r in ROLES:
		if r["id"] == role_id:
			return r["display"]
	return "SUIVRE"


static func get_role_color(role_id: StringName) -> Color:
	for r in ROLES:
		if r["id"] == role_id:
			return r["color"]
	return Color(0.4, 0.65, 1.0)


static func get_role_short(role_id: StringName) -> String:
	match role_id:
		&"follow": return "S"
		&"attack": return "A"
		&"defend": return "D"
		&"intercept": return "I"
		&"mimic": return "C"
	return "S"
