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

	match pd.type:
		PlanetData.PlanetType.ROCKY:
			cfg.scatter_color = Color(0.4, 0.55, 1.0)
			cfg.glow_color = Color(0.35, 0.5, 0.9)
			cfg.atmosphere_scale = 1.06
			cfg.glow_intensity = 1.2
			cfg.glow_falloff = 3.5
		PlanetData.PlanetType.OCEAN:
			cfg.scatter_color = Color(0.25, 0.45, 1.0)
			cfg.glow_color = Color(0.3, 0.5, 1.0)
			cfg.atmosphere_scale = 1.08
			cfg.glow_intensity = 1.6
			cfg.glow_falloff = 2.5
		PlanetData.PlanetType.LAVA:
			cfg.scatter_color = Color(1.0, 0.4, 0.15)
			cfg.glow_color = Color(1.0, 0.35, 0.1)
			cfg.atmosphere_scale = 1.05
			cfg.glow_intensity = 2.0
			cfg.glow_falloff = 4.0
		PlanetData.PlanetType.ICE:
			cfg.scatter_color = Color(0.6, 0.75, 1.0)
			cfg.glow_color = Color(0.55, 0.7, 0.95)
			cfg.atmosphere_scale = 1.07
			cfg.glow_intensity = 1.3
			cfg.glow_falloff = 3.0
		PlanetData.PlanetType.GAS_GIANT:
			cfg.scatter_color = Color(0.7, 0.55, 0.3)
			cfg.glow_color = Color(0.6, 0.45, 0.25)
			cfg.atmosphere_scale = 1.1
			cfg.glow_intensity = 1.8
			cfg.glow_falloff = 2.0

	# Tint by planet color for extra variety
	cfg.scatter_color = cfg.scatter_color.lerp(pd.color, 0.2)
	cfg.glow_color = cfg.glow_color.lerp(pd.color, 0.15)

	# Scale intensity by density
	cfg.glow_intensity *= cfg.density

	return cfg
