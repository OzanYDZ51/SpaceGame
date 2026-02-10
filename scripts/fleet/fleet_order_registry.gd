class_name FleetOrderRegistry
extends RefCounted

# =============================================================================
# Fleet Order Registry — Extensible registry of fleet orders
# Each order: { "id": StringName, "display_name": String, "description": String }
# Filters orders by context (deployed state, target entity, etc.)
# =============================================================================

static var _orders: Array[Dictionary] = []
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_register(&"move_to", "DEPLACER", "Se deplacer vers cette position")
	_register(&"patrol", "PATROUILLER", "Patrouiller dans cette zone")
	_register(&"return_to_station", "RAPPELER", "Retourner a la station")


static func _register(id: StringName, display_name: String, description: String) -> void:
	_orders.append({
		"id": id,
		"display_name": display_name,
		"description": description,
	})


static func get_available_orders(context: Dictionary) -> Array[Dictionary]:
	_ensure_init()
	var result: Array[Dictionary] = []
	for order in _orders:
		if _is_available(order["id"], context):
			result.append(order)
	return result


static func _is_available(order_id: StringName, context: Dictionary) -> bool:
	var is_deployed: bool = context.get("is_deployed", false)
	match order_id:
		&"move_to":
			return true
		&"patrol":
			return true
		&"return_to_station":
			return is_deployed
	return false


static func build_default_params(order_id: StringName, context: Dictionary) -> Dictionary:
	match order_id:
		&"move_to":
			return {
				"target_x": context.get("universe_x", 0.0),
				"target_z": context.get("universe_z", 0.0),
			}
		&"patrol":
			return {
				"center_x": context.get("universe_x", 0.0),
				"center_z": context.get("universe_z", 0.0),
				"radius": 500.0,
			}
		&"return_to_station":
			return {}
	return {}
