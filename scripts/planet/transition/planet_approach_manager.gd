class_name PlanetApproachManager
extends Node

# =============================================================================
# Planet Approach Manager — Orchestrates the seamless space→planet transition
# Monitors distance to nearest planet, manages gravity/drag zones, locks cruise.
# Also drives AtmosphereEnvironment for visual transitions (fog, sky, light).
# =============================================================================

signal entered_planet_zone(planet_body: PlanetBody, zone: int)
signal exited_planet_zone
signal altitude_changed(altitude: float, planet_name: String)

## Transition zones (distances from planet surface in meters)
const ZONE_APPROACH: float = 100_000.0   # 100 km — terrain starts loading
const ZONE_EXTERIOR: float = 10_000.0    # 10 km — cruise force off, light gravity
const ZONE_ATMOSPHERE: float = 0.0       # At atmosphere edge — full gravity + drag
const ZONE_SURFACE: float = 1_000.0      # 1 km — strong drag, speed limit

## Zone enum for signals
enum Zone { SPACE = 0, APPROACH = 1, EXTERIOR = 2, ATMOSPHERE = 3, SURFACE = 4 }

var current_zone: int = Zone.SPACE
var current_planet: PlanetBody = null
var current_altitude: float = INF
var current_planet_name: String = ""

var _planet_lod_mgr: PlanetLODManager = null
var _ship: ShipController = null
var _atmo_env: AtmosphereEnvironment = null
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.05  # 20 Hz (faster to reduce frame-dragging staleness)

# Gravity/drag values (smoothly interpolated)
var gravity_strength: float = 0.0     # 0-1, applied by ship_controller
var drag_factor: float = 0.0          # 0-1, applied by ship_controller
var gravity_direction: Vector3 = Vector3.DOWN
var max_speed_override: float = 0.0   # 0 = no override


func _ready() -> void:
	_planet_lod_mgr = get_parent().get_node_or_null("PlanetLODManager") as PlanetLODManager


func set_ship(ship: ShipController) -> void:
	_ship = ship


func setup_atmosphere_environment(env: Environment, dir_light: DirectionalLight3D) -> void:
	_atmo_env = AtmosphereEnvironment.new()
	_atmo_env.name = "AtmosphereEnvironment"
	_atmo_env.setup(env, dir_light)
	add_child(_atmo_env)


func _process(delta: float) -> void:
	if _ship == null or _planet_lod_mgr == null:
		return

	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	# Find nearest active planet body
	var body := _planet_lod_mgr.get_nearest_body(_ship.global_position)

	if body == null:
		# Unfreeze previous planet orbit if we had one
		if current_planet and current_planet.entity_id != "" and current_zone >= Zone.APPROACH:
			EntityRegistry.unfreeze_orbit(current_planet.entity_id)
		if current_zone != Zone.SPACE:
			_transition_to_zone(Zone.SPACE, null)
		gravity_strength = 0.0
		drag_factor = 0.0
		max_speed_override = 0.0
		_apply_to_ship()
		_apply_to_camera()
		_update_atmosphere_env(null, Zone.SPACE)
		return

	current_planet = body
	current_planet_name = body.planet_data.planet_name if body.planet_data else ""
	current_altitude = body.get_altitude(_ship.global_position)
	gravity_direction = body.get_center_direction(_ship.global_position)

	# Determine zone
	var render_radius: float = body.planet_radius
	var atmo_height: float = render_radius * (body.planet_data.atmosphere_density * 0.08 if body.planet_data else 0.05)
	var atmo_edge: float = atmo_height

	var new_zone: int
	if current_altitude > ZONE_APPROACH:
		new_zone = Zone.SPACE
	elif current_altitude > ZONE_EXTERIOR:
		new_zone = Zone.APPROACH
	elif current_altitude > atmo_edge:
		new_zone = Zone.EXTERIOR
	elif current_altitude > ZONE_SURFACE:
		new_zone = Zone.ATMOSPHERE
	else:
		new_zone = Zone.SURFACE

	if new_zone != current_zone:
		_transition_to_zone(new_zone, body)

	# Compute gravity and drag based on altitude
	_compute_physics(body, atmo_edge)

	# Push physics values
	_apply_to_ship()
	_apply_to_camera()

	# Drive atmosphere visuals
	_update_atmosphere_env(body, new_zone)

	# Emit altitude for HUD
	altitude_changed.emit(current_altitude, current_planet_name)


func _transition_to_zone(new_zone: int, body: PlanetBody) -> void:
	var old_zone := current_zone
	current_zone = new_zone

	if body:
		entered_planet_zone.emit(body, new_zone)
	else:
		exited_planet_zone.emit()

	# Force cruise off in atmosphere zones
	if new_zone >= Zone.EXTERIOR and _ship:
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_ship._exit_cruise()

	# Freeze/unfreeze planet orbital motion when player is nearby.
	# Prevents terrain from sliding under the ship due to orbit updates.
	if body and body.entity_id != "":
		if new_zone >= Zone.APPROACH and old_zone < Zone.APPROACH:
			EntityRegistry.freeze_orbit(body.entity_id)
		elif new_zone < Zone.APPROACH and old_zone >= Zone.APPROACH:
			EntityRegistry.unfreeze_orbit(body.entity_id)


