class_name NpcPersistence
extends Node

# =============================================================================
# NPC Persistence - Saves/restores NPC state across system transitions.
# Uses a "dormant node" model: NPCs are reparented into a hidden container
# with process_mode = DISABLED when the player leaves a system, and
# reparented back when returning.
#
# Respawn: if an NPC was killed, it won't be in the dormant list.
# After a configurable delay, the EncounterManager re-spawns it fresh.
# =============================================================================

# system_id -> Array[Node] (dormant NPC nodes, process_mode DISABLED)
var _dormant_systems: Dictionary = {}

# system_id -> float (Time.get_ticks_msec when system was saved)
var _dormant_timestamps: Dictionary = {}

# Container node for dormant NPCs (hidden, no processing)
var _dormant_root: Node = null

# Max systems to keep dormant before evicting oldest
const MAX_DORMANT_SYSTEMS: int = 10
# Max time (ms) to keep a dormant system before discarding (10 minutes)
const MAX_DORMANT_AGE_MS: float = 600000.0


func _ready() -> void:
	_dormant_root = Node.new()
	_dormant_root.name = "_dormant_npcs"
	_dormant_root.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.add_child(_dormant_root)


## Check if we have saved dormant NPCs for a system.
func has_saved_state(system_id: int) -> bool:
	if not _dormant_systems.has(system_id):
		return false
	# Check age — if too old, discard
	var saved_time: float = _dormant_timestamps.get(system_id, 0.0)
	if Time.get_ticks_msec() - saved_time > MAX_DORMANT_AGE_MS:
		_discard_system(system_id)
		return false
	# Check that at least some nodes still exist
	var nodes: Array = _dormant_systems[system_id]
	return not nodes.is_empty()


## Save all NPCs from the current system into dormant storage.
## Called when the player leaves a system (before cleanup).
## Returns the number of NPCs saved.
func save_system(system_id: int, npc_nodes: Array[Node]) -> int:
	if npc_nodes.is_empty():
		return 0

	# Evict oldest if at capacity
	if _dormant_systems.size() >= MAX_DORMANT_SYSTEMS and not _dormant_systems.has(system_id):
		_evict_oldest()

	# Create a sub-container for this system
	var sys_container: Node = Node.new()
	sys_container.name = "system_%d" % system_id
	_dormant_root.add_child(sys_container)

	var saved: int = 0
	for npc in npc_nodes:
		if npc == null or not is_instance_valid(npc):
			continue
		# Remove from current parent (Universe)
		var parent = npc.get_parent()
		if parent:
			parent.remove_child(npc)
		# Disable processing
		npc.process_mode = Node.PROCESS_MODE_DISABLED
		if npc is RigidBody3D:
			npc.freeze = true
		# Reparent into dormant container
		sys_container.add_child(npc)
		saved += 1

	if saved > 0:
		_dormant_systems[system_id] = _get_children_array(sys_container)
		_dormant_timestamps[system_id] = Time.get_ticks_msec()
		print("NpcPersistence: Saved %d NPCs for system %d" % [saved, system_id])
	else:
		sys_container.queue_free()

	return saved


## Restore dormant NPCs for a system back into the Universe node.
## Returns the Array of restored NPC nodes, or empty if no saved state.
func restore_system(system_id: int, universe: Node3D) -> Array[Node]:
	if not has_saved_state(system_id):
		return []

	var nodes: Array = _dormant_systems[system_id]
	var restored: Array[Node] = []

	# Find the system container
	var sys_container: Node = _dormant_root.get_node_or_null("system_%d" % system_id)
	if sys_container == null:
		_dormant_systems.erase(system_id)
		_dormant_timestamps.erase(system_id)
		return []

	for npc in nodes:
		if npc == null or not is_instance_valid(npc):
			continue
		# Reparent into Universe
		sys_container.remove_child(npc)
		universe.add_child(npc)
		# Re-enable processing
		npc.process_mode = Node.PROCESS_MODE_INHERIT
		if npc is RigidBody3D:
			npc.freeze = false
		restored.append(npc)

	# Clean up container
	sys_container.queue_free()
	_dormant_systems.erase(system_id)
	_dormant_timestamps.erase(system_id)

	print("NpcPersistence: Restored %d NPCs for system %d" % [restored.size(), system_id])
	return restored


## Remove a specific NPC from dormant storage (e.g., it was killed).
func remove_npc(system_id: int, npc_id: StringName) -> void:
	if not _dormant_systems.has(system_id):
		return
	var nodes: Array = _dormant_systems[system_id]
	for i in range(nodes.size() - 1, -1, -1):
		var npc = nodes[i]
		if npc != null and is_instance_valid(npc) and StringName(npc.name) == npc_id:
			npc.queue_free()
			nodes.remove_at(i)
			break
	if nodes.is_empty():
		_discard_system(system_id)


## Discard all dormant NPCs for a system (free nodes).
func _discard_system(system_id: int) -> void:
	if _dormant_systems.has(system_id):
		var nodes: Array = _dormant_systems[system_id]
		for npc in nodes:
			if npc != null and is_instance_valid(npc):
				npc.queue_free()
		_dormant_systems.erase(system_id)
	_dormant_timestamps.erase(system_id)
	# Free the container node
	var sys_container: Node = _dormant_root.get_node_or_null("system_%d" % system_id)
	if sys_container:
		sys_container.queue_free()


## Evict the oldest dormant system to make room.
func _evict_oldest() -> void:
	var oldest_sys: int = -1
	var oldest_time: float = INF
	for sys_id in _dormant_timestamps:
		if _dormant_timestamps[sys_id] < oldest_time:
			oldest_time = _dormant_timestamps[sys_id]
			oldest_sys = sys_id
	if oldest_sys >= 0:
		print("NpcPersistence: Evicting dormant system %d (%.0fs old)" % [oldest_sys, (Time.get_ticks_msec() - oldest_time) / 1000.0])
		_discard_system(oldest_sys)


## Helper: get children as Array.
func _get_children_array(node: Node) -> Array:
	var arr: Array = []
	for child in node.get_children():
		arr.append(child)
	return arr


## Stubs for future DB persistence.
func serialize_all() -> Dictionary:
	var data: Dictionary = {}
	for sys_id in _dormant_systems:
		var nodes: Array = _dormant_systems[sys_id]
		var npcs: Array = []
		for npc in nodes:
			if npc == null or not is_instance_valid(npc):
				continue
			npcs.append({
				"name": npc.name,
				"position": [npc.global_position.x, npc.global_position.y, npc.global_position.z],
			})
		data[sys_id] = npcs
	return data


func deserialize_all(_data: Dictionary) -> void:
	pass  # Future: restore from DB
