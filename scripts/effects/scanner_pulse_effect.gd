class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — Slow sonar bubble visible to the naked eye.
#
# VISUAL APPROACH:
#   - 1 outer sphere  (Fresnel, no flip_faces): dramatic initial burst when
#     camera is outside (~0.5 s). Clean disappearance once camera enters.
#   - 3 thin orthogonal rings (CylinderMesh): ALWAYS visible from any camera
#     angle for the full duration. No screen-filling. No blue screen.
#
# TIMING:
#   - Speed: 120 m/s  (slow — clearly watchable)
#   - Range: 1200 m   → 10 seconds total
#   - Camera (25–50 m behind ship) sees outer sphere for ~0.2–0.4 s.
#   - Rings visible for all 10 s.
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const MAX_RANGE   : float = 1200.0
const PULSE_SPEED : float = 120.0    # m/s — slow, clearly visible

var _current_radius : float = 1.0
var _elapsed        : float = 0.0
var _completed      : bool  = false

var _sphere_mesh : MeshInstance3D   = null
var _mat_sphere  : ShaderMaterial   = null
var _rings       : Array            = []    # Array[MeshInstance3D]
var _mat_rings   : ShaderMaterial   = null  # shared by all 3 rings
var _flash_light : OmniLight3D      = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_build_outer_sphere()
	_build_rings()
	_build_flash()


# ---------------------------------------------------------------------------
#  Outer sphere — Fresnel shell, visible from OUTSIDE only.
#  Gives the dramatic "bubble leaving the ship" moment for ~0.3–0.5 s.
# ---------------------------------------------------------------------------
func _build_outer_sphere() -> void:
	_sphere_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 64
	sph.rings = 32
	_sphere_mesh.mesh = sph
	_sphere_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_mat_sphere = ShaderMaterial.new()
	_mat_sphere.shader = load("res://shaders/scanner_pulse.gdshader")
	_mat_sphere.set_shader_parameter("brightness", 10.0)
	_mat_sphere.set_shader_parameter("rim_power",  5.0)   # tight thin shell
	_mat_sphere.set_shader_parameter("fade",       1.0)
	_sphere_mesh.material_override = _mat_sphere
	add_child(_sphere_mesh)


# ---------------------------------------------------------------------------
#  3 orthogonal thin rings — always visible from any angle.
#  CylinderMesh (height = 0.01 in local space → very thin in world space).
#  Shared ShaderMaterial so a single set_shader_parameter updates all three.
# ---------------------------------------------------------------------------
func _build_rings() -> void:
	_mat_rings = ShaderMaterial.new()
	_mat_rings.shader = load("res://shaders/scanner_pulse.gdshader")
	_mat_rings.set_shader_parameter("brightness", 14.0)
	_mat_rings.set_shader_parameter("rim_power",  2.5)   # broader glow on thin cylinder
	_mat_rings.set_shader_parameter("fade",       1.0)

	# Rotations: XZ plane (horizontal), XY plane (vertical), YZ plane (vertical)
	var rotations : Array = [
		Vector3(0.0,      0.0, 0.0),
		Vector3(PI / 2.0, 0.0, 0.0),
		Vector3(0.0,      0.0, PI / 2.0),
	]
	for rot in rotations:
		var mesh := MeshInstance3D.new()
		var cyl  := CylinderMesh.new()
		cyl.top_radius     = 1.0
		cyl.bottom_radius  = 1.0
		cyl.height         = 0.01   # 1 % of radius → very thin ring in world space
		cyl.radial_segments = 128
		cyl.rings           = 1
		mesh.mesh         = cyl
		mesh.rotation     = rot
		mesh.cast_shadow  = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = _mat_rings
		add_child(mesh)
		_rings.append(mesh)


# ---------------------------------------------------------------------------
#  Initial OmniLight flash — bright cyan burst, decays over ~1 s.
# ---------------------------------------------------------------------------
func _build_flash() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color  = Color(0.4, 0.8, 1.0)
	_flash_light.light_energy = 300.0
	_flash_light.omni_range   = 1200.0
	add_child(_flash_light)


# ---------------------------------------------------------------------------
#  Update loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta
	_current_radius = minf(_current_radius + delta * PULSE_SPEED, MAX_RANGE)

	# Flash decay (~1 s)
	if _flash_light != null:
		_flash_light.light_energy = maxf(0.0, 300.0 - _elapsed * 300.0)
		if _flash_light.light_energy <= 0.0:
			_flash_light.queue_free()
			_flash_light = null

	if _current_radius >= MAX_RANGE:
		_completed = true
		scan_completed.emit()
		_fade_out()
		return

	var r := _current_radius

	# Scale sphere and all rings uniformly
	_sphere_mesh.scale = Vector3.ONE * r
	for ring in _rings:
		(ring as MeshInstance3D).scale = Vector3.ONE * r

	# Fade out gently near max range
	var range_fade : float = 1.0 - smoothstep(MAX_RANGE * 0.78, MAX_RANGE * 0.98, r)
	_mat_sphere.set_shader_parameter("fade", range_fade)
	_mat_rings.set_shader_parameter("fade",  range_fade)

	scan_radius_updated.emit(_current_radius)


func _fade_out() -> void:
	var fade_fn := func(v: float) -> void:
		_mat_sphere.set_shader_parameter("fade", v)
		_mat_rings.set_shader_parameter("fade",  v)
	var tw := create_tween()
	tw.tween_method(fade_fn, 1.0, 0.0, 0.6)
	tw.tween_callback(queue_free)
