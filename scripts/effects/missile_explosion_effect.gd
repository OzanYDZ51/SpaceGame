class_name MissileExplosionEffect
extends Node3D

# =============================================================================
# Missile Explosion Effect - Spectacular size-scaled explosion VFX
# 10 components: flash, core fireball, secondary fires, 2 shockwaves,
# spark burst, hot debris, ember cloud, smoke cloud, secondary flash.
# Scales with missile size (S=0, M=1, L=2). Auto queue_free after duration.
# =============================================================================

var _age: float = 0.0
var _duration: float = 1.5
var _missile_size: int = 0

# Flash
var _flash_light: OmniLight3D = null
var _flash_energy_peak: float = 20.0
var _flash_range: float = 60.0

# Core fireball (inner + outer)
var _core_inner: MeshInstance3D = null
var _core_inner_mat: StandardMaterial3D = null
var _core_outer: MeshInstance3D = null
var _core_outer_mat: StandardMaterial3D = null
var _core_size: float = 3.0

# Secondary fire spheres (M+L)
var _fire_spheres: Array[MeshInstance3D] = []
var _fire_mats: Array[StandardMaterial3D] = []
var _fire_offsets: Array[Vector3] = []
var _fire_delays: Array[float] = []

# Shockwave rings
var _shockwave1: MeshInstance3D = null
var _shockwave1_mat: StandardMaterial3D = null
var _shockwave2: MeshInstance3D = null
var _shockwave2_mat: StandardMaterial3D = null
var _shockwave_radius: float = 10.0

# Secondary flash
var _secondary_flash: OmniLight3D = null

# Color
var _bolt_color: Color = Color(1.0, 0.5, 0.1)

# Size presets: [S, M, L]
const DURATIONS: Array[float] = [1.5, 2.5, 4.0]
const FLASH_ENERGIES: Array[float] = [20.0, 50.0, 120.0]
const FLASH_RANGES: Array[float] = [60.0, 120.0, 250.0]
const CORE_SIZES: Array[float] = [3.0, 6.0, 14.0]
const SHOCKWAVE_RADII: Array[float] = [10.0, 25.0, 60.0]
const SPARK_COUNTS: Array[int] = [48, 96, 200]
const DEBRIS_COUNTS: Array[int] = [12, 24, 48]
const EMBER_COUNTS: Array[int] = [16, 40, 80]
const SMOKE_COUNTS: Array[int] = [8, 16, 32]
const FIRE_COUNTS: Array[int] = [0, 3, 8]
const SHAKE_INTENSITIES: Array[float] = [0.15, 0.35, 0.7]


func setup(missile_size: int, bolt_color: Color, aoe_radius: float) -> void:
	_missile_size = clampi(missile_size, 0, 2)
	_bolt_color = bolt_color
	_duration = DURATIONS[_missile_size]
	_flash_energy_peak = FLASH_ENERGIES[_missile_size]
	_flash_range = FLASH_RANGES[_missile_size]
	_core_size = CORE_SIZES[_missile_size]
	_shockwave_radius = maxf(SHOCKWAVE_RADII[_missile_size], aoe_radius * 1.5)

	_create_flash()
	_create_core_fireball()
	if _missile_size >= 1:
		_create_secondary_fires()
	_create_shockwave1()
	if _missile_size >= 1:
		_create_shockwave2()
	_create_sparks()
	_create_debris()
	_create_embers()
	_create_smoke()
	_create_secondary_flash()

	# Camera shake
	_trigger_camera_shake()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return

	var t: float = _age / _duration

	_update_flash(t)
	_update_core(t)
	_update_secondary_fires(t)
	_update_shockwave1(t)
	_update_shockwave2(t)
	_update_secondary_flash(t)


# =============================================================================
# 1. FLASH LIGHT
# =============================================================================
func _create_flash() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.95, 0.8)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = _flash_range
	_flash_light.omni_attenuation = 1.5
	_flash_light.shadow_enabled = false
	add_child(_flash_light)


