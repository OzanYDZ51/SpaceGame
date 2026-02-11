class_name SystemStar
extends Node3D

# =============================================================================
# System Star Impostor
# Renders a visual star at a clamped distance from the camera to avoid
# float32 jitter at real orbital distances. Tracks the star's true direction
# and scales based on angular size.
# NOT a child of Universe — doesn't get shifted by FloatingOrigin.
# Updates DirectionalLight3D direction in SpaceEnvironment each frame so the
# star actually lights planets and ships from the correct direction.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 5000.0
const MIN_VISUAL_RADIUS: float = 20.0
const MAX_VISUAL_RADIUS: float = 300.0

var _star_color: Color = Color(1.0, 0.95, 0.7)
var _star_radius: float = 696340.0 * 100.0  # default ~Sun size in game meters
var _star_luminosity: float = 1.0

var _mesh_instance: MeshInstance3D = null
var _last_cam_pos: Vector3 = Vector3(INF, INF, INF)
var _last_origin_x: float = INF
var _last_origin_y: float = INF
var _last_origin_z: float = INF
var _last_sun_dir: Vector3 = Vector3.ZERO


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
	mesh.radial_segments = 16
	mesh.rings = 8

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _star_color
	mat.emission_enabled = true
	mat.emission = _star_color
	mat.emission_energy_multiplier = clampf(2.0 + _star_luminosity * 0.3, 2.0, 5.0)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	# Skip update if camera and origin haven't changed meaningfully
	var origin_changed: bool = FloatingOrigin.origin_offset_x != _last_origin_x \
		or FloatingOrigin.origin_offset_y != _last_origin_y \
		or FloatingOrigin.origin_offset_z != _last_origin_z
	if cam_pos.distance_squared_to(_last_cam_pos) < 1.0 and not origin_changed:
		return
	_last_cam_pos = cam_pos
	_last_origin_x = FloatingOrigin.origin_offset_x
	_last_origin_y = FloatingOrigin.origin_offset_y
	_last_origin_z = FloatingOrigin.origin_offset_z

	# Star is at universe (0,0,0) — its scene position relative to world origin
	var star_local := Vector3(
		-FloatingOrigin.origin_offset_x,
		-FloatingOrigin.origin_offset_y,
		-FloatingOrigin.origin_offset_z
	)

	# Direction from camera to star (for impostor placement)
	var to_star := star_local - cam_pos
	var actual_distance := to_star.length()

	if actual_distance < 0.01:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		return

	var dir_to_star := to_star / actual_distance

	# Position impostor at clamped distance along the direction
	global_position = cam_pos + dir_to_star * IMPOSTOR_DISTANCE

	# Scale based on angular size
	var visual_radius: float = IMPOSTOR_DISTANCE * _star_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Sun direction for lighting = from star toward scene origin (0,0,0).
	# Use scene origin (not camera) so the light doesn't shift when the camera rotates.
	# star_local points from origin to star, so -star_local.normalized() = from star to origin.
	var sun_dir := -star_local.normalized()
	if sun_dir.distance_squared_to(_last_sun_dir) > 0.0001:
		_last_sun_dir = sun_dir
		var main := GameManager.main_scene
		if main is SpaceEnvironment:
			(main as SpaceEnvironment).update_sun_direction(sun_dir)
