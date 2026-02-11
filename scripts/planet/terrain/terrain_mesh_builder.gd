class_name TerrainMeshBuilder
extends RefCounted

# =============================================================================
# Terrain Mesh Builder — Generates ArrayMesh for a single quadtree chunk
# Uses SurfaceTool to build a GRID_SIZE x GRID_SIZE vertex grid projected
# onto the sphere surface with heightmap displacement.
#
# GEO-MORPHING: Each vertex stores a morph delta in CUSTOM0 (RGBA_FLOAT).
# Even-indexed vertices (shared with parent LOD) have delta = (0,0,0).
# Odd-indexed vertices (new at this LOD) store the offset from the coarse
# interpolated position. The shader uses morph_factor to blend:
#   VERTEX -= delta * (1.0 - morph_factor)
# morph_factor=0 → coarse (parent appearance), morph_factor=1 → full detail.
# =============================================================================

const GRID_SIZE: int = 25  # 25x25 vertices = 24x24 quads
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
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

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

	# --- Geo-morph deltas ---
	# Even-indexed vertices are shared with the parent LOD → delta = 0.
	# Odd-indexed vertices are new at this LOD → delta = true_pos - coarse_pos
	# where coarse_pos is the bilinear interpolation of even neighbors.
	var morph_deltas := PackedVector3Array()
	morph_deltas.resize(GRID_SIZE * GRID_SIZE)

	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var even_x: bool = (gx & 1) == 0
			var even_y: bool = (gy & 1) == 0

			if even_x and even_y:
				# Shared with parent LOD — no morph needed
				morph_deltas[idx] = Vector3.ZERO
			elif not even_x and even_y:
				# Interpolate from left/right even neighbors
				var left_pos: Vector3 = vertices[gy * GRID_SIZE + (gx - 1)]
				var right_pos: Vector3 = vertices[gy * GRID_SIZE + (gx + 1)]
				morph_deltas[idx] = vertices[idx] - (left_pos + right_pos) * 0.5
			elif even_x and not even_y:
				# Interpolate from top/bottom even neighbors
				var up_pos: Vector3 = vertices[(gy - 1) * GRID_SIZE + gx]
				var down_pos: Vector3 = vertices[(gy + 1) * GRID_SIZE + gx]
				morph_deltas[idx] = vertices[idx] - (up_pos + down_pos) * 0.5
			else:
				# Interpolate from 4 diagonal even neighbors
				var tl: Vector3 = vertices[(gy - 1) * GRID_SIZE + (gx - 1)]
				var tr: Vector3 = vertices[(gy - 1) * GRID_SIZE + (gx + 1)]
				var bl: Vector3 = vertices[(gy + 1) * GRID_SIZE + (gx - 1)]
				var br: Vector3 = vertices[(gy + 1) * GRID_SIZE + (gx + 1)]
				morph_deltas[idx] = vertices[idx] - (tl + tr + bl + br) * 0.25

	# Build triangles
	for gy in GRID_SIZE - 1:
		for gx in GRID_SIZE - 1:
			var i00: int = gy * GRID_SIZE + gx
			var i10: int = i00 + 1
			var i01: int = i00 + GRID_SIZE
			var i11: int = i01 + 1

			# Triangle 1
			_add_vertex(st, vertices[i00], normals_arr[i00], uvs[i00], morph_deltas[i00])
			_add_vertex(st, vertices[i01], normals_arr[i01], uvs[i01], morph_deltas[i01])
			_add_vertex(st, vertices[i10], normals_arr[i10], uvs[i10], morph_deltas[i10])

			# Triangle 2
			_add_vertex(st, vertices[i10], normals_arr[i10], uvs[i10], morph_deltas[i10])
			_add_vertex(st, vertices[i01], normals_arr[i01], uvs[i01], morph_deltas[i01])
			_add_vertex(st, vertices[i11], normals_arr[i11], uvs[i11], morph_deltas[i11])

	# Skirt: extra triangles hanging down on all 4 edges (hides seams between LODs)
	if include_skirt:
		var skirt_drop: float = planet_radius * SKIRT_DEPTH
		_add_skirt_edge(st, vertices, normals_arr, uvs, morph_deltas, skirt_drop, true, true)   # top
		_add_skirt_edge(st, vertices, normals_arr, uvs, morph_deltas, skirt_drop, true, false)  # bottom
		_add_skirt_edge(st, vertices, normals_arr, uvs, morph_deltas, skirt_drop, false, true)  # left
		_add_skirt_edge(st, vertices, normals_arr, uvs, morph_deltas, skirt_drop, false, false) # right

	st.generate_tangents()
	return st.commit()


## Helper: add a single vertex with all attributes including morph delta.
static func _add_vertex(st: SurfaceTool, pos: Vector3, normal: Vector3, uv: Vector2, delta: Vector3) -> void:
	st.set_uv(uv)
	st.set_normal(normal)
	st.set_custom(0, Color(delta.x, delta.y, delta.z, 0.0))
	st.add_vertex(pos)


static func _add_skirt_edge(
	st: SurfaceTool,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	morph_deltas: PackedVector3Array,
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
		var md0: Vector3 = morph_deltas[idx0]
		var md1: Vector3 = morph_deltas[idx1]

		# Drop vertices toward planet center
		var v0_drop: Vector3 = v0 - v0.normalized() * drop
		var v1_drop: Vector3 = v1 - v1.normalized() * drop

		# Two triangles per segment — skirt vertices share morph delta with source edge vertex
		_add_vertex(st, v0, n0, uv0, md0)
		_add_vertex(st, v0_drop, n0, uv0, md0)
		_add_vertex(st, v1, n1, uv1, md1)

		_add_vertex(st, v1, n1, uv1, md1)
		_add_vertex(st, v0_drop, n0, uv0, md0)
		_add_vertex(st, v1_drop, n1, uv1, md1)
