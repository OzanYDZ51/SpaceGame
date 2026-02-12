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

# --- Simplified AI ---
var ai_state: int = 0  # Maps to AIBrain.State
var ai_target_id: StringName = &""
var ai_patrol_center: Vector3 = Vector3.ZERO
var ai_patrol_radius: float = 300.0

# --- Network ---
var is_remote_player: bool = false
var is_server_npc: bool = false
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


func tick_simple_ai(delta: float) -> void:
	if is_dead:
		return

	# Dead reckoning: advance position
	position += velocity * delta

	# Ensure ships always move (prevents frozen LOD2 dots on radar)
	if velocity.length_squared() < 400.0:
		velocity = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.2, 0.2),
			randf_range(-1.0, 1.0)
		).normalized() * randf_range(40.0, 80.0)

	# Patrol: steer back hard toward center when drifting out
	if ai_patrol_radius > 0.0:
		var to_center := ai_patrol_center - position
		var dist := to_center.length()
		if dist > ai_patrol_radius:
			velocity = velocity.lerp(to_center.normalized() * 80.0, delta * 2.0)
		elif dist > ai_patrol_radius * 0.8:
			velocity = velocity.lerp(to_center.normalized() * 60.0, delta * 0.5)


func capture_from_node(ship: Node3D) -> void:
	position = ship.global_position
	rotation_basis = ship.global_transform.basis
	if ship is RigidBody3D:
		velocity = (ship as RigidBody3D).linear_velocity

	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		hull_ratio = health.get_hull_ratio()
		shield_ratio = health.get_total_shield_ratio()
		is_dead = health.is_dead()

	var brain := ship.get_node_or_null("AIBrain") as AIBrain
	if brain:
		ai_state = brain.current_state
		ai_patrol_center = brain._patrol_center
		ai_patrol_radius = brain._patrol_radius
		if brain.target and is_instance_valid(brain.target):
			ai_target_id = StringName(brain.target.name)

	var model := ship.get_node_or_null("ShipModel") as ShipModel
	if model:
		color_tint = model.color_tint
		model_scale = model.model_scale

	if ship is ShipController:
		faction = (ship as ShipController).faction
		if (ship as ShipController).ship_data:
			ship_id = (ship as ShipController).ship_data.ship_id
			ship_class = (ship as ShipController).ship_data.ship_class
