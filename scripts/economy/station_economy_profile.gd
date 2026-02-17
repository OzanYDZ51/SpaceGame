class_name StationEconomyProfile
extends RefCounted

# =============================================================================
# Station Economy Profile - Defines production, consumption, and stock levels
# for a single station. Each station type has default economic patterns.
# =============================================================================

var station_key: String = ""
var station_type: int = 0  # 0=repair, 1=trade, 2=military, 3=mining
var stock: Dictionary = {}  # item_name (String) -> current_quantity (int)
var base_demand: Dictionary = {}  # item_name (String) -> demand_per_hour (float)
var base_supply: Dictionary = {}  # item_name (String) -> supply_per_hour (float)
var price_modifier: float = 1.0  # system-wide price multiplier (danger_level based)

# Max stock caps per station type (default, then trade override)
const DEFAULT_MAX_STOCK: int = 500
const TRADE_MAX_STOCK: int = 1000

# Base stock levels per station type (before randomization)
const REPAIR_STOCK := {
	"metal": 200, "electronics": 100, "weapon_parts": 50,
}
const REPAIR_DEMAND := {
	"metal": 20.0, "electronics": 10.0,
}
const REPAIR_SUPPLY := {}

const TRADE_STOCK := {
	"metal": 300, "electronics": 200, "weapon_parts": 100, "data_chips": 150,
	"water": 200, "ice": 200, "iron": 200, "copper": 150, "titanium": 100,
	"gold": 50, "crystal": 40, "uranium": 30, "platinum": 15,
}
const TRADE_DEMAND := {
	"metal": 10.0, "electronics": 10.0, "weapon_parts": 5.0, "data_chips": 5.0,
	"water": 8.0, "ice": 5.0, "iron": 5.0, "copper": 3.0, "titanium": 2.0,
	"gold": 1.0, "crystal": 0.5, "uranium": 0.5, "platinum": 0.2,
}
const TRADE_SUPPLY := {
	"metal": 8.0, "electronics": 8.0, "weapon_parts": 3.0, "data_chips": 4.0,
	"water": 6.0, "ice": 4.0, "iron": 4.0, "copper": 2.0, "titanium": 1.5,
	"gold": 0.8, "crystal": 0.4, "uranium": 0.3, "platinum": 0.1,
}

const MILITARY_STOCK := {
	"weapon_parts": 200, "electronics": 150, "metal": 150, "uranium": 50,
}
const MILITARY_DEMAND := {
	"metal": 30.0, "electronics": 20.0, "uranium": 5.0,
}
const MILITARY_SUPPLY := {
	"weapon_parts": 5.0,
}

const MINING_STOCK := {
	"ice": 400, "iron": 350, "copper": 250, "titanium": 150,
	"gold": 60, "crystal": 40, "uranium": 25, "platinum": 10,
	"electronics": 50, "water": 80,
}
const MINING_DEMAND := {
	"electronics": 5.0, "water": 10.0,
}
const MINING_SUPPLY := {
	"ice": 40.0, "iron": 30.0, "copper": 20.0, "titanium": 10.0,
	"gold": 3.0, "crystal": 2.0, "uranium": 1.0, "platinum": 0.3,
}


## Factory: create a profile for a specific station with deterministic randomization.
static func create_for_station(station_key_: String, station_type_: int, danger_level: int) -> StationEconomyProfile:
	var profile := StationEconomyProfile.new()
	profile.station_key = station_key_
	profile.station_type = station_type_
	profile.price_modifier = 1.0 + danger_level * 0.1

	# Select base data based on station type
	var base_stock: Dictionary = {}
	var demand: Dictionary = {}
	var supply: Dictionary = {}

	match station_type_:
		0:  # REPAIR
			base_stock = REPAIR_STOCK.duplicate()
			demand = REPAIR_DEMAND.duplicate()
			supply = REPAIR_SUPPLY.duplicate()
		1:  # TRADE
			base_stock = TRADE_STOCK.duplicate()
			demand = TRADE_DEMAND.duplicate()
			supply = TRADE_SUPPLY.duplicate()
		2:  # MILITARY
			base_stock = MILITARY_STOCK.duplicate()
			demand = MILITARY_DEMAND.duplicate()
			supply = MILITARY_SUPPLY.duplicate()
		3:  # MINING
			base_stock = MINING_STOCK.duplicate()
			demand = MINING_DEMAND.duplicate()
			supply = MINING_SUPPLY.duplicate()

	profile.base_demand = demand
	profile.base_supply = supply

	# Deterministic randomization of initial stock (50-150% of base)
	var rng := RandomNumberGenerator.new()
	rng.seed = station_key_.hash()
	for item_name in base_stock:
		var base_qty: int = base_stock[item_name]
		var factor: float = 0.5 + rng.randf() * 1.0  # 0.5 to 1.5
		profile.stock[item_name] = int(base_qty * factor)

	return profile


func get_stock(item: String) -> int:
	return stock.get(item, 0)


func add_stock(item: String, amount: int) -> void:
	if item not in stock:
		stock[item] = 0
	var max_qty: int = get_max_stock(item)
	stock[item] = mini(stock[item] + amount, max_qty)


func remove_stock(item: String, amount: int) -> bool:
	var current: int = stock.get(item, 0)
	if current < amount:
		return false
	stock[item] = current - amount
	return true


func get_max_stock(_item: String) -> int:
	if station_type == 1:  # Trade stations have higher caps
		return TRADE_MAX_STOCK
	return DEFAULT_MAX_STOCK


func serialize() -> Dictionary:
	return {
		"station_key": station_key,
		"station_type": station_type,
		"stock": stock.duplicate(),
		"price_modifier": price_modifier,
	}


func deserialize(data: Dictionary) -> void:
	station_key = data.get("station_key", "")
	station_type = data.get("station_type", 0)
	price_modifier = data.get("price_modifier", 1.0)
	var saved_stock: Dictionary = data.get("stock", {})
	for key in saved_stock:
		stock[key] = int(saved_stock[key])

	# Rebuild supply/demand from station type (not serialized — deterministic)
	match station_type:
		0:
			base_demand = REPAIR_DEMAND.duplicate()
			base_supply = REPAIR_SUPPLY.duplicate()
		1:
			base_demand = TRADE_DEMAND.duplicate()
			base_supply = TRADE_SUPPLY.duplicate()
		2:
			base_demand = MILITARY_DEMAND.duplicate()
			base_supply = MILITARY_SUPPLY.duplicate()
		3:
			base_demand = MINING_DEMAND.duplicate()
			base_supply = MINING_SUPPLY.duplicate()
