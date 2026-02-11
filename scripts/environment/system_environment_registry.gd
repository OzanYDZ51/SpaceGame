class_name SystemEnvironmentRegistry
extends RefCounted

# =============================================================================
# System Environment Registry
# Resolves visual identity for any system:
#   1. Per-system override .tres  (data/environments/overrides/env_system_42.tres)
#   2. Spectral class preset .tres (data/environments/env_spectral_G.tres)
#      + seed-based randomization for variety
# =============================================================================

const PRESETS_PATH := "res://data/environments/"
const OVERRIDES_PATH := "res://data/environments/overrides/"

static var _cache: Dictionary = {}
static var _override_cache: Dictionary = {}
static var _preset_cache: Dictionary = {}


## Main entry point — returns the resolved environment for a system.
static func get_environment(
	system_id: int,
	spectral_class: String,
	seed_val: int,
	star_color: Color,
	star_luminosity: float,
) -> SystemEnvironmentData:
	# 1. Per-system override (highest priority)
	if _override_cache.has(system_id):
		return _override_cache[system_id]

	var override_path := OVERRIDES_PATH + "env_system_%d.tres" % system_id
	if ResourceLoader.exists(override_path):
		var override_data: SystemEnvironmentData = load(override_path)
		_override_cache[system_id] = override_data
		return override_data

	# 2. Generate from spectral preset + seed randomization
	var cache_key := "%s_%d" % [spectral_class, seed_val]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var preset := _load_spectral_preset(spectral_class)
	var data := _randomize(preset, seed_val, star_color, star_luminosity)
	_cache[cache_key] = data
	return data


## Clear caches (useful on galaxy change / wormhole).
static func clear_cache() -> void:
	_cache.clear()
	_override_cache.clear()


# ─── Internal ────────────────────────────────────────────────────────────────

static func _load_spectral_preset(spectral_class: String) -> SystemEnvironmentData:
	if _preset_cache.has(spectral_class):
		return _preset_cache[spectral_class]

	var path := PRESETS_PATH + "env_spectral_%s.tres" % spectral_class
	var preset: SystemEnvironmentData
	if ResourceLoader.exists(path):
		preset = load(path)
	else:
		# Fallback to G-class
		preset = load(PRESETS_PATH + "env_spectral_G.tres")

	_preset_cache[spectral_class] = preset
	return preset


## Randomize a preset copy based on system seed + star properties.
static func _randomize(
	base: SystemEnvironmentData,
	seed_val: int,
	star_color: Color,
	star_luminosity: float,
) -> SystemEnvironmentData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 9999

	var d := SystemEnvironmentData.new()

	# --- Star light (derived from star properties) ---
	d.star_light_color = star_color
	d.star_light_energy = clampf(star_luminosity * 0.8 + 1.0, 1.2, 4.0)

	# --- Ambient (tinted from star, intensity from luminosity) ---
	var ambient_tint := star_color.lerp(Color.WHITE, 0.6)
	d.ambient_color = Color(
		ambient_tint.r * base.ambient_color.r * 3.0,
		ambient_tint.g * base.ambient_color.g * 3.0,
		ambient_tint.b * base.ambient_color.b * 3.0,
	)
	d.ambient_energy = clampf(
		base.ambient_energy + (star_luminosity - 1.0) * 0.06,
		base.ambient_energy * 0.7,
		base.ambient_energy * 1.5,
	)

	# --- Glow (scaled by luminosity) ---
	d.glow_intensity = clampf(
		base.glow_intensity + star_luminosity * 0.1,
		base.glow_intensity * 0.8,
		base.glow_intensity * 1.4,
	)
	d.glow_bloom = clampf(
		base.glow_bloom + star_luminosity * 0.008,
		base.glow_bloom * 0.8,
		base.glow_bloom * 1.5,
	)

	# --- Nebula (preserve base hue, vary saturation/brightness ±20%) ---
	d.nebula_warm = Color(
		base.nebula_warm.r * rng.randf_range(0.8, 1.2),
		base.nebula_warm.g * rng.randf_range(0.8, 1.2),
		base.nebula_warm.b * rng.randf_range(0.8, 1.2),
	)
	d.nebula_cool = Color(
		base.nebula_cool.r * rng.randf_range(0.8, 1.2),
		base.nebula_cool.g * rng.randf_range(0.8, 1.2),
		base.nebula_cool.b * rng.randf_range(0.8, 1.2),
	)
	d.nebula_accent = Color(
		base.nebula_accent.r * rng.randf_range(0.8, 1.2),
		base.nebula_accent.g * rng.randf_range(0.8, 1.2),
		base.nebula_accent.b * rng.randf_range(0.8, 1.2),
	)
	d.nebula_intensity = rng.randf_range(
		base.nebula_intensity * 0.8, base.nebula_intensity * 1.3
	)

	# --- Stars ---
	d.star_density = rng.randf_range(
		base.star_density * 0.85, base.star_density * 1.15
	)
	d.star_brightness = rng.randf_range(
		base.star_brightness * 0.9, base.star_brightness * 1.1
	)

	# --- Milky Way ---
	d.milky_way_intensity = rng.randf_range(
		base.milky_way_intensity * 0.7, base.milky_way_intensity * 1.3
	)
	d.milky_way_width = base.milky_way_width
	d.milky_way_color = base.milky_way_color.lerp(
		Color(
			0.04 + rng.randf() * 0.06,
			0.03 + rng.randf() * 0.06,
			0.06 + rng.randf() * 0.10
		), 0.3
	)

	# --- Dust ---
	d.dust_intensity = rng.randf_range(
		base.dust_intensity * 0.7, base.dust_intensity * 1.3
	)

	# --- God Rays ---
	d.god_ray_intensity = rng.randf_range(
		base.god_ray_intensity * 0.7, base.god_ray_intensity * 1.3
	)

	# --- Nebula Detail ---
	d.nebula_warp_strength = rng.randf_range(
		base.nebula_warp_strength * 0.8, base.nebula_warp_strength * 1.3
	)
	d.nebula_emission_strength = rng.randf_range(
		base.nebula_emission_strength * 0.7, base.nebula_emission_strength * 1.3
	)

	# --- Star Clusters ---
	d.star_cluster_density = rng.randf_range(
		base.star_cluster_density * 0.7, base.star_cluster_density * 1.4
	)

	return d
