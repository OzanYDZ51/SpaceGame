class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — Visible wavefront ring.
#
# Single-speed expansion from ship to SCAN_RANGE.
# The shader renders a wide shell band with concentric rings and grid pattern,
# so the pulse stays visible even when the camera is inside the sphere.
#
# is_remote = true for pulses spawned from other players' scans:
#   → visual only, no scan_radius_updated signal emitted.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const MAX_RANGE    : float = 2500.0   # Matches AsteroidScanner.SCAN_RANGE (~half radar)
const PULSE_SPEED  : float = 800.0    # m/s — ~3.1 s total

var is_remote      : bool  = false

var _current_radius : float = 1.0
var _elapsed        : float = 0.0
var _completed      : bool  = false

var _mesh        : MeshInstance3D = null
var _mat         : ShaderMaterial = null
var _flash_light : OmniLight3D    = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_build_sphere()
	_build_flash()


func _build_sphere() -> void:
	_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius          = 1.0
	sph.height          = 2.0
	sph.radial_segments = 64
	sph.rings           = 32
	_mesh.mesh        = sph
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/scanner_pulse.gdshader")
	_mat.set_shader_parameter("brightness", 1.2)
	_mat.set_shader_parameter("rim_power",  4.0)
	_mat.set_shader_parameter("fade",       1.0)
	_mat.set_shader_parameter("shell_band", 0.08)
	_mat.set_shader_parameter("scan_progress", 0.0)
	_mesh.material_override = _mat
	add_child(_mesh)


func _build_flash() -> void:
	_flash_light              = OmniLight3D.new()
	_flash_light.light_color  = Color(0.35, 0.85, 1.0)
	_flash_light.light_energy = 5.0
	_flash_light.omni_range   = 150.0
	add_child(_flash_light)


func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta

	_current_radius = minf(_current_radius + delta * PULSE_SPEED, MAX_RANGE)

	var progress: float = _current_radius / MAX_RANGE

	# Light follows wavefront — persistent, fades only near the end
	if _flash_light != null:
		var light_fade: float = 1.0 - smoothstep(0.5, 0.99, progress)
		_flash_light.light_energy = 5.0 * light_fade
		_flash_light.omni_range = clampf(_current_radius * 0.15, 50.0, 400.0)
		if light_fade <= 0.01:
			_flash_light.queue_free()
			_flash_light = null

	if _current_radius >= MAX_RANGE:
		_completed = true
		scan_completed.emit()
		_fade_out()
		return

	_mesh.scale = Vector3.ONE * _current_radius

	# Delayed fade — stays bright until 90% of range
	var range_fade: float = 1.0 - smoothstep(MAX_RANGE * 0.90, MAX_RANGE * 0.99, _current_radius)
	_mat.set_shader_parameter("fade", range_fade)
	_mat.set_shader_parameter("scan_progress", progress)

	if not is_remote:
		scan_radius_updated.emit(_current_radius)


func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _mat.set_shader_parameter("fade", v),
		1.0, 0.0, 0.5
	)
	tw.tween_callback(queue_free)
