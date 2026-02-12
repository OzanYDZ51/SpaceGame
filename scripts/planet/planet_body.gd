class_name PlanetBody
extends Node3D

# =============================================================================
# Planet Body — Main planet node with terrain, ocean, clouds, atmosphere.
# Child of Universe node (gets shifted by FloatingOrigin automatically).
# Position tracked in float64 via EntityRegistry.
# Orchestrates all visual subsystems for a single planet.
# =============================================================================

const MAX_TOTAL_CHUNKS: int = 800
const UPDATE_INTERVAL: float = 0.0625  # 16 Hz quadtree updates
const GLOBAL_REBUILD_BUDGET: int = 12  # Total mesh rebuilds across all 6 faces per update

var planet_data: PlanetData = null
var planet_index: int = 0
var planet_radius: float = 50_000.0
var entity_id: String = ""  # EntityRegistry key, e.g. "planet_0"

# True universe position (float64) — planet center
var true_pos_x: float = 0.0
var true_pos_y: float = 0.0
var true_pos_z: float = 0.0

# Subsystems
var _faces: Array[QuadtreeFace] = []
var _heightmap: HeightmapGenerator = null
var _biome_gen: BiomeGenerator = null
var _terrain_material: ShaderMaterial = null
var _ocean: OceanRenderer = null
var _cloud_layer: CloudLayer = null
var _atmo_renderer: AtmosphereRenderer = null
var _vegetation: VegetationScatter = null
var _city_lights: CityLightsLayer = null
var _cached_atmo_config: AtmosphereConfig = null

var _update_timer: float = 0.0
var _is_active: bool = false
var _last_total_chunks: int = 0  # Previous frame's chunk count for budget enforcement


func setup(pd: PlanetData, index: int, pos_x: float, pos_y: float, pos_z: float, system_seed: int) -> void:
	planet_data = pd
	planet_index = index
	true_pos_x = pos_x
	true_pos_y = pos_y
	true_pos_z = pos_z
	planet_radius = pd.get_render_radius()

	# Derive terrain seed
	var terrain_seed: int = pd.terrain_seed if pd.terrain_seed != 0 else (system_seed * 1000 + index * 137)

	# Heightmap generator
	_heightmap = HeightmapGenerator.new()
	_heightmap.setup(terrain_seed, pd.type, pd.get_terrain_amplitude(), pd.ocean_level)

	# Biome generator (same seed family, amplitude needed for height normalization)
	_biome_gen = BiomeGenerator.new()
	_biome_gen.setup(terrain_seed, pd.type, pd.ocean_level, pd.get_terrain_amplitude())

	# Terrain material — use splatmap with biome data
	_terrain_material = TerrainMaterialFactory.create_biome_splatmap(pd, planet_radius, terrain_seed)

	# 6 quadtree faces
	_faces.resize(6)
	for f in 6:
		var face := QuadtreeFace.new()
		face.setup(f, planet_radius, _heightmap, _terrain_material, self)
		_faces[f] = face

	# Atmosphere mesh
	_create_atmosphere(pd)

	# Cloud layer
	_create_clouds(pd)

	# Ocean
	_create_ocean(pd)

	# Vegetation scatter (landable planets only, not gas giants/lava)
	_create_vegetation(pd, terrain_seed)

	# City lights (civilization planets only)
	_create_city_lights(pd, terrain_seed)


func activate() -> void:
	_is_active = true
	visible = true


## Fully deactivate (hides + frees resources). Called after despawn fade completes.
func deactivate() -> void:
	_is_active = false
	visible = false
	for face in _faces:
		face.free_all()
	if _vegetation:
		_vegetation.set_active(false)


## Soft deactivate: stop expensive processing but KEEP VISIBLE for crossfade.
## Called when starting DESPAWNING_BODY — the body stays visible while the
## impostor fades in, then deactivate() + queue_free() when fade completes.
func deactivate_soft() -> void:
	_is_active = false
	# visible stays true — LOD manager will free us after impostor fade-in completes
	if _vegetation:
		_vegetation.set_active(false)


func _process(delta: float) -> void:
	if not _is_active:
		return

	# Read current orbital position from EntityRegistry
	if entity_id != "":
		var pos: Array = EntityRegistry.get_position(entity_id)
		true_pos_x = pos[0]
		true_pos_y = pos[1]
		true_pos_z = pos[2]

	# Update position based on floating origin
	global_position = Vector3(
		float(true_pos_x) - float(FloatingOrigin.origin_offset_x),
		float(true_pos_y) - float(FloatingOrigin.origin_offset_y),
		float(true_pos_z) - float(FloatingOrigin.origin_offset_z)
	)

	# Axial rotation — disabled

	# Sun direction (star at universe origin) — world space for shaders
	var star_local := Vector3(
		-float(FloatingOrigin.origin_offset_x),
		-float(FloatingOrigin.origin_offset_y),
		-float(FloatingOrigin.origin_offset_z)
	)
	var sun_dir := (star_local - global_position).normalized()

	# Update atmosphere sun direction
	if _atmo_renderer:
		_atmo_renderer.update_sun_direction(sun_dir)

	# Update cloud sun direction
	if _cloud_layer:
		_cloud_layer.update_sun_direction(sun_dir)

	# Update city lights sun direction
	if _city_lights:
		_city_lights.update_sun_direction(sun_dir)

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# Transform camera into planet's local (unrotated) space for LOD calculations.
	# Quadtree chunks are in local space — their centers are at center_sphere * radius
	# relative to the planet origin. By working in local space, rotation doesn't break
	# distance-based LOD decisions.
	var local_cam: Vector3 = to_local(cam.global_position)

	# Smooth geo-morph factor update every frame (not throttled)
	for face in _faces:
		face.update_morph_factors(local_cam, Vector3.ZERO)

	# Throttled quadtree update (split/merge + mesh rebuilds)
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	_update_quadtrees(local_cam)


