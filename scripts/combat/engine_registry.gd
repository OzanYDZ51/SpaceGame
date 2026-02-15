class_name EngineRegistry
extends RefCounted

# =============================================================================
# Engine Registry - Static database of all engine definitions.
# Data-driven: loads .tres files from res://data/engines/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/engines", "engine_name")
	return _registry


static func get_engine(engine_name: StringName) -> EngineResource:
	var e: EngineResource = _get_registry().get_by_id(engine_name) as EngineResource
	if e == null:
		push_error("EngineRegistry: Unknown engine '%s'" % engine_name)
	return e


static func get_all_engine_names() -> Array[StringName]:
	return _get_registry().get_all_ids()
