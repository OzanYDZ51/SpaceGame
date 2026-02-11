class_name TerrainMaterialFactory
extends RefCounted

# =============================================================================
# Terrain Material Factory — Creates ShaderMaterial for each planet biome/type
# Centralizes color palette + shader parameter configuration.
# =============================================================================

## Planet type color palettes: { color_low, color_mid, color_high, color_peak, color_cliff, ocean_color }
const PALETTES: Dictionary = {
	"rocky": {
		"low": Color(0.18, 0.14, 0.10),
		"mid": Color(0.38, 0.32, 0.24),
		"high": Color(0.52, 0.48, 0.40),
		"peak": Color(0.80, 0.78, 0.72),
		"cliff": Color(0.28, 0.24, 0.18),
		"ocean": Color(0.08, 0.20, 0.45),
	},
	"lava": {
		"low": Color(0.8, 0.25, 0.05),
		"mid": Color(0.35, 0.15, 0.08),
		"high": Color(0.20, 0.12, 0.08),
		"peak": Color(0.10, 0.08, 0.06),
		"cliff": Color(0.6, 0.18, 0.04),
		"ocean": Color(0.9, 0.3, 0.05),
	},
	"ocean": {
		"low": Color(0.10, 0.25, 0.55),
		"mid": Color(0.20, 0.45, 0.25),
		"high": Color(0.40, 0.38, 0.30),
		"peak": Color(0.85, 0.83, 0.80),
		"cliff": Color(0.30, 0.26, 0.20),
		"ocean": Color(0.05, 0.15, 0.40),
	},
	"ice": {
		"low": Color(0.65, 0.72, 0.80),
		"mid": Color(0.75, 0.80, 0.88),
		"high": Color(0.85, 0.88, 0.92),
		"peak": Color(0.95, 0.96, 0.98),
		"cliff": Color(0.50, 0.55, 0.62),
		"ocean": Color(0.55, 0.65, 0.80),
	},
	"gas_giant": {
		"low": Color(0.65, 0.50, 0.30),
		"mid": Color(0.75, 0.60, 0.35),
		"high": Color(0.85, 0.70, 0.40),
		"peak": Color(0.90, 0.80, 0.50),
		"cliff": Color(0.55, 0.42, 0.25),
		"ocean": Color(0.55, 0.42, 0.25),
	},
}


## Create the basic terrain shader material for a planet.
static func create_basic(pd: PlanetData, planet_radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet/planet_terrain.gdshader")
	mat.set_shader_parameter("planet_radius", planet_radius)

	var type_key: String = pd.get_type_string()
	var palette: Dictionary = PALETTES.get(type_key, PALETTES["rocky"])

	mat.set_shader_parameter("color_low", palette["low"])
	mat.set_shader_parameter("color_mid", palette["mid"])
	mat.set_shader_parameter("color_high", palette["high"])
	mat.set_shader_parameter("color_peak", palette["peak"])
	mat.set_shader_parameter("color_cliff", palette["cliff"])

	# Tint toward planet base color
	for param in ["color_low", "color_mid", "color_high"]:
		var c: Color = mat.get_shader_parameter(param)
		mat.set_shader_parameter(param, c.lerp(pd.color, 0.15))

	return mat


## Create the splatmap shader material (used when player is close).
static func create_splatmap(pd: PlanetData, planet_radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet/planet_terrain_splatmap.gdshader")
	mat.set_shader_parameter("planet_radius", planet_radius)

	var type_key: String = pd.get_type_string()
	var palette: Dictionary = PALETTES.get(type_key, PALETTES["rocky"])

	mat.set_shader_parameter("color_low", palette["low"])
	mat.set_shader_parameter("color_mid", palette["mid"])
	mat.set_shader_parameter("color_high", palette["high"])
	mat.set_shader_parameter("color_peak", palette["peak"])
	mat.set_shader_parameter("color_cliff", palette["cliff"])
	mat.set_shader_parameter("color_ocean", palette["ocean"])
	mat.set_shader_parameter("ocean_level", pd.ocean_level)

	# Tint toward planet base color
	for param in ["color_low", "color_mid", "color_high"]:
		var c: Color = mat.get_shader_parameter(param)
		mat.set_shader_parameter(param, c.lerp(pd.color, 0.15))

	return mat


## Create ocean surface material.
static func create_ocean(pd: PlanetData) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet/planet_ocean.gdshader")

	var type_key: String = pd.get_type_string()
	var palette: Dictionary = PALETTES.get(type_key, PALETTES["ocean"])

	mat.set_shader_parameter("ocean_color_shallow", Color(palette["ocean"]).lightened(0.3))
	mat.set_shader_parameter("ocean_color_deep", palette["ocean"])

	return mat


## Create lava surface material.
static func create_lava(_pd: PlanetData) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet/planet_lava.gdshader")
	return mat
