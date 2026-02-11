class_name VegetationScatter
extends Node3D

# =============================================================================
# Vegetation Scatter — Cell-based procedural vegetation placement.
# Mirrors the AsteroidFieldManager pattern: cells load/unload around the camera.
# Uses lat/lon grid on the sphere for deterministic, seamless cell placement.
# Child of PlanetBody — gets floating origin shift automatically.
# =============================================================================

const CELL_SIZE: float = 500.0
const LOAD_RADIUS: float = 2500.0
const UNLOAD_RADIUS: float = 3500.0
const EVAL_INTERVAL: float = 0.5
const MAX_CELLS: int = 80
const ALTITUDE_MAX: float = 5000.0

var _biome_gen: BiomeGenerator = null
var _heightmap: HeightmapGenerator = null
var _planet_radius: float = 50000.0
var _ocean_level: float = 0.0
var _planet_seed: int = 0
var _angular_cell: float = 0.01  # radians

var _loaded_cells: Dictionary = {}  # Vector2i -> VegetationCell (or null = empty)
var _eval_timer: float = 0.0
var _active: bool = false

# Biome vegetation recipes: { Biome -> { VegType -> base_count } }
# Counts are per 500m cell at full density. Trees/bushes/grass scale with
# VEGETATION_DENSITY; rocks use a fixed count.
var _VT := VegetationMeshLib.VegType


func setup(biome_gen: BiomeGenerator, heightmap: HeightmapGenerator,
		radius: float, ocean_level: float, seed_val: int) -> void:
	_biome_gen = biome_gen
	_heightmap = heightmap
	_planet_radius = radius
	_ocean_level = ocean_level
	_planet_seed = seed_val
	_angular_cell = CELL_SIZE / radius


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if not active:
		_clear_all()


func _process(delta: float) -> void:
	if not _active:
		return
	_eval_timer += delta
	if _eval_timer < EVAL_INTERVAL:
		return
	_eval_timer = 0.0
	_evaluate_cells()


# =========================================================================
# Cell evaluation
# =========================================================================

func _evaluate_cells() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var planet_center: Vector3 = get_parent().global_position
	var cam_pos := cam.global_position
	var to_cam := cam_pos - planet_center
	var dist := to_cam.length()
	var altitude := dist - _planet_radius

	if altitude > ALTITUDE_MAX:
		if not _loaded_cells.is_empty():
			_clear_all()
		return

	# Player sphere point & lat/lon
	var sp := to_cam.normalized()
	var lat := asin(clampf(sp.y, -1.0, 1.0))
	var lon := atan2(sp.z, sp.x)
	var pcell_lat := floori(lat / _angular_cell)
	var pcell_lon := floori(lon / _angular_cell)

	# Angular load radius
	var ang_load := LOAD_RADIUS / _planet_radius
	var range_lat := ceili(ang_load / _angular_cell)
	var range_lon := ceili(ang_load / (_angular_cell * maxf(cos(lat), 0.1)))

	# Desired cells
	var desired: Dictionary = {}
	for clat in range(pcell_lat - range_lat, pcell_lat + range_lat + 1):
		for clon in range(pcell_lon - range_lon, pcell_lon + range_lon + 1):
			var cell_sp := _cell_sphere_point(clat, clon)
			var ang_dist := acos(clampf(sp.dot(cell_sp), -1.0, 1.0))
			if ang_dist * _planet_radius <= LOAD_RADIUS:
				desired[Vector2i(clat, clon)] = cell_sp

	# Unload distant cells (hysteresis)
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _loaded_cells:
		if desired.has(key):
			continue
		var cell_sp := _cell_sphere_point(key.x, key.y)
		var ang_dist := acos(clampf(sp.dot(cell_sp), -1.0, 1.0))
		if ang_dist * _planet_radius > UNLOAD_RADIUS:
			to_remove.append(key)
	for key in to_remove:
		_unload_cell(key)

	# Load new cells
	for key: Vector2i in desired:
		if _loaded_cells.size() >= MAX_CELLS:
			break
		if not _loaded_cells.has(key):
			_load_cell(key, desired[key])


# =========================================================================
# Cell loading
# =========================================================================

func _load_cell(key: Vector2i, cell_sp: Vector3) -> void:
	var height := _heightmap.get_height(cell_sp)
	var biome: int = _biome_gen.get_biome(cell_sp, height)
	var recipe := _get_recipe(biome)
	if recipe.is_empty():
		_loaded_cells[key] = null
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_cell(key.x, key.y)
	var cell_surface := cell_sp * _planet_radius * (1.0 + height)

	var instances: Dictionary = {}  # VegType -> Array[Transform3D]
	for vtype: int in recipe:
		var count: int = recipe[vtype]
		var xforms: Array[Transform3D] = []
		for _i in count:
			var t := _make_instance(key, cell_sp, cell_surface, rng, vtype)
			if t != Transform3D.IDENTITY:
				xforms.append(t)
		if not xforms.is_empty():
			instances[vtype] = xforms

	if instances.is_empty():
		_loaded_cells[key] = null
		return

	var cell := VegetationCell.new()
	cell.cell_key = key
	cell.position = cell_surface
	add_child(cell)
	cell.populate(instances)
	_loaded_cells[key] = cell


