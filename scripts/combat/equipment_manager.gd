class_name EquipmentManager
extends Node

# =============================================================================
# Equipment Manager - Manages shield, engine, and module equipment on a ship.
# Child of ShipController, applies stats to HealthSystem/EnergySystem/ShipController.
# =============================================================================

signal shield_equipped(shield: ShieldResource)
signal engine_equipped(engine: EngineResource)
signal module_equipped(slot_index: int, module: ModuleResource)
signal equipment_changed

var ship_data: ShipData = null
var equipped_shield: ShieldResource = null
var equipped_engine: EngineResource = null
var equipped_modules: Array = []  # Array of ModuleResource|null

# Cached refs (from parent ShipController)
var _health_sys: HealthSystem = null
var _energy_sys: EnergySystem = null
var _ship_controller: ShipController = null


func setup(data: ShipData) -> void:
	ship_data = data
	equipped_modules.resize(data.module_slots.size())
	for i in equipped_modules.size():
		equipped_modules[i] = null
	_cache_refs.call_deferred()


func _cache_refs() -> void:
	var parent := get_parent()
	_ship_controller = parent as ShipController
	_health_sys = parent.get_node_or_null("HealthSystem") as HealthSystem
	_energy_sys = parent.get_node_or_null("EnergySystem") as EnergySystem


func equip_shield(shield: ShieldResource) -> ShieldResource:
	var old := equipped_shield
	equipped_shield = shield
	_apply_all_stats()
	shield_equipped.emit(shield)
	equipment_changed.emit()
	return old


func remove_shield() -> ShieldResource:
	var old := equipped_shield
	equipped_shield = null
	_apply_all_stats()
	equipment_changed.emit()
	return old


func equip_engine(engine: EngineResource) -> EngineResource:
	var old := equipped_engine
	equipped_engine = engine
	_apply_all_stats()
	engine_equipped.emit(engine)
	equipment_changed.emit()
	return old


func remove_engine() -> EngineResource:
	var old := equipped_engine
	equipped_engine = null
	_apply_all_stats()
	equipment_changed.emit()
	return old


func equip_module(slot_idx: int, module: ModuleResource) -> ModuleResource:
	if slot_idx < 0 or slot_idx >= equipped_modules.size():
		return null
	var old: ModuleResource = equipped_modules[slot_idx]
	equipped_modules[slot_idx] = module
	_apply_all_stats()
	module_equipped.emit(slot_idx, module)
	equipment_changed.emit()
	return old


func remove_module(slot_idx: int) -> ModuleResource:
	if slot_idx < 0 or slot_idx >= equipped_modules.size():
		return null
	var old: ModuleResource = equipped_modules[slot_idx]
	equipped_modules[slot_idx] = null
	_apply_all_stats()
	equipment_changed.emit()
	return old


func get_module_slot_size(idx: int) -> String:
	if ship_data and idx >= 0 and idx < ship_data.module_slots.size():
		return ship_data.module_slots[idx]
	return "S"


# =============================================================================
# STAT APPLICATION
# =============================================================================
func _apply_all_stats() -> void:
	_apply_module_stats()
	_apply_shield_stats()
	_apply_engine_stats()


func _apply_shield_stats() -> void:
	if _health_sys == null or ship_data == null:
		return

	# Gather module multipliers
	var cap_mult := 1.0
	var regen_mult := 1.0
	for mod in equipped_modules:
		if mod is ModuleResource:
			cap_mult *= mod.shield_cap_mult
			regen_mult *= mod.shield_regen_mult

	if equipped_shield:
		_health_sys.shield_max_per_facing = equipped_shield.shield_hp_per_facing * cap_mult
		_health_sys.shield_regen_rate = equipped_shield.regen_rate * regen_mult
		_health_sys.shield_regen_delay = equipped_shield.regen_delay
		_health_sys.shield_bleedthrough = equipped_shield.bleedthrough
	else:
		# Fallback to base ShipData stats
		_health_sys.shield_max_per_facing = (ship_data.shield_hp / 4.0) * cap_mult
		_health_sys.shield_regen_rate = ship_data.shield_regen_rate * regen_mult
		_health_sys.shield_regen_delay = ship_data.shield_regen_delay
		_health_sys.shield_bleedthrough = ship_data.shield_damage_bleedthrough

	# Clamp current shields to new max
	for i in 4:
		_health_sys.shield_current[i] = minf(_health_sys.shield_current[i], _health_sys.shield_max_per_facing)
		_health_sys.shield_changed.emit(i, _health_sys.shield_current[i], _health_sys.shield_max_per_facing)


func _apply_engine_stats() -> void:
	if _ship_controller == null:
		return

	if equipped_engine:
		_ship_controller.engine_accel_mult = equipped_engine.accel_mult
		_ship_controller.engine_speed_mult = equipped_engine.speed_mult
		_ship_controller.engine_rotation_mult = equipped_engine.rotation_mult
		_ship_controller.engine_cruise_mult = equipped_engine.cruise_mult
		_ship_controller.engine_boost_drain_mult = equipped_engine.boost_drain_mult
	else:
		_ship_controller.engine_accel_mult = 1.0
		_ship_controller.engine_speed_mult = 1.0
		_ship_controller.engine_rotation_mult = 1.0
		_ship_controller.engine_cruise_mult = 1.0
		_ship_controller.engine_boost_drain_mult = 1.0


func _apply_module_stats() -> void:
	if ship_data == null:
		return

	# Accumulate additive bonuses from all modules
	var hull_bonus := 0.0
	var armor_bonus := 0.0
	var energy_cap_bonus := 0.0
	var energy_regen_bonus := 0.0

	for mod in equipped_modules:
		if mod is ModuleResource:
			hull_bonus += mod.hull_bonus
			armor_bonus += mod.armor_bonus
			energy_cap_bonus += mod.energy_cap_bonus
			energy_regen_bonus += mod.energy_regen_bonus

	# Apply to HealthSystem
	if _health_sys:
		_health_sys.hull_max = ship_data.hull_hp + hull_bonus
		_health_sys.hull_current = minf(_health_sys.hull_current, _health_sys.hull_max)
		_health_sys.armor_rating = ship_data.armor_rating + armor_bonus
		_health_sys.hull_changed.emit(_health_sys.hull_current, _health_sys.hull_max)

	# Apply to EnergySystem
	if _energy_sys:
		_energy_sys.energy_max = ship_data.energy_capacity + energy_cap_bonus
		_energy_sys.energy_current = minf(_energy_sys.energy_current, _energy_sys.energy_max)
		_energy_sys.energy_regen_base = ship_data.energy_regen_rate + energy_regen_bonus
		_energy_sys.energy_changed.emit(_energy_sys.energy_current, _energy_sys.energy_max)
