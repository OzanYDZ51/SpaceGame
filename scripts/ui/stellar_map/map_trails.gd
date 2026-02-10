class_name MapTrails
extends RefCounted

# =============================================================================
# Ship position trail history for the stellar map.
# Stores recent (x, z, time) triplets per entity and provides trail data.
# =============================================================================

const SAMPLE_INTERVAL: float = 0.15
const MAX_TRAIL_TIME: float = 8.0
const MAX_POINTS: int = 60

# entity_id -> PackedFloat64Array (x, z, t triplets)
var _trails: Dictionary = {}
var _last_sample_time: float = 0.0


func update(entities: Dictionary, time: float) -> void:
	if time - _last_sample_time < SAMPLE_INTERVAL:
		return
	_last_sample_time = time

	for id in entities:
		var ent: Dictionary = entities[id]
		var etype: int = ent["type"]
		# Only track ships
		if etype != EntityRegistrySystem.EntityType.SHIP_PLAYER \
			and etype != EntityRegistrySystem.EntityType.SHIP_NPC \
			and etype != EntityRegistrySystem.EntityType.SHIP_FLEET:
			continue

		var px: float = ent["pos_x"]
		var pz: float = ent["pos_z"]

		if not _trails.has(id):
			_trails[id] = PackedFloat64Array()

		var arr: PackedFloat64Array = _trails[id]

		# Skip if position hasn't changed
		if arr.size() >= 3:
			var last_x: float = arr[arr.size() - 3]
			var last_z: float = arr[arr.size() - 2]
			if absf(px - last_x) < 0.5 and absf(pz - last_z) < 0.5:
				continue

		arr.append(px)
		arr.append(pz)
		arr.append(time)

		# Trim old points
		while arr.size() > MAX_POINTS * 3:
			arr = arr.slice(3)
		while arr.size() >= 3 and (time - arr[2]) > MAX_TRAIL_TIME:
			arr = arr.slice(3)

		_trails[id] = arr

	# Remove trails for entities no longer present
	var to_remove: Array[String] = []
	for id in _trails:
		if not entities.has(id):
			to_remove.append(id)
	for id in to_remove:
		_trails.erase(id)


func get_trail(id: String) -> PackedFloat64Array:
	return _trails.get(id, PackedFloat64Array())


func clear() -> void:
	_trails.clear()
