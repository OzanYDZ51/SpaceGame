@tool
class_name MissileModelExtractor
extends Node3D

# =============================================================================
# Missile Model Extractor — Shows only a single missile from the GLB pack.
# Hides all other meshes. Works in editor (@tool) and at runtime.
# Uses recursive keyword matching to handle any GLB hierarchy depth.
# =============================================================================

@export var target_node_name: String = "":
	set(value):
		target_node_name = value
		_apply_extraction()


func _ready() -> void:
	_apply_extraction()


func _apply_extraction() -> void:
	if get_child_count() == 0:
		return
	var pack: Node = get_child(0)
	if pack == null:
		return

	# Step 1: Hide ALL MeshInstance3D nodes in the entire pack
	_set_all_meshes_visible(pack, false)

	# Step 2: Find the target node recursively using flexible matching
	var target: Node = _find_node_flexible(pack, target_node_name)
	if target == null:
		var names: PackedStringArray = PackedStringArray()
		_collect_all_node_names(pack, names, 0)
		push_warning("MissileModelExtractor: '%s' not found. Tree:\n%s" % [target_node_name, "\n".join(names)])
		return

	# Step 3: Show all MeshInstance3D nodes under the target
	_set_all_meshes_visible(target, true)

	# Step 4: Ensure entire ancestor chain is visible
	var node: Node = target
	while node != null and node != self:
		if node is Node3D:
			node.visible = true
		node = node.get_parent()

	# Step 5: Center the missile at the origin
	_center_on_target(pack, target)


func _set_all_meshes_visible(root: Node, vis: bool) -> void:
	if root is MeshInstance3D:
		root.visible = vis
	for child in root.get_children():
		_set_all_meshes_visible(child, vis)


func _find_node_flexible(root: Node, search_name: String) -> Node:
	if search_name.is_empty():
		return null
	var clean_search: String = _normalize(search_name)
	return _find_recursive(root, clean_search)


func _find_recursive(root: Node, clean_search: String) -> Node:
	var clean_name: String = _normalize(str(root.name))
	# Exact normalized match
	if clean_name == clean_search:
		return root
	# Keyword contains
	if clean_name.contains(clean_search):
		return root
	for child in root.get_children():
		var found: Node = _find_recursive(child, clean_search)
		if found:
			return found
	return null


func _center_on_target(pack: Node, target: Node) -> void:
	# Collect all visible MeshInstance3D AABBs under the target
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(target, meshes)
	if meshes.is_empty():
		return
	# Compute combined AABB in pack's local space
	var combined_aabb: AABB = meshes[0].get_aabb()
	var first_transform: Transform3D = meshes[0].global_transform
	combined_aabb = first_transform * combined_aabb
	for i in range(1, meshes.size()):
		var mesh_aabb: AABB = meshes[i].get_aabb()
		mesh_aabb = meshes[i].global_transform * mesh_aabb
		combined_aabb = combined_aabb.merge(mesh_aabb)
	# Offset the pack so the missile center is at our origin
	var center: Vector3 = combined_aabb.get_center()
	# Transform center from global to our local space
	var local_center: Vector3 = global_transform.affine_inverse() * center
	if pack is Node3D:
		pack.position -= local_center


func _collect_meshes(root: Node, meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D and root.visible:
		meshes.append(root)
	for child in root.get_children():
		_collect_meshes(child, meshes)


func _normalize(s: String) -> String:
	return s.replace(" ", "").replace("-", "").replace("_", "").to_lower()


func _collect_all_node_names(root: Node, names: PackedStringArray, depth: int) -> void:
	var indent: String = "  ".repeat(depth)
	var type_info: String = root.get_class()
	names.append("%s%s (%s)" % [indent, root.name, type_info])
	for child in root.get_children():
		_collect_all_node_names(child, names, depth + 1)
