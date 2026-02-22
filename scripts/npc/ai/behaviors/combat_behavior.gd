class_name CombatBehavior
extends AIBehavior

# =============================================================================
# Combat Behavior — Pursue and attack a target.
# Extracted from AIBrain._tick_pursue + _tick_attack.
# Sub-states: PURSUE → ATTACK → back to PURSUE or disengage.
# =============================================================================

enum SubState { PURSUE, ATTACK }

var sub_state: SubState = SubState.PURSUE
var target: Node3D = null

const MIN_SAFE_DIST: float = Constants.AI_MIN_SAFE_DIST

var _cached_target_health = null
var _cached_target_ref: Node3D = null


func enter() -> void:
	sub_state = SubState.PURSUE


func exit() -> void:
	target = null
	_cached_target_health = null
	_cached_target_ref = null


func set_target(node: Node3D) -> void:
	target = node
	_cached_target_ref = null
	_cached_target_health = null


func tick(dt: float) -> void:
	if controller == null:
		return

	if not _is_target_valid():
		# Try next highest threat
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
			return
		sub_state = SubState.PURSUE

	match sub_state:
		SubState.PURSUE:
			_tick_pursue()
		SubState.ATTACK:
			_tick_attack(dt)


func _tick_pursue() -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	var dist: float = nav.get_distance_to(target.global_position)

	if dist < MIN_SAFE_DIST:
		var away: Vector3 = (controller._ship.global_position - target.global_position).normalized()
		nav.fly_toward(controller._ship.global_position + away * 300.0, 10.0)
		return

	if dist > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		return

	var engage_mult := 2.0 if controller.environment and controller.environment.in_asteroid_belt else 1.5
	if dist <= controller.preferred_range * engage_mult:
		sub_state = SubState.ATTACK
		return

	nav.fly_intercept(target, controller.preferred_range)

	if dist < controller.preferred_range and controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.accuracy * 0.6, controller.guard_station)


func _tick_attack(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	var dist: float = nav.get_distance_to(target.global_position)

	if dist < MIN_SAFE_DIST:
		var away: Vector3 = (controller._ship.global_position - target.global_position).normalized()
		nav.fly_toward(controller._ship.global_position + away * 300.0, 10.0)
		return

	if dist > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		else:
			sub_state = SubState.PURSUE
		return

	nav.update_combat_maneuver(dt)

	if dist > controller.preferred_range * 1.3:
		nav.fly_intercept(target, controller.preferred_range)
	else:
		# Use the SAME lead position that try_fire_forward will use for dot check
		var lead_pos: Vector3 = controller.combat.get_lead_position(target)
		nav.face_target(lead_pos)
		nav.apply_attack_throttle(dist, controller.preferred_range)

	if controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.accuracy, controller.guard_station)


func _is_target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree():
		return false
	if _cached_target_ref != target:
		_cached_target_ref = target
		_cached_target_health = target.get_node_or_null("HealthSystem")
	if _cached_target_health and _cached_target_health.is_dead():
		return false
	return true


func get_behavior_name() -> StringName:
	return NAME_COMBAT
