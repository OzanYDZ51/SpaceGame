class_name StationEquipAdapter
extends RefCounted

# =============================================================================
# Station Equip Adapter — FleetShipEquipAdapter-compatible interface for stations.
# Always DATA mode (station is not the player's active ship).
# =============================================================================

signal loadout_changed

var station_equipment = null
var player_inventory = null

# Cached configs for hardpoint queries
var _hp_configs: Array[Dictionary] = []


static func create(equipment, inv):
	var a =StationEquipAdapter.new()
	a.station_equipment = equipment
	a.player_inventory = inv
	a._hp_configs = StationHardpointConfig.get_configs(equipment.station_type)
	return a


# =============================================================================
# QUERIES — Weapons / Hardpoints
# =============================================================================
func get_hardpoint_count() -> int:
	return _hp_configs.size()


func get_hardpoint_slot_size(idx: int) -> String:
	if idx >= 0 and idx < _hp_configs.size():
		return _hp_configs[idx].get("size", "S")
	return "S"


func is_hardpoint_turret(idx: int) -> bool:
	if idx >= 0 and idx < _hp_configs.size():
		return _hp_configs[idx].get("is_turret", false)
	return false


func get_mounted_weapon_name(idx: int) -> StringName:
	if station_equipment and idx >= 0 and idx < station_equipment.weapons.size():
		return station_equipment.weapons[idx]
	return &""


func get_mounted_weapon(idx: int) -> WeaponResource:
	var wn =get_mounted_weapon_name(idx)
	if wn == &"":
		return null
	return WeaponRegistry.get_weapon(wn)


# =============================================================================
# QUERIES — Shield
# =============================================================================
func get_equipped_shield_name() -> StringName:
	return station_equipment.shield_name if station_equipment else &""


func get_equipped_shield() -> ShieldResource:
	var sn =get_equipped_shield_name()
	if sn == &"":
		return null
	return ShieldRegistry.get_shield(sn)


func get_shield_slot_size() -> String:
	return station_equipment.shield_slot_size if station_equipment else "S"


# =============================================================================
# QUERIES — Engine (stations don't have engines)
# =============================================================================
func get_equipped_engine_name() -> StringName:
	return &""


func get_equipped_engine() -> EngineResource:
	return null


func get_engine_slot_size() -> String:
	return ""


# =============================================================================
# QUERIES — Modules
# =============================================================================
func get_module_slot_count() -> int:
	return station_equipment.module_slots.size() if station_equipment else 0


func get_module_slot_size(idx: int) -> String:
	if station_equipment and idx >= 0 and idx < station_equipment.module_slots.size():
		return station_equipment.module_slots[idx]
	return "S"


func get_equipped_module_name(idx: int) -> StringName:
	if station_equipment and idx >= 0 and idx < station_equipment.modules.size():
		return station_equipment.modules[idx]
	return &""


func get_equipped_module(idx: int) -> ModuleResource:
	var mn =get_equipped_module_name(idx)
	if mn == &"":
		return null
	return ModuleRegistry.get_module(mn)


# =============================================================================
# QUERIES — Ship Data (N/A for stations)
# =============================================================================
func get_ship_data() -> ShipData:
	return null


# =============================================================================
# MUTATIONS — Weapons
# =============================================================================
func equip_weapon(idx: int, weapon_name: StringName) -> void:
	if player_inventory == null or station_equipment == null:
		return
	if not player_inventory.has_weapon(weapon_name):
		return
	if idx < 0 or idx >= station_equipment.weapons.size():
		return
	# Slot compatibility check
	var slot_size =get_hardpoint_slot_size(idx)
	var is_turret =is_hardpoint_turret(idx)
	if not player_inventory.is_compatible(weapon_name, slot_size, is_turret):
		return
	player_inventory.remove_weapon(weapon_name)
	var old = station_equipment.weapons[idx]
	if old != &"":
		player_inventory.add_weapon(old)
	station_equipment.weapons[idx] = weapon_name
	loadout_changed.emit()


func remove_weapon(idx: int) -> void:
	if player_inventory == null or station_equipment == null:
		return
	if idx < 0 or idx >= station_equipment.weapons.size():
		return
	var old = station_equipment.weapons[idx]
	if old != &"":
		player_inventory.add_weapon(old)
		station_equipment.weapons[idx] = &""
	loadout_changed.emit()


# =============================================================================
# MUTATIONS — Shield
# =============================================================================
func equip_shield(shield_name: StringName) -> void:
	if player_inventory == null or station_equipment == null:
		return
	if not player_inventory.has_shield(shield_name):
		return
	if not player_inventory.is_shield_compatible(shield_name, station_equipment.shield_slot_size):
		return
	player_inventory.remove_shield(shield_name)
	if station_equipment.shield_name != &"":
		player_inventory.add_shield(station_equipment.shield_name)
	station_equipment.shield_name = shield_name
	loadout_changed.emit()


func remove_shield() -> void:
	if player_inventory == null or station_equipment == null:
		return
	if station_equipment.shield_name != &"":
		player_inventory.add_shield(station_equipment.shield_name)
		station_equipment.shield_name = &""
	loadout_changed.emit()


# =============================================================================
# MUTATIONS — Engine (N/A)
# =============================================================================
func equip_engine(_engine_name: StringName) -> void:
	pass


func remove_engine() -> void:
	pass


# =============================================================================
# MUTATIONS — Modules
# =============================================================================
func equip_module(idx: int, module_name: StringName) -> void:
	if player_inventory == null or station_equipment == null:
		return
	if not player_inventory.has_module(module_name):
		return
	if idx < 0 or idx >= station_equipment.modules.size():
		return
	var slot_sz =get_module_slot_size(idx)
	if not player_inventory.is_module_compatible(module_name, slot_sz):
		return
	player_inventory.remove_module(module_name)
	var old = station_equipment.modules[idx]
	if old != &"":
		player_inventory.add_module(old)
	station_equipment.modules[idx] = module_name
	loadout_changed.emit()


func remove_module(idx: int) -> void:
	if player_inventory == null or station_equipment == null:
		return
	if idx < 0 or idx >= station_equipment.modules.size():
		return
	var old = station_equipment.modules[idx]
	if old != &"":
		player_inventory.add_module(old)
		station_equipment.modules[idx] = &""
	loadout_changed.emit()
