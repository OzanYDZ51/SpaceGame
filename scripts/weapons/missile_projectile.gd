class_name MissileProjectile
extends BaseProjectile

# =============================================================================
# Missile Projectile - Tracking projectile that homes toward a target
# =============================================================================

var target: Node3D = null
var tracking_strength: float = 90.0  # degrees per second
var _arm_timer: float = 0.3  # seconds before tracking activates


func _physics_process(delta: float) -> void:
	_arm_timer -= delta

	if _arm_timer <= 0.0 and target != null and is_instance_valid(target):
		var to_target: Vector3 = (target.global_position - global_position).normalized()
		var current_dir: Vector3 = velocity.normalized()
		var max_turn: float = deg_to_rad(tracking_strength) * delta
		var new_dir: Vector3 = current_dir.slerp(to_target, min(max_turn / current_dir.angle_to(to_target), 1.0)) if current_dir.angle_to(to_target) > 0.001 else current_dir
		velocity = new_dir * velocity.length()

		# Align visual rotation with velocity
		if velocity.length_squared() > 1.0:
			look_at(global_position + velocity, Vector3.UP)

	# Call base movement and lifetime
	global_position += velocity * delta
	_lifetime += delta
	if _lifetime >= max_lifetime:
		_return_to_pool()
