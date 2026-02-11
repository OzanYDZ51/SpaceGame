class_name CloudLayer
extends MeshInstance3D

# =============================================================================
# Cloud Layer — Animated cloud sphere between atmosphere and planet surface.
# Visible from space (white patches) and from below (shadows on terrain).
# Uses a FBM noise shader for procedural clouds.
# =============================================================================

var _material: ShaderMaterial = null
var _cloud_radius: float = 0.0


func setup(planet_radius: float, atmo_config: AtmosphereConfig) -> void:
	if atmo_config.density < 0.15:
		visible = false
		return

	# Clouds sit at ~2% above surface (below atmosphere edge)
	_cloud_radius = planet_radius * 1.02

	var sphere := SphereMesh.new()
	sphere.radius = _cloud_radius
	sphere.height = _cloud_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/planet/planet_clouds.gdshader")
	_material.set_shader_parameter("cloud_coverage", clampf(atmo_config.density * 0.45, 0.15, 0.7))
	_material.set_shader_parameter("cloud_color", Color(1.0, 1.0, 1.0, 1.0))
	_material.set_shader_parameter("cloud_shadow_color", atmo_config.glow_color.darkened(0.6))
	_material.set_shader_parameter("cloud_speed", 0.008)
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = true


## Update sun direction for cloud lighting.
func update_sun_direction(sun_dir: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_direction", sun_dir)
