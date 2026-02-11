class_name CityLightsLayer
extends MeshInstance3D

# =============================================================================
# City Lights Layer — Night-side emissive glow visible from orbit.
# Sphere mesh at 1.002× planet radius with additive noise-driven shader.
# Only created for planets with has_civilization = true.
# =============================================================================

var _material: ShaderMaterial = null


func setup(planet_radius: float, seed_val: int) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius * 1.002
	sphere.height = planet_radius * 2.004
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	var shader := load("res://shaders/planet/planet_city_lights.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("city_seed", seed_val)
	material_override = _material

	# Render behind terrain but above ocean
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func update_sun_direction(sun_dir: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_direction", sun_dir)
