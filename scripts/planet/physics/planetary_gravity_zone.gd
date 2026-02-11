class_name PlanetaryGravityZone
extends Area3D

# =============================================================================
# Planetary Gravity Zone — Area3D that applies progressive gravity
# toward the planet center. Managed by PlanetApproachManager.
# This is a simpler alternative to modifying _integrate_forces directly.
# Currently unused — gravity is applied via PlanetApproachManager signals
# directly in ShipController._integrate_forces() for better control.
# Kept for potential future use with other physics bodies (debris, etc.)
# =============================================================================

const BASE_GRAVITY: float = 9.8  # m/s² at surface

var planet_center: Vector3 = Vector3.ZERO
var planet_radius: float = 50_000.0
var gravity_enabled: bool = false


func setup(center: Vector3, radius: float) -> void:
	planet_center = center
	planet_radius = radius

	# Large sphere collision shape covering the gravity well
	var shape := SphereShape3D.new()
	shape.radius = radius * 3.0  # Gravity extends to 3x radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	gravity_space_override = Area3D.SPACE_OVERRIDE_COMBINE
	gravity_point = true
	gravity_point_center = Vector3.ZERO  # Relative to self (planet center)
	gravity = BASE_GRAVITY
	gravity_direction = Vector3.DOWN  # Overridden by gravity_point

	# Don't block other physics — only applies gravity
	collision_layer = 0
	collision_mask = Constants.LAYER_SHIPS
