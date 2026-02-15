class_name ShipChangeManager
extends Node

# =============================================================================
# Ship Change Manager — handles ship switching + rewiring ship-dependent systems.
# Child Node of GameManager.
# =============================================================================

signal ship_rebuilt(ship: ShipController)

# Injected refs
var player_ship: RigidBody3D = null
var main_scene: Node3D = null
var player_data: PlayerData = null
var mining_system: MiningSystem = null
var lod_manager: ShipLODManager = null
var ship_net_sync: ShipNetworkSync = null
var get_game_state: Callable


func rewire_ship_systems() -> void:
	var ship := player_ship as ShipController
	if ship == null:
		return

	# --- Signals ---
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health and not health.ship_destroyed.is_connected(_on_player_destroyed):
		health.ship_destroyed.connect(_on_player_destroyed)
	if not ship.autopilot_disengaged_by_player.is_connected(_on_autopilot_cancelled):
		ship.autopilot_disengaged_by_player.connect(_on_autopilot_cancelled)

	# --- HUD ---
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as FlightHUD
	if hud:
		hud.set_ship(ship)
		hud.set_health_system(health)
		hud.set_energy_system(ship.get_node_or_null("EnergySystem") as EnergySystem)
		hud.set_targeting_system(ship.get_node_or_null("TargetingSystem") as TargetingSystem)
		hud.set_weapon_manager(ship.get_node_or_null("WeaponManager") as WeaponManager)

	# --- Mining ---
	if mining_system:
		mining_system.set_weapon_manager(ship.get_node_or_null("WeaponManager") as WeaponManager)

	# --- LOD ---
	if lod_manager:
		var player_lod := lod_manager.get_ship_data(&"player_ship")
		if player_lod and ship.ship_data:
			player_lod.ship_id = ship.ship_data.ship_id
			player_lod.ship_class = ship.ship_data.ship_class

	# --- Network ---
	if ship_net_sync:
		ship_net_sync.reconnect_weapon_signal()

	ship_rebuilt.emit(ship)


# These thin stubs are connected by rewire_ship_systems to ship signals.
# The actual handlers are on GameManager (death_respawn_mgr, route_manager).
# We forward them via the ship_rebuilt signal chain — but for death and autopilot
# we need to emit upward.
var _on_destroyed_callback: Callable
var _on_autopilot_cancelled_callback: Callable

func _on_player_destroyed() -> void:
	if _on_destroyed_callback.is_valid():
		_on_destroyed_callback.call()

func _on_autopilot_cancelled() -> void:
	if _on_autopilot_cancelled_callback.is_valid():
		_on_autopilot_cancelled_callback.call()


## Force-rebuild the player ship for respawn (bypasses DOCKED state check).
## Used when the active ship is DESTROYED and we need to switch to another ship.
func rebuild_ship_for_respawn(fleet_index: int) -> void:
	if player_ship == null:
		return
	var fleet := player_data.fleet if player_data else null
	if fleet == null or fleet_index < 0 or fleet_index >= fleet.ships.size():
		return

	var fs := fleet.ships[fleet_index]
	var ship_id := fs.ship_id
	var data := ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("ShipChangeManager: Unknown ship_id '%s' for respawn" % ship_id)
		return

	var ship := player_ship as ShipController
	# Strip old components
	for comp_name in ["HealthSystem", "EnergySystem", "WeaponManager", "TargetingSystem", "EquipmentManager"]:
		var comp := ship.get_node_or_null(comp_name)
		if comp:
			ship.remove_child(comp)
			comp.free()
	var old_model := ship.get_node_or_null("ShipModel")
	if old_model:
		ship.remove_child(old_model)
		old_model.free()
	var old_col := ship.get_node_or_null("CollisionShape3D")
	if old_col:
		ship.remove_child(old_col)
		old_col.free()

	# Rebuild with new ship
	ShipFactory.setup_player_ship(ship_id, ship)

	# Equip loadout from FleetShip
	var wm := ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm and not fs.weapons.is_empty():
		wm.equip_weapons(fs.weapons)
	var em := ship.get_node_or_null("EquipmentManager") as EquipmentManager
	if em:
		em.remove_shield()
		em.remove_engine()
		for i in em.equipped_modules.size():
			em.remove_module(i)
		if fs.shield_name != &"":
			var shield_res := ShieldRegistry.get_shield(fs.shield_name)
			if shield_res:
				em.equip_shield(shield_res)
		if fs.engine_name != &"":
			var engine_res := EngineRegistry.get_engine(fs.engine_name)
			if engine_res:
				em.equip_engine(engine_res)
		for i in fs.modules.size():
			if fs.modules[i] != &"":
				var mod_res := ModuleRegistry.get_module(fs.modules[i])
				if mod_res:
					em.equip_module(i, mod_res)

	# Update fleet active index
	fleet.set_active(fleet_index)

	# Resync economy resources
	if player_data:
		player_data._sync_economy_resources()

	# Rewire
	rewire_ship_systems()

	# Notify multiplayer peers
	NetworkManager.local_ship_id = ship_id
	if NetworkManager.is_connected_to_server():
		if NetworkManager.is_host:
			if NetworkManager.peers.has(1):
				var my_state: NetworkState = NetworkManager.peers[1]
				my_state.ship_id = ship_id
				var sdata_net := ShipRegistry.get_ship_data(ship_id)
				my_state.ship_class = sdata_net.ship_class if sdata_net else &"Fighter"
			for pid in NetworkManager.peers:
				if pid == 1:
					continue
				NetworkManager._rpc_receive_player_ship_changed.rpc_id(pid, 1, String(ship_id))
		else:
			NetworkManager._rpc_player_ship_changed.rpc_id(1, String(ship_id))

	print("ShipChangeManager: Respawn rebuild -> '%s' (%s)" % [data.ship_name, ship_id])


