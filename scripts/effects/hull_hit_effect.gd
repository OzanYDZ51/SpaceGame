class_name HullHitEffect
extends Node3D

# =============================================================================
# Hull Hit Effect - Realistic impact when projectile hits unshielded hull
# Directional sparks, metal debris, scorch glow, smoke wisps.
# No gravity (space). Scales with projectile damage via intensity param.
# =============================================================================

const DURATION: float = 1.2

var _age: float = 0.0
var _intensity: float = 1.0
var _flash: OmniLight3D = null
var _scorch: MeshInstance3D = null
var _scorch_mat: StandardMaterial3D = null


func setup(hit_normal: Vector3, intensity: float = 1.0) -> void:
	_intensity = clampf(intensity, 0.5, 3.0)
	if hit_normal.length_squared() < 0.01:
		hit_normal = Vector3.UP
	hit_normal = hit_normal.normalized()

	_create_flash()
	_create_scorch()
	_create_sparks(hit_normal)
	_create_debris(hit_normal)
	_create_smoke(hit_normal)


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return

	var t := _age / DURATION

	# Flash: sharp spike then fast decay
	if _flash:
		var flash_t := _age * 6.0
		if flash_t < 1.0:
			_flash.light_energy = lerpf(0.0, 10.0 * _intensity, flash_t)
		else:
			_flash.light_energy = 10.0 * _intensity * maxf(0.0, 1.0 - (flash_t - 1.0) * 1.5)
		var ct := minf(t * 4.0, 1.0)
		_flash.light_color = Color(1.0, lerpf(0.95, 0.35, ct), lerpf(0.8, 0.05, ct))

	# Scorch glow: bright start, slow fade
	if _scorch and _scorch_mat:
		var scorch_peak := 1.2 * sqrt(_intensity)
		var scorch_scale: float
		if t < 0.08:
			scorch_scale = lerpf(0.01, scorch_peak, t / 0.08)
		else:
			scorch_scale = lerpf(scorch_peak, 0.1, (t - 0.08) / 0.92)
		_scorch.scale = Vector3.ONE * maxf(scorch_scale, 0.01)
		_scorch_mat.albedo_color.a = clampf(1.0 - t * 1.5, 0.0, 1.0)
		_scorch_mat.emission_energy_multiplier = 8.0 * maxf(0.0, 1.0 - t * 2.0)


func _create_flash() -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.9, 0.7)
	_flash.light_energy = 0.0
	_flash.omni_range = 30.0 * sqrt(_intensity)
	_flash.omni_attenuation = 1.2
	_flash.shadow_enabled = false
	add_child(_flash)


func _create_scorch() -> void:
	_scorch = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	_scorch.mesh = sphere

	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.albedo_color = Color(1.0, 0.7, 0.3, 1.0)
	_scorch_mat.emission_enabled = true
	_scorch_mat.emission = Color(1.0, 0.5, 0.15)
	_scorch_mat.emission_energy_multiplier = 8.0
	_scorch_mat.no_depth_test = true
	_scorch_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_scorch.material_override = _scorch_mat
	_scorch.scale = Vector3.ONE * 0.01
	_scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_scorch)


func _create_sparks(hit_normal: Vector3) -> void:
	var sparks := GPUParticles3D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.amount = int(randf_range(18.0, 28.0) * _intensity)
	sparks.lifetime = 0.5
	sparks.explosiveness = 0.95
	sparks.randomness = 0.4

	var mat := ParticleProcessMaterial.new()
	mat.direction = hit_normal
	mat.spread = 65.0
	mat.initial_velocity_min = 40.0 * sqrt(_intensity)
	mat.initial_velocity_max = 110.0 * sqrt(_intensity)
	mat.gravity = Vector3.ZERO
	mat.damping_min = 3.0
	mat.damping_max = 12.0
	mat.scale_min = 0.3
	mat.scale_max = 1.2

	# White-hot → orange → dark red → gone
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.85, 1.0),
		Color(1.0, 0.6, 0.15, 1.0),
		Color(0.8, 0.18, 0.04, 0.6),
		Color(0.15, 0.02, 0.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	sparks.process_material = mat

	# Stretched box for spark streaks
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.5)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(1.0, 0.9, 0.5, 1.0)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(1.0, 0.7, 0.3)
	mesh_mat.emission_energy_multiplier = 5.0
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	sparks.draw_pass_1 = mesh

	add_child(sparks)


func _create_debris(hit_normal: Vector3) -> void:
	var debris := GPUParticles3D.new()
	debris.emitting = true
	debris.one_shot = true
	debris.amount = int(randf_range(6.0, 10.0) * _intensity)
	debris.lifetime = 0.9
	debris.explosiveness = 0.9
	debris.randomness = 0.6

	var mat := ParticleProcessMaterial.new()
	mat.direction = hit_normal
	mat.spread = 50.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 45.0
	mat.gravity = Vector3.ZERO
	mat.angular_velocity_min = -360.0
	mat.angular_velocity_max = 360.0
	mat.damping_min = 1.0
	mat.damping_max = 5.0
	mat.scale_min = 0.4
	mat.scale_max = 1.5

	# Metallic debris: gray with slight warm glow
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.6, 0.55, 0.5, 1.0),
		Color(0.35, 0.3, 0.28, 0.9),
		Color(0.15, 0.12, 0.1, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	debris.process_material = mat

	# Angular metal chunks
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.15, 0.2)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.4, 0.38, 0.35, 1.0)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(0.8, 0.4, 0.1)
	mesh_mat.emission_energy_multiplier = 1.5
	mesh.material = mesh_mat
	debris.draw_pass_1 = mesh

	add_child(debris)


func _create_smoke(hit_normal: Vector3) -> void:
	var smoke := GPUParticles3D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.amount = 6
	smoke.lifetime = 1.0
	smoke.explosiveness = 0.8
	smoke.randomness = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.direction = hit_normal
	mat.spread = 40.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.0
	mat.damping_max = 6.0
	mat.scale_min = 1.0
	mat.scale_max = 3.0

	# Grow over lifetime
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 1.5))
	scale_curve.curve = curve
	mat.scale_curve = scale_curve

	# Dark smoke
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.15, 0.12, 0.1, 0.4),
		Color(0.08, 0.06, 0.05, 0.25),
		Color(0.03, 0.02, 0.02, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	smoke.process_material = mat

	# Soft sphere for smoke puff
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color(0.1, 0.08, 0.07, 0.5)
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	smoke.draw_pass_1 = mesh

	add_child(smoke)
