class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — Star Citizen style.
#
# TWO-PHASE expansion:
#   Phase 1 (SLOW  — 20 m/s, 0→50 m):
#     Camera is at ~25–50 m. The sphere expands slowly FROM the ship,
#     growing from a tiny dot to a ring that FILLS the screen over ~2.5 s.
#     You clearly watch it leave the ship. Then it passes through you.
#
#   Phase 2 (FAST  — 800 m/s, 50→2000 m):
#     Sphere zooms to full scan range in ~2.4 s. Camera is inside →
#     sphere not visible, but asteroids reveal themselves as the wave passes.
#
# Total: ~5 seconds.  No rings, no cull_disabled, no blue screen.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const MAX_RANGE  : float = 2000.0
const SPEED_SLOW : float = 20.0    # m/s — slow visible phase
const SPEED_FAST : float = 800.0   # m/s — fast scan phase
const SLOW_END   : float = 55.0    # m  — switch point

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
	_mat.set_shader_parameter("brightness", 5.0)
	_mat.set_shader_parameter("rim_power",  5.0)
	_mat.set_shader_parameter("fade",       1.0)
	_mesh.material_override = _mat
	add_child(_mesh)


func _build_flash() -> void:
	_flash_light              = OmniLight3D.new()
	_flash_light.light_color  = Color(0.35, 0.85, 1.0)
	_flash_light.light_energy = 80.0
	_flash_light.omni_range   = 600.0
	add_child(_flash_light)


func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta

	var speed : float = SPEED_SLOW if _current_radius < SLOW_END else SPEED_FAST
	_current_radius = minf(_current_radius + delta * speed, MAX_RANGE)

	# Flash decays over ~1 s
	if _flash_light != null:
		_flash_light.light_energy = maxf(0.0, 80.0 - _elapsed * 80.0)
		if _flash_light.light_energy <= 0.0:
			_flash_light.queue_free()
			_flash_light = null

	if _current_radius >= MAX_RANGE:
		_completed = true
		scan_completed.emit()
		_fade_out()
		return

	_mesh.scale = Vector3.ONE * _current_radius

	var range_fade : float = 1.0 - smoothstep(MAX_RANGE * 0.78, MAX_RANGE * 0.98, _current_radius)
	_mat.set_shader_parameter("fade", range_fade)

	scan_radius_updated.emit(_current_radius)


func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _mat.set_shader_parameter("fade", v),
		1.0, 0.0, 0.5
	)
	tw.tween_callback(queue_free)
