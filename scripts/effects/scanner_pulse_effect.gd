class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — Expanding 3D bubble shell (sonar style)
# Sphere mesh pre-scaled to MAX_RANGE. Shader draws a thin bright shell
# at pulse_radius that moves outward. Visible from inside and outside.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const PULSE_SPEED: float = 2000.0   # m/s
const MAX_RANGE: float = 5000.0     # 5 km

var _current_radius: float = 0.0
var _elapsed: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _shader_mat: ShaderMaterial = null
var _light: OmniLight3D = null
var _completed: bool = false


func _ready() -> void:
	# Sphere mesh — pre-scaled to full range, shader controls where the shell appears
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh_instance.mesh = sphere
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.scale = Vector3(MAX_RANGE, MAX_RANGE, MAX_RANGE)
	_mesh_instance.custom_aabb = AABB(
		Vector3(-MAX_RANGE, -MAX_RANGE, -MAX_RANGE),
		Vector3(MAX_RANGE * 2, MAX_RANGE * 2, MAX_RANGE * 2)
	)

	# Shader material
	_shader_mat = ShaderMaterial.new()
	var shader := load("res://shaders/scanner_pulse.gdshader") as Shader
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("pulse_radius", 0.0)
	_shader_mat.set_shader_parameter("max_radius", MAX_RANGE)
	_shader_mat.set_shader_parameter("pulse_color", Color(0.0, 0.85, 0.95, 1.0))
	_shader_mat.set_shader_parameter("time_val", 0.0)
	_shader_mat.set_shader_parameter("opacity", 1.0)
	_mesh_instance.material_override = _shader_mat
	add_child(_mesh_instance)

	# Initial flash light at center
	_light = OmniLight3D.new()
	_light.light_color = Color(0.0, 0.85, 0.95)
	_light.light_energy = 8.0
	_light.omni_range = 60.0
	_light.omni_attenuation = 1.5
	add_child(_light)


func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta
	_current_radius = _elapsed * PULSE_SPEED

	if _current_radius >= MAX_RANGE:
		_current_radius = MAX_RANGE
		_completed = true
		scan_completed.emit()
		# Fade out and free
		var tw := create_tween()
		tw.tween_method(func(v: float): _shader_mat.set_shader_parameter("opacity", v), 1.0, 0.0, 0.4)
		tw.tween_callback(queue_free)
		return

	# Shader drives the visual — shell moves outward through the static sphere
	_shader_mat.set_shader_parameter("pulse_radius", _current_radius)
	_shader_mat.set_shader_parameter("time_val", _elapsed)

	# Fade flash light quickly
	if _light:
		_light.light_energy = maxf(0.0, 8.0 - _elapsed * 16.0)
		if _light.light_energy <= 0.0:
			_light.queue_free()
			_light = null

	scan_radius_updated.emit(_current_radius)
