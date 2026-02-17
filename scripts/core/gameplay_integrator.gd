class_name GameplayIntegrator
extends Node

# =============================================================================
# Gameplay Integrator — creates and wires new gameplay systems:
# Factions, Missions, Economy Simulator, POIs, Help & Mission Board screens.
# Single integration point — keeps GameManager clean.
# Child of GameManager, created after core systems + UI managers.
# =============================================================================

# Sub-systems (created and owned here)
var faction_manager: FactionManager
var mission_manager: MissionManager
var economy_sim: EconomySimulator
var poi_manager: POIManager
var event_manager: EventManager

# Screens (created and registered here)
var _help_screen: HelpScreen
var _mission_board_screen: MissionBoardScreen

# Injected refs (set in initialize)
var _screen_manager = null
var _notif: NotificationService = null
var _player_data = null


func initialize(refs: Dictionary) -> void:
	_screen_manager = refs.get("screen_manager")
	_notif = refs.get("notif")
	_player_data = refs.get("player_data")

	_create_subsystems()
	_register_screens()
	_wire_signals(refs)


# =============================================================================
# SETUP
# =============================================================================

func _create_subsystems() -> void:
	faction_manager = FactionManager.new()
	faction_manager.name = "FactionManager"
	add_child(faction_manager)

	mission_manager = MissionManager.new()
	mission_manager.name = "MissionManager"
	add_child(mission_manager)

	economy_sim = EconomySimulator.new()
	economy_sim.name = "EconomySimulator"
	add_child(economy_sim)

	poi_manager = POIManager.new()
	poi_manager.name = "POIManager"
	add_child(poi_manager)

	event_manager = EventManager.new()
	event_manager.name = "EventManager"
	add_child(event_manager)


func _register_screens() -> void:
	if _screen_manager == null:
		return

	_help_screen = HelpScreen.new()
	_help_screen.name = "HelpScreen"
	_screen_manager.register_screen("help", _help_screen)

	_mission_board_screen = MissionBoardScreen.new()
	_mission_board_screen.name = "MissionBoardScreen"
	_screen_manager.register_screen("mission_board", _mission_board_screen)


func _wire_signals(refs: Dictionary) -> void:
	# NPC kill → mission progress + reputation
	var encounter_mgr = refs.get("encounter_manager")
	if encounter_mgr:
		encounter_mgr.ship_destroyed_in_encounter.connect(_on_npc_destroyed)

	# Mission lifecycle
	mission_manager.mission_completed.connect(_on_mission_completed)

	# POI lifecycle
	poi_manager.poi_discovered.connect(_on_poi_discovered)
	poi_manager.poi_collected.connect(_on_poi_collected)

	# Station missions card
	var station_screen = refs.get("station_screen")
	if station_screen and station_screen.has_signal("missions_requested"):
		station_screen.missions_requested.connect(_on_missions_requested)

	# Mission board close → return to station terminal
	_mission_board_screen.mission_board_closed.connect(_on_mission_board_closed)

	# Random events
	event_manager.event_completed.connect(_on_event_completed)
	event_manager.event_started.connect(_on_event_started)


# =============================================================================
# SYSTEM TRANSITION HOOKS (called by GameManager)
# =============================================================================

func on_system_loaded(system_id: int, danger_level: int) -> void:
	if poi_manager:
		poi_manager.on_system_loaded(system_id, danger_level)
	if event_manager:
		event_manager.on_system_loaded(system_id, danger_level)


func on_system_unloading() -> void:
	if poi_manager:
		poi_manager.on_system_unloading()
	if event_manager:
		event_manager.on_system_unloading()


# =============================================================================
# NPC KILL HANDLING
# =============================================================================

func _on_npc_destroyed(ship_name: String) -> void:
	var npc_id := StringName(ship_name)
	var faction := _resolve_npc_faction(npc_id)
	var ship_class := _resolve_npc_ship_class(npc_id)
	var sys_id: int = GameManager.current_system_id_safe()

	# Update mission progress
	mission_manager.on_npc_killed(faction, sys_id, ship_class)

	# Update faction reputation
	_apply_kill_reputation(faction)


## Called by NetworkSyncManager when we (the local player) killed an NPC in multiplayer.
## Faction + ship_class are pre-resolved by the caller before LOD cleanup erases the data.
func on_npc_kill_credited(_npc_id_str: String, faction: StringName, ship_class: StringName = &"") -> void:
	var sys_id: int = GameManager.current_system_id_safe()
	mission_manager.on_npc_killed(faction, sys_id, ship_class)
	_apply_kill_reputation(faction)


func _resolve_npc_faction(npc_id: StringName) -> StringName:
	# Try LOD manager (ShipLODData stores faction)
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr and lod_mgr._ships.has(npc_id):
		return lod_mgr._ships[npc_id].faction
	# Fallback: NpcAuthority registry
	var npc_auth = GameManager.get_node_or_null("NpcAuthority")
	if npc_auth and npc_auth._npcs.has(npc_id):
		return StringName(npc_auth._npcs[npc_id].get("faction", "hostile"))
	return &"hostile"


func _resolve_npc_ship_class(npc_id: StringName) -> StringName:
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	if lod_mgr and lod_mgr._ships.has(npc_id):
		return lod_mgr._ships[npc_id].ship_class
	return &""


