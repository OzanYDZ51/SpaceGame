class_name ShipRegistry
extends RefCounted

# =============================================================================
# Ship Registry - Static database of all ship class definitions
# =============================================================================

static var _cache: Dictionary = {}


static func get_ship_data(ship_class: StringName) -> ShipData:
	if _cache.has(ship_class):
		return _cache[ship_class]

	var data: ShipData = null
	match ship_class:
		&"Scout": data = _build_scout()
		&"Interceptor": data = _build_interceptor()
		&"Fighter": data = _build_fighter()
		&"Bomber": data = _build_bomber()
		&"Corvette": data = _build_corvette()
		&"Frigate": data = _build_frigate()
		&"Cruiser": data = _build_cruiser()
		_:
			push_error("ShipRegistry: Unknown ship class '%s'" % ship_class)
			return null

	_cache[ship_class] = data
	return data


# === Ship Builders ===

static func _build_scout() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Scout Mk I"
	d.ship_class = &"Scout"
	d.hull_hp = 400.0; d.shield_hp = 200.0; d.shield_regen_rate = 10.0; d.shield_regen_delay = 3.0
	d.shield_damage_bleedthrough = 0.15; d.armor_rating = 2.0
	d.mass = 20000.0
	d.accel_forward = 120.0; d.accel_backward = 80.0; d.accel_strafe = 70.0; d.accel_vertical = 70.0
	d.max_speed_normal = 400.0; d.max_speed_boost = 700.0; d.max_speed_cruise = 3500.0
	d.rotation_pitch_speed = 50.0; d.rotation_yaw_speed = 45.0; d.rotation_roll_speed = 70.0
	d.max_speed_lateral = 200.0; d.max_speed_vertical = 200.0
	d.rotation_damp_min_factor = 0.20
	d.energy_capacity = 80.0; d.energy_regen_rate = 18.0; d.boost_energy_drain = 12.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-6.0, -1.0, -18.0), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(6.0, -1.0, -18.0), direction = Vector3.FORWARD},
	]
	return d


static func _build_interceptor() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Interceptor Mk I"
	d.ship_class = &"Interceptor"
	d.hull_hp = 600.0; d.shield_hp = 350.0; d.shield_regen_rate = 12.0; d.shield_regen_delay = 3.5
	d.shield_damage_bleedthrough = 0.12; d.armor_rating = 3.0
	d.mass = 30000.0
	d.accel_forward = 100.0; d.accel_backward = 65.0; d.accel_strafe = 55.0; d.accel_vertical = 55.0
	d.max_speed_normal = 380.0; d.max_speed_boost = 680.0; d.max_speed_cruise = 3200.0
	d.rotation_pitch_speed = 45.0; d.rotation_yaw_speed = 40.0; d.rotation_roll_speed = 65.0
	d.max_speed_lateral = 180.0; d.max_speed_vertical = 180.0
	d.rotation_damp_min_factor = 0.18
	d.energy_capacity = 90.0; d.energy_regen_rate = 20.0; d.boost_energy_drain = 13.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-8.0, -1.0, -20.0), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(8.0, -1.0, -20.0), direction = Vector3.FORWARD},
		{id = 2, size = "M", position = Vector3(0.0, -2.0, -16.0), direction = Vector3.FORWARD},
	]
	return d


static func _build_fighter() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Fighter Mk I"
	d.ship_class = &"Fighter"
	d.hull_hp = 1000.0; d.shield_hp = 500.0; d.shield_regen_rate = 15.0; d.shield_regen_delay = 4.0
	d.shield_damage_bleedthrough = 0.1; d.armor_rating = 5.0
	d.mass = 50000.0
	d.accel_forward = 80.0; d.accel_backward = 50.0; d.accel_strafe = 40.0; d.accel_vertical = 40.0
	d.max_speed_normal = 300.0; d.max_speed_boost = 600.0; d.max_speed_cruise = 3000.0
	d.rotation_pitch_speed = 30.0; d.rotation_yaw_speed = 25.0; d.rotation_roll_speed = 50.0
	d.max_speed_lateral = 150.0; d.max_speed_vertical = 150.0
	d.rotation_damp_min_factor = 0.15
	d.energy_capacity = 100.0; d.energy_regen_rate = 22.0; d.boost_energy_drain = 15.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-0.3, 0.0, -1.5), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(0.3, 0.0, -1.5), direction = Vector3.FORWARD},
	]
	return d


