class_name CubeSphere
extends RefCounted

# =============================================================================
# Cube-Sphere Math — Projects cube face coordinates onto a unit sphere
# Uses the normalized-cube method for near-uniform cell distribution.
# =============================================================================

## 6 cube faces: +X, -X, +Y, -Y, +Z, -Z
enum Face { POS_X, NEG_X, POS_Y, NEG_Y, POS_Z, NEG_Z }

## Face axes: [right, up, forward] for each face
const FACE_AXES: Array[Array] = [
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],   # +X
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],    # -X
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],    # +Y (top)
	[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],    # -Y (bottom)
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],     # +Z
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],   # -Z
]


## Convert a face UV (u, v in [-1, 1]) to a unit sphere point.
## Uses tangent remapping for near-uniform cell distribution across all 6 faces.
## Without this, cells near face centers are ~1.7x larger than at edges/corners,
## creating visible square patterns on the planet surface.
static func cube_to_sphere(face: int, u: float, v: float) -> Vector3:
	# Tangent correction: maps [-1,1] UV through tan(x*π/4) → [-1,1]
	# This warps the UV grid so that angular spacing between vertices is uniform
	var tu: float = tan(u * PI * 0.25)
	var tv: float = tan(v * PI * 0.25)
	var axes: Array = FACE_AXES[face]
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var forward: Vector3 = axes[2]
	var cube_point: Vector3 = forward + right * tu + up * tv
	return cube_point.normalized()
