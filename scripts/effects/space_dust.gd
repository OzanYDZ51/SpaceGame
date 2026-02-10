class_name SpaceDust
extends GPUParticles3D

# =============================================================================
# Space Dust - Ambient particles that create a visceral sense of speed
# Parented under Universe node (floating origin compatible).
# _process() follows camera position so particles stream past as ship moves.
# Uses soft radial gradient for smooth glowing motes, not hard quads.
# =============================================================================

var _camera: Camera3D = null
var _ship: ShipController = null
var _base_amount_ratio: float = 1.0
var _base_speed_scale: float = 1.0
var _mat: ParticleProcessMaterial = null


func _ready() -> void:
	var mat := ParticleProcessMaterial.new()

	# Large box emission around the camera
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(80.0, 40.0, 100.0)

	# Near-zero velocity: particles are mostly stationary in world space
	mat.direction = Vector3.ZERO
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.5
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO

	mat.scale_min = 0.7
	mat.scale_max = 1.8

	# Color ramp: fade in, hold, fade out — subtle dim blue-white
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.4, 0.5, 0.8, 0.0),
		Color(0.5, 0.6, 0.85, 0.2),
		Color(0.45, 0.55, 0.8, 0.15),
		Color(0.3, 0.4, 0.65, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.08, 0.75, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	_mat = mat
	process_material = mat
	amount = 120
	lifetime = 4.0
	local_coords = false
	emitting = true

	# Soft glowing particle mesh
	var soft_tex := _create_soft_circle(24)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.25, 0.25)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = soft_tex
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(0.3, 0.45, 0.7)
	mesh_mat.emission_energy_multiplier = 0.6
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	draw_pass_1 = mesh


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func set_ship(ship: ShipController) -> void:
	_ship = ship


func _process(_delta: float) -> void:
	if _camera:
		global_position = _camera.global_position

	# Speed-reactive dust: more particles + faster + stretched box at high speed
	if _ship and _mat:
		# Use boost max as reference (cruise is warp territory, dust irrelevant)
		var speed_ratio: float = clampf(_ship.current_speed / maxf(Constants.MAX_SPEED_BOOST, 1.0), 0.0, 1.0)
		amount_ratio = 0.3 + speed_ratio * 0.7
		speed_scale = 0.5 + speed_ratio * 2.5
		# Stretch emission box along Z at speed (particles stream past)
		var z_extent: float = 100.0 + speed_ratio * 200.0
		_mat.emission_box_extents.z = z_extent


func _create_soft_circle(tex_size: int = 24) -> GradientTexture2D:
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
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	tex.gradient = grad
	return tex