func _update_flash(t: float) -> void:
	if _flash_light == null:
		return
	var energy: float
	if t < 0.02:
		energy = _flash_energy_peak * (t / 0.02)
	elif t < 0.15:
		energy = _flash_energy_peak * exp(-(t - 0.02) * 15.0)
	else:
		energy = 0.0
	_flash_light.light_energy = energy
	# White-hot -> bolt_color -> orange
	var ct: float = clampf(t * 8.0, 0.0, 1.0)
	_flash_light.light_color = Color(1.0, lerpf(0.95, _bolt_color.g, ct), lerpf(0.8, _bolt_color.b * 0.5, ct))


# =============================================================================
# 2. CORE FIREBALL (double layer)
# =============================================================================
func _create_core_fireball() -> void:
	# Inner bright sphere
	_core_inner = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_core_inner.mesh = sphere
	_core_inner_mat = StandardMaterial3D.new()
	_core_inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_inner_mat.albedo_color = Color(1.0, 0.95, 0.8, 1.0)
	_core_inner_mat.emission_enabled = true
	_core_inner_mat.emission = Color(1.0, 0.9, 0.7)
	_core_inner_mat.emission_energy_multiplier = 12.0
	_core_inner_mat.no_depth_test = true
	_core_inner_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_inner.material_override = _core_inner_mat
	_core_inner.scale = Vector3.ONE * 0.01
	_core_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core_inner)

	# Outer glow (larger, more transparent)
	_core_outer = MeshInstance3D.new()
	_core_outer.mesh = sphere
	_core_outer_mat = StandardMaterial3D.new()
	_core_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_outer_mat.albedo_color = Color(_bolt_color.r, _bolt_color.g, _bolt_color.b, 0.4)
	_core_outer_mat.emission_enabled = true
	_core_outer_mat.emission = _bolt_color
	_core_outer_mat.emission_energy_multiplier = 6.0
	_core_outer_mat.no_depth_test = true
	_core_outer_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_outer.material_override = _core_outer_mat
	_core_outer.scale = Vector3.ONE * 0.01
	_core_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core_outer)


func _update_core(t: float) -> void:
	if _core_inner == null:
		return
	# Inner: rapid expand then shrink
	var inner_scale: float
	if t < 0.08:
		inner_scale = _core_size * (t / 0.08)
	elif t < 0.5:
		inner_scale = _core_size * maxf(0.0, 1.0 - (t - 0.08) * 2.0)
	else:
		inner_scale = 0.0
	_core_inner.scale = Vector3.ONE * maxf(inner_scale, 0.01)

	# Outer: slightly delayed, larger, slower fade
	var outer_scale: float
	if t < 0.05:
		outer_scale = _core_size * 1.8 * (t / 0.05)
	elif t < 0.6:
		outer_scale = _core_size * 1.8 * maxf(0.0, 1.0 - (t - 0.05) * 1.5)
	else:
		outer_scale = 0.0
	_core_outer.scale = Vector3.ONE * maxf(outer_scale, 0.01)

	# Color evolution: white -> bolt_color -> orange dark
	var ct: float = clampf(t * 4.0, 0.0, 1.0)
	_core_inner_mat.albedo_color = Color(
		lerpf(1.0, _bolt_color.r, ct),
		lerpf(0.95, _bolt_color.g * 0.7, ct),
		lerpf(0.8, _bolt_color.b * 0.3, ct),
		clampf(1.0 - t * 1.5, 0.0, 1.0)
	)
	_core_inner_mat.emission_energy_multiplier = maxf(0.0, 12.0 * (1.0 - t * 2.5))
	_core_outer_mat.albedo_color.a = clampf(0.4 - t * 0.6, 0.0, 0.4)
	_core_outer_mat.emission_energy_multiplier = maxf(0.0, 6.0 * (1.0 - t * 2.0))


