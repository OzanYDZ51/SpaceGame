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

@export_group("Planetary Landing")
@export var render_radius: float = 0.0           ## Gameplay-scaled radius (km). 0 = auto from type
@export var terrain_seed: int = 0                 ## Seed for procedural terrain. 0 = derive from system
@export var can_land: bool = true                 ## False for gas giants
@export var atmosphere_density: float = 1.0       ## 0 = no atmosphere, 1 = Earth-like
@export var ocean_level: float = 0.0              ## 0-1 fraction of render_radius (0 = no ocean)
@export var terrain_amplitude: float = 0.0        ## 0 = auto from type
@export var heightmap_override: Texture2D = null  ## Override heightmap for hand-crafted planets
@export var biome_profile: PlanetBiomeProfile = null  ## Custom biome colors (null = type defaults)
@export var has_civilization: bool = false              ## City lights visible from orbit on night side
@export var rotation_period: float = 0.0               ## Seconds for one full rotation (0 = auto from type)


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


## Get gameplay-scaled render radius in meters. Auto-computed if not overridden.
func get_render_radius() -> float:
	if render_radius > 0.0:
		return render_radius * 1000.0  # km -> meters
	# Auto-scale: log-based from real radius (in meters)
	# Maps ~3M m (small rocky) to ~25km, ~50M m (gas giant) to ~200km
	match type:
		PlanetType.GAS_GIANT:
			return clampf(log(radius / 1000.0) * 18000.0, 100_000.0, 200_000.0)
		PlanetType.OCEAN:
			return clampf(log(radius / 1000.0) * 8000.0, 35_000.0, 70_000.0)
		PlanetType.ICE:
			return clampf(log(radius / 1000.0) * 7000.0, 25_000.0, 80_000.0)
		_:  # ROCKY, LAVA
			return clampf(log(radius / 1000.0) * 6500.0, 25_000.0, 80_000.0)


## Get terrain amplitude (fraction of render_radius). Auto from type if not set.
func get_terrain_amplitude() -> float:
	if terrain_amplitude > 0.0:
		return terrain_amplitude
	match type:
		PlanetType.ROCKY: return 0.025
		PlanetType.LAVA: return 0.03
		PlanetType.OCEAN: return 0.01
		PlanetType.ICE: return 0.02
		PlanetType.GAS_GIANT: return 0.005
	return 0.025


## Get rotation period in seconds (time for one full axial rotation).
func get_rotation_period() -> float:
	if rotation_period > 0.0:
		return rotation_period
	match type:
		PlanetType.GAS_GIANT: return 600.0    # 10 min — fast spinner like Jupiter
		PlanetType.LAVA: return 2400.0        # 40 min — slow, tidally locked feel
		PlanetType.OCEAN: return 1200.0       # 20 min
		PlanetType.ICE: return 1500.0         # 25 min
		_: return 1200.0  # ROCKY — 20 min


## Whether this planet type supports landing.
func is_landable() -> bool:
	return can_land and type != PlanetType.GAS_GIANT
