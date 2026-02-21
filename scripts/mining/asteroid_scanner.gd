class_name AsteroidScanner
extends Node

# =============================================================================
# Asteroid Scanner — Sends expanding ring pulses to reveal asteroid resources
# Triggered by H key. Cooldown 8s, range 5km, reveal lasts 30s.
# Multiple pulses can coexist — each is independent.
# =============================================================================

signal scan_triggered
signal scan_cooldown_changed(remaining: float, total: float)
signal scan_results(count: int)

const SCAN_COOLDOWN: float = 8.0
const SCAN_RANGE: float = 5000.0

var _asteroid_mgr = null
var _ship: RigidBody3D = null
var _universe_node: Node3D = null

var _cooldown: float = 0.0
var _notif: NotificationService = null

# Each active pulse tracks its own reveal count
var _active_pulses: Array[Dictionary] = []  # [{pulse, revealed}]


func initialize(mgr, ship: RigidBody3D, universe: Node3D) -> void:
	_asteroid_mgr = mgr
	_ship = ship
	_universe_node = universe


func set_notification_service(notif: NotificationService) -> void:
	_notif = notif


func can_scan() -> bool:
	return _cooldown <= 0.0


## Returns array of {position: Vector3, radius: float} for each active pulse (for radar).
func get_active_pulses_info() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for data in _active_pulses:
		var pulse: ScannerPulseEffect = data["pulse"]
		if is_instance_valid(pulse):
			result.append({"position": pulse.global_position, "radius": pulse._current_radius})
	return result


func trigger_scan() -> void:
	if not can_scan():
		return
	if _ship == null or _universe_node == null or _asteroid_mgr == null:
		return

	_cooldown = SCAN_COOLDOWN

	# Spawn pulse effect at ship position (in Universe node so it shifts with origin)
	var pulse =ScannerPulseEffect.new()
	pulse.name = "ScannerPulse_%d" % Time.get_ticks_msec()
	pulse.position = _ship.global_position
	_universe_node.add_child(pulse)

	var pulse_data ={"pulse": pulse, "revealed": 0}
	_active_pulses.append(pulse_data)

	pulse.scan_radius_updated.connect(_on_pulse_radius_updated.bind(pulse_data))
	pulse.scan_completed.connect(_on_pulse_completed.bind(pulse_data))

	scan_triggered.emit()


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
		scan_cooldown_changed.emit(_cooldown, SCAN_COOLDOWN)


func _on_pulse_radius_updated(radius: float, data: Dictionary) -> void:
	if _asteroid_mgr == null:
		return
	var pulse: ScannerPulseEffect = data["pulse"]
	if not is_instance_valid(pulse):
		return
	var center: Vector3 = pulse.global_position
	var count: int = _asteroid_mgr.reveal_asteroids_in_radius(center, radius)
	data["revealed"] += count


func _on_pulse_completed(data: Dictionary) -> void:
	var revealed: int = data["revealed"]
	_active_pulses.erase(data)
	scan_results.emit(revealed)

	if _notif:
		if revealed > 0:
			_notif.toast("%d GISEMENT%s DETECTE%s" % [revealed, "S" if revealed > 1 else "", "S" if revealed > 1 else ""], UIToast.ToastType.SUCCESS, 3.0)
		else:
			_notif.toast("AUCUN GISEMENT DETECTE", UIToast.ToastType.WARNING, 3.0)
