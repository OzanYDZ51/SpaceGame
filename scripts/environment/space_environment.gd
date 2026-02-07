class_name SpaceEnvironment
extends Node3D

# =============================================================================
# Space Environment Setup
# Configures lighting + skybox per star system.
# Skybox is handled by the Sky resource in WorldEnvironment (always at infinity).
# =============================================================================

@export_group("Default Star Light")
@export var default_star_color: Color = Color(1.0, 0.95, 0.9)
@export var default_star_energy: float = 1.5

@onready var star_light: DirectionalLight3D = $StarLight
@onready var world_env: WorldEnvironment = $WorldEnvironment

# Spectral class → nebula color palettes
const NEBULA_PALETTES := {
	"M": { "warm": Color(0.18, 0.03, 0.02), "cool": Color(0.05, 0.02, 0.08), "accent": Color(0.10, 0.01, 0.06) },
	"K": { "warm": Color(0.14, 0.04, 0.03), "cool": Color(0.03, 0.03, 0.09), "accent": Color(0.08, 0.02, 0.10) },
	"G": { "warm": Color(0.12, 0.02, 0.04), "cool": Color(0.02, 0.03, 0.10), "accent": Color(0.06, 0.01, 0.12) },
	"F": { "warm": Color(0.08, 0.03, 0.06), "cool": Color(0.03, 0.04, 0.12), "accent": Color(0.05, 0.02, 0.14) },
	"A": { "warm": Color(0.06, 0.04, 0.10), "cool": Color(0.02, 0.05, 0.15), "accent": Color(0.04, 0.03, 0.16) },
	"B": { "warm": Color(0.04, 0.03, 0.14), "cool": Color(0.01, 0.04, 0.18), "accent": Color(0.03, 0.02, 0.20) },
	"O": { "warm": Color(0.03, 0.04, 0.18), "cool": Color(0.01, 0.05, 0.22), "accent": Color(0.02, 0.03, 0.25) },
}


func _ready() -> void:
	if star_light:
		star_light.light_color = default_star_color
		star_light.light_energy = default_star_energy
		star_light.shadow_enabled = false


func configure_for_system(system_data: StarSystemData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = system_data.seed_value + 9999  # Offset to not correlate with planet gen

	# --- Star light ---
	if star_light:
		star_light.light_color = system_data.star_color
		star_light.light_energy = clampf(system_data.star_luminosity * 0.5 + 0.8, 0.8, 3.0)

	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment

	# --- Ambient light tinted by star ---
	var ambient_tint := system_data.star_color.lerp(Color.WHITE, 0.6)
	env.ambient_light_color = Color(ambient_tint.r * 0.08, ambient_tint.g * 0.08, ambient_tint.b * 0.12, 1.0)
	env.ambient_light_energy = clampf(0.15 + system_data.star_luminosity * 0.05, 0.15, 0.4)

	# --- Glow tweaks per star type ---
	env.glow_intensity = clampf(0.6 + system_data.star_luminosity * 0.1, 0.6, 1.2)
	env.glow_bloom = clampf(0.1 + system_data.star_luminosity * 0.02, 0.1, 0.25)

	# --- Skybox shader parameters ---
	if env.sky == null or env.sky.sky_material == null:
		return
	var sky_mat: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	if sky_mat == null:
		return

	var spectral: String = system_data.star_spectral_class
	var palette: Dictionary = NEBULA_PALETTES.get(spectral, NEBULA_PALETTES["G"])

	# Nebula colors with slight randomization
	var warm := palette["warm"] as Color
	var cool := palette["cool"] as Color
	var accent := palette["accent"] as Color
	warm = warm.lerp(Color(rng.randf() * 0.1, rng.randf() * 0.05, rng.randf() * 0.05), 0.3)
	cool = cool.lerp(Color(rng.randf() * 0.05, rng.randf() * 0.05, rng.randf() * 0.1), 0.3)
	accent = accent.lerp(Color(rng.randf() * 0.05, rng.randf() * 0.03, rng.randf() * 0.1), 0.3)

	sky_mat.set_shader_parameter("nebula_warm", Vector3(warm.r, warm.g, warm.b))
	sky_mat.set_shader_parameter("nebula_cool", Vector3(cool.r, cool.g, cool.b))
	sky_mat.set_shader_parameter("nebula_accent", Vector3(accent.r, accent.g, accent.b))
	sky_mat.set_shader_parameter("nebula_intensity", rng.randf_range(0.15, 0.5))
	sky_mat.set_shader_parameter("star_density", rng.randf_range(0.4, 0.8))
	sky_mat.set_shader_parameter("star_brightness", rng.randf_range(1.8, 2.8))
	sky_mat.set_shader_parameter("milky_way_intensity", rng.randf_range(0.4, 0.9))
	sky_mat.set_shader_parameter("dust_intensity", rng.randf_range(0.2, 0.7))
	sky_mat.set_shader_parameter("milky_way_color", Vector3(
		0.08 + rng.randf() * 0.08,
		0.06 + rng.randf() * 0.08,
		0.10 + rng.randf() * 0.10,
	))
