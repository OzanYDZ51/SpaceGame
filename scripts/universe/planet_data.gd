class_name PlanetData
extends Resource

# =============================================================================
# Planet Data — Editable in Godot inspector, saved as sub-resource in .tres
# =============================================================================

enum PlanetType { ROCKY, LAVA, OCEAN, GAS_GIANT, ICE }

@export var planet_name: String = ""
@export var type: PlanetType = PlanetType.ROCKY
@export var orbital_radius: float = 50_000_000.0
@export var orbital_period: float = 600.0
@export var orbital_angle: float = 0.0
@export var radius: float = 3_000_000.0
@export var color: Color = Color(0.5, 0.5, 0.5)
@export var has_rings: bool = false


## Helper to get type as string (for backwards compat with existing code).
func get_type_string() -> String:
	match type:
		PlanetType.ROCKY: return "rocky"
		PlanetType.LAVA: return "lava"
		PlanetType.OCEAN: return "ocean"
		PlanetType.GAS_GIANT: return "gas_giant"
		PlanetType.ICE: return "ice"
	return "rocky"


## Create from type string (used by SystemGenerator).
static func type_from_string(s: String) -> PlanetType:
	match s:
		"rocky": return PlanetType.ROCKY
		"lava": return PlanetType.LAVA
		"ocean": return PlanetType.OCEAN
		"gas_giant": return PlanetType.GAS_GIANT
		"ice": return PlanetType.ICE
	return PlanetType.ROCKY
