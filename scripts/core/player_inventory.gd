class_name PlayerInventory
extends RefCounted

# =============================================================================
# Player Inventory - Tracks owned weapons by name and count
# Weapons that are mounted on hardpoints are NOT in the inventory.
# =============================================================================

signal inventory_changed

var _weapons: Dictionary = {}  # StringName -> int (count)


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


func get_weapons_for_slot(slot_size: String) -> Array[StringName]:
	var size_order := {"S": 0, "M": 1, "L": 2}
	var slot_val: int = size_order.get(slot_size, 0)
	var compatible: Array[StringName] = []
	var incompatible: Array[StringName] = []

	for weapon_name in _weapons:
		var weapon := WeaponRegistry.get_weapon(weapon_name)
		if weapon == null:
			continue
		var weapon_size_str: String = ["S", "M", "L"][weapon.slot_size]
		var weapon_val: int = size_order.get(weapon_size_str, 0)
		if weapon_val <= slot_val:
			compatible.append(weapon_name)
		else:
			incompatible.append(weapon_name)

	compatible.sort()
	incompatible.sort()
	var result: Array[StringName] = []
	result.append_array(compatible)
	result.append_array(incompatible)
	return result


func is_compatible(weapon_name: StringName, slot_size: String) -> bool:
	var weapon := WeaponRegistry.get_weapon(weapon_name)
	if weapon == null:
		return false
	var size_order := {"S": 0, "M": 1, "L": 2}
	var weapon_size_str: String = ["S", "M", "L"][weapon.slot_size]
	return size_order.get(weapon_size_str, 0) <= size_order.get(slot_size, 0)
