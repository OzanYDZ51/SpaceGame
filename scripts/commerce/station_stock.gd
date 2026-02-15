class_name StationStock
extends RefCounted

# =============================================================================
# Station Stock - Data-driven: queries registries for items with matching
# sold_at_station_types. Station type int -> StringName mapping below.
# =============================================================================

const STATION_TYPE_NAMES: Dictionary = {
	0: &"repair",
	1: &"trade",
	2: &"military",
	3: &"mining",
}


static func get_available_ships(station_type: int) -> Array[StringName]:
	var st_name: StringName = STATION_TYPE_NAMES.get(station_type, &"")
	if st_name == &"":
		return []
	var result: Array[StringName] = []
	for sid in ShipRegistry.get_all_ship_ids():
		var data := ShipRegistry.get_ship_data(sid)
		if data and data.sold_at_station_types.has(st_name):
			result.append(sid)
	return result


static func get_available_weapons(station_type: int) -> Array[StringName]:
	var st_name: StringName = STATION_TYPE_NAMES.get(station_type, &"")
	if st_name == &"":
		return []
	var result: Array[StringName] = []
	for wn in WeaponRegistry.get_all_weapon_names():
		var w := WeaponRegistry.get_weapon(wn)
		if w and w.sold_at_station_types.has(st_name):
			result.append(wn)
	return result


static func get_available_shields(station_type: int) -> Array[StringName]:
	var st_name: StringName = STATION_TYPE_NAMES.get(station_type, &"")
	if st_name == &"":
		return []
	var result: Array[StringName] = []
	for sn in ShieldRegistry.get_all_shield_names():
		var s := ShieldRegistry.get_shield(sn)
		if s and s.sold_at_station_types.has(st_name):
			result.append(sn)
	return result


static func get_available_engines(station_type: int) -> Array[StringName]:
	var st_name: StringName = STATION_TYPE_NAMES.get(station_type, &"")
	if st_name == &"":
		return []
	var result: Array[StringName] = []
	for en in EngineRegistry.get_all_engine_names():
		var e := EngineRegistry.get_engine(en)
		if e and e.sold_at_station_types.has(st_name):
			result.append(en)
	return result


static func get_available_modules(station_type: int) -> Array[StringName]:
	var st_name: StringName = STATION_TYPE_NAMES.get(station_type, &"")
	if st_name == &"":
		return []
	var result: Array[StringName] = []
	for mn in ModuleRegistry.get_all_module_names():
		var m := ModuleRegistry.get_module(mn)
		if m and m.sold_at_station_types.has(st_name):
			result.append(mn)
	return result
