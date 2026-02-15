class_name ShieldRegistry
extends RefCounted

# =============================================================================
# Shield Registry - Static database of all shield definitions.
# Data-driven: loads .tres files from res://data/shields/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/shields", "shield_name")
	return _registry


static func get_shield(shield_name: StringName) -> ShieldResource:
	var s: ShieldResource = _get_registry().get_by_id(shield_name) as ShieldResource
	if s == null:
		push_error("ShieldRegistry: Unknown shield '%s'" % shield_name)
	return s


static func get_all_shield_names() -> Array[StringName]:
	return _get_registry().get_all_ids()
