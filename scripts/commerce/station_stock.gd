class_name StationStock
extends RefCounted

# =============================================================================
# Station Stock - Defines what each station type sells
# Uses StationData.StationType enum values (0=REPAIR, 1=TRADE, 2=MILITARY, 3=MINING)
# =============================================================================


static func get_available_ships(station_type: int) -> Array[StringName]:
	match station_type:
		0:  # REPAIR — sells all ships
			return ShipRegistry.get_all_ship_ids()
		2:  # MILITARY — all combat ships
			return ShipRegistry.get_all_ship_ids()
		3:  # MINING — fighter only
			return [&"fighter_mk1"] as Array[StringName]
	# TRADE (1) — no ships
	return []


static func get_available_weapons(station_type: int) -> Array[StringName]:
	match station_type:
		0:  # REPAIR — all weapons
			return _get_all_weapon_names()
		1:  # TRADE — none
			return []
		2:  # MILITARY — combat weapons only (no mining)
			var result: Array[StringName] = []
			for wn in _get_all_weapon_names():
				var w := WeaponRegistry.get_weapon(wn)
				if w and w.weapon_type != WeaponResource.WeaponType.MINING_LASER:
					result.append(wn)
			return result
		3:  # MINING — mining lasers + basic weapons
			var result: Array[StringName] = []
			for wn in _get_all_weapon_names():
				var w := WeaponRegistry.get_weapon(wn)
				if w == null: continue
				if w.weapon_type == WeaponResource.WeaponType.MINING_LASER:
					result.append(wn)
				elif w.slot_size == WeaponResource.SlotSize.S:
					result.append(wn)
			return result
	return []


static func get_available_shields(station_type: int) -> Array[StringName]:
	match station_type:
		0: return ShieldRegistry.get_all_shield_names()
		1: return ShieldRegistry.get_all_shield_names()  # Trade sells shields
		2:  # Military — M/L shields
			var result: Array[StringName] = []
			for sn in ShieldRegistry.get_all_shield_names():
				var s := ShieldRegistry.get_shield(sn)
				if s and s.slot_size >= 1: result.append(sn)
			return result
		3:  # Mining — S shields only
			var result: Array[StringName] = []
			for sn in ShieldRegistry.get_all_shield_names():
				var s := ShieldRegistry.get_shield(sn)
				if s and s.slot_size == 0: result.append(sn)
			return result
	return []


static func get_available_engines(station_type: int) -> Array[StringName]:
	match station_type:
		0: return EngineRegistry.get_all_engine_names()
		1: return EngineRegistry.get_all_engine_names()
		2:  # Military — M/L engines
			var result: Array[StringName] = []
			for en in EngineRegistry.get_all_engine_names():
				var e := EngineRegistry.get_engine(en)
				if e and e.slot_size >= 1: result.append(en)
			return result
		3:  # Mining — S engines only
			var result: Array[StringName] = []
			for en in EngineRegistry.get_all_engine_names():
				var e := EngineRegistry.get_engine(en)
				if e and e.slot_size == 0: result.append(en)
			return result
	return []


static func get_available_modules(station_type: int) -> Array[StringName]:
	match station_type:
		0: return ModuleRegistry.get_all_module_names()
		1: return ModuleRegistry.get_all_module_names()
		2:  # Military — M/L modules
			var result: Array[StringName] = []
			for mn in ModuleRegistry.get_all_module_names():
				var m := ModuleRegistry.get_module(mn)
				if m and m.slot_size >= 1: result.append(mn)
			return result
		3:  # Mining — S modules only
			var result: Array[StringName] = []
			for mn in ModuleRegistry.get_all_module_names():
				var m := ModuleRegistry.get_module(mn)
				if m and m.slot_size == 0: result.append(mn)
			return result
	return []


static func _get_all_weapon_names() -> Array[StringName]:
	# Only weapons with real 3D models are sold in shops.
	# Placeholder weapons (BoxMesh/CylinderMesh) are hidden until proper models are added.
	var result: Array[StringName] = [
		&"Laser Mk1",
		&"Turret Mk1",
		&"Mining Laser Mk1", &"Mining Laser Mk2",
	]
	return result
