class_name StationFactory
extends RefCounted

# =============================================================================
# Station Factory — Sets up hardpoints, WeaponManager, defense AI on a station.
# =============================================================================


static func setup_station(station, equipment) -> void:
	station.station_equipment = equipment

	var configs := StationHardpointConfig.get_configs(station.station_type)
	if configs.is_empty():
		return

	# Create hardpoint root
	var hp_root := Node3D.new()
	hp_root.name = "HardpointRoot"
	station.add_child(hp_root)

	# Create weapon manager (all weapons auto-track on stations)
	var wm := WeaponManager.new()
	wm.name = "WeaponManager"
	wm.all_weapons_are_turrets = true
	station.add_child(wm)
	wm.setup_hardpoints_from_configs(configs, station, hp_root)

	# Equip weapons from saved equipment
	wm.equip_weapons(equipment.weapons)
	station.weapon_manager = wm

	# Apply shield bonus to StructureHealth if shield equipped
	if equipment.shield_name != &"":
		var shield_res := ShieldRegistry.get_shield(equipment.shield_name)
		if shield_res and station.structure_health:
			station.structure_health.shield_max += shield_res.shield_hp
			station.structure_health.shield_current = station.structure_health.shield_max
			station.structure_health.shield_regen_rate += shield_res.regen_rate * 0.5

	# Create defense AI
	var defense_ai := StationDefenseAI.new()
	defense_ai.name = "StationDefenseAI"
	station.add_child(defense_ai)
	defense_ai.initialize(station, wm)
	station.defense_ai = defense_ai

	# Build visual service modules
	ServiceModuleBuilder.build_modules(station, station.station_type)