func handle_ship_change(fleet_index: int) -> void:
	var state_val: int = get_game_state.call() if get_game_state.is_valid() else 0
	if state_val != Constants.GameState.DOCKED or player_ship == null:
		return
	var fleet := player_data.fleet if player_data else null
	if fleet == null or fleet_index < 0 or fleet_index >= fleet.ships.size():
		return
	if fleet_index == fleet.active_index:
		return

	var fs := fleet.ships[fleet_index]
	# Safety: only switch to ships docked at the same station
	var active_fs := fleet.get_active()
	if active_fs and fs.docked_station_id != active_fs.docked_station_id:
		push_warning("ShipChangeManager: Cannot switch to ship at different station")
		return
	var ship_id := fs.ship_id
	var data := ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("ShipChangeManager: Unknown ship_id '%s'" % ship_id)
		return

	var ship := player_ship as ShipController

	# Strip old combat components
	for comp_name in ["HealthSystem", "EnergySystem", "WeaponManager", "TargetingSystem", "EquipmentManager"]:
		var comp := ship.get_node_or_null(comp_name)
		if comp:
			ship.remove_child(comp)
			comp.free()

	# Strip old ShipModel and CollisionShape3D
	var old_model := ship.get_node_or_null("ShipModel")
	if old_model:
		ship.remove_child(old_model)
		old_model.free()
	var old_col := ship.get_node_or_null("CollisionShape3D")
	if old_col:
		ship.remove_child(old_col)
		old_col.free()

	# Rebuild with new ship
	ShipFactory.setup_player_ship(ship_id, ship)

	# Equip loadout from FleetShip (setup_player_ship applies defaults, strip them first)
	var wm := ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm and not fs.weapons.is_empty():
		wm.equip_weapons(fs.weapons)
	var em := ship.get_node_or_null("EquipmentManager") as EquipmentManager
	if em:
		# Strip defaults applied by setup_player_ship
		em.remove_shield()
		em.remove_engine()
		for i in em.equipped_modules.size():
			em.remove_module(i)
		# Re-equip from FleetShip loadout
		if fs.shield_name != &"":
			var shield_res := ShieldRegistry.get_shield(fs.shield_name)
			if shield_res:
				em.equip_shield(shield_res)
		if fs.engine_name != &"":
			var engine_res := EngineRegistry.get_engine(fs.engine_name)
			if engine_res:
				em.equip_engine(engine_res)
		for i in fs.modules.size():
			if fs.modules[i] != &"":
				var mod_res := ModuleRegistry.get_module(fs.modules[i])
				if mod_res:
					em.equip_module(i, mod_res)

	# Repair the new ship
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.hull_current = health.hull_max
		for i in health.shield_current.size():
			health.shield_current[i] = health.shield_max_per_facing

	# Mark old ship as docked at the current station before switching
	var old_fs := fleet.get_active()
	if old_fs:
		old_fs.docked_system_id = GameManager.current_system_id_safe()
		# Resolve station ID from DockInstance
		var dock_inst := GameManager.get_node_or_null("DockInstance") as DockInstance
		if dock_inst and dock_inst.station_name != "":
			var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
			for ent in stations:
				if ent.get("name", "") == dock_inst.station_name:
					old_fs.docked_station_id = ent.get("id", "")
					break

	# Update fleet active index
	fleet.set_active(fleet_index)

	# Resync economy resources mirror for new active ship
	if player_data:
		player_data._sync_economy_resources()

	# Rewire all ship-dependent systems
	rewire_ship_systems()

	# Notify multiplayer peers
	NetworkManager.local_ship_id = ship_id
	if NetworkManager.is_connected_to_server():
		if NetworkManager.is_host:
			if NetworkManager.peers.has(1):
				var my_state: NetworkState = NetworkManager.peers[1]
				my_state.ship_id = ship_id
				var sdata_net := ShipRegistry.get_ship_data(ship_id)
				my_state.ship_class = sdata_net.ship_class if sdata_net else &"Fighter"
			for pid in NetworkManager.peers:
				if pid == 1:
					continue
				NetworkManager._rpc_receive_player_ship_changed.rpc_id(pid, 1, String(ship_id))
		else:
			NetworkManager._rpc_player_ship_changed.rpc_id(1, String(ship_id))

	SaveManager.trigger_save("ship_changed")
	print("ShipChangeManager: Ship changed to '%s' (%s)" % [data.ship_name, ship_id])
