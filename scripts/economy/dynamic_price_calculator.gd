class_name DynamicPriceCalculator
extends RefCounted

# =============================================================================
# Dynamic Price Calculator - Computes buy/sell prices based on supply, demand,
# and station stock levels. Prices fluctuate with scarcity and surplus.
# =============================================================================

const SELL_RATIO: float = 0.5  # Player sells at 50% of buy price
const MIN_PRICE_FACTOR: float = 0.3  # Price never drops below 30% of base
const MAX_PRICE_FACTOR: float = 3.0  # Price never exceeds 300% of base


## Calculate the buy price for an item at a given station.
## base_price: the static reference price from PriceCatalog/registries.
## profile: the station's StationEconomyProfile (stock levels, modifier).
static func get_buy_price(item_name: String, base_price: int, profile: StationEconomyProfile) -> int:
	if base_price <= 0:
		return 0
	if profile == null:
		return base_price

	var factor: float = _compute_price_factor(item_name, profile)
	var price: float = float(base_price) * factor
	return maxi(1, int(roundf(price)))


## Calculate the sell price for an item at a given station.
## Always SELL_RATIO (50%) of the dynamic buy price.
static func get_sell_price(item_name: String, base_price: int, profile: StationEconomyProfile) -> int:
	var buy: int = get_buy_price(item_name, base_price, profile)
	return maxi(1, int(roundf(float(buy) * SELL_RATIO)))


## Returns a price trend indicator for UI display.
## -1 = cheap (surplus), 0 = normal, +1 = expensive (scarce).
static func get_price_trend(item_name: String, profile: StationEconomyProfile) -> int:
	if profile == null:
		return 0

	var current_stock: int = profile.get_stock(item_name)
	var max_stock: int = profile.get_max_stock(item_name)
	if max_stock <= 0:
		return 0

	var stock_ratio: float = float(current_stock) / float(max_stock)
	if stock_ratio < 0.25:
		return 1   # Scarce — expensive
	elif stock_ratio > 0.7:
		return -1  # Surplus — cheap
	return 0       # Normal


## Internal: compute the total price multiplier from supply/demand + station + volatility.
static func _compute_price_factor(item_name: String, profile: StationEconomyProfile) -> float:
	var supply_demand_factor: float = _get_supply_demand_factor(item_name, profile)
	var station_modifier: float = profile.price_modifier
	var volatility: float = _get_volatility(item_name, profile.station_key)

	var raw_factor: float = supply_demand_factor * station_modifier * (1.0 + volatility)
	return clampf(raw_factor, MIN_PRICE_FACTOR, MAX_PRICE_FACTOR)


## Supply/demand factor based on current stock vs max stock.
## Low stock = high price, high stock = low price.
static func _get_supply_demand_factor(item_name: String, profile: StationEconomyProfile) -> float:
	var current_stock: int = profile.get_stock(item_name)
	var max_stock: int = profile.get_max_stock(item_name)

	# Item not stocked at this station — use base price
	if max_stock <= 0:
		return 1.0

	var stock_ratio: float = float(current_stock) / float(max_stock)

	if stock_ratio < 0.2:
		# Scarce: 1.5x up to 2.5x as stock approaches 0
		return 1.5 + (0.2 - stock_ratio) * 5.0
	elif stock_ratio > 0.8:
		# Surplus: 0.7x down to 0.5x as stock approaches max
		return maxf(0.5, 0.7 - (stock_ratio - 0.8) * 1.0)
	else:
		# Normal range: gentle slope from 1.15x (at 0.2) to 0.85x (at 0.8)
		return 1.0 + (0.5 - stock_ratio) * 0.5


## Small deterministic noise (+-5%) seeded by item + station + current hour.
## This ensures prices are consistent within the same hour for all players.
static func _get_volatility(item_name: String, station_key: String) -> float:
	# Use hour-based seed for consistency within the same game-hour
	var hour_seed: int = int(Time.get_unix_time_from_system() / 3600.0)
	var combined_seed: int = item_name.hash() ^ station_key.hash() ^ hour_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = combined_seed
	# Range: -0.05 to +0.05
	return rng.randf_range(-0.05, 0.05)
