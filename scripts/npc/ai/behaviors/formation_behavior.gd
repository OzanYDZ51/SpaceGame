class_name FormationBehavior
extends AIBehavior

# =============================================================================
# Formation Behavior — Follow a leader with velocity-based basis (anti-jitter).
# Extracted from AIBrain._tick_formation.
# =============================================================================

var leader: Node3D = null
var offset: Vector3 = Vector3.ZERO


func set_leader(node: Node3D, formation_offset: Vector3) -> void:
	leader = node
	offset = formation_offset


func tick(_dt: float) -> void:
	if controller == null:
		return
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	if leader == null or not is_instance_valid(leader):
		# Leader dead → become autonomous, patrol around current position
		var pb := PatrolBehavior.new()
		pb.controller = controller
		pb.set_patrol_area(controller._ship.global_position, 2000.0)
		controller._set_behavior(pb)
		controller._default_behavior = pb
		controller.mode = AIController.Mode.BEHAVIOR
		return

	# Follow leader into combat: if leader has a target, engage it
	if controller.weapons_enabled and leader.has_node("AIController"):
		var leader_ctrl = leader.get_node("AIController")
		if leader_ctrl and leader_ctrl._combat_behavior and leader_ctrl._combat_behavior.target:
			var lt = leader_ctrl._combat_behavior.target
			if is_instance_valid(lt):
				var tdist: float = controller._ship.global_position.distance_to(lt.global_position)
				if tdist < controller.disengage_range:
					controller._enter_combat(lt)
					return

	# Use leader's velocity direction for formation basis (anti-jitter)
	var leader_vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in leader:
		leader_vel = leader.linear_velocity
	var formation_basis: Basis
	if leader_vel.length_squared() > 25.0:
		var fwd: Vector3 = -leader_vel.normalized()
		var up: Vector3 = Vector3.UP
		var right: Vector3 = up.cross(fwd).normalized()
		if right.length_squared() < 0.5:
			right = Vector3.RIGHT
		up = fwd.cross(right).normalized()
		formation_basis = Basis(right, up, fwd)
	else:
		formation_basis = leader.global_transform.basis
	var target_pos: Vector3 = leader.global_position + formation_basis * offset
	nav.fly_toward(target_pos, 20.0)


func get_behavior_name() -> StringName:
	return NAME_FORMATION
