class_name ShipLODData
extends RefCounted

# =============================================================================
# Ship LOD Data - Lightweight data-only representation of a ship.
# Used for LOD2 ships that have no scene tree node.
# =============================================================================

enum LODLevel { LOD0, LOD1, LOD2, LOD3 }

# --- Identity ---
var id: StringName = &""
var ship_id: StringName = &""
var ship_class: StringName = &""
var faction: StringName = &"hostile"
var display_name: String = ""

# --- Transform ---
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rotation_basis: Basis = Basis.IDENTITY

# --- Visual (for MultiMesh) ---
var color_tint: Color = Color.WHITE
var model_scale: float = 1.0

# --- Combat ---
var hull_ratio: float = 1.0
var shield_ratio: float = 1.0
var is_dead: bool = false
var is_docked: bool = false

# --- Per-ship AI ranges (from ShipData) ---
var sensor_range: float = Constants.AI_DETECTION_RANGE
var engagement_range: float = Constants.AI_ENGAGEMENT_RANGE
var disengage_range: float = Constants.AI_DISENGAGE_RANGE

# --- Simplified AI ---
var ai_state: int = 0  # Maps to AIController.State
var ai_target_id: StringName = &""
var ai_patrol_center: Vector3 = Vector3.ZERO
var ai_patrol_radius: float = 300.0
var ai_route_waypoints: Array[Vector3] = []  # Linear travel route (convoy)
var ai_route_priority: bool = false           # Keep route during combat
var guard_station_name: StringName = &""

# --- Network ---
var is_remote_player: bool = false
var is_server_npc: bool = false
var is_event_npc: bool = false
var peer_id: int = 0

# --- LOD bookkeeping ---
var current_lod: LODLevel = LODLevel.LOD2
var node_ref: Node3D = null  # Non-null when LOD0/LOD1 (has a scene node)
var distance_to_camera: float = 0.0

# --- Behavior profile (for re-spawning at LOD0/1) ---
var behavior_name: StringName = &"balanced"

# --- Fleet ship data (for re-equipping after LOD re-promotion) ---
var fleet_index: int = -1  # -1 = not a fleet ship
var owner_pid: int = 0     # 0 = not a fleet ship, >0 = owning player's peer_id
var owner_name: String = "" # Display name of the fleet owner (empty for non-fleet NPCs)

# --- Internal flag to prevent duplicate registration during LOD promotion ---
# Used by ShipLODManager to prevent duplicate registration during async promote.
var is_promoting: bool = false


var _route_wp_index: int = 0  # Current waypoint index for route travel

# Obstacle avoidance cache for data-only ships
var _cached_obstacles: Array = []  # Array of { "pos": Vector3, "radius": float }
var _obstacle_refresh_timer: float = 0.0
const OBSTACLE_REFRESH_INTERVAL: float = 5.0  # Refresh obstacle cache every 5s

## Cruise speeds for data-only simulation (visible at system-map scale)
const ROUTE_CRUISE_SPEED: float = 350.0   # Route NPCs: 350 m/s (visible inter-station traffic)
const PATROL_CRUISE_SPEED: float = 180.0  # Patrol NPCs: 180 m/s (visible area coverage)
const MIN_DRIFT_SPEED: float = 100.0      # Minimum speed (no frozen dots)

const STATION_MODEL_RADIUS: float = 3000.0  # Station model ~2500m + margin


func _refresh_obstacle_cache() -> void:
	_cached_obstacles.clear()
	# Stations
	var stations: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for st in stations:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		_cached_obstacles.append({"pos": scene_pos, "radius": STATION_MODEL_RADIUS})
	# Planets
	var planets: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET)
	for pl in planets:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([pl["pos_x"], pl["pos_y"], pl["pos_z"]])
		var planet_r: float = pl.get("radius", 5000.0)
		_cached_obstacles.append({"pos": scene_pos, "radius": maxf(planet_r * 1.2 + 500.0, 5000.0)})
	# Stars
	var stars: Array[Dictionary] = EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR)
	for star in stars:
		var scene_pos: Vector3 = FloatingOrigin.to_local_pos([star["pos_x"], star["pos_y"], star["pos_z"]])
		var star_r: float = star.get("radius", 50000.0)
		_cached_obstacles.append({"pos": scene_pos, "radius": maxf(star_r * 1.5, 50000.0)})


