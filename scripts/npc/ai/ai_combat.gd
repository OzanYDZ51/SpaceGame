class_name AICombat
extends RefCounted

# =============================================================================
# AI Combat — Fire control for forward guns and turrets.
# Extracted from AIPilot.fire_at_target + WeaponManager turret logic.
# Works for both ships (forward + turrets) and stations (turrets only).
# =============================================================================

const LOS_COLLISION_MASK: int = 7  # LAYER_SHIPS(1) | LAYER_STATIONS(2) | LAYER_ASTEROIDS(4)

var _owner_node: Node3D = null
var _weapon_manager = null
var _targeting_system = null


func setup(owner: Node3D) -> void:
	_owner_node = owner
	_cache_refs.call_deferred()


func _cache_refs() -> void:
	if _owner_node == null:
		return
	_weapon_manager = _owner_node.get_node_or_null("WeaponManager")
	_targeting_system = _owner_node.get_node_or_null("TargetingSystem")


func try_fire_forward(target: Node3D, accuracy_mod: float, guard_station: Node3D = null) -> void:
	if _owner_node == null or target == null or not is_instance_valid(target):
		return
	if _weapon_manager == null:
		return

	var target_pos: Vector3
	if _targeting_system:
		_targeting_system.current_target = target
		target_pos = _targeting_system.get_lead_indicator_position()
	else:
		target_pos = target.global_position

	var inaccuracy := (1.0 - accuracy_mod) * 12.0
	target_pos += Vector3(
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy)
	)

	var to_target: Vector3 = (target_pos - _owner_node.global_position).normalized()
	var forward: Vector3 = -_owner_node.global_transform.basis.z
	var dot: float = forward.dot(to_target)
	if dot > 0.6:
		var space = _owner_node.get_world_3d().direct_space_state
		if space:
			var los_query := PhysicsRayQueryParameters3D.create(
				_owner_node.global_position, target.global_position)
			los_query.collision_mask = LOS_COLLISION_MASK
			los_query.collide_with_areas = false
			var exclude_rids: Array[RID] = [_owner_node.get_rid()]
			if target is CollisionObject3D:
				exclude_rids.append(target.get_rid())
			# Exclude guard station to prevent station blocking guard's own shots
			if guard_station and is_instance_valid(guard_station):
				if guard_station is CollisionObject3D:
					exclude_rids.append(guard_station.get_rid())
			los_query.exclude = exclude_rids
			var los_hit = space.intersect_ray(los_query)
			if not los_hit.is_empty():
				return
		_weapon_manager.fire_group(0, true, target_pos)


func update_turrets(target: Node3D) -> void:
	if _weapon_manager:
		_weapon_manager.update_turrets(target)
