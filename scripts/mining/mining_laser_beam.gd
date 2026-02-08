class_name MiningLaserBeam
extends Node3D

# =============================================================================
# Mining Laser Beam - Visual beam between ship and asteroid
# CylinderMesh stretched dynamically, impact particles + light
# =============================================================================

var _beam_mesh: MeshInstance3D = null
var _beam_mat: StandardMaterial3D = null
var _impact_light: OmniLight3D = null
var _impact_particles: GPUParticles3D = null
var _active: bool = false
var _pulse_t: float = 0.0

const BEAM_COLOR := Color(0.2, 1.0, 0.5)
const BEAM_RADIUS: float = 0.15


func _ready() -> void:
	# Beam mesh (cylinder)
	_beam_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_RADIUS
	cyl.bottom_radius = BEAM_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_beam_mesh.mesh = cyl
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = BEAM_COLOR
	_beam_mat.emission_enabled = true
	_beam_mat.emission = BEAM_COLOR
	_beam_mat.emission_energy_multiplier = 3.0
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color.a = 0.8
	_beam_mesh.material_override = _beam_mat
	_beam_mesh.visible = false
	add_child(_beam_mesh)

	# Impact light
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = BEAM_COLOR
	_impact_light.light_energy = 2.0
	_impact_light.omni_range = 15.0
	_impact_light.omni_attenuation = 2.0
	_impact_light.visible = false
	add_child(_impact_light)

	# Impact particles
	_impact_particles = GPUParticles3D.new()
	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 60.0
	particle_mat.initial_velocity_min = 2.0
	particle_mat.initial_velocity_max = 8.0
	particle_mat.gravity = Vector3.ZERO
	particle_mat.scale_min = 0.3
	particle_mat.scale_max = 1.0
	particle_mat.color = BEAM_COLOR
	_impact_particles.process_material = particle_mat
	_impact_particles.amount = 12
	_impact_particles.lifetime = 0.5
	_impact_particles.emitting = false
	# Small sphere mesh for particles
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.2
	particle_mesh.height = 0.4
	particle_mesh.radial_segments = 4
	particle_mesh.rings = 2
	_impact_particles.draw_pass_1 = particle_mesh
	_impact_particles.visible = false
	add_child(_impact_particles)


func activate(source_pos: Vector3, target_pos: Vector3) -> void:
	_active = true
	update_beam(source_pos, target_pos)
	_beam_mesh.visible = true
	_impact_light.visible = true
	_impact_particles.visible = true
	_impact_particles.emitting = true


func deactivate() -> void:
	_active = false
	_beam_mesh.visible = false
	_impact_light.visible = false
	_impact_particles.emitting = false
	_impact_particles.visible = false


func update_beam(source_pos: Vector3, target_pos: Vector3) -> void:
	if not _active:
		return

	var direction: Vector3 = target_pos - source_pos
	var distance: float = direction.length()
	if distance < 0.1:
		return

	var midpoint: Vector3 = (source_pos + target_pos) * 0.5

	# Scale cylinder to match distance
	_beam_mesh.global_position = midpoint
	_beam_mesh.scale = Vector3(1.0, distance, 1.0)

	# Orient cylinder along beam direction
	var up := direction.normalized()
	if abs(up.dot(Vector3.UP)) > 0.999:
		_beam_mesh.global_transform = Transform3D(Basis.looking_at(-up, Vector3.RIGHT), midpoint)
		_beam_mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		_beam_mesh.look_at_from_position(midpoint, target_pos, Vector3.UP)
		_beam_mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	# Impact at target
	_impact_light.global_position = target_pos
	_impact_particles.global_position = target_pos


func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_t += delta
	# Pulsing emission
	var pulse: float = 2.5 + sin(_pulse_t * 8.0) * 1.0
	_beam_mat.emission_energy_multiplier = pulse
	_impact_light.light_energy = 1.5 + sin(_pulse_t * 6.0) * 0.8
