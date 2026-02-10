class_name StationHardpointConfig
extends RefCounted

# =============================================================================
# Station Hardpoint Config — Static hardpoint layouts per station type.
# Returns config dictionaries compatible with Hardpoint.setup_from_config().
# =============================================================================


static func get_configs(station_type: int) -> Array[Dictionary]:
	match station_type:
		0:  # REPAIR — 4 slots: 2S turrets (top/bottom) + 2M forward (sides)
			return _repair_configs()
		1:  # TRADE — 2 slots: 2S turrets (top/bottom)
			return _trade_configs()
		2:  # MILITARY — 6 slots: 2L turrets (top/bottom) + 2M turrets (flanks) + 2S forward
			return _military_configs()
		3:  # MINING — 3 slots: 1M turret (top) + 2S forward (sides)
			return _mining_configs()
	return _repair_configs()


static func _repair_configs() -> Array[Dictionary]:
	var configs: Array[Dictionary] = []
	configs.append({
		"id": 0, "size": "S", "position": Vector3(0, 30, 0),
		"rotation_degrees": Vector3.ZERO, "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 60.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 80.0,
	})
	configs.append({
		"id": 1, "size": "S", "position": Vector3(0, -25, 0),
		"rotation_degrees": Vector3(180, 0, 0), "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 60.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 80.0,
	})
	configs.append({
		"id": 2, "size": "M", "position": Vector3(35, 5, -10),
		"rotation_degrees": Vector3(0, -10, 0), "is_turret": false,
	})
	configs.append({
		"id": 3, "size": "M", "position": Vector3(-35, 5, -10),
		"rotation_degrees": Vector3(0, 10, 0), "is_turret": false,
	})
	return configs


static func _trade_configs() -> Array[Dictionary]:
	var configs: Array[Dictionary] = []
	configs.append({
		"id": 0, "size": "S", "position": Vector3(0, 25, 0),
		"rotation_degrees": Vector3.ZERO, "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 50.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 80.0,
	})
	configs.append({
		"id": 1, "size": "S", "position": Vector3(0, -20, 0),
		"rotation_degrees": Vector3(180, 0, 0), "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 50.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 80.0,
	})
	return configs


static func _military_configs() -> Array[Dictionary]:
	var configs: Array[Dictionary] = []
	# Top turret (L)
	configs.append({
		"id": 0, "size": "L", "position": Vector3(0, 35, 0),
		"rotation_degrees": Vector3.ZERO, "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 45.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 85.0,
	})
	# Bottom turret (L)
	configs.append({
		"id": 1, "size": "L", "position": Vector3(0, -30, 0),
		"rotation_degrees": Vector3(180, 0, 0), "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 45.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 85.0,
	})
	# Right flank turret (M)
	configs.append({
		"id": 2, "size": "M", "position": Vector3(40, 10, 0),
		"rotation_degrees": Vector3(0, -90, 0), "is_turret": true,
		"turret_arc_degrees": 270.0, "turret_speed_deg_s": 55.0,
		"turret_pitch_min": -30.0, "turret_pitch_max": 60.0,
	})
	# Left flank turret (M)
	configs.append({
		"id": 3, "size": "M", "position": Vector3(-40, 10, 0),
		"rotation_degrees": Vector3(0, 90, 0), "is_turret": true,
		"turret_arc_degrees": 270.0, "turret_speed_deg_s": 55.0,
		"turret_pitch_min": -30.0, "turret_pitch_max": 60.0,
	})
	# Right forward (S)
	configs.append({
		"id": 4, "size": "S", "position": Vector3(25, 0, -30),
		"rotation_degrees": Vector3.ZERO, "is_turret": false,
	})
	# Left forward (S)
	configs.append({
		"id": 5, "size": "S", "position": Vector3(-25, 0, -30),
		"rotation_degrees": Vector3.ZERO, "is_turret": false,
	})
	return configs


static func _mining_configs() -> Array[Dictionary]:
	var configs: Array[Dictionary] = []
	# Top turret (M)
	configs.append({
		"id": 0, "size": "M", "position": Vector3(0, 28, 0),
		"rotation_degrees": Vector3.ZERO, "is_turret": true,
		"turret_arc_degrees": 360.0, "turret_speed_deg_s": 55.0,
		"turret_pitch_min": -10.0, "turret_pitch_max": 80.0,
	})
	# Right forward (S)
	configs.append({
		"id": 1, "size": "S", "position": Vector3(30, 5, -15),
		"rotation_degrees": Vector3(0, -10, 0), "is_turret": false,
	})
	# Left forward (S)
	configs.append({
		"id": 2, "size": "S", "position": Vector3(-30, 5, -15),
		"rotation_degrees": Vector3(0, 10, 0), "is_turret": false,
	})
	return configs