func _make_instance(cell_key: Vector2i, cell_sp: Vector3, cell_surface: Vector3,
		rng: RandomNumberGenerator, vtype: int) -> Transform3D:
	var off_lat := rng.randf_range(-0.5, 0.5) * _angular_cell
	var off_lon := rng.randf_range(-0.5, 0.5) * _angular_cell
	var lat := (cell_key.x + 0.5) * _angular_cell + off_lat
	var lon := (cell_key.y + 0.5) * _angular_cell + off_lon
	var sp := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var height := _heightmap.get_height(sp)

	# Reject underwater
	if _ocean_level > 0.001 and height < _ocean_level + 0.0005:
		return Transform3D.IDENTITY

	var surface_pos := sp * _planet_radius * (1.0 + height)
	var local_pos := surface_pos - cell_surface

	# Basis: up = sphere normal, random Y rotation, random scale
	var up := sp
	var right := up.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = up.cross(Vector3.FORWARD).normalized()
	var forward := right.cross(up)
	var basis := Basis(right, up, forward)
	basis = basis * Basis(Vector3.UP, rng.randf() * TAU)

	# Scale: trees/palms larger variance, grass/rocks less
	var s_min := 0.6
	var s_max := 1.4
	if vtype == _VT.GRASS:
		s_min = 0.5; s_max = 1.2
	elif vtype == _VT.ROCK:
		s_min = 0.4; s_max = 2.5
	var s := rng.randf_range(s_min, s_max)
	basis = basis.scaled(Vector3(s, s, s))

	return Transform3D(basis, local_pos)


# =========================================================================
# Biome recipes
# =========================================================================

func _get_recipe(biome: int) -> Dictionary:
	var d: float = BiomeTypes.VEGETATION_DENSITY.get(biome, 0.0)
	var r: Dictionary = {}
	match biome:
		BiomeTypes.Biome.FOREST:
			r = { _VT.CONIFER: int(6 * d), _VT.BROADLEAF: int(6 * d),
				_VT.BUSH: int(8 * d), _VT.GRASS: int(22 * d), _VT.ROCK: 1 }
		BiomeTypes.Biome.RAINFOREST:
			r = { _VT.BROADLEAF: int(8 * d), _VT.PALM: int(4 * d),
				_VT.BUSH: int(10 * d), _VT.GRASS: int(28 * d) }
		BiomeTypes.Biome.TAIGA:
			r = { _VT.CONIFER: int(10 * d), _VT.BUSH: int(4 * d), _VT.ROCK: 2 }
		BiomeTypes.Biome.GRASSLAND:
			r = { _VT.BROADLEAF: int(4 * d), _VT.BUSH: int(6 * d),
				_VT.GRASS: int(30 * d), _VT.ROCK: 1 }
		BiomeTypes.Biome.SAVANNA:
			r = { _VT.BROADLEAF: int(3 * d), _VT.BUSH: int(4 * d),
				_VT.GRASS: int(18 * d), _VT.ROCK: 2 }
		BiomeTypes.Biome.BEACH:
			r = { _VT.PALM: 2, _VT.BUSH: 1, _VT.ROCK: 2 }
		BiomeTypes.Biome.TUNDRA:
			r = { _VT.BUSH: int(4 * d), _VT.ROCK: 3 }
		BiomeTypes.Biome.MOUNTAIN:
			r = { _VT.CONIFER: int(4 * d), _VT.ROCK: 4 }
		BiomeTypes.Biome.DESERT:
			r = { _VT.ROCK: 3 }
		BiomeTypes.Biome.SNOW:
			r = { _VT.ROCK: 2 }
		BiomeTypes.Biome.VOLCANIC:
			r = { _VT.ROCK: 4 }
	# Remove zero-count entries
	var clean: Dictionary = {}
	for k: int in r:
		if r[k] > 0:
			clean[k] = r[k]
	return clean


# =========================================================================
# Cleanup
# =========================================================================

func _unload_cell(key: Vector2i) -> void:
	var cell = _loaded_cells.get(key)
	if cell is VegetationCell and is_instance_valid(cell):
		cell.queue_free()
	_loaded_cells.erase(key)


func _clear_all() -> void:
	for key: Vector2i in _loaded_cells:
		var cell = _loaded_cells[key]
		if cell is VegetationCell and is_instance_valid(cell):
			cell.queue_free()
	_loaded_cells.clear()


# =========================================================================
# Helpers
# =========================================================================

func _cell_sphere_point(clat: int, clon: int) -> Vector3:
	var la := (clat + 0.5) * _angular_cell
	var lo := (clon + 0.5) * _angular_cell
	return Vector3(cos(la) * cos(lo), sin(la), cos(la) * sin(lo))


func _hash_cell(clat: int, clon: int) -> int:
	return _planet_seed * 73856093 + clat * 19349669 + clon * 83492791
