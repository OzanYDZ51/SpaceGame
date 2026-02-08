class_name MiningLaserBeam
extends Node3D

# =============================================================================
# Mining Laser Beam - Multi-layer energy beam visual
# Core beam (shader) + outer glow + impact sparks/light + source glow
# =============================================================================

const _BeamShader = preload("res://shaders/mining_beam.gdshader")

const BEAM_COLOR := Color(0.3, 1.0, 0.6)
const BEAM_COLOR_HOT := Color(0.6, 1.0, 0.8)
const CORE_RADIUS: float = 0.12
const GLOW_RADIUS: float = 0.5

var _core_mesh: MeshInstance3D = null
var _glow_mesh: MeshInstance3D = null
var _core_mat: ShaderMaterial = null
var _glow_mat: StandardMaterial3D = null

var _impact_light: OmniLight3D = null
var _source_light: OmniLight3D = null
var _impact_particles: GPUParticles3D = null
var _source_particles: GPUParticles3D = null

var _active: bool = false
var _pulse_t: float = 0.0
var _warmup: float = 0.0  # 0→1 over 0.4s for smooth activation


func _ready() -> void:
	_build_core_beam()
	_build_glow_beam()
	_build_impact_effects()
	_build_source_effects()


func _build_core_beam() -> void:
	_core_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = CORE_RADIUS
	cyl.bottom_radius = CORE_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	_core_mesh.mesh = cyl
	_core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_core_mat = ShaderMaterial.new()
	_core_mat.shader = _BeamShader
	_core_mat.set_shader_parameter("core_color", BEAM_COLOR)
	_core_mat.set_shader_parameter("edge_color", Color(0.1, 0.5, 0.3, 0.4))
	_core_mat.set_shader_parameter("scroll_speed", 3.0)
	_core_mat.set_shader_parameter("pulse_frequency", 12.0)
	_core_mat.set_shader_parameter("pulse_intensity", 0.6)
	_core_mat.set_shader_parameter("core_width", 0.3)
	_core_mat.set_shader_parameter("flicker_speed", 8.0)
	_core_mat.set_shader_parameter("energy_density", 6.0)
	_core_mat.set_shader_parameter("beam_intensity", 3.0)
	_core_mesh.material_override = _core_mat
	_core_mesh.visible = false
	add_child(_core_mesh)


func _build_glow_beam() -> void:
	_glow_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = GLOW_RADIUS
	cyl.bottom_radius = GLOW_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_glow_mesh.mesh = cyl
	_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_glow_mat = StandardMaterial3D.new()
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.08)
	_glow_mat.no_depth_test = true
	_glow_mesh.material_override = _glow_mat
	_glow_mesh.visible = false
	add_child(_glow_mesh)


