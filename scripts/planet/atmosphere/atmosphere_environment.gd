class_name AtmosphereEnvironment
extends Node

# =============================================================================
# Atmosphere Environment — Transitions the visual environment when entering
# a planet's atmosphere. Manages fog, sky dimming, ambient light, sun color.
# Creates a completely different visual feel on the planet surface.
# =============================================================================

var _space_env: Environment = null
var _dir_light: DirectionalLight3D = null
var _atmo_config: AtmosphereConfig = null

# Saved space values (restored when leaving)
var _space_fog_enabled: bool = false
var _space_fog_density: float = 0.0
var _space_ambient_source: int = 0
var _space_ambient_energy: float = 0.0
var _space_light_energy: float = 1.0
var _space_light_color: Color = Color.WHITE
var _space_tonemap_white: float = 1.0

# Current blend factor (0 = space, 1 = full atmosphere)
var _blend: float = 0.0
var _target_blend: float = 0.0

# Atmosphere visual params (from AtmosphereConfig)
var _fog_color: Color = Color(0.6, 0.75, 1.0)
var _fog_density: float = 0.0003
var _sky_color: Color = Color(0.4, 0.6, 1.0)
var _ambient_energy: float = 0.4
var _sun_energy_mult: float = 1.3
var _is_setup: bool = false


func setup(env: Environment, dir_light: DirectionalLight3D) -> void:
	_space_env = env
	_dir_light = dir_light
	if env == null:
		return

	# Save space defaults
	_space_fog_enabled = env.fog_enabled
	_space_fog_density = env.fog_density
	_space_ambient_source = env.ambient_light_source
	_space_ambient_energy = env.ambient_light_energy
	_space_tonemap_white = env.tonemap_white
	if dir_light:
		_space_light_energy = dir_light.light_energy
		_space_light_color = dir_light.light_color
	_is_setup = true


func configure_for_planet(atmo_config: AtmosphereConfig) -> void:
	_atmo_config = atmo_config
	if atmo_config == null:
		return
	# Derive fog/sky from atmosphere config
	_fog_color = atmo_config.glow_color.lerp(Color(0.7, 0.78, 0.88), 0.5)
	_sky_color = atmo_config.glow_color.lerp(Color(0.4, 0.55, 0.9), 0.3)
	_fog_density = 0.0001 * atmo_config.density
	_ambient_energy = 0.3 * atmo_config.density
	_sun_energy_mult = 1.0 + atmo_config.density * 0.4


func set_target_blend(blend: float) -> void:
	_target_blend = clampf(blend, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _is_setup or _space_env == null:
		return

	# Smooth interpolation toward target
	var speed: float = 1.5 if _target_blend > _blend else 2.5  # Faster exit
	_blend = lerpf(_blend, _target_blend, delta * speed)

	# Clamp tiny values
	if _blend < 0.001:
		_blend = 0.0
		_restore_space()
		return

	_apply_atmosphere()


func _apply_atmosphere() -> void:
	var env := _space_env
	var t := _blend

	# Fog: grows from 0 to max density
	env.fog_enabled = true
	env.fog_light_color = _fog_color
	env.fog_density = lerpf(0.0, _fog_density, t * t)  # Quadratic ramp
	env.fog_sky_affect = lerpf(0.0, 0.8, t)
	env.fog_light_energy = lerpf(0.0, 1.2, t)

	# Ambient: add planetary ambient light
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if t > 0.3 else _space_ambient_source
	env.ambient_light_color = _sky_color
	env.ambient_light_energy = lerpf(_space_ambient_energy, _ambient_energy, t)

	# Tonemap: slightly brighter on surface
	env.tonemap_white = lerpf(_space_tonemap_white, _space_tonemap_white * 1.15, t)

	# Sun: warmer and brighter in atmosphere (scattered light)
	if _dir_light:
		_dir_light.light_energy = lerpf(_space_light_energy, _space_light_energy * _sun_energy_mult, t)
		var warm := _space_light_color.lerp(Color(1.0, 0.95, 0.85), t * 0.3)
		_dir_light.light_color = warm


func _restore_space() -> void:
	var env := _space_env
	env.fog_enabled = _space_fog_enabled
	env.fog_density = _space_fog_density
	env.ambient_light_source = _space_ambient_source
	env.ambient_light_energy = _space_ambient_energy
	env.tonemap_white = _space_tonemap_white
	if _dir_light:
		_dir_light.light_energy = _space_light_energy
		_dir_light.light_color = _space_light_color


## Hard reset (when leaving system or docking).
func reset() -> void:
	_blend = 0.0
	_target_blend = 0.0
	_atmo_config = null
	if _is_setup:
		_restore_space()
