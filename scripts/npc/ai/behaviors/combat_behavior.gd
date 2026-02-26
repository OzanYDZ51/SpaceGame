class_name CombatBehavior
extends AIBehavior

# =============================================================================
# Combat Behavior — Attack-run passes (X4/Elite style).
# 4 cyclic sub-states: ENGAGE → ATTACK_RUN → BREAK_OFF → REPOSITION → ...
# Light ships (fighters) do fast, tight passes. Heavy ships (frigates) do
# slower, sustained runs. Replaces the old PURSUE/ATTACK orbit standoff.
# =============================================================================

enum SubState { ENGAGE, ATTACK_RUN, BREAK_OFF, REPOSITION }

var sub_state: SubState = SubState.ENGAGE
var target: Node3D = null

const MIN_SAFE_DIST: float = Constants.AI_MIN_SAFE_DIST

# Phase timers (accumulate dt — works at any AI LOD tick rate)
var _run_timer: float = 0.0
var _break_off_timer: float = 0.0
var _break_off_duration: float = 2.0
var _reposition_timer: float = 0.0

# Break-off direction (randomised at break initiation)
var _break_off_dir: Vector3 = Vector3.ZERO

# Reposition target point (where to fly before next pass)
var _reposition_point: Vector3 = Vector3.ZERO

# Ship classification cache
var _is_heavy: bool = false

# Target validity cache
var _cached_target_health = null
var _cached_target_ref: Node3D = null


func enter() -> void:
	sub_state = SubState.ENGAGE
	_run_timer = 0.0
	_break_off_timer = 0.0
	_reposition_timer = 0.0
	_break_off_dir = Vector3.ZERO
	_reposition_point = Vector3.ZERO

	# Classify ship as heavy or light
	_is_heavy = false
	if controller and controller._ship and "ship_data" in controller._ship:
		var sd = controller._ship.ship_data
		if sd:
			_is_heavy = sd.ship_class in [&"Frigate", &"Croiseur", &"Freighter"]


func exit() -> void:
	target = null
	_cached_target_health = null
	_cached_target_ref = null


func set_target(node: Node3D) -> void:
	target = node
	_cached_target_ref = null
	_cached_target_health = null
	# Reset to engage when switching targets
	if sub_state == SubState.REPOSITION or sub_state == SubState.BREAK_OFF:
		sub_state = SubState.ENGAGE
		_run_timer = 0.0


func tick(dt: float) -> void:
	if controller == null:
		return

	if not _is_target_valid():
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
			return
		sub_state = SubState.ENGAGE
		_run_timer = 0.0

	match sub_state:
		SubState.ENGAGE:
			_tick_engage(dt)
		SubState.ATTACK_RUN:
			_tick_attack_run(dt)
		SubState.BREAK_OFF:
			_tick_break_off(dt)
		SubState.REPOSITION:
			_tick_reposition(dt)


