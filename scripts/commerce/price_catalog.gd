class_name PriceCatalog
extends RefCounted

# =============================================================================
# Price Catalog - Static helpers to get prices from any item type
# =============================================================================


static func get_ship_price(ship_id: StringName) -> int:
	var d := ShipRegistry.get_ship_data(ship_id)
	return d.price if d else 0


static func get_weapon_price(weapon_name: StringName) -> int:
	var w := WeaponRegistry.get_weapon(weapon_name)
	return w.price if w else 0


static func get_shield_price(shield_name: StringName) -> int:
	var s := ShieldRegistry.get_shield(shield_name)
	return s.price if s else 0


static func get_engine_price(engine_name: StringName) -> int:
	var e := EngineRegistry.get_engine(engine_name)
	return e.price if e else 0


static func get_module_price(module_name: StringName) -> int:
	var m := ModuleRegistry.get_module(module_name)
	return m.price if m else 0


static func get_cargo_price(item_name: String) -> int:
	const CARGO_PRICES := {
		"metal": 15, "electronics": 30, "weapon_part": 80, "data_chip": 50,
	}
	return CARGO_PRICES.get(item_name, 10)


static func get_resource_price(resource_id: StringName) -> int:
	var r := MiningRegistry.get_resource(resource_id)
	return r.base_value if r else 0


static func get_sell_price(buy_price: int) -> int:
	return int(buy_price * 0.5)


static func format_price(amount: int) -> String:
	return PlayerEconomy.format_credits(amount) + " CR"
