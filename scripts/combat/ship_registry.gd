class_name ShipRegistry
extends RefCounted

# =============================================================================
# Ship Registry - Static database of all ship definitions, keyed by ship_id.
# ship_class is just a category (Scout, Fighter, etc.) — multiple ships per class.
# Hardpoints and collision are defined in ship scenes (scenes/ships/*.tscn),
# NOT here. ShipFactory reads them at spawn time.
# =============================================================================

static var _cache: Dictionary = {}


static func get_ship_data(ship_id: StringName) -> ShipData:
	if _cache.has(ship_id):
		return _cache[ship_id]

	var data: ShipData = null
	match ship_id:
		&"scout_mk1": data = _build_scout_mk1()
		&"interceptor_mk1": data = _build_interceptor_mk1()
		&"fighter_mk1": data = _build_fighter_mk1()
		&"bomber_mk1": data = _build_bomber_mk1()
		&"corvette_mk1": data = _build_corvette_mk1()
		&"frigate_mk1": data = _build_frigate_mk1()
		&"cruiser_mk1": data = _build_cruiser_mk1()
		_:
			push_error("ShipRegistry: Unknown ship_id '%s'" % ship_id)
			return null

	_cache[ship_id] = data
	return data


## Returns all registered ship_ids for a given class category.
static func get_ships_by_class(ship_class: StringName) -> Array[StringName]:
	_ensure_all_loaded()
	var result: Array[StringName] = []
	for id: StringName in _cache:
		var d: ShipData = _cache[id]
		if d.ship_class == ship_class:
			result.append(id)
	return result


## Returns all registered ship_ids.
static func get_all_ship_ids() -> Array[StringName]:
	_ensure_all_loaded()
	var result: Array[StringName] = []
	for id: StringName in _cache:
		result.append(id)
	return result


static func _ensure_all_loaded() -> void:
	# Force-load every ship so iteration works
	var all_ids: Array[StringName] = [
		&"scout_mk1", &"interceptor_mk1", &"fighter_mk1", &"bomber_mk1",
		&"corvette_mk1", &"frigate_mk1", &"cruiser_mk1",
	]
	for id in all_ids:
		if not _cache.has(id):
			get_ship_data(id)


# === Ship Builders ===

static func _build_scout_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"scout_mk1"
	d.ship_name = &"Scout Mk I"
	d.ship_class = &"Scout"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1"]
	d.hull_hp = 400.0; d.shield_hp = 200.0; d.shield_regen_rate = 10.0; d.shield_regen_delay = 3.0
	d.shield_damage_bleedthrough = 0.15; d.armor_rating = 2.0
	d.mass = 20000.0
	d.accel_forward = 120.0; d.accel_backward = 80.0; d.accel_strafe = 70.0; d.accel_vertical = 70.0
	d.max_speed_normal = 400.0; d.max_speed_boost = 700.0; d.max_speed_cruise = 58000.0
	d.rotation_pitch_speed = 50.0; d.rotation_yaw_speed = 45.0; d.rotation_roll_speed = 70.0
	d.max_speed_lateral = 200.0; d.max_speed_vertical = 200.0
	d.rotation_damp_min_factor = 0.20
	d.energy_capacity = 80.0; d.energy_regen_rate = 18.0; d.boost_energy_drain = 12.0
	d.ship_scene_path = "res://scenes/ships/scout_mk1.tscn"
	d.shield_slot_size = "S"; d.engine_slot_size = "S"
	d.module_slots = ["S"] as Array[String]
	return d


