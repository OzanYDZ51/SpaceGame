class_name TerrainMeshBuilder
extends RefCounted

# =============================================================================
# Terrain Mesh Builder — Generates ArrayMesh for a single quadtree chunk
# Uses SurfaceTool to build a GRID_SIZE x GRID_SIZE vertex grid projected
# onto the sphere surface with heightmap displacement.
# =============================================================================

const GRID_SIZE: int = 17  # 17x17 vertices = 16x16 quads
const SKIRT_DEPTH: float = 0.005  # Fraction of planet radius (hides seams)


## Build a terrain chunk mesh for a given face region.
## uv_min/uv_max define the region on the cube face in [-1, 1] range.
## Returns an ArrayMesh ready for MeshInstance3D.
static func build_chunk(
	face: int,
	uv_min: Vector2,
	uv_max: Vector2,
	planet_radius: float,
	heightmap: HeightmapGenerator,
	include_skirt: bool = true
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := Vector2(
		(uv_max.x - uv_min.x) / float(GRID_SIZE - 1),
		(uv_max.y - uv_min.y) / float(GRID_SIZE - 1),
	)

	# Generate vertex grid
	var vertices := PackedVector3Array()
	var normals_arr := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(GRID_SIZE * GRID_SIZE)
	normals_arr.resize(GRID_SIZE * GRID_SIZE)
	uvs.resize(GRID_SIZE * GRID_SIZE)

	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var u: float = uv_min.x + float(gx) * step.x
			var v: float = uv_min.y + float(gy) * step.y
			var sphere_pt: Vector3 = CubeSphere.cube_to_sphere(face, u, v)
			var h: float = heightmap.get_height(sphere_pt)
			var pos: Vector3 = sphere_pt * (planet_radius * (1.0 + h))
			vertices[idx] = pos
			normals_arr[idx] = sphere_pt  # Will recompute after
			uvs[idx] = Vector2(float(gx) / float(GRID_SIZE - 1), float(gy) / float(GRID_SIZE - 1))

	# Compute smooth normals from cross products of neighbors
	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var p: Vector3 = vertices[idx]
			var right: Vector3 = vertices[mini(idx + 1, gy * GRID_SIZE + GRID_SIZE - 1)] if gx < GRID_SIZE - 1 else p
			var left: Vector3 = vertices[maxi(idx - 1, gy * GRID_SIZE)] if gx > 0 else p
			var down: Vector3 = vertices[mini((gy + 1) * GRID_SIZE + gx, (GRID_SIZE - 1) * GRID_SIZE + gx)] if gy < GRID_SIZE - 1 else p
			var up: Vector3 = vertices[maxi((gy - 1) * GRID_SIZE + gx, gx)] if gy > 0 else p
			var n: Vector3 = (right - left).cross(down - up)
			if n.length_squared() > 0.0001:
				normals_arr[idx] = n.normalized()

	# Build triangles
	for gy in GRID_SIZE - 1:
		for gx in GRID_SIZE - 1:
			var i00: int = gy * GRID_SIZE + gx
			var i10: int = i00 + 1
			var i01: int = i00 + GRID_SIZE
			var i11: int = i01 + 1

			# Triangle 1
			st.set_uv(uvs[i00])
			st.set_normal(normals_arr[i00])
			st.add_vertex(vertices[i00])

			st.set_uv(uvs[i01])
			st.set_normal(normals_arr[i01])
			st.add_vertex(vertices[i01])

			st.set_uv(uvs[i10])
			st.set_normal(normals_arr[i10])
			st.add_vertex(vertices[i10])

			# Triangle 2
			st.set_uv(uvs[i10])
			st.set_normal(normals_arr[i10])
			st.add_vertex(vertices[i10])

			st.set_uv(uvs[i01])
			st.set_normal(normals_arr[i01])
			st.add_vertex(vertices[i01])

			st.set_uv(uvs[i11])
			st.set_normal(normals_arr[i11])
			st.add_vertex(vertices[i11])

	# Skirt: extra triangles hanging down on all 4 edges (hides seams between LODs)
	if include_skirt:
		var skirt_drop: float = planet_radius * SKIRT_DEPTH
		_add_skirt_edge(st, vertices, normals_arr, uvs, skirt_drop, true, true)   # top
		_add_skirt_edge(st, vertices, normals_arr, uvs, skirt_drop, true, false)  # bottom
		_add_skirt_edge(st, vertices, normals_arr, uvs, skirt_drop, false, true)  # left
		_add_skirt_edge(st, vertices, normals_arr, uvs, skirt_drop, false, false) # right

	return st.commit()


static func _add_skirt_edge(
	st: SurfaceTool,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	drop: float,
	is_horizontal: bool,
	is_start: bool
) -> void:
	for i in GRID_SIZE - 1:
		var idx0: int
		var idx1: int

		if is_horizontal:
			var row: int = 0 if is_start else (GRID_SIZE - 1)
			idx0 = row * GRID_SIZE + i
			idx1 = row * GRID_SIZE + i + 1
		else:
			var col: int = 0 if is_start else (GRID_SIZE - 1)
			idx0 = i * GRID_SIZE + col
			idx1 = (i + 1) * GRID_SIZE + col

		var v0: Vector3 = vertices[idx0]
		var v1: Vector3 = vertices[idx1]
		var n0: Vector3 = normals[idx0]
		var n1: Vector3 = normals[idx1]
		var uv0: Vector2 = uvs[idx0]
		var uv1: Vector2 = uvs[idx1]

		# Drop vertices toward planet center
		var v0_drop: Vector3 = v0 - v0.normalized() * drop
		var v1_drop: Vector3 = v1 - v1.normalized() * drop

		# Two triangles per segment
		st.set_uv(uv0); st.set_normal(n0); st.add_vertex(v0)
		st.set_uv(uv0); st.set_normal(n0); st.add_vertex(v0_drop)
		st.set_uv(uv1); st.set_normal(n1); st.add_vertex(v1)

		st.set_uv(uv1); st.set_normal(n1); st.add_vertex(v1)
		st.set_uv(uv0); st.set_normal(n0); st.add_vertex(v0_drop)
		st.set_uv(uv1); st.set_normal(n1); st.add_vertex(v1_drop)
