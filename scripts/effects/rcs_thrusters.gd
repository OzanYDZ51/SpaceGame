class_name RCSThrusters
extends Node3D

# =============================================================================
# RCS Thrusters - Maneuvering thruster puffs on ship surface
# Child of ShipModel. Continuous low-count emitters toggled by input.
# 8 thruster positions: 4 for translation, 4 for rotation.
# =============================================================================

var _thruster_data: Array[Dictionary] = []  # {direction: Vector3, node: GPUParticles3D}
var _model_scale: float = 1.0

# Thruster layout: position offset + activation direction
const THRUSTER_CONFIG := [
	# Translation thrusters
	{"pos": Vector3(2.5, 0.0, 0.0), "dir": Vector3(-1, 0, 0)},    # Right side -> fires when strafing left
	{"pos": Vector3(-2.5, 0.0, 0.0), "dir": Vector3(1, 0, 0)},    # Left side -> fires when strafing right
	{"pos": Vector3(0.0, 1.5, 0.0), "dir": Vector3(0, -1, 0)},    # Top -> fires when moving down
	{"pos": Vector3(0.0, -1.5, 0.0), "dir": Vector3(0, 1, 0)},    # Bottom -> fires when moving up
	# Rotation thrusters (nose)
	{"pos": Vector3(1.5, 0.0, -4.0), "dir": Vector3(-1, 0, 0)},   # Nose right -> fires on yaw left
	{"pos": Vector3(-1.5, 0.0, -4.0), "dir": Vector3(1, 0, 0)},   # Nose left -> fires on yaw right
	# Rotation thrusters (tail)
	{"pos": Vector3(1.5, 0.0, 4.0), "dir": Vector3(1, 0, 0)},     # Tail right -> fires on yaw left
	{"pos": Vector3(-1.5, 0.0, 4.0), "dir": Vector3(-1, 0, 0)},   # Tail left -> fires on yaw right
]

const FIRE_THRESHOLD: float = 0.15


func setup(p_model_scale: float, vfx_points: Array[Dictionary] = []) -> void:
	_model_scale = p_model_scale
	var soft_tex := _create_soft_circle(16)

	# Collect RCS configs from VFX attach points or use hardcoded defaults
	var rcs_configs: Array[Dictionary] = []
	for pt in vfx_points:
		if pt.get("type") == &"RCS":
			# Activation direction = opposite of emission (force direction)
			rcs_configs.append({
				"pos": pt["position"],
				"activation": -pt["direction"],
				"prescaled": true,
			})

	if rcs_configs.is_empty():
		for cfg in THRUSTER_CONFIG:
			rcs_configs.append({
				"pos": cfg["pos"],
				"activation": cfg["dir"],
				"prescaled": false,
			})

	for cfg in rcs_configs:
		var p := _create_emitter(soft_tex, p_model_scale)
		p.position = cfg["pos"] if cfg["prescaled"] else cfg["pos"] * p_model_scale
		add_child(p)
		_thruster_data.append({"direction": cfg["activation"], "node": p})


func _process(_delta: float) -> void:
	var ship := _get_ship()
	if ship == null:
		return

	var throttle: Vector3 = ship.throttle_input
	var ang_vel: Vector3 = ship.angular_velocity

	for td in _thruster_data:
		var dir: Vector3 = td["direction"]
		var p: GPUParticles3D = td["node"]

		# Translation activation
		var activation: float = maxf(0.0, dir.dot(throttle))
		# Rotation: lateral thrusters respond to yaw, vertical to pitch
		activation = maxf(activation, absf(ang_vel.y) * absf(dir.x) * 0.5)
		activation = maxf(activation, absf(ang_vel.x) * absf(dir.y) * 0.5)

		p.emitting = activation > FIRE_THRESHOLD


func _get_ship() -> ShipController:
	# Walk up: RCSThrusters -> ShipModel -> ShipController
	var model := get_parent()
	if model:
		var ship := model.get_parent()
		if ship is ShipController:
			return ship as ShipController
	return null


func _create_emitter(soft_tex: GradientTexture2D, ms: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.15 * ms
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 25.0
	mat.initial_velocity_min = 3.0 * ms
	mat.initial_velocity_max = 6.0 * ms
	mat.gravity = Vector3.ZERO
	mat.damping_min = 3.0
	mat.damping_max = 6.0
	mat.scale_min = 0.3 * ms
	mat.scale_max = 0.6 * ms

	# Color: white-blue puff that fades quickly
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.8, 0.9, 1.0, 0.7),
		Color(0.5, 0.7, 1.0, 0.3),
		Color(0.3, 0.5, 0.8, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	p.process_material = mat
	p.amount = 5
	p.lifetime = 0.15
	p.emitting = false
	p.local_coords = true

	# Soft particle mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15) * ms
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = soft_tex
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(0.4, 0.6, 1.0)
	mesh_mat.emission_energy_multiplier = 1.5
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	p.draw_pass_1 = mesh

	return p


func _create_soft_circle(tex_size: int = 16) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = tex_size
	tex.height = tex_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.4),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	tex.gradient = grad
	return tex
