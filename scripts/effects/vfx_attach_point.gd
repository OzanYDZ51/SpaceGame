@tool
class_name VFXAttachPoint
extends Marker3D

# =============================================================================
# VFX Attach Point - Editor-visible VFX mount point (@tool).
# Place as child of a ship scene to define VFX emitter positions visually.
# The marker's -Z direction (forward arrow) defines the emission direction.
# Draws a colored diamond gizmo + direction arrow in editor.
#
# Types:
#   ENGINE  — engine trail particles + heat haze (cyan gizmo)
#   RCS     — maneuvering thruster puffs (yellow gizmo)
#   BOOST   — boost-specific flame effects (orange gizmo)
# =============================================================================

enum PointType { ENGINE, RCS, BOOST }

@export var point_type: PointType = PointType.ENGINE

var _gizmo_mesh: MeshInstance3D = null
var _arrow_mesh: MeshInstance3D = null
var _label: Label3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_create_gizmo()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _gizmo_mesh:
		_gizmo_mesh.material_override.albedo_color = _get_color()
		if _arrow_mesh:
			_arrow_mesh.material_override.albedo_color = _get_color()
		if _label:
			_label.modulate = _get_color()
			var new_text := _build_label()
			if _label.text != new_text:
				_label.text = new_text


## Extracts runtime config from this editor node.
func get_config() -> Dictionary:
	return {
		"type": _type_name(),
		"position": position,
		"direction": -basis.z,
	}


# =============================================================================
# GIZMO
# =============================================================================

func _create_gizmo() -> void:
	# Diamond gizmo (rotated cube)
	_gizmo_mesh = MeshInstance3D.new()
	_gizmo_mesh.name = "_VFXGizmo"
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	_gizmo_mesh.mesh = box
	_gizmo_mesh.rotation_degrees = Vector3(45, 45, 0)
	_gizmo_mesh.material_override = _make_mat()
	add_child(_gizmo_mesh)

	# Direction arrow (points -Z = emission direction)
	_arrow_mesh = MeshInstance3D.new()
	_arrow_mesh.name = "_VFXArrow"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.12
	cyl.height = 0.8
	_arrow_mesh.mesh = cyl
	_arrow_mesh.material_override = _make_mat()
	_arrow_mesh.rotation_degrees.x = 90.0
	_arrow_mesh.position.z = -0.6
	add_child(_arrow_mesh)

	# Label
	_label = Label3D.new()
	_label.name = "_VFXLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = false
	_label.pixel_size = 0.002
	_label.font_size = 28
	_label.outline_size = 4
	_label.modulate = _get_color()
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.no_depth_test = true
	_label.position.y = 0.4
	_label.text = _build_label()
	add_child(_label)


func _get_color() -> Color:
	match point_type:
		PointType.ENGINE: return Color(0.0, 0.9, 1.0, 0.8)   # Cyan
		PointType.RCS:    return Color(1.0, 0.9, 0.2, 0.8)    # Yellow
		PointType.BOOST:  return Color(1.0, 0.5, 0.1, 0.8)    # Orange
	return Color(0.0, 0.9, 1.0, 0.8)


func _type_name() -> StringName:
	match point_type:
		PointType.ENGINE: return &"ENGINE"
		PointType.RCS:    return &"RCS"
		PointType.BOOST:  return &"BOOST"
	return &"ENGINE"


func _build_label() -> String:
	return "VFX:%s" % _type_name()


func _make_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_color()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat
