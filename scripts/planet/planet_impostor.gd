class_name PlanetImpostor
extends Node3D

# =============================================================================
# Planet Impostor — Visible sphere at clamped distance from camera
# Same pattern as SystemStar: NOT child of Universe, follows camera direction
# to the planet's true position. Scale = angular size at true distance.
# Uses procedural ShaderMaterial for per-type planet surfaces (PBR).
# Includes atmosphere glow ring and optional planetary rings.
# =============================================================================

const IMPOSTOR_DISTANCE: float = 4500.0
const MIN_VISUAL_RADIUS: float = 5.0
const MAX_VISUAL_RADIUS: float = 4400.0  # 98% of IMPOSTOR_DISTANCE — camera stays 100m outside sphere

var planet_data: PlanetData = null
var planet_index: int = 0
var entity_id: String = ""  # EntityRegistry key, e.g. "planet_0"

var _render_radius: float = 50_000.0  # meters

var _mesh_instance: MeshInstance3D = null
var _surface_material: ShaderMaterial = null
var _ring_instance: MeshInstance3D = null
var _ring_material: ShaderMaterial = null

# Fade for LOD transition (Phase B: impostor fades out when PlanetBody spawns)
var fade_alpha: float = 1.0


func setup(pd: PlanetData, index: int, ent_id: String) -> void:
	planet_data = pd
	planet_index = index
	entity_id = ent_id
	# Impostor uses the REAL terrain radius — same size as PlanetBody.
	# No visual_scale: what you see from space = what you land on.
	_render_radius = pd.get_render_radius()
	_build_visuals()


func _build_visuals() -> void:
	# Planet sphere — procedural PBR shader lit by the star's DirectionalLight
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 48
	mesh.rings = 24

	var surface_shader := preload("res://shaders/planet/planet_impostor_surface.gdshader")
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = surface_shader
	_surface_material.set_shader_parameter("planet_type", planet_data.type as int)
	_surface_material.set_shader_parameter("planet_color", planet_data.color)
	_surface_material.set_shader_parameter("planet_seed", float(planet_index * 137 + 42))

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _surface_material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	# Atmosphere glow — only for rocky/ocean/ice (not gas giants, their surface IS atmosphere)
	# Only used on PlanetBody when close. Impostor relies on PBR lighting alone
	# to avoid visible mesh boundary halos from space.
	pass

	# Planetary rings (gas giants with has_rings)
	if planet_data.has_rings:
		_create_rings()


func _create_rings() -> void:
	var ring_mesh := PlanetRingMesh.create(1.3, 2.2, 128)

	var ring_shader := preload("res://shaders/planet/planet_rings.gdshader")
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = ring_shader
	_ring_material.set_shader_parameter("ring_color", planet_data.color)
	_ring_material.set_shader_parameter("ring_seed", float(planet_index * 73 + 19))

	_ring_instance = MeshInstance3D.new()
	_ring_instance.mesh = ring_mesh
	_ring_instance.material_override = _ring_material
	_ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_instance)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position

	# Read true universe position from EntityRegistry (updated by orbital mechanics)
	var pos: Array = EntityRegistry.get_position(entity_id)
	var true_pos_x: float = pos[0]
	var true_pos_y: float = pos[1]
	var true_pos_z: float = pos[2]

	# Compute distance in float64 to avoid precision loss at large distances.
	# Vector3 is float32 — at 100 Mm the growth per frame is sub-pixel in float32.
	var player_upos: Array = FloatingOrigin.to_universe_pos(cam_pos)
	var dx: float = true_pos_x - player_upos[0]
	var dy: float = true_pos_y - player_upos[1]
	var dz: float = true_pos_z - player_upos[2]
	var actual_distance: float = sqrt(dx * dx + dy * dy + dz * dz)

	if actual_distance < 1.0:
		global_position = cam_pos + Vector3(0, 0, -IMPOSTOR_DISTANCE)
		_mesh_instance.scale = Vector3.ONE * MIN_VISUAL_RADIUS
		return

	# Direction in local coords (float32 fine for direction vector)
	var planet_local := Vector3(
		float(true_pos_x) - float(FloatingOrigin.origin_offset_x),
		float(true_pos_y) - float(FloatingOrigin.origin_offset_y),
		float(true_pos_z) - float(FloatingOrigin.origin_offset_z)
	)
	var to_planet := planet_local - cam_pos
	var direction := to_planet.normalized()

	# Scale based on angular size: visual_radius = IMPOSTOR_DISTANCE * render_radius / distance
	# Clamped so camera never enters the sphere (MAX_VISUAL_RADIUS < IMPOSTOR_DISTANCE).
	var visual_radius: float = IMPOSTOR_DISTANCE * _render_radius / actual_distance
	visual_radius = clampf(visual_radius, MIN_VISUAL_RADIUS, MAX_VISUAL_RADIUS)

	# Position impostor at fixed distance from camera toward planet
	global_position = cam_pos + direction * IMPOSTOR_DISTANCE
	_mesh_instance.scale = Vector3.ONE * visual_radius

	# Compute sun direction (star at universe origin)
	var star_local := Vector3(
		-float(FloatingOrigin.origin_offset_x),
		-float(FloatingOrigin.origin_offset_y),
		-float(FloatingOrigin.origin_offset_z)
	)
	var sun_dir := (star_local - planet_local).normalized()

	# Pass sun direction to surface shader
	_surface_material.set_shader_parameter("sun_direction", sun_dir)

	# Rings scale with planet
	if _ring_instance:
		_ring_instance.scale = Vector3.ONE * visual_radius
		if _ring_material:
			_ring_material.set_shader_parameter("sun_direction", sun_dir)

	# Apply fade (for LOD transition)
	if fade_alpha < 1.0:
		visible = fade_alpha > 0.01
