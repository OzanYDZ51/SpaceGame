class_name ShipEnvironmentLighting
extends Node3D

# =============================================================================
# Ship Environment Lighting — Dynamic environmental illumination.
# Added to the PLAYER ship only. Large-range shadowless OmniLights
# illuminate the player AND nearby NPC ships realistically.
#
# 3 dynamic lights:
# - Planet bounce: colored albedo from nearby planet surface
# - Station glow: warm light when near a station
# - Nebula fill: subtle colored ambient from system nebula/star
#
# Also adapts the ship's rim shader color to match the environment.
# =============================================================================

var _planet_light: OmniLight3D     # Albedo bounce from nearby planet
var _station_light: OmniLight3D    # Warm glow from nearby station
var _nebula_fill: OmniLight3D      # Subtle system ambient fill

var _ship_model: ShipModel = null
var _update_timer: float = 0.0

# Smooth interpolation targets
var _target_planet_energy: float = 0.0
var _target_planet_color: Color = Color.BLACK
var _target_station_energy: float = 0.0
var _target_station_color: Color = Color(0.75, 0.82, 1.0)
var _target_nebula_color: Color = Color(0.08, 0.06, 0.1)
var _base_rim_color: Color = Color(0.35, 0.5, 0.7)

const UPDATE_INTERVAL: float = 0.15
const PLANET_LIGHT_RANGE: float = 400.0
const STATION_LIGHT_RANGE: float = 300.0
const NEBULA_FILL_RANGE: float = 600.0
const STATION_MAX_DIST: float = 3000.0
const LERP_SPEED: float = 0.12


func _ready() -> void:
	_planet_light = _make_light("PlanetBounce", Color.BLACK, 0.0, PLANET_LIGHT_RANGE, 1.2)
	_station_light = _make_light("StationGlow", Color(0.75, 0.82, 1.0), 0.0, STATION_LIGHT_RANGE, 1.5)
	_nebula_fill = _make_light("NebulaFill", Color(0.08, 0.06, 0.1), 0.08, NEBULA_FILL_RANGE, 2.0)

	_ship_model = get_parent().get_node_or_null("ShipModel")


