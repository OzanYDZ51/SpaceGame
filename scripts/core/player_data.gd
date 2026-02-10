class_name PlayerData
extends RefCounted

# =============================================================================
# Player Data — facade for all player-owned data objects.
# Owned by GameManager. Provides collect/apply for SaveManager.
# =============================================================================

var economy: PlayerEconomy = null
var inventory: PlayerInventory = null
var cargo: PlayerCargo = null
var fleet: PlayerFleet = null
var station_services: StationServices = null


func initialize(galaxy: GalaxyData) -> void:
	# Economy (hardcoded starting values for testing)
	economy = PlayerEconomy.new()
	economy.add_credits(1000000)
	economy.add_resource(&"ice", 10)
	economy.add_resource(&"iron", 5)

	# Inventory with starting weapons + equipment
	inventory = PlayerInventory.new()
	inventory.add_weapon(&"Laser Mk1", 2)
	inventory.add_weapon(&"Mine Layer", 2)
	inventory.add_weapon(&"Laser Mk2", 1)
	inventory.add_weapon(&"Plasma Cannon", 1)
	inventory.add_weapon(&"Mining Laser Mk1", 1)
	inventory.add_shield(&"Bouclier Basique Mk2", 1)
	inventory.add_shield(&"Bouclier Prismatique", 1)
	inventory.add_engine(&"Propulseur Standard Mk2", 1)
	inventory.add_engine(&"Propulseur de Combat", 1)
	inventory.add_module(&"Condensateur d'Energie", 1)
	inventory.add_module(&"Dissipateur Thermique", 1)
	inventory.add_module(&"Amplificateur de Bouclier", 1)

	# Cargo
	cargo = PlayerCargo.new()

	# Fleet (starts with one ship)
	fleet = PlayerFleet.new()
	var starting_ship := FleetShip.from_ship_data(ShipRegistry.get_ship_data(&"fighter_mk1"))
	fleet.add_ship(starting_ship)

	# Station services (unlock state per station)
	station_services = StationServices.new()
	if galaxy:
		station_services.init_center_systems(galaxy)


func get_starting_fleet_ship() -> FleetShip:
	if fleet and fleet.ships.size() > 0:
		return fleet.ships[0]
	return null


func collect_save_state(player_ship: ShipController, system_transition: SystemTransition) -> Dictionary:
	var state: Dictionary = {}

	# Ship ID
	if player_ship:
		state["current_ship_id"] = str(player_ship.ship_data.ship_id if player_ship.ship_data else &"fighter_mk1")

	# Galaxy + system
	state["galaxy_seed"] = Constants.galaxy_seed
	if system_transition:
		state["system_id"] = system_transition.current_system_id

	# Position (floating origin absolute)
	if player_ship:
		var abs_pos: Array = FloatingOrigin.to_universe_pos(player_ship.global_position)
		state["pos_x"] = abs_pos[0]
		state["pos_y"] = abs_pos[1]
		state["pos_z"] = abs_pos[2]

	# Rotation
	if player_ship:
		var rot: Vector3 = player_ship.rotation
		state["rotation_x"] = rot.x
		state["rotation_y"] = rot.y
		state["rotation_z"] = rot.z

	# Credits & resources
	if economy:
		state["credits"] = economy.credits
		var resources: Array = []
		for res_id in economy.resources:
			var qty: int = economy.resources[res_id]
			if qty > 0:
				resources.append({"resource_id": str(res_id), "quantity": qty})
		state["resources"] = resources

	# Inventory
	if inventory:
		state["inventory"] = inventory.serialize()

	# Cargo
	if cargo:
		state["cargo"] = cargo.serialize()

	# Equipment
	if player_ship:
		var em := player_ship.get_node_or_null("EquipmentManager") as EquipmentManager
		if em:
			state["equipment"] = em.serialize()

	# Station services
	if station_services:
		state["station_services"] = station_services.serialize()

	# Fleet
	if fleet:
		state["fleet"] = fleet.serialize()

	return state


