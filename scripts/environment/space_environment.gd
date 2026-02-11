class_name SpaceEnvironment
extends Node3D

# =============================================================================
# Space Environment Setup
# Applies a SystemEnvironmentData to the scene (lighting + skybox).
# Data resolved by SystemEnvironmentRegistry (preset .tres + overrides).
# =============================================================================

@export_group("Default Star Light")
@export var default_star_color: Color = Color(0.95, 0.9, 0.85)
@export var default_star_energy: float = 2.2

@onready var star_light: DirectionalLight3D = $StarLight
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _current_env_data: SystemEnvironmentData = null
var _sun_direction: Vector3 = Vector3(0.0, -1.0, -0.5).normalized()


func _ready() -> void:
	if star_light:
		star_light.light_color = default_star_color
		star_light.light_energy = default_star_energy
		star_light.shadow_enabled = true
		star_light.shadow_bias = 0.02
		star_light.shadow_normal_bias = 1.0
		star_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		star_light.directional_shadow_max_distance = 50000.0  # 50 km — covers combat, docking, station approach
		star_light.directional_shadow_fade_start = 0.9


## Called by SystemTransition when entering a new system.
func configure_for_system(system_data: StarSystemData, system_id: int = -1) -> void:
	# Priority: StarSystemData.environment_override > env override .tres > spectral preset
	if system_data.environment_override:
		_current_env_data = system_data.environment_override
	else:
		_current_env_data = SystemEnvironmentRegistry.get_environment(
			system_id,
			system_data.star_spectral_class,
			system_data.seed_value,
			system_data.star_color,
			system_data.star_luminosity,
		)
	apply_environment(_current_env_data)

	# Set a default sun direction based on system seed (variety per system).
	# The actual direction can be updated later via update_sun_direction()
	# when the SystemStar node position is known relative to the camera.
	var rng := RandomNumberGenerator.new()
	rng.seed = system_data.seed_value + 7777
	var theta := rng.randf_range(0.0, TAU)
	var phi := rng.randf_range(0.3, 1.2)  # Avoid straight up/down
	var default_dir := Vector3(sin(phi) * cos(theta), -cos(phi), sin(phi) * sin(theta)).normalized()
	update_sun_direction(default_dir)


## Apply a SystemEnvironmentData to the scene. Can also be called directly
## with a custom resource for testing in the editor.
func apply_environment(env_data: SystemEnvironmentData) -> void:
	_current_env_data = env_data

	# --- Star light ---
	if star_light:
		star_light.light_color = env_data.star_light_color
		star_light.light_energy = env_data.star_light_energy

	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment

	# --- Ambient light ---
	# Use COLOR source (not SKY) so the shadow side of objects is actually dark.
	# SKY source floods ambient from the skybox in all directions, washing out shadows.
	# In space, the shadow side should be nearly black — only a faint fill.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = env_data.ambient_color
	env.ambient_light_energy = env_data.ambient_energy
	# Keep sky reflections for specular highlights (directional, not uniform)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# --- Glow / Bloom (HDR-driven, only very bright objects like the star bloom) ---
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.glow_strength = 1.0
	env.glow_hdr_threshold = 1.2
	env.glow_hdr_scale = 1.5
	env.glow_hdr_luminance_cap = 30.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# --- SSAO on, SSIL off in space ---
	# SSIL bounces light into shadow areas — wrong for space where shadows are hard.
	env.ssao_enabled = true
	env.ssil_enabled = false

	# --- Skybox shader parameters ---
	if env.sky == null or env.sky.sky_material == null:
		return
	var sky_mat: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	if sky_mat == null:
		return

	sky_mat.set_shader_parameter("nebula_warm",
		Vector3(env_data.nebula_warm.r, env_data.nebula_warm.g, env_data.nebula_warm.b))
	sky_mat.set_shader_parameter("nebula_cool",
		Vector3(env_data.nebula_cool.r, env_data.nebula_cool.g, env_data.nebula_cool.b))
	sky_mat.set_shader_parameter("nebula_accent",
		Vector3(env_data.nebula_accent.r, env_data.nebula_accent.g, env_data.nebula_accent.b))
	sky_mat.set_shader_parameter("nebula_intensity", env_data.nebula_intensity)
	sky_mat.set_shader_parameter("star_density", env_data.star_density)
	sky_mat.set_shader_parameter("star_brightness", env_data.star_brightness)
	sky_mat.set_shader_parameter("milky_way_intensity", env_data.milky_way_intensity)
	sky_mat.set_shader_parameter("milky_way_width", env_data.milky_way_width)
	sky_mat.set_shader_parameter("milky_way_color",
		Vector3(env_data.milky_way_color.r, env_data.milky_way_color.g, env_data.milky_way_color.b))
	sky_mat.set_shader_parameter("dust_intensity", env_data.dust_intensity)
	sky_mat.set_shader_parameter("god_ray_intensity", env_data.god_ray_intensity)
	sky_mat.set_shader_parameter("nebula_warp_strength", env_data.nebula_warp_strength)
	sky_mat.set_shader_parameter("nebula_emission_strength", env_data.nebula_emission_strength)
	sky_mat.set_shader_parameter("star_cluster_density", env_data.star_cluster_density)

	# Pass current sun direction to skybox
	sky_mat.set_shader_parameter("sun_direction", _sun_direction)


## Update the sun direction in the skybox shader and star light.
## Call this when the SystemStar position changes relative to the camera.
func update_sun_direction(direction: Vector3) -> void:
	_sun_direction = direction.normalized()

	# Update star light to match
	if star_light:
		# _sun_direction points TOWARD the sun. DirectionalLight3D shines along
		# its -Z axis, so we aim it in the OPPOSITE direction (from sun toward scene).
		var light_dir := -_sun_direction
		var target := star_light.global_position + light_dir
		# Safe up vector: avoid gimbal lock when sun is near vertical
		var up := Vector3.RIGHT if absf(light_dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		star_light.look_at(target, up)

	# Update skybox shader
	if world_env and world_env.environment and world_env.environment.sky:
		var sky_mat := world_env.environment.sky.sky_material as ShaderMaterial
		if sky_mat:
			sky_mat.set_shader_parameter("sun_direction", _sun_direction)
