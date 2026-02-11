class_name ConstructionManager
extends RefCounted

# =============================================================================
# Construction Manager — Session-local construction marker storage
# Markers represent planned construction sites on the system map
# =============================================================================

signal marker_added(marker: Dictionary)
signal marker_removed(marker_id: int)

var _markers: Array[Dictionary] = []
var _next_id: int = 1


func add_marker(type: StringName, display_name: String, pos_x: float, pos_z: float, system_id: int = -1) -> Dictionary:
	var marker := {
		"id": _next_id,
		"type": type,
		"display_name": display_name,
		"pos_x": pos_x,
		"pos_z": pos_z,
		"system_id": system_id,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"color": Color(1.0, 0.6, 0.1, 0.9),
		"deposited_resources": {&"iron": 0, &"copper": 0, &"titanium": 0, &"crystal": 0},
	}
	_next_id += 1
	_markers.append(marker)
	marker_added.emit(marker)
	return marker


func get_markers_for_system(system_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m in _markers:
		if m.get("system_id", -1) == system_id:
			result.append(m)
	return result


func remove_marker(marker_id: int) -> void:
	for i in _markers.size():
		if _markers[i]["id"] == marker_id:
			_markers.remove_at(i)
			marker_removed.emit(marker_id)
			return


func get_marker(marker_id: int) -> Dictionary:
	for m in _markers:
		if m.get("id", -1) == marker_id:
			return m
	return {}


func get_markers() -> Array[Dictionary]:
	return _markers


func clear() -> void:
	_markers.clear()
