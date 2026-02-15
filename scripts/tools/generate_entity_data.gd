@tool
extends EditorScript

# =============================================================================
# Entity Data Generator (EditorScript — run via Ctrl+Shift+X in Script Editor)
# Generates .tres files for all ships, weapons, shields, engines, modules
# into data/ships/, data/weapons/, data/shields/, data/engines/, data/modules/
# =============================================================================


func _run() -> void:
	print("=== Entity Data Generator ===")
	_ensure_dirs()
	_generate_ships()
	_generate_weapons()
	_generate_shields()
	_generate_engines()
	_generate_modules()
	print("=== Done! All entity .tres files generated ===")


func _ensure_dirs() -> void:
	for dir_path in ["res://data/ships", "res://data/weapons", "res://data/shields", "res://data/engines", "res://data/modules"]:
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
			print("  Created directory: %s" % dir_path)


# =========================================================================
# SHIPS
# =========================================================================

func _generate_ships() -> void:
	_save_ship(_build_fighter_mk1())
	_save_ship(_build_corvette_mk1())
	_save_ship(_build_frigate_mk1())
	print("  Ships: 3 generated")


func _build_fighter_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"fighter_mk1"
	d.ship_name = &"Fighter Mk I"
	d.ship_class = &"Fighter"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.exhaust_scale = 0.8
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1"]
	d.hull_hp = 1000.0; d.shield_hp = 500.0; d.shield_regen_rate = 15.0; d.shield_regen_delay = 4.0
	d.shield_damage_bleedthrough = 0.1; d.armor_rating = 5.0
	d.mass = 50000.0
	d.accel_forward = 80.0; d.accel_backward = 50.0; d.accel_strafe = 40.0; d.accel_vertical = 40.0
	d.max_speed_normal = 300.0; d.max_speed_boost = 600.0; d.max_speed_cruise = 850_000.0
	d.rotation_pitch_speed = 30.0; d.rotation_yaw_speed = 25.0; d.rotation_roll_speed = 50.0
	d.max_speed_lateral = 150.0; d.max_speed_vertical = 150.0
	d.rotation_damp_min_factor = 0.15
	d.energy_capacity = 100.0; d.energy_regen_rate = 22.0; d.boost_energy_drain = 15.0
	d.ship_scene_path = "res://scenes/ships/fighter_mk1.tscn"
	d.shield_slot_size = "S"; d.engine_slot_size = "S"
	d.module_slots = ["S", "S"] as Array[String]
	d.sensor_range = 3000.0; d.engagement_range = 1500.0; d.disengage_range = 4000.0
	d.price = 30000
	d.cargo_capacity = 30
	# Data-driven fields
	d.default_shield = &"Bouclier Basique Mk1"
	d.default_engine = &"Propulseur Standard Mk1"
	d.default_modules = [&"Blindage Renforce", &"Condensateur d'Energie"]
	d.loot_credits_min = 150; d.loot_credits_max = 400
	d.loot_mat_count_min = 1; d.loot_mat_count_max = 2
	d.loot_weapon_part_chance = 0.0
	d.lod_combat_dps = 18.0
	d.npc_tier = 0
	d.sold_at_station_types = [&"repair", &"military", &"mining"]
	return d


func _build_corvette_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"corvette_mk1"
	d.ship_name = &"Corvette Mk I"
	d.ship_class = &"Corvette"
	d.model_path = "res://assets/models/corvette_mk1.glb"
	d.model_scale = 2.5
	d.exhaust_scale = 1.2
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Turret Mk1", &"Turret Mk1"]
	d.hull_hp = 2500.0; d.shield_hp = 1200.0; d.shield_regen_rate = 20.0; d.shield_regen_delay = 4.5
	d.shield_damage_bleedthrough = 0.08; d.armor_rating = 10.0
	d.mass = 120000.0
	d.accel_forward = 55.0; d.accel_backward = 35.0; d.accel_strafe = 25.0; d.accel_vertical = 25.0
	d.max_speed_normal = 220.0; d.max_speed_boost = 450.0; d.max_speed_cruise = 700_000.0
	d.rotation_pitch_speed = 20.0; d.rotation_yaw_speed = 16.0; d.rotation_roll_speed = 35.0
	d.max_speed_lateral = 100.0; d.max_speed_vertical = 100.0
	d.rotation_damp_min_factor = 0.12
	d.energy_capacity = 150.0; d.energy_regen_rate = 30.0; d.boost_energy_drain = 20.0
	d.ship_scene_path = "res://scenes/ships/corvette_mk1.tscn"
	d.shield_slot_size = "M"; d.engine_slot_size = "M"
	d.module_slots = ["S", "M", "M"] as Array[String]
	d.sensor_range = 3500.0; d.engagement_range = 1800.0; d.disengage_range = 4500.0
	d.price = 120000
	d.cargo_capacity = 60
	# Data-driven fields
	d.default_shield = &"Bouclier Renforce"
	d.default_engine = &"Propulseur de Combat"
	d.default_modules = [&"Blindage Renforce", &"Generateur Auxiliaire", &"Amplificateur de Bouclier"]
	d.loot_credits_min = 300; d.loot_credits_max = 800
	d.loot_mat_count_min = 2; d.loot_mat_count_max = 3
	d.loot_weapon_part_chance = 0.15
	d.lod_combat_dps = 40.0
	d.npc_tier = 1
	d.sold_at_station_types = [&"repair", &"military", &"mining"]
	return d


