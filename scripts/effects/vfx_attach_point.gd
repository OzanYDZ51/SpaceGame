@tool
class_name VFXAttachPoint
extends Marker3D

# =============================================================================
# VFX Attach Point - Editor-visible VFX mount point (@tool).
# Place as child of a ship scene to define VFX emitter positions visually.
# The marker's -Z direction (forward arrow) defines the emission direction.
# Shows REAL particle previews in the editor instead of abstract gizmos.
#
# Types:
#   ENGINE  — engine trail (cyan exhaust stream)
#   RCS     — maneuvering thruster (white-blue puff)
#   BOOST   — boost flame (orange-hot jet)
# =============================================================================

enum PointType { ENGINE, RCS, BOOST }

@export var point_type: PointType = PointType.ENGINE

var _gizmo_mesh: MeshInstance3D = null
var _label: Label3D = null
var _preview: GPUParticles3D = null
var _preview_type: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		_create_gizmo()
		_create_preview()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _gizmo_mesh:
		_gizmo_mesh.material_override.albedo_color = _get_color()
	if _label:
		_label.modulate = _get_color()
		var new_text := _build_label()
		if _label.text != new_text:
			_label.text = new_text
	# Recreate preview when point_type changes in inspector
	if int(point_type) != _preview_type:
		_create_preview()


## Extracts runtime config from this editor node.
func get_config() -> Dictionary:
	return {
		"type": _type_name(),
		"position": position,
		"direction": -basis.z,
	}


# =============================================================================
# GIZMO (tiny diamond click-target + label)
# =============================================================================

func _create_gizmo() -> void:
	# Tiny diamond (click target only — the particles ARE the gizmo)
	_gizmo_mesh = MeshInstance3D.new()
	_gizmo_mesh.name = "_VFXGizmo"
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	_gizmo_mesh.mesh = box
	_gizmo_mesh.rotation_degrees = Vector3(45, 45, 0)
	_gizmo_mesh.material_override = _make_unlit_mat(_get_color())
	add_child(_gizmo_mesh)

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
	_label.position.y = 0.35
	_label.text = _build_label()
	add_child(_label)


# =============================================================================
# VFX PREVIEW (real GPU particles — what you see is what you get)
# =============================================================================

func _create_preview() -> void:
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null

	_preview_type = int(point_type)
	_preview = GPUParticles3D.new()
	_preview.name = "_VFXPreview"

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	# Particles emit along marker's -Z (local forward)
	mat.direction = Vector3(0.0, 0.0, -1.0)
	mat.gravity = Vector3.ZERO

	var emit_color := Color.WHITE
	var emit_energy := 1.0
	var quad_size := Vector2(0.15, 0.15)

	match point_type:
		PointType.ENGINE:
			mat.emission_sphere_radius = 0.08
			mat.spread = 12.0
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 6.0
			mat.damping_min = 1.0
			mat.damping_max = 3.0
			mat.scale_min = 0.4
			mat.scale_max = 0.8
			_preview.amount = 12
			_preview.lifetime = 0.35
			emit_color = Color(0.3, 0.6, 1.0)
			emit_energy = 3.0
			quad_size = Vector2(0.2, 0.2)
			mat.color_ramp = _make_gradient([
				[0.0, Color(1.0, 0.95, 0.9, 0.9)],
				[0.2, Color(0.4, 0.8, 1.0, 0.6)],
				[1.0, Color(0.1, 0.3, 0.6, 0.0)],
			])

		PointType.RCS:
			mat.emission_sphere_radius = 0.04
			mat.spread = 30.0
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 4.0
			mat.damping_min = 3.0
			mat.damping_max = 6.0
			mat.scale_min = 0.2
			mat.scale_max = 0.4
			_preview.amount = 6
			_preview.lifetime = 0.12
			emit_color = Color(0.4, 0.6, 1.0)
			emit_energy = 1.5
			quad_size = Vector2(0.1, 0.1)
			mat.color_ramp = _make_gradient([
				[0.0, Color(0.9, 0.95, 1.0, 0.7)],
				[0.3, Color(0.5, 0.7, 1.0, 0.3)],
				[1.0, Color(0.3, 0.5, 0.8, 0.0)],
			])

		PointType.BOOST:
			mat.emission_sphere_radius = 0.1
			mat.spread = 8.0
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 9.0
			mat.damping_min = 1.0
			mat.damping_max = 2.0
			mat.scale_min = 0.5
			mat.scale_max = 1.0
			_preview.amount = 16
			_preview.lifetime = 0.45
			emit_color = Color(1.0, 0.4, 0.1)
			emit_energy = 4.0
			quad_size = Vector2(0.25, 0.25)
			mat.color_ramp = _make_gradient([
				[0.0, Color(1.0, 0.95, 0.85, 1.0)],
				[0.15, Color(1.0, 0.7, 0.3, 0.8)],
				[0.5, Color(1.0, 0.3, 0.1, 0.4)],
				[1.0, Color(0.4, 0.1, 0.0, 0.0)],
			])

	_preview.process_material = mat
	_preview.local_coords = true
	_preview.emitting = true

	# Soft billboard quad mesh
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = _create_soft_circle(16)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = emit_color
	mesh_mat.emission_energy_multiplier = emit_energy
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	_preview.draw_pass_1 = mesh

	add_child(_preview)


# =============================================================================
# HELPERS
# =============================================================================

func _get_color() -> Color:
	match point_type:
		PointType.ENGINE: return Color(0.0, 0.9, 1.0, 0.8)
		PointType.RCS:    return Color(1.0, 0.9, 0.2, 0.8)
		PointType.BOOST:  return Color(1.0, 0.5, 0.1, 0.8)
	return Color(0.0, 0.9, 1.0, 0.8)


func _type_name() -> StringName:
	match point_type:
		PointType.ENGINE: return &"ENGINE"
		PointType.RCS:    return &"RCS"
		PointType.BOOST:  return &"BOOST"
	return &"ENGINE"


func _build_label() -> String:
	return "VFX:%s" % _type_name()


func _make_unlit_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat


func _make_gradient(stops: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	var colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	for stop in stops:
		offsets.append(stop[0])
		colors.append(stop[1])
	grad.colors = colors
	grad.offsets = offsets
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _create_soft_circle(tex_size: int = 16) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = tex_size
	tex.height = tex_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.4),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	tex.gradient = grad
	return tex
