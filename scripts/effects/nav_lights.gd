class_name NavLights
extends Node3D

# =============================================================================
# Navigation Lights - Aviation-style nav lights for all ships.
# Port (red), Starboard (green), Strobe (white).
# Auto-placed via ship visual AABB. Each light = OmniLight3D + emissive bulb.
# =============================================================================

var _lights: Array[OmniLight3D] = []
var _bulbs: Array[MeshInstance3D] = []
var _port_light: OmniLight3D
var _starboard_light: OmniLight3D
var _strobe_light: OmniLight3D
var _time: float = 0.0
## LOD energy multiplier — set by ShipLODManager to dim lights at distance
var _energy_scale: float = 1.0

# Bulb materials (shared)
static var _red_mat: StandardMaterial3D = null
static var _green_mat: StandardMaterial3D = null
static var _white_mat: StandardMaterial3D = null
static var _bulb_mesh: SphereMesh = null


func setup(aabb: AABB, scale: float) -> void:
	var center: Vector3 = aabb.get_center()

	# Port (left, -X) — red
	_port_light = _create_light(
		"NavPort",
		Color(1.0, 0.1, 0.05),
		Vector3(aabb.position.x, center.y, center.z),
		4.0 * scale,
		2.0
	)

	# Starboard (right, +X) — green
	_starboard_light = _create_light(
		"NavStarboard",
		Color(0.05, 1.0, 0.1),
		Vector3(aabb.position.x + aabb.size.x, center.y, center.z),
		4.0 * scale,
		2.0
	)

	# Strobe (rear top) — white
	_strobe_light = _create_light(
		"NavStrobe",
		Color(1.0, 1.0, 0.95),
		Vector3(center.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z * 0.8),
		6.0 * scale,
		3.0
	)


func _create_light(light_name: String, color: Color, pos: Vector3, omni_range: float, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = omni_range
	light.shadow_enabled = false
	light.position = pos
	add_child(light)
	_lights.append(light)

	# Emissive bulb (visible at distance)
	_ensure_shared_resources()
	var bulb := MeshInstance3D.new()
	bulb.name = light_name + "_Bulb"
	bulb.mesh = _bulb_mesh
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat: StandardMaterial3D
	match light_name:
		"NavPort": mat = _red_mat
		"NavStarboard": mat = _green_mat
		_: mat = _white_mat
	bulb.material_override = mat
	light.add_child(bulb)
	_bulbs.append(bulb)

	return light


func _ensure_shared_resources() -> void:
	if _bulb_mesh != null:
		return

	_bulb_mesh = SphereMesh.new()
	_bulb_mesh.radius = 0.15
	_bulb_mesh.height = 0.3
	_bulb_mesh.radial_segments = 8
	_bulb_mesh.rings = 4

	_red_mat = _make_emissive_mat(Color(1.0, 0.1, 0.05))
	_green_mat = _make_emissive_mat(Color(0.05, 1.0, 0.1))
	_white_mat = _make_emissive_mat(Color(1.0, 1.0, 0.95))


static func _make_emissive_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.no_depth_test = false
	return mat


func _process(delta: float) -> void:
	_time += delta

	# Nav pulse: smooth sin wave, period 2s
	var nav_pulse: float = (sin(_time * PI) + 1.0) * 0.5  # 0..1
	var nav_energy: float = (0.5 + nav_pulse * 1.5) * _energy_scale  # 0.5..2.0 × LOD scale

	if _port_light:
		_port_light.light_energy = nav_energy
	if _starboard_light:
		_starboard_light.light_energy = nav_energy

	# Strobe: sharp flash, period 0.8s, 15% duty cycle
	var strobe_phase: float = fmod(_time, 0.8) / 0.8  # 0..1
	var strobe_on: bool = strobe_phase < 0.15
	var strobe_energy: float = (4.0 if strobe_on else 0.0) * _energy_scale

	if _strobe_light:
		_strobe_light.light_energy = strobe_energy

	# Bulb visibility follows light energy
	for i in _bulbs.size():
		if i < _lights.size():
			var e: float = _lights[i].light_energy
			_bulbs[i].visible = e > 0.1


func get_lights() -> Array[OmniLight3D]:
	return _lights
