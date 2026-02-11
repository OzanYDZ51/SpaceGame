class_name LandingZoneMarker
extends Node3D

# =============================================================================
# Landing Zone Marker — Flat area on a planet surface designated for landing
# Shows a holographic landing pad indicator when the player is near.
# =============================================================================

const MARKER_RADIUS: float = 50.0     # Meters
const APPROACH_DIST: float = 2000.0   # Show marker within this distance
const LANDING_DIST: float = 100.0     # "Landed" threshold

var zone_name: String = ""
var planet_body: PlanetBody = null

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _is_visible: bool = false


func setup(p_name: String, world_pos: Vector3, p_planet: PlanetBody) -> void:
	zone_name = p_name
	planet_body = p_planet
	global_position = world_pos
	_build_visual()


func _build_visual() -> void:
	# Flat ring on the surface
	var torus := TorusMesh.new()
	torus.inner_radius = MARKER_RADIUS * 0.8
	torus.outer_radius = MARKER_RADIUS
	torus.rings = 32
	torus.ring_segments = 8

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.2, 0.8, 0.4, 0.6)
	_material.emission_enabled = true
	_material.emission = Color(0.2, 0.8, 0.4)
	_material.emission_energy_multiplier = 2.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mesh = MeshInstance3D.new()
	_mesh.mesh = torus
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	# Rotate to lie flat on the surface (assuming planet center is below)
	if planet_body:
		var up: Vector3 = (global_position - planet_body.global_position).normalized()
		if up.length_squared() > 0.5:
			look_at(global_position + up, Vector3.UP)
			rotate_object_local(Vector3.RIGHT, PI * 0.5)

	visible = false


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := cam.global_position.distance_to(global_position)
	var should_show := dist < APPROACH_DIST
	if should_show != _is_visible:
		_is_visible = should_show
		visible = should_show

	# Pulse effect
	if _is_visible and _material:
		var pulse: float = sin(Time.get_ticks_msec() * 0.003) * 0.15 + 0.85
		_material.albedo_color.a = 0.6 * pulse


## Check if the ship has landed in this zone.
func is_ship_landed(ship_pos: Vector3) -> bool:
	return ship_pos.distance_to(global_position) < LANDING_DIST
