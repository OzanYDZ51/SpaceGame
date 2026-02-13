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
	_register(&"attack", "ATTAQUER", "Attaquer la cible ennemie")
	_register(&"return_to_station", "RAPPELER", "Retourner a la station")
	_register(&"construction", "CONSTRUCTION", "Livrer des ressources au site de construction")
	_register(&"mine", "MINER", "Miner les asteroides dans cette zone")


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
		&"attack":
			var target_id: String = context.get("target_entity_id", "")
			if target_id == "":
				return false
			var ent := EntityRegistry.get_entity(target_id)
			return ent.get("type", -1) == EntityRegistrySystem.EntityType.SHIP_NPC
		&"return_to_station":
			return is_deployed
		&"construction":
			return context.has("construction_marker")
		&"mine":
			var fleet_ship: FleetShip = context.get("fleet_ship")
			if fleet_ship == null:
				return false
			for wn in fleet_ship.weapons:
				if wn != &"":
					var w := WeaponRegistry.get_weapon(wn)
					if w and w.weapon_type == WeaponResource.WeaponType.MINING_LASER:
						return true
			return false
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
		&"attack":
			var target_id: String = context.get("target_entity_id", "")
			var ent := EntityRegistry.get_entity(target_id)
			return {
				"target_entity_id": target_id,
				"target_x": ent.get("pos_x", context.get("universe_x", 0.0)),
				"target_z": ent.get("pos_z", context.get("universe_z", 0.0)),
			}
		&"return_to_station":
			return {}
		&"construction":
			var marker: Dictionary = context.get("construction_marker", {})
			return {
				"target_x": marker.get("pos_x", context.get("universe_x", 0.0)),
				"target_z": marker.get("pos_z", context.get("universe_z", 0.0)),
				"marker_id": marker.get("id", ""),
			}
		&"mine":
			return {
				"center_x": context.get("universe_x", 0.0),
				"center_z": context.get("universe_z", 0.0),
				"resource_filter": context.get("resource_filter", []),
			}
	return {}
