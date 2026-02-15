class_name WeaponRegistry
extends RefCounted

# =============================================================================
# Weapon Registry - Static database of all weapon definitions.
# Data-driven: loads .tres files from res://data/weapons/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/weapons", "weapon_name")
	return _registry


static func get_weapon(weapon_name: StringName) -> WeaponResource:
	var w: WeaponResource = _get_registry().get_by_id(weapon_name) as WeaponResource
	if w == null:
		push_error("WeaponRegistry: Unknown weapon '%s'" % weapon_name)
	return w


static func get_all_weapon_names() -> Array[StringName]:
	return _get_registry().get_all_ids()


## DEPRECATED: Default loadouts are now stored in ShipData.default_loadout.
static func get_default_loadout(ship_id: StringName) -> Array[StringName]:
	var data := ShipRegistry.get_ship_data(ship_id)
	if data and not data.default_loadout.is_empty():
		return data.default_loadout
	return []
