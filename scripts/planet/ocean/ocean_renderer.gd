class_name OceanRenderer
extends MeshInstance3D

# =============================================================================
# Ocean Renderer — Animated ocean sphere at the planet's ocean level.
# Uses the planet_ocean.gdshader for wave animation and reflections.
# Only created for planets with ocean_level > 0.
# =============================================================================

var _material: ShaderMaterial = null
var _ocean_radius: float = 0.0


func setup(planet_radius: float, pd: PlanetData) -> void:
	if pd.ocean_level < 0.001:
		visible = false
		return

	# Ocean surface at the ocean_level height
	_ocean_radius = planet_radius * (1.0 + pd.ocean_level * pd.get_terrain_amplitude())

	var sphere := SphereMesh.new()
	sphere.radius = _ocean_radius
	sphere.height = _ocean_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/planet/planet_ocean.gdshader")

	# Derive ocean colors from planet color
	var deep: Color = pd.color.darkened(0.5).lerp(Color(0.03, 0.12, 0.35), 0.6)
	var shallow: Color = pd.color.lerp(Color(0.1, 0.35, 0.6), 0.5)

	_material.set_shader_parameter("ocean_color_deep", deep)
	_material.set_shader_parameter("ocean_color_shallow", shallow)
	_material.set_shader_parameter("wave_speed", 0.25)
	_material.set_shader_parameter("wave_amplitude", planet_radius * 0.0001)  # Scale waves to planet
	_material.set_shader_parameter("wave_scale", 1.0 / planet_radius)
	_material.set_shader_parameter("specular_strength", 0.85)
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = true
