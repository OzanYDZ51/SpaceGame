class_name StationHardpointConfig
extends RefCounted

# =============================================================================
# Station Hardpoint Config — Reads hardpoint positions from the station .tscn
# scene (editable in editor), then selects a subset per station type.
# The scene defines ALL possible hardpoint positions.
# Each station type picks which slots to use and overrides size/properties.
# =============================================================================

const STATION_SCENE_PATH: String = "res://scenes/structures/space_station.tscn"

# Cache: loaded once, shared across all calls
static var _scene_configs: Array[Dictionary] = []
static var _scene_loaded: bool = false
static var _equip_camera_data: Dictionary = {}
static var _station_center: Vector3 = Vector3.ZERO


static func get_configs(station_type: int) -> Array[Dictionary]:
	_ensure_loaded()
	match station_type:
		0: return _repair_configs()
		1: return _trade_configs()
		2: return _military_configs()
		3: return _mining_configs()
	return _repair_configs()


static func get_equipment_camera_data() -> Dictionary:
	_ensure_loaded()
	return _equip_camera_data


static func get_station_center() -> Vector3:
	_ensure_loaded()
	return _station_center


static func _ensure_loaded() -> void:
	if _scene_loaded:
		return
	_scene_loaded = true
	_scene_configs.clear()
	_equip_camera_data = {}
	_station_center = Vector3.ZERO

	var packed: PackedScene = load(STATION_SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("StationHardpointConfig: Could not load station scene '%s'" % STATION_SCENE_PATH)
		return

	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		return

	for child in instance.get_children():
		if child is HardpointSlot:
			_scene_configs.append(child.get_slot_config())
		elif child.name == "StationCenter":
			_station_center = child.position
		elif child is Camera3D and child.name == "EquipmentCamera":
			_equip_camera_data = {
				"position": child.position,
				"basis": child.transform.basis,
				"fov": child.fov,
			}
			if child.projection == Camera3D.PROJECTION_ORTHOGONAL:
				_equip_camera_data["projection"] = child.projection
				_equip_camera_data["size"] = child.size

	# Sort by slot_id
	_scene_configs.sort_custom(func(a, b): return a["id"] < b["id"])
	instance.queue_free()


## Get a scene slot config by slot_id, with optional size/turret overrides.
## All station slots are forced to turret mode (stations are static).
static func _get_slot(slot_id: int, size_override: String = "", turret_overrides: Dictionary = {}) -> Dictionary:
	for cfg in _scene_configs:
		if cfg["id"] == slot_id:
			var result: Dictionary = cfg.duplicate()
			if size_override != "":
				result["size"] = size_override
			# Stations can't move — all weapons must be turrets
			result["is_turret"] = true
			if not result.has("turret_arc_degrees") or result["turret_arc_degrees"] <= 0.0:
				result["turret_arc_degrees"] = 180.0
			if not result.has("turret_speed_deg_s") or result["turret_speed_deg_s"] <= 0.0:
				result["turret_speed_deg_s"] = 60.0
			if not result.has("turret_pitch_min"):
				result["turret_pitch_min"] = -30.0
			if not result.has("turret_pitch_max"):
				result["turret_pitch_max"] = 60.0
			for key in turret_overrides:
				result[key] = turret_overrides[key]
			return result
	push_warning("StationHardpointConfig: slot_id %d not found in scene" % slot_id)
	return {}


# =============================================================================
# PER-TYPE CONFIGS — select slots from scene + override properties
# =============================================================================

static func _repair_configs() -> Array[Dictionary]:
	# 4 slots: top/bottom turrets (S) + right/left forward (M)
	var configs: Array[Dictionary] = []
	configs.append(_get_slot(0, "S", {"turret_speed_deg_s": 60.0, "turret_pitch_max": 80.0}))
	configs.append(_get_slot(1, "S", {"turret_speed_deg_s": 60.0, "turret_pitch_max": 80.0}))
	configs.append(_get_slot(4, "M"))
	configs.append(_get_slot(5, "M"))
	# Re-index for this type
	for i in configs.size():
		configs[i]["id"] = i
	return configs


static func _trade_configs() -> Array[Dictionary]:
	# 2 slots: top/bottom turrets (S)
	var configs: Array[Dictionary] = []
	configs.append(_get_slot(0, "S", {"turret_speed_deg_s": 50.0, "turret_pitch_max": 80.0}))
	configs.append(_get_slot(1, "S", {"turret_speed_deg_s": 50.0, "turret_pitch_max": 80.0}))
	for i in configs.size():
		configs[i]["id"] = i
	return configs


static func _military_configs() -> Array[Dictionary]:
	# 6 slots: all from scene, use scene sizes (L, L, M, M, S, S)
	var configs: Array[Dictionary] = []
	configs.append(_get_slot(0))
	configs.append(_get_slot(1))
	configs.append(_get_slot(2))
	configs.append(_get_slot(3))
	configs.append(_get_slot(4))
	configs.append(_get_slot(5))
	for i in configs.size():
		configs[i]["id"] = i
	return configs


static func _mining_configs() -> Array[Dictionary]:
	# 3 slots: top turret (M) + right/left forward (S)
	var configs: Array[Dictionary] = []
	configs.append(_get_slot(0, "M", {"turret_speed_deg_s": 55.0, "turret_pitch_max": 80.0}))
	configs.append(_get_slot(4, "S"))
	configs.append(_get_slot(5, "S"))
	for i in configs.size():
		configs[i]["id"] = i
	return configs
