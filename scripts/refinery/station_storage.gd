class_name StationStorage
extends RefCounted

# =============================================================================
# Station Storage — per-station item storage (ores + refined materials).
# Key format for station_key: "system_id:station_idx" (e.g. "42:0")
# =============================================================================

var station_key: String = ""
var storage: Dictionary = {}  # StringName -> int
var capacity: int = 10000     # total items max


func get_total() -> int:
	var total: int = 0
	for qty in storage.values():
		total += qty
	return total


func get_amount(item_id: StringName) -> int:
	return storage.get(item_id, 0)


func has_amount(item_id: StringName, qty: int) -> bool:
	return get_amount(item_id) >= qty


func add(item_id: StringName, qty: int) -> int:
	var space: int = capacity - get_total()
	var actual: int = mini(qty, space)
	if actual <= 0:
		return 0
	storage[item_id] = get_amount(item_id) + actual
	return actual


func remove(item_id: StringName, qty: int) -> int:
	var current: int = get_amount(item_id)
	var actual: int = mini(qty, current)
	if actual <= 0:
		return 0
	var remaining: int = current - actual
	if remaining <= 0:
		storage.erase(item_id)
	else:
		storage[item_id] = remaining
	return actual


func get_all_items() -> Dictionary:
	return storage.duplicate()


func serialize() -> Dictionary:
	var result: Dictionary = {}
	for key in storage:
		if storage[key] > 0:
			result[str(key)] = storage[key]
	return result


func deserialize(data: Dictionary) -> void:
	storage.clear()
	for key in data:
		var qty: int = int(data[key])
		if qty > 0:
			storage[StringName(str(key))] = qty
