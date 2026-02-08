class_name HealthSystem
extends Node

# =============================================================================
# Health System - Hull + 4 directional shields + subsystems
# =============================================================================

enum ShieldFacing { FRONT, REAR, LEFT, RIGHT }
enum Subsystem { ENGINES, WEAPONS, SHIELDS }

signal hull_changed(current: float, max_hp: float)
signal damage_taken(attacker: Node3D)
signal shield_changed(facing: int, current: float, max_per_facing: float)
signal shield_facing_depleted(facing: int)
signal subsystem_damaged(subsystem: int)
signal ship_destroyed()

# --- Hull ---
var hull_current: float = 1000.0
var hull_max: float = 1000.0
var armor_rating: float = 5.0

# --- Shields (per facing) ---
var shield_max_per_facing: float = 125.0
var shield_current: Array[float] = [125.0, 125.0, 125.0, 125.0]  # F, R, L, R
var shield_regen_rate: float = 15.0
var shield_regen_delay: float = 4.0
var shield_bleedthrough: float = 0.1
var _shield_regen_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]

# --- Subsystems ---
var subsystem_health: Array[float] = [1.0, 1.0, 1.0]  # 0-1 ratio
const SUBSYSTEM_DAMAGE_CHANCE: float = 0.1
const SUBSYSTEM_DAMAGE_AMOUNT: float = 0.15

var _is_dead: bool = false
var _cached_energy_sys: EnergySystem = null
var _energy_sys_checked: bool = false


func setup(ship_data: ShipData) -> void:
	hull_max = ship_data.hull_hp
	hull_current = hull_max
	armor_rating = ship_data.armor_rating
	shield_max_per_facing = ship_data.shield_hp / 4.0
	shield_regen_rate = ship_data.shield_regen_rate
	shield_regen_delay = ship_data.shield_regen_delay
	shield_bleedthrough = ship_data.shield_damage_bleedthrough
	for i in 4:
		shield_current[i] = shield_max_per_facing
		_shield_regen_timers[i] = 0.0
	subsystem_health = [1.0, 1.0, 1.0]
	_is_dead = false


func _process(delta: float) -> void:
	if _is_dead:
		return
	_regen_shields(delta)


func _regen_shields(delta: float) -> void:
	for i in 4:
		if shield_current[i] >= shield_max_per_facing:
			continue
		_shield_regen_timers[i] -= delta
		if _shield_regen_timers[i] > 0.0:
			continue
		# Shield regen multiplied by parent's energy system if available
		var regen_mult := 1.0
		var energy_sys := _get_energy_system()
		if energy_sys:
			regen_mult = energy_sys.get_shield_multiplier()
		shield_current[i] = minf(shield_current[i] + shield_regen_rate * regen_mult * delta, shield_max_per_facing)
		shield_changed.emit(i, shield_current[i], shield_max_per_facing)


func apply_damage(amount: float, damage_type: StringName, hit_direction: Vector3, attacker: Node3D = null) -> Dictionary:
	if _is_dead:
		return {"shield_absorbed": false, "facing": 0, "shield_ratio": 0.0}

	if attacker:
		damage_taken.emit(attacker)

	var facing := _direction_to_facing(hit_direction)
	var shield_absorbed := false

	# Shield absorption
	var shield_damage := amount
	var hull_damage := 0.0

	if shield_current[facing] > 0.0:
		shield_absorbed = true
		# Bleedthrough goes directly to hull
		hull_damage += amount * shield_bleedthrough
		shield_damage = amount * (1.0 - shield_bleedthrough)

		shield_current[facing] -= shield_damage
		_shield_regen_timers[facing] = shield_regen_delay

		if shield_current[facing] <= 0.0:
			# Overflow to hull
			hull_damage += absf(shield_current[facing])
			shield_current[facing] = 0.0
			shield_facing_depleted.emit(facing)

		shield_changed.emit(facing, shield_current[facing], shield_max_per_facing)
	else:
		hull_damage = amount

	# Apply armor to hull damage
	hull_damage = maxf(hull_damage - armor_rating, 1.0)

	# Damage type modifiers
	match damage_type:
		&"em":
			hull_damage *= 0.5  # EM does less hull damage but more shield damage
		&"explosive":
			hull_damage *= 1.2  # Explosive does more hull damage

	hull_current = maxf(hull_current - hull_damage, 0.0)
	hull_changed.emit(hull_current, hull_max)

	# Subsystem damage chance on hull hits
	if shield_current[facing] <= 0.0 and randf() < SUBSYSTEM_DAMAGE_CHANCE:
		var sub: int = randi_range(0, 2)
		subsystem_health[sub] = maxf(subsystem_health[sub] - SUBSYSTEM_DAMAGE_AMOUNT, 0.0)
		subsystem_damaged.emit(sub)

	if hull_current <= 0.0:
		_is_dead = true
		ship_destroyed.emit()

	return {"shield_absorbed": shield_absorbed, "facing": facing, "shield_ratio": get_shield_ratio(facing)}


func _direction_to_facing(hit_dir: Vector3) -> int:
	# hit_dir is in local space of the ship being hit
	# Determine which shield quadrant was hit
	var ship_node := get_parent() as Node3D
	if ship_node == null:
		return ShieldFacing.FRONT

	var local_dir: Vector3 = ship_node.global_transform.basis.inverse() * hit_dir.normalized()

	# Forward is -Z, Right is +X
	if absf(local_dir.z) >= absf(local_dir.x):
		return ShieldFacing.FRONT if local_dir.z < 0.0 else ShieldFacing.REAR
	else:
		return ShieldFacing.RIGHT if local_dir.x > 0.0 else ShieldFacing.LEFT


func get_hull_ratio() -> float:
	return hull_current / hull_max if hull_max > 0.0 else 0.0


func get_shield_ratio(facing: int) -> float:
	return shield_current[facing] / shield_max_per_facing if shield_max_per_facing > 0.0 else 0.0


func get_total_shield_ratio() -> float:
	var total := 0.0
	for i in 4:
		total += shield_current[i]
	return total / (shield_max_per_facing * 4.0) if shield_max_per_facing > 0.0 else 0.0


func revive() -> void:
	_is_dead = false
	hull_current = hull_max
	for i in 4:
		shield_current[i] = shield_max_per_facing
		_shield_regen_timers[i] = 0.0
	subsystem_health = [1.0, 1.0, 1.0]
	hull_changed.emit(hull_current, hull_max)
	for i in 4:
		shield_changed.emit(i, shield_current[i], shield_max_per_facing)


func is_dead() -> bool:
	return _is_dead


func _get_energy_system() -> EnergySystem:
	if not _energy_sys_checked:
		_energy_sys_checked = true
		var parent := get_parent()
		if parent:
			_cached_energy_sys = parent.get_node_or_null("EnergySystem") as EnergySystem
	return _cached_energy_sys