# =============================================================================
# 3. SECONDARY FIRE SPHERES (M+L only)
# =============================================================================
func _create_secondary_fires() -> void:
	var count: int = FIRE_COUNTS[_missile_size]
	for i in count:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		mesh.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(_bolt_color.r, _bolt_color.g, _bolt_color.b, 0.7)
		mat.emission_enabled = true
		mat.emission = _bolt_color
		mat.emission_energy_multiplier = 8.0
		mat.no_depth_test = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.material_override = mat
		mesh.scale = Vector3.ONE * 0.01
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

		_fire_spheres.append(mesh)
		_fire_mats.append(mat)
		# Random offset direction and delay
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_fire_offsets.append(dir * _core_size * randf_range(0.5, 1.2))
		_fire_delays.append(randf_range(0.05, 0.15))


func _update_secondary_fires(t: float) -> void:
	for i in _fire_spheres.size():
		var mesh: MeshInstance3D = _fire_spheres[i]
		var mat: StandardMaterial3D = _fire_mats[i]
		var delay: float = _fire_delays[i]
		var local_t: float = (t * _duration - delay) / (_duration * 0.4)
		if local_t < 0.0:
			mesh.scale = Vector3.ONE * 0.01
			continue
		local_t = clampf(local_t, 0.0, 1.0)

		var fire_size: float = _core_size * 0.5
		var s: float
		if local_t < 0.3:
			s = fire_size * (local_t / 0.3)
		else:
			s = fire_size * maxf(0.0, 1.0 - (local_t - 0.3) * 1.43)
		mesh.scale = Vector3.ONE * maxf(s, 0.01)
		mesh.position = _fire_offsets[i] * local_t
		mat.albedo_color.a = clampf(0.7 * (1.0 - local_t), 0.0, 0.7)
		mat.emission_energy_multiplier = maxf(0.0, 8.0 * (1.0 - local_t * 1.5))


# =============================================================================
# 4. SHOCKWAVE RING 1
# =============================================================================
func _create_shockwave1() -> void:
	_shockwave1 = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.15
	ring.radial_segments = 32
	_shockwave1.mesh = ring

	_shockwave1_mat = StandardMaterial3D.new()
	_shockwave1_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shockwave1_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave1_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var sw_col := Color(
		lerpf(_bolt_color.r, 1.0, 0.5),
		lerpf(_bolt_color.g, 1.0, 0.5),
		lerpf(_bolt_color.b, 1.0, 0.5),
		0.7
	)
	_shockwave1_mat.albedo_color = sw_col
	_shockwave1_mat.emission_enabled = true
	_shockwave1_mat.emission = sw_col
	_shockwave1_mat.emission_energy_multiplier = 4.0
	_shockwave1_mat.no_depth_test = true
	_shockwave1_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_shockwave1.material_override = _shockwave1_mat
	_shockwave1.scale = Vector3.ONE * 0.01
	_shockwave1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shockwave1)


func _update_shockwave1(t: float) -> void:
	if _shockwave1 == null:
		return
	var ring_t: float = clampf(t * 3.0, 0.0, 1.0)
	var ring_scale: float = _shockwave_radius * ring_t
	_shockwave1.scale = Vector3.ONE * maxf(ring_scale, 0.01)
	_shockwave1_mat.albedo_color.a = clampf(0.7 * (1.0 - ring_t), 0.0, 0.7)
	_shockwave1_mat.emission_energy_multiplier = maxf(0.0, 4.0 * (1.0 - ring_t))


# =============================================================================
# 5. SHOCKWAVE RING 2 (M+L, delayed, larger)
# =============================================================================
func _create_shockwave2() -> void:
	_shockwave2 = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.1
	ring.radial_segments = 32
	_shockwave2.mesh = ring

	_shockwave2_mat = StandardMaterial3D.new()
	_shockwave2_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shockwave2_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave2_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shockwave2_mat.albedo_color = Color(_bolt_color.r, _bolt_color.g, _bolt_color.b, 0.4)
	_shockwave2_mat.emission_enabled = true
	_shockwave2_mat.emission = _bolt_color
	_shockwave2_mat.emission_energy_multiplier = 2.5
	_shockwave2_mat.no_depth_test = true
	_shockwave2_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_shockwave2.material_override = _shockwave2_mat
	_shockwave2.scale = Vector3.ONE * 0.01
	_shockwave2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shockwave2)


