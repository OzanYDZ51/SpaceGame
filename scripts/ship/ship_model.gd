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

## Engine positions from VFX attach points (already in ShipModel space). If empty, uses defaults.
var vfx_engine_positions: Array[Vector3] = []


var _engine_lights: Array[OmniLight3D] = []
var _engine_fill_lights: Array[OmniLight3D] = []
var _cockpit_light: OmniLight3D = null
var _nav_lights: NavLights = null
var _engine_glow_intensity: float = 0.0
var _model_instance: Node3D = null
var _model_pivot: Node3D = null
var _silhouette_points: PackedVector3Array = PackedVector3Array()
var _visual_aabb_cache: AABB
var _visual_aabb_cached: bool = false
var _weapon_meshes: Array[Node3D] = []  # Weapon model instances attached to this ship
var _weapon_mount_root: Node3D = null  # Wrapper with root_basis for correct weapon positioning

const SHIELD_EXPANSION: float = 1.12  # Shield mesh is 12% larger than the hull
static var _shield_mesh_cache: Dictionary = {}  # model_path -> ArrayMesh




func _ready() -> void:
	if external_model_instance:
		_use_external_model()
	else:
		_load_model()
	_enhance_materials()
	_add_engine_lights()
	_add_cockpit_glow()
	_add_nav_lights()


func _use_external_model() -> void:
	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	_model_pivot.rotation_degrees = model_rotation_degrees
	_model_pivot.scale = Vector3.ONE * model_scale
	add_child(_model_pivot)

	_model_instance = external_model_instance
	_model_instance.set_owner(null)
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


func _enhance_materials() -> void:
	if _model_instance == null:
		return

	# NPC ships: apply faction color tint overlay (no rim light)
	if color_tint != Color.WHITE:
		for child in _get_all_descendants(_model_instance):
			if child is MeshInstance3D:
				var mesh_inst: MeshInstance3D = child
				var tint_overlay := StandardMaterial3D.new()
				tint_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				tint_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
				tint_overlay.albedo_color = color_tint
				tint_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_inst.material_overlay = tint_overlay




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
	var positions: Array[Vector3] = vfx_engine_positions.duplicate()
	if positions.is_empty():
		for side in [-1.0, 1.0]:
			positions.append(Vector3(1.5 * side, 0.0, 5.0) * model_scale)

	for i in positions.size():
		# Primary engine light (sharp, close)
		var light := OmniLight3D.new()
		light.light_color = engine_light_color
		light.light_energy = 0.3
		light.omni_range = 15.0 * model_scale
		light.shadow_enabled = false
		light.position = positions[i]
		light.name = "EngineLight_%d" % i
		add_child(light)
		_engine_lights.append(light)

		# Fill light (large, soft) — illuminates hull broadly
		var fill := OmniLight3D.new()
		fill.light_color = engine_light_color.lightened(0.3)
		fill.light_energy = 0.15
		fill.omni_range = 25.0 * model_scale
		fill.omni_attenuation = 1.5
		fill.shadow_enabled = false
		fill.position = positions[i]
		fill.name = "EngineFill_%d" % i
		add_child(fill)
		_engine_fill_lights.append(fill)


func _add_cockpit_glow() -> void:
	var aabb := get_visual_aabb()
	var center := aabb.get_center()
	# Cockpit: slightly forward (-Z) and above center
	var cockpit_pos := Vector3(
		center.x,
		center.y + aabb.size.y * 0.25,
		center.z - aabb.size.z * 0.3
	)
	_cockpit_light = OmniLight3D.new()
	_cockpit_light.name = "CockpitGlow"
	_cockpit_light.light_color = Color(1.0, 0.8, 0.4)  # Warm amber
	_cockpit_light.light_energy = 1.0
	_cockpit_light.omni_range = 5.0 * model_scale
	_cockpit_light.shadow_enabled = false
	_cockpit_light.position = cockpit_pos
	add_child(_cockpit_light)



func _add_nav_lights() -> void:
	var aabb := get_visual_aabb()
	_nav_lights = NavLights.new()
	_nav_lights.name = "NavLights"
	_nav_lights.setup(aabb, model_scale)
	add_child(_nav_lights)


func update_engine_glow(thrust_amount: float) -> void:
	_engine_glow_intensity = lerp(_engine_glow_intensity, thrust_amount, 0.1)
	var primary_energy: float = 0.3 + _engine_glow_intensity * 2.0
	var fill_energy: float = 0.15 + _engine_glow_intensity * 0.5
	for light in _engine_lights:
		light.light_energy = primary_energy
	for fill in _engine_fill_lights:
		fill.light_energy = fill_energy


