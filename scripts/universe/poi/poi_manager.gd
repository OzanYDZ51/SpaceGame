class_name POIManager
extends Node

# =============================================================================
# POI Manager - Manages Points of Interest for the current star system
# Generates POIs on system load, tracks discovery/collection, registers
# in EntityRegistry. Child of GameManager.
# =============================================================================

signal poi_discovered(poi: POIData)
signal poi_collected(poi: POIData)
signal poi_spawned(poi: POIData)

# Entity type constant for POIs (matches EntityRegistrySystem.EntityType.POINT_OF_INTEREST)
const ENTITY_TYPE_POI: int = EntityRegistrySystem.EntityType.POINT_OF_INTEREST

# How often to check player distance to undiscovered POIs (seconds)
const DISCOVERY_CHECK_INTERVAL: float = 0.5

var _current_system_pois: Array[POIData] = []
var _collected_pois: Dictionary = {}  # poi_id -> true (persists across system changes)
var _current_system_id: int = -1
var _discovery_timer: float = 0.0


func on_system_loaded(system_id: int, danger_level: int) -> void:
	_current_system_id = system_id

	# Generate POIs deterministically for this system
	var all_pois: Array[POIData] = POIGenerator.generate_pois(system_id, danger_level)

	# Filter out already-collected POIs
	_current_system_pois.clear()
	for poi in all_pois:
		if _collected_pois.has(poi.poi_id):
			continue
		_current_system_pois.append(poi)
		_register_poi(poi)
		poi_spawned.emit(poi)


func on_system_unloading() -> void:
	# Unregister all POIs from EntityRegistry
	for poi in _current_system_pois:
		EntityRegistry.unregister(poi.poi_id)
	_current_system_pois.clear()
	_current_system_id = -1


func _process(delta: float) -> void:
	if _current_system_pois.is_empty():
		return

	_discovery_timer -= delta
	if _discovery_timer > 0.0:
		return
	_discovery_timer = DISCOVERY_CHECK_INTERVAL

	_check_discoveries()


func _check_discoveries() -> void:
	# Get player universe position
	var player_pos: Array = EntityRegistry.get_position("player_ship")
	var px: float = player_pos[0]
	var pz: float = player_pos[2]

	for poi in _current_system_pois:
		if poi.is_discovered:
			continue

		var dx: float = px - poi.pos_x
		var dz: float = pz - poi.pos_z
		var dist_sq: float = dx * dx + dz * dz

		if dist_sq <= poi.discovery_range * poi.discovery_range:
			poi.is_discovered = true
			poi_discovered.emit(poi)


func interact_with_poi(poi_id: String) -> Dictionary:
	var poi: POIData = _find_poi(poi_id)
	if poi == null:
		return {}
	if poi.is_collected:
		return {}

	# Mark as collected
	poi.is_collected = true
	_collected_pois[poi.poi_id] = true

	# Unregister from EntityRegistry
	EntityRegistry.unregister(poi.poi_id)

	# Remove from active list
	_current_system_pois.erase(poi)

	poi_collected.emit(poi)

	# For scanner echoes, reveal the linked POI (mark as discovered)
	if poi.poi_type == POIData.Type.SCANNER_ECHO and poi.linked_poi_id != "":
		var linked: POIData = _find_poi(poi.linked_poi_id)
		if linked and not linked.is_discovered:
			linked.is_discovered = true
			poi_discovered.emit(linked)

	return poi.rewards.duplicate()


func get_nearby_poi(max_range: float) -> POIData:
	var player_pos: Array = EntityRegistry.get_position("player_ship")
	var px: float = player_pos[0]
	var pz: float = player_pos[2]

	var best_poi: POIData = null
	var best_dist_sq: float = max_range * max_range

	for poi in _current_system_pois:
		if poi.is_collected:
			continue

		var dx: float = px - poi.pos_x
		var dz: float = pz - poi.pos_z
		var dist_sq: float = dx * dx + dz * dz

		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_poi = poi

	return best_poi


func get_interactable_poi() -> POIData:
	var player_pos: Array = EntityRegistry.get_position("player_ship")
	var px: float = player_pos[0]
	var pz: float = player_pos[2]

	for poi in _current_system_pois:
		if poi.is_collected:
			continue

		var dx: float = px - poi.pos_x
		var dz: float = pz - poi.pos_z
		var dist_sq: float = dx * dx + dz * dz

		if dist_sq <= poi.interaction_range * poi.interaction_range:
			return poi

	return null


func get_discovered_pois() -> Array[POIData]:
	var result: Array[POIData] = []
	for poi in _current_system_pois:
		if poi.is_discovered and not poi.is_collected:
			result.append(poi)
	return result


func get_all_pois() -> Array[POIData]:
	return _current_system_pois


func serialize() -> Dictionary:
	return {
		"collected_pois": _collected_pois.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	var raw_pois = data.get("collected_pois", {})
	_collected_pois = raw_pois.duplicate() if raw_pois is Dictionary else {}


func _find_poi(poi_id: String) -> POIData:
	for poi in _current_system_pois:
		if poi.poi_id == poi_id:
			return poi
	return null


func _register_poi(poi: POIData) -> void:
	EntityRegistry.register(poi.poi_id, {
		"name": poi.display_name,
		"type": ENTITY_TYPE_POI,
		"pos_x": poi.pos_x,
		"pos_y": 0.0,
		"pos_z": poi.pos_z,
		"node": null,
		"radius": 50.0,
		"color": poi.get_type_color(),
		"extra": {
			"poi_type": poi.poi_type,
			"poi_id": poi.poi_id,
			"is_discovered": poi.is_discovered,
		},
	})
