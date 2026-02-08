class_name SpatialGrid
extends RefCounted

# =============================================================================
# Spatial Grid - Hash-grid spatial partitioning for O(1) insert/remove/update
# and O(k) radius queries where k = entities in the queried area.
# =============================================================================

var cell_size: float = 500.0

# id -> { cell: Vector3i, pos: Vector3, data: Variant }
var _entities: Dictionary = {}

# Vector3i -> Array[StringName]
var _cells: Dictionary = {}

# Reusable Vector3i for lookups (avoids allocation in hot loops)
var _lookup_cell := Vector3i.ZERO


func _init(p_cell_size: float = 500.0) -> void:
	cell_size = p_cell_size


func insert(id: StringName, pos: Vector3, data: Variant = null) -> void:
	var cell := _pos_to_cell(pos)
	_entities[id] = { "cell": cell, "pos": pos, "data": data }
	if not _cells.has(cell):
		_cells[cell] = [] as Array[StringName]
	_cells[cell].append(id)


func remove(id: StringName) -> void:
	if not _entities.has(id):
		return
	var entry: Dictionary = _entities[id]
	var cell: Vector3i = entry["cell"]
	if _cells.has(cell):
		var arr: Array = _cells[cell]
		arr.erase(id)
		if arr.is_empty():
			_cells.erase(cell)
	_entities.erase(id)


func update_position(id: StringName, new_pos: Vector3) -> void:
	if not _entities.has(id):
		return
	var entry: Dictionary = _entities[id]
	var old_cell: Vector3i = entry["cell"]
	var new_cell := _pos_to_cell(new_pos)
	entry["pos"] = new_pos
	if old_cell != new_cell:
		# Move between cells
		if _cells.has(old_cell):
			var arr: Array = _cells[old_cell]
			arr.erase(id)
			if arr.is_empty():
				_cells.erase(old_cell)
		if not _cells.has(new_cell):
			_cells[new_cell] = [] as Array[StringName]
		_cells[new_cell].append(id)
		entry["cell"] = new_cell


func get_position(id: StringName) -> Vector3:
	if _entities.has(id):
		return _entities[id]["pos"]
	return Vector3.ZERO


func get_data(id: StringName) -> Variant:
	if _entities.has(id):
		return _entities[id]["data"]
	return null


func has_entity(id: StringName) -> bool:
	return _entities.has(id)


func query_radius(center: Vector3, radius: float) -> Array[StringName]:
	var result: Array[StringName] = []
	var r_sq := radius * radius
	var min_cell := _pos_to_cell(center - Vector3.ONE * radius)
	var max_cell := _pos_to_cell(center + Vector3.ONE * radius)

	for cx in range(min_cell.x, max_cell.x + 1):
		for cy in range(min_cell.y, max_cell.y + 1):
			for cz in range(min_cell.z, max_cell.z + 1):
				_lookup_cell.x = cx
				_lookup_cell.y = cy
				_lookup_cell.z = cz
				if not _cells.has(_lookup_cell):
					continue
				for id: StringName in _cells[_lookup_cell]:
					var pos: Vector3 = _entities[id]["pos"]
					if center.distance_squared_to(pos) <= r_sq:
						result.append(id)
	return result


## Returns up to `count` nearest entities as Array of {id, dist_sq} Dicts.
## Optimized: reuses query_radius, sorts in-place, truncates.
func query_nearest(center: Vector3, radius: float, count: int) -> Array[Dictionary]:
	var ids := query_radius(center, radius)
	var scored: Array[Dictionary] = []
	scored.resize(ids.size())
	for i in ids.size():
		var pos: Vector3 = _entities[ids[i]]["pos"]
		scored[i] = { "id": ids[i], "dist_sq": center.distance_squared_to(pos) }
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist_sq"] < b["dist_sq"])
	if scored.size() > count:
		scored.resize(count)
	return scored


func apply_origin_shift(shift: Vector3) -> void:
	# Rebuild cells after shifting all positions
	_cells.clear()
	for id: StringName in _entities:
		var entry: Dictionary = _entities[id]
		entry["pos"] -= shift
		var new_cell := _pos_to_cell(entry["pos"])
		entry["cell"] = new_cell
		if not _cells.has(new_cell):
			_cells[new_cell] = [] as Array[StringName]
		_cells[new_cell].append(id)


func get_all_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _entities:
		result.append(id)
	return result


func get_count() -> int:
	return _entities.size()


func clear() -> void:
	_entities.clear()
	_cells.clear()


func _pos_to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(pos.x / cell_size),
		floori(pos.y / cell_size),
		floori(pos.z / cell_size)
	)
