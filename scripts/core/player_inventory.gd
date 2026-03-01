class_name PlayerInventory
extends RefCounted

# =============================================================================
# Player Inventory - Tracks owned weapons, shields, engines, and modules.
# Items that are currently equipped are NOT in the inventory.
# =============================================================================

signal inventory_changed

var _weapons: Dictionary = {}   # StringName -> int (count)
var _shields: Dictionary = {}   # StringName -> int (count)
var _engines: Dictionary = {}   # StringName -> int (count)
var _modules: Dictionary = {}   # StringName -> int (count)
var _ammo: Dictionary = {}      # StringName -> int (count) — missile ammo

const _SIZE_ORDER := {"S": 0, "M": 1, "L": 2}

# =============================================================================
# WEAPONS
# =============================================================================
func add_weapon(weapon_name: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	_weapons[weapon_name] = _weapons.get(weapon_name, 0) + count
	inventory_changed.emit()


func remove_weapon(weapon_name: StringName, count: int = 1) -> bool:
	var current: int = _weapons.get(weapon_name, 0)
	if current < count:
		return false
	current -= count
	if current <= 0:
		_weapons.erase(weapon_name)
	else:
		_weapons[weapon_name] = current
	inventory_changed.emit()
	return true


func get_weapon_count(weapon_name: StringName) -> int:
	return _weapons.get(weapon_name, 0)


func get_all_weapons() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _weapons:
		result.append(key)
	result.sort()
	return result


func has_weapon(weapon_name: StringName) -> bool:
	return _weapons.get(weapon_name, 0) > 0


func get_weapons_for_slot(slot_size: String, is_turret: bool = false) -> Array[StringName]:
	var slot_val: int = _SIZE_ORDER.get(slot_size, 0)
	var compatible: Array[StringName] = []
	var incompatible: Array[StringName] = []

	for weapon_name in _weapons:
		var weapon := WeaponRegistry.get_weapon(weapon_name)
		if weapon == null:
			continue
		if _is_weapon_slot_compatible(weapon, slot_val, is_turret):
			compatible.append(weapon_name)
		else:
			incompatible.append(weapon_name)

	compatible.sort()
	incompatible.sort()
	var result: Array[StringName] = []
	result.append_array(compatible)
	result.append_array(incompatible)
	return result


func is_compatible(weapon_name: StringName, slot_size: String, is_turret: bool = false) -> bool:
	var weapon := WeaponRegistry.get_weapon(weapon_name)
	if weapon == null:
		return false
	var slot_val: int = _SIZE_ORDER.get(slot_size, 0)
	return _is_weapon_slot_compatible(weapon, slot_val, is_turret)


func _is_weapon_slot_compatible(weapon: WeaponResource, slot_val: int, is_turret: bool) -> bool:
	var weapon_size_str: String = ["S", "M", "L"][weapon.slot_size]
	var weapon_val: int = _SIZE_ORDER.get(weapon_size_str, 0)
	if weapon_val > slot_val:
		return false
	# TURRET weapons can only mount on turret slots
	if weapon.weapon_type == WeaponResource.WeaponType.TURRET and not is_turret:
		return false
	return true


# =============================================================================
# SHIELDS
# =============================================================================
func add_shield(shield_name: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	_shields[shield_name] = _shields.get(shield_name, 0) + count
	inventory_changed.emit()


func remove_shield(shield_name: StringName, count: int = 1) -> bool:
	var current: int = _shields.get(shield_name, 0)
	if current < count:
		return false
	current -= count
	if current <= 0:
		_shields.erase(shield_name)
	else:
		_shields[shield_name] = current
	inventory_changed.emit()
	return true


func get_shield_count(shield_name: StringName) -> int:
	return _shields.get(shield_name, 0)


func get_all_shields() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _shields:
		result.append(key)
	result.sort()
	return result


func has_shield(shield_name: StringName) -> bool:
	return _shields.get(shield_name, 0) > 0


func get_shields_for_slot(slot_size: String) -> Array[StringName]:
	var slot_val: int = _SIZE_ORDER.get(slot_size, 0)
	var compatible: Array[StringName] = []
	var incompatible: Array[StringName] = []
	for sn in _shields:
		var shield := ShieldRegistry.get_shield(sn)
		if shield == null:
			continue
		var size_str: String = ["S", "M", "L"][shield.slot_size]
		if _SIZE_ORDER.get(size_str, 0) <= slot_val:
			compatible.append(sn)
		else:
			incompatible.append(sn)
	compatible.sort()
	incompatible.sort()
	var result: Array[StringName] = []
	result.append_array(compatible)
	result.append_array(incompatible)
	return result


func is_shield_compatible(shield_name: StringName, slot_size: String) -> bool:
	var shield := ShieldRegistry.get_shield(shield_name)
	if shield == null:
		return false
	var size_str: String = ["S", "M", "L"][shield.slot_size]
	return _SIZE_ORDER.get(size_str, 0) <= _SIZE_ORDER.get(slot_size, 0)


# =============================================================================
# ENGINES
# =============================================================================
func add_engine(engine_name: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	_engines[engine_name] = _engines.get(engine_name, 0) + count
	inventory_changed.emit()


func remove_engine(engine_name: StringName, count: int = 1) -> bool:
	var current: int = _engines.get(engine_name, 0)
	if current < count:
		return false
	current -= count
	if current <= 0:
		_engines.erase(engine_name)
	else:
		_engines[engine_name] = current
	inventory_changed.emit()
	return true


func get_engine_count(engine_name: StringName) -> int:
	return _engines.get(engine_name, 0)


func get_all_engines() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _engines:
		result.append(key)
	result.sort()
	return result


func has_engine(engine_name: StringName) -> bool:
	return _engines.get(engine_name, 0) > 0


func get_engines_for_slot(slot_size: String) -> Array[StringName]:
	var slot_val: int = _SIZE_ORDER.get(slot_size, 0)
	var compatible: Array[StringName] = []
	var incompatible: Array[StringName] = []
	for en in _engines:
		var engine := EngineRegistry.get_engine(en)
		if engine == null:
			continue
		var size_str: String = ["S", "M", "L"][engine.slot_size]
		if _SIZE_ORDER.get(size_str, 0) <= slot_val:
			compatible.append(en)
		else:
			incompatible.append(en)
	compatible.sort()
	incompatible.sort()
	var result: Array[StringName] = []
	result.append_array(compatible)
	result.append_array(incompatible)
	return result


func is_engine_compatible(engine_name: StringName, slot_size: String) -> bool:
	var engine := EngineRegistry.get_engine(engine_name)
	if engine == null:
		return false
	var size_str: String = ["S", "M", "L"][engine.slot_size]
	return _SIZE_ORDER.get(size_str, 0) <= _SIZE_ORDER.get(slot_size, 0)


# =============================================================================
# MODULES
# =============================================================================
func add_module(module_name: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	_modules[module_name] = _modules.get(module_name, 0) + count
	inventory_changed.emit()


func remove_module(module_name: StringName, count: int = 1) -> bool:
	var current: int = _modules.get(module_name, 0)
	if current < count:
		return false
	current -= count
	if current <= 0:
		_modules.erase(module_name)
	else:
		_modules[module_name] = current
	inventory_changed.emit()
	return true


func get_module_count(module_name: StringName) -> int:
	return _modules.get(module_name, 0)


func get_all_modules() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _modules:
		result.append(key)
	result.sort()
	return result


func has_module(module_name: StringName) -> bool:
	return _modules.get(module_name, 0) > 0


func get_modules_for_slot(slot_size: String) -> Array[StringName]:
	var slot_val: int = _SIZE_ORDER.get(slot_size, 0)
	var compatible: Array[StringName] = []
	var incompatible: Array[StringName] = []
	for mn in _modules:
		var module := ModuleRegistry.get_module(mn)
		if module == null:
			continue
		var size_str: String = ["S", "M", "L"][module.slot_size]
		if _SIZE_ORDER.get(size_str, 0) <= slot_val:
			compatible.append(mn)
		else:
			incompatible.append(mn)
	compatible.sort()
	incompatible.sort()
	var result: Array[StringName] = []
	result.append_array(compatible)
	result.append_array(incompatible)
	return result


func is_module_compatible(module_name: StringName, slot_size: String) -> bool:
	var module := ModuleRegistry.get_module(module_name)
	if module == null:
		return false
	var size_str: String = ["S", "M", "L"][module.slot_size]
	return _SIZE_ORDER.get(size_str, 0) <= _SIZE_ORDER.get(slot_size, 0)


# =============================================================================
# AMMO (missile munitions)
# =============================================================================
func add_ammo(missile_name: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	_ammo[missile_name] = _ammo.get(missile_name, 0) + count
	inventory_changed.emit()


func remove_ammo(missile_name: StringName, count: int = 1) -> bool:
	var current: int = _ammo.get(missile_name, 0)
	if current < count:
		return false
	current -= count
	if current <= 0:
		_ammo.erase(missile_name)
	else:
		_ammo[missile_name] = current
	inventory_changed.emit()
	return true


func get_ammo_count(missile_name: StringName) -> int:
	return _ammo.get(missile_name, 0)


func get_all_ammo() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _ammo:
		result.append(key)
	result.sort()
	return result


func has_ammo(missile_name: StringName) -> bool:
	return _ammo.get(missile_name, 0) > 0


func get_ammo_for_launcher_size(size: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for missile_name in _ammo:
		var missile := MissileRegistry.get_missile(missile_name)
		if missile and missile.missile_size == size:
			result.append(missile_name)
	result.sort()
	return result


# =============================================================================
# SERIALIZATION (for backend persistence)
# =============================================================================
func serialize() -> Array:
	var items: Array = []
	for name in _weapons:
		items.append({"category": "weapon", "item_name": str(name), "quantity": _weapons[name]})
	for name in _shields:
		items.append({"category": "shield", "item_name": str(name), "quantity": _shields[name]})
	for name in _engines:
		items.append({"category": "engine", "item_name": str(name), "quantity": _engines[name]})
	for name in _modules:
		items.append({"category": "module", "item_name": str(name), "quantity": _modules[name]})
	for name in _ammo:
		items.append({"category": "ammo", "item_name": str(name), "quantity": _ammo[name]})
	return items


func clear_all() -> void:
	_weapons.clear()
	_shields.clear()
	_engines.clear()
	_modules.clear()
	_ammo.clear()
	inventory_changed.emit()
