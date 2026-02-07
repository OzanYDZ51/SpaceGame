class_name SystemStar
extends Node3D

# =============================================================================
# System Star Impostor
# Renders a visual star at a clamped distance from the camera to avoid
# float32 jitter at real orbital distances. Tracks the star's true direction
# and scales based on angular size.
# NOT a child of Universe — doesn't get shifted by FloatingOrigin.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 5000.0
const MIN_VISUAL_RADIUS: float = 20.0
const MAX_VISUAL_RADIUS: float = 300.0

var _star_color: Color = Color(1.0, 0.95, 0.7)
var _star_radius: float = 696340.0 * 100.0  # default ~Sun size in game meters
var _star_luminosity: float = 1.0

var _mesh_instance: MeshInstance3D = null
var _light: OmniLight3D = null


func setup(star_color: Color, star_radius: float, star_luminosity: float) -> void:
	_star_color = star_color
	_star_radius = star_radius
	_star_luminosity = star_luminosity
	_build_visuals()


func _build_visuals() -> void:
	# Sphere mesh
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 32
	mesh.rings = 16

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _star_color
	mat.emission_enabled = true
	mat.emission = _star_color
	mat.emission_energy_multiplier = clampf(3.0 + _star_luminosity * 0.5, 3.0, 8.0)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	# Glow light
	_light = OmniLight3D.new()
	_light.light_color = _star_color
	_light.light_energy = clampf(_star_luminosity * 0.3, 0.2, 2.0)
	_light.omni_range = 800.0
	_light.omni_attenuation = 1.5
	_light.shadow_enabled = false
	add_child(_light)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# True star position in local scene coords is always at (0,0,0) minus FloatingOrigin offset.
	# Star universe pos is (0,0,0). Local pos = universe_pos - origin_offset.
	var star_local := Vector3(
		-FloatingOrigin.origin_offset_x,
		-FloatingOrigin.origin_offset_y,
		-FloatingOrigin.origin_offset_z
	)

	var cam_pos := cam.global_position
	var to_star := star_local - cam_pos
	var actual_distance := to_star.length()

	if actual_distance < 0.01:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		return

	var direction := to_star / actual_distance

	# Position impostor at clamped distance along the direction
	global_position = cam_pos + direction * IMPOSTOR_DISTANCE

	# Scale based on angular size: visual_radius = IMPOSTOR_DISTANCE * actual_radius / actual_distance
	var visual_radius: float = IMPOSTOR_DISTANCE * _star_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Light stays at impostor position (already parented)
