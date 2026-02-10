class_name StationEquipment
extends RefCounted

# =============================================================================
# Station Equipment — Persistent equipment storage for a station.
# Mirrors FleetShip for stations: weapons, shield, modules.
# =============================================================================

var station_id: String = ""
var station_type: int = 0
var weapons: Array[StringName] = []
var shield_name: StringName = &""
var modules: Array[StringName] = []

# Slot definitions per station type
var module_slots: Array[String] = []
var shield_slot_size: String = "S"


static func create_empty(p_station_id: String, p_station_type: int) -> StationEquipment:
	var eq := StationEquipment.new()
	eq.station_id = p_station_id
	eq.station_type = p_station_type

	# Init weapons array from hardpoint config count
	var configs := StationHardpointConfig.get_configs(p_station_type)
	eq.weapons.resize(configs.size())
	for i in configs.size():
		eq.weapons[i] = &""

	# Module slots per type
	match p_station_type:
		0:  # REPAIR
			eq.module_slots = ["M", "S"]
			eq.shield_slot_size = "M"
		1:  # TRADE
			eq.module_slots = ["S"]
			eq.shield_slot_size = "S"
		2:  # MILITARY
			eq.module_slots = ["L", "M", "M"]
			eq.shield_slot_size = "L"
		3:  # MINING
			eq.module_slots = ["M", "S"]
			eq.shield_slot_size = "S"

	eq.modules.resize(eq.module_slots.size())
	for i in eq.module_slots.size():
		eq.modules[i] = &""

	return eq


func serialize() -> Dictionary:
	var w_arr: Array = []
	for w in weapons:
		w_arr.append(String(w))
	var m_arr: Array = []
	for m in modules:
		m_arr.append(String(m))
	return {
		"station_id": station_id,
		"station_type": station_type,
		"weapons": w_arr,
		"shield_name": String(shield_name),
		"modules": m_arr,
	}


static func deserialize(data: Dictionary) -> StationEquipment:
	var p_type: int = data.get("station_type", 0)
	var eq := create_empty(data.get("station_id", ""), p_type)
	eq.shield_name = StringName(data.get("shield_name", ""))

	var w_arr: Array = data.get("weapons", [])
	for i in mini(w_arr.size(), eq.weapons.size()):
		eq.weapons[i] = StringName(w_arr[i])

	var m_arr: Array = data.get("modules", [])
	for i in mini(m_arr.size(), eq.modules.size()):
		eq.modules[i] = StringName(m_arr[i])

	return eq
