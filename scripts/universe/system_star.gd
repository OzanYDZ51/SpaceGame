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
#
# Procedural animated surface shader (granulation + sunspots + limb darkening).
# No corona mesh — HDR emission + engine bloom handles the glow naturally.
# Distance computed in float64 to avoid jitter at large orbital distances.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 5000.0
const MIN_VISUAL_RADIUS: float = 30.0
const MAX_VISUAL_RADIUS: float = 4900.0  # 98% of IMPOSTOR_DISTANCE — camera stays outside sphere

var _star_color: Color = Color(1.0, 0.95, 0.7)
var _star_radius: float = 696340.0  # default ~Sun size in game meters (~696 km)
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
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 32
	mesh.rings = 16

	var surface_shader := preload("res://shaders/planet/star_surface.gdshader")
	var surface_mat := ShaderMaterial.new()
	surface_mat.shader = surface_shader
	surface_mat.set_shader_parameter("star_color", _star_color)
	# High emission for realistic HDR bloom/glare — the star should be blinding
	surface_mat.set_shader_parameter("emission_energy", clampf(6.0 + _star_luminosity * 2.0, 6.0, 15.0))

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = surface_mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	var origin_changed: bool = FloatingOrigin.origin_offset_x != _last_origin_x \
		or FloatingOrigin.origin_offset_y != _last_origin_y \
		or FloatingOrigin.origin_offset_z != _last_origin_z
	if cam_pos.distance_squared_to(_last_cam_pos) < 1.0 and not origin_changed:
		return
	_last_cam_pos = cam_pos
	_last_origin_x = FloatingOrigin.origin_offset_x
	_last_origin_y = FloatingOrigin.origin_offset_y
	_last_origin_z = FloatingOrigin.origin_offset_z

	# Star is at universe (0,0,0) — compute distance in float64 to avoid jitter
	var player_upos: Array = FloatingOrigin.to_universe_pos(cam_pos)
	var dx: float = -player_upos[0]
	var dy: float = -player_upos[1]
	var dz: float = -player_upos[2]
	var actual_distance: float = sqrt(dx * dx + dy * dy + dz * dz)

	if actual_distance < 1.0:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		return

	# Direction in local float32 coords (fine for direction vector)
	var star_local := Vector3(
		-float(FloatingOrigin.origin_offset_x),
		-float(FloatingOrigin.origin_offset_y),
		-float(FloatingOrigin.origin_offset_z)
	)
	var dir_to_star := (star_local - cam_pos).normalized()

	global_position = cam_pos + dir_to_star * IMPOSTOR_DISTANCE

	var visual_radius: float = IMPOSTOR_DISTANCE * _star_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Sun direction for lighting — convention: direction TOWARD the sun
	# (skybox god rays need dot(EYEDIR, sun_dir) > 0 when looking at star)
	var sun_dir := dir_to_star
	if sun_dir.distance_squared_to(_last_sun_dir) > 0.0001:
		_last_sun_dir = sun_dir
		var main := GameManager.main_scene
		if main is SpaceEnvironment:
			(main as SpaceEnvironment).update_sun_direction(sun_dir)