func _build_impact_effects() -> void:
	# Impact light — pulsing green-teal
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = BEAM_COLOR
	_impact_light.light_energy = 3.0
	_impact_light.omni_range = 20.0
	_impact_light.omni_attenuation = 2.0
	_impact_light.visible = false
	add_child(_impact_light)

	# Impact sparks — debris flying off asteroid surface
	_impact_particles = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 50.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 12.0
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.0
	mat.damping_max = 5.0
	mat.scale_min = 0.3
	mat.scale_max = 1.2
	mat.color = BEAM_COLOR_HOT
	# Color ramp: bright at spawn → dim at death
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, BEAM_COLOR_HOT)
	grad.add_point(0.3, BEAM_COLOR)
	grad.set_color(grad.get_point_count() - 1, Color(0.1, 0.3, 0.2, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp
	_impact_particles.process_material = mat
	_impact_particles.amount = 20
	_impact_particles.lifetime = 0.6
	_impact_particles.explosiveness = 0.1
	_impact_particles.emitting = false

	# Particle mesh: small rock-like chunks
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.25, 0.15, 0.2)
	_impact_particles.draw_pass_1 = pmesh
	_impact_particles.visible = false
	add_child(_impact_particles)


func _build_source_effects() -> void:
	# Source glow light (at the hardpoint)
	_source_light = OmniLight3D.new()
	_source_light.light_color = BEAM_COLOR
	_source_light.light_energy = 1.5
	_source_light.omni_range = 8.0
	_source_light.omni_attenuation = 2.0
	_source_light.visible = false
	add_child(_source_light)

	# Source sparks — small energy discharge at emission point
	_source_particles = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 3.0
	mat.damping_max = 6.0
	mat.scale_min = 0.1
	mat.scale_max = 0.4
	mat.color = BEAM_COLOR_HOT
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 1.0, 0.9, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.2, 0.6, 0.4, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp
	_source_particles.process_material = mat
	_source_particles.amount = 8
	_source_particles.lifetime = 0.3
	_source_particles.emitting = false

	var pmesh := SphereMesh.new()
	pmesh.radius = 0.12
	pmesh.height = 0.24
	pmesh.radial_segments = 4
	pmesh.rings = 2
	_source_particles.draw_pass_1 = pmesh
	_source_particles.visible = false
	add_child(_source_particles)


func activate(source_pos: Vector3, target_pos: Vector3) -> void:
	_active = true
	_warmup = 0.0
	update_beam(source_pos, target_pos)
	_core_mesh.visible = true
	_glow_mesh.visible = true
	_impact_light.visible = true
	_source_light.visible = true
	_impact_particles.visible = true
	_impact_particles.emitting = true
	_source_particles.visible = true
	_source_particles.emitting = true


func deactivate() -> void:
	_active = false
	_warmup = 0.0
	_core_mesh.visible = false
	_glow_mesh.visible = false
	_impact_light.visible = false
	_source_light.visible = false
	_impact_particles.emitting = false
	_impact_particles.visible = false
	_source_particles.emitting = false
	_source_particles.visible = false


func update_beam(source_pos: Vector3, target_pos: Vector3) -> void:
	if not _active:
		return

	var direction: Vector3 = target_pos - source_pos
	var distance: float = direction.length()
	if distance < 0.1:
		return

	var midpoint: Vector3 = (source_pos + target_pos) * 0.5

	# Orient and scale both beam meshes
	_orient_beam(_core_mesh, midpoint, source_pos, target_pos, distance)
	_orient_beam(_glow_mesh, midpoint, source_pos, target_pos, distance)

	# Impact effects at target
	_impact_light.global_position = target_pos
	_impact_particles.global_position = target_pos
	# Orient particles away from beam direction
	var hit_dir: Vector3 = direction.normalized()
	if hit_dir.length_squared() > 0.01:
		_impact_particles.global_transform = Transform3D(
			Basis.looking_at(-hit_dir, Vector3.UP),
			target_pos
		)

	# Source effects at hardpoint
	_source_light.global_position = source_pos
	_source_particles.global_position = source_pos


func _orient_beam(mesh: MeshInstance3D, midpoint: Vector3, source: Vector3, target: Vector3, dist: float) -> void:
	mesh.global_position = midpoint
	mesh.scale = Vector3(1.0, dist, 1.0)

	var up := (target - source).normalized()
	if abs(up.dot(Vector3.UP)) > 0.999:
		mesh.global_transform = Transform3D(Basis.looking_at(-up, Vector3.RIGHT), midpoint)
		mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		mesh.look_at_from_position(midpoint, target, Vector3.UP)
		mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mesh.scale = Vector3(1.0, dist, 1.0)


func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_t += delta

	# Warmup ramp (0→1 over 0.4s) for smooth beam appear
	_warmup = minf(_warmup + delta / 0.4, 1.0)
	var warmup_ease: float = _warmup * _warmup * (3.0 - 2.0 * _warmup)  # smoothstep

	# Beam intensity modulation
	var intensity: float = warmup_ease * (2.5 + sin(_pulse_t * 6.0) * 0.8)
	_core_mat.set_shader_parameter("beam_intensity", intensity)

	# Glow pulse
	var glow_alpha: float = warmup_ease * (0.06 + sin(_pulse_t * 4.0) * 0.03)
	_glow_mat.albedo_color.a = glow_alpha

	# Impact light flicker
	_impact_light.light_energy = warmup_ease * (2.5 + sin(_pulse_t * 8.0) * 1.2 + sin(_pulse_t * 13.0) * 0.5)

	# Source light softer pulse
	_source_light.light_energy = warmup_ease * (1.2 + sin(_pulse_t * 5.0) * 0.4)
