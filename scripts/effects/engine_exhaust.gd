class_name EngineExhaust
extends Node3D

# =============================================================================
# Engine Exhaust — Thick volumetric engine VFX (Star Citizen style)
#
# 7 layers per nozzle for a FAT, solid-looking plume:
#   1. CORE CONE      — Shader-driven, nearly cylindrical (not a thin cone!)
#   2. VOLUME FILL    — Huge overlapping soft quads = solid "block" of exhaust
#   3. AFTERBURNER    — Billboard bloom disc at nozzle
#   4. INNER FLAME    — Bright hot particles near nozzle
#   5. OUTER FLAME    — Wide colored plume that extends far back
#   6. SPARK EMBERS   — Hot metal particles on boost/cruise
#   7. DYNAMIC LIGHT  — Pulsating omni light
#
# The key to the "Star Citizen block" look is the VOLUME FILL layer:
# many large, low-alpha, overlapping billboard quads that stack via
# additive blend to create a dense, opaque-looking plume.
# =============================================================================

var _nozzles: Array[Dictionary] = []

var _engine_color: Color = Color(0.3, 0.6, 1.0)
var _model_scale: float = 1.0
var _exhaust_scale: float = 1.0
var _max_speed_boost: float = 600.0

# Smooth state
var _throttle_smooth: float = 0.0
var _boost_blend: float = 0.0
var _cruise_blend: float = 0.0
var _pulse_time: float = 0.0
var _ship_speed_ratio: float = 0.0

# Shared resources
var _soft_circle_tex: GradientTexture2D = null
var _exhaust_shader: Shader = null


func setup(p_model_scale: float, color: Color, vfx_points: Array[Dictionary] = [], ship_data: ShipData = null) -> void:
	_model_scale = p_model_scale
	_engine_color = color
	if ship_data:
		_exhaust_scale = ship_data.exhaust_scale
		_max_speed_boost = ship_data.max_speed_boost
	else:
		_exhaust_scale = p_model_scale
		_max_speed_boost = Constants.MAX_SPEED_BOOST
	_soft_circle_tex = _create_soft_circle(64)
	_exhaust_shader = load("res://shaders/engine_exhaust.gdshader") as Shader

	var positions: Array[Dictionary] = []
	for pt in vfx_points:
		if pt.get("type") == &"ENGINE":
			positions.append(pt)

	if positions.is_empty():
		positions.append({"position": Vector3(-1.5, 0.0, 5.0) * p_model_scale, "direction": Vector3.BACK})
		positions.append({"position": Vector3(1.5, 0.0, 5.0) * p_model_scale, "direction": Vector3.BACK})

	for pt in positions:
		_create_nozzle(pt["position"], pt.get("direction", Vector3.BACK))


func update_intensity(throttle: float, speed_mode: int = 0, ship_speed: float = 0.0) -> void:
	_throttle_smooth = lerpf(_throttle_smooth, throttle, 0.12)
	_ship_speed_ratio = clampf(ship_speed / maxf(_max_speed_boost, 1.0), 0.0, 1.0)

	var target_boost: float = 1.0 if speed_mode == Constants.SpeedMode.BOOST else 0.0
	_boost_blend = lerpf(_boost_blend, target_boost, 0.08)

	var target_cruise: float = 1.0 if speed_mode == Constants.SpeedMode.CRUISE else 0.0
	_cruise_blend = lerpf(_cruise_blend, target_cruise, 0.06)

	var t := _throttle_smooth
	var idle := 0.06

	for nozzle in _nozzles:
		_update_cone(nozzle, t, idle)
		_update_volume_fill(nozzle, t, idle)
		_update_afterburner(nozzle, t)
		_update_inner_flame(nozzle, t, idle)
		_update_outer_flame(nozzle, t, idle)
		_update_light(nozzle, t, idle)


# =============================================================================
# NOZZLE CREATION
# =============================================================================

