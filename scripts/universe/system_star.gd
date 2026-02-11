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
# Uses procedural animated shaders: star_surface (granulation + sunspots)
# + star_corona (additive glow halo).
# Distance computed in float64 to avoid jitter at large orbital distances.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 5000.0
const MIN_VISUAL_RADIUS: float = 30.0
const MAX_VISUAL_RADIUS: float = 1200.0
const CORONA_SCALE: float = 1.35  # Corona sphere relative to star

var _star_color: Color = Color(1.0, 0.95, 0.7)
var _star_radius: float = 696340.0 * 100.0  # default ~Sun size in game meters
var _star_luminosity: float = 1.0

var _mesh_instance: MeshInstance3D = null
var _corona_instance: MeshInstance3D = null
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
	# --- Star surface mesh (procedural shader) ---
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 32
	mesh.rings = 16

	var surface_shader := preload("res://shaders/planet/star_surface.gdshader")
	var surface_mat := ShaderMaterial.new()
	surface_mat.shader = surface_shader
	surface_mat.set_shader_parameter("star_color", _star_color)
	surface_mat.set_shader_parameter("emission_energy", clampf(2.5 + _star_luminosity * 0.5, 2.5, 6.0))

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = surface_mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	# --- Corona mesh (larger, additive glow) ---
	var corona_mesh := SphereMesh.new()
	corona_mesh.radius = 1.0
	corona_mesh.height = 2.0
	corona_mesh.radial_segments = 24
	corona_mesh.rings = 12

	var corona_shader := preload("res://shaders/planet/star_corona.gdshader")
	var corona_mat := ShaderMaterial.new()
	corona_mat.shader = corona_shader
	corona_mat.set_shader_parameter("corona_color", _star_color)
	corona_mat.set_shader_parameter("corona_intensity", clampf(1.0 + _star_luminosity * 0.3, 1.0, 3.0))

	_corona_instance = MeshInstance3D.new()
	_corona_instance.mesh = corona_mesh
	_corona_instance.material_override = corona_mat
	_corona_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_corona_instance)


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

	# Star is at universe (0,0,0) — compute distance in float64 to avoid jitter
	var player_upos: Array = FloatingOrigin.to_universe_pos(cam_pos)
	var dx: float = -player_upos[0]  # star at (0,0,0) minus player
	var dy: float = -player_upos[1]
	var dz: float = -player_upos[2]
	var actual_distance: float = sqrt(dx * dx + dy * dy + dz * dz)

	if actual_distance < 1.0:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		if _corona_instance:
			_corona_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS * CORONA_SCALE
		return

	# Direction in local float32 coords (fine for direction vector)
	var star_local := Vector3(
		-float(FloatingOrigin.origin_offset_x),
		-float(FloatingOrigin.origin_offset_y),
		-float(FloatingOrigin.origin_offset_z)
	)
	var to_star := star_local - cam_pos
	var dir_to_star := to_star.normalized()

	# Position impostor at clamped distance along the direction
	global_position = cam_pos + dir_to_star * IMPOSTOR_DISTANCE

	# Scale based on angular size (using float64 distance for stability)
	var visual_radius: float = IMPOSTOR_DISTANCE * _star_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Corona is slightly larger
	if _corona_instance:
		_corona_instance.scale = Vector3.ONE * visual_radius * CORONA_SCALE

	# Sun direction for lighting = from star toward scene origin (0,0,0).
	# Use scene origin (not camera) so the light doesn't shift when the camera rotates.
	var sun_dir := -star_local.normalized()
	if sun_dir.distance_squared_to(_last_sun_dir) > 0.0001:
		_last_sun_dir = sun_dir
		var main := GameManager.main_scene
		if main is SpaceEnvironment:
			(main as SpaceEnvironment).update_sun_direction(sun_dir)
