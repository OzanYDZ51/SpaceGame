class_name TerrainMeshBuilder
extends RefCounted

# =============================================================================
# Terrain Mesh Builder — Generates ArrayMesh for a single quadtree chunk
# Uses SurfaceTool with INDEXED geometry to build a GRID_SIZE x GRID_SIZE
# vertex grid projected onto the sphere surface with heightmap displacement.
# Indexed mesh shares vertices via indices: 1089 verts + indices vs 6144 verts.
#
# GEO-MORPHING: Each vertex stores morph deltas in two custom channels:
#   CUSTOM0 (RGBA_FLOAT) = position delta  (fine_pos - coarse_pos)
#   CUSTOM1 (RGBA_FLOAT) = normal delta    (fine_normal - coarse_normal)
# Even-indexed vertices (shared with parent LOD) have delta = (0,0,0).
# Odd-indexed vertices (new at this LOD) store the offset.
# The shader blends both position and normal:
#   VERTEX -= pos_delta * (1.0 - morph_factor)
#   NORMAL  = normalize(NORMAL - nrm_delta * (1.0 - morph_factor))
# morph_factor=0 → coarse (parent appearance), morph_factor=1 → full detail.
# =============================================================================

const GRID_SIZE: int = 33  # 33x33 vertices = 32x32 quads (must be odd for geo-morph)
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
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)

	var step := Vector2(
		(uv_max.x - uv_min.x) / float(GRID_SIZE - 1),
		(uv_max.y - uv_min.y) / float(GRID_SIZE - 1),
	)

	var count: int = GRID_SIZE * GRID_SIZE

	# Compute all sphere points first
	var sphere_points := PackedVector3Array()
	sphere_points.resize(count)
	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var u: float = uv_min.x + float(gx) * step.x
			var v: float = uv_min.y + float(gy) * step.y
			sphere_points[idx] = CubeSphere.cube_to_sphere(face, u, v)

	# Batch heightmap query (1089 points at once instead of individual calls)
	var heights := heightmap.get_heights(sphere_points)

	# Generate vertex grid
	var vertices := PackedVector3Array()
	var normals_arr := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(count)
	normals_arr.resize(count)
	uvs.resize(count)

	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var sphere_pt: Vector3 = sphere_points[idx]
			var h: float = heights[idx]
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

	# --- Geo-morph deltas (position + normal) ---
	# Even-indexed vertices are shared with the parent LOD -> delta = 0.
	# Odd-indexed vertices are new at this LOD -> delta = fine - coarse
	# where coarse = bilinear interpolation of even neighbors.
	var pos_deltas := PackedVector3Array()
	var nrm_deltas := PackedVector3Array()
	pos_deltas.resize(count)
	nrm_deltas.resize(count)

	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			var even_x: bool = (gx & 1) == 0
			var even_y: bool = (gy & 1) == 0

			if even_x and even_y:
				# Shared with parent LOD — no morph needed
				pos_deltas[idx] = Vector3.ZERO
				nrm_deltas[idx] = Vector3.ZERO
			elif not even_x and even_y:
				# Interpolate from left/right even neighbors
				var li: int = gy * GRID_SIZE + (gx - 1)
				var ri: int = gy * GRID_SIZE + (gx + 1)
				pos_deltas[idx] = vertices[idx] - (vertices[li] + vertices[ri]) * 0.5
				nrm_deltas[idx] = normals_arr[idx] - (normals_arr[li] + normals_arr[ri]).normalized()
			elif even_x and not even_y:
				# Interpolate from top/bottom even neighbors
				var ui: int = (gy - 1) * GRID_SIZE + gx
				var di: int = (gy + 1) * GRID_SIZE + gx
				pos_deltas[idx] = vertices[idx] - (vertices[ui] + vertices[di]) * 0.5
				nrm_deltas[idx] = normals_arr[idx] - (normals_arr[ui] + normals_arr[di]).normalized()
			else:
				# Interpolate from 4 diagonal even neighbors
				var tl: int = (gy - 1) * GRID_SIZE + (gx - 1)
				var top_r: int = (gy - 1) * GRID_SIZE + (gx + 1)
				var bl: int = (gy + 1) * GRID_SIZE + (gx - 1)
				var br: int = (gy + 1) * GRID_SIZE + (gx + 1)
				pos_deltas[idx] = vertices[idx] - (vertices[tl] + vertices[top_r] + vertices[bl] + vertices[br]) * 0.25
				nrm_deltas[idx] = normals_arr[idx] - (normals_arr[tl] + normals_arr[top_r] + normals_arr[bl] + normals_arr[br]).normalized()

	# Emit all grid vertices once (shared via indices — 1089 instead of 6144)
	for gy in GRID_SIZE:
		for gx in GRID_SIZE:
			var idx: int = gy * GRID_SIZE + gx
			_add_vertex(st, vertices[idx], normals_arr[idx], uvs[idx], pos_deltas[idx], nrm_deltas[idx])

	# Build triangle indices for main grid
	for gy in GRID_SIZE - 1:
		for gx in GRID_SIZE - 1:
			var i00: int = gy * GRID_SIZE + gx
			var i10: int = i00 + 1
			var i01: int = i00 + GRID_SIZE
			var i11: int = i01 + 1
			# Triangle 1
			st.add_index(i00)
			st.add_index(i01)
			st.add_index(i10)
			# Triangle 2
			st.add_index(i10)
			st.add_index(i01)
			st.add_index(i11)

	# Skirt: dropped edge vertices + indexed triangles (hides seams between LODs)
	if include_skirt:
		var skirt_drop: float = planet_radius * SKIRT_DEPTH
		var base_idx: int = count

		# Top edge (row=0)
		for gx in GRID_SIZE:
			var gi: int = gx
			var drop_pos: Vector3 = vertices[gi] - vertices[gi].normalized() * skirt_drop
			_add_vertex(st, drop_pos, normals_arr[gi], uvs[gi], pos_deltas[gi], nrm_deltas[gi])
		for gx in GRID_SIZE - 1:
			var e0: int = gx
			var e1: int = gx + 1
			var d0: int = base_idx + gx
			var d1: int = base_idx + gx + 1
			st.add_index(e0); st.add_index(d0); st.add_index(e1)
			st.add_index(e1); st.add_index(d0); st.add_index(d1)
		base_idx += GRID_SIZE

		# Bottom edge (row=GRID_SIZE-1)
		for gx in GRID_SIZE:
			var gi: int = (GRID_SIZE - 1) * GRID_SIZE + gx
			var drop_pos: Vector3 = vertices[gi] - vertices[gi].normalized() * skirt_drop
			_add_vertex(st, drop_pos, normals_arr[gi], uvs[gi], pos_deltas[gi], nrm_deltas[gi])
		for gx in GRID_SIZE - 1:
			var e0: int = (GRID_SIZE - 1) * GRID_SIZE + gx
			var e1: int = e0 + 1
			var d0: int = base_idx + gx
			var d1: int = base_idx + gx + 1
			st.add_index(e0); st.add_index(e1); st.add_index(d0)
			st.add_index(e1); st.add_index(d1); st.add_index(d0)
		base_idx += GRID_SIZE

		# Left edge (col=0)
		for gy in GRID_SIZE:
			var gi: int = gy * GRID_SIZE
			var drop_pos: Vector3 = vertices[gi] - vertices[gi].normalized() * skirt_drop
			_add_vertex(st, drop_pos, normals_arr[gi], uvs[gi], pos_deltas[gi], nrm_deltas[gi])
		for gy in GRID_SIZE - 1:
			var e0: int = gy * GRID_SIZE
			var e1: int = (gy + 1) * GRID_SIZE
			var d0: int = base_idx + gy
			var d1: int = base_idx + gy + 1
			st.add_index(e0); st.add_index(e1); st.add_index(d0)
			st.add_index(e1); st.add_index(d1); st.add_index(d0)
		base_idx += GRID_SIZE

		# Right edge (col=GRID_SIZE-1)
		for gy in GRID_SIZE:
			var gi: int = gy * GRID_SIZE + GRID_SIZE - 1
			var drop_pos: Vector3 = vertices[gi] - vertices[gi].normalized() * skirt_drop
			_add_vertex(st, drop_pos, normals_arr[gi], uvs[gi], pos_deltas[gi], nrm_deltas[gi])
		for gy in GRID_SIZE - 1:
			var e0: int = gy * GRID_SIZE + GRID_SIZE - 1
			var e1: int = (gy + 1) * GRID_SIZE + GRID_SIZE - 1
			var d0: int = base_idx + gy
			var d1: int = base_idx + gy + 1
			st.add_index(e0); st.add_index(d0); st.add_index(e1)
			st.add_index(e1); st.add_index(d0); st.add_index(d1)

	st.generate_tangents()
	return st.commit()


## Helper: add a single vertex with all attributes including morph deltas.
static func _add_vertex(st: SurfaceTool, pos: Vector3, normal: Vector3, uv: Vector2, pos_delta: Vector3, nrm_delta: Vector3) -> void:
	st.set_uv(uv)
	st.set_normal(normal)
	st.set_custom(0, Color(pos_delta.x, pos_delta.y, pos_delta.z, 0.0))
	st.set_custom(1, Color(nrm_delta.x, nrm_delta.y, nrm_delta.z, 0.0))
	st.add_vertex(pos)