## cam_pos is in planet-local space (rotation removed). planet_center = Vector3.ZERO.
func _update_quadtrees(cam_pos: Vector3) -> void:
	var total_chunks: int = 0

	# Distribute global rebuild budget evenly across faces (2 per face by default)
	var per_face: int = maxi(1, int(GLOBAL_REBUILD_BUDGET / 6.0))
	for face in _faces:
		face.max_rebuilds_per_frame = per_face

	# Hard budget enforcement: disable splitting if last frame exceeded budget.
	# Merging still runs, so count will decrease until budget is respected again.
	var allow_split: bool = _last_total_chunks < MAX_TOTAL_CHUNKS

	for face in _faces:
		var count: int = face.update(cam_pos, Vector3.ZERO, allow_split)
		total_chunks += count

	_last_total_chunks = total_chunks

	# Altitude: distance from local origin minus radius (rotation-invariant)
	var altitude: float = cam_pos.length() - planet_radius

	# Vegetation: activate below 5km altitude
	if _vegetation:
		_vegetation.set_active(altitude < 5000.0)

	# Terrain collision: enable trimesh on nearby chunks when close to surface
	# Budget: max 2 total collision shapes per update (trimesh creation is expensive)
	if altitude < 10000.0:
		var col_budget: int = 2
		for face in _faces:
			if col_budget <= 0:
				break
			col_budget -= face.update_collision(cam_pos, Vector3.ZERO, col_budget)


# =========================================================================
# Subsystem creation
# =========================================================================

func _create_atmosphere(pd: PlanetData) -> void:
	var atmo_cfg := AtmosphereConfig.from_planet_data(pd)
	if atmo_cfg.density < 0.01:
		return
	_atmo_renderer = AtmosphereRenderer.new()
	_atmo_renderer.setup(planet_radius, atmo_cfg)
	add_child(_atmo_renderer)


func _create_clouds(pd: PlanetData) -> void:
	var atmo_cfg := AtmosphereConfig.from_planet_data(pd)
	if pd.type == PlanetData.PlanetType.GAS_GIANT:
		return  # Gas giants have no distinct cloud layer
	_cloud_layer = CloudLayer.new()
	_cloud_layer.setup(planet_radius, atmo_cfg)
	add_child(_cloud_layer)


func _create_ocean(pd: PlanetData) -> void:
	if pd.ocean_level < 0.001:
		return
	if pd.type == PlanetData.PlanetType.GAS_GIANT:
		return
	_ocean = OceanRenderer.new()
	_ocean.setup(planet_radius, pd)
	add_child(_ocean)


func _create_vegetation(pd: PlanetData, terrain_seed: int) -> void:
	# No vegetation on gas giants or lava planets
	if pd.type in [PlanetData.PlanetType.GAS_GIANT, PlanetData.PlanetType.LAVA]:
		return
	_vegetation = VegetationScatter.new()
	_vegetation.name = "VegetationScatter"
	_vegetation.setup(_biome_gen, _heightmap, planet_radius, pd.ocean_level, terrain_seed)
	add_child(_vegetation)


func _create_city_lights(pd: PlanetData, terrain_seed: int) -> void:
	if not pd.has_civilization:
		return
	if pd.type == PlanetData.PlanetType.GAS_GIANT:
		return
	_city_lights = CityLightsLayer.new()
	_city_lights.name = "CityLights"
	_city_lights.setup(planet_radius, terrain_seed)
	add_child(_city_lights)


# =========================================================================
# Public API
# =========================================================================

## Get the distance from a world position to the planet surface (negative = inside).
## Uses actual heightmap terrain height at the ship's position for accuracy.
func get_altitude(world_pos: Vector3) -> float:
	var to_center: Vector3 = world_pos - global_position
	var dist: float = to_center.length()
	if dist < 0.01:
		return 0.0
	# Sample actual terrain height at this direction on the sphere
	var sphere_point: Vector3 = to_center / dist  # Unit sphere direction
	var terrain_h: float = 0.0
	if _heightmap:
		terrain_h = _heightmap.get_height(sphere_point)
	var surface_radius: float = planet_radius * (1.0 + terrain_h)
	return dist - surface_radius


## Get the center direction from a world position (gravity direction = -result).
func get_center_direction(world_pos: Vector3) -> Vector3:
	return (global_position - world_pos).normalized()


## Get atmosphere config for this planet (cached — no allocation per call).
func get_atmosphere_config() -> AtmosphereConfig:
	if _cached_atmo_config == null and planet_data:
		_cached_atmo_config = AtmosphereConfig.from_planet_data(planet_data)
	return _cached_atmo_config


## Free all resources.
func cleanup() -> void:
	if _vegetation:
		_vegetation.set_active(false)
	for face in _faces:
		face.free_all()
	_faces.clear()