func apply_save_state(state: Dictionary, player_ship: ShipController, system_transition: SystemTransition, galaxy: GalaxyData, fleet_deployment_mgr: FleetDeploymentManager, commerce_manager: CommerceManager) -> void:
	if state.is_empty():
		return

	var ship_id: String = state.get("current_ship_id", "fighter_mk1")

	# Position — galaxy + system
	var gal_seed: int = int(state.get("galaxy_seed", Constants.galaxy_seed))
	if gal_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = gal_seed
		# Galaxy re-generation handled by caller (GameManager)

	var sys_id: int = int(state.get("system_id", 0))
	if system_transition and sys_id != system_transition.current_system_id:
		system_transition.jump_to_system(sys_id)

	# Credits & resources
	if economy:
		var current_credits: int = economy.credits
		if current_credits > 0:
			economy.add_credits(-current_credits)
		var saved_credits: int = int(state.get("credits", 1500))
		economy.add_credits(saved_credits)

		var resources: Array = state.get("resources", [])
		for res_id in economy.resources.keys():
			var qty: int = economy.resources[res_id]
			if qty > 0:
				economy.add_resource(res_id, -qty)
		for res in resources:
			var res_id := StringName(str(res.get("resource_id", "")))
			var qty: int = int(res.get("quantity", 0))
			if res_id != &"" and qty > 0:
				economy.add_resource(res_id, qty)

	# Inventory
	if inventory:
		inventory.clear_all()
		var items: Array = state.get("inventory", [])
		for item in items:
			var category: String = item.get("category", "")
			var item_name := StringName(str(item.get("item_name", "")))
			var qty: int = int(item.get("quantity", 1))
			match category:
				"weapon": inventory.add_weapon(item_name, qty)
				"shield": inventory.add_shield(item_name, qty)
				"engine": inventory.add_engine(item_name, qty)
				"module": inventory.add_module(item_name, qty)

	# Cargo
	if cargo:
		cargo.clear()
		var cargo_items: Array = state.get("cargo", [])
		var items_to_add: Array[Dictionary] = []
		for item in cargo_items:
			items_to_add.append({
				"name": item.get("item_name", ""),
				"type": item.get("item_type", ""),
				"quantity": item.get("quantity", 1),
				"icon_color": item.get("icon_color", ""),
			})
		if not items_to_add.is_empty():
			cargo.add_items(items_to_add)

	# Equipment
	var equipment: Dictionary = state.get("equipment", {})
	if not equipment.is_empty() and player_ship:
		var em := player_ship.get_node_or_null("EquipmentManager") as EquipmentManager
		if em:
			var shield_name = equipment.get("shield_name", null)
			if shield_name != null and str(shield_name) != "":
				var shield_res := ShieldRegistry.get_shield(StringName(str(shield_name)))
				if shield_res:
					em.equip_shield(shield_res)
			var engine_name = equipment.get("engine_name", null)
			if engine_name != null and str(engine_name) != "":
				var engine_res := EngineRegistry.get_engine(StringName(str(engine_name)))
				if engine_res:
					em.equip_engine(engine_res)
		var wm := player_ship.get_node_or_null("WeaponManager") as WeaponManager
		if wm:
			var hardpoints: Array = equipment.get("hardpoints", [])
			var weapon_names: Array[StringName] = []
			for wp_name in hardpoints:
				weapon_names.append(StringName(str(wp_name)) if wp_name != null and str(wp_name) != "" else &"")
			if not weapon_names.is_empty():
				wm.equip_weapons(weapon_names)

	# Station services
	var svc_data: Array = state.get("station_services", [])
	if not svc_data.is_empty() and station_services:
		station_services.deserialize(svc_data)

	# Fleet
	var fleet_data: Array = state.get("fleet", [])
	if not fleet_data.is_empty():
		fleet = PlayerFleet.deserialize(fleet_data)
		if fleet_deployment_mgr:
			fleet_deployment_mgr.initialize(fleet)
		if commerce_manager:
			commerce_manager.player_fleet = fleet

	print("SaveManager: State applied — ship=%s, system=%d, credits=%d" % [
		ship_id, sys_id, int(state.get("credits", 0))
	])