# =============================================================================
# ENGAGE — Aggressive intercept approach, opportunistic fire
# =============================================================================
func _tick_engage(_dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	var dist: float = nav.get_distance_to(target.global_position)

	# Disengage check
	if dist > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		return

	# Transition to attack run
	var engage_threshold: float = controller.preferred_range * (0.8 if _is_heavy else 1.2)
	if dist <= engage_threshold:
		_begin_attack_run()
		return

	# Fly intercept toward target
	nav.fly_intercept(target, controller.preferred_range)

	# Opportunistic fire during approach
	if dist < controller.preferred_range and controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# ATTACK_RUN — Full speed charge, face lead position, fire at lead
# =============================================================================
func _tick_attack_run(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_run_timer += dt
	var dist: float = nav.get_distance_to(target.global_position)

	# Break-off conditions
	var max_run_time: float = Constants.AI_ATTACK_RUN_MAX_TIME_HEAVY if _is_heavy else Constants.AI_ATTACK_RUN_MAX_TIME_LIGHT
	var pass_dist: float = Constants.AI_PASS_DISTANCE_HEAVY if _is_heavy else Constants.AI_PASS_DISTANCE_LIGHT

	if dist < pass_dist or _has_flown_past_target() or _run_timer > max_run_time:
		_initiate_break_off()
		return

	# Disengage check (target fled)
	if dist > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		else:
			sub_state = SubState.ENGAGE
			_run_timer = 0.0
		return

	# Face lead position + charge forward
	var lead_pos: Vector3 = controller.combat.get_lead_position(target)
	nav.face_target(lead_pos)
	nav.update_combat_maneuver(dt)
	nav.apply_attack_run_throttle(dist, controller.preferred_range, _is_heavy)

	# Fire at lead position
	if controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# BREAK_OFF — Evasive turn away, no fire
# =============================================================================
func _tick_break_off(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_break_off_timer += dt
	var dist: float = nav.get_distance_to(target.global_position)

	# Transition to reposition
	if _break_off_timer > _break_off_duration or dist > controller.preferred_range * 0.6:
		_begin_reposition()
		return

	# Fly along break-off direction
	var break_point: Vector3 = controller._ship.global_position + _break_off_dir * 500.0
	nav.fly_toward(break_point, 10.0)


# =============================================================================
# REPOSITION — Circle back to set up next pass, no fire
# =============================================================================
func _tick_reposition(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_reposition_timer += dt
	var dist_to_point: float = nav.get_distance_to(_reposition_point)
	var dist_to_target: float = nav.get_distance_to(target.global_position)

	# Disengage check
	if dist_to_target > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		else:
			sub_state = SubState.ENGAGE
			_run_timer = 0.0
		return

	# Transition to engage (next pass)
	if dist_to_point < 200.0 or _reposition_timer > Constants.AI_REPOSITION_MAX_TIME:
		sub_state = SubState.ENGAGE
		_run_timer = 0.0
		return

	nav.fly_toward(_reposition_point, 150.0)


# =============================================================================
# PHASE TRANSITIONS
# =============================================================================
func _begin_attack_run() -> void:
	sub_state = SubState.ATTACK_RUN
	_run_timer = 0.0


func _initiate_break_off() -> void:
	sub_state = SubState.BREAK_OFF
	_break_off_timer = 0.0

	# Randomise break-off duration (heavy ships take longer)
	var min_dur: float = Constants.AI_BREAK_OFF_DURATION_MIN
	var max_dur: float = Constants.AI_BREAK_OFF_DURATION_MAX
	if _is_heavy:
		min_dur += 0.5
		max_dur += 1.0
	_break_off_duration = randf_range(min_dur, max_dur)

	# Compute break-off direction: mostly away + random lateral + vertical
	var to_target: Vector3 = target.global_position - controller._ship.global_position
	var away: Vector3 = -to_target.normalized()

	# Random perpendicular component
	var up := Vector3.UP
	var right := away.cross(up).normalized()
	if right.length_squared() < 0.5:
		right = away.cross(Vector3.RIGHT).normalized()
	var lat := right * randf_range(-1.0, 1.0)
	var vert := up * randf_range(-0.6, 0.6)

	_break_off_dir = (away * 0.6 + lat * 0.3 + vert * 0.2).normalized()


func _begin_reposition() -> void:
	sub_state = SubState.REPOSITION
	_reposition_timer = 0.0
	_reposition_point = _compute_reposition_point()


func _compute_reposition_point() -> Vector3:
	if target == null or not is_instance_valid(target):
		return controller._ship.global_position

	var target_pos: Vector3 = target.global_position
	var pref_range: float = controller.preferred_range

	# Random angle offset from current approach direction (new angle each pass)
	var to_target: Vector3 = target_pos - controller._ship.global_position
	var base_dir: Vector3 = -to_target.normalized()  # away from target

	# Rotate base_dir by random yaw (±0.5 to ±1.2 rad) and pitch (±0.4 rad)
	var yaw_offset: float = randf_range(0.5, 1.2) * (1.0 if randf() > 0.5 else -1.0)
	var pitch_offset: float = randf_range(-0.4, 0.4)

	# Build rotated direction using basis rotation
	var up := Vector3.UP
	var right := base_dir.cross(up).normalized()
	if right.length_squared() < 0.5:
		right = base_dir.cross(Vector3.RIGHT).normalized()
	up = right.cross(base_dir).normalized()

	var rotated: Vector3 = base_dir * cos(yaw_offset) + right * sin(yaw_offset)
	rotated = rotated * cos(pitch_offset) + up * sin(pitch_offset)
	rotated = rotated.normalized()

	var point: Vector3 = target_pos + rotated * pref_range

	# Guard station constraint: clamp within disengage_range of station
	if controller.guard_station and is_instance_valid(controller.guard_station):
		var station_pos: Vector3 = controller.guard_station.global_position
		var to_point: Vector3 = point - station_pos
		var max_dist: float = controller.disengage_range * 0.8
		if to_point.length() > max_dist:
			point = station_pos + to_point.normalized() * max_dist

	return point


# =============================================================================
# HELPERS
# =============================================================================
func _has_flown_past_target() -> bool:
	if controller._ship == null or target == null:
		return false
	var to_target: Vector3 = target.global_position - controller._ship.global_position
	var vel: Vector3 = controller._ship.linear_velocity
	if vel.length_squared() < 100.0:
		return false
	return vel.normalized().dot(to_target.normalized()) < -0.3


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
