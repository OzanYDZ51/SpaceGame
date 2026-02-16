class_name EconomySimulator
extends Node

# =============================================================================
# Economy Simulator - Background tick that updates station stock levels.
# Stations produce and consume goods over time. Child of GameManager.
# =============================================================================

signal economy_updated

var _profiles: Dictionary = {}  # station_key (String) -> StationEconomyProfile
var _tick_timer: float = 0.0

const TICK_INTERVAL: float = 60.0  # Update every 60 seconds
const HOURS_PER_TICK: float = 1.0  # Each tick simulates 1 hour of economy
const TRADE_CONVOY_CHANCE: float = 0.05  # 5% chance per tick per station
const TRADE_CONVOY_BOOST: float = 0.5  # +50% stock of a random item


## Get or lazily create a profile for a given station.
func get_or_create_profile(station_key: String, station_type: int, danger_level: int) -> StationEconomyProfile:
	if _profiles.has(station_key):
		return _profiles[station_key]
	var profile := StationEconomyProfile.create_for_station(station_key, station_type, danger_level)
	_profiles[station_key] = profile
	return profile


## Get an existing profile (returns null if not yet created).
func get_profile(station_key: String) -> StationEconomyProfile:
	return _profiles.get(station_key) as StationEconomyProfile


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer -= TICK_INTERVAL
	_simulate_tick()


## Run one economy tick: production, consumption, random events.
func _simulate_tick() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())

	for station_key in _profiles:
		var profile: StationEconomyProfile = _profiles[station_key]
		_tick_profile(profile, rng)

	economy_updated.emit()


## Apply production (supply) and consumption (demand) for one tick.
func _tick_profile(profile: StationEconomyProfile, rng: RandomNumberGenerator) -> void:
	# Production: add supply amounts
	for item_name in profile.base_supply:
		var supply_rate: float = profile.base_supply[item_name]
		var amount: int = int(supply_rate * HOURS_PER_TICK)
		if amount > 0:
			profile.add_stock(item_name, amount)

	# Consumption: subtract demand amounts
	for item_name in profile.base_demand:
		var demand_rate: float = profile.base_demand[item_name]
		var amount: int = int(demand_rate * HOURS_PER_TICK)
		if amount > 0:
			var current: int = profile.get_stock(item_name)
			var to_remove: int = mini(amount, current)
			if to_remove > 0:
				profile.remove_stock(item_name, to_remove)

	# Random event: trade convoy arrives (5% chance per tick)
	if rng.randf() < TRADE_CONVOY_CHANCE:
		_apply_trade_convoy(profile, rng)


## Random event: a trade convoy delivers extra stock of a random item.
func _apply_trade_convoy(profile: StationEconomyProfile, rng: RandomNumberGenerator) -> void:
	var items: Array = profile.stock.keys()
	if items.is_empty():
		return
	var random_item: String = items[rng.randi() % items.size()]
	var current: int = profile.get_stock(random_item)
	var boost: int = maxi(1, int(current * TRADE_CONVOY_BOOST))
	profile.add_stock(random_item, boost)


## Serialize all profiles for save/load.
func serialize() -> Dictionary:
	var data := {}
	for station_key in _profiles:
		var profile: StationEconomyProfile = _profiles[station_key]
		data[station_key] = profile.serialize()
	return data


## Restore all profiles from saved data.
func deserialize(data: Dictionary) -> void:
	_profiles.clear()
	for station_key in data:
		var profile := StationEconomyProfile.new()
		profile.deserialize(data[station_key])
		_profiles[station_key] = profile
