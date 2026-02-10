class_name PlayerData
extends RefCounted

# =============================================================================
# Player Data — facade for all player-owned data objects.
# Owned by GameManager. Provides collect/apply for SaveManager.
# =============================================================================

var economy: PlayerEconomy = null
var inventory: PlayerInventory = null
var cargo: PlayerCargo:
	get:
		if fleet:
			var active := fleet.get_active()
			if active and active.cargo:
				return active.cargo
		return _fallback_cargo
var _fallback_cargo: PlayerCargo = null
var fleet: PlayerFleet = null
var station_services: StationServices = null


func initialize(galaxy: GalaxyData) -> void:
	# Economy (hardcoded starting values for testing)
	economy = PlayerEconomy.new()
	economy.add_credits(1000000)

	# Fallback cargo (safety net, should not be used in normal flow)
	_fallback_cargo = PlayerCargo.new()

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

	# Fleet (starts with one ship — cargo lives on the ship)
	fleet = PlayerFleet.new()
	var starting_ship := FleetShip.from_ship_data(ShipRegistry.get_ship_data(&"fighter_mk1"))
	# Starting resources on the ship
	starting_ship.add_resource(&"ice", 10)
	starting_ship.add_resource(&"iron", 5)
	fleet.add_ship(starting_ship)
	fleet.active_ship_changed.connect(_on_active_ship_changed)

	# Sync economy mirror from active ship
	_sync_economy_resources()

	# Station services (unlock state per station)
	station_services = StationServices.new()
	if galaxy:
		station_services.init_center_systems(galaxy)


# =========================================================================
# Per-ship resource helpers (operate on active fleet ship)
# =========================================================================

func add_active_ship_resource(resource_id: StringName, amount: int) -> void:
	if fleet:
		var active := fleet.get_active()
		if active:
			active.add_resource(resource_id, amount)
			# Mirror to economy for HUD display
			if economy:
				economy.add_resource(resource_id, amount)
			return
	# Fallback: economy only
	if economy:
		economy.add_resource(resource_id, amount)


func spend_active_ship_resource(resource_id: StringName, amount: int) -> bool:
	if fleet:
		var active := fleet.get_active()
		if active:
			if not active.spend_resource(resource_id, amount):
				return false
			# Mirror to economy
			if economy:
				economy.add_resource(resource_id, -amount)
			return true
	return false


func get_active_ship_resource(resource_id: StringName) -> int:
	if fleet:
		var active := fleet.get_active()
		if active:
			return active.get_resource(resource_id)
	return 0


## Mirrors the active ship's resources onto PlayerEconomy.resources for HUD display.
func _sync_economy_resources() -> void:
	if economy == null:
		return
	var active: FleetShip = fleet.get_active() if fleet else null
	for res_id in PlayerEconomy.RESOURCE_DEFS:
		var ship_qty: int = active.get_resource(res_id) if active else 0
		var eco_qty: int = economy.resources.get(res_id, 0)
		if eco_qty != ship_qty:
			economy.resources[res_id] = ship_qty
			economy.resources_changed.emit(res_id, ship_qty)


func _on_active_ship_changed(_ship: FleetShip) -> void:
	_sync_economy_resources()


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

	# Credits (global)
	if economy:
		state["credits"] = economy.credits
		# Resources are now per-ship (inside fleet serialization).
		# Keep top-level empty for backward compat with backend.
		state["resources"] = []

	# Inventory
	if inventory:
		state["inventory"] = inventory.serialize()

	# Cargo — top-level empty, per-ship cargo is inside fleet
	state["cargo"] = []

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

	# Squadrons
	if fleet and not fleet.squadrons.is_empty():
		var sq_arr: Array = []
		for sq in fleet.squadrons:
			sq_arr.append(sq.serialize())
		state["squadrons"] = sq_arr
		state["next_squadron_id"] = fleet._next_squadron_id

	return state


func apply_save_state(state: Dictionary, player_ship: ShipController, system_transition: SystemTransition, _galaxy: GalaxyData, fleet_deployment_mgr: FleetDeploymentManager, commerce_manager: CommerceManager, squadron_mgr: Variant = null) -> void:
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

	# Credits (global)
	if economy:
		var current_credits: int = economy.credits
		if current_credits > 0:
			economy.add_credits(-current_credits)
		var saved_credits: int = int(state.get("credits", 1500))
		economy.add_credits(saved_credits)

		# Clear economy resources (will be synced from active ship below)
		for res_id in economy.resources.keys():
			economy.resources[res_id] = 0

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
		fleet.active_ship_changed.connect(_on_active_ship_changed)
		if fleet_deployment_mgr:
			fleet_deployment_mgr.initialize(fleet)
		if commerce_manager:
			commerce_manager.player_fleet = fleet

	# Squadrons
	var sq_data: Array = state.get("squadrons", [])
	if not sq_data.is_empty() and fleet:
		fleet.squadrons.clear()
		for sq_dict in sq_data:
			fleet.squadrons.append(Squadron.deserialize(sq_dict))
		fleet._next_squadron_id = int(state.get("next_squadron_id", fleet.squadrons.size() + 1))

	# Re-initialize squadron manager if fleet was replaced
	if squadron_mgr and fleet:
		squadron_mgr.initialize(fleet, fleet_deployment_mgr)

	# Migration: old saves stored cargo/resources at top-level — migrate to active ship
	var old_cargo: Array = state.get("cargo", [])
	var old_resources: Array = state.get("resources", [])
	if fleet:
		var active_fs := fleet.get_active()
		if active_fs:
			# Migrate top-level cargo items if ship has no per-ship cargo
			if not old_cargo.is_empty() and active_fs.cargo and active_fs.cargo.get_all().is_empty():
				for item in old_cargo:
					active_fs.cargo.add_item({
						"name": item.get("item_name", ""),
						"type": item.get("item_type", ""),
						"quantity": item.get("quantity", 1),
						"icon_color": item.get("icon_color", ""),
					})
			# Migrate top-level resources if ship has none
			if not old_resources.is_empty():
				var has_any: bool = false
				for res_id in active_fs.ship_resources:
					if active_fs.ship_resources[res_id] > 0:
						has_any = true
						break
				if not has_any:
					for res in old_resources:
						var res_id := StringName(str(res.get("resource_id", "")))
						var qty: int = int(res.get("quantity", 0))
						if res_id != &"" and qty > 0:
							active_fs.add_resource(res_id, qty)

	# Sync economy mirror from active ship resources
	_sync_economy_resources()

	print("SaveManager: State applied — ship=%s, system=%d, credits=%d" % [
		ship_id, sys_id, int(state.get("credits", 0))
	])
