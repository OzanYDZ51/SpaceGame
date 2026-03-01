class_name PlayerData
extends RefCounted

# =============================================================================
# Player Data — facade for all player-owned data objects.
# Owned by GameManager. Provides collect/apply for SaveManager.
# =============================================================================

var economy = null
var inventory = null
var cargo:
	get:
		if fleet:
			var active = fleet.get_active()
			if active and active.cargo:
				return active.cargo
		return null
var fleet = null
var station_services = null
var refinery_manager = null


func initialize(galaxy) -> void:
	# Economy (hardcoded starting values for testing)
	economy = PlayerEconomy.new()
	economy.add_credits(10000000)

	# Inventory with starting weapons + equipment
	inventory = PlayerInventory.new()
	inventory.add_weapon(&"Laser Mk1 S", 2)
	inventory.add_weapon(&"Turret Mk1 M", 1)
	inventory.add_weapon(&"Mining Laser S", 1)
	inventory.add_shield(&"Bouclier Basique Mk2", 1)
	inventory.add_shield(&"Bouclier Prismatique", 1)
	inventory.add_engine(&"Propulseur Standard Mk2", 1)
	inventory.add_engine(&"Propulseur de Combat", 1)
	inventory.add_module(&"Condensateur d'Energie", 1)
	inventory.add_module(&"Dissipateur Thermique", 1)
	inventory.add_module(&"Amplificateur de Bouclier", 1)

	# Fleet (starts with one ship — cargo lives on the ship)
	fleet = PlayerFleet.new()
	var starting_ship =FleetShip.from_ship_data(ShipRegistry.get_ship_data(Constants.DEFAULT_SHIP_ID))
	# Starting resources on the ship (testing — set directly, bypassing cargo clamp)
	starting_ship.ship_resources[&"ice"] = 500
	starting_ship.ship_resources[&"iron"] = 1000
	starting_ship.ship_resources[&"copper"] = 1000
	starting_ship.ship_resources[&"titanium"] = 1000
	starting_ship.ship_resources[&"gold"] = 500
	starting_ship.ship_resources[&"crystal"] = 500
	starting_ship.ship_resources[&"uranium"] = 500
	starting_ship.ship_resources[&"platinum"] = 500
	fleet.add_ship(starting_ship)
	fleet.active_ship_changed.connect(_on_active_ship_changed)

	# Sync economy mirror from active ship
	_sync_economy_resources()

	# Station services (unlock state per station)
	station_services = StationServices.new()
	if galaxy:
		station_services.init_center_systems(galaxy)

	# Refinery manager (station storage + queues)
	refinery_manager = RefineryManager.new()


# =========================================================================
# Per-ship resource helpers (operate on active fleet ship)
# =========================================================================

## Adds resource to active ship (clamped to cargo space). Returns quantity actually added.
func add_active_ship_resource(resource_id: StringName, amount: int) -> int:
	if fleet:
		var active = fleet.get_active()
		if active:
			var added: int = active.add_resource(resource_id, amount)
			# Mirror to economy for HUD display
			if economy and added > 0:
				economy.add_resource(resource_id, added)
			return added
	# Fallback: economy only
	if economy:
		economy.add_resource(resource_id, amount)
	return amount


func spend_active_ship_resource(resource_id: StringName, amount: int) -> bool:
	if fleet:
		var active = fleet.get_active()
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
		var active = fleet.get_active()
		if active:
			return active.get_resource(resource_id)
	return 0


## Mirrors the active ship's resources onto PlayerEconomy.resources for HUD display.
func _sync_economy_resources() -> void:
	if economy == null:
		return
	var active = fleet.get_active() if fleet else null
	for res_id in PlayerEconomy.RESOURCE_DEFS:
		var ship_qty: int = active.get_resource(res_id) if active else 0
		var eco_qty: int = economy.resources.get(res_id, 0)
		if eco_qty != ship_qty:
			economy.resources[res_id] = ship_qty
			economy.resources_changed.emit(res_id, ship_qty)


func _on_active_ship_changed(_ship) -> void:
	_sync_economy_resources()


func get_starting_fleet_ship():
	if fleet and fleet.ships.size() > 0:
		return fleet.ships[0]
	return null