static func _build_bomber() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Bomber Mk I"
	d.ship_class = &"Bomber"
	d.hull_hp = 1200.0; d.shield_hp = 400.0; d.shield_regen_rate = 12.0; d.shield_regen_delay = 4.5
	d.shield_damage_bleedthrough = 0.1; d.armor_rating = 8.0
	d.mass = 60000.0
	d.accel_forward = 60.0; d.accel_backward = 35.0; d.accel_strafe = 30.0; d.accel_vertical = 30.0
	d.max_speed_normal = 220.0; d.max_speed_boost = 450.0; d.max_speed_cruise = 2800.0
	d.rotation_pitch_speed = 20.0; d.rotation_yaw_speed = 18.0; d.rotation_roll_speed = 35.0
	d.max_speed_lateral = 100.0; d.max_speed_vertical = 100.0
	d.rotation_damp_min_factor = 0.10
	d.energy_capacity = 120.0; d.energy_regen_rate = 25.0; d.boost_energy_drain = 18.0
	d.hardpoints = [
		{id = 0, size = "M", position = Vector3(-12.0, -3.0, -22.0), direction = Vector3.FORWARD},
		{id = 1, size = "M", position = Vector3(12.0, -3.0, -22.0), direction = Vector3.FORWARD},
		{id = 2, size = "L", position = Vector3(0.0, -4.0, -18.0), direction = Vector3.FORWARD},
	]
	return d


static func _build_corvette() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Corvette Mk I"
	d.ship_class = &"Corvette"
	d.hull_hp = 2500.0; d.shield_hp = 1200.0; d.shield_regen_rate = 20.0; d.shield_regen_delay = 5.0
	d.shield_damage_bleedthrough = 0.08; d.armor_rating = 12.0
	d.mass = 120000.0
	d.accel_forward = 50.0; d.accel_backward = 30.0; d.accel_strafe = 25.0; d.accel_vertical = 25.0
	d.max_speed_normal = 200.0; d.max_speed_boost = 400.0; d.max_speed_cruise = 2500.0
	d.rotation_pitch_speed = 15.0; d.rotation_yaw_speed = 12.0; d.rotation_roll_speed = 25.0
	d.max_speed_lateral = 80.0; d.max_speed_vertical = 80.0
	d.rotation_damp_min_factor = 0.08
	d.energy_capacity = 150.0; d.energy_regen_rate = 30.0; d.boost_energy_drain = 22.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-20.0, 2.0, -30.0), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(20.0, 2.0, -30.0), direction = Vector3.FORWARD},
		{id = 2, size = "M", position = Vector3(-14.0, -2.0, -25.0), direction = Vector3.FORWARD},
		{id = 3, size = "M", position = Vector3(14.0, -2.0, -25.0), direction = Vector3.FORWARD},
		{id = 4, size = "L", position = Vector3(0.0, -3.0, -20.0), direction = Vector3.FORWARD},
	]
	return d


