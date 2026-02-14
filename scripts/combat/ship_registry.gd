class_name ShipRegistry
extends RefCounted

# =============================================================================
# Ship Registry - Static database of all ship definitions, keyed by ship_id.
# ship_class is just a category (Fighter, Frigate, etc.) — multiple ships per class.
# Hardpoints and collision are defined in ship scenes (scenes/ships/*.tscn),
# NOT here. ShipFactory reads them at spawn time.
# =============================================================================

static var _cache: Dictionary = {}


static func get_ship_data(ship_id: StringName) -> ShipData:
	if _cache.has(ship_id):
		return _cache[ship_id]

	var data: ShipData = null
	match ship_id:
		&"fighter_mk1": data = _build_fighter_mk1()
		&"frigate_mk1": data = _build_frigate_mk1()
		_:
			push_error("ShipRegistry: Unknown ship_id '%s'" % ship_id)
			return null

	_cache[ship_id] = data
	# Populate hardpoints from ship scene (needed for DATA-mode equipment screen)
	if data.hardpoints.is_empty() and data.ship_scene_path != "":
		data.hardpoints = ShipFactory.get_hardpoint_configs(ship_id)
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
		&"fighter_mk1", &"frigate_mk1",
	]
	for id in all_ids:
		if not _cache.has(id):
			get_ship_data(id)


# === Ship Builders ===

static func _build_fighter_mk1() -> ShipData:
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
	return d


static func _build_frigate_mk1() -> ShipData:
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
	return d


