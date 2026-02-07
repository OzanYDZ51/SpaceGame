class_name ExplosionEffect
extends Node3D

# =============================================================================
# Explosion Effect - Sci-fi energy impact
# Flash + core glow sphere + spark burst + lingering embers + shockwave ring
# Everything built in code for full control. Auto-frees after effect ends.
# =============================================================================

var _flash_light: OmniLight3D = null
var _core_mesh: MeshInstance3D = null
var _core_mat: StandardMaterial3D = null
var _sparks: GPUParticles3D = null
var _embers: GPUParticles3D = null
var _shockwave_mesh: MeshInstance3D = null
var _shockwave_mat: StandardMaterial3D = null

var _age: float = 0.0
var _flash_energy: float = 0.0

const DURATION: float = 1.5
const FLASH_PEAK: float = 12.0
const FLASH_RANGE: float = 60.0
const CORE_SIZE: float = 2.5
const SHOCKWAVE_MAX_RADIUS: float = 8.0


func _ready() -> void:
	_create_flash()
	_create_core_glow()
	_create_sparks()
	_create_embers()
	_create_shockwave()


func _process(delta: float) -> void:
	_age += delta

	if _age >= DURATION:
		queue_free()
		return

	var t: float = _age / DURATION  # 0 → 1

	# === Flash: bright spike then fast decay ===
	if _flash_light:
		if t < 0.05:
			_flash_energy = FLASH_PEAK * (t / 0.05)
		else:
			_flash_energy = FLASH_PEAK * max(0.0, 1.0 - (t - 0.05) * 4.0)
		_flash_light.light_energy = _flash_energy
		# Color shifts from white-hot to orange to nothing
		var color_t: float = clamp(t * 5.0, 0.0, 1.0)
		_flash_light.light_color = Color(1.0, lerp(0.95, 0.4, color_t), lerp(0.8, 0.1, color_t))

	# === Core glow: expand then shrink + fade ===
	if _core_mesh:
		var core_scale: float
		if t < 0.1:
			core_scale = CORE_SIZE * (t / 0.1)
		else:
			core_scale = CORE_SIZE * max(0.0, 1.0 - (t - 0.1) * 1.5)
		_core_mesh.scale = Vector3.ONE * max(core_scale, 0.01)

		if _core_mat:
			var alpha: float = 1.0 - t * 1.2
			_core_mat.albedo_color.a = clamp(alpha, 0.0, 1.0)
			var emit_energy: float = 10.0 * max(0.0, 1.0 - t * 2.0)
			_core_mat.emission_energy_multiplier = emit_energy

	# === Shockwave ring: expand + fade ===
	if _shockwave_mesh:
		var ring_t: float = clamp(t * 3.0, 0.0, 1.0)
		var ring_scale: float = SHOCKWAVE_MAX_RADIUS * ring_t
		_shockwave_mesh.scale = Vector3(ring_scale, ring_scale, ring_scale).max(Vector3.ONE * 0.01)
		if _shockwave_mat:
			_shockwave_mat.albedo_color.a = clamp(1.0 - ring_t, 0.0, 0.8)


func _create_flash() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.9, 0.7)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = FLASH_RANGE
	_flash_light.omni_attenuation = 1.5
	add_child(_flash_light)


func _create_core_glow() -> void:
	_core_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_core_mesh.mesh = sphere

	_core_mat = StandardMaterial3D.new()
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.albedo_color = Color(1.0, 0.8, 0.4, 1.0)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.6, 0.2)
	_core_mat.emission_energy_multiplier = 10.0
	_core_mat.no_depth_test = true
	_core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_mesh.material_override = _core_mat
	_core_mesh.scale = Vector3.ONE * 0.01
	add_child(_core_mesh)


func _create_sparks() -> void:
	_sparks = GPUParticles3D.new()
	_sparks.emitting = true
	_sparks.one_shot = true
	_sparks.amount = 32
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 1.0
	_sparks.randomness = 0.3

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(0, -5.0, 0)
	mat.damping_min = 5.0
	mat.damping_max = 15.0
	mat.scale_min = 0.3
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.8, 0.3, 1.0)

	# Color ramp: bright yellow → orange → fade out
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	gradient.add_point(0.3, Color(1.0, 0.5, 0.15, 0.9))
	gradient.add_point(0.7, Color(0.8, 0.2, 0.05, 0.5))
	gradient.set_color(1, Color(0.3, 0.05, 0.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_sparks.process_material = mat

	# Spark mesh: tiny stretched box
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.1, 0.1, 0.5)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.albedo_color = Color(1.0, 0.9, 0.5, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.7, 0.3)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mesh.material = spark_mat
	_sparks.draw_pass_1 = spark_mesh

	add_child(_sparks)


func _create_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.emitting = true
	_embers.one_shot = true
	_embers.amount = 16
	_embers.lifetime = 1.2
	_embers.explosiveness = 0.9
	_embers.randomness = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 20.0
	mat.gravity = Vector3(0, 2.0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.scale_min = 0.5
	mat.scale_max = 2.0

	# Color ramp: orange embers → fade
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.6, 0.2, 0.8))
	gradient.add_point(0.5, Color(0.6, 0.15, 0.05, 0.5))
	gradient.set_color(1, Color(0.2, 0.02, 0.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_embers.process_material = mat

	# Ember mesh: small glowing sphere
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.2
	ember_mesh.height = 0.4
	ember_mesh.radial_segments = 6
	ember_mesh.rings = 3
	var ember_mat := StandardMaterial3D.new()
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.albedo_color = Color(1.0, 0.5, 0.15, 0.9)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.4, 0.1)
	ember_mat.emission_energy_multiplier = 4.0
	ember_mesh.material = ember_mat
	_embers.draw_pass_1 = ember_mesh

	add_child(_embers)


func _create_shockwave() -> void:
	_shockwave_mesh = MeshInstance3D.new()

	# Torus-like ring using a thin cylinder
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.15
	ring.radial_segments = 24
	_shockwave_mesh.mesh = ring

	_shockwave_mat = StandardMaterial3D.new()
	_shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.6)
	_shockwave_mat.emission_enabled = true
	_shockwave_mat.emission = Color(0.3, 0.6, 1.0)
	_shockwave_mat.emission_energy_multiplier = 3.0
	_shockwave_mat.no_depth_test = true
	_shockwave_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_shockwave_mesh.material_override = _shockwave_mat
	_shockwave_mesh.scale = Vector3.ONE * 0.01
	add_child(_shockwave_mesh)