func _create_nozzle(pos: Vector3, dir: Vector3) -> void:
	var nozzle := {}
	var nozzle_root := Node3D.new()
	nozzle_root.position = pos
	if dir.length_squared() > 0.01:
		# look_at makes -Z face the target, but we emit along +Z,
		# so look AWAY from dir so +Z aligns with the exhaust direction.
		var up := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		nozzle_root.look_at_from_position(pos, pos - dir, up)
	add_child(nozzle_root)

	nozzle["cone"] = _create_core_cone(nozzle_root)
	nozzle["volume"] = _create_volume_fill(nozzle_root)
	nozzle["afterburner"] = _create_afterburner_disc(nozzle_root)
	nozzle["inner"] = _create_inner_flame(nozzle_root)
	nozzle["outer"] = _create_outer_flame(nozzle_root)
	nozzle["light"] = _create_dynamic_light(nozzle_root)
	nozzle["root"] = nozzle_root
	_nozzles.append(nozzle)


# =============================================================================
# LAYER 1: CORE CONE — Fat at nozzle, tapers to fine point
# =============================================================================

func _create_core_cone(parent: Node3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ExhaustCore"
	var es := _exhaust_scale

	# Fat base that tapers aggressively to a fine point — teardrop shape
	var cone := CylinderMesh.new()
	var base_radius := 1.1 * es
	var tip_radius := 0.06 * es
	var length := 12.0 * es
	cone.top_radius = base_radius
	cone.bottom_radius = tip_radius
	cone.height = length
	cone.radial_segments = 16
	cone.rings = 10

	mesh_inst.mesh = cone
	mesh_inst.rotation.x = -PI / 2.0
	mesh_inst.position.z = length * 0.5

	if _exhaust_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _exhaust_shader
		mat.set_shader_parameter("color_core", Vector3(
			_engine_color.r * 0.5 + 0.5,
			_engine_color.g * 0.4 + 0.6,
			_engine_color.b * 0.3 + 0.7))
		mat.set_shader_parameter("color_mid", Vector3(
			_engine_color.r, _engine_color.g, _engine_color.b))
		mat.set_shader_parameter("color_tip", Vector3(
			_engine_color.r * 0.6, _engine_color.g * 0.7, _engine_color.b * 0.9))
		mat.set_shader_parameter("intensity", 10.0)
		mat.set_shader_parameter("throttle", 0.0)
		mat.set_shader_parameter("flame_length", 1.0)
		mat.set_shader_parameter("flicker_speed", 8.0)
		mat.set_shader_parameter("flicker_strength", 0.7)
		mat.set_shader_parameter("pulse_speed", 2.5)
		mat.set_shader_parameter("pulse_amount", 0.04)
		mat.set_shader_parameter("boost_glow", 0.0)
		mesh_inst.material_override = mat
	else:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = _engine_color
		mat.emission_enabled = true
		mat.emission = _engine_color
		mat.emission_energy_multiplier = 10.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = false
		mesh_inst.material_override = mat

	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_inst)
	return mesh_inst


# =============================================================================
# LAYER 2: VOLUME FILL — Dense near nozzle, tapers to wispy trail
# =============================================================================

func _create_volume_fill(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "VolumeFill"
	var es := _exhaust_scale

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.0 * es
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 6.0  # Tight spread = tapers naturally
	mat.initial_velocity_min = 15.0 * es
	mat.initial_velocity_max = 35.0 * es
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.2
	mat.damping_max = 0.5
	# Round soft blobs, NOT elongated rectangles
	mat.scale_min = 1.5 * es
	mat.scale_max = 2.5 * es
	mat.color_ramp = _make_gradient([
		[0.0, Color(_engine_color.r * 1.1, _engine_color.g * 1.0, _engine_color.b * 0.9, 0.3)],
		[0.08, Color(_engine_color.r, _engine_color.g * 0.9, _engine_color.b * 0.85, 0.22)],
		[0.25, Color(_engine_color.r * 0.8, _engine_color.g * 0.7, _engine_color.b * 0.8, 0.12)],
		[0.5, Color(_engine_color.r * 0.5, _engine_color.g * 0.4, _engine_color.b * 0.6, 0.04)],
		[1.0, Color(_engine_color.r * 0.2, _engine_color.g * 0.15, _engine_color.b * 0.3, 0.0)],
	])
	# Scale 1.0 at birth → 0.08 at death = realistic taper
	mat.scale_curve = _make_scale_curve_4pt(1.0, 0.7, 0.2, 0.04)

	p.process_material = mat
	p.amount = 40
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = true

	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.2, 1.2) * es
	mesh.material = _make_particle_material(_engine_color, 1.0)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(p)
	return p


