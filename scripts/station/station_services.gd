class_name StationServices
extends RefCounted

# =============================================================================
# Station Services — tracks unlock state for station services across all stations.
# Key format: "system_id:station_idx" (e.g. "42:0")
# Each station has 6 services: commerce, equipment, repair, shipyard, refinery, entrepot.
# =============================================================================

enum Service { COMMERCE, EQUIPMENT, REPAIR, SHIPYARD, REFINERY, ENTREPOT }

const SERVICE_NAMES: Dictionary = {
	Service.COMMERCE: "commerce",
	Service.EQUIPMENT: "equipment",
	Service.REPAIR: "repair",
	Service.SHIPYARD: "shipyard",
	Service.REFINERY: "refinery",
	Service.ENTREPOT: "entrepot",
}

## Locale keys for service labels — use Locale.t(SERVICE_LABEL_KEYS[svc]) to get translated name.
const SERVICE_LABEL_KEYS: Dictionary = {
	Service.COMMERCE: "station.commerce",
	Service.EQUIPMENT: "station.equipment",
	Service.REPAIR: "station.repair",
	Service.SHIPYARD: "station.shipyard",
	Service.REFINERY: "station.refinery",
	Service.ENTREPOT: "station.storage",
}

## Returns translated service label.
static func get_service_label(svc: int) -> String:
	return Locale.t(SERVICE_LABEL_KEYS.get(svc, ""))

const SERVICE_PRICES: Dictionary = {
	Service.COMMERCE: 5000,
	Service.EQUIPMENT: 3000,
	Service.REPAIR: 2000,
	Service.SHIPYARD: 8000,
	Service.REFINERY: 6000,
	Service.ENTREPOT: 4000,
}

# station_key -> { "commerce": bool, "equipment": bool, "repair": bool }
var _states: Dictionary = {}


func _make_key(system_id: int, station_idx: int) -> String:
	return "%d:%d" % [system_id, station_idx]


func _get_or_create(key: String) -> Dictionary:
	if not _states.has(key):
		_states[key] = { "commerce": false, "equipment": false, "repair": false, "shipyard": false, "refinery": false, "entrepot": false }
	return _states[key]


func is_unlocked(system_id: int, station_idx: int, service: Service) -> bool:
	var key =_make_key(system_id, station_idx)
	if not _states.has(key):
		return false
	return _states[key].get(SERVICE_NAMES[service], false)


func unlock(system_id: int, station_idx: int, service: Service, economy) -> bool:
	var price: int = SERVICE_PRICES[service]
	if economy.credits < price:
		return false
	if not economy.spend_credits(price):
		return false
	var key =_make_key(system_id, station_idx)
	var state =_get_or_create(key)
	state[SERVICE_NAMES[service]] = true
	return true


func unlock_all(system_id: int, station_idx: int) -> void:
	var key =_make_key(system_id, station_idx)
	_states[key] = { "commerce": true, "equipment": true, "repair": true, "shipyard": true, "refinery": true, "entrepot": true }


func get_unlocked_count(system_id: int, station_idx: int) -> int:
	var key =_make_key(system_id, station_idx)
	if not _states.has(key):
		return 0
	var count: int = 0
	var state: Dictionary = _states[key]
	for svc_name in state:
		if state[svc_name]:
			count += 1
	return count


func init_center_systems(galaxy) -> void:
	for sys in galaxy.systems:
		var sys_id: int = sys.get("id", -1)
		var danger: int = sys.get("danger_level", 5)
		if danger > 1:
			continue
		# Resolve station count from system data
		var system_data: StarSystemData = SystemDataRegistry.get_override(sys_id)
		if system_data == null:
			var connections: Array[Dictionary] = []
			for conn_id in sys.get("connections", []):
				var conn_sys: Dictionary = galaxy.get_system(conn_id)
				if not conn_sys.is_empty():
					connections.append({
						"target_id": conn_id,
						"target_name": conn_sys.get("name", ""),
						"origin_x": sys.get("x", 0.0),
						"origin_y": sys.get("y", 0.0),
						"target_x": conn_sys.get("x", 0.0),
						"target_y": conn_sys.get("y", 0.0),
					})
			system_data = SystemGenerator.generate(sys.get("seed", 0), connections)
		for i in system_data.stations.size():
			unlock_all(sys_id, i)


func serialize() -> Array:
	var result: Array = []
	for key in _states:
		var state: Dictionary = _states[key]
		result.append({
			"key": key,
			"commerce": state.get("commerce", false),
			"equipment": state.get("equipment", false),
			"repair": state.get("repair", false),
			"shipyard": state.get("shipyard", false),
			"refinery": state.get("refinery", false),
			"entrepot": state.get("entrepot", false),
		})
	return result


func deserialize(data: Array) -> void:
	_states.clear()
	for entry in data:
		if entry is Dictionary:
			var key: String = entry.get("key", "")
			if key != "":
				_states[key] = {
					"commerce": entry.get("commerce", false),
					"equipment": entry.get("equipment", false),
					"repair": entry.get("repair", false),
					"shipyard": entry.get("shipyard", false),
					"refinery": entry.get("refinery", false),
					"entrepot": entry.get("entrepot", false),
				}
