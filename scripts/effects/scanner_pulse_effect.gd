class_name ScannerPulseEffect
extends Node3D

# =============================================================================
# Scanner Pulse Effect — DIAGNOSTIC VERSION
# Testing BLEND_MODE_MIX (normal transparency) vs ADD
# =============================================================================

signal scan_radius_updated(radius: float)
signal scan_completed

const PULSE_SPEED: float = 2000.0
const MAX_RANGE: float = 5000.0
const START_RADIUS: float = 10.0
const PULSE_COLOR := Color(0.0, 0.85, 0.95)

var _current_radius: float = START_RADIUS
var _elapsed: float = 0.0
var _mesh_inner: MeshInstance3D = null   # flip_faces — visible from inside
var _mesh_outer: MeshInstance3D = null   # normal — visible from outside
var _mat_inner: StandardMaterial3D = null
var _mat_outer: StandardMaterial3D = null
var _flash_light: OmniLight3D = null     # stored as var, not meta — fix crash
var _completed: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	# --- Inner sphere (flip_faces: visible from INSIDE) ---
	_mesh_inner = MeshInstance3D.new()
	var sph_in := SphereMesh.new()
	sph_in.radius = 1.0
	sph_in.height = 2.0
	sph_in.radial_segments = 32
	sph_in.rings = 16
	sph_in.flip_faces = true
	_mesh_inner.mesh = sph_in
	_mesh_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inner.scale = Vector3(START_RADIUS, START_RADIUS, START_RADIUS)

	_mat_inner = StandardMaterial3D.new()
	_mat_inner.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# BLEND_MODE_MIX (normal transparency) — testing if ADD is the problem
	_mat_inner.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_inner.no_depth_test = true
	_mat_inner.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, 0.7)
	_mat_inner.emission_enabled = true
	_mat_inner.emission = PULSE_COLOR
	_mat_inner.emission_energy_multiplier = 3.0
	_mesh_inner.material_override = _mat_inner
	add_child(_mesh_inner)

	# --- Outer sphere (normal normals: visible from OUTSIDE first ~0.03s) ---
	_mesh_outer = MeshInstance3D.new()
	var sph_out := SphereMesh.new()
	sph_out.radius = 1.0
	sph_out.height = 2.0
	sph_out.radial_segments = 32
	sph_out.rings = 16
	_mesh_outer.mesh = sph_out
	_mesh_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_outer.scale = Vector3(START_RADIUS, START_RADIUS, START_RADIUS)

	_mat_outer = StandardMaterial3D.new()
	_mat_outer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_outer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_outer.no_depth_test = true
	_mat_outer.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, 0.7)
	_mat_outer.emission_enabled = true
	_mat_outer.emission = PULSE_COLOR
	_mat_outer.emission_energy_multiplier = 3.0
	_mesh_outer.material_override = _mat_outer
	add_child(_mesh_outer)

	# --- Flash light (stored as var — no crash on queue_free) ---
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = PULSE_COLOR
	_flash_light.light_energy = 50.0
	_flash_light.omni_range = 300.0
	add_child(_flash_light)


func _process(delta: float) -> void:
	if _completed:
		return

	_elapsed += delta
	_current_radius = START_RADIUS + _elapsed * PULSE_SPEED

	if _current_radius >= MAX_RANGE:
		_current_radius = MAX_RANGE
		_completed = true
		scan_completed.emit()
		var fade_fn := func(v: float):
			_mat_inner.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, v * 0.7)
			_mat_inner.emission_energy_multiplier = v * 3.0
			_mat_outer.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, v * 0.7)
			_mat_outer.emission_energy_multiplier = v * 3.0
		var tw := create_tween()
		tw.tween_method(fade_fn, 1.0, 0.0, 0.4)
		tw.tween_callback(queue_free)
		return

	var r := _current_radius
	_mesh_inner.scale = Vector3(r, r, r)
	_mesh_outer.scale = Vector3(r, r, r)

	var range_fade: float = 1.0 - smoothstep(MAX_RANGE * 0.65, MAX_RANGE * 0.95, r)
	var ripple: float = sin(_elapsed * 8.0) * 0.15 + 0.85
	var a: float = range_fade * ripple * 0.7
	_mat_inner.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, a)
	_mat_inner.emission_energy_multiplier = range_fade * ripple * 3.0
	_mat_outer.albedo_color = Color(PULSE_COLOR.r, PULSE_COLOR.g, PULSE_COLOR.b, a)
	_mat_outer.emission_energy_multiplier = range_fade * ripple * 3.0

	# Flash light — use var (not meta) to avoid freed-instance crash
	if _flash_light != null:
		_flash_light.light_energy = maxf(0.0, 50.0 - _elapsed * 100.0)
		if _flash_light.light_energy <= 0.0:
			_flash_light.queue_free()
			_flash_light = null

	scan_radius_updated.emit(_current_radius)
