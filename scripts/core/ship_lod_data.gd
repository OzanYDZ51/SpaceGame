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
var ai_state: int = 0  # Maps to AIBrain.State
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

# --- Internal flag to prevent duplicate registration during LOD promotion ---
# Used by ShipLODManager to prevent duplicate registration during async promote.
var is_promoting: bool = false


var _route_wp_index: int = 0  # Current waypoint index for route travel

## Cruise speeds for data-only simulation (visible at system-map scale)
const ROUTE_CRUISE_SPEED: float = 350.0   # Route NPCs: 350 m/s (visible inter-station traffic)
const PATROL_CRUISE_SPEED: float = 180.0  # Patrol NPCs: 180 m/s (visible area coverage)
const MIN_DRIFT_SPEED: float = 100.0      # Minimum speed (no frozen dots)

func tick_simple_ai(delta: float) -> void:
	if is_dead or is_docked:
		return

	# Dead reckoning: advance position
	position += velocity * delta

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

	var brain = ship.get_node_or_null("AIBrain")
	if brain:
		ai_state = brain.current_state
		ai_patrol_center = brain._patrol_center
		ai_patrol_radius = brain._patrol_radius
		var wps: Array[Vector3] = []
		if not brain._waypoints.is_empty() and brain.route_priority:
			wps.assign(brain._waypoints)
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
