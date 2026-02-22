class_name GuardBehavior
extends AIBehavior

# =============================================================================
# Guard Behavior — Patrol near a station/point and respond to alerts.
# Used by station guard NPCs AND station turrets (via AIController).
# Replaces StationDefenseAI.alert_guards + guard logic from AIBrain.
# =============================================================================

const GUARD_REALERT_INTERVAL: float = 3.0
const SCAN_INTERVAL: float = 0.5

var guard_target: Node3D = null  # Station or point to guard

# Station turret mode (no movement, turrets only)
var turret_only: bool = false

# Patrol sub-behavior for mobile guards
var _patrol: PatrolBehavior = null
var _scan_timer: float = 0.0
var _guard_alert_timer: float = 0.0


func enter() -> void:
	if not turret_only:
		_patrol = PatrolBehavior.new()
		_patrol.controller = controller
		# Initialize patrol around the guard target, offset from station center
		if guard_target and is_instance_valid(guard_target):
			var offset_dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var offset_center := guard_target.global_position + offset_dir * (AIEnvironment.STATION_MODEL_RADIUS + 500.0)
			_patrol.set_patrol_area(offset_center, 800.0)
		_patrol.enter()


func exit() -> void:
	if _patrol:
		_patrol.exit()
		_patrol = null


func set_guard_target(station: Node3D) -> void:
	guard_target = station


func tick(dt: float) -> void:
	if controller == null:
		return

	# Station turret mode: just scan and fire turrets
	if turret_only:
		_tick_turret_guard(dt)
		return

	# Mobile guard: patrol near station, detect threats
	if _patrol:
		_patrol.tick(dt)


func _tick_turret_guard(dt: float) -> void:
	# Periodic scan for targets (same as StationDefenseAI)
	_scan_timer -= dt
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		var threat = controller.perception.detect_nearest_hostile(controller.detection_range)
		if threat:
			# Check if this is a new target
			var prev = controller._combat_behavior.target if controller._combat_behavior else null
			if threat != prev:
				_alert_nearby_guards(threat)
				_guard_alert_timer = GUARD_REALERT_INTERVAL
			if controller._combat_behavior:
				controller._combat_behavior.set_target(threat)

	# Re-alert guards periodically
	if controller._combat_behavior and controller._combat_behavior.target:
		_guard_alert_timer -= dt
		if _guard_alert_timer <= 0.0:
			_guard_alert_timer = GUARD_REALERT_INTERVAL
			_alert_nearby_guards(controller._combat_behavior.target)


func _alert_nearby_guards(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if guard_target == null or not is_instance_valid(guard_target):
		return
	# Alert station's own perception (turrets)
	controller.perception.alert_to_threat(attacker)
	# Alert all guard NPCs
	if not controller._ship.is_inside_tree():
		return
	for ship in controller._ship.get_tree().get_nodes_in_group("ships"):
		if ship == null or not is_instance_valid(ship):
			continue
		var ctrl = ship.get_node_or_null("AIController")
		if ctrl and ctrl.guard_station == guard_target:
			ctrl.alert_to_threat(attacker)


func get_behavior_name() -> StringName:
	return &"guard"
