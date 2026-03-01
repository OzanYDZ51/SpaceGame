class_name FleetShipEquipAdapter
extends RefCounted

# =============================================================================
# Fleet Ship Equip Adapter
# Unified interface for equipment management across LIVE (active ship) and
# DATA (non-active fleet ships) modes.
# LIVE mode delegates to WeaponManager + EquipmentManager (real game objects).
# DATA mode modifies FleetShip + PlayerInventory directly.
# =============================================================================

signal loadout_changed

enum Mode { LIVE, DATA }

var mode: Mode = Mode.LIVE
var fleet_ship = null
var player_inventory = null

# LIVE mode refs
var _weapon_manager = null
var _equipment_manager = null

# DATA mode cache
var _ship_data: ShipData = null


static func create_live(wm, em, fs, inv):
	var a =FleetShipEquipAdapter.new()
	a.mode = Mode.LIVE
	a._weapon_manager = wm
	a._equipment_manager = em
	a.fleet_ship = fs
	a.player_inventory = inv
	a._ship_data = em.ship_data if em else null
	return a


static func create_data(fs, inv):
	var a =FleetShipEquipAdapter.new()
	a.mode = Mode.DATA
	a.fleet_ship = fs
	a.player_inventory = inv
	a._ship_data = ShipRegistry.get_ship_data(fs.ship_id)
	return a


# =============================================================================
# QUERIES — Ship Data
# =============================================================================
func get_ship_data() -> ShipData:
	if mode == Mode.LIVE and _equipment_manager:
		return _equipment_manager.ship_data
	return _ship_data


# =============================================================================
# QUERIES — Weapons / Hardpoints
# =============================================================================
func get_hardpoint_count() -> int:
	if mode == Mode.LIVE and _weapon_manager:
		return _weapon_manager.hardpoints.size()
	return _ship_data.hardpoints.size() if _ship_data else 0


func get_hardpoint_slot_size(idx: int) -> String:
	if mode == Mode.LIVE and _weapon_manager:
		if idx >= 0 and idx < _weapon_manager.hardpoints.size():
			return _weapon_manager.hardpoints[idx].slot_size
		return "S"
	if _ship_data and idx >= 0 and idx < _ship_data.hardpoints.size():
		return _ship_data.hardpoints[idx].get("size", "S")
	return "S"


func is_hardpoint_turret(idx: int) -> bool:
	if mode == Mode.LIVE and _weapon_manager:
		if idx >= 0 and idx < _weapon_manager.hardpoints.size():
			return _weapon_manager.hardpoints[idx].is_turret
		return false
	if _ship_data and idx >= 0 and idx < _ship_data.hardpoints.size():
		return _ship_data.hardpoints[idx].get("is_turret", false)
	return false


func get_mounted_weapon_name(idx: int) -> StringName:
	if mode == Mode.LIVE and _weapon_manager:
		if idx >= 0 and idx < _weapon_manager.hardpoints.size():
			var hp =_weapon_manager.hardpoints[idx]
			return hp.mounted_weapon.weapon_name if hp.mounted_weapon else &""
		return &""
	if fleet_ship and idx >= 0 and idx < fleet_ship.weapons.size():
		return fleet_ship.weapons[idx]
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
	if mode == Mode.LIVE and _equipment_manager:
		return _equipment_manager.equipped_shield.shield_name if _equipment_manager.equipped_shield else &""
	return fleet_ship.shield_name if fleet_ship else &""


func get_equipped_shield() -> ShieldResource:
	var sn =get_equipped_shield_name()
	if sn == &"":
		return null
	return ShieldRegistry.get_shield(sn)


func get_shield_slot_size() -> String:
	var sd =get_ship_data()
	return sd.shield_slot_size if sd else "S"


# =============================================================================
# QUERIES — Engine
# =============================================================================
func get_equipped_engine_name() -> StringName:
	if mode == Mode.LIVE and _equipment_manager:
		return _equipment_manager.equipped_engine.engine_name if _equipment_manager.equipped_engine else &""
	return fleet_ship.engine_name if fleet_ship else &""


func get_equipped_engine() -> EngineResource:
	var en =get_equipped_engine_name()
	if en == &"":
		return null
	return EngineRegistry.get_engine(en)


func get_engine_slot_size() -> String:
	var sd =get_ship_data()
	return sd.engine_slot_size if sd else "S"


# =============================================================================
# QUERIES — Modules
# =============================================================================
func get_module_slot_count() -> int:
	var sd =get_ship_data()
	return sd.module_slots.size() if sd else 0


func get_module_slot_size(idx: int) -> String:
	if mode == Mode.LIVE and _equipment_manager:
		return _equipment_manager.get_module_slot_size(idx)
	var sd =get_ship_data()
	if sd and idx >= 0 and idx < sd.module_slots.size():
		return sd.module_slots[idx]
	return "S"


