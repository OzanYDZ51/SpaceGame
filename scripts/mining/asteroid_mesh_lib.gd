class_name AsteroidMeshLib
extends RefCounted

# =============================================================================
# Asteroid Mesh Library — Loads asteroid GLB pack once, extracts all mesh
# variants sorted by volume, and provides helpers to pick/scale them.
# =============================================================================

const GLB_PATH: String = "res://assets/models/asteroids/asteroids_pack_metallic_version.glb"

# Each entry: { "mesh": Mesh, "max_extent": float }
static var _variants: Array = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	if not ResourceLoader.exists(GLB_PATH):
		push_warning("AsteroidMeshLib: %s not found — asteroids will use placeholder meshes" % GLB_PATH)
		return
	var scene: PackedScene = load(GLB_PATH)
	if scene == null:
		push_warning("AsteroidMeshLib: Failed to load %s — asteroids will use placeholder meshes" % GLB_PATH)
		return

	var root: Node3D = scene.instantiate()
	var entries: Array = []

	for mi in _get_all_mesh_instances(root):
		if mi.mesh == null:
			continue
		var aabb: AABB = mi.mesh.get_aabb()
		var max_extent: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
		if max_extent < 0.01:
			continue
		entries.append({
			"mesh": mi.mesh,
			"max_extent": max_extent,
		})

	# Sort by volume (biggest first) for consistent ordering
	entries.sort_custom(func(a, b):
		return a["max_extent"] > b["max_extent"]
	)

	_variants = entries
	root.queue_free()

	print("AsteroidMeshLib: Loaded %d mesh variants from GLB" % _variants.size())


static func get_variant_count() -> int:
	return _variants.size()


static func get_variant(index: int) -> Dictionary:
	if _variants.is_empty():
		return {}
	return _variants[index % _variants.size()]


static func compute_scale_for_radius(variant: Dictionary, target_radius: float) -> Vector3:
	var max_extent: float = variant.get("max_extent", 1.0)
	var ratio: float = target_radius / max_extent
	return Vector3(ratio, ratio, ratio)


static func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_all_mesh_instances(child))
	return result
