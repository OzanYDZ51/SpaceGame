class_name GalaxyData
extends RefCounted

# =============================================================================
# Galaxy Data - Describes the full galaxy: all systems and connections
# Generated once from a master seed by GalaxyGenerator.
# =============================================================================

# Per-system entry: {
#   "id": int,
#   "seed": int,                   # Deterministic seed for SystemGenerator
#   "name": String,
#   "x": float, "y": float,       # 2D galaxy map position
#   "spectral_class": String,      # Star type (for map icon color)
#   "connections": Array[int],     # IDs of systems connected by jump gates
#   "has_station": bool,
#   "faction": StringName,         # Controlling faction
#   "danger_level": int,           # 0-5, affects NPC spawns
# }
var systems: Array[Dictionary] = []
var master_seed: int = 0
var player_home_system: int = 0


func get_system(id: int) -> Dictionary:
	if id >= 0 and id < systems.size():
		return systems[id]
	return {}


func get_system_name(id: int) -> String:
	var sys := get_system(id)
	if sys.is_empty():
		return "Unknown"
	return sys["name"]


func get_connections(id: int) -> Array:
	var sys := get_system(id)
	if sys.is_empty():
		return []
	return sys["connections"]
