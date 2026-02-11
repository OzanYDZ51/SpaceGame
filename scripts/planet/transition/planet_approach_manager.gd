class_name PlanetApproachManager
extends Node

# =============================================================================
# Planet Approach Manager — Orchestrates the seamless space→planet transition
# Monitors distance to nearest planet, manages gravity/drag zones, locks cruise.
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
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1  # 10 Hz

# Gravity/drag values (smoothly interpolated)
var gravity_strength: float = 0.0     # 0-1, applied by ship_controller
var drag_factor: float = 0.0          # 0-1, applied by ship_controller
var gravity_direction: Vector3 = Vector3.DOWN
var max_speed_override: float = 0.0   # 0 = no override


func _ready() -> void:
	_planet_lod_mgr = get_parent().get_node_or_null("PlanetLODManager") as PlanetLODManager


func set_ship(ship: ShipController) -> void:
	_ship = ship


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
		if current_zone != Zone.SPACE:
			_transition_to_zone(Zone.SPACE, null)
		gravity_strength = 0.0
		drag_factor = 0.0
		max_speed_override = 0.0
		_apply_to_ship()
		_apply_to_camera()
		return

	current_planet = body
	current_planet_name = body.planet_data.planet_name if body.planet_data else ""
	current_altitude = body.get_altitude(_ship.global_position)
	gravity_direction = body.get_center_direction(_ship.global_position)

	# Determine zone
	var render_radius: float = body.planet_radius
	var atmo_height: float = render_radius * (body.planet_data.atmosphere_density * 0.08 if body.planet_data else 0.05)
	var atmo_edge: float = atmo_height  # Altitude at atmosphere start

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

	# Push physics values to ShipController
	_apply_to_ship()

	# Push camera up-hint for planetary mode
	_apply_to_camera()

	# Emit altitude for HUD
	altitude_changed.emit(current_altitude, current_planet_name)


func _transition_to_zone(new_zone: int, body: PlanetBody) -> void:
	current_zone = new_zone

	if body:
		entered_planet_zone.emit(body, new_zone)
	else:
		exited_planet_zone.emit()

	# Force cruise off in atmosphere zones
	if new_zone >= Zone.EXTERIOR and _ship:
		if _ship.speed_mode == Constants.SpeedMode.CRUISE:
			_ship._exit_cruise()


func _compute_physics(body: PlanetBody, atmo_edge: float) -> void:
	match current_zone:
		Zone.SPACE:
			gravity_strength = 0.0
			drag_factor = 0.0
			max_speed_override = 0.0
		Zone.APPROACH:
			# Very light gravity starting, no drag
			var t: float = 1.0 - clampf((current_altitude - ZONE_EXTERIOR) / (ZONE_APPROACH - ZONE_EXTERIOR), 0.0, 1.0)
			gravity_strength = t * 0.01  # 1% max in approach
			drag_factor = 0.0
			max_speed_override = 0.0
		Zone.EXTERIOR:
			# Increasing gravity, light drag
			var t: float = 1.0 - clampf((current_altitude - atmo_edge) / (ZONE_EXTERIOR - atmo_edge), 0.0, 1.0)
			gravity_strength = lerpf(0.01, 0.3, t)
			drag_factor = t * 0.1
			max_speed_override = lerpf(0.0, 300.0, t)  # Gradually reduce from unlimited to 300 m/s
		Zone.ATMOSPHERE:
			# Full gravity and drag
			var t: float = 1.0 - clampf((current_altitude - ZONE_SURFACE) / maxf(atmo_edge - ZONE_SURFACE, 1.0), 0.0, 1.0)
			gravity_strength = lerpf(0.3, 1.0, t)
			drag_factor = lerpf(0.1, 0.6, t)
			max_speed_override = lerpf(300.0, 100.0, t)
		Zone.SURFACE:
			gravity_strength = 1.0
			drag_factor = 0.8
			max_speed_override = 100.0


func _apply_to_ship() -> void:
	if _ship == null:
		return
	# Gravity: direction * strength * base_gravity (9.8 m/s²)
	_ship.planetary_gravity = gravity_direction * gravity_strength * 9.8
	_ship.atmospheric_drag = drag_factor
	_ship.planetary_max_speed_override = max_speed_override
	_ship._near_planet_surface = current_zone >= Zone.EXTERIOR


func _apply_to_camera() -> void:
	if _ship == null:
		return
	var cam := _ship.get_node_or_null("ShipCamera") as ShipCamera
	if cam == null:
		# Camera might be a sibling or child — search
		var viewport := _ship.get_viewport()
		if viewport:
			cam = viewport.get_camera_3d() as ShipCamera
	if cam == null:
		return

	if current_zone >= Zone.ATMOSPHERE:
		# In atmosphere: planet surface normal is "up"
		cam.planetary_up = -gravity_direction
		cam.planetary_up_blend = clampf(gravity_strength, 0.0, 1.0)
	elif current_zone >= Zone.EXTERIOR:
		# Approaching: gentle blend
		cam.planetary_up = -gravity_direction
		cam.planetary_up_blend = clampf(gravity_strength * 0.5, 0.0, 0.3)
	else:
		cam.planetary_up = Vector3.ZERO
		cam.planetary_up_blend = 0.0


## Check if cruise should be blocked.
func is_cruise_blocked() -> bool:
	return current_zone >= Zone.EXTERIOR
