class_name TerrainChunk
extends MeshInstance3D

# =============================================================================
# Terrain Chunk — MeshInstance3D wrapper for a single quadtree tile
# Manages its own mesh lifecycle. Created by QuadtreeNode.
# =============================================================================

var face: int = 0
var depth: int = 0
var uv_min: Vector2 = Vector2(-1, -1)
var uv_max: Vector2 = Vector2(1, 1)
var chunk_center: Vector3 = Vector3.ZERO  # Center on unit sphere (for distance calc)
var chunk_size: float = 2.0               # Angular size in UV space

var _is_built: bool = false
var _col_body: StaticBody3D = null


func setup(p_face: int, p_depth: int, p_uv_min: Vector2, p_uv_max: Vector2) -> void:
	face = p_face
	depth = p_depth
	uv_min = p_uv_min
	uv_max = p_uv_max
	chunk_size = maxf(uv_max.x - uv_min.x, uv_max.y - uv_min.y)

	# Compute center on unit sphere
	var center_u: float = (uv_min.x + uv_max.x) * 0.5
	var center_v: float = (uv_min.y + uv_max.y) * 0.5
	chunk_center = CubeSphere.cube_to_sphere(face, center_u, center_v)

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Build the mesh (call from main thread only — SurfaceTool is not thread-safe).
func build_mesh(planet_radius: float, heightmap: HeightmapGenerator, material: Material) -> void:
	mesh = TerrainMeshBuilder.build_chunk(face, uv_min, uv_max, planet_radius, heightmap)
	material_override = material
	_is_built = true


func is_built() -> bool:
	return _is_built


## Set geo-morph factor via instance shader parameter (no material duplication needed).
## 0.0 = coarse (looks like parent LOD), 1.0 = full detail.
func set_morph_factor(value: float) -> void:
	set_instance_shader_parameter("morph_factor", value)


## Create a trimesh collision shape from the terrain mesh.
## The ConcavePolygonShape3D exactly follows the terrain surface (mountains, valleys).
func enable_collision() -> void:
	if _col_body or not _is_built or mesh == null:
		return
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return
	_col_body = StaticBody3D.new()
	_col_body.collision_layer = Constants.LAYER_TERRAIN
	_col_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_col_body.add_child(cs)
	add_child(_col_body)


func disable_collision() -> void:
	if _col_body:
		_col_body.queue_free()
		_col_body = null


func has_collision() -> bool:
	return _col_body != null
