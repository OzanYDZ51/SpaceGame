class_name NebulaWisps
extends GPUParticles3D

# =============================================================================
# Nebula Wisps - Volumetric near-camera gas clouds
# Spawns large, faint, colored billboard particles around the player camera
# to simulate flying through nebula gas. Parented under Universe node for
# floating-origin compatibility.
#
# Color and opacity adapt to the current SystemEnvironmentData:
#   - nebula_warm / nebula_cool / nebula_accent → particle hue
#   - nebula_intensity → overall opacity (invisible in empty systems)
# =============================================================================

const WISP_SHADER_PATH := "res://shaders/nebula_wisp.gdshader"

# --- Config ---
const PARTICLE_COUNT: int = 50
const PARTICLE_LIFETIME: float = 10.0
const EMISSION_EXTENTS := Vector3(100.0, 50.0, 100.0)
const WISP_SIZE_MIN: float = 20.0
const WISP_SIZE_MAX: float = 40.0
const DRIFT_SPEED_MIN: float = 0.5
const DRIFT_SPEED_MAX: float = 2.0
const BASE_ALPHA: float = 0.015  # Extremely faint — subtle depth, not bright blobs

# --- Internal refs ---
var _camera: Camera3D = null
var _ship: ShipController = null
var _mat: ParticleProcessMaterial = null
var _shader_mat: ShaderMaterial = null
var _nebula_intensity: float = 0.35
var _wisp_color: Color = Color(0.12, 0.04, 0.15, BASE_ALPHA)


func _ready() -> void:
	_setup_process_material()
	_setup_draw_pass()

	amount = PARTICLE_COUNT
	lifetime = PARTICLE_LIFETIME
	local_coords = false
	emitting = true
	# Generous visibility AABB so particles don't cull when camera turns
	visibility_aabb = AABB(Vector3(-150, -80, -150), Vector3(300, 160, 300))


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func set_ship(ship: ShipController) -> void:
	_ship = ship


## Configure colors and opacity from the current system's environment data.
func configure_for_environment(env_data: SystemEnvironmentData) -> void:
	if env_data == null:
		_nebula_intensity = 0.0
		_update_visibility()
		return

	_nebula_intensity = env_data.nebula_intensity

	# Blend the three nebula colors into one average wisp tint
	var warm: Color = env_data.nebula_warm
	var cool: Color = env_data.nebula_cool
	var accent: Color = env_data.nebula_accent
	# Weighted blend: warm 40%, cool 35%, accent 25% — accent is the pop color
	var blended := Color(
		warm.r * 0.4 + cool.r * 0.35 + accent.r * 0.25,
		warm.g * 0.4 + cool.g * 0.35 + accent.g * 0.25,
		warm.b * 0.4 + cool.b * 0.35 + accent.b * 0.25,
		1.0,
	)
	# Brighten slightly so the additive blend is visible
	blended = blended * 1.2
	# Clamp to avoid oversaturation
	blended.r = clampf(blended.r, 0.0, 1.0)
	blended.g = clampf(blended.g, 0.0, 1.0)
	blended.b = clampf(blended.b, 0.0, 1.0)

	_wisp_color = Color(blended.r, blended.g, blended.b, BASE_ALPHA)

	# Update shader uniform
	if _shader_mat:
		var alpha_scaled: float = BASE_ALPHA * clampf(_nebula_intensity * 1.0, 0.0, 0.5)
		_shader_mat.set_shader_parameter("wisp_color",
			Color(_wisp_color.r, _wisp_color.g, _wisp_color.b, alpha_scaled))

	# Update color_ramp with the new nebula tint
	_update_color_ramp()
	_update_visibility()