# =============================================================================
# LAYER 3: AFTERBURNER DISC — Bright bloom star at nozzle
# =============================================================================

func _create_afterburner_disc(parent: Node3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "AfterburnerDisc"

	var quad := QuadMesh.new()
	var disc_size := 3.0 * _exhaust_scale
	quad.size = Vector2(disc_size, disc_size)
	mesh_inst.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.9, 0.0)
	mat.albedo_texture = _soft_circle_tex
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.5)
	mat.emission_energy_multiplier = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	mesh_inst.material_override = mat

	mesh_inst.position = Vector3.ZERO
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.visible = false
	parent.add_child(mesh_inst)
	return mesh_inst


# =============================================================================
# LAYER 4: INNER FLAME — Bright, fast, near-nozzle particles
# =============================================================================

func _create_inner_flame(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "InnerFlame"
	var es := _exhaust_scale

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.6 * es
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 5.0  # Tight = follows the cone taper
	mat.initial_velocity_min = 30.0 * es
	mat.initial_velocity_max = 65.0 * es
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.5
	mat.damping_max = 6.0
	mat.scale_min = 0.6 * es
	mat.scale_max = 1.2 * es
	mat.color_ramp = _make_gradient([
		[0.0, Color(1.0, 0.98, 0.95, 0.7)],
		[0.05, Color(1.0, 0.95, 0.88, 0.5)],
		[0.15, Color(_engine_color.r * 1.3, _engine_color.g * 1.2, _engine_color.b * 1.1, 0.35)],
		[0.4, Color(_engine_color.r, _engine_color.g * 0.8, _engine_color.b * 0.9, 0.12)],
		[1.0, Color(_engine_color.r * 0.3, _engine_color.g * 0.2, _engine_color.b * 0.4, 0.0)],
	])
	# Big at nozzle → tiny at end
	mat.scale_curve = _make_scale_curve_4pt(1.0, 0.6, 0.15, 0.02)

	p.process_material = mat
	p.amount = 40
	p.lifetime = 0.4
	p.local_coords = true
	p.emitting = true

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.4, 0.4) * es
	mesh.material = _make_particle_material(_engine_color, 3.0)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(p)
	return p


# =============================================================================
# LAYER 5: OUTER FLAME — Wide exhaust plume extending far back
# =============================================================================

func _create_outer_flame(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "OuterFlame"
	var es := _exhaust_scale

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.8 * es
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 12.0  # Moderate spread — forms the envelope
	mat.initial_velocity_min = 18.0 * es
	mat.initial_velocity_max = 45.0 * es
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.1
	mat.damping_max = 0.3
	mat.scale_min = 0.8 * es
	mat.scale_max = 1.5 * es
	mat.color_ramp = _make_gradient([
		[0.0, Color(_engine_color.r * 1.2, _engine_color.g * 1.1, _engine_color.b, 0.3)],
		[0.1, Color(_engine_color.r, _engine_color.g, _engine_color.b * 0.95, 0.2)],
		[0.3, Color(_engine_color.r * 0.7, _engine_color.g * 0.6, _engine_color.b * 0.8, 0.1)],
		[0.6, Color(_engine_color.r * 0.35, _engine_color.g * 0.3, _engine_color.b * 0.5, 0.03)],
		[1.0, Color(_engine_color.r * 0.1, _engine_color.g * 0.08, _engine_color.b * 0.2, 0.0)],
	])
	# Big → thin trail
	mat.scale_curve = _make_scale_curve_4pt(0.9, 0.5, 0.12, 0.02)

	p.process_material = mat
	p.amount = 56
	p.lifetime = 1.1
	p.local_coords = false
	p.emitting = true

	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0) * es
	mesh.material = _make_particle_material(_engine_color, 1.5)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(p)
	return p


