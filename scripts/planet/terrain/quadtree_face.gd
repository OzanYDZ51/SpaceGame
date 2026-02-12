class_name QuadtreeFace
extends RefCounted

# =============================================================================
# Quadtree Face — Manages one of 6 cube faces
# Owns the root QuadtreeNode, handles chunk creation/destruction, mesh builds.
# Parent chunks linger after split until all children are built (seamless LOD).
# =============================================================================

## Per-face budget is set externally by PlanetBody to share a global budget.
var max_rebuilds_per_frame: int = 4

var face_index: int = 0
var root: QuadtreeNode = null
var planet_radius: float = 50_000.0
var heightmap: HeightmapGenerator = null
var terrain_material: Material = null
var parent_node: Node3D = null  # PlanetBody — chunks are added as children

# Chunks pending mesh rebuild
var _rebuild_queue: Array[QuadtreeNode] = []
var _rebuild_set: Dictionary = {}  # QuadtreeNode -> true, for O(1) lookup

# Cached leaves for per-frame morph updates (avoids tree traversal every frame)
var _active_leaves: Array = []
var _last_cam_pos: Vector3 = Vector3.ZERO
var _last_planet_center: Vector3 = Vector3.ZERO


func setup(p_face: int, p_radius: float, p_heightmap: HeightmapGenerator, p_material: Material, p_parent: Node3D) -> void:
	face_index = p_face
	planet_radius = p_radius
	heightmap = p_heightmap
	terrain_material = p_material
	parent_node = p_parent
	root = QuadtreeNode.new(p_face, 0, Vector2(-1, -1), Vector2(1, 1))


## Update quadtree LOD and process pending chunk rebuilds.
## can_split=false prevents new splits (global budget exceeded).
## Returns number of active chunks on this face.
func update(cam_pos: Vector3, planet_center: Vector3, can_split: bool = true) -> int:
	if root == null:
		return 0

	_last_cam_pos = cam_pos
	_last_planet_center = planet_center

	# Update quadtree structure (split/merge)
	root.update(cam_pos, planet_center, planet_radius, can_split)

	# Collect leaves that need chunks (cached for per-frame morph updates)
	_active_leaves.clear()
	root.get_leaves(_active_leaves)

	# Queue any leaves missing chunks for rebuild (O(1) set lookup)
	for leaf: QuadtreeNode in _active_leaves:
		if leaf.chunk == null or not is_instance_valid(leaf.chunk):
			if not _rebuild_set.has(leaf):
				_rebuild_queue.append(leaf)
				_rebuild_set[leaf] = true

	# Process rebuild queue (amortized)
	var rebuilds: int = 0
	while not _rebuild_queue.is_empty() and rebuilds < max_rebuilds_per_frame:
		var node: QuadtreeNode = _rebuild_queue.pop_front()
		_rebuild_set.erase(node)
		# Verify still a leaf (may have been split since queued)
		if not node.is_leaf():
			continue
		_build_chunk_for_node(node)
		rebuilds += 1

	# Free parent chunks whose children are all built (seamless split transition)
	_retire_stale_parent_chunks(root)

	return _active_leaves.size()


func _build_chunk_for_node(node: QuadtreeNode) -> void:
	# Free existing chunk
	if node.chunk and is_instance_valid(node.chunk):
		node.chunk.queue_free()

	var chunk := TerrainChunk.new()
	chunk.setup(face_index, node.depth, node.uv_min, node.uv_max)
	chunk.build_mesh(planet_radius, heightmap, terrain_material)
	# Start with correct morph factor to avoid 1-frame pop
	var mf: float = node.compute_morph_factor(_last_cam_pos, _last_planet_center, planet_radius)
	chunk.set_morph_factor(mf)
	parent_node.add_child(chunk)
	node.chunk = chunk


## Update geo-morph factors on all active leaf chunks. Call every frame for smooth transitions.
func update_morph_factors(cam_pos: Vector3, planet_center: Vector3) -> void:
	for leaf: QuadtreeNode in _active_leaves:
		if leaf.chunk and is_instance_valid(leaf.chunk):
			var mf: float = leaf.compute_morph_factor(cam_pos, planet_center, planet_radius)
			leaf.chunk.set_morph_factor(mf)


## Recursively free parent chunks that linger after a split, once ALL their
## descendant leaves have built chunks. This ensures seamless visual coverage:
## the parent stays visible until children are ready, then is retired.
func _retire_stale_parent_chunks(node: QuadtreeNode) -> void:
	if node == null or node.is_leaf():
		return
	# Bottom-up: recurse children first
	for child in node.children:
		_retire_stale_parent_chunks(child)
	# Non-leaf with a chunk = parent lingering after split
	if node.chunk and is_instance_valid(node.chunk):
		if _all_leaves_have_chunks(node):
			node.chunk.queue_free()
			node.chunk = null


## Check if every leaf descendant of this node has a built chunk.
static func _all_leaves_have_chunks(node: QuadtreeNode) -> bool:
	if node.is_leaf():
		return node.chunk != null and is_instance_valid(node.chunk) and node.chunk.is_built()
	for child in node.children:
		if not _all_leaves_have_chunks(child):
			return false
	return true


## Free all chunks and the quadtree.
func free_all() -> void:
	if root:
		root.free_recursive()
		root = null
	_rebuild_queue.clear()
	_rebuild_set.clear()
	_active_leaves.clear()


## Enable/disable trimesh collision on nearby chunks.
## Only chunks within COLLISION_RADIUS get collision (expensive), the rest are visual-only.
## Returns number of collision shapes created this call (for budget tracking).
func update_collision(cam_pos: Vector3, planet_center: Vector3, budget: int = 2) -> int:
	const COLLISION_ENABLE_DIST: float = 5000.0
	const COLLISION_DISABLE_DIST: float = 6000.0  # Hysteresis to avoid thrashing
	var created: int = 0
	for leaf: QuadtreeNode in _active_leaves:
		var ch := leaf.chunk
		if ch == null or not is_instance_valid(ch) or not ch.is_built():
			continue
		var world_center: Vector3 = planet_center + ch.chunk_center * planet_radius
		var dist: float = cam_pos.distance_to(world_center)
		if dist < COLLISION_ENABLE_DIST and not ch.has_collision():
			if created >= budget:
				continue
			ch.enable_collision()
			created += 1
		elif dist > COLLISION_DISABLE_DIST and ch.has_collision():
			ch.disable_collision()
	return created


## Get total active leaf count.
func get_chunk_count() -> int:
	if root == null:
		return 0
	return root.count_leaves()