static func _build_interceptor_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"interceptor_mk1"
	d.ship_name = &"Interceptor Mk I"
	d.ship_class = &"Interceptor"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Plasma Cannon"]
	d.hull_hp = 600.0; d.shield_hp = 350.0; d.shield_regen_rate = 12.0; d.shield_regen_delay = 3.5
	d.shield_damage_bleedthrough = 0.12; d.armor_rating = 3.0
	d.mass = 30000.0
	d.accel_forward = 100.0; d.accel_backward = 65.0; d.accel_strafe = 55.0; d.accel_vertical = 55.0
	d.max_speed_normal = 380.0; d.max_speed_boost = 680.0; d.max_speed_cruise = 53000.0
	d.rotation_pitch_speed = 45.0; d.rotation_yaw_speed = 40.0; d.rotation_roll_speed = 65.0
	d.max_speed_lateral = 180.0; d.max_speed_vertical = 180.0
	d.rotation_damp_min_factor = 0.18
	d.energy_capacity = 90.0; d.energy_regen_rate = 20.0; d.boost_energy_drain = 13.0
	d.ship_scene_path = "res://scenes/ships/interceptor_mk1.tscn"
	d.shield_slot_size = "S"; d.engine_slot_size = "S"
	d.module_slots = ["S", "M"] as Array[String]
	return d


static func _build_fighter_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"fighter_mk1"
	d.ship_name = &"Fighter Mk I"
	d.ship_class = &"Fighter"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1"]
	d.hull_hp = 1000.0; d.shield_hp = 500.0; d.shield_regen_rate = 15.0; d.shield_regen_delay = 4.0
	d.shield_damage_bleedthrough = 0.1; d.armor_rating = 5.0
	d.mass = 50000.0
	d.accel_forward = 80.0; d.accel_backward = 50.0; d.accel_strafe = 40.0; d.accel_vertical = 40.0
	d.max_speed_normal = 300.0; d.max_speed_boost = 600.0; d.max_speed_cruise = 50000.0
	d.rotation_pitch_speed = 30.0; d.rotation_yaw_speed = 25.0; d.rotation_roll_speed = 50.0
	d.max_speed_lateral = 150.0; d.max_speed_vertical = 150.0
	d.rotation_damp_min_factor = 0.15
	d.energy_capacity = 100.0; d.energy_regen_rate = 22.0; d.boost_energy_drain = 15.0
	d.ship_scene_path = "res://scenes/ships/fighter_mk1.tscn"
	d.shield_slot_size = "S"; d.engine_slot_size = "S"
	d.module_slots = ["S", "S"] as Array[String]
	return d


static func _build_bomber_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"bomber_mk1"
	d.ship_name = &"Bomber Mk I"
	d.ship_class = &"Bomber"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Plasma Cannon", &"Plasma Cannon", &"Torpedo"]
	d.hull_hp = 1200.0; d.shield_hp = 400.0; d.shield_regen_rate = 12.0; d.shield_regen_delay = 4.5
	d.shield_damage_bleedthrough = 0.1; d.armor_rating = 8.0
	d.mass = 60000.0
	d.accel_forward = 60.0; d.accel_backward = 35.0; d.accel_strafe = 30.0; d.accel_vertical = 30.0
	d.max_speed_normal = 220.0; d.max_speed_boost = 450.0; d.max_speed_cruise = 46000.0
	d.rotation_pitch_speed = 20.0; d.rotation_yaw_speed = 18.0; d.rotation_roll_speed = 35.0
	d.max_speed_lateral = 100.0; d.max_speed_vertical = 100.0
	d.rotation_damp_min_factor = 0.10
	d.energy_capacity = 120.0; d.energy_regen_rate = 25.0; d.boost_energy_drain = 18.0
	d.ship_scene_path = "res://scenes/ships/bomber_mk1.tscn"
	d.shield_slot_size = "M"; d.engine_slot_size = "M"
	d.module_slots = ["S", "M"] as Array[String]
	return d


