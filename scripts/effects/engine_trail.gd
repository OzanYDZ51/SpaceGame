class_name EngineTrail
extends Node3D

# =============================================================================
# Engine Trail - Dual-layer GPU particle exhaust system
# Layer 1 (CORE): Hot white-yellow, small, fast, short-lived → HDR bloom
# Layer 2 (GLOW): Colored, larger, slower, longer-lived → soft diffuse trail
# Uses radial gradient texture for soft circular particles (no hard quad edges).
# All ships (player + NPCs) get trails, color matches engine_light_color.
# =============================================================================

var _particles: Array[GPUParticles3D] = []
var _trail_intensity: float = 0.0

const _ENGINE_OFFSETS := [
	Vector3(-1.5, 0.0, 5.0),
	Vector3(1.5, 0.0, 5.0),
]


func setup(p_model_scale: float, color: Color, vfx_points: Array[Dictionary] = []) -> void:
	var soft_tex := _create_soft_circle(32)

	# Collect engine positions from VFX attach points (already in ShipModel space)
	var positions: Array[Vector3] = []
	for pt in vfx_points:
		if pt.get("type") == &"ENGINE":
			positions.append(pt["position"])

	# Fallback to hardcoded defaults (need scaling by model_scale)
	if positions.is_empty():
		for off in _ENGINE_OFFSETS:
			positions.append(off * p_model_scale)

	for pos in positions:
		# ─── CORE LAYER (hot, bright, small) ─────────────────────────────
		var core := _create_emitter(
			p_model_scale, pos,
			16,                    # amount
			0.25,                  # lifetime
			Vector2(0.12, 0.12),   # quad size factor
			12.0, 30.0,           # velocity min/max factor
			8.0,                   # spread degrees
			soft_tex,
			_make_core_gradient(color),
			_make_grow_shrink_curve(0.4, 1.0, 0.1),
			color,
			6.0                    # emission energy (high → bloom)
		)
		add_child(core)
		_particles.append(core)

		# ─── GLOW LAYER (colored, diffuse, larger) ───────────────────────
		var glow := _create_emitter(
			p_model_scale, pos,
			20,                    # amount
			0.5,                   # lifetime
			Vector2(0.35, 0.35),   # quad size factor
			6.0, 18.0,            # velocity min/max factor
			15.0,                  # spread degrees
			soft_tex,
			_make_glow_gradient(color),
			_make_grow_shrink_curve(0.3, 1.0, 0.05),
			color,
			2.5                    # emission energy (moderate bloom)
		)
		add_child(glow)
		_particles.append(glow)


func update_intensity(throttle: float) -> void:
	_trail_intensity = lerpf(_trail_intensity, throttle, 0.15)
	for p in _particles:
		p.amount_ratio = 0.08 + _trail_intensity * 0.92
		p.speed_scale = 0.3 + _trail_intensity * 1.7


# =============================================================================
# FACTORY HELPERS
# =============================================================================

func _create_emitter(
	ms: float, offset: Vector3,
	amount: int, lifetime: float, quad_size: Vector2,
	vel_min_f: float, vel_max_f: float, spread: float,
	soft_tex: GradientTexture2D,
	color_ramp: GradientTexture1D,
	scale_curve: CurveTexture,
	emit_color: Color, emit_energy: float
) -> GPUParticles3D:
	var p := GPUParticles3D.new()

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.25 * ms
	mat.direction = Vector3(0.0, 0.0, 1.0)  # +Z = backward
	mat.spread = spread
	mat.initial_velocity_min = vel_min_f * ms
	mat.initial_velocity_max = vel_max_f * ms
	mat.gravity = Vector3.ZERO
	mat.damping_min = 1.5
	mat.damping_max = 4.0
	mat.scale_min = 0.6 * ms
	mat.scale_max = 1.2 * ms
	mat.color_ramp = color_ramp
	mat.scale_curve = scale_curve

	p.process_material = mat
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = true
	p.position = offset
	p.emitting = true

	# Soft particle mesh (billboard quad with radial gradient)
	var mesh := QuadMesh.new()
	mesh.size = quad_size * ms
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = soft_tex
	mesh_mat.emission_enabled = true
	mesh_mat.emission = emit_color
	mesh_mat.emission_energy_multiplier = emit_energy
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	return p


func _create_soft_circle(tex_size: int = 32) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = tex_size
	tex.height = tex_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.5),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	tex.gradient = grad
	return tex


func _make_core_gradient(color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.85, 1.0),                                    # White-hot start
		Color(color.r * 1.3, color.g * 1.1, color.b * 0.9, 0.8),      # Warm tint
		Color(color.r * 0.6, color.g * 0.5, color.b * 0.3, 0.0),      # Fade out
	])
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _make_glow_gradient(color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(color.r * 1.2, color.g * 1.1, color.b, 0.75),   # Bright start
		Color(color.r, color.g * 0.8, color.b * 0.9, 0.4),    # Mid
		Color(color.r * 0.3, color.g * 0.2, color.b * 0.5, 0.0),  # Fade
	])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _make_grow_shrink_curve(start: float, peak: float, end_val: float) -> CurveTexture:
	var tex := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(0.12, peak))
	curve.add_point(Vector2(1.0, end_val))
	tex.curve = curve
	return tex
