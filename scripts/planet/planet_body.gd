class_name PlanetBody
extends Node3D

# =============================================================================
# Planet Body — Main planet node with 6 quadtree faces + atmosphere
# Child of Universe node (gets shifted by FloatingOrigin automatically).
# Position tracked in float64 via EntityRegistry.
# =============================================================================

const MAX_TOTAL_CHUNKS: int = 300
const UPDATE_INTERVAL: float = 0.2  # 5 Hz quadtree updates

var planet_data: PlanetData = null
var planet_index: int = 0
var planet_radius: float = 50_000.0
var entity_id: String = ""  # EntityRegistry key, e.g. "planet_0"

# True universe position (float64) — planet center (initial, updated from EntityRegistry)
var true_pos_x: float = 0.0
var true_pos_y: float = 0.0
var true_pos_z: float = 0.0

var _faces: Array[QuadtreeFace] = []
var _heightmap: HeightmapGenerator = null
var _terrain_material: ShaderMaterial = null
var _atmo_mesh: MeshInstance3D = null
var _update_timer: float = 0.0
var _is_active: bool = false


func setup(pd: PlanetData, index: int, pos_x: float, pos_y: float, pos_z: float, system_seed: int) -> void:
	planet_data = pd
	planet_index = index
	true_pos_x = pos_x
	true_pos_y = pos_y
	true_pos_z = pos_z
	planet_radius = pd.get_render_radius()

	# Derive terrain seed
	var terrain_seed: int = pd.terrain_seed if pd.terrain_seed != 0 else (system_seed * 1000 + index * 137)

	# Setup heightmap generator
	_heightmap = HeightmapGenerator.new()
	_heightmap.setup(terrain_seed, pd.type, pd.get_terrain_amplitude(), pd.ocean_level)

	# Create terrain material (factory-based)
	_terrain_material = TerrainMaterialFactory.create_basic(pd, planet_radius)

	# Create 6 quadtree faces
	_faces.resize(6)
	for f in 6:
		var face := QuadtreeFace.new()
		face.setup(f, planet_radius, _heightmap, _terrain_material, self)
		_faces[f] = face

	# Create atmosphere mesh
	_create_atmosphere(pd)


func activate() -> void:
	_is_active = true
	visible = true


func deactivate() -> void:
	_is_active = false
	visible = false
	# Free all chunks to save memory
	for face in _faces:
		face.free_all()


func _process(delta: float) -> void:
	if not _is_active:
		return

	# Read current orbital position from EntityRegistry (single source of truth)
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

	# Throttled quadtree update
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	_update_quadtrees(cam.global_position)


func _update_quadtrees(cam_pos: Vector3) -> void:
	var planet_center := global_position
	var total_chunks: int = 0

	for face in _faces:
		var count: int = face.update(cam_pos, planet_center)
		total_chunks += count

	# Budget enforcement: if over MAX_TOTAL_CHUNKS, reduce quality
	# (In practice the quadtree thresholds should prevent this)
	if total_chunks > MAX_TOTAL_CHUNKS:
		push_warning("PlanetBody: %d chunks exceeds budget %d" % [total_chunks, MAX_TOTAL_CHUNKS])


func _create_atmosphere(pd: PlanetData) -> void:
	var atmo_cfg := AtmosphereConfig.from_planet_data(pd)
	if atmo_cfg.density < 0.01:
		return

	var atmo_mesh := SphereMesh.new()
	var atmo_radius: float = planet_radius * atmo_cfg.atmosphere_scale
	atmo_mesh.radius = atmo_radius
	atmo_mesh.height = atmo_radius * 2.0
	atmo_mesh.radial_segments = 48
	atmo_mesh.rings = 24

	var atmo_shader := preload("res://shaders/planet/planet_atmosphere.gdshader")
	var atmo_mat := ShaderMaterial.new()
	atmo_mat.shader = atmo_shader
	atmo_mat.set_shader_parameter("glow_color", atmo_cfg.glow_color)
	atmo_mat.set_shader_parameter("glow_intensity", atmo_cfg.glow_intensity)
	atmo_mat.set_shader_parameter("glow_falloff", atmo_cfg.glow_falloff)
	atmo_mat.set_shader_parameter("atmosphere_density", atmo_cfg.density)

	_atmo_mesh = MeshInstance3D.new()
	_atmo_mesh.mesh = atmo_mesh
	_atmo_mesh.material_override = atmo_mat
	_atmo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmo_mesh)


## Get the distance from a world position to the planet surface (negative = inside).
func get_altitude(world_pos: Vector3) -> float:
	var to_center: Vector3 = world_pos - global_position
	var dist: float = to_center.length()
	# Approximate surface height: radius + average terrain
	var surface_radius: float = planet_radius * (1.0 + planet_data.get_terrain_amplitude() * 0.5)
	return dist - surface_radius


## Get the center direction from a world position (gravity direction = -result).
func get_center_direction(world_pos: Vector3) -> Vector3:
	return (global_position - world_pos).normalized()


## Free all resources.
func cleanup() -> void:
	for face in _faces:
		face.free_all()
	_faces.clear()
