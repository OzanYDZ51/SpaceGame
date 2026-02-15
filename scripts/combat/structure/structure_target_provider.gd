class_name StructureTargetProvider
extends RefCounted

# =============================================================================
# Structure Target Provider — Gathers targetable structures for TargetingSystem
# =============================================================================

static func gather_targetable(from: Vector3, range_limit: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var tree =Engine.get_main_loop() as SceneTree
	if tree == null:
		return result

	var structures =tree.get_nodes_in_group("structures")
	for node in structures:
		if not (node is Node3D):
			continue
		var n3d =node as Node3D
		var dist: float = from.distance_to(n3d.global_position)
		if dist > range_limit:
			continue
		var health = n3d.get_node_or_null("StructureHealth")
		if health and health.is_dead():
			continue
		result.append(n3d)

	return result
