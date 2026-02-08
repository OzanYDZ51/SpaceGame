class_name ShipModel
extends Node3D

# =============================================================================
# Ship Model - Loads a .glb 3D model for any ship (player or NPC).
# Auto-centers the model based on its mesh AABB so the pivot is correct.
# Supports color tinting for faction identification (red=hostile, green=friendly).
# =============================================================================

## Path to the ship .glb model
@export var model_path: String = "res://assets/models/tie.glb"

## Scale applied to the imported model
@export var model_scale: float = 1.0

## Rotation offset in degrees (adjust in inspector to orient the model facing -Z)
@export var model_rotation_degrees: Vector3 = Vector3.ZERO

## If true, skip AABB auto-centering (scene-based models handle their own positioning)
var skip_centering: bool = false

## Color tint applied to the model (white = no tint)
var color_tint: Color = Color.WHITE

## Engine light color (blue for player, can be red/orange for NPCs)
var engine_light_color: Color = Color(0.3, 0.5, 1.0)

## If set, this pre-instantiated model is used instead of loading from model_path.
## Used when a ship scene provides the model directly.
var external_model_instance: Node3D = null

var _engine_lights: Array[OmniLight3D] = []
var _engine_glow_intensity: float = 0.0
var _model_instance: Node3D = null
var _model_pivot: Node3D = null
var _silhouette_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	if external_model_instance:
		_use_external_model()
	else:
		_load_model()
	if color_tint != Color.WHITE:
		_apply_color_tint()
	_add_engine_lights()


func _use_external_model() -> void:
	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	_model_pivot.rotation_degrees = model_rotation_degrees
	_model_pivot.scale = Vector3.ONE * model_scale
	add_child(_model_pivot)

	_model_instance = external_model_instance
	_model_pivot.add_child(_model_instance)
	# Skip _center_model() — the ship scene already has correct positioning


func _load_model() -> void:
	var scene: PackedScene = load(model_path)
	if scene == null:
		push_error("ShipModel: Failed to load model at " + model_path)
		return

	_model_instance = scene.instantiate() as Node3D
	if _model_instance == null:
		push_error("ShipModel: Model root is not Node3D")
		return

	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	_model_pivot.rotation_degrees = model_rotation_degrees
	_model_pivot.scale = Vector3.ONE * model_scale
	add_child(_model_pivot)

	_model_pivot.add_child(_model_instance)

	# Auto-center based on combined AABB (skip for scene-based models)
	if not skip_centering:
		_center_model()



func _center_model() -> void:
	var aabb := _get_combined_aabb(_model_instance)
	if aabb.size.length() < 0.001:
		push_warning("ShipModel: AABB is zero-sized, cannot auto-center")
		return
	_model_instance.position = -aabb.get_center()


func _apply_color_tint() -> void:
	if _model_instance == null:
		return
	for child in _get_all_descendants(_model_instance):
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child
			# Create a tint overlay material
			var overlay := StandardMaterial3D.new()
			overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			overlay.albedo_color = color_tint
			overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_inst.material_overlay = overlay


func _get_combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var found_first := false
	for child in _get_all_descendants(node):
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child
			if mesh_inst.mesh == null:
				continue
			var child_aabb: AABB = mesh_inst.mesh.get_aabb()
			var child_transform: Transform3D = _get_relative_transform(mesh_inst, node)
			var transformed := _transform_aabb(child_aabb, child_transform)
			if not found_first:
				result = transformed
				found_first = true
			else:
				result = result.merge(transformed)
	return result


func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result


func _get_relative_transform(child: Node3D, ancestor: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node3D = child
	while current != ancestor and current != null:
		xform = current.transform * xform
		current = current.get_parent() as Node3D
	return xform


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	for i in range(8):
		var corner := Vector3(
			aabb.position.x + aabb.size.x * (1 if i & 1 else 0),
			aabb.position.y + aabb.size.y * (1 if i & 2 else 0),
			aabb.position.z + aabb.size.z * (1 if i & 4 else 0),
		)
		corners.append(xform * corner)
	var result := AABB(corners[0], Vector3.ZERO)
	for j in range(1, 8):
		result = result.expand(corners[j])
	return result


func _add_engine_lights() -> void:
	for side in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.light_color = engine_light_color
		light.light_energy = 2.0
		light.omni_range = 8.0 * model_scale
		light.position = Vector3(1.5 * side, 0.0, 5.0) * model_scale
		light.name = "EngineLight_" + ("L" if side < 0 else "R")
		add_child(light)
		_engine_lights.append(light)



func update_engine_glow(thrust_amount: float) -> void:
	_engine_glow_intensity = lerp(_engine_glow_intensity, thrust_amount, 0.1)
	for light in _engine_lights:
		light.light_energy = 0.5 + _engine_glow_intensity * 4.0


func get_silhouette_points() -> PackedVector3Array:
	## Returns a small set (~60) of extreme 3D vertices that define the ship's
	## outline from any viewing angle. Computed lazily and cached.
	if _silhouette_points.is_empty() and _model_instance != null:
		_build_silhouette_points()
	return _silhouette_points


func _build_silhouette_points() -> void:
	if _model_instance == null or _model_pivot == null:
		return

	# Collect all transformed vertices from the mesh
	var verts := PackedVector3Array()
	var base_xform: Transform3D = _model_pivot.transform * _model_instance.transform

	for desc in _get_all_descendants(_model_instance):
		if not (desc is MeshInstance3D):
			continue
		var mi: MeshInstance3D = desc
		if mi.mesh == null:
			continue
		var mesh_xform: Transform3D = base_xform * _get_relative_transform(mi, _model_instance)
		for surf_idx in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surf_idx)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in raw:
				verts.append(mesh_xform * v)

	if verts.is_empty():
		return

	# 26 sample directions: 6 face + 8 corner + 12 edge normals of a cube
	var dirs: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		dirs.append(axis)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				dirs.append(Vector3(sx, sy, sz).normalized())
	for s1 in [-1.0, 1.0]:
		for s2 in [-1.0, 1.0]:
			dirs.append(Vector3(s1, s2, 0).normalized())
			dirs.append(Vector3(s1, 0, s2).normalized())
			dirs.append(Vector3(0, s1, s2).normalized())

	# For each direction, find the farthest vertex (single pass)
	var best_dots: Array[float] = []
	var best_indices: Array[int] = []
	best_dots.resize(dirs.size())
	best_indices.resize(dirs.size())
	for d in dirs.size():
		best_dots[d] = -INF
		best_indices[d] = 0

	for i in verts.size():
		var v: Vector3 = verts[i]
		for d in dirs.size():
			var dot_val := v.dot(dirs[d])
			if dot_val > best_dots[d]:
				best_dots[d] = dot_val
				best_indices[d] = i

	# Collect unique extreme vertices
	var unique: Dictionary = {}
	for idx in best_indices:
		unique[idx] = true

	_silhouette_points = PackedVector3Array()
	for idx in unique:
		_silhouette_points.append(verts[idx])