func _apply_kill_reputation(killed_faction: StringName) -> void:
	if faction_manager == null:
		return
	# Killing pirates/hostiles: small positive rep with major factions
	if killed_faction == &"pirate" or killed_faction == &"hostile":
		faction_manager.modify_reputation(&"nova_terra", 0.5)
		faction_manager.modify_reputation(&"kharsis", 0.5)
		faction_manager.modify_reputation(&"pirate", -2.0)
	elif killed_faction == &"nova_terra":
		faction_manager.modify_reputation(&"nova_terra", -3.0)
	elif killed_faction == &"kharsis":
		faction_manager.modify_reputation(&"kharsis", -3.0)


# =============================================================================
# MISSION HANDLERS
# =============================================================================

func _on_mission_completed(mission: MissionData) -> void:
	# Award credits
	if _player_data and _player_data.economy:
		_player_data.economy.add_credits(mission.reward_credits)

	# Award reputation
	if faction_manager and mission.faction_id != &"":
		faction_manager.modify_reputation(mission.faction_id, mission.reward_reputation)

	if _notif:
		_notif.toast("MISSION TERMINEE: %s [+%s CR]" % [mission.title, PlayerEconomy.format_credits(mission.reward_credits)])

	SaveManager.trigger_save("mission_completed")


func _on_missions_requested() -> void:
	_open_mission_board()


func _open_mission_board() -> void:
	if _mission_board_screen == null or _screen_manager == null:
		return

	var sys_id: int = GameManager.current_system_id_safe()
	var danger: int = _get_current_danger_level()
	var station_type: int = _get_docked_station_type()
	var faction_id: StringName = faction_manager.player_faction if faction_manager and faction_manager.player_faction != &"" else &"nova_terra"

	var available := MissionGenerator.generate_missions(sys_id, station_type, danger, faction_id)
	_mission_board_screen.setup(available, mission_manager)

	_screen_manager.close_screen("station")
	await get_tree().process_frame
	_screen_manager.open_screen("mission_board")


func _on_mission_board_closed() -> void:
	if GameManager.current_state != Constants.GameState.DOCKED:
		return
	if GameManager._docking_mgr:
		GameManager._docking_mgr.open_station_terminal()


# =============================================================================
# POI HANDLERS
# =============================================================================

func _on_poi_discovered(poi: POIData) -> void:
	if _notif:
		_notif.toast("POI DECOUVERT: " + poi.display_name)


func _on_poi_collected(poi: POIData) -> void:
	_apply_poi_rewards(poi.rewards)
	if _notif:
		_notif.toast("POI COLLECTE: " + poi.display_name)
	SaveManager.trigger_save("poi_collected")


func _apply_poi_rewards(rewards: Dictionary) -> void:
	if _player_data == null:
		return
	var credits: int = int(rewards.get("credits", 0))
	if credits > 0 and _player_data.economy:
		_player_data.economy.add_credits(credits)
	var reputation: Dictionary = rewards.get("reputation", {})
	if faction_manager:
		for fac_id in reputation:
			faction_manager.modify_reputation(StringName(fac_id), float(reputation[fac_id]))


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_event_started(evt: EventData) -> void:
	if _notif:
		_notif.toast("%s détecté dans le système!" % evt.get_display_name())


func _on_event_completed(evt: EventData) -> void:
	# Bonus credits for destroying the convoy leader
	var bonus: int = EventDefinitions.get_leader_bonus_credits(evt.tier)
	if _player_data and _player_data.economy:
		_player_data.economy.add_credits(bonus)

	# Pirate reputation penalty
	if faction_manager:
		faction_manager.modify_reputation(&"pirate", -3.0 * evt.tier)
		faction_manager.modify_reputation(&"nova_terra", 1.0 * evt.tier)
		faction_manager.modify_reputation(&"kharsis", 1.0 * evt.tier)

	if _notif:
		_notif.toast("%s éliminé! +%s CR" % [evt.get_display_name(), PlayerEconomy.format_credits(bonus)])


# =============================================================================
# SAVE / LOAD (called by SaveManager via GameManager)
# =============================================================================

func collect_save_state(state: Dictionary) -> void:
	if faction_manager:
		state["factions"] = faction_manager.serialize()
		state["faction_id"] = String(faction_manager.player_faction)
	if mission_manager:
		state["missions"] = mission_manager.serialize()
	if economy_sim:
		state["economy_sim"] = economy_sim.serialize()
	if poi_manager:
		state["pois"] = poi_manager.serialize()


func apply_save_state(state: Dictionary) -> void:
	if faction_manager and state.has("factions"):
		faction_manager.deserialize(state["factions"])
	if mission_manager and state.has("missions"):
		mission_manager.deserialize(state["missions"])
	if economy_sim and state.has("economy_sim"):
		economy_sim.deserialize(state["economy_sim"])
	if poi_manager and state.has("pois"):
		poi_manager.deserialize(state["pois"])


# =============================================================================
# HELPERS
# =============================================================================

func _get_current_danger_level() -> int:
	var st = GameManager._system_transition
	if st and GameManager._galaxy:
		var sys_dict: Dictionary = GameManager._galaxy.get_system(st.current_system_id)
		return int(sys_dict.get("danger_level", 1))
	return 1


func _get_docked_station_type() -> int:
	var dock_inst = GameManager._dock_instance
	if dock_inst == null:
		return 0
	var station_name: String = dock_inst.station_name if dock_inst else ""
	var stations := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	for ent in stations:
		if ent.get("name", "") == station_name:
			var extra: Dictionary = ent.get("extra", {})
			var type_str: String = extra.get("station_type", "repair")
			match type_str:
				"repair": return 0
				"trade": return 1
				"military": return 2
				"mining": return 3
	return 0
