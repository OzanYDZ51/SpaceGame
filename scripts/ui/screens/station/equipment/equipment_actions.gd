class_name EquipmentActions
extends RefCounted

# =============================================================================
# Equipment Screen — Business Logic (Equip / Remove / Button States)
# =============================================================================


var _adapter: RefCounted = null
var _inventory = null


static func create(adapter: RefCounted, inventory):
	var a =EquipmentActions.new()
	a._adapter = adapter
	a._inventory = inventory
	return a


# =============================================================================
# EQUIP
# =============================================================================
func equip_weapon(hardpoint: int, weapon_name: StringName) -> void:
	if hardpoint < 0 or weapon_name == &"" or _adapter == null:
		return
	_adapter.equip_weapon(hardpoint, weapon_name)


func equip_shield(shield_name: StringName) -> void:
	if shield_name == &"" or _adapter == null:
		return
	_adapter.equip_shield(shield_name)


func equip_engine(engine_name: StringName) -> void:
	if engine_name == &"" or _adapter == null:
		return
	_adapter.equip_engine(engine_name)


func equip_module(slot: int, module_name: StringName) -> void:
	if slot < 0 or module_name == &"" or _adapter == null:
		return
	_adapter.equip_module(slot, module_name)


func load_missile(hardpoint: int, missile_name: StringName) -> void:
	if hardpoint < 0 or missile_name == &"" or _adapter == null:
		return
	_adapter.load_missile(hardpoint, missile_name)


func unload_missile(hardpoint: int) -> void:
	if hardpoint < 0 or _adapter == null:
		return
	_adapter.unload_missile(hardpoint)


# =============================================================================
# REMOVE
# =============================================================================
func remove_weapon(hardpoint: int) -> void:
	if hardpoint < 0 or _adapter == null:
		return
	_adapter.remove_weapon(hardpoint)


func remove_shield() -> void:
	if _adapter == null:
		return
	_adapter.remove_shield()


func remove_engine() -> void:
	if _adapter == null:
		return
	_adapter.remove_engine()


func remove_module(slot: int) -> void:
	if slot < 0 or _adapter == null:
		return
	_adapter.remove_module(slot)


# =============================================================================
# BUTTON STATE QUERIES
# =============================================================================
func get_equip_enabled(tab: int, selected_weapon: StringName, selected_shield: StringName,
		selected_engine: StringName, selected_module: StringName,
		selected_hardpoint: int, selected_module_slot: int) -> bool:
	if _adapter == null or _inventory == null:
		return false
	match tab:
		0:
			if selected_hardpoint >= 0 and selected_weapon != &"":
				var mounted = _adapter.get_mounted_weapon(selected_hardpoint)
				if mounted and mounted.weapon_type == WeaponResource.WeaponType.MISSILE:
					return _inventory.has_ammo(selected_weapon)
				var hp_sz: String = _adapter.get_hardpoint_slot_size(selected_hardpoint)
				var hp_turret: bool = _adapter.is_hardpoint_turret(selected_hardpoint)
				return _inventory.is_compatible(selected_weapon, hp_sz, hp_turret) and _inventory.has_weapon(selected_weapon)
		1:
			if selected_module_slot >= 0 and selected_module != &"":
				var slot_sz: String = _adapter.get_module_slot_size(selected_module_slot)
				return _inventory.is_module_compatible(selected_module, slot_sz) and _inventory.has_module(selected_module)
		2:
			if selected_shield != &"":
				return _inventory.is_shield_compatible(selected_shield, _adapter.get_shield_slot_size()) and _inventory.has_shield(selected_shield)
		3:
			if selected_engine != &"":
				return _inventory.is_engine_compatible(selected_engine, _adapter.get_engine_slot_size()) and _inventory.has_engine(selected_engine)
	return false


func get_remove_enabled(tab: int, selected_hardpoint: int, selected_module_slot: int) -> bool:
	if _adapter == null:
		return false
	match tab:
		0:
			if selected_hardpoint >= 0:
				var mounted = _adapter.get_mounted_weapon(selected_hardpoint)
				if mounted and mounted.weapon_type == WeaponResource.WeaponType.MISSILE:
					return _adapter.get_loaded_missile_name(selected_hardpoint) != &""
				return mounted != null
		1:
			if selected_module_slot >= 0:
				return _adapter.get_equipped_module(selected_module_slot) != null
		2:
			return _adapter.get_equipped_shield() != null
		3:
			return _adapter.get_equipped_engine() != null
	return false


# =============================================================================
# STOCK COUNT
# =============================================================================
func get_current_stock_count(tab: int) -> int:
	if _inventory == null:
		return 0
	var total =0
	match tab:
		0:
			for wn in _inventory.get_all_weapons():
				total += _inventory.get_weapon_count(wn)
		1:
			for mn in _inventory.get_all_modules():
				total += _inventory.get_module_count(mn)
		2:
			for sn in _inventory.get_all_shields():
				total += _inventory.get_shield_count(sn)
		3:
			for en in _inventory.get_all_engines():
				total += _inventory.get_engine_count(en)
	return total
