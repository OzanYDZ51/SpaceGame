class_name RefineryManager
extends RefCounted

# =============================================================================
# Refinery Manager — orchestrates station storages + refinery queues.
# Keyed by station_key ("system_id:station_idx").
# Handles: storage access, job submission, tick, transfer, serialization.
# =============================================================================

var _storages: Dictionary = {}  # station_key -> StationStorage
var _queues: Dictionary = {}    # station_key -> RefineryQueue


static func make_key(system_id: int, station_idx: int) -> String:
	return "%d:%d" % [system_id, station_idx]


func get_storage(station_key: String) -> StationStorage:
	if not _storages.has(station_key):
		var s := StationStorage.new()
		s.station_key = station_key
		_storages[station_key] = s
	return _storages[station_key]


func get_queue(station_key: String) -> RefineryQueue:
	if not _queues.has(station_key):
		var q := RefineryQueue.new()
		q.station_key = station_key
		_queues[station_key] = q
	return _queues[station_key]


## Submit a refining job. Consumes inputs from station storage.
## Returns the job on success, null on failure.
func submit_job(station_key: String, recipe_id: StringName, quantity: int) -> RefineryJob:
	var recipe := RefineryRegistry.get_recipe(recipe_id)
	if recipe == null:
		return null
	var storage := get_storage(station_key)
	var queue := get_queue(station_key)
	if not queue.can_add():
		return null
	# Check inputs
	for input in recipe.inputs:
		var needed: int = input.qty * quantity
		if not storage.has_amount(input.id, needed):
			return null
	# Consume inputs
	for input in recipe.inputs:
		storage.remove(input.id, input.qty * quantity)
	# Create job
	var job := RefineryJob.create(recipe, quantity)
	queue.add_job(job)
	return job


## Transfer items from ship resources to station storage.
## Returns actual amount transferred.
func transfer_to_storage(station_key: String, item_id: StringName, qty: int, player_data: PlayerData) -> int:
	if player_data == null:
		return 0
	var available: int = player_data.get_active_ship_resource(item_id)
	var actual: int = mini(qty, available)
	if actual <= 0:
		return 0
	var storage := get_storage(station_key)
	var stored: int = storage.add(item_id, actual)
	if stored > 0:
		player_data.spend_active_ship_resource(item_id, stored)
	return stored


## Transfer items from station storage to ship resources.
## Returns actual amount transferred.
func transfer_to_ship(station_key: String, item_id: StringName, qty: int, player_data: PlayerData) -> int:
	if player_data == null:
		return 0
	var storage := get_storage(station_key)
	var available: int = storage.get_amount(item_id)
	var actual: int = mini(qty, available)
	if actual <= 0:
		return 0
	var removed: int = storage.remove(item_id, actual)
	if removed > 0:
		player_data.add_active_ship_resource(item_id, removed)
	return removed


## Tick all active queues (call each frame from GameManager).
func tick() -> void:
	for key in _queues:
		var queue: RefineryQueue = _queues[key]
		var storage := get_storage(key)
		queue.tick(storage)


func serialize() -> Dictionary:
	var result: Dictionary = {}
	var storages_data: Dictionary = {}
	for key in _storages:
		var s: StationStorage = _storages[key]
		var data := s.serialize()
		if not data.is_empty():
			storages_data[key] = data
	if not storages_data.is_empty():
		result["storages"] = storages_data
	var queues_data: Dictionary = {}
	for key in _queues:
		var q: RefineryQueue = _queues[key]
		var data := q.serialize()
		if not data.is_empty():
			queues_data[key] = data
	if not queues_data.is_empty():
		result["queues"] = queues_data
	return result


func deserialize(data: Dictionary) -> void:
	_storages.clear()
	_queues.clear()
	var storages_data: Dictionary = data.get("storages", {})
	for key in storages_data:
		var s := StationStorage.new()
		s.station_key = key
		s.deserialize(storages_data[key])
		_storages[key] = s
	var queues_data: Dictionary = data.get("queues", {})
	for key in queues_data:
		var q := RefineryQueue.new()
		q.station_key = key
		q.deserialize(queues_data[key])
		_queues[key] = q