func _compute_physics(_body: PlanetBody, _atmo_edge: float) -> void:
	# Gravity and drag disabled — ships fly freely near planets.
	# Zone transitions still function for cruise lock and atmosphere visuals.
	# Speed caps are distance-based for safety (prevents tunneling).
	gravity_strength = 0.0
	drag_factor = 0.0
	match current_zone:
		Zone.SPACE:
			max_speed_override = 0.0
		Zone.APPROACH:
			# Gentle hint cap during approach (main safety is the per-frame guard in ShipController)
			max_speed_override = 0.0  # Guard handles it per-frame
		Zone.EXTERIOR:
			var t: float = 1.0 - clampf((current_altitude - _atmo_edge) / (ZONE_EXTERIOR - _atmo_edge), 0.0, 1.0)
			max_speed_override = lerpf(500.0, 300.0, t)
		Zone.ATMOSPHERE:
			var t: float = 1.0 - clampf((current_altitude - ZONE_SURFACE) / maxf(_atmo_edge - ZONE_SURFACE, 1.0), 0.0, 1.0)
			max_speed_override = lerpf(300.0, 100.0, t)
		Zone.SURFACE:
			max_speed_override = 100.0


func _apply_to_ship() -> void:
	if _ship == null:
		return
	_ship.planetary_gravity = gravity_direction * gravity_strength * 9.8
	_ship.atmospheric_drag = drag_factor
	_ship.planetary_max_speed_override = max_speed_override
	_ship._near_planet_surface = current_zone >= Zone.EXTERIOR

	# Planet ref for cruise warp exit (terrain collision handles surface contact)
	if current_planet and current_zone >= Zone.APPROACH:
		_ship._planet_guard_body = current_planet
		_ship._planet_guard_center = current_planet.global_position
		_ship._planet_guard_radius = current_planet.planet_radius
	else:
		_ship._planet_guard_body = null
		_ship._planet_guard_radius = 0.0

	# Frame-dragging disabled — planet orbit is frozen when player is nearby,
	# so no orbital velocity compensation is needed.
	_ship.planetary_orbit_velocity = Vector3.ZERO


func _apply_to_camera() -> void:
	if _ship == null:
		return
	var cam := _ship.get_node_or_null("ShipCamera") as ShipCamera
	if cam == null:
		var viewport := _ship.get_viewport()
		if viewport:
			cam = viewport.get_camera_3d() as ShipCamera
	if cam == null:
		return

	if current_zone >= Zone.ATMOSPHERE:
		cam.planetary_up = -gravity_direction
		cam.planetary_up_blend = clampf(gravity_strength, 0.0, 1.0)
	elif current_zone >= Zone.EXTERIOR:
		cam.planetary_up = -gravity_direction
		cam.planetary_up_blend = clampf(gravity_strength * 0.5, 0.0, 0.3)
	else:
		cam.planetary_up = Vector3.ZERO
		cam.planetary_up_blend = 0.0


func _update_atmosphere_env(body: PlanetBody, zone: int) -> void:
	if _atmo_env == null:
		return
	if body == null or zone <= Zone.APPROACH:
		_atmo_env.set_target_blend(0.0)
		return

	# Configure for this planet's atmosphere
	var atmo_cfg := body.get_atmosphere_config()
	if atmo_cfg:
		_atmo_env.configure_for_planet(atmo_cfg)

	# Blend based on zone and altitude
	match zone:
		Zone.EXTERIOR:
			var t: float = 1.0 - clampf(current_altitude / ZONE_EXTERIOR, 0.0, 1.0)
			_atmo_env.set_target_blend(t * 0.3)  # Subtle start
		Zone.ATMOSPHERE:
			var t: float = 1.0 - clampf(current_altitude / ZONE_EXTERIOR, 0.0, 1.0)
			_atmo_env.set_target_blend(clampf(t, 0.3, 0.85))
		Zone.SURFACE:
			_atmo_env.set_target_blend(1.0)


## Check if cruise should be blocked.
func is_cruise_blocked() -> bool:
	return current_zone >= Zone.EXTERIOR


## Hard reset (leaving system).
func reset() -> void:
	# Unfreeze any frozen planet orbit
	if current_planet and current_planet.entity_id != "":
		EntityRegistry.unfreeze_orbit(current_planet.entity_id)
	current_zone = Zone.SPACE
	current_planet = null
	current_altitude = INF
	gravity_strength = 0.0
	drag_factor = 0.0
	max_speed_override = 0.0
	if _atmo_env:
		_atmo_env.reset()
