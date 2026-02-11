class_name ConstructionOrderRegistry
extends RefCounted

# =============================================================================
# Construction Order Registry — Available construction orders for context menu
# Pattern matches FleetOrderRegistry
# =============================================================================

static var _orders: Array[Dictionary] = []
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_register(&"build_station", "Station spatiale", "Placer un marqueur de construction de station")


static func _register(id: StringName, display_name: String, description: String) -> void:
	_orders.append({
		"id": id,
		"display_name": display_name,
		"description": description,
	})


static func get_available_orders() -> Array[Dictionary]:
	_ensure_init()
	var result: Array[Dictionary] = []
	for order in _orders:
		result.append(order.duplicate())
	return result
