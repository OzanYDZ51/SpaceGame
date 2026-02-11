class_name HeightmapGenerator
extends RefCounted

# =============================================================================
# Heightmap Generator — Procedural terrain height via FastNoiseLite
# Multi-octave FBM + ridged noise for realistic mountains.
# Returns height values in [0, amplitude] range.
# =============================================================================

var _noise: FastNoiseLite = null
var _ridge_noise: FastNoiseLite = null
var _detail_noise: FastNoiseLite = null
var _planet_type: PlanetData.PlanetType = PlanetData.PlanetType.ROCKY
var _amplitude: float = 0.06
var _ocean_level: float = 0.0

# Per-type noise configs: [frequency, octaves, lacunarity, gain, noise_type]
const CONFIGS: Dictionary = {
	"rocky":     [0.6, 7, 2.0, 0.50, FastNoiseLite.TYPE_SIMPLEX_SMOOTH],
	"lava":      [0.9, 7, 2.2, 0.45, FastNoiseLite.TYPE_SIMPLEX_SMOOTH],
	"ocean":     [0.3, 6, 2.0, 0.50, FastNoiseLite.TYPE_SIMPLEX_SMOOTH],
	"ice":       [0.4, 6, 2.0, 0.55, FastNoiseLite.TYPE_SIMPLEX_SMOOTH],
	"gas_giant": [0.3, 4, 2.0, 0.50, FastNoiseLite.TYPE_SIMPLEX_SMOOTH],
}


func setup(seed_val: int, planet_type: PlanetData.PlanetType, amplitude: float, ocean_level: float) -> void:
	_planet_type = planet_type
	_amplitude = amplitude
	_ocean_level = ocean_level

	var type_key: String = _type_to_key(planet_type)
	var cfg: Array = CONFIGS.get(type_key, CONFIGS["rocky"])

	# Base terrain FBM
	_noise = FastNoiseLite.new()
	_noise.seed = seed_val
	_noise.noise_type = cfg[4]
	_noise.frequency = cfg[0]
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = cfg[1]
	_noise.fractal_lacunarity = cfg[2]
	_noise.fractal_gain = cfg[3]

	# Ridge noise for rocky/lava/ice mountains
	if planet_type in [PlanetData.PlanetType.ROCKY, PlanetData.PlanetType.LAVA, PlanetData.PlanetType.ICE]:
		_ridge_noise = FastNoiseLite.new()
		_ridge_noise.seed = seed_val + 1000
		_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_ridge_noise.frequency = cfg[0] * 2.0
		_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		_ridge_noise.fractal_octaves = 6
		_ridge_noise.fractal_lacunarity = 2.2
		_ridge_noise.fractal_gain = 0.55

	# Detail noise (adds small-scale variation to break up flat areas)
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = seed_val + 2000
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = cfg[0] * 6.0
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_lacunarity = 2.0
	_detail_noise.fractal_gain = 0.5


## Get height at a unit sphere point. Returns value in [0, amplitude] range.
func get_height(sphere_point: Vector3) -> float:
	var nx: float = sphere_point.x
	var ny: float = sphere_point.y
	var nz: float = sphere_point.z

	# Base terrain: FBM noise in [-1, 1] → remap to [0, 1]
	var h: float = (_noise.get_noise_3d(nx * 1000.0, ny * 1000.0, nz * 1000.0) + 1.0) * 0.5

	# Ridge overlay for rocky/lava/ice — dramatic mountain ranges
	if _ridge_noise:
		var ridge: float = _ridge_noise.get_noise_3d(nx * 1000.0, ny * 1000.0, nz * 1000.0)
		ridge = (ridge + 1.0) * 0.5
		ridge = ridge * ridge  # Square for sharper peaks
		h = h * 0.4 + ridge * 0.6

	# Small-scale detail (12% contribution — adds rolling hills, erosion-like features)
	if _detail_noise:
		var detail: float = (_detail_noise.get_noise_3d(nx * 1000.0, ny * 1000.0, nz * 1000.0) + 1.0) * 0.5
		h = h * 0.88 + detail * 0.12

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


func _type_to_key(pt: PlanetData.PlanetType) -> String:
	match pt:
		PlanetData.PlanetType.ROCKY: return "rocky"
		PlanetData.PlanetType.LAVA: return "lava"
		PlanetData.PlanetType.OCEAN: return "ocean"
		PlanetData.PlanetType.ICE: return "ice"
		PlanetData.PlanetType.GAS_GIANT: return "gas_giant"
	return "rocky"
