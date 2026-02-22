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

	# Dot check on CLEAN lead position (before inaccuracy) — front hemisphere only.
	# Hardpoints already prevent backward shots internally.
	# Threshold at 0.0 (90°) because face_target queues rotation that hasn't applied yet,
	# so the ship is always "catching up" to the lead position.
	var to_lead: Vector3 = (target_pos - _owner_node.global_position).normalized()
	var forward: Vector3 = -_owner_node.global_transform.basis.z
	if forward.dot(to_lead) < 0.0:
		return

	# Apply inaccuracy AFTER dot check (only affects fire direction, not firing decision)
	var inaccuracy := (1.0 - accuracy_mod) * Constants.AI_INACCURACY_SPREAD
	target_pos += Vector3(
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy),
		randf_range(-inaccuracy, inaccuracy)
	)

	# LOS check
	var space = _owner_node.get_world_3d().direct_space_state
	if space:
		var los_query := PhysicsRayQueryParameters3D.create(
			_owner_node.global_position, target.global_position)
		los_query.collision_mask = LOS_COLLISION_MASK
		los_query.collide_with_areas = false
		var exclude_rids: Array[RID] = [_owner_node.get_rid()]
		if target is CollisionObject3D:
			exclude_rids.append(target.get_rid())
		else:
			# RemotePlayerShip is Node3D — exclude its HitBody child so LOS isn't blocked
			var hit_body = target.get_node_or_null("HitBody")
			if hit_body and hit_body is CollisionObject3D:
				exclude_rids.append(hit_body.get_rid())
		# Exclude guard station to prevent station blocking guard's own shots
		if guard_station and is_instance_valid(guard_station):
			if guard_station is CollisionObject3D:
				exclude_rids.append(guard_station.get_rid())
		los_query.exclude = exclude_rids
		var los_hit = space.intersect_ray(los_query)
		if not los_hit.is_empty():
			return
	_weapon_manager.fire_group(0, true, target_pos)


func get_lead_position(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		if _owner_node:
			return _owner_node.global_position + (-_owner_node.global_transform.basis.z) * 500.0
		return Vector3.ZERO
	if _targeting_system:
		_targeting_system.current_target = target
		return _targeting_system.get_lead_indicator_position()
	# Fallback: simple linear lead (no targeting system)
	if _owner_node == null:
		return target.global_position
	var target_vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in target:
		target_vel = target.linear_velocity
	var to_target: Vector3 = target.global_position - _owner_node.global_position
	var dist: float = to_target.length()
	var my_vel: Vector3 = _owner_node.linear_velocity if "linear_velocity" in _owner_node else Vector3.ZERO
	var closing: float = maxf(-(my_vel - target_vel).dot(to_target.normalized()), 10.0)
	var tti: float = clampf(dist / closing, 0.0, 3.0)
	return target.global_position + target_vel * tti


func update_turrets(target: Node3D) -> void:
	if _weapon_manager:
		_weapon_manager.update_turrets(target)
