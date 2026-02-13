class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — 3D expanding sphere wave for asteroid scanning
# Spawns at ship position, expands outward, auto-frees on completion.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const PULSE_SPEED: float = 2000.0   # m/s
const MAX_RANGE: float = 5000.0     # 5 km
const RING_WIDTH: float = 80.0

var _current_radius: float = 0.0
var _elapsed: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _shader_mat: ShaderMaterial = null
var _light: OmniLight3D = null
var _completed: bool = false


func _ready() -> void:
	# Sphere mesh (unit sphere, scaled dynamically)
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_mesh_instance.mesh = sphere
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Shader material
	_shader_mat = ShaderMaterial.new()
	var shader := load("res://shaders/scanner_pulse.gdshader") as Shader
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("pulse_radius", 0.0)
	_shader_mat.set_shader_parameter("max_radius", MAX_RANGE)
	_shader_mat.set_shader_parameter("ring_width", RING_WIDTH)
	_shader_mat.set_shader_parameter("pulse_color", Color(0.0, 0.85, 0.95, 1.0))
	_shader_mat.set_shader_parameter("time_val", 0.0)
	_mesh_instance.material_override = _shader_mat
	add_child(_mesh_instance)

	# Initial flash light
	_light = OmniLight3D.new()
	_light.light_color = Color(0.0, 0.85, 0.95)
	_light.light_energy = 4.0
	_light.omni_range = 50.0
	_light.omni_attenuation = 2.0
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
		tw.tween_property(_mesh_instance, "transparency", 1.0, 0.3)
		tw.tween_callback(queue_free)
		return

	# Scale sphere to current radius
	var s: float = _current_radius
	_mesh_instance.scale = Vector3(s, s, s)

	# Update shader params
	_shader_mat.set_shader_parameter("pulse_radius", _current_radius)
	_shader_mat.set_shader_parameter("time_val", _elapsed)

	# Fade flash light
	if _light:
		_light.light_energy = maxf(0.0, 4.0 - _elapsed * 4.0)
		if _light.light_energy <= 0.0:
			_light.queue_free()
			_light = null

	scan_radius_updated.emit(_current_radius)
