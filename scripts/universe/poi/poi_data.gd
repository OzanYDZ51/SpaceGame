class_name POIData
extends RefCounted

# =============================================================================
# POI Data - Runtime data for a single Point of Interest
# Stores type, position, rewards, and discovery/collection state.
# =============================================================================

enum Type { WRECK, CARGO_CACHE, ANOMALY, DISTRESS_SIGNAL, SCANNER_ECHO }

const TYPE_NAMES: Dictionary = {
	Type.WRECK: "Epave",
	Type.CARGO_CACHE: "Cache de cargaison",
	Type.ANOMALY: "Anomalie",
	Type.DISTRESS_SIGNAL: "Signal de detresse",
	Type.SCANNER_ECHO: "Echo scanner",
}

const TYPE_COLORS: Dictionary = {
	Type.WRECK: Color(0.6, 0.6, 0.5),
	Type.CARGO_CACHE: Color(0.2, 0.8, 0.3),
	Type.ANOMALY: Color(0.8, 0.4, 1.0),
	Type.DISTRESS_SIGNAL: Color(1.0, 0.3, 0.3),
	Type.SCANNER_ECHO: Color(0.4, 0.7, 1.0),
}

# --- Identity ---
var poi_id: String = ""
var poi_type: int = 0
var display_name: String = ""
var description: String = ""

# --- Position (universe float64 coordinates) ---
var pos_x: float = 0.0
var pos_z: float = 0.0
var system_id: int = -1

# --- Discovery & Collection ---
var is_discovered: bool = false
var is_collected: bool = false
var discovery_range: float = 2000.0
var interaction_range: float = 200.0

# --- Rewards & Danger ---
var rewards: Dictionary = {}
var danger_level: int = 0
var faction_id: StringName = &""

# --- Scanner Echo link ---
var linked_poi_id: String = ""


func get_type_name() -> String:
	return TYPE_NAMES.get(poi_type, "Inconnu")


func get_type_color() -> Color:
	return TYPE_COLORS.get(poi_type, Color.WHITE)


func serialize() -> Dictionary:
	return {
		"poi_id": poi_id,
		"poi_type": poi_type,
		"display_name": display_name,
		"description": description,
		"pos_x": pos_x,
		"pos_z": pos_z,
		"system_id": system_id,
		"is_discovered": is_discovered,
		"is_collected": is_collected,
		"discovery_range": discovery_range,
		"interaction_range": interaction_range,
		"rewards": rewards.duplicate(),
		"danger_level": danger_level,
		"faction_id": String(faction_id),
		"linked_poi_id": linked_poi_id,
	}


static func deserialize(data: Dictionary) -> POIData:
	var poi := POIData.new()
	poi.poi_id = data.get("poi_id", "")
	poi.poi_type = data.get("poi_type", 0)
	poi.display_name = data.get("display_name", "")
	poi.description = data.get("description", "")
	poi.pos_x = data.get("pos_x", 0.0)
	poi.pos_z = data.get("pos_z", 0.0)
	poi.system_id = data.get("system_id", -1)
	poi.is_discovered = data.get("is_discovered", false)
	poi.is_collected = data.get("is_collected", false)
	poi.discovery_range = data.get("discovery_range", 2000.0)
	poi.interaction_range = data.get("interaction_range", 200.0)
	poi.rewards = data.get("rewards", {}).duplicate()
	poi.danger_level = data.get("danger_level", 0)
	poi.faction_id = StringName(data.get("faction_id", ""))
	poi.linked_poi_id = data.get("linked_poi_id", "")
	return poi