func _build_frigate_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"frigate_mk1"
	d.ship_name = &"Frigate Mk I"
	d.ship_class = &"Frigate"
	d.model_path = "res://assets/models/frigate_mk1.glb"
	d.model_scale = 1.0
	d.exhaust_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Turret Mk1", &"Turret Mk1", &"Turret Mk1", &"Turret Mk1", &"Turret Mk1", &"Turret Mk1"]
	d.hull_hp = 5000.0; d.shield_hp = 2500.0; d.shield_regen_rate = 30.0; d.shield_regen_delay = 6.0
	d.shield_damage_bleedthrough = 0.05; d.armor_rating = 20.0
	d.mass = 300000.0
	d.accel_forward = 35.0; d.accel_backward = 20.0; d.accel_strafe = 15.0; d.accel_vertical = 15.0
	d.max_speed_normal = 150.0; d.max_speed_boost = 300.0; d.max_speed_cruise = 560_000.0
	d.rotation_pitch_speed = 10.0; d.rotation_yaw_speed = 8.0; d.rotation_roll_speed = 15.0
	d.max_speed_lateral = 60.0; d.max_speed_vertical = 60.0
	d.rotation_damp_min_factor = 0.07
	d.energy_capacity = 200.0; d.energy_regen_rate = 40.0; d.boost_energy_drain = 28.0
	d.ship_scene_path = "res://scenes/ships/frigate_mk1.tscn"
	d.shield_slot_size = "L"; d.engine_slot_size = "L"
	d.module_slots = ["S", "M", "M", "L"] as Array[String]
	d.sensor_range = 4000.0; d.engagement_range = 2000.0; d.disengage_range = 5000.0
	d.price = 350000
	d.cargo_capacity = 100
	# Data-driven fields
	d.default_shield = &"Bouclier Lourd"
	d.default_engine = &"Propulseur Militaire"
	d.default_modules = [&"Blindage Renforce", &"Generateur Auxiliaire", &"Amplificateur de Bouclier", &"Systeme de Ciblage"]
	d.loot_credits_min = 500; d.loot_credits_max = 1200
	d.loot_mat_count_min = 3; d.loot_mat_count_max = 4
	d.loot_weapon_part_chance = 0.25
	d.lod_combat_dps = 65.0
	d.npc_tier = 2
	d.sold_at_station_types = [&"repair", &"military"]
	return d


func _save_ship(d: ShipData) -> void:
	var path := "res://data/ships/%s.tres" % String(d.ship_id)
	ResourceSaver.save(d, path)
	print("    Saved: %s" % path)


# =========================================================================
# WEAPONS
# =========================================================================

func _generate_weapons() -> void:
	_save_weapon(_build_laser_mk1())
	_save_weapon(_build_turret_mk1())
	_save_weapon(_build_mining_laser_mk1())
	_save_weapon(_build_mining_laser_mk2())
	print("  Weapons: 4 generated")


func _build_laser_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Laser Mk1"
	w.weapon_type = WeaponResource.WeaponType.LASER
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 25.0
	w.damage_type = &"thermal"
	w.fire_rate = 6.0
	w.energy_cost_per_shot = 4.0
	w.projectile_speed = 800.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(0.3, 0.7, 1.0)
	w.bolt_length = 4.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	w.weapon_model_scene = "res://scenes/weapons/models/laser_mk1.tscn"
	w.price = 500
	w.sold_at_station_types = [&"repair", &"military", &"mining"]
	return w


