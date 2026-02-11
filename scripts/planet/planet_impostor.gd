class_name PlanetImpostor
extends Node3D

# =============================================================================
# Planet Impostor — Visible sphere at clamped distance from camera
# Same pattern as SystemStar: NOT child of Universe, follows camera direction
# to the planet's true position. Scale = angular size at true distance.
# Uses PBR shading so the star's DirectionalLight illuminates it realistically.
# Includes atmosphere glow ring.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 4500.0
const MIN_VISUAL_RADIUS: float = 5.0
const MAX_VISUAL_RADIUS: float = 1500.0

var planet_data: PlanetData = null
var planet_index: int = 0
var entity_id: String = ""  # EntityRegistry key, e.g. "planet_0"

var _render_radius: float = 50_000.0  # meters

var _mesh_instance: MeshInstance3D = null
var _atmo_mesh: MeshInstance3D = null
var _atmo_config: AtmosphereConfig = null
var _material: StandardMaterial3D = null

var _last_cam_pos: Vector3 = Vector3(INF, INF, INF)
var _last_origin_x: float = INF
var _last_origin_y: float = INF
var _last_origin_z: float = INF

# Fade for LOD transition (Phase B: impostor fades out when PlanetBody spawns)
var fade_alpha: float = 1.0


func setup(pd: PlanetData, index: int, ent_id: String) -> void:
	planet_data = pd
	planet_index = index
	entity_id = ent_id
	# Visual radius for impostor is much larger than terrain render_radius
	# so planets look impressive from orbital distances (Star Citizen style).
	# Terrain radius stays the same for actual landing.
	_render_radius = pd.get_render_radius() * pd.get_visual_scale()
	_atmo_config = AtmosphereConfig.from_planet_data(pd)
	_build_visuals()


func _build_visuals() -> void:
	# Planet sphere — PBR lit by the star's DirectionalLight
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 48
	mesh.rings = 24

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.albedo_color = planet_data.color
	_material.roughness = 0.75
	_material.metallic = 0.0

	# Slight emission so planets aren't totally black on the dark side
	_material.emission_enabled = true
	_material.emission = planet_data.color * 0.05
	_material.emission_energy_multiplier = 0.3

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	# Atmosphere glow sphere (slightly larger)
	if _atmo_config and _atmo_config.density > 0.01:
		var atmo_mesh := SphereMesh.new()
		atmo_mesh.radius = 1.0
		atmo_mesh.height = 2.0
		atmo_mesh.radial_segments = 48
		atmo_mesh.rings = 24

		var atmo_shader := preload("res://shaders/planet/planet_atmosphere.gdshader")
		var atmo_mat := ShaderMaterial.new()
		atmo_mat.shader = atmo_shader
		atmo_mat.set_shader_parameter("glow_color", _atmo_config.glow_color)
		atmo_mat.set_shader_parameter("glow_intensity", _atmo_config.glow_intensity)
		atmo_mat.set_shader_parameter("glow_falloff", _atmo_config.glow_falloff)
		atmo_mat.set_shader_parameter("atmosphere_density", _atmo_config.density)

		_atmo_mesh = MeshInstance3D.new()
		_atmo_mesh.mesh = atmo_mesh
		_atmo_mesh.material_override = atmo_mat
		_atmo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_atmo_mesh)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	# Skip update if nothing changed (camera + all 3 origin axes)
	var origin_changed: bool = FloatingOrigin.origin_offset_x != _last_origin_x \
		or FloatingOrigin.origin_offset_y != _last_origin_y \
		or FloatingOrigin.origin_offset_z != _last_origin_z
	if cam_pos.distance_squared_to(_last_cam_pos) < 1.0 and not origin_changed:
		return
	_last_cam_pos = cam_pos
	_last_origin_x = FloatingOrigin.origin_offset_x
	_last_origin_y = FloatingOrigin.origin_offset_y
	_last_origin_z = FloatingOrigin.origin_offset_z

	# Read true universe position from EntityRegistry (updated by orbital mechanics)
	var pos: Array = EntityRegistry.get_position(entity_id)
	var true_pos_x: float = pos[0]
	var true_pos_y: float = pos[1]
	var true_pos_z: float = pos[2]

	# True planet position in scene coords
	var planet_local := Vector3(
		float(true_pos_x) - float(FloatingOrigin.origin_offset_x),
		float(true_pos_y) - float(FloatingOrigin.origin_offset_y),
		float(true_pos_z) - float(FloatingOrigin.origin_offset_z)
	)

	var to_planet := planet_local - cam_pos
	var actual_distance := to_planet.length()

	if actual_distance < 0.01:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		return

	var direction := to_planet / actual_distance

	# Position impostor at clamped distance
	global_position = cam_pos + direction * IMPOSTOR_DISTANCE

	# Scale based on angular size: visual_size = IMPOSTOR_DISTANCE * real_size / real_distance
	var visual_radius: float = IMPOSTOR_DISTANCE * _render_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Atmosphere is slightly larger
	if _atmo_mesh:
		_atmo_mesh.scale = Vector3.ONE * visual_radius * _atmo_config.atmosphere_scale

	# Apply fade (for LOD transition)
	if fade_alpha < 1.0:
		_material.albedo_color.a = fade_alpha
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade_alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
		visible = fade_alpha > 0.01
