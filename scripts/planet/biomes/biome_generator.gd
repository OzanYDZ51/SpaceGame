class_name BiomeGenerator
extends RefCounted

# =============================================================================
# Biome Generator — Determines biome type from sphere position + heightmap.
# Uses latitude + altitude + moisture/temperature noise for classification.
#
# IMPORTANT: Noise frequencies here MUST match the GPU shader
# (planet_terrain_splatmap.gdshader) so CPU biome queries and visual rendering
# agree. The shader uses freq ~6 on unit sphere for moisture, ~5 for temperature.
# =============================================================================

var _moisture_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _warp_noise: FastNoiseLite  # Domain warp for organic shapes
var _planet_type: PlanetData.PlanetType
var _ocean_level: float = 0.0
var _terrain_amplitude: float = 0.06


func setup(seed_val: int, planet_type: PlanetData.PlanetType, ocean_level: float, amplitude: float = 0.06) -> void:
	_planet_type = planet_type
	_ocean_level = ocean_level
	_terrain_amplitude = amplitude

	# Moisture noise — freq 6 on unit sphere (matches shader sn * 6.0)
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = seed_val + 5000
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture_noise.frequency = 6.0
	_moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture_noise.fractal_octaves = 5
	_moisture_noise.fractal_lacunarity = 2.1
	_moisture_noise.fractal_gain = 0.5

	# Temperature noise — freq 5 on unit sphere (matches shader sn * 5.0)
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = seed_val + 7000
	_temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_temperature_noise.frequency = 5.0
	_temperature_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temperature_noise.fractal_octaves = 4
	_temperature_noise.fractal_lacunarity = 2.1
	_temperature_noise.fractal_gain = 0.5

	# Domain warp noise — organic continent shapes
	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed = seed_val + 3000
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.frequency = 3.0
	_warp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_warp_noise.fractal_octaves = 3
	_warp_noise.fractal_lacunarity = 2.1
	_warp_noise.fractal_gain = 0.5


## Get the biome at a given sphere point with a known height value.
## height: normalized height from heightmap (0 to amplitude).
func get_biome(sphere_point: Vector3, height: float) -> BiomeTypes.Biome:
	if _planet_type == PlanetData.PlanetType.LAVA:
		return _classify_lava(sphere_point, height)
	if _planet_type == PlanetData.PlanetType.ICE:
		return _classify_ice(sphere_point, height)
	if _planet_type == PlanetData.PlanetType.GAS_GIANT:
		return BiomeTypes.Biome.DESERT
	return _classify_temperate(sphere_point, height)


## Get climate values for a sphere point (matches shader get_climate).
func get_climate(sp: Vector3, height: float) -> Vector2:
	var latitude: float = absf(sp.y)

	# Domain warp for organic shapes
	var wx: float = _warp_noise.get_noise_3d(sp.x, sp.y, sp.z)
	var wy: float = _warp_noise.get_noise_3d(sp.x + 5.2, sp.y + 1.3, sp.z + 2.8)
	var wz: float = _warp_noise.get_noise_3d(sp.x + 1.7, sp.y + 9.2, sp.z + 6.1)
	var warped := Vector3(sp.x + wx * 1.2, sp.y + wy * 1.2, sp.z + wz * 1.2)

	# Moisture
	var moisture: float = (_moisture_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
	moisture = clampf(moisture, 0.0, 1.0)

	# Temperature
	var base_temp: float = 1.0 - pow(latitude, 1.3) * 0.9
	var temp_noise: float = (_temperature_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
	var alt_cool: float = height / maxf(_terrain_amplitude, 0.001) * 0.35
	var temperature: float = clampf(base_temp + (temp_noise - 0.5) * 0.35 - alt_cool, 0.0, 1.0)

	return Vector2(temperature, moisture)


func _classify_temperate(sp: Vector3, height: float) -> BiomeTypes.Biome:
	if height < _ocean_level and _ocean_level > 0.001:
		return BiomeTypes.Biome.OCEAN

	var above_ocean: float = height - _ocean_level
	if _ocean_level > 0.001 and above_ocean < _terrain_amplitude * 0.06:
		return BiomeTypes.Biome.BEACH

	var climate := get_climate(sp, height)
	var temp: float = climate.x
	var moist: float = climate.y
	var norm_h: float = height / maxf(_terrain_amplitude, 0.001)

	# High altitude
	if norm_h > 0.72:
		if temp < 0.35:
			return BiomeTypes.Biome.SNOW
		return BiomeTypes.Biome.MOUNTAIN

	# Main biome classification (matches shader weight centers)
	if temp > 0.7:
		if moist < 0.3:
			return BiomeTypes.Biome.DESERT
		if moist < 0.55:
			return BiomeTypes.Biome.SAVANNA
		if moist < 0.75:
			return BiomeTypes.Biome.GRASSLAND
		return BiomeTypes.Biome.RAINFOREST
	elif temp > 0.4:
		if moist < 0.25:
			return BiomeTypes.Biome.SAVANNA
		if moist < 0.55:
			return BiomeTypes.Biome.GRASSLAND
		return BiomeTypes.Biome.FOREST
	elif temp > 0.2:
		if moist < 0.4:
			return BiomeTypes.Biome.TUNDRA
		return BiomeTypes.Biome.TAIGA
	else:
		return BiomeTypes.Biome.SNOW


func _classify_lava(sp: Vector3, height: float) -> BiomeTypes.Biome:
	var norm_h: float = height / maxf(_terrain_amplitude, 0.001)
	if norm_h < 0.2:
		return BiomeTypes.Biome.VOLCANIC
	if norm_h > 0.7:
		return BiomeTypes.Biome.MOUNTAIN
	return BiomeTypes.Biome.DESERT


func _classify_ice(sp: Vector3, height: float) -> BiomeTypes.Biome:
	var latitude: float = absf(sp.y)
	var norm_h: float = height / maxf(_terrain_amplitude, 0.001)
	if norm_h > 0.5 or latitude > 0.55:
		return BiomeTypes.Biome.SNOW
	if latitude > 0.25:
		return BiomeTypes.Biome.TUNDRA
	return BiomeTypes.Biome.TAIGA
