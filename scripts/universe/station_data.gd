class_name StationData
extends Resource

# =============================================================================
# Station Data — Editable in Godot inspector
# =============================================================================

enum StationType { REPAIR, TRADE, MILITARY, MINING }

@export var station_name: String = ""
@export var station_type: StationType = StationType.REPAIR
@export var orbital_radius: float = 45_000_000.0
@export var orbital_parent: String = "star_0"
@export var orbital_period: float = 540.0
@export var orbital_angle: float = 0.0


func get_type_string() -> String:
	match station_type:
		StationType.REPAIR: return "repair"
		StationType.TRADE: return "trade"
		StationType.MILITARY: return "military"
		StationType.MINING: return "mining"
	return "repair"


static func type_from_string(s: String) -> StationType:
	match s:
		"repair": return StationType.REPAIR
		"trade": return StationType.TRADE
		"military": return StationType.MILITARY
		"mining": return StationType.MINING
	return StationType.REPAIR
