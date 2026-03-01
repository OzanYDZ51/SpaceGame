class_name MissileRegistry
extends RefCounted

# =============================================================================
# Missile Registry - Static database of all missile definitions.
# Data-driven: loads .tres files from res://data/missiles/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/missiles", "missile_name")
	return _registry


static func get_missile(missile_name: StringName) -> MissileResource:
	return _get_registry().get_by_id(missile_name) as MissileResource


static func has_missile(missile_name: StringName) -> bool:
	return _get_registry().has_id(missile_name)


static func get_all_missile_names() -> Array[StringName]:
	return _get_registry().get_all_ids()
