class_name ShipRegistry
extends RefCounted

# =============================================================================
# Ship Registry - Static database of all ship definitions, keyed by ship_id.
# Data-driven: loads .tres files from res://data/ships/
# =============================================================================

static var _registry: DataRegistry = null


static func _get_registry() -> DataRegistry:
	if _registry == null:
		_registry = DataRegistry.new("res://data/ships", "ship_id")
		# Populate hardpoints from ship scenes (needed for DATA-mode equipment screen)
		for res in _registry.get_all():
			var data: ShipData = res as ShipData
			if data and data.hardpoints.is_empty() and data.ship_scene_path != "":
				data.hardpoints = ShipFactory.get_hardpoint_configs(data.ship_id)
	return _registry


static func get_ship_data(ship_id: StringName) -> ShipData:
	var data: ShipData = _get_registry().get_by_id(ship_id) as ShipData
	if data == null:
		push_error("ShipRegistry: Unknown ship_id '%s'" % ship_id)
	return data


## Returns all registered ship_ids for a given class category.
static func get_ships_by_class(ship_class: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for res in _get_registry().get_all():
		var d: ShipData = res as ShipData
		if d and d.ship_class == ship_class:
			result.append(d.ship_id)
	return result


## Returns all registered ship_ids.
static func get_all_ship_ids() -> Array[StringName]:
	return _get_registry().get_all_ids()
