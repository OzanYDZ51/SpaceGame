class_name QuadtreeFace
extends RefCounted

# =============================================================================
# Quadtree Face — Manages one of 6 cube faces
# Owns the root QuadtreeNode, handles chunk creation/destruction, mesh builds.
# Budget: max 2-4 chunk rebuilds per frame.
# =============================================================================

const MAX_REBUILDS_PER_FRAME: int = 8

var face_index: int = 0
var root: QuadtreeNode = null
var planet_radius: float = 50_000.0
var heightmap: HeightmapGenerator = null
var terrain_material: Material = null
var parent_node: Node3D = null  # PlanetBody — chunks are added as children

# Chunks pending mesh rebuild
var _rebuild_queue: Array[QuadtreeNode] = []


func setup(p_face: int, p_radius: float, p_heightmap: HeightmapGenerator, p_material: Material, p_parent: Node3D) -> void:
	face_index = p_face
	planet_radius = p_radius
	heightmap = p_heightmap
	terrain_material = p_material
	parent_node = p_parent
	root = QuadtreeNode.new(p_face, 0, Vector2(-1, -1), Vector2(1, 1))


## Update quadtree LOD and process pending chunk rebuilds.
## Returns number of active chunks on this face.
func update(cam_pos: Vector3, planet_center: Vector3) -> int:
	if root == null:
		return 0

	# Update quadtree structure (split/merge)
	root.update(cam_pos, planet_center, planet_radius)

	# Collect leaves that need chunks
	var leaves: Array = []
	root.get_leaves(leaves)

	# Queue any leaves missing chunks for rebuild
	for leaf: QuadtreeNode in leaves:
		if leaf.chunk == null or not is_instance_valid(leaf.chunk):
			if not _rebuild_queue.has(leaf):
				_rebuild_queue.append(leaf)

	# Process rebuild queue (amortized)
	var rebuilds: int = 0
	while not _rebuild_queue.is_empty() and rebuilds < MAX_REBUILDS_PER_FRAME:
		var node: QuadtreeNode = _rebuild_queue.pop_front()
		# Verify still a leaf (may have been split since queued)
		if not node.is_leaf():
			continue
		_build_chunk_for_node(node)
		rebuilds += 1

	# Clean up orphaned chunks (nodes that were merged away)
	_cleanup_orphan_chunks(leaves)

	return leaves.size()


func _build_chunk_for_node(node: QuadtreeNode) -> void:
	# Free existing chunk
	if node.chunk and is_instance_valid(node.chunk):
		node.chunk.queue_free()

	var chunk := TerrainChunk.new()
	chunk.setup(face_index, node.depth, node.uv_min, node.uv_max)
	chunk.build_mesh(planet_radius, heightmap, terrain_material)
	parent_node.add_child(chunk)
	node.chunk = chunk


func _cleanup_orphan_chunks(active_leaves: Array) -> void:
	# Build set of active chunks for fast lookup
	var active_chunks: Dictionary = {}
	for leaf: QuadtreeNode in active_leaves:
		if leaf.chunk and is_instance_valid(leaf.chunk):
			active_chunks[leaf.chunk.get_instance_id()] = true

	# Check all children of parent_node that are TerrainChunks on our face
	# (We trust that chunks have face set correctly)
	# This is done by the PlanetBody orchestrator instead to avoid cross-face issues


## Free all chunks and the quadtree.
func free_all() -> void:
	if root:
		root.free_recursive()
		root = null
	_rebuild_queue.clear()


## Get total active leaf count.
func get_chunk_count() -> int:
	if root == null:
		return 0
	return root.count_leaves()