func collect_save_state(player_ship, system_transition) -> Dictionary:
	var state: Dictionary = {}

	# Ship ID
	if player_ship:
		state["current_ship_id"] = str(player_ship.ship_data.ship_id if player_ship.ship_data else Constants.DEFAULT_SHIP_ID)

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
		var em = player_ship.get_node_or_null("EquipmentManager")
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

	# Refinery (station storages + queues)
	if refinery_manager:
		var ref_data =refinery_manager.serialize()
		if not ref_data.is_empty():
			state["refinery"] = ref_data

	# Player settings (audio + controls) for backend sync
	state["settings"] = OptionsScreen.collect_settings_dict()

	return state


func apply_save_state(state: Dictionary, player_ship, system_transition, _galaxy, fleet_deployment_mgr, commerce_manager, squadron_mgr = null) -> void:
	if state.is_empty():
		return

	GameManager._crash_log("apply_save_state: start keys=%d" % state.size())

	# Position — galaxy + system
	var gal_seed: int = int(state.get("galaxy_seed", Constants.galaxy_seed))
	if gal_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = gal_seed
		# Galaxy re-generation handled by caller (GameManager)

	var sys_id: int = int(state.get("system_id", 0))
	if system_transition and sys_id != system_transition.current_system_id:
		system_transition.jump_to_system(sys_id)
	GameManager._crash_log("apply_save_state: system jump done")

	# Position — restore exact saved universe coordinates.
	# Check for collision with planets/stations and offset if inside one.
	if player_ship and state.has("pos_x"):
		var abs_x: float = float(state.get("pos_x", 0.0))
		var abs_y: float = float(state.get("pos_y", 0.0))
		var abs_z: float = float(state.get("pos_z", 0.0))
		var spawn_pos: Vector3 = FloatingOrigin.to_local_pos([abs_x, abs_y, abs_z])

		# Check planet collisions — don't spawn inside a planet
		var sys_data = system_transition.current_system_data if system_transition else null
		if sys_data:
			for planet in sys_data.planets:
				var p_angle: float = EntityRegistrySystem.compute_orbital_angle(
					planet.orbital_angle, planet.orbital_period)
				var p_x: float = cos(p_angle) * planet.orbital_radius
				var p_z: float = sin(p_angle) * planet.orbital_radius
				var p_local: Vector3 = FloatingOrigin.to_local_pos([p_x, 0.0, p_z])
				var safe_r: float = planet.get_render_radius() + 500.0
				var dist: float = spawn_pos.distance_to(p_local)
				if dist < safe_r:
					var dir: Vector3 = (spawn_pos - p_local)
					if dir.length_squared() < 1.0:
						dir = Vector3.FORWARD
					spawn_pos = p_local + dir.normalized() * (planet.get_render_radius() + 1000.0)

			# Check station collisions (200m safe radius)
			for st in sys_data.stations:
				var st_angle: float = EntityRegistrySystem.compute_orbital_angle(
					st.orbital_angle, st.orbital_period)
				var st_x: float = cos(st_angle) * st.orbital_radius
				var st_z: float = sin(st_angle) * st.orbital_radius
				var st_local: Vector3 = FloatingOrigin.to_local_pos([st_x, 0.0, st_z])
				if spawn_pos.distance_to(st_local) < 200.0:
					var dir: Vector3 = (spawn_pos - st_local)
					if dir.length_squared() < 1.0:
						dir = Vector3.FORWARD
					spawn_pos = st_local + dir.normalized() * 500.0

		player_ship.global_position = spawn_pos
	GameManager._crash_log("apply_save_state: position restored")

	# Rotation
	if player_ship and state.has("rotation_x"):
		player_ship.rotation = Vector3(
			float(state.get("rotation_x", 0.0)),
			float(state.get("rotation_y", 0.0)),
			float(state.get("rotation_z", 0.0)),
		)

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
	GameManager._crash_log("apply_save_state: credits done")

	# Inventory
	if inventory:
		GameManager._crash_log("apply_save_state: clearing inventory...")
		inventory.clear_all()
		var items: Array = state.get("inventory", []) if state.get("inventory") is Array else []
		GameManager._crash_log("apply_save_state: inventory items count=%d" % items.size())
		for idx in items.size():
			var item = items[idx]
			GameManager._crash_log("apply_save_state: item[%d] = %s" % [idx, str(item).left(100)])
			var category: String = item.get("category", "")
			var item_name = StringName(str(item.get("item_name", "")))
			var qty: int = int(item.get("quantity", 1))
			match category:
				"weapon": inventory.add_weapon(item_name, qty)
				"shield": inventory.add_shield(item_name, qty)
				"engine": inventory.add_engine(item_name, qty)
				"module": inventory.add_module(item_name, qty)
				"ammo": inventory.add_ammo(item_name, qty)

	GameManager._crash_log("apply_save_state: inventory done")
	# Equipment
	var equipment: Dictionary = state.get("equipment", {}) if state.get("equipment") is Dictionary else {}
	if not equipment.is_empty() and player_ship:
		var em = player_ship.get_node_or_null("EquipmentManager")
		if em:
			var shield_name = equipment.get("shield_name", null)
			if shield_name != null and str(shield_name) != "":
				var shield_res =ShieldRegistry.get_shield(StringName(str(shield_name)))
				if shield_res:
					em.equip_shield(shield_res)
			var engine_name = equipment.get("engine_name", null)
			if engine_name != null and str(engine_name) != "":
				var engine_res =EngineRegistry.get_engine(StringName(str(engine_name)))
				if engine_res:
					em.equip_engine(engine_res)
			var saved_modules: Array = equipment.get("modules", []) if equipment.get("modules") is Array else []
			for i in saved_modules.size():
				if i >= em.equipped_modules.size():
					break
				var mod_name: String = str(saved_modules[i])
				if mod_name != "":
					var mod_res =ModuleRegistry.get_module(StringName(mod_name))
					if mod_res:
						em.equip_module(i, mod_res)
		var wm = player_ship.get_node_or_null("WeaponManager")
		if wm:
			var hardpoints: Array = equipment.get("hardpoints", []) if equipment.get("hardpoints") is Array else []
			var weapon_names: Array[StringName] = []
			for wp_name in hardpoints:
				weapon_names.append(StringName(str(wp_name)) if wp_name != null and str(wp_name) != "" else &"")
			if not weapon_names.is_empty():
				wm.equip_weapons(weapon_names)

	GameManager._crash_log("apply_save_state: equipment done")
	# Station services
	var svc_data: Array = state.get("station_services", []) if state.get("station_services") is Array else []
	if not svc_data.is_empty() and station_services:
		station_services.deserialize(svc_data)

	GameManager._crash_log("apply_save_state: station_services done")
	# Fleet
	var fleet_data: Array = state.get("fleet", []) if state.get("fleet") is Array else []
	if not fleet_data.is_empty():
		fleet = PlayerFleet.deserialize(fleet_data)
		fleet.active_ship_changed.connect(_on_active_ship_changed)
		if fleet_deployment_mgr:
			fleet_deployment_mgr.initialize(fleet)
		if commerce_manager:
			commerce_manager.player_fleet = fleet

	GameManager._crash_log("apply_save_state: fleet deserialized")
	# Squadrons
	var sq_data: Array = state.get("squadrons", []) if state.get("squadrons") is Array else []
	if not sq_data.is_empty() and fleet:
		fleet.squadrons.clear()
		for sq_dict in sq_data:
			fleet.squadrons.append(Squadron.deserialize(sq_dict))
		fleet._next_squadron_id = int(state.get("next_squadron_id", fleet.squadrons.size() + 1))

	# Re-initialize squadron manager if fleet was replaced
	if squadron_mgr and fleet:
		squadron_mgr.initialize(fleet, fleet_deployment_mgr)

	GameManager._crash_log("apply_save_state: squadrons done")
	# Refinery
	var refinery_data: Dictionary = state.get("refinery", {}) if state.get("refinery") is Dictionary else {}
	if not refinery_data.is_empty() and refinery_manager:
		refinery_manager.deserialize(refinery_data)

	GameManager._crash_log("apply_save_state: refinery done")
	# Player settings (audio + controls) from backend
	var settings_data: Dictionary = state.get("settings", {}) if state.get("settings") is Dictionary else {}
	if not settings_data.is_empty():
		OptionsScreen.apply_settings_dict(settings_data)

	GameManager._crash_log("apply_save_state: settings done")
	# Migration: old saves stored cargo/resources at top-level — migrate to active ship
	var old_cargo: Array = state.get("cargo", []) if state.get("cargo") is Array else []
	var old_resources: Array = state.get("resources", []) if state.get("resources") is Array else []
	if fleet:
		var active_fs = fleet.get_active()
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
						var res_id =StringName(str(res.get("resource_id", "")))
						var qty: int = int(res.get("quantity", 0))
						if res_id != &"" and qty > 0:
							# Migration: set directly, bypassing cargo clamp
							if res_id not in active_fs.ship_resources:
								active_fs.ship_resources[res_id] = 0
							active_fs.ship_resources[res_id] += qty

	GameManager._crash_log("apply_save_state: migration done")
	# Sync economy mirror from active ship resources
	_sync_economy_resources()
	GameManager._crash_log("apply_save_state: DONE")