static func _build_frigate() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Frigate Mk I"
	d.ship_class = &"Frigate"
	d.hull_hp = 5000.0; d.shield_hp = 2500.0; d.shield_regen_rate = 30.0; d.shield_regen_delay = 6.0
	d.shield_damage_bleedthrough = 0.05; d.armor_rating = 20.0
	d.mass = 300000.0
	d.accel_forward = 35.0; d.accel_backward = 20.0; d.accel_strafe = 15.0; d.accel_vertical = 15.0
	d.max_speed_normal = 150.0; d.max_speed_boost = 300.0; d.max_speed_cruise = 2000.0
	d.rotation_pitch_speed = 10.0; d.rotation_yaw_speed = 8.0; d.rotation_roll_speed = 15.0
	d.max_speed_lateral = 60.0; d.max_speed_vertical = 60.0
	d.rotation_damp_min_factor = 0.07
	d.energy_capacity = 200.0; d.energy_regen_rate = 40.0; d.boost_energy_drain = 28.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-25.0, 5.0, -40.0), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(25.0, 5.0, -40.0), direction = Vector3.FORWARD},
		{id = 2, size = "M", position = Vector3(-18.0, 0.0, -35.0), direction = Vector3.FORWARD},
		{id = 3, size = "M", position = Vector3(18.0, 0.0, -35.0), direction = Vector3.FORWARD},
		{id = 4, size = "M", position = Vector3(-12.0, -3.0, -30.0), direction = Vector3.FORWARD},
		{id = 5, size = "M", position = Vector3(12.0, -3.0, -30.0), direction = Vector3.FORWARD},
		{id = 6, size = "L", position = Vector3(-8.0, -5.0, -25.0), direction = Vector3.FORWARD},
		{id = 7, size = "L", position = Vector3(8.0, -5.0, -25.0), direction = Vector3.FORWARD},
	]
	return d


static func _build_cruiser() -> ShipData:
	var d := ShipData.new()
	d.ship_name = &"Cruiser Mk I"
	d.ship_class = &"Cruiser"
	d.hull_hp = 10000.0; d.shield_hp = 5000.0; d.shield_regen_rate = 50.0; d.shield_regen_delay = 8.0
	d.shield_damage_bleedthrough = 0.03; d.armor_rating = 35.0
	d.mass = 800000.0
	d.accel_forward = 20.0; d.accel_backward = 12.0; d.accel_strafe = 10.0; d.accel_vertical = 10.0
	d.max_speed_normal = 100.0; d.max_speed_boost = 200.0; d.max_speed_cruise = 1500.0
	d.rotation_pitch_speed = 6.0; d.rotation_yaw_speed = 5.0; d.rotation_roll_speed = 10.0
	d.max_speed_lateral = 40.0; d.max_speed_vertical = 40.0
	d.rotation_damp_min_factor = 0.06
	d.energy_capacity = 300.0; d.energy_regen_rate = 60.0; d.boost_energy_drain = 35.0
	d.hardpoints = [
		{id = 0, size = "S", position = Vector3(-30.0, 8.0, -50.0), direction = Vector3.FORWARD},
		{id = 1, size = "S", position = Vector3(30.0, 8.0, -50.0), direction = Vector3.FORWARD},
		{id = 2, size = "S", position = Vector3(-35.0, 3.0, -45.0), direction = Vector3.FORWARD},
		{id = 3, size = "S", position = Vector3(35.0, 3.0, -45.0), direction = Vector3.FORWARD},
		{id = 4, size = "M", position = Vector3(-22.0, 0.0, -40.0), direction = Vector3.FORWARD},
		{id = 5, size = "M", position = Vector3(22.0, 0.0, -40.0), direction = Vector3.FORWARD},
		{id = 6, size = "M", position = Vector3(-15.0, -3.0, -35.0), direction = Vector3.FORWARD},
		{id = 7, size = "M", position = Vector3(15.0, -3.0, -35.0), direction = Vector3.FORWARD},
		{id = 8, size = "L", position = Vector3(-10.0, -5.0, -30.0), direction = Vector3.FORWARD},
		{id = 9, size = "L", position = Vector3(10.0, -5.0, -30.0), direction = Vector3.FORWARD},
		{id = 10, size = "L", position = Vector3(0.0, -7.0, -25.0), direction = Vector3.FORWARD},
	]
	return d
