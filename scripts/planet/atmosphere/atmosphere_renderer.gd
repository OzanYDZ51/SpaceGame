class_name AtmosphereRenderer
extends MeshInstance3D

# =============================================================================
# Atmosphere Renderer — Sphere mesh with Rayleigh+Mie scatter shader
# Slightly larger than the planet, visible from both sides (space + surface).
# =============================================================================

var _material: ShaderMaterial = null


func setup(planet_radius: float, atmo_config: AtmosphereConfig) -> void:
	if atmo_config.density < 0.01:
		visible = false
		return

	var atmo_radius: float = planet_radius * atmo_config.atmosphere_scale

	# Sphere mesh
	var sphere := SphereMesh.new()
	sphere.radius = atmo_radius
	sphere.height = atmo_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	# Shader material
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/planet/planet_atmosphere.gdshader")
	_material.set_shader_parameter("glow_color", atmo_config.glow_color)
	_material.set_shader_parameter("glow_intensity", atmo_config.glow_intensity)
	_material.set_shader_parameter("glow_falloff", atmo_config.glow_falloff)
	_material.set_shader_parameter("atmosphere_density", atmo_config.density)

	# Rayleigh scatter parameters
	_material.set_shader_parameter("scatter_color", atmo_config.scatter_color)
	_material.set_shader_parameter("planet_radius_norm", planet_radius / atmo_radius)
	_material.set_shader_parameter("atmosphere_height", atmo_radius - planet_radius)

	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Update atmosphere density (for transition effects).
func set_density(density: float) -> void:
	if _material:
		_material.set_shader_parameter("atmosphere_density", density)


## Update sun direction for lighting.
func update_sun_direction(sun_dir: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_direction", sun_dir)