func _build_turret_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Turret Mk1"
	w.weapon_type = WeaponResource.WeaponType.TURRET
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 25.0
	w.damage_type = &"kinetic"
	w.fire_rate = 4.0
	w.energy_cost_per_shot = 4.0
	w.projectile_speed = 1000.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(1.0, 0.6, 0.2)
	w.bolt_length = 3.5
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	w.weapon_model_scene = "res://scenes/weapons/models/turret_mk1.tscn"
	w.price = 6000
	w.sold_at_station_types = [&"repair", &"military"]
	return w


func _build_mining_laser_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Mining Laser Mk1"
	w.weapon_type = WeaponResource.WeaponType.MINING_LASER
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 10.0
	w.damage_type = &"thermal"
	w.fire_rate = 2.0
	w.energy_cost_per_shot = 4.0
	w.projectile_speed = 0.0
	w.projectile_lifetime = 0.0
	w.bolt_color = Color(0.2, 1.0, 0.5)
	w.bolt_length = 0.0
	w.weapon_model_scene = "res://scenes/weapons/models/mining_laser_mk1.tscn"
	w.price = 1000
	w.sold_at_station_types = [&"repair", &"mining"]
	return w


func _build_mining_laser_mk2() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Mining Laser Mk2"
	w.weapon_type = WeaponResource.WeaponType.MINING_LASER
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 20.0
	w.damage_type = &"thermal"
	w.fire_rate = 2.0
	w.energy_cost_per_shot = 6.0
	w.projectile_speed = 0.0
	w.projectile_lifetime = 0.0
	w.bolt_color = Color(0.15, 0.9, 0.6)
	w.bolt_length = 0.0
	w.weapon_model_scene = "res://scenes/weapons/models/mining_laser_mk2.tscn"
	w.price = 4000
	w.sold_at_station_types = [&"repair", &"mining"]
	return w


func _save_weapon(w: WeaponResource) -> void:
	var safe_name := String(w.weapon_name).to_lower().replace(" ", "_")
	var path := "res://data/weapons/%s.tres" % safe_name
	ResourceSaver.save(w, path)
	print("    Saved: %s" % path)


# =========================================================================
# SHIELDS
# =========================================================================

func _generate_shields() -> void:
	_save_shield(_build_shield(&"Bouclier Basique Mk1", 0, 100.0, 12.0, 4.0, 0.12, 800,
		[&"repair", &"trade", &"mining"]))
	_save_shield(_build_shield(&"Bouclier Basique Mk2", 0, 150.0, 15.0, 3.5, 0.10, 2000,
		[&"repair", &"trade", &"mining"]))
	_save_shield(_build_shield(&"Bouclier Renforce", 1, 200.0, 18.0, 4.0, 0.08, 5000,
		[&"repair", &"trade", &"military"]))
	_save_shield(_build_shield(&"Bouclier Prismatique", 1, 150.0, 25.0, 2.5, 0.15, 8000,
		[&"repair", &"trade", &"military"]))
	_save_shield(_build_shield(&"Bouclier de Combat", 1, 250.0, 20.0, 5.0, 0.05, 12000,
		[&"repair", &"trade", &"military"]))
	_save_shield(_build_shield(&"Bouclier Lourd", 2, 375.0, 25.0, 6.0, 0.03, 25000,
		[&"repair", &"trade", &"military"]))
	_save_shield(_build_shield(&"Bouclier Experimental", 2, 300.0, 40.0, 2.0, 0.10, 40000,
		[&"repair", &"trade", &"military"]))
	print("  Shields: 7 generated")


func _build_shield(sname: StringName, slot: int, hp: float, regen: float,
		delay: float, bleed: float, sprice: int, sold_at: Array[StringName]) -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = sname
	s.slot_size = slot
	s.shield_hp_per_facing = hp
	s.regen_rate = regen
	s.regen_delay = delay
	s.bleedthrough = bleed
	s.price = sprice
	s.sold_at_station_types = sold_at
	return s


func _save_shield(s: ShieldResource) -> void:
	var safe_name := String(s.shield_name).to_lower().replace(" ", "_").replace("'", "")
	var path := "res://data/shields/%s.tres" % safe_name
	ResourceSaver.save(s, path)
	print("    Saved: %s" % path)


# =========================================================================
# ENGINES
# =========================================================================

