class_name DataRegistry
extends RefCounted

# =============================================================================
# Data Registry - Generic .tres folder scanner.
# Loads all .tres files from a folder and indexes them by a specified ID field.
# Handles exported builds where .tres becomes .tres.remap.
# =============================================================================

var _cache: Dictionary = {}  # StringName -> Resource
var _folder: String
var _id_field: String


func _init(folder: String, id_field: String) -> void:
	_folder = folder
	_id_field = id_field
	load_all()


func load_all() -> void:
	_cache.clear()
	var dir := DirAccess.open(_folder)
	if dir == null:
		push_error("DataRegistry: Cannot open folder '%s' — run generate_entity_data.gd (Ctrl+Shift+X) to create .tres files" % _folder)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# Handle both editor (.tres) and exported (.tres.remap) builds
			var load_path := ""
			if file_name.ends_with(".tres"):
				load_path = _folder.path_join(file_name)
			elif file_name.ends_with(".tres.remap"):
				load_path = _folder.path_join(file_name.replace(".remap", ""))

			if load_path != "":
				var res := ResourceLoader.load(load_path)
				if res:
					var id_val: Variant = res.get(_id_field)
					if id_val != null and id_val is StringName and id_val != &"":
						_cache[id_val] = res
					elif id_val != null and id_val is String and id_val != "":
						_cache[StringName(id_val)] = res
					else:
						push_warning("DataRegistry: '%s' has empty or missing field '%s'" % [load_path, _id_field])
				else:
					push_warning("DataRegistry: Failed to load '%s'" % load_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func get_by_id(id: StringName) -> Resource:
	return _cache.get(id)


func get_all_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: StringName in _cache:
		result.append(key)
	result.sort()
	return result


func get_all() -> Array:
	var result: Array = []
	for key in _cache:
		result.append(_cache[key])
	return result


func has_id(id: StringName) -> bool:
	return _cache.has(id)


func count() -> int:
	return _cache.size()