func _update_shockwave2(t: float) -> void:
	if _shockwave2 == null:
		return
	# Delayed by 0.1s relative to duration
	var delay: float = 0.1 / _duration
	var ring_t: float = clampf((t - delay) * 2.5, 0.0, 1.0)
	if ring_t <= 0.0:
		return
	var ring_scale: float = _shockwave_radius * 1.5 * ring_t
	_shockwave2.scale = Vector3.ONE * maxf(ring_scale, 0.01)
	_shockwave2_mat.albedo_color.a = clampf(0.4 * (1.0 - ring_t), 0.0, 0.4)
	_shockwave2_mat.emission_energy_multiplier = maxf(0.0, 2.5 * (1.0 - ring_t))


# =============================================================================
# 6. SPARK BURST
# =============================================================================
func _create_sparks() -> void:
	var sparks := GPUParticles3D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.amount = SPARK_COUNTS[_missile_size]
	sparks.lifetime = _duration * 0.4
	sparks.explosiveness = 1.0
	sparks.randomness = 0.3
	sparks.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0 + _missile_size * 30.0
	mat.initial_velocity_max = 100.0 + _missile_size * 60.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 8.0
	mat.damping_max = 20.0
	mat.scale_min = 0.3 + _missile_size * 0.2
	mat.scale_max = 1.0 + _missile_size * 0.5

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.9, 1.0))
	gradient.add_point(0.2, Color(_bolt_color.r, _bolt_color.g, _bolt_color.b, 0.9))
	gradient.add_point(0.6, Color(
		lerpf(_bolt_color.r, 1.0, 0.3),
		lerpf(_bolt_color.g, 0.4, 0.5),
		0.05, 0.5
	))
	gradient.set_color(1, Color(0.2, 0.02, 0.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	sparks.process_material = mat

	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.08, 0.08, 0.6)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.albedo_color = Color(1.0, 0.9, 0.5, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.7, 0.3)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.no_depth_test = true
	spark_mesh.material = spark_mat
	sparks.draw_pass_1 = spark_mesh

	add_child(sparks)


# =============================================================================
# 7. HOT DEBRIS
# =============================================================================
func _create_debris() -> void:
	var debris := GPUParticles3D.new()
	debris.emitting = true
	debris.one_shot = true
	debris.amount = DEBRIS_COUNTS[_missile_size]
	debris.lifetime = _duration * 0.6
	debris.explosiveness = 0.95
	debris.randomness = 0.5
	debris.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 15.0 + _missile_size * 10.0
	mat.initial_velocity_max = 50.0 + _missile_size * 25.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 3.0
	mat.damping_max = 8.0
	mat.angular_velocity_min = -360.0
	mat.angular_velocity_max = 360.0
	mat.scale_min = 0.2 + _missile_size * 0.15
	mat.scale_max = 0.8 + _missile_size * 0.4

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.5, 0.35, 1.0))
	gradient.add_point(0.4, Color(0.4, 0.35, 0.3, 0.8))
	gradient.set_color(1, Color(0.2, 0.18, 0.15, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	debris.process_material = mat

	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.3, 0.15, 0.4)
	var debris_mat := StandardMaterial3D.new()
	debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debris_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debris_mat.vertex_color_use_as_albedo = true
	debris_mesh.material = debris_mat
	debris.draw_pass_1 = debris_mesh

	add_child(debris)


# =============================================================================
# 8. EMBER CLOUD
# =============================================================================
func _create_embers() -> void:
	var embers := GPUParticles3D.new()
	embers.emitting = true
	embers.one_shot = true
	embers.amount = EMBER_COUNTS[_missile_size]
	embers.lifetime = _duration * 0.8
	embers.explosiveness = 0.85
	embers.randomness = 0.6
	embers.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 12.0 + _missile_size * 5.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.scale_min = 0.4 + _missile_size * 0.3
	mat.scale_max = 1.5 + _missile_size * 0.8

	var gradient := Gradient.new()
	gradient.set_color(0, Color(
		minf(_bolt_color.r * 1.3, 1.0),
		minf(_bolt_color.g * 1.3, 1.0),
		_bolt_color.b, 0.8
	))
	gradient.add_point(0.3, Color(_bolt_color.r, _bolt_color.g * 0.7, _bolt_color.b * 0.3, 0.6))
	gradient.add_point(0.7, Color(0.6, 0.1, 0.02, 0.3))
	gradient.set_color(1, Color(0.2, 0.02, 0.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	embers.process_material = mat

	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.3
	ember_mesh.height = 0.6
	ember_mesh.radial_segments = 6
	ember_mesh.rings = 3
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.emission_enabled = true
	ember_mat.emission = _bolt_color
	ember_mat.emission_energy_multiplier = 3.0
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_mesh.material = ember_mat
	embers.draw_pass_1 = ember_mesh

	add_child(embers)


# =============================================================================
# 9. SMOKE CLOUD
# =============================================================================
func _create_smoke() -> void:
	var smoke := GPUParticles3D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.amount = SMOKE_COUNTS[_missile_size]
	smoke.lifetime = _duration
	smoke.explosiveness = 0.7
	smoke.randomness = 0.6
	smoke.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 6.0 + _missile_size * 3.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.5
	mat.damping_max = 2.0
	mat.scale_min = 1.0 + _missile_size * 0.5
	mat.scale_max = 3.0 + _missile_size * 2.0

	# Scale curve: small -> big
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 0.7))
	curve.add_point(Vector2(1.0, 1.5))
	scale_curve.curve = curve
	mat.scale_curve = scale_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.25, 0.22, 0.2, 0.4))
	gradient.add_point(0.4, Color(0.15, 0.13, 0.12, 0.3))
	gradient.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	smoke.process_material = mat

	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.5
	smoke_mesh.height = 1.0
	smoke_mesh.radial_segments = 6
	smoke_mesh.rings = 3
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mesh.material = smoke_mat
	smoke.draw_pass_1 = smoke_mesh

	add_child(smoke)