func get_visual_aabb() -> AABB:
	## Returns the ship's visual AABB in ShipModel-local space (with model_pivot
	## scale and centering applied). Cached after first call.
	if _visual_aabb_cached:
		return _visual_aabb_cache
	if _model_instance == null or _model_pivot == null:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var raw_aabb := _get_combined_aabb(_model_instance)
	# Apply model_instance offset (centering) and model_pivot scale
	var pivot_xform := _model_pivot.transform * _model_instance.transform
	_visual_aabb_cache = _transform_aabb(raw_aabb, pivot_xform)
	_visual_aabb_cached = true
	return _visual_aabb_cache


func get_shield_mesh() -> ArrayMesh:
	## Returns a hull-conforming ArrayMesh for shield effects, expanded by SHIELD_EXPANSION.
	## Cached per model_path so all instances of the same ship type share the mesh.
	if _shield_mesh_cache.has(model_path):
		return _shield_mesh_cache[model_path]
	var mesh := _build_shield_mesh()
	if mesh:
		_shield_mesh_cache[model_path] = mesh
	return mesh


func _build_shield_mesh() -> ArrayMesh:
	if _model_instance == null or _model_pivot == null:
		return null

	var base_xform: Transform3D = _model_pivot.transform * _model_instance.transform
	var aabb := get_visual_aabb()
	var center := aabb.get_center()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert_count := 0

	for desc in _get_all_descendants(_model_instance):
		if not (desc is MeshInstance3D):
			continue
		var mi: MeshInstance3D = desc
		if mi.mesh == null:
			continue
		var mesh_xform: Transform3D = base_xform * _get_relative_transform(mi, _model_instance)

		for surf_idx in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surf_idx)
			if arrays.is_empty() or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()

			if indices.size() > 0:
				# Indexed geometry: emit non-indexed triangles
				for i in range(0, indices.size() - 2, 3):
					for j in 3:
						var idx := indices[i + j]
						if idx >= verts.size():
							break
						var v: Vector3 = mesh_xform * verts[idx]
						v = center + (v - center) * SHIELD_EXPANSION
						st.add_vertex(v)
						vert_count += 1
			else:
				# Non-indexed: vertices already in triangle order
				for i in verts.size():
					var v: Vector3 = mesh_xform * verts[i]
					v = center + (v - center) * SHIELD_EXPANSION
					st.add_vertex(v)
					vert_count += 1

	if vert_count < 3:
		return null

	st.generate_normals()
	return st.commit()


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


## Instantiates weapon model scenes at hardpoint positions on this ship model.
## configs: Array of hardpoint config dicts (each with "position", "id", etc.)
## weapon_names: Array of weapon StringNames matching hardpoint order (empty = no weapon)
func apply_equipment(configs: Array[Dictionary], weapon_names: Array[StringName], root_basis: Basis = Basis.IDENTITY) -> void:
	clear_equipment()

	# Wrapper node with root_basis (ship scene root's rotation+scale).
	# No runtime scaling — everything uses the scene's actual values.
	var mount_root := Node3D.new()
	mount_root.name = "WeaponMountRoot"
	mount_root.transform.basis = root_basis
	add_child(mount_root)
	_weapon_mount_root = mount_root

	for i in mini(configs.size(), weapon_names.size()):
		if weapon_names[i] == &"":
			continue
		var weapon := WeaponRegistry.get_weapon(weapon_names[i])
		if weapon == null or weapon.weapon_model_scene == "":
			continue
		var scene: PackedScene = load(weapon.weapon_model_scene) as PackedScene
		if scene == null:
			continue
		var instance := scene.instantiate() as Node3D
		if instance == null:
			continue
		var pivot := Node3D.new()
		pivot.name = "WeaponMount_%d" % i
		pivot.position = configs[i].get("position", Vector3.ZERO)
		pivot.rotation_degrees = configs[i].get("rotation_degrees", Vector3.ZERO)
		mount_root.add_child(pivot)
		pivot.add_child(instance)
		_weapon_meshes.append(pivot)


## Removes all weapon model instances from this ship model.
func clear_equipment() -> void:
	for mesh in _weapon_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_weapon_meshes.clear()
	if _weapon_mount_root and is_instance_valid(_weapon_mount_root):
		_weapon_mount_root.queue_free()
		_weapon_mount_root = null
