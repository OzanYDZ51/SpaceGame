class_name CombatBehavior
extends AIBehavior

# =============================================================================
# Combat Behavior — Dogfight system (X4/Star Citizen style).
# 5 cyclic sub-states: CLOSE_IN → ATTACK_PASS → LEAD_TURN → DOGFIGHT ←→ DISENGAGE_TURN
# Light ships orbit tight and fast. Heavy ships orbit wide and slow.
# ~75-80% of combat time is spent actively firing (vs ~20-30% with old joust).
# =============================================================================

enum SubState { CLOSE_IN, ATTACK_PASS, LEAD_TURN, DOGFIGHT, DISENGAGE_TURN }

var sub_state: SubState = SubState.CLOSE_IN
var target: Node3D = null

const MIN_SAFE_DIST: float = Constants.AI_MIN_SAFE_DIST

# Phase timers
var _pass_timer: float = 0.0
var _lead_turn_timer: float = 0.0
var _dogfight_timer: float = 0.0
var _disengage_timer: float = 0.0
var _disengage_duration: float = 1.0

# Dogfight orbit state
var _orbit_direction: float = 1.0       # +1 = orbit right, -1 = orbit left
var _orbit_reversal_timer: float = 0.0
var _vert_phase: float = 0.0            # Sinusoidal vertical weave phase

# Attack pass state
var _pass_side: float = 1.0             # +1 = strafe right, -1 = strafe left

# Disengage state
var _disengage_dir: Vector3 = Vector3.ZERO

# Ship classification cache
var _is_heavy: bool = false

# Target validity cache
var _cached_target_health = null
var _cached_target_ref: Node3D = null

# Blind spot analysis (recalculated every 0.5s, not every frame)
var _blind_spot_cache: Dictionary = {}
var _blind_spot_timer: float = 0.0


func enter() -> void:
	sub_state = SubState.CLOSE_IN
	_pass_timer = 0.0
	_lead_turn_timer = 0.0
	_dogfight_timer = 0.0
	_disengage_timer = 0.0
	_disengage_dir = Vector3.ZERO
	_orbit_direction = 1.0 if randf() > 0.5 else -1.0
	_orbit_reversal_timer = randf_range(3.0, 6.0)
	_vert_phase = randf() * TAU
	_pass_side = 1.0 if randf() > 0.5 else -1.0

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
	_blind_spot_cache = {}
	_blind_spot_timer = 0.0


func set_target(node: Node3D) -> void:
	target = node
	_cached_target_ref = null
	_cached_target_health = null
	# Reset to close_in when switching targets
	if sub_state == SubState.DISENGAGE_TURN:
		sub_state = SubState.CLOSE_IN
		_pass_timer = 0.0


func tick(dt: float) -> void:
	if controller == null:
		return

	if not _is_target_valid():
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
			return
		sub_state = SubState.CLOSE_IN
		_pass_timer = 0.0

	# Formation leash: if we have a formation leader and drifted too far, abandon
	# combat and return to formation (escorts must protect the convoy, not chase)
	if controller._default_behavior and controller._default_behavior is FormationBehavior:
		var fb: FormationBehavior = controller._default_behavior as FormationBehavior
		if fb.leader and is_instance_valid(fb.leader):
			var dist_to_leader: float = controller._ship.global_position.distance_to(fb.leader.global_position)
			if dist_to_leader > Constants.AI_FORMATION_LEASH_DISTANCE:
				controller._end_combat()
				return

	match sub_state:
		SubState.CLOSE_IN:
			_tick_close_in(dt)
		SubState.ATTACK_PASS:
			_tick_attack_pass(dt)
		SubState.LEAD_TURN:
			_tick_lead_turn(dt)
		SubState.DOGFIGHT:
			_tick_dogfight(dt)
		SubState.DISENGAGE_TURN:
			_tick_disengage_turn(dt)


# =============================================================================
# CLOSE_IN — Aggressive intercept approach, opportunistic fire
# =============================================================================
func _tick_close_in(_dt: float) -> void:
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

	# Transition to attack pass when close enough
	var merge_range: float = controller.preferred_range * (0.5 if _is_heavy else 0.8)
	if dist <= merge_range:
		_begin_attack_pass()
		return

	# Fly intercept toward target
	nav.fly_intercept(target, controller.preferred_range)

	# Opportunistic fire during approach
	if dist < controller.preferred_range and controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# ATTACK_PASS — Short attack pass with lateral offset, fire continuously
