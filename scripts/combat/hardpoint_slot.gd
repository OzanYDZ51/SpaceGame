@tool
class_name HardpointSlot
extends Node3D

# =============================================================================
# Hardpoint Slot - Editor-visible weapon mount point (@tool).
# Place as child of a ship scene to define weapon positions visually.
# Draws a colored sphere gizmo + direction arrow in editor.
# =============================================================================

@export var slot_id: int = 0
@export_enum("S", "M", "L") var slot_size: String = "S"
@export var is_turret: bool = false
@export_range(0, 360) var turret_arc_degrees: float = 180.0
@export_range(10, 360) var turret_speed_deg_s: float = 90.0
@export_range(0, 90) var turret_vertical_arc: float = 45.0

var _gizmo_mesh: MeshInstance3D = null
var _arrow_mesh: MeshInstance3D = null
var _arc_mesh: MeshInstance3D = null
var _label: Label3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_create_gizmo()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _gizmo_mesh:
		_update_gizmo_color()
		_update_label()


func _create_gizmo() -> void:
	# Sphere gizmo
	_gizmo_mesh = MeshInstance3D.new()
	_gizmo_mesh.name = "_EditorGizmo"
	var sphere := SphereMesh.new()
	sphere.radius = _get_gizmo_radius()
	sphere.height = _get_gizmo_radius() * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_gizmo_mesh.mesh = sphere
	_gizmo_mesh.material_override = _create_gizmo_material()
	add_child(_gizmo_mesh)

	# Direction arrow (points forward -Z)
	_arrow_mesh = MeshInstance3D.new()
	_arrow_mesh.name = "_EditorArrow"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.0
	cylinder.bottom_radius = _get_gizmo_radius() * 0.5
	cylinder.height = _get_gizmo_radius() * 3.0
	_arrow_mesh.mesh = cylinder
	_arrow_mesh.material_override = _create_gizmo_material()
	# Rotate so cone points -Z (forward)
	_arrow_mesh.rotation_degrees.x = 90.0
	_arrow_mesh.position.z = -_get_gizmo_radius() * 2.0
	add_child(_arrow_mesh)

	# Info label
	_label = Label3D.new()
	_label.name = "_EditorLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = false
	_label.pixel_size = 0.002
	_label.font_size = 32
	_label.outline_size = 4
	_label.modulate = _get_gizmo_color()
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.no_depth_test = true
	_label.position.y = _get_gizmo_radius() + 0.15
	_label.text = _build_label_text()
	add_child(_label)

	# Arc indicator for turrets
	if is_turret:
		_create_arc_indicator()


func _create_arc_indicator() -> void:
	_arc_mesh = MeshInstance3D.new()
	_arc_mesh.name = "_EditorArc"
	var im := ImmediateMesh.new()
	_arc_mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mesh.material_override = mat
	add_child(_arc_mesh)
	_rebuild_arc_mesh()


func _rebuild_arc_mesh() -> void:
	if _arc_mesh == null or not (_arc_mesh.mesh is ImmediateMesh):
		return
	var im: ImmediateMesh = _arc_mesh.mesh
	im.clear_surfaces()

	var radius: float = _get_gizmo_radius() * 5.0
	var half_arc: float = deg_to_rad(turret_arc_degrees * 0.5)
	var segments: int = 16

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0: float = -half_arc + (float(i) / segments) * half_arc * 2.0
		var a1: float = -half_arc + (float(i + 1) / segments) * half_arc * 2.0
		# Triangle fan from origin
		var p0 := Vector3(sin(a0) * radius, 0.0, -cos(a0) * radius)
		var p1 := Vector3(sin(a1) * radius, 0.0, -cos(a1) * radius)
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(p0)
		im.surface_add_vertex(p1)
	im.surface_end()


func _get_gizmo_radius() -> float:
	match slot_size:
		"S": return 0.3
		"M": return 0.5
		"L": return 0.7
	return 0.3


func _get_gizmo_color() -> Color:
	match slot_size:
		"S": return Color(0.2, 1.0, 0.3, 0.7)   # Green
		"M": return Color(1.0, 0.9, 0.2, 0.7)   # Yellow
		"L": return Color(1.0, 0.3, 0.2, 0.7)   # Red
	return Color(0.2, 1.0, 0.3, 0.7)


func _create_gizmo_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_gizmo_color()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat


func _update_gizmo_color() -> void:
	var col := _get_gizmo_color()
	if _gizmo_mesh and _gizmo_mesh.material_override:
		_gizmo_mesh.material_override.albedo_color = col
	if _arrow_mesh and _arrow_mesh.material_override:
		_arrow_mesh.material_override.albedo_color = col
	if _label:
		_label.modulate = col


func _build_label_text() -> String:
	var txt := "#%d [%s]" % [slot_id, slot_size]
	if is_turret:
		txt += " TURRET"
	return txt


func _update_label() -> void:
	if _label == null:
		return
	var new_text := _build_label_text()
	if _label.text != new_text:
		_label.text = new_text
		_label.position.y = _get_gizmo_radius() + 0.15


## Extracts runtime configuration dictionary from this editor node.
func get_slot_config() -> Dictionary:
	return {
		"id": slot_id,
		"size": slot_size,
		"position": position,
		"direction": -basis.z,  # Forward direction of the slot
		"is_turret": is_turret,
		"turret_arc_degrees": turret_arc_degrees,
		"turret_speed_deg_s": turret_speed_deg_s,
		"turret_vertical_arc": turret_vertical_arc,
	}
