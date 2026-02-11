class_name BiomeGenerator
extends RefCounted

# =============================================================================
# Biome Generator — Determines biome type from sphere position + heightmap.
# Uses latitude + altitude + moisture/temperature noise for classification.
# Generates the same biome data used by the GPU terrain splatmap shader
# (noise seeds and frequencies must match shader constants).
# =============================================================================

var _moisture_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _planet_type: PlanetData.PlanetType
var _ocean_level: float = 0.0


func setup(seed_val: int, planet_type: PlanetData.PlanetType, ocean_level: float) -> void:
	_planet_type = planet_type
	_ocean_level = ocean_level

	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = seed_val + 5000
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture_noise.frequency = 0.5
	_moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture_noise.fractal_octaves = 4
	_moisture_noise.fractal_lacunarity = 2.0
	_moisture_noise.fractal_gain = 0.5

	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = seed_val + 7000
	_temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_temperature_noise.frequency = 0.35
	_temperature_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temperature_noise.fractal_octaves = 3
	_temperature_noise.fractal_lacunarity = 2.0
	_temperature_noise.fractal_gain = 0.5


## Get the biome at a given sphere point with a known height value.
## height: normalized height from heightmap (0 to amplitude).
func get_biome(sphere_point: Vector3, height: float) -> BiomeTypes.Biome:
	# Planet-type overrides
	if _planet_type == PlanetData.PlanetType.LAVA:
		return _classify_lava(sphere_point, height)
	if _planet_type == PlanetData.PlanetType.ICE:
		return _classify_ice(sphere_point, height)
	if _planet_type == PlanetData.PlanetType.GAS_GIANT:
		return BiomeTypes.Biome.DESERT  # Gas giants don't land

	# ROCKY and OCEAN use full biome classification
	return _classify_temperate(sphere_point, height)


func _classify_temperate(sp: Vector3, height: float) -> BiomeTypes.Biome:
	# Below ocean → ocean
	if height < _ocean_level and _ocean_level > 0.001:
		return BiomeTypes.Biome.OCEAN

	# Beach: just above ocean level
	var above_ocean: float = height - _ocean_level
	if _ocean_level > 0.001 and above_ocean < 0.003:
		return BiomeTypes.Biome.BEACH

	# Latitude (0 at equator, 1 at poles)
	var latitude: float = absf(sp.y)

	# Moisture noise: 0 (dry) to 1 (wet)
	var moisture: float = (_moisture_noise.get_noise_3d(
		sp.x * 1000.0, sp.y * 1000.0, sp.z * 1000.0) + 1.0) * 0.5

	# Temperature: hot at equator, cold at poles, colder at altitude
	var base_temp: float = 1.0 - latitude * 0.8
	var temp_noise: float = (_temperature_noise.get_noise_3d(
		sp.x * 1000.0, sp.y * 1000.0, sp.z * 1000.0) + 1.0) * 0.5
	var temperature: float = base_temp + temp_noise * 0.25 - height * 3.0
	temperature = clampf(temperature, 0.0, 1.0)

	# High altitude → mountain or snow
	if height > 0.05:
		if temperature < 0.3:
			return BiomeTypes.Biome.SNOW
		return BiomeTypes.Biome.MOUNTAIN

	# Classification grid: temperature x moisture
	if temperature > 0.7:
		if moisture < 0.3:
			return BiomeTypes.Biome.DESERT
		if moisture < 0.55:
			return BiomeTypes.Biome.SAVANNA
		if moisture < 0.75:
			return BiomeTypes.Biome.GRASSLAND
		return BiomeTypes.Biome.RAINFOREST
	elif temperature > 0.4:
		if moisture < 0.25:
			return BiomeTypes.Biome.SAVANNA
		if moisture < 0.55:
			return BiomeTypes.Biome.GRASSLAND
		return BiomeTypes.Biome.FOREST
	elif temperature > 0.2:
		if moisture < 0.4:
			return BiomeTypes.Biome.TUNDRA
		return BiomeTypes.Biome.TAIGA
	else:
		if temperature > 0.1:
			return BiomeTypes.Biome.TUNDRA
		return BiomeTypes.Biome.SNOW


func _classify_lava(sp: Vector3, height: float) -> BiomeTypes.Biome:
	if height < 0.02:
		return BiomeTypes.Biome.VOLCANIC  # Lava flows in lowlands
	if height > 0.06:
		return BiomeTypes.Biome.MOUNTAIN
	return BiomeTypes.Biome.DESERT  # Scorched rock


func _classify_ice(sp: Vector3, height: float) -> BiomeTypes.Biome:
	var latitude: float = absf(sp.y)
	if height > 0.03:
		return BiomeTypes.Biome.SNOW
	if latitude > 0.6:
		return BiomeTypes.Biome.SNOW
	if latitude > 0.3:
		return BiomeTypes.Biome.TUNDRA
	return BiomeTypes.Biome.TAIGA  # Some hardy life at equator
