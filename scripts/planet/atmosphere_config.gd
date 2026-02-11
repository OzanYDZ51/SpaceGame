class_name AtmosphereConfig
extends RefCounted

# =============================================================================
# Atmosphere Config — Per-planet-type atmosphere visual parameters
# =============================================================================

var scatter_color: Color = Color(0.3, 0.5, 1.0)   ## Rayleigh scatter (atmosphere tint)
var glow_color: Color = Color(0.4, 0.6, 1.0)       ## Outer glow ring color
var density: float = 1.0                            ## 0-2 range
var atmosphere_scale: float = 1.08                  ## Ratio to planet render_radius
var glow_intensity: float = 1.5                     ## HDR glow strength
var glow_falloff: float = 3.0                       ## How fast glow fades at edges


static func from_planet_data(pd: PlanetData) -> AtmosphereConfig:
	var cfg := AtmosphereConfig.new()
	cfg.density = pd.atmosphere_density

	# glow_falloff: controls ring thinness (squared in exp, higher = thinner)
	# glow_intensity: overall brightness of the atmosphere ring
	# atmosphere_scale: how far the atmosphere mesh extends beyond the planet
	match pd.type:
		PlanetData.PlanetType.ROCKY:
			cfg.scatter_color = Color(0.3, 0.5, 1.0)
			cfg.glow_color = Color(0.2, 0.35, 0.75)
			cfg.atmosphere_scale = 1.06
			cfg.glow_intensity = 1.0
			cfg.glow_falloff = 3.0
		PlanetData.PlanetType.OCEAN:
			cfg.scatter_color = Color(0.2, 0.4, 1.0)
			cfg.glow_color = Color(0.15, 0.35, 0.85)
			cfg.atmosphere_scale = 1.08
			cfg.glow_intensity = 1.2
			cfg.glow_falloff = 2.5
		PlanetData.PlanetType.LAVA:
			cfg.scatter_color = Color(1.0, 0.35, 0.1)
			cfg.glow_color = Color(0.7, 0.2, 0.03)
			cfg.atmosphere_scale = 1.04
			cfg.glow_intensity = 0.6
			cfg.glow_falloff = 4.0
		PlanetData.PlanetType.ICE:
			cfg.scatter_color = Color(0.5, 0.7, 1.0)
			cfg.glow_color = Color(0.3, 0.5, 0.8)
			cfg.atmosphere_scale = 1.05
			cfg.glow_intensity = 0.8
			cfg.glow_falloff = 3.0
		PlanetData.PlanetType.GAS_GIANT:
			cfg.scatter_color = Color(0.6, 0.45, 0.25)
			cfg.glow_color = Color(0.4, 0.3, 0.15)
			cfg.atmosphere_scale = 1.08
			cfg.glow_intensity = 1.0
			cfg.glow_falloff = 2.5

	# Tint by planet color for extra variety
	cfg.scatter_color = cfg.scatter_color.lerp(pd.color, 0.2)
	cfg.glow_color = cfg.glow_color.lerp(pd.color, 0.15)

	# Scale intensity by density
	cfg.glow_intensity *= cfg.density

	return cfg
