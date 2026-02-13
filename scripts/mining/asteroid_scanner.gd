class_name AsteroidScanner
extends Node

# =============================================================================
# Asteroid Scanner — Sends a pulse wave to reveal asteroid resources
# Triggered by H key. Cooldown 15s, range 5km, reveal lasts 30s.
# =============================================================================

signal scan_triggered
signal scan_cooldown_changed(remaining: float, total: float)
signal scan_results(count: int)

const SCAN_COOLDOWN: float = 15.0
const SCAN_RANGE: float = 5000.0

var _asteroid_mgr: AsteroidFieldManager = null
var _ship: RigidBody3D = null
var _universe_node: Node3D = null

var _cooldown: float = 0.0
var _is_scanning: bool = false
var _pulse: ScannerPulseEffect = null
var _last_reveal_radius: float = 0.0
var _total_revealed: int = 0
var _notif: NotificationService = null


func initialize(mgr: AsteroidFieldManager, ship: RigidBody3D, universe: Node3D) -> void:
	_asteroid_mgr = mgr
	_ship = ship
	_universe_node = universe


func set_notification_service(notif: NotificationService) -> void:
	_notif = notif


func can_scan() -> bool:
	return _cooldown <= 0.0 and not _is_scanning


func trigger_scan() -> void:
	if not can_scan():
		return
	if _ship == null or _universe_node == null or _asteroid_mgr == null:
		return

	_is_scanning = true
	_cooldown = SCAN_COOLDOWN
	_last_reveal_radius = 0.0
	_total_revealed = 0

	# Spawn pulse effect at ship position (in Universe node so it shifts with origin)
	_pulse = ScannerPulseEffect.new()
	_pulse.name = "ScannerPulse"
	_pulse.position = _ship.global_position
	_universe_node.add_child(_pulse)
	_pulse.scan_radius_updated.connect(_on_pulse_radius_updated)
	_pulse.scan_completed.connect(_on_pulse_completed)

	scan_triggered.emit()


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
		scan_cooldown_changed.emit(_cooldown, SCAN_COOLDOWN)


func _on_pulse_radius_updated(radius: float) -> void:
	if _asteroid_mgr == null or _pulse == null:
		return
	# Reveal asteroids in the annular ring between last radius and current radius
	var center: Vector3 = _pulse.global_position
	var count: int = _asteroid_mgr.reveal_asteroids_in_radius(center, radius)
	_total_revealed += count


func _on_pulse_completed() -> void:
	_is_scanning = false
	_pulse = null
	scan_results.emit(_total_revealed)

	if _notif:
		if _total_revealed > 0:
			_notif.toast("%d GISEMENT%s DETECTE%s" % [_total_revealed, "S" if _total_revealed > 1 else "", "S" if _total_revealed > 1 else ""], UIToast.ToastType.SUCCESS, 3.0)
		else:
			_notif.toast("AUCUN GISEMENT DETECTE", UIToast.ToastType.WARNING, 3.0)