func get_equipped_module_name(idx: int) -> StringName:
	if mode == Mode.LIVE and _equipment_manager:
		if idx >= 0 and idx < _equipment_manager.equipped_modules.size():
			var m: ModuleResource = _equipment_manager.equipped_modules[idx]
			return m.module_name if m else &""
		return &""
	if fleet_ship and idx >= 0 and idx < fleet_ship.modules.size():
		return fleet_ship.modules[idx]
	return &""


func get_equipped_module(idx: int) -> ModuleResource:
	var mn =get_equipped_module_name(idx)
	if mn == &"":
		return null
	return ModuleRegistry.get_module(mn)


# =============================================================================
# QUERIES — Loaded Missiles
# =============================================================================
func get_loaded_missile_name(idx: int) -> StringName:
	if mode == Mode.LIVE and _weapon_manager:
		return _weapon_manager.get_loaded_missile(idx)
	if fleet_ship and idx >= 0 and idx < fleet_ship.loaded_missiles.size():
		return fleet_ship.loaded_missiles[idx]
	return &""


# =============================================================================
# MUTATIONS — Missiles
# =============================================================================
func load_missile(idx: int, missile_name: StringName) -> void:
	if mode == Mode.LIVE and _weapon_manager:
		_weapon_manager.load_missile(idx, missile_name)
		_sync_fleet_ship_missiles()
	else:
		if fleet_ship and idx >= 0 and idx < fleet_ship.loaded_missiles.size():
			fleet_ship.loaded_missiles[idx] = missile_name
	loadout_changed.emit()


func unload_missile(idx: int) -> void:
	load_missile(idx, &"")


# =============================================================================
# MUTATIONS — Weapons
# =============================================================================
func equip_weapon(idx: int, weapon_name: StringName) -> void:
	if player_inventory == null or not player_inventory.has_weapon(weapon_name):
		return

	if mode == Mode.LIVE and _weapon_manager:
		var hp =_weapon_manager.hardpoints[idx]
		var new_w =WeaponRegistry.get_weapon(weapon_name)
		if new_w == null or not hp.can_mount(new_w):
			return
		player_inventory.remove_weapon(weapon_name)
		var old_name =_weapon_manager.swap_weapon(idx, weapon_name)
		if old_name != &"":
			player_inventory.add_weapon(old_name)
		_sync_fleet_ship_weapons()
	else:
		if fleet_ship == null or idx < 0 or idx >= fleet_ship.weapons.size():
			return
		# Slot compatibility check
		var slot_size =get_hardpoint_slot_size(idx)
		var is_turret =is_hardpoint_turret(idx)
		if not player_inventory.is_compatible(weapon_name, slot_size, is_turret):
			return
		player_inventory.remove_weapon(weapon_name)
		var old = fleet_ship.weapons[idx]
		if old != &"":
			player_inventory.add_weapon(old)
		fleet_ship.weapons[idx] = weapon_name

	loadout_changed.emit()


func remove_weapon(idx: int) -> void:
	if player_inventory == null:
		return

	if mode == Mode.LIVE and _weapon_manager:
		var old_name =_weapon_manager.remove_weapon(idx)
		if old_name != &"":
			player_inventory.add_weapon(old_name)
		_sync_fleet_ship_weapons()
	else:
		if fleet_ship == null or idx < 0 or idx >= fleet_ship.weapons.size():
			return
		var old = fleet_ship.weapons[idx]
		if old != &"":
			player_inventory.add_weapon(old)
			fleet_ship.weapons[idx] = &""

	loadout_changed.emit()


# =============================================================================
# MUTATIONS — Shield
# =============================================================================
func equip_shield(shield_name: StringName) -> void:
	if player_inventory == null or not player_inventory.has_shield(shield_name):
		return

	if mode == Mode.LIVE and _equipment_manager:
		var sd =_equipment_manager.ship_data
		if sd and not player_inventory.is_shield_compatible(shield_name, sd.shield_slot_size):
			return
		player_inventory.remove_shield(shield_name)
		var new_sh =ShieldRegistry.get_shield(shield_name)
		var old =_equipment_manager.equip_shield(new_sh)
		if old:
			player_inventory.add_shield(old.shield_name)
		_sync_fleet_ship_shield()
	else:
		if fleet_ship == null:
			return
		var slot_sz =get_shield_slot_size()
		if not player_inventory.is_shield_compatible(shield_name, slot_sz):
			return
		player_inventory.remove_shield(shield_name)
		if fleet_ship.shield_name != &"":
			player_inventory.add_shield(fleet_ship.shield_name)
		fleet_ship.shield_name = shield_name

	loadout_changed.emit()


func remove_shield() -> void:
	if player_inventory == null:
		return

	if mode == Mode.LIVE and _equipment_manager:
		var old =_equipment_manager.remove_shield()
		if old:
			player_inventory.add_shield(old.shield_name)
		_sync_fleet_ship_shield()
	else:
		if fleet_ship and fleet_ship.shield_name != &"":
			player_inventory.add_shield(fleet_ship.shield_name)
			fleet_ship.shield_name = &""

	loadout_changed.emit()


