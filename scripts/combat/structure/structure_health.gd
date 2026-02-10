class_name StructureHealth
extends Node

# =============================================================================
# Structure Health — Global shield + hull for stations and large structures.
# Unlike ships (4 directional shields), structures use a single shield pool.
# =============================================================================

signal hull_changed(current: float, max_hp: float)
signal shield_changed(current: float, max_shield: float)
signal damage_taken(attacker: Node3D, amount: float)
signal structure_destroyed()

# --- Hull ---
var hull_current: float = 10000.0
var hull_max: float = 10000.0
var armor_rating: float = 15.0

# --- Shield (single pool) ---
var shield_current: float = 5000.0
var shield_max: float = 5000.0
var shield_regen_rate: float = 20.0
var shield_regen_delay: float = 5.0
var shield_bleedthrough: float = 0.05
var _shield_regen_timer: float = 0.0

var _is_dead: bool = false


func _process(delta: float) -> void:
	if _is_dead:
		return
	_regen_shield(delta)


func _regen_shield(delta: float) -> void:
	if shield_current >= shield_max:
		return
	_shield_regen_timer -= delta
	if _shield_regen_timer > 0.0:
		return
	shield_current = minf(shield_current + shield_regen_rate * delta, shield_max)
	shield_changed.emit(shield_current, shield_max)


func apply_damage(amount: float, _damage_type: StringName, _hit_direction: Vector3, attacker: Node3D = null) -> Dictionary:
	if _is_dead:
		return {"shield_absorbed": false, "shield_ratio": 0.0}

	if attacker:
		damage_taken.emit(attacker, amount)

	var shield_absorbed := false
	var hull_damage := 0.0

	if shield_current > 0.0:
		shield_absorbed = true
		hull_damage += amount * shield_bleedthrough
		var shield_damage: float = amount * (1.0 - shield_bleedthrough)

		shield_current -= shield_damage
		_shield_regen_timer = shield_regen_delay

		if shield_current <= 0.0:
			hull_damage += absf(shield_current)
			shield_current = 0.0

		shield_changed.emit(shield_current, shield_max)
	else:
		hull_damage = amount

	# Apply armor
	hull_damage = maxf(hull_damage - armor_rating, 1.0)
	hull_current = maxf(hull_current - hull_damage, 0.0)
	hull_changed.emit(hull_current, hull_max)

	if hull_current <= 0.0:
		_is_dead = true
		structure_destroyed.emit()

	return {"shield_absorbed": shield_absorbed, "shield_ratio": get_shield_ratio()}


func is_dead() -> bool:
	return _is_dead


func get_hull_ratio() -> float:
	return hull_current / hull_max if hull_max > 0.0 else 0.0


func get_shield_ratio() -> float:
	return shield_current / shield_max if shield_max > 0.0 else 0.0


func get_total_shield_ratio() -> float:
	return get_shield_ratio()


func revive() -> void:
	_is_dead = false
	hull_current = hull_max
	shield_current = shield_max
	_shield_regen_timer = 0.0
	hull_changed.emit(hull_current, hull_max)
	shield_changed.emit(shield_current, shield_max)


## Configure from station type preset
func apply_preset(station_type: int) -> void:
	var p: Dictionary = get_preset(station_type)
	hull_max = p["hull"]
	hull_current = hull_max
	shield_max = p["shield"]
	shield_current = shield_max
	armor_rating = p["armor"]
	shield_regen_rate = p["regen"]


static func get_preset(station_type: int) -> Dictionary:
	match station_type:
		0:  # REPAIR
			return {"hull": 15000.0, "shield": 8000.0, "armor": 20.0, "regen": 25.0}
		1:  # TRADE
			return {"hull": 8000.0, "shield": 5000.0, "armor": 10.0, "regen": 15.0}
		2:  # MILITARY
			return {"hull": 25000.0, "shield": 15000.0, "armor": 30.0, "regen": 40.0}
		3:  # MINING
			return {"hull": 6000.0, "shield": 3000.0, "armor": 8.0, "regen": 10.0}
	return {"hull": 10000.0, "shield": 5000.0, "armor": 15.0, "regen": 20.0}
