class_name ShieldHitEffect
extends Node3D

# =============================================================================
# Shield Hit Effect - Curved energy patch at projectile impact on shields
# SphereMesh centered on ship — shader only renders a smooth curved cap
# around the impact point (~70 deg). Appears with fade-in, blue gradient.
# Parented to the target ship so it moves with it.
# =============================================================================

const DURATION: float = 0.8
const DEFAULT_SHIELD_RADIUS: float = 20.0

var _age: float = 0.0
var _intensity: float = 1.0
var _shield_mat: ShaderMaterial = null
var _flash_light: OmniLight3D = null


func setup(hit_world_pos: Vector3, target_ship: Node3D, shield_ratio: float, intensity: float = 1.0) -> void:
	_intensity = clampf(intensity, 0.5, 3.0)
	position = Vector3.ZERO  # Centered on parent ship

	# Shield radius: pushed out further from ship for cleaner look
	var shield_radius := DEFAULT_SHIELD_RADIUS
	var ship_model := target_ship.get_node_or_null("ShipModel")
	if ship_model is ShipModel:
		shield_radius = ship_model.model_scale * 3.0

	# Impact direction in ship's local space (for shader)
	var impact_world := (hit_world_pos - target_ship.global_position)
	if impact_world.length_squared() < 0.01:
		impact_world = -target_ship.global_transform.basis.z
	var impact_local: Vector3 = target_ship.global_transform.basis.inverse() * impact_world.normalized()

	# === Load shader ===
	var shader := load("res://shaders/shield_hit.gdshader") as Shader
	if shader == null:
		push_warning("ShieldHitEffect: shader not found")
		queue_free()
		return

	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = shader
	_shield_mat.set_shader_parameter("impact_direction", impact_local)
	_shield_mat.set_shader_parameter("effect_time", 0.0)
	_shield_mat.set_shader_parameter("shield_health", shield_ratio)

	# === Sphere mesh (only a curved cap is visible via shader) ===
	var shield_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = shield_radius
	sphere.height = shield_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	shield_mesh.mesh = sphere
	shield_mesh.material_override = _shield_mat
	shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_mesh)

	# === Flash light at impact point on shield surface ===
	var flash_pos := impact_local * shield_radius
	_flash_light = OmniLight3D.new()
	_flash_light.position = flash_pos
	var flash_col := Color(0.12, 0.35, 1.0) if shield_ratio > 0.3 else Color(1.0, 0.3, 0.08)
	_flash_light.light_color = flash_col
	_flash_light.light_energy = 3.5 * _intensity
	_flash_light.omni_range = 20.0 * sqrt(_intensity)
	_flash_light.omni_attenuation = 1.8
	_flash_light.shadow_enabled = false
	add_child(_flash_light)

	# === Electric arc sparks at impact ===
	_create_sparks(flash_pos, impact_local, shield_ratio)


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return

	if _shield_mat:
		_shield_mat.set_shader_parameter("effect_time", _age)

	if _flash_light:
		_flash_light.light_energy = 3.5 * _intensity * maxf(0.0, 1.0 - _age * 5.0)


func _create_sparks(pos: Vector3, impact_dir: Vector3, shield_ratio: float) -> void:
	var sparks := GPUParticles3D.new()
	sparks.position = pos
	sparks.emitting = true
	sparks.one_shot = true
	sparks.amount = int(8 * _intensity)
	sparks.lifetime = 0.25
	sparks.explosiveness = 0.95
	sparks.randomness = 0.4
	sparks.local_coords = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = impact_dir
	mat.spread = 80.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 55.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 18.0
	mat.damping_max = 45.0
	mat.scale_min = 0.1
	mat.scale_max = 0.45

	var arc_col := Color(0.15, 0.4, 1.0) if shield_ratio > 0.3 else Color(1.0, 0.35, 0.1)

	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.6, 0.8, 1.0, 0.8),
		arc_col,
		Color(arc_col.r * 0.1, arc_col.g * 0.1, arc_col.b * 0.25, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	sparks.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 0.35)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.albedo_color = arc_col
	mesh_mat.emission_enabled = true
	mesh_mat.emission = arc_col
	mesh_mat.emission_energy_multiplier = 3.0
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	sparks.draw_pass_1 = mesh

	add_child(sparks)