func _make_light(n: String, color: Color, energy: float, r: float, attenuation: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = n
	l.light_color = color
	l.light_energy = energy
	l.omni_range = r
	l.omni_attenuation = attenuation
	l.shadow_enabled = false
	add_child(l)
	return l


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer > 0.0:
		# Still interpolate between updates for smooth transitions
		_interpolate_lights()
		return
	_update_timer = UPDATE_INTERVAL

	_update_planet_bounce()
	_update_station_glow()
	_update_nebula_fill()
	_update_rim_color()
	_interpolate_lights()


func _interpolate_lights() -> void:
	_planet_light.light_energy = lerpf(_planet_light.light_energy, _target_planet_energy, LERP_SPEED)
	_planet_light.light_color = _planet_light.light_color.lerp(_target_planet_color, LERP_SPEED)
	_station_light.light_energy = lerpf(_station_light.light_energy, _target_station_energy, LERP_SPEED)
	_station_light.light_color = _station_light.light_color.lerp(_target_station_color, LERP_SPEED)
	_nebula_fill.light_color = _nebula_fill.light_color.lerp(_target_nebula_color, 0.05)


# =============================================================================
# PLANET BOUNCE — albedo light from nearby planet surface
# =============================================================================

func _update_planet_bounce() -> void:
	var pam := _get_planet_approach_manager()
	if pam == null or pam.current_zone == PlanetApproachManager.Zone.SPACE:
		_target_planet_energy = 0.0
		return

	var altitude: float = pam.current_altitude
	# Fade in from 100km, max at surface
	var t: float = clampf(1.0 - altitude / 100_000.0, 0.0, 1.0)
	_target_planet_energy = t * t * 2.5  # Quadratic: subtle at distance, strong close

	# Color from planet atmosphere scatter + surface color
	var planet_color := Color(0.4, 0.5, 0.7)
	if pam.current_planet and pam.current_planet.planet_data:
		var pd: PlanetData = pam.current_planet.planet_data
		var atmo := AtmosphereConfig.from_planet_data(pd)
		planet_color = atmo.scatter_color.lerp(pd.color, 0.3)
		# Scale by atmosphere density (thin atmosphere = less bounce)
		_target_planet_energy *= clampf(pd.atmosphere_density, 0.3, 1.5)

	_target_planet_color = planet_color

	# Position: toward planet (below ship in most approach angles)
	_planet_light.position = pam.gravity_direction * 8.0


# =============================================================================
# STATION GLOW — warm light from nearby station structures
# =============================================================================

func _update_station_glow() -> void:
	var stations: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	if stations.is_empty():
		_target_station_energy = 0.0
		return

	var ship_pos: Vector3 = get_parent().global_position

	# Find nearest station with a valid node
	var best_node: Node3D = null
	var best_dist: float = INF
	for ent in stations:
		var node: Node3D = ent.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var dist: float = ship_pos.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_node = node

	if best_node == null or best_dist > STATION_MAX_DIST:
		_target_station_energy = 0.0
		return

	# Smooth falloff: quadratic, max 2.0 at ~200m, zero at 3000m
	var t: float = clampf(1.0 - best_dist / STATION_MAX_DIST, 0.0, 1.0)
	_target_station_energy = t * t * 2.0

	# Station interior light color (blueish white, matching bay lights)
	_target_station_color = Color(0.75, 0.82, 1.0)

	# Point light toward station
	var dir: Vector3 = (best_node.global_position - ship_pos).normalized()
	_station_light.position = dir * 12.0


# =============================================================================
# NEBULA FILL — subtle colored ambient from system nebula and star
# =============================================================================

func _update_nebula_fill() -> void:
	var space_env = _get_space_environment()
	if space_env == null:
		return

	# Get current environment data for nebula colors
	var env_data: SystemEnvironmentData = space_env._current_env_data as SystemEnvironmentData
	if env_data == null:
		return

	# Blend nebula warm + cool + star color for a subtle fill
	var fill_color: Color = env_data.nebula_warm.lerp(env_data.nebula_cool, 0.5)
	# Mix in some star color (star illuminates nebula)
	fill_color = fill_color.lerp(env_data.star_light_color, 0.3)
	fill_color = fill_color.lightened(0.2)

	_target_nebula_color = fill_color
	# Very subtle energy — just adds a tint to shadow areas
	_nebula_fill.light_energy = 0.08 + env_data.nebula_intensity * 0.1


# =============================================================================
# RIM COLOR ADAPTATION — rim glow picks up environment color
# =============================================================================

func _update_rim_color() -> void:
	if _ship_model == null or _ship_model._rim_material == null:
		return

	var env_color := _base_rim_color

	# Planet influence: rim picks up atmosphere color
	if _target_planet_energy > 0.1:
		var blend: float = clampf(_target_planet_energy / 2.5, 0.0, 0.5)
		env_color = env_color.lerp(_target_planet_color.lightened(0.3), blend)

	# Station influence: rim picks up warm station glow
	if _target_station_energy > 0.1:
		var blend: float = clampf(_target_station_energy / 2.0, 0.0, 0.3)
		env_color = env_color.lerp(_target_station_color.lightened(0.2), blend)

	# Nebula influence: subtle tint from system nebula
	env_color = env_color.lerp(_target_nebula_color.lightened(0.4), 0.1)

	_ship_model._rim_material.set_shader_parameter("rim_color", env_color)


# =============================================================================
# HELPERS
# =============================================================================

func _get_planet_approach_manager() -> PlanetApproachManager:
	return GameManager.get_node_or_null("PlanetApproachManager") as PlanetApproachManager


func _get_space_environment():
	if GameManager.main_scene == null:
		return null
	return GameManager.main_scene
