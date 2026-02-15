class_name SpaceStation
extends StaticBody3D

# =============================================================================
# Space Station
# Loads a GLB model and generates precise trimesh collision.
# Size is controlled by the node's transform in the editor, not in code.
# =============================================================================

@export var station_name: String = "Alpha Station"
@export var station_type: int = 0  # StationData.StationType value

var structure_health = null
var weapon_manager = null
var station_equipment = null
var defense_ai = null


func _ready() -> void:
	collision_layer = Constants.LAYER_STATIONS
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_PROJECTILES
	add_to_group("structures")

	# Health system
	structure_health = StructureHealth.new()
	structure_health.name = "StructureHealth"
	structure_health.apply_preset(station_type)
	add_child(structure_health)

	# Death handler
	var death_handler =StructureDeathHandler.new()
	death_handler.name = "StructureDeathHandler"
	add_child(death_handler)

	await _load_model()

	# Setup hardpoints, weapons, defense AI after model is loaded
	if station_equipment == null:
		station_equipment = StationEquipment.create_empty(name, station_type)
	StationFactory.setup_station(self, station_equipment)


func _load_model() -> void:
	var scene: PackedScene = load("res://assets/models/space_station.glb")
	if scene == null:
		push_warning("SpaceStation: Could not load model, using fallback")
		_build_fallback()
		return

	var model: Node3D = scene.instantiate()
	add_child(model)

	# Wait one frame so global transforms are computed (includes editor scale)
	await get_tree().process_frame

	# Generate exact trimesh collision from every mesh
	for child in _get_all_children(model):
		if child is MeshInstance3D and child.mesh != null:
			_create_trimesh_collision(child)


func _create_trimesh_collision(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return

	# Get mesh transform relative to this station (includes all parent scales)
	var rel_transform: Transform3D = global_transform.affine_inverse() * mesh_instance.global_transform

	# Transform every vertex to station-local space
	var transformed_faces =PackedVector3Array()
	transformed_faces.resize(faces.size())
	for i in range(faces.size()):
		transformed_faces[i] = rel_transform * faces[i]

	var shape =ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(transformed_faces)

	var col =CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _get_all_children(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_children(child))
	return result


func _build_fallback() -> void:
	var mesh =MeshInstance3D.new()
	var box =BoxMesh.new()
	box.size = Vector3(50, 20, 50)
	mesh.mesh = box
	var mat =StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4)
	mat.metallic = 0.7
	mesh.material_override = mat
	add_child(mesh)
	var col =CollisionShape3D.new()
	var shape =BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	add_child(col)
