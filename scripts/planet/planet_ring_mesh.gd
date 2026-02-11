class_name PlanetRingMesh
extends RefCounted

# =============================================================================
# Planet Ring Mesh — Static helper to create a flat ring ArrayMesh in XZ plane.
# UV.x = radial position (0 = inner edge, 1 = outer edge)
# UV.y = angle (0-1 around the ring)
# =============================================================================


## Create a flat ring mesh.
## inner_r / outer_r are in local units (relative to planet radius = 1.0).
## segments = number of subdivisions around the ring.
static func create(inner_r: float = 1.3, outer_r: float = 2.2, segments: int = 128) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var up := Vector3.UP

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = t * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))

		# Inner vertex
		var v_inner := dir * inner_r
		verts.append(v_inner)
		normals.append(up)
		uvs.append(Vector2(0.0, t))

		# Outer vertex
		var v_outer := dir * outer_r
		verts.append(v_outer)
		normals.append(up)
		uvs.append(Vector2(1.0, t))

	# Triangles
	for i in range(segments):
		var base: int = i * 2
		# Two triangles per segment
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)

		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