# =============================================================================
# LAYER 6: SPARK EMBERS
# =============================================================================

func _create_sparks(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SparkEmbers"
	var ms := _model_scale

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5 * ms
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 30.0
	mat.initial_velocity_min = 30.0 * ms
	mat.initial_velocity_max = 80.0 * ms
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.0
	mat.damping_max = 0.3
	mat.scale_min = 0.15 * ms
	mat.scale_max = 0.35 * ms

	var spark_color := Color(1.0, 0.7, 0.3)
	mat.color_ramp = _make_gradient([
		[0.0, Color(1.0, 0.95, 0.8, 1.0)],
		[0.1, Color(1.0, 0.7, 0.3, 0.9)],
		[0.4, Color(1.0, 0.4, 0.1, 0.6)],
		[0.7, Color(0.8, 0.2, 0.05, 0.3)],
		[1.0, Color(0.5, 0.15, 0.0, 0.0)],
	])
	mat.scale_curve = _make_scale_curve(0.5, 1.0, 0.0)

	p.process_material = mat
	p.amount = 28
	p.lifetime = 0.55
	p.local_coords = false
	p.emitting = false
	p.amount_ratio = 0.0

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08) * ms
	mesh.material = _make_particle_material(spark_color, 7.0)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(p)
	return p


# =============================================================================
# LAYER 7: DYNAMIC LIGHT
# =============================================================================

func _create_dynamic_light(parent: Node3D) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "ExhaustLight"
	light.light_color = _engine_color
	light.light_energy = 0.0
	light.omni_range = 10.0 * _exhaust_scale
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 0.0, 3.0 * _exhaust_scale)
	parent.add_child(light)
	return light


# =============================================================================
# UPDATE METHODS
# =============================================================================

func _update_cone(nozzle: Dictionary, t: float, idle: float) -> void:
	var cone: MeshInstance3D = nozzle["cone"]
	if cone == null:
		return
	var mat := cone.material_override
	if mat == null:
		return

	var effective_t := maxf(t, idle)

	var mode_intensity := 10.0
	var mode_length := 1.0
	var mode_flicker := 0.35
	var mode_boost_glow := 0.0

	# Boost: brighter, subtle radial swell only
	mode_intensity = lerpf(mode_intensity, 14.0, _boost_blend)
	mode_length = lerpf(mode_length, 1.15, _boost_blend)
	mode_flicker = lerpf(mode_flicker, 0.8, _boost_blend)
	mode_boost_glow = _boost_blend

	# Cruise: intense glow, minimal radial swell
	mode_intensity = lerpf(mode_intensity, 18.0, _cruise_blend)
	mode_length = lerpf(mode_length, 1.25, _cruise_blend)
	mode_flicker = lerpf(mode_flicker, 0.5, _cruise_blend)
	mode_boost_glow = maxf(mode_boost_glow, _cruise_blend * 0.7)

	if mat is ShaderMaterial:
		# Color shift — boost goes HOT orange, cruise goes icy blue-white
		var base_core := Vector3(
			_engine_color.r * 0.5 + 0.5,
			_engine_color.g * 0.4 + 0.6,
			_engine_color.b * 0.3 + 0.7)
		var boost_core := Vector3(1.0, 0.9, 0.75)
		var cruise_core := Vector3(0.92, 0.96, 1.0)
		var final_core := base_core.lerp(boost_core, _boost_blend).lerp(cruise_core, _cruise_blend)

		var base_mid := Vector3(_engine_color.r, _engine_color.g, _engine_color.b)
		var boost_mid := Vector3(1.0, 0.5, 0.1)  # Hot orange
		var cruise_mid := Vector3(0.45, 0.65, 1.0)
		var final_mid := base_mid.lerp(boost_mid, _boost_blend).lerp(cruise_mid, _cruise_blend)

		var base_tip := Vector3(
			_engine_color.r * 0.6,
			_engine_color.g * 0.7,
			_engine_color.b * 0.9)
		var boost_tip := Vector3(0.7, 0.25, 0.05)  # Deep orange-red
		var cruise_tip := Vector3(0.25, 0.45, 1.0)
		var final_tip := base_tip.lerp(boost_tip, _boost_blend).lerp(cruise_tip, _cruise_blend)

		mat.set_shader_parameter("color_core", final_core)
		mat.set_shader_parameter("color_mid", final_mid)
		mat.set_shader_parameter("color_tip", final_tip)
		mat.set_shader_parameter("intensity", mode_intensity)
		mat.set_shader_parameter("throttle", effective_t)
		mat.set_shader_parameter("flame_length", mode_length * (0.6 + effective_t * 0.4))
		mat.set_shader_parameter("flicker_strength", mode_flicker)
		mat.set_shader_parameter("boost_glow", mode_boost_glow * effective_t)

	cone.visible = effective_t > 0.01


