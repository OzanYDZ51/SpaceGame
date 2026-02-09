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


## BFS search for the nearest system with a station (for respawn).
## Returns the system id, or from_id if none found.
func find_nearest_repair_system(from_id: int) -> int:
	# Current system has a station? Use it directly
	var current := get_system(from_id)
	if not current.is_empty() and current.get("has_station", false):
		return from_id

	# BFS through jump gate connections
	var visited: Dictionary = {}
	var queue: Array[int] = [from_id]
	visited[from_id] = true

	while queue.size() > 0:
		var sys_id: int = queue.pop_front()
		for conn_id in get_connections(sys_id):
			if visited.has(conn_id):
				continue
			visited[conn_id] = true
			var conn_sys := get_system(conn_id)
			if not conn_sys.is_empty() and conn_sys.get("has_station", false):
				return conn_id
			queue.append(conn_id)

	# Fallback: no reachable station, stay in current system
	return from_id


## BFS pathfinding: returns ordered array of system IDs from from_id to to_id (inclusive).
## Returns empty array if no path found (shouldn't happen — MST guarantees connectivity).
func find_path(from_id: int, to_id: int) -> Array[int]:
	if from_id == to_id:
		return [from_id]

	var visited: Dictionary = {}
	var parent: Dictionary = {}  # child_id -> parent_id
	var queue: Array[int] = [from_id]
	visited[from_id] = true

	while queue.size() > 0:
		var sys_id: int = queue.pop_front()
		for conn_id in get_connections(sys_id):
			if visited.has(conn_id):
				continue
			visited[conn_id] = true
			parent[conn_id] = sys_id
			if conn_id == to_id:
				# Reconstruct path
				var path: Array[int] = []
				var current: int = to_id
				while current != from_id:
					path.append(current)
					current = parent[current]
				path.append(from_id)
				path.reverse()
				return path
			queue.append(conn_id)

	return []
