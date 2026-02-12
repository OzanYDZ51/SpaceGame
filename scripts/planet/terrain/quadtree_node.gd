class_name QuadtreeNode
extends RefCounted

# =============================================================================
# Quadtree Node — Single node in the LOD quadtree for one cube face
# Manages split/merge decisions and creates TerrainChunk leaves.
# =============================================================================

const SPLIT_THRESHOLD: float = 0.35   # screen_error above which we split (lower = more detail, smoother LOD)
const MERGE_THRESHOLD: float = 0.175  # SPLIT/2 — ensures children start at morph_factor=0 after split
const MAX_DEPTH: int = 14             # ~5-20m tiles for 60km radius planet

var face: int = 0
var depth: int = 0
var uv_min: Vector2 = Vector2(-1, -1)
var uv_max: Vector2 = Vector2(1, 1)

var children: Array = []  # 4 QuadtreeNode children (empty if leaf)
var chunk: TerrainChunk = null
var center_sphere: Vector3 = Vector3.ZERO  # Center point on unit sphere
var node_size: float = 2.0  # Size in UV space


func _init(p_face: int = 0, p_depth: int = 0, p_uv_min: Vector2 = Vector2(-1, -1), p_uv_max: Vector2 = Vector2(1, 1)) -> void:
	face = p_face
	depth = p_depth
	uv_min = p_uv_min
	uv_max = p_uv_max
	node_size = maxf(uv_max.x - uv_min.x, uv_max.y - uv_min.y)
	var cu: float = (uv_min.x + uv_max.x) * 0.5
	var cv: float = (uv_min.y + uv_max.y) * 0.5
	center_sphere = CubeSphere.cube_to_sphere(face, cu, cv)


func is_leaf() -> bool:
	return children.is_empty()


## Compute screen-space error metric.
## Higher = more detail needed (should split). Lower = can merge.
func compute_screen_error(cam_pos: Vector3, planet_center: Vector3, planet_radius: float) -> float:
	# World-space position of this node's center
	var world_center: Vector3 = planet_center + center_sphere * planet_radius
	var dist: float = cam_pos.distance_to(world_center)
	if dist < 1.0:
		dist = 1.0
	# node_size is in UV space [0, 2] — convert to world size via tangent-warp angular span
	# With tan(u*π/4) remapping, angular span per UV unit ≈ π/4 radians
	var world_size: float = node_size * planet_radius * 0.785  # PI/4 ≈ 0.785
	return world_size / dist


## Compute geo-morph factor for this node.
## Returns 0.0 (coarse/parent appearance) to 1.0 (full detail).
func compute_morph_factor(cam_pos: Vector3, planet_center: Vector3, planet_radius: float) -> float:
	if depth == 0:
		return 1.0  # Root nodes have no parent to morph toward
	var error: float = compute_screen_error(cam_pos, planet_center, planet_radius)
	return clampf((error - MERGE_THRESHOLD) / (SPLIT_THRESHOLD - MERGE_THRESHOLD), 0.0, 1.0)


## Update the quadtree: split or merge based on camera distance.
## Returns number of chunks that need rebuilding.
func update(cam_pos: Vector3, planet_center: Vector3, planet_radius: float) -> int:
	var error: float = compute_screen_error(cam_pos, planet_center, planet_radius)
	var rebuilds: int = 0

	if is_leaf():
		# Should we split?
		if error > SPLIT_THRESHOLD and depth < MAX_DEPTH:
			_split()
			# Do NOT recursively update children — they'll be processed next cycle.
			# This prevents cascading splits (depth 0→14 in one frame).
			return 4  # Signal that 4 new leaves need chunks
		# Leaf is fine at current depth
		return 0

	# Non-leaf: check if we should merge
	if error < MERGE_THRESHOLD:
		# All children are simple enough to merge back
		var can_merge: bool = true
		for child in children:
			if not child.is_leaf():
				can_merge = false
				break
		if can_merge:
			_merge()
			return 1  # Need to rebuild our chunk

	# Recurse into children
	for child in children:
		rebuilds += child.update(cam_pos, planet_center, planet_radius)
	return rebuilds


## Get all leaf nodes that need chunks.
func get_leaves(out: Array) -> void:
	if is_leaf():
		out.append(self)
		return
	for child in children:
		child.get_leaves(out)


## Count total leaf nodes.
func count_leaves() -> int:
	if is_leaf():
		return 1
	var total: int = 0
	for child in children:
		total += child.count_leaves()
	return total


func _split() -> void:
	var mid_u: float = (uv_min.x + uv_max.x) * 0.5
	var mid_v: float = (uv_min.y + uv_max.y) * 0.5
	var d: int = depth + 1

	children = [
		QuadtreeNode.new(face, d, uv_min, Vector2(mid_u, mid_v)),
		QuadtreeNode.new(face, d, Vector2(mid_u, uv_min.y), Vector2(uv_max.x, mid_v)),
		QuadtreeNode.new(face, d, Vector2(uv_min.x, mid_v), Vector2(mid_u, uv_max.y)),
		QuadtreeNode.new(face, d, Vector2(mid_u, mid_v), uv_max),
	]

	# Keep parent chunk alive — QuadtreeFace will free it once all
	# descendant leaves have their chunks built (seamless transition).
	# If camera pulls back and node merges, the lingering chunk is reused.


func _merge() -> void:
	# Free all children and their chunks
	for child in children:
		child.free_recursive()
	children.clear()
	# Our chunk will be rebuilt by the face manager


func free_recursive() -> void:
	for child in children:
		child.free_recursive()
	children.clear()
	if chunk and is_instance_valid(chunk):
		chunk.queue_free()
		chunk = null