# =============================================================================
# MUTATIONS — Engine
# =============================================================================
func equip_engine(engine_name: StringName) -> void:
	if player_inventory == null or not player_inventory.has_engine(engine_name):
		return

	if mode == Mode.LIVE and _equipment_manager:
		var sd =_equipment_manager.ship_data
		if sd and not player_inventory.is_engine_compatible(engine_name, sd.engine_slot_size):
			return
		player_inventory.remove_engine(engine_name)
		var new_en =EngineRegistry.get_engine(engine_name)
		var old =_equipment_manager.equip_engine(new_en)
		if old:
			player_inventory.add_engine(old.engine_name)
		_sync_fleet_ship_engine()
	else:
		if fleet_ship == null:
			return
		var slot_sz =get_engine_slot_size()
		if not player_inventory.is_engine_compatible(engine_name, slot_sz):
			return
		player_inventory.remove_engine(engine_name)
		if fleet_ship.engine_name != &"":
			player_inventory.add_engine(fleet_ship.engine_name)
		fleet_ship.engine_name = engine_name

	loadout_changed.emit()


func remove_engine() -> void:
	if player_inventory == null:
		return

	if mode == Mode.LIVE and _equipment_manager:
		var old =_equipment_manager.remove_engine()
		if old:
			player_inventory.add_engine(old.engine_name)
		_sync_fleet_ship_engine()
	else:
		if fleet_ship and fleet_ship.engine_name != &"":
			player_inventory.add_engine(fleet_ship.engine_name)
			fleet_ship.engine_name = &""

	loadout_changed.emit()


# =============================================================================
# MUTATIONS — Modules
# =============================================================================
func equip_module(idx: int, module_name: StringName) -> void:
	if player_inventory == null or not player_inventory.has_module(module_name):
		return

	if mode == Mode.LIVE and _equipment_manager:
		var slot_sz =_equipment_manager.get_module_slot_size(idx)
		if not player_inventory.is_module_compatible(module_name, slot_sz):
			return
		player_inventory.remove_module(module_name)
		var new_mod =ModuleRegistry.get_module(module_name)
		var old =_equipment_manager.equip_module(idx, new_mod)
		if old:
			player_inventory.add_module(old.module_name)
		_sync_fleet_ship_modules()
	else:
		if fleet_ship == null or idx < 0 or idx >= fleet_ship.modules.size():
			return
		var slot_sz =get_module_slot_size(idx)
		if not player_inventory.is_module_compatible(module_name, slot_sz):
			return
		player_inventory.remove_module(module_name)
		var old = fleet_ship.modules[idx]
		if old != &"":
			player_inventory.add_module(old)
		fleet_ship.modules[idx] = module_name

	loadout_changed.emit()


func remove_module(idx: int) -> void:
	if player_inventory == null:
		return

	if mode == Mode.LIVE and _equipment_manager:
		var old =_equipment_manager.remove_module(idx)
		if old:
			player_inventory.add_module(old.module_name)
		_sync_fleet_ship_modules()
	else:
		if fleet_ship == null or idx < 0 or idx >= fleet_ship.modules.size():
			return
		var old = fleet_ship.modules[idx]
		if old != &"":
			player_inventory.add_module(old)
			fleet_ship.modules[idx] = &""

	loadout_changed.emit()


# =============================================================================
# SYNC — Keep FleetShip in sync with live managers (LIVE mode only)
# =============================================================================
func _sync_fleet_ship_weapons() -> void:
	if fleet_ship == null or _weapon_manager == null:
		return
	for i in _weapon_manager.hardpoints.size():
		if i < fleet_ship.weapons.size():
			var hp =_weapon_manager.hardpoints[i]
			fleet_ship.weapons[i] = hp.mounted_weapon.weapon_name if hp.mounted_weapon else &""


func _sync_fleet_ship_shield() -> void:
	if fleet_ship == null or _equipment_manager == null:
		return
	fleet_ship.shield_name = _equipment_manager.equipped_shield.shield_name if _equipment_manager.equipped_shield else &""


func _sync_fleet_ship_engine() -> void:
	if fleet_ship == null or _equipment_manager == null:
		return
	fleet_ship.engine_name = _equipment_manager.equipped_engine.engine_name if _equipment_manager.equipped_engine else &""


func _sync_fleet_ship_modules() -> void:
	if fleet_ship == null or _equipment_manager == null:
		return
	for i in _equipment_manager.equipped_modules.size():
		if i < fleet_ship.modules.size():
			var m: ModuleResource = _equipment_manager.equipped_modules[i]
			fleet_ship.modules[i] = m.module_name if m else &""


func _sync_fleet_ship_missiles() -> void:
	if fleet_ship == null or _weapon_manager == null:
		return
	for i in _weapon_manager.hardpoints.size():
		if i < fleet_ship.loaded_missiles.size():
			fleet_ship.loaded_missiles[i] = _weapon_manager.hardpoints[i].loaded_missile
