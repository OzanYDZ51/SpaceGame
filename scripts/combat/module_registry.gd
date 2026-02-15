class_name ModuleRegistry
extends RefCounted

# =============================================================================
# Module Registry - Static database of all module definitions.
# Data-driven: loads .tres files from res://data/modules/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/modules", "module_name")
	return _registry


static func get_module(module_name: StringName) -> ModuleResource:
	var m: ModuleResource = _get_registry().get_by_id(module_name) as ModuleResource
	if m == null:
		push_error("ModuleRegistry: Unknown module '%s'" % module_name)
	return m


static func get_all_module_names() -> Array[StringName]:
	return _get_registry().get_all_ids()
