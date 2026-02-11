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
static func cube_to_sphere(face: int, u: float, v: float) -> Vector3:
	var axes: Array = FACE_AXES[face]
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var forward: Vector3 = axes[2]
	var cube_point: Vector3 = forward + right * u + up * v
	return cube_point.normalized()


## Convert face UV to unit sphere with improved distribution (tangent-adjusted).
## Reduces distortion near cube corners.
static func cube_to_sphere_tangent(face: int, u: float, v: float) -> Vector3:
	# Apply tangent correction for more uniform cell sizes
	var tu: float = tan(u * PI * 0.25) * 1.0
	var tv: float = tan(v * PI * 0.25) * 1.0
	var axes: Array = FACE_AXES[face]
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var forward: Vector3 = axes[2]
	var cube_point: Vector3 = forward + right * tu + up * tv
	return cube_point.normalized()
