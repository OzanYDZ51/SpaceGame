class_name FleetShip
extends RefCounted

# =============================================================================
# Fleet Ship - Represents a single owned ship with its loadout
# =============================================================================

var ship_id: StringName = &""
var custom_name: String = ""
var weapons: Array[StringName] = []     # per hardpoint (empty = &"")
var shield_name: StringName = &""
var engine_name: StringName = &""
var modules: Array[StringName] = []     # per slot (empty = &"")


static func from_ship_data(data: ShipData) -> FleetShip:
	var fs := FleetShip.new()
	fs.ship_id = data.ship_id
	fs.custom_name = String(data.ship_name)
	# Copy default weapon loadout
	fs.weapons.resize(data.hardpoints.size())
	for i in data.hardpoints.size():
		if i < data.default_loadout.size():
			fs.weapons[i] = data.default_loadout[i]
		else:
			fs.weapons[i] = &""
	# Default equipment from registries
	fs.shield_name = ShieldRegistry.get_default_shield(data.ship_class)
	fs.engine_name = EngineRegistry.get_default_engine(data.ship_class)
	var default_mods := ModuleRegistry.get_default_modules(data.ship_class)
	fs.modules.resize(data.module_slots.size())
	for i in data.module_slots.size():
		if i < default_mods.size():
			fs.modules[i] = default_mods[i]
		else:
			fs.modules[i] = &""
	return fs


func get_total_equipment_value() -> int:
	var total: int = 0
	for wn in weapons:
		if wn != &"":
			var w := WeaponRegistry.get_weapon(wn)
			if w: total += w.price
	if shield_name != &"":
		var s := ShieldRegistry.get_shield(shield_name)
		if s: total += s.price
	if engine_name != &"":
		var e := EngineRegistry.get_engine(engine_name)
		if e: total += e.price
	for mn in modules:
		if mn != &"":
			var m := ModuleRegistry.get_module(mn)
			if m: total += m.price
	return total


func serialize() -> Dictionary:
	return {
		"ship_id": String(ship_id),
		"custom_name": custom_name,
		"weapons": weapons.map(func(w): return String(w)),
		"shield": String(shield_name),
		"engine": String(engine_name),
		"modules": modules.map(func(m): return String(m)),
	}


static func deserialize(data: Dictionary) -> FleetShip:
	var fs := FleetShip.new()
	fs.ship_id = StringName(data.get("ship_id", ""))
	fs.custom_name = data.get("custom_name", "")
	for w in data.get("weapons", []):
		fs.weapons.append(StringName(w))
	fs.shield_name = StringName(data.get("shield", ""))
	fs.engine_name = StringName(data.get("engine", ""))
	for m in data.get("modules", []):
		fs.modules.append(StringName(m))
	return fs