func _update_volume_fill(nozzle: Dictionary, t: float, idle: float) -> void:
	var p: GPUParticles3D = nozzle["volume"]
	if p == null:
		return
	var effective_t := maxf(t, idle)
	p.amount_ratio = 0.04 + effective_t * 0.96
	# Boost/cruise = faster particles = longer trail before they shrink to nothing
	p.speed_scale = 0.3 + effective_t * 1.2 + _boost_blend * 1.8 + _cruise_blend * 3.0
	p.emitting = effective_t > 0.01

	# Dynamic lifetime: longer trail at higher speed
	p.lifetime = 0.9 + _ship_speed_ratio * 0.5


func _update_afterburner(nozzle: Dictionary, t: float) -> void:
	var disc: MeshInstance3D = nozzle["afterburner"]
	if disc == null:
		return
	var mat := disc.material_override as StandardMaterial3D
	if mat == null:
		return

	var ab_t := maxf(0.0, t - 0.6) * 2.5
	ab_t = maxf(ab_t, _boost_blend)
	ab_t = maxf(ab_t, _cruise_blend * 0.6)
	ab_t = clampf(ab_t, 0.0, 1.0)

	if ab_t < 0.02:
		disc.visible = false
		return
	disc.visible = true

	_pulse_time += 0.016
	var pulse := 1.0 + sin(_pulse_time * 9.0) * 0.12 + sin(_pulse_time * 14.0) * 0.06
	var disc_size := (3.0 + _boost_blend * 2.0 + _cruise_blend * 1.5) * _exhaust_scale * pulse
	disc.mesh.size = Vector2(disc_size, disc_size)

	# Orange for boost, blue-white for cruise
	var col := Color(1.0, 0.75, 0.4).lerp(Color(0.7, 0.85, 1.0), _cruise_blend)
	mat.emission = col
	mat.emission_energy_multiplier = ab_t * (15.0 + _boost_blend * 10.0 + _cruise_blend * 8.0)
	mat.albedo_color = Color(col.r, col.g, col.b, ab_t * 0.85)


func _update_inner_flame(nozzle: Dictionary, t: float, idle: float) -> void:
	var p: GPUParticles3D = nozzle["inner"]
	if p == null:
		return
	var effective_t := maxf(t, idle)
	p.amount_ratio = 0.05 + effective_t * 0.95
	p.speed_scale = 0.3 + effective_t * 1.5 + _boost_blend * 1.5 + _cruise_blend * 2.5
	p.emitting = effective_t > 0.01


