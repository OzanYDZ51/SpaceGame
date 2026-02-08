class_name SpaceEnvironment
extends Node3D

# =============================================================================
# Space Environment Setup
# Applies a SystemEnvironmentData to the scene (lighting + skybox).
# Data resolved by SystemEnvironmentRegistry (preset .tres + overrides).
# =============================================================================

@export_group("Default Star Light")
@export var default_star_color: Color = Color(0.95, 0.9, 0.85)
@export var default_star_energy: float = 1.0

@onready var star_light: DirectionalLight3D = $StarLight
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _current_env_data: SystemEnvironmentData = null


func _ready() -> void:
	if star_light:
		star_light.light_color = default_star_color
		star_light.light_energy = default_star_energy
		star_light.shadow_enabled = false


## Called by SystemTransition when entering a new system.
func configure_for_system(system_data: StarSystemData, system_id: int = -1) -> void:
	_current_env_data = SystemEnvironmentRegistry.get_environment(
		system_id,
		system_data.star_spectral_class,
		system_data.seed_value,
		system_data.star_color,
		system_data.star_luminosity,
	)
	apply_environment(_current_env_data)


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
	env.ambient_light_color = env_data.ambient_color
	env.ambient_light_energy = env_data.ambient_energy

	# --- Glow ---
	env.glow_intensity = env_data.glow_intensity
	env.glow_bloom = env_data.glow_bloom

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