static func _build_corvette_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"corvette_mk1"
	d.ship_name = &"Corvette Mk I"
	d.ship_class = &"Corvette"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Laser Mk2", &"Laser Mk2", &"Heavy Plasma"]
	d.hull_hp = 2500.0; d.shield_hp = 1200.0; d.shield_regen_rate = 20.0; d.shield_regen_delay = 5.0
	d.shield_damage_bleedthrough = 0.08; d.armor_rating = 12.0
	d.mass = 120000.0
	d.accel_forward = 50.0; d.accel_backward = 30.0; d.accel_strafe = 25.0; d.accel_vertical = 25.0
	d.max_speed_normal = 200.0; d.max_speed_boost = 400.0; d.max_speed_cruise = 42000.0
	d.rotation_pitch_speed = 15.0; d.rotation_yaw_speed = 12.0; d.rotation_roll_speed = 25.0
	d.max_speed_lateral = 80.0; d.max_speed_vertical = 80.0
	d.rotation_damp_min_factor = 0.08
	d.energy_capacity = 150.0; d.energy_regen_rate = 30.0; d.boost_energy_drain = 22.0
	d.ship_scene_path = "res://scenes/ships/corvette_mk1.tscn"
	d.shield_slot_size = "M"; d.engine_slot_size = "M"
	d.module_slots = ["S", "M", "M"] as Array[String]
	return d


static func _build_frigate_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"frigate_mk1"
	d.ship_name = &"Frigate Mk I"
	d.ship_class = &"Frigate"
	d.model_path = "res://assets/models/frigate_mk1.glb"
	d.model_scale = 1.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Laser Mk2", &"Laser Mk2", &"Plasma Cannon", &"Plasma Cannon", &"Railgun", &"Railgun"]
	d.hull_hp = 5000.0; d.shield_hp = 2500.0; d.shield_regen_rate = 30.0; d.shield_regen_delay = 6.0
	d.shield_damage_bleedthrough = 0.05; d.armor_rating = 20.0
	d.mass = 300000.0
	d.accel_forward = 35.0; d.accel_backward = 20.0; d.accel_strafe = 15.0; d.accel_vertical = 15.0
	d.max_speed_normal = 150.0; d.max_speed_boost = 300.0; d.max_speed_cruise = 33000.0
	d.rotation_pitch_speed = 10.0; d.rotation_yaw_speed = 8.0; d.rotation_roll_speed = 15.0
	d.max_speed_lateral = 60.0; d.max_speed_vertical = 60.0
	d.rotation_damp_min_factor = 0.07
	d.energy_capacity = 200.0; d.energy_regen_rate = 40.0; d.boost_energy_drain = 28.0
	d.ship_scene_path = "res://scenes/ships/frigate_mk1.tscn"
	d.shield_slot_size = "L"; d.engine_slot_size = "L"
	d.module_slots = ["S", "M", "M", "L"] as Array[String]
	return d


static func _build_cruiser_mk1() -> ShipData:
	var d := ShipData.new()
	d.ship_id = &"cruiser_mk1"
	d.ship_name = &"Cruiser Mk I"
	d.ship_class = &"Cruiser"
	d.model_path = "res://assets/models/tie.glb"
	d.model_scale = 2.0
	d.default_loadout = [&"Laser Mk1", &"Laser Mk1", &"Laser Mk1", &"Laser Mk1", &"Laser Mk2", &"Laser Mk2", &"Plasma Cannon", &"Plasma Cannon", &"Heavy Plasma", &"Railgun", &"Railgun"]
	d.hull_hp = 10000.0; d.shield_hp = 5000.0; d.shield_regen_rate = 50.0; d.shield_regen_delay = 8.0
	d.shield_damage_bleedthrough = 0.03; d.armor_rating = 35.0
	d.mass = 800000.0
	d.accel_forward = 20.0; d.accel_backward = 12.0; d.accel_strafe = 10.0; d.accel_vertical = 10.0
	d.max_speed_normal = 100.0; d.max_speed_boost = 200.0; d.max_speed_cruise = 25000.0
	d.rotation_pitch_speed = 6.0; d.rotation_yaw_speed = 5.0; d.rotation_roll_speed = 10.0
	d.max_speed_lateral = 40.0; d.max_speed_vertical = 40.0
	d.rotation_damp_min_factor = 0.06
	d.energy_capacity = 300.0; d.energy_regen_rate = 60.0; d.boost_energy_drain = 35.0
	d.ship_scene_path = "res://scenes/ships/cruiser_mk1.tscn"
	d.shield_slot_size = "L"; d.engine_slot_size = "L"
	d.module_slots = ["S", "S", "M", "M", "L"] as Array[String]
	return d