func _steer_away_from_obstacles(delta: float) -> void:
	## Push velocity away from nearby obstacle zones (stations, planets, stars).
	for zone in _cached_obstacles:
		var to_ship: Vector3 = position - zone["pos"]
		var dist: float = to_ship.length()
		var excl_r: float = zone["radius"]
		if dist < excl_r * 1.2 and dist > 1.0:
			# Inside or near exclusion zone — steer outward
			var escape_dir: Vector3 = to_ship.normalized()
			var urgency: float = clampf(1.0 - dist / excl_r, 0.0, 1.0)
			var desired_vel: Vector3 = escape_dir * maxf(velocity.length(), PATROL_CRUISE_SPEED)
			velocity = velocity.lerp(desired_vel, delta * (2.0 + urgency * 4.0))


func tick_simple_ai(delta: float) -> void:
	if is_dead or is_docked:
		return

	# Periodic obstacle cache refresh
	_obstacle_refresh_timer -= delta
	if _obstacle_refresh_timer <= 0.0:
		_obstacle_refresh_timer = OBSTACLE_REFRESH_INTERVAL
		_refresh_obstacle_cache()

	# Dead reckoning: advance position
	position += velocity * delta

	# Obstacle avoidance: steer away from stations, planets, stars
	_steer_away_from_obstacles(delta)

	# Route-based travel: steer toward next waypoint in sequence
	if not ai_route_waypoints.is_empty():
		var wp: Vector3 = ai_route_waypoints[_route_wp_index]
		var to_wp: Vector3 = wp - position
		var dist_wp: float = to_wp.length()
		if dist_wp < 2000.0:
			_route_wp_index = (_route_wp_index + 1) % ai_route_waypoints.size()
			wp = ai_route_waypoints[_route_wp_index]
			to_wp = wp - position
		# Steer toward waypoint at cruise speed
		var desired_speed: float = maxf(velocity.length(), ROUTE_CRUISE_SPEED)
		velocity = velocity.lerp(to_wp.normalized() * desired_speed, delta * 1.5)
		return

	# Ensure ships always move (prevents frozen LOD2 dots on radar)
	if velocity.length_squared() < MIN_DRIFT_SPEED * MIN_DRIFT_SPEED:
		velocity = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.2, 0.2),
			randf_range(-1.0, 1.0)
		).normalized() * randf_range(MIN_DRIFT_SPEED, PATROL_CRUISE_SPEED)

	# Patrol: steer back toward center when drifting out
	if ai_patrol_radius > 0.0:
		var to_center = ai_patrol_center - position
		var dist = to_center.length()
		if dist > ai_patrol_radius:
			velocity = velocity.lerp(to_center.normalized() * PATROL_CRUISE_SPEED, delta * 2.0)
		elif dist > ai_patrol_radius * 0.7:
			velocity = velocity.lerp(to_center.normalized() * PATROL_CRUISE_SPEED * 0.7, delta * 0.5)


func capture_from_node(ship: Node3D) -> void:
	position = ship.global_position
	rotation_basis = ship.global_transform.basis
	if ship is RigidBody3D:
		velocity = (ship as RigidBody3D).linear_velocity
	elif "linear_velocity" in ship:
		velocity = ship.linear_velocity

	var health = ship.get_node_or_null("HealthSystem")
	if health:
		hull_ratio = health.get_hull_ratio()
		shield_ratio = health.get_total_shield_ratio()
		is_dead = health.is_dead()

	var brain = ship.get_node_or_null("AIController")
	if brain:
		ai_state = brain.current_state
		ai_patrol_center = brain.patrol_center_compat
		ai_patrol_radius = brain.patrol_radius_compat
		var wps: Array[Vector3] = []
		if not brain.waypoints_compat.is_empty() and brain.route_priority:
			wps.assign(brain.waypoints_compat)
		ai_route_waypoints = wps
		ai_route_priority = brain.route_priority
		if brain.target and is_instance_valid(brain.target):
			ai_target_id = StringName(brain.target.name)
		if brain.guard_station and is_instance_valid(brain.guard_station):
			guard_station_name = StringName(brain.guard_station.name)

	var model = ship.get_node_or_null("ShipModel")
	if model:
		color_tint = model.color_tint
		model_scale = model.model_scale

	if ship.has_method("get") and ship.get("ship_data") != null:
		faction = ship.faction
		if ship.ship_data:
			var sd = ship.ship_data
			ship_id = sd.ship_id
			ship_class = sd.ship_class
			sensor_range = sd.sensor_range
			engagement_range = sd.engagement_range
			disengage_range = sd.disengage_range