func _update_outer_flame(nozzle: Dictionary, t: float, idle: float) -> void:
	var p: GPUParticles3D = nozzle["outer"]
	if p == null:
		return
	var effective_t := maxf(t, idle)
	p.amount_ratio = 0.03 + effective_t * 0.97
	p.speed_scale = 0.25 + effective_t * 1.3 + _boost_blend * 1.2 + _cruise_blend * 2.0
	p.emitting = effective_t > 0.01
	# Dynamic lifetime: longer trail at higher speed
	p.lifetime = 1.1 + _ship_speed_ratio * 0.6

	# Boost/cruise: slightly wider base spread, taper does the rest
	var pmat := p.process_material as ParticleProcessMaterial
	if pmat:
		pmat.spread = 12.0 + _boost_blend * 4.0 + _cruise_blend * 3.0


func _update_sparks(nozzle: Dictionary, t: float) -> void:
	var p: GPUParticles3D = nozzle["sparks"]
	if p == null:
		return
	var spark_t := maxf(0.0, t - 0.4) * 1.7
	spark_t = maxf(spark_t, _boost_blend * 1.0)
	spark_t = maxf(spark_t, _cruise_blend * 0.5)
	p.amount_ratio = clampf(spark_t, 0.0, 1.0)
	p.speed_scale = 0.5 + spark_t * 2.5
	p.emitting = spark_t > 0.05
	# Dynamic lifetime: longer trail at higher speed
	p.lifetime = 0.55 + _ship_speed_ratio * 0.4


func _update_light(nozzle: Dictionary, t: float, idle: float) -> void:
	var light: OmniLight3D = nozzle["light"]
	if light == null:
		return
	var effective_t := maxf(t, idle)

	_pulse_time += 0.016
	var pulse := 1.0 + sin(_pulse_time * 7.3) * 0.15 + sin(_pulse_time * 11.7) * 0.08

	var base_energy := 2.5 * effective_t * pulse
	base_energy += _boost_blend * 4.0 * effective_t
	base_energy += _cruise_blend * 5.0 * effective_t
	light.light_energy = base_energy

	var col := _engine_color
	col = col.lerp(Color(1.0, 0.55, 0.15), _boost_blend * 0.65)
	col = col.lerp(Color(0.6, 0.8, 1.0), _cruise_blend * 0.4)
	light.light_color = col

	light.omni_range = (10.0 + _boost_blend * 8.0 + _cruise_blend * 12.0) * _exhaust_scale


# =============================================================================
# TEXTURE & MATERIAL HELPERS
# =============================================================================

func _make_particle_material(emit_color: Color, emit_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_circle_tex
	mat.emission_enabled = true
	mat.emission = emit_color
	mat.emission_energy_multiplier = emit_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	return mat


func _create_soft_circle(tex_size: int = 64) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = tex_size
	tex.height = tex_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.8),
		Color(1.0, 1.0, 1.0, 0.3),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 1.0])
	tex.gradient = grad
	return tex


func _make_gradient(stops: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	var colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	for stop in stops:
		offsets.append(stop[0])
		colors.append(stop[1])
	grad.colors = colors
	grad.offsets = offsets
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _make_scale_curve(start: float, peak: float, end_val: float) -> CurveTexture:
	var tex := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(0.1, peak))
	curve.add_point(Vector2(1.0, end_val))
	tex.curve = curve
	return tex


func _make_scale_curve_4pt(birth: float, early: float, mid: float, death: float) -> CurveTexture:
	## Creates a 4-point scale curve for realistic taper: big at birth → tiny at death.
	var tex := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, birth))
	curve.add_point(Vector2(0.15, early))
	curve.add_point(Vector2(0.5, mid))
	curve.add_point(Vector2(1.0, death))
	tex.curve = curve
	return tex
