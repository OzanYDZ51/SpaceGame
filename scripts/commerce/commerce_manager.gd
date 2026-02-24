class_name CommerceManager
extends RefCounted

# =============================================================================
# Commerce Manager - Handles buy/sell transactions
# =============================================================================

signal purchase_completed(item_type: String, item_id: StringName)
signal purchase_failed(reason: String)
signal sale_completed(item_type: String, item_id: StringName, total: int)

var player_economy
var player_inventory
var player_fleet
var player_data


func can_afford(amount: int) -> bool:
	return player_economy.credits >= amount


func buy_ship(ship_id: StringName) -> bool:
	var ship_data =ShipRegistry.get_ship_data(ship_id)
	if ship_data == null:
		purchase_failed.emit("Vaisseau inconnu")
		return false
	if not can_afford(ship_data.price):
		purchase_failed.emit("Credits insuffisants")
		return false
	# Check resource cost on active ship
	var active_ship = player_data.fleet.get_active() if player_data and player_data.fleet else null
	for res_id in ship_data.resource_cost:
		var required: int = int(ship_data.resource_cost[res_id])
		var available: int = active_ship.get_resource(res_id) if active_ship else 0
		if available < required:
			purchase_failed.emit("Ressources insuffisantes")
			return false
	# Deduct credits
	player_economy.spend_credits(ship_data.price)
	# Deduct resources from active ship
	for res_id in ship_data.resource_cost:
		var qty: int = int(ship_data.resource_cost[res_id])
		if active_ship:
			active_ship.spend_resource(res_id, qty)
	# Sync economy mirror after resource deduction
	if player_data:
		player_data._sync_economy_resources()
	var bare_ship =FleetShip.create_bare(ship_id)
	bare_ship.docked_system_id = GameManager.current_system_id_safe()
	# Use the active ship's already-resolved station ID (set by DockingManager on dock)
	var active_fs = player_fleet.get_active()
	if active_fs:
		bare_ship.docked_station_id = active_fs.docked_station_id
	player_fleet.add_ship(bare_ship)
	purchase_completed.emit("ship", ship_id)
	SaveManager.trigger_save("ship_purchase")
	return true


func can_afford_ship(ship_id: StringName) -> Dictionary:
	var result := { "can_buy": false, "missing_credits": 0, "missing_resources": {} }
	var ship_data =ShipRegistry.get_ship_data(ship_id)
	if ship_data == null:
		return result
	var credits_ok: bool = player_economy.credits >= ship_data.price
	if not credits_ok:
		result["missing_credits"] = ship_data.price - player_economy.credits
	var active_ship = player_data.fleet.get_active() if player_data and player_data.fleet else null
	var resources_ok := true
	for res_id in ship_data.resource_cost:
		var required: int = int(ship_data.resource_cost[res_id])
		var available: int = active_ship.get_resource(res_id) if active_ship else 0
		if available < required:
			resources_ok = false
			result["missing_resources"][res_id] = required - available
	result["can_buy"] = credits_ok and resources_ok
	return result


func buy_weapon(weapon_name: StringName) -> bool:
	var w =WeaponRegistry.get_weapon(weapon_name)
	if w == null:
		purchase_failed.emit("Arme inconnue")
		return false
	if not can_afford(w.price):
		purchase_failed.emit("Credits insuffisants")
		return false
	player_economy.spend_credits(w.price)
	player_inventory.add_weapon(weapon_name)
	purchase_completed.emit("weapon", weapon_name)
	SaveManager.trigger_save("weapon_purchase")
	return true


func buy_shield(shield_name: StringName) -> bool:
	var s =ShieldRegistry.get_shield(shield_name)
	if s == null:
		purchase_failed.emit("Bouclier inconnu")
		return false
	if not can_afford(s.price):
		purchase_failed.emit("Credits insuffisants")
		return false
	player_economy.spend_credits(s.price)
	player_inventory.add_shield(shield_name)
	purchase_completed.emit("shield", shield_name)
	SaveManager.trigger_save("shield_purchase")
	return true


func buy_engine(engine_name: StringName) -> bool:
	var e =EngineRegistry.get_engine(engine_name)
	if e == null:
		purchase_failed.emit("Moteur inconnu")
		return false
	if not can_afford(e.price):
		purchase_failed.emit("Credits insuffisants")
		return false
	player_economy.spend_credits(e.price)
	player_inventory.add_engine(engine_name)
	purchase_completed.emit("engine", engine_name)
	SaveManager.trigger_save("engine_purchase")
	return true


func buy_module(module_name: StringName) -> bool:
	var m =ModuleRegistry.get_module(module_name)
	if m == null:
		purchase_failed.emit("Module inconnu")
		return false
	if not can_afford(m.price):
		purchase_failed.emit("Credits insuffisants")
		return false
	player_economy.spend_credits(m.price)
	player_inventory.add_module(module_name)
	purchase_completed.emit("module", module_name)
	SaveManager.trigger_save("module_purchase")
	return true