# =============================================================================
func _tick_attack_pass(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_pass_timer += dt
	var dist: float = nav.get_distance_to(target.global_position)

	# Max pass time
	var max_pass_time: float = Constants.AI_ATTACK_PASS_MAX_TIME_HEAVY if _is_heavy else Constants.AI_ATTACK_PASS_MAX_TIME_LIGHT
	var pass_dist: float = Constants.AI_PASS_DISTANCE_HEAVY if _is_heavy else Constants.AI_PASS_DISTANCE_LIGHT

	# Transition conditions
	if _has_flown_past_target() or dist < pass_dist:
		_begin_lead_turn()
		return
	if _pass_timer > max_pass_time:
		# Merged without flying past — go straight to dogfight
		_begin_dogfight()
		return

	# Disengage check (target fled)
	if dist > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		else:
			sub_state = SubState.CLOSE_IN
			_pass_timer = 0.0
		return

	# Face lead position + charge with lateral offset
	var lead_pos: Vector3 = controller.combat.get_lead_position(target)
	nav.face_target(lead_pos)
	nav.update_combat_maneuver(dt)
	nav.apply_attack_pass_throttle(dist, controller.preferred_range, _is_heavy, _pass_side)

	# Fire continuously
	if controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# LEAD_TURN — Immediate turn toward target after passing (replaces BREAK_OFF)
# =============================================================================
func _tick_lead_turn(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_lead_turn_timer += dt
	var dist: float = nav.get_distance_to(target.global_position)

	# Face the target — turn hard toward it
	nav.face_target(target.global_position)

	# Check alignment
	var forward: Vector3 = -controller._ship.global_transform.basis.z
	var to_target: Vector3 = (target.global_position - controller._ship.global_position).normalized()
	var alignment: float = forward.dot(to_target)

	# Moderate forward throttle + slight vertical offset for 3D
	var vert: float = sin(_vert_phase) * 0.15
	controller._ship.set_throttle(Vector3(0.0, vert, -0.4))

	# Transition conditions
	if alignment > 0.7:
		if dist < controller.preferred_range:
			_begin_dogfight()
		else:
			sub_state = SubState.CLOSE_IN
			_pass_timer = 0.0
		return

	# Force merge after max lead turn time
	if _lead_turn_timer > Constants.AI_LEAD_TURN_MAX_TIME:
		_begin_dogfight()
		return

	# Opportunistic fire if somewhat aligned
	if alignment > 0.5 and controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# DOGFIGHT — Sustained close combat orbit (main state, ~60-70% of combat time)
# =============================================================================
func _tick_dogfight(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_dogfight_timer += dt

	var dist: float = nav.get_distance_to(target.global_position)
	var ideal_radius: float = Constants.AI_DOGFIGHT_ORBIT_RADIUS_HEAVY if _is_heavy else Constants.AI_DOGFIGHT_ORBIT_RADIUS_LIGHT
	var max_dogfight_time: float = Constants.AI_DOGFIGHT_MAX_TIME_HEAVY if _is_heavy else Constants.AI_DOGFIGHT_MAX_TIME_LIGHT

	# Update blind spot analysis (every 0.5s)
	_blind_spot_timer -= dt
	if _blind_spot_timer <= 0.0:
		_blind_spot_timer = 0.5
		_blind_spot_cache = BlindSpotAnalyzer.analyze(target, controller._ship.global_position)

	# Update vertical weave phase (bias toward blind spot if available)
	var vert_speed: float = 0.6 if _is_heavy else 1.5
	_vert_phase += vert_speed * dt

	# Update orbit reversal timer
	_orbit_reversal_timer -= dt
	if _orbit_reversal_timer <= 0.0:
		_orbit_reversal_timer = randf_range(3.0, 6.0)
		var preferred_side: float = _blind_spot_cache.get("orbit_side", 0.0)
		if preferred_side != 0.0:
			# Blind spot found — steer toward it (occasional random flip for unpredictability)
			if randf() < 0.85:
				_orbit_direction = preferred_side
			else:
				_orbit_direction *= -1.0
		else:
			# No preference — keep existing random behavior
			if randf() < 0.3:
				_orbit_direction *= -1.0

	# Disengage check: target fled or max time reached
	if dist > ideal_radius * 2.5:
		sub_state = SubState.CLOSE_IN
		_pass_timer = 0.0
		return

	if _dogfight_timer > max_dogfight_time:
		_begin_disengage_turn()
		return

	# Target dead/invalid check happens in tick() already

	# Face lead position while orbiting
	var lead_pos: Vector3 = controller.combat.get_lead_position(target)
	nav.face_target(lead_pos)

	# Orbit throttle — bias vertical weave toward blind spot
	var orbit_strength: float = 0.4 if _is_heavy else 0.7
	var vert_bias: float = _blind_spot_cache.get("vertical_bias", 0.0)
	var vert_offset: float = sin(_vert_phase) + vert_bias * 0.5
	nav.apply_dogfight_throttle(target, ideal_radius, _orbit_direction, orbit_strength, vert_offset, _is_heavy)

	# Fire continuously while orbiting
	if controller.weapons_enabled:
		controller.combat.try_fire_forward(target, controller.guard_station)


# =============================================================================
# DISENGAGE_TURN — Brief disengagement for variety (replaces REPOSITION)
# =============================================================================
func _tick_disengage_turn(dt: float) -> void:
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	_disengage_timer += dt

	# Transition: timer expired → re-engage
	if _disengage_timer > _disengage_duration:
		var dist: float = nav.get_distance_to(target.global_position)
		if dist > controller.preferred_range * 0.5:
			sub_state = SubState.CLOSE_IN
			_pass_timer = 0.0
		else:
			_begin_dogfight()
		return

	# Disengage check
	var dist_to_target: float = nav.get_distance_to(target.global_position)
	if dist_to_target > controller.disengage_range:
		target = controller.perception.get_highest_threat()
		if target == null:
			controller._end_combat()
		else:
			sub_state = SubState.CLOSE_IN
			_pass_timer = 0.0
		return

	# Fly along disengage direction — no fire
	var disengage_point: Vector3 = controller._ship.global_position + _disengage_dir * 400.0
	nav.fly_toward(disengage_point, 10.0)


# =============================================================================
# PHASE TRANSITIONS
# =============================================================================
func _begin_attack_pass() -> void:
	sub_state = SubState.ATTACK_PASS
	_pass_timer = 0.0
	# Bias pass side toward target's blind spot
	var analysis: Dictionary = BlindSpotAnalyzer.analyze(target, controller._ship.global_position)
	var preferred: float = analysis.get("orbit_side", 0.0)
	if preferred != 0.0:
		_pass_side = preferred
	else:
		_pass_side = 1.0 if randf() > 0.5 else -1.0


func _begin_lead_turn() -> void:
	sub_state = SubState.LEAD_TURN
	_lead_turn_timer = 0.0
	# Small random vertical offset for 3D variety
	_vert_phase = randf() * TAU


func _begin_dogfight() -> void:
	sub_state = SubState.DOGFIGHT
	_dogfight_timer = 0.0
	_blind_spot_timer = 0.0  # Force immediate analysis
	_orbit_reversal_timer = randf_range(3.0, 6.0)
	_vert_phase = randf() * TAU
	# Initial orbit direction biased toward blind spot
	var analysis: Dictionary = BlindSpotAnalyzer.analyze(target, controller._ship.global_position)
	var preferred: float = analysis.get("orbit_side", 0.0)
	if preferred != 0.0:
		_orbit_direction = preferred
	else:
		_orbit_direction = 1.0 if randf() > 0.5 else -1.0


func _begin_disengage_turn() -> void:
	sub_state = SubState.DISENGAGE_TURN
	_disengage_timer = 0.0
	_disengage_duration = randf_range(Constants.AI_DISENGAGE_TURN_MIN, Constants.AI_DISENGAGE_TURN_MAX)

	# Compute disengage direction: 45-90° from target direction + vertical component
	var to_target: Vector3 = target.global_position - controller._ship.global_position
	var away: Vector3 = -to_target.normalized()

	var up := Vector3.UP
	var right := away.cross(up).normalized()
	if right.length_squared() < 0.5:
		right = away.cross(Vector3.RIGHT).normalized()

	# 45-90° offset — NOT directly away (that's boring), but not perpendicular either
	var angle_t: float = randf_range(0.4, 0.8)  # blend between away and perpendicular
	# Bias lateral direction and vertical component toward target's blind spot
	var analysis: Dictionary = BlindSpotAnalyzer.analyze(target, controller._ship.global_position)
	var lat_sign: float = analysis.get("orbit_side", 0.0)
	if lat_sign == 0.0:
		lat_sign = 1.0 if randf() > 0.5 else -1.0
	var vert_bias: float = analysis.get("vertical_bias", 0.0)
	var vert_range: float = randf_range(-0.4, 0.4) + vert_bias * 0.3
	var vert := up * vert_range

	_disengage_dir = (away * angle_t + right * lat_sign * (1.0 - angle_t) + vert * 0.3).normalized()


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
	# Docked/deactivated ships are invisible — stop targeting them
	if target is Node3D and not (target as Node3D).visible:
		return false
	if _cached_target_ref != target:
		_cached_target_ref = target
		_cached_target_health = target.get_node_or_null("HealthSystem")
	if _cached_target_health and _cached_target_health.is_dead():
		return false
	return true


func get_behavior_name() -> StringName:
	return NAME_COMBAT