func _process(_delta: float) -> void:
	# Follow camera position
	if _camera and is_instance_valid(_camera):
		global_position = _camera.global_position

	# Speed reactivity: stretch emission box and increase drift when moving fast
	if _ship and _mat:
		var speed_ratio: float = clampf(
			_ship.current_speed / maxf(Constants.MAX_SPEED_BOOST, 1.0), 0.0, 1.0)
		# Stretch emission along Z at speed (wisps stream past like space dust)
		var z_extent: float = EMISSION_EXTENTS.z + speed_ratio * 100.0
		_mat.emission_box_extents.z = z_extent
		# Slightly increase amount ratio at speed for denser feel
		amount_ratio = 0.6 + speed_ratio * 0.4


func _setup_process_material() -> void:
	var mat := ParticleProcessMaterial.new()

	# Large box emission centered on camera
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = EMISSION_EXTENTS

	# Very slow random drift — gas wisps float lazily
	mat.direction = Vector3.ZERO
	mat.initial_velocity_min = DRIFT_SPEED_MIN
	mat.initial_velocity_max = DRIFT_SPEED_MAX
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO

	# Slight turbulence for organic movement
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.5
	mat.turbulence_noise_speed_random = 0.3
	mat.turbulence_noise_speed = Vector3(0.1, 0.1, 0.1)
	mat.turbulence_influence_min = 0.1
	mat.turbulence_influence_max = 0.4

	# Scale: large gas clouds (20-40m), grow over lifetime
	mat.scale_min = WISP_SIZE_MIN
	mat.scale_max = WISP_SIZE_MAX

	# Scale curve: wisps grow from 60% to 100% over lifetime (gas expansion)
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.4, 0.85))
	curve.add_point(Vector2(1.0, 1.0))
	scale_curve.curve = curve
	mat.scale_curve = scale_curve

	# Color ramp: fade-in → hold → fade-out over lifetime
	_update_color_ramp_on_mat(mat)

	# Random rotation for variety
	mat.angle_min = 0.0
	mat.angle_max = 360.0

	_mat = mat
	process_material = mat


func _setup_draw_pass() -> void:
	# Load the custom wisp shader
	var shader := load(WISP_SHADER_PATH) as Shader
	if shader == null:
		push_warning("NebulaWisps: Could not load shader at %s" % WISP_SHADER_PATH)
		_setup_draw_pass_fallback()
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("wisp_color", _wisp_color)
	_shader_mat.set_shader_parameter("softness", 3.0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)  # Scale is handled by ParticleProcessMaterial
	mesh.material = _shader_mat
	draw_pass_1 = mesh


## Fallback if shader fails to load — uses StandardMaterial3D like SpaceDust
func _setup_draw_pass_fallback() -> void:
	var soft_tex := _create_soft_circle(32)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = soft_tex
	mesh_mat.albedo_color = _wisp_color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(_wisp_color.r, _wisp_color.g, _wisp_color.b)
	mesh_mat.emission_energy_multiplier = 0.4
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh_mat.no_depth_test = true
	mesh.material = mesh_mat
	draw_pass_1 = mesh


func _update_color_ramp() -> void:
	if _mat:
		_update_color_ramp_on_mat(_mat)


func _update_color_ramp_on_mat(mat: ParticleProcessMaterial) -> void:
	var c := _wisp_color
	# Intensity-scaled alpha for the hold phase
	var hold_alpha: float = clampf(_nebula_intensity * 0.8, 0.05, 0.3)

	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(c.r, c.g, c.b, 0.0),        # Fade in from invisible
		Color(c.r, c.g, c.b, hold_alpha),  # Ramp up
		Color(c.r, c.g, c.b, hold_alpha),  # Hold
		Color(c.r, c.g, c.b, 0.0),        # Fade out
	])
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.75, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex


func _update_visibility() -> void:
	# Hide wisps entirely in systems with negligible nebula
	if _nebula_intensity < 0.05:
		emitting = false
		visible = false
	else:
		visible = true
		emitting = true
		# Scale amount_ratio by nebula intensity
		amount_ratio = clampf(_nebula_intensity * 1.5, 0.2, 1.0)


func _create_soft_circle(tex_size: int = 32) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = tex_size
	tex.height = tex_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.8),
		Color(1.0, 1.0, 1.0, 0.3),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	tex.gradient = grad
	return tex
