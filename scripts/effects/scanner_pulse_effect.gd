class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — Sonar bubble with Fresnel rim.
# Uses cull_disabled shader → single sphere works from inside & outside.
# Expands at PULSE_SPEED m/s. Emits scan_radius_updated each frame so
# AsteroidScanner can reveal asteroids in real-time as the wave crosses them.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const PULSE_SPEED: float = 2000.0
const MAX_RANGE: float = 5000.0
const START_RADIUS: float = 5.0

var _current_radius: float = START_RADIUS
var _elapsed: float = 0.0
var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _flash_light: OmniLight3D = null
var _completed: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_build_sphere()
	_build_flash()


func _build_sphere() -> void:
	_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 48
	sph.rings = 24
	_mesh.mesh = sph
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * START_RADIUS

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/scanner_pulse.gdshader")
	_mat.set_shader_parameter("fade", 1.0)
	_mesh.material_override = _mat
	add_child(_mesh)


func _build_flash() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(0.5, 0.85, 1.0)
	_flash_light.light_energy = 120.0
	_flash_light.omni_range = 600.0
	add_child(_flash_light)


func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta
	_current_radius = START_RADIUS + _elapsed * PULSE_SPEED

	# Flash light: bright burst, decays in ~0.6s
	if _flash_light != null:
		_flash_light.light_energy = maxf(0.0, 120.0 - _elapsed * 200.0)
		if _flash_light.light_energy <= 0.0:
			_flash_light.queue_free()
			_flash_light = null

	if _current_radius >= MAX_RANGE:
		_current_radius = MAX_RANGE
		_completed = true
		scan_completed.emit()
		_fade_out()
		return

	var r := _current_radius
	_mesh.scale = Vector3.ONE * r

	# Range fade: start at 70%, reach 0 at 96%
	var range_fade: float = 1.0 - smoothstep(MAX_RANGE * 0.70, MAX_RANGE * 0.96, r)
	_mat.set_shader_parameter("fade", range_fade)

	scan_radius_updated.emit(_current_radius)


func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _mat.set_shader_parameter("fade", v),
		1.0, 0.0, 0.5
	)
	tw.tween_callback(queue_free)