# =============================================================================
# 10. SECONDARY FLASH (at ~15% duration, shockwave midpoint)
# =============================================================================
func _create_secondary_flash() -> void:
	_secondary_flash = OmniLight3D.new()
	_secondary_flash.light_color = _bolt_color
	_secondary_flash.light_energy = 0.0
	_secondary_flash.omni_range = _flash_range * 0.6
	_secondary_flash.omni_attenuation = 1.5
	_secondary_flash.shadow_enabled = false
	add_child(_secondary_flash)


func _update_secondary_flash(t: float) -> void:
	if _secondary_flash == null:
		return
	# Activates around 15% of duration, slow decay
	var trigger_t: float = 0.15
	var peak: float = _flash_energy_peak * 0.3
	if t < trigger_t - 0.02:
		_secondary_flash.light_energy = 0.0
	elif t < trigger_t:
		_secondary_flash.light_energy = peak * ((t - trigger_t + 0.02) / 0.02)
	elif t < trigger_t + 0.15:
		_secondary_flash.light_energy = peak * maxf(0.0, 1.0 - (t - trigger_t) / 0.15)
	else:
		_secondary_flash.light_energy = 0.0


# =============================================================================
# CAMERA SHAKE
# =============================================================================
func _trigger_camera_shake() -> void:
	var player_ship = GameManager.player_ship
	if player_ship == null or not is_instance_valid(player_ship):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not (cam is ShipCamera):
		return
	var dist: float = global_position.distance_to(player_ship.global_position)
	var intensity: float = SHAKE_INTENSITIES[_missile_size]
	(cam as ShipCamera).add_explosion_shake(intensity, dist)
