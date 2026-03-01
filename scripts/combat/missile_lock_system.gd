class_name MissileLockSystem
extends Node

# =============================================================================
# Missile Lock System - Manages lock-on for missile weapons
# Reads target from TargetingSystem, checks cone angle, accumulates lock progress.
# =============================================================================

signal lock_progress_changed(progress: float)
signal lock_acquired()
signal lock_lost()

var lock_progress: float = 0.0  # 0.0 → 1.0
var is_locked: bool = false
var lock_time: float = 2.0  # Seconds to acquire lock (from best missile)
var lock_cone_degrees: float = 15.0  # Half-angle of lock cone

var _targeting: TargetingSystem = null
var _ship: Node3D = null
var _has_missile_weapon: bool = false
var _degrade_rate: float = 0.5  # Lock progress loss per second when out of cone


func _ready() -> void:
	_ship = get_parent()
	set_process(false)
	# Defer setup to let sibling nodes initialize
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	_targeting = _ship.get_node_or_null("TargetingSystem") as TargetingSystem
	if _targeting:
		_targeting.target_changed.connect(_on_target_changed)
		_targeting.target_lost.connect(_on_target_lost)
	_update_lock_config()
	set_process(_has_missile_weapon)


func _process(delta: float) -> void:
	if not _has_missile_weapon or _targeting == null:
		return

	var target: Node3D = _targeting.current_target
	if target == null or not is_instance_valid(target):
		_degrade_lock(delta)
		return

	# Check if target is within lock cone
	var ship_fwd: Vector3 = (-_ship.global_transform.basis.z).normalized()
	var target_pos: Vector3 = TargetingSystem.get_ship_center(target)
	var to_target: Vector3 = (target_pos - _ship.global_position).normalized()
	var angle_deg: float = rad_to_deg(ship_fwd.angle_to(to_target))

	if angle_deg <= lock_cone_degrees:
		# In cone — accumulate lock
		if lock_time > 0.01:
			lock_progress += delta / lock_time
		else:
			lock_progress = 1.0  # Instant lock (dumbfire shouldn't use this path)

		if lock_progress >= 1.0:
			lock_progress = 1.0
			if not is_locked:
				is_locked = true
				lock_acquired.emit()
		lock_progress_changed.emit(lock_progress)
	else:
		# Out of cone — degrade slowly
		_degrade_lock(delta)


func _degrade_lock(delta: float) -> void:
	if lock_progress <= 0.0:
		return
	var _was_locked: bool = is_locked
	lock_progress = maxf(lock_progress - _degrade_rate * delta, 0.0)
	if lock_progress < 1.0 and is_locked:
		is_locked = false
		lock_lost.emit()
	lock_progress_changed.emit(lock_progress)


func _on_target_changed(_new_target: Node3D) -> void:
	# Reset lock on target change
	lock_progress = 0.0
	is_locked = false
	lock_progress_changed.emit(0.0)


func _on_target_lost() -> void:
	if is_locked:
		lock_lost.emit()
	lock_progress = 0.0
	is_locked = false
	lock_progress_changed.emit(0.0)


func _update_lock_config() -> void:
	_has_missile_weapon = false
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm == null:
		return

	var best_lock_time: float = 999.0
	var best_cone: float = 15.0

	for hp in wm.hardpoints:
		if hp.mounted_weapon == null:
			continue
		if hp.mounted_weapon.weapon_type != WeaponResource.WeaponType.MISSILE:
			continue
		# Read lock config from loaded missile (new system)
		if hp.loaded_missile != &"":
			var missile_res := MissileRegistry.get_missile(hp.loaded_missile)
			if missile_res == null:
				continue
			if missile_res.missile_category == MissileResource.MissileCategory.DUMBFIRE:
				continue  # Dumbfire doesn't need lock
			_has_missile_weapon = true
			if missile_res.lock_time < best_lock_time:
				best_lock_time = missile_res.lock_time
				best_cone = missile_res.lock_cone_degrees
		else:
			# Fallback: legacy missile weapons (backward compat)
			if hp.mounted_weapon.missile_category == WeaponResource.MissileCategory.DUMBFIRE:
				continue
			_has_missile_weapon = true
			if hp.mounted_weapon.lock_time < best_lock_time:
				best_lock_time = hp.mounted_weapon.lock_time
				best_cone = hp.mounted_weapon.lock_cone_degrees

	if _has_missile_weapon:
		lock_time = best_lock_time
		lock_cone_degrees = best_cone

	set_process(_has_missile_weapon)


func notify_weapons_changed() -> void:
	_update_lock_config()
	# Reset lock when loadout changes
	lock_progress = 0.0
	is_locked = false
	lock_progress_changed.emit(0.0)