func sell_weapon(weapon_name: StringName) -> bool:
	if not player_inventory.has_weapon(weapon_name):
		return false
	var w =WeaponRegistry.get_weapon(weapon_name)
	if w == null: return false
	var price =PriceCatalog.get_sell_price(w.price)
	player_inventory.remove_weapon(weapon_name)
	player_economy.add_credits(price)
	sale_completed.emit("weapon", weapon_name, price)
	SaveManager.mark_dirty()
	return true


func sell_shield(shield_name: StringName) -> bool:
	if not player_inventory.has_shield(shield_name):
		return false
	var s =ShieldRegistry.get_shield(shield_name)
	if s == null: return false
	var price =PriceCatalog.get_sell_price(s.price)
	player_inventory.remove_shield(shield_name)
	player_economy.add_credits(price)
	sale_completed.emit("shield", shield_name, price)
	SaveManager.mark_dirty()
	return true


func sell_engine(engine_name: StringName) -> bool:
	if not player_inventory.has_engine(engine_name):
		return false
	var e =EngineRegistry.get_engine(engine_name)
	if e == null: return false
	var price =PriceCatalog.get_sell_price(e.price)
	player_inventory.remove_engine(engine_name)
	player_economy.add_credits(price)
	sale_completed.emit("engine", engine_name, price)
	SaveManager.mark_dirty()
	return true


func sell_module(module_name: StringName) -> bool:
	if not player_inventory.has_module(module_name):
		return false
	var m =ModuleRegistry.get_module(module_name)
	if m == null: return false
	var price =PriceCatalog.get_sell_price(m.price)
	player_inventory.remove_module(module_name)
	player_economy.add_credits(price)
	sale_completed.emit("module", module_name, price)
	SaveManager.mark_dirty()
	return true


func sell_ship(fleet_index: int) -> bool:
	if player_fleet == null:
		return false
	if fleet_index == player_fleet.active_index:
		return false
	if fleet_index < 0 or fleet_index >= player_fleet.ships.size():
		return false
	if player_fleet.ships.size() <= 1:
		return false
	var fs =player_fleet.ships[fleet_index]
	var ship_data =ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null:
		return false
	var hull_price =PriceCatalog.get_sell_price(ship_data.price)
	var equip_price =PriceCatalog.get_sell_price(fs.get_total_equipment_value())
	var total =hull_price + equip_price
	player_fleet.remove_ship(fleet_index)
	player_economy.add_credits(total)
	sale_completed.emit("ship", fs.ship_id, total)
	SaveManager.trigger_save("ship_sold")
	return true


func get_ship_sell_price(fs) -> int:
	if fs == null:
		return 0
	var ship_data =ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null:
		return 0
	return PriceCatalog.get_sell_price(ship_data.price) + PriceCatalog.get_sell_price(fs.get_total_equipment_value())


func sell_cargo(item_name: String, qty: int = 1) -> bool:
	if player_data and player_data.fleet:
		var active = player_data.fleet.get_active()
		if active:
			return sell_cargo_from_ship(item_name, qty, active)
	return false


func sell_resource(resource_id: StringName, qty: int = 1) -> bool:
	# Default: sell from active ship via player_data
	if player_data:
		var active = player_data.fleet.get_active() if player_data.fleet else null
		if active:
			return sell_resource_from_ship(resource_id, qty, active)
	# Fallback for old path
	var unit_price =PriceCatalog.get_resource_price(resource_id)
	if unit_price <= 0: return false
	if not player_economy.spend_resource(resource_id, qty):
		return false
	var total =unit_price * qty
	player_economy.add_credits(total)
	sale_completed.emit("resource", resource_id, total)
	SaveManager.mark_dirty()
	return true


func sell_cargo_from_ship(item_name: String, qty: int, ship) -> bool:
	if ship == null or ship.cargo == null:
		return false
	var unit_price =PriceCatalog.get_cargo_price(item_name)
	if not ship.cargo.remove_item(item_name, qty):
		return false
	var total =unit_price * qty
	player_economy.add_credits(total)
	sale_completed.emit("cargo", StringName(item_name), total)
	# If this is the active ship, the cargo getter already points here
	SaveManager.mark_dirty()
	return true


func sell_resource_from_ship(resource_id: StringName, qty: int, ship) -> bool:
	if ship == null:
		return false
	var unit_price =PriceCatalog.get_resource_price(resource_id)
	if unit_price <= 0:
		return false
	if not ship.spend_resource(resource_id, qty):
		return false
	var total =unit_price * qty
	player_economy.add_credits(total)
	# Sync economy mirror if this is the active ship
	if player_data:
		player_data._sync_economy_resources()
	sale_completed.emit("resource", resource_id, total)
	SaveManager.mark_dirty()
	return true