func _generate_engines() -> void:
	_save_engine(_build_engine(&"Propulseur Standard Mk1", 0, 1.0, 1.0, 1.0, 1.0, 1.0, 600,
		[&"repair", &"trade", &"mining"]))
	_save_engine(_build_engine(&"Propulseur Standard Mk2", 0, 1.1, 1.05, 1.05, 1.05, 1.0, 1500,
		[&"repair", &"trade", &"mining"]))
	_save_engine(_build_engine(&"Propulseur de Combat", 1, 1.3, 1.0, 1.15, 0.9, 1.0, 6000,
		[&"repair", &"trade", &"military"]))
	_save_engine(_build_engine(&"Propulseur d'Exploration", 1, 0.9, 1.0, 1.0, 1.4, 0.9, 8000,
		[&"repair", &"trade"]))
	_save_engine(_build_engine(&"Propulseur de Course", 1, 1.15, 1.2, 1.0, 1.2, 1.2, 10000,
		[&"repair", &"trade", &"military"]))
	_save_engine(_build_engine(&"Propulseur Militaire", 2, 1.25, 1.15, 1.1, 1.1, 1.0, 20000,
		[&"repair", &"trade", &"military"]))
	_save_engine(_build_engine(&"Propulseur Experimental", 2, 1.35, 1.2, 1.15, 1.25, 1.3, 35000,
		[&"repair", &"trade", &"military"]))
	print("  Engines: 7 generated")


func _build_engine(ename: StringName, slot: int, accel: float, speed: float,
		rot: float, cruise: float, boost_drain: float, eprice: int,
		sold_at: Array[StringName]) -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = ename
	e.slot_size = slot
	e.accel_mult = accel
	e.speed_mult = speed
	e.rotation_mult = rot
	e.cruise_mult = cruise
	e.boost_drain_mult = boost_drain
	e.price = eprice
	e.sold_at_station_types = sold_at
	return e


func _save_engine(e: EngineResource) -> void:
	var safe_name := String(e.engine_name).to_lower().replace(" ", "_").replace("'", "")
	var path := "res://data/engines/%s.tres" % safe_name
	ResourceSaver.save(e, path)
	print("    Saved: %s" % path)


# =========================================================================
# MODULES
# =========================================================================

func _generate_modules() -> void:
	var m: ModuleResource

	m = ModuleResource.new()
	m.module_name = &"Blindage Renforce"; m.slot_size = 0
	m.module_type = ModuleResource.ModuleType.COQUE
	m.hull_bonus = 100.0; m.armor_bonus = 5.0; m.price = 1500
	m.sold_at_station_types = [&"repair", &"trade", &"military", &"mining"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Condensateur d'Energie"; m.slot_size = 0
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 20.0; m.energy_regen_bonus = 5.0; m.price = 2000
	m.sold_at_station_types = [&"repair", &"trade", &"mining"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Amplificateur de Bouclier"; m.slot_size = 0
	m.module_type = ModuleResource.ModuleType.BOUCLIER
	m.shield_regen_mult = 1.15; m.price = 2500
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Dissipateur Thermique"; m.slot_size = 0
	m.module_type = ModuleResource.ModuleType.ARME
	m.weapon_energy_mult = 0.85; m.price = 3000
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Scanner Ameliore"; m.slot_size = 1
	m.module_type = ModuleResource.ModuleType.SCANNER
	m.weapon_range_mult = 1.1; m.energy_regen_bonus = 3.0; m.price = 5000
	m.sold_at_station_types = [&"repair", &"trade"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Blindage Lourd"; m.slot_size = 1
	m.module_type = ModuleResource.ModuleType.COQUE
	m.hull_bonus = 250.0; m.armor_bonus = 10.0; m.price = 7000
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Generateur Auxiliaire"; m.slot_size = 1
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 50.0; m.energy_regen_bonus = 15.0; m.price = 8000
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Systeme de Ciblage"; m.slot_size = 1
	m.module_type = ModuleResource.ModuleType.ARME
	m.weapon_range_mult = 1.2; m.price = 10000
	m.sold_at_station_types = [&"repair", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Reacteur Auxiliaire"; m.slot_size = 2
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 100.0; m.energy_regen_bonus = 25.0; m.price = 20000
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	m = ModuleResource.new()
	m.module_name = &"Module de Renfort"; m.slot_size = 2
	m.module_type = ModuleResource.ModuleType.BOUCLIER
	m.shield_cap_mult = 1.3; m.price = 25000
	m.sold_at_station_types = [&"repair", &"trade", &"military"]
	_save_module(m)

	print("  Modules: 10 generated")


func _save_module(m: ModuleResource) -> void:
	var safe_name := String(m.module_name).to_lower().replace(" ", "_").replace("'", "")
	var path := "res://data/modules/%s.tres" % safe_name
	ResourceSaver.save(m, path)
	print("    Saved: %s" % path)
