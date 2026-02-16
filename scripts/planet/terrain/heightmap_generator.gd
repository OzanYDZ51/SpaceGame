class_name HeightmapGenerator
extends RefCounted

# =============================================================================
# Heightmap Generator — Procedural terrain height via FastNoiseLite
# Mostly FLAT terrain with localized gentle hills and rare mountain zones.
# Noise sampled at low scale (100) = few broad features, not hundreds of spikes.
# =============================================================================

var _noise: FastNoiseLite = null
var _mountain_mask: FastNoiseLite = null
var _planet_type: PlanetData.PlanetType = PlanetData.PlanetType.ROCKY
var _amplitude: float = 0.015
var _ocean_level: float = 0.0

const NOISE_SCALE: float = 100.0  # Low scale = broad continental features


func setup(seed_val: int, planet_type: PlanetData.PlanetType, amplitude: float, ocean_level: float) -> void:
	_planet_type = planet_type
	_amplitude = amplitude
	_ocean_level = ocean_level

	# Base terrain — very smooth, few octaves, low frequency
	_noise = FastNoiseLite.new()
	_noise.seed = seed_val
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.3
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.4

	# Mountain mask — even lower frequency, decides where mountains CAN exist
	if planet_type != PlanetData.PlanetType.GAS_GIANT:
		_mountain_mask = FastNoiseLite.new()
		_mountain_mask.seed = seed_val + 500
		_mountain_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_mountain_mask.frequency = 0.15
		_mountain_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
		_mountain_mask.fractal_octaves = 2
		_mountain_mask.fractal_lacunarity = 2.0
		_mountain_mask.fractal_gain = 0.5


## Get height at a unit sphere point. Returns value in [0, amplitude] range.
func get_height(sphere_point: Vector3) -> float:
	var sx: float = sphere_point.x * NOISE_SCALE
	var sy: float = sphere_point.y * NOISE_SCALE
	var sz: float = sphere_point.z * NOISE_SCALE

	# Base terrain noise [-1,1] → [0,1]
	var h: float = (_noise.get_noise_3d(sx, sy, sz) + 1.0) * 0.5

	# Flatten: crush low/mid values to near-zero, only peaks survive
	# Power of 3 makes ~80% of terrain nearly flat
	h = h * h * h

	# Mountain mask: further restrict WHERE terrain can rise
	if _mountain_mask:
		var mask: float = (_mountain_mask.get_noise_3d(sx * 0.5, sy * 0.5, sz * 0.5) + 1.0) * 0.5
		# Only let terrain rise where mask > 0.55 (about 40% of surface)
		var factor: float = clampf((mask - 0.55) / 0.45, 0.0, 1.0)
		# Outside mountain zones: terrain stays at 5% of its value (nearly flat)
		h = h * (0.05 + 0.95 * factor)

	# Ocean clamping
	if _ocean_level > 0.0 and h < _ocean_level:
		h = _ocean_level

	return h * _amplitude


## Get height for a batch of sphere points (optimization for mesh generation).
func get_heights(points: PackedVector3Array) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(points.size())
	for i in points.size():
		heights[i] = get_height(points[i])
	return heights
