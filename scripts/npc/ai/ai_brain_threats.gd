class_name AIBrainThreats
extends RefCounted

# =============================================================================
# AI Brain Threats - Threat detection, faction checks, threat table management.
# Extracted from AIBrain to keep the core state machine lean.
# Runs as a RefCounted sub-object owned by AIBrain.
# =============================================================================

const THREAT_DECAY_RATE: float = 5.0
const THREAT_SWITCH_RATIO: float = 1.5
const THREAT_CLEANUP_TIME: float = 10.0

# Threat table: tracks accumulated damage from each attacker
# Key = attacker instance_id, Value = { "node": Node3D, "threat": float, "last_hit": float }
var threat_table: Dictionary = {}
var _last_threat_update_ms: float = 0.0

var _ship = null
var _cached_lod_mgr = null


func setup(ship: Node3D) -> void:
	_ship = ship
	_cached_lod_mgr = GameManager.get_node_or_null("ShipLODManager")


func detect_threats(detection_range: float, weapons_enabled: bool, ignore_threats: bool) -> Node3D:
	if _ship == null or ignore_threats or not weapons_enabled:
		return null

	# Use spatial grid via LOD manager if available (O(k) instead of O(n))
	if _cached_lod_mgr:
		var self_id =StringName(_ship.name)
		var results = _cached_lod_mgr.get_nearest_ships(_ship.global_position, detection_range, 5, self_id)
		var nearest_threat: Node3D = null
		var nearest_dist: float = detection_range
		for entry in results:
			var data = _cached_lod_mgr.get_ship_data(entry["id"])
			if data == null or data.is_dead:
				continue
			if is_faction_allied(data.faction, entry["id"]):
				continue
			if data.node_ref == null or not is_instance_valid(data.node_ref):
				continue
			var dist_sq: float = entry["dist_sq"]
			if dist_sq < nearest_dist * nearest_dist:
				nearest_dist = sqrt(dist_sq)
				nearest_threat = data.node_ref
		return nearest_threat

	# Legacy fallback
	var all_ships = _ship.get_tree().get_nodes_in_group("ships") if _ship.is_inside_tree() else []
	var fallback_threat: Node3D = null
	var fallback_dist: float = detection_range

	for node in all_ships:
		if node == _ship:
			continue
		if node.get("ship_data") != null:
			var other = node
			var other_faction: StringName = other.faction
			if is_faction_allied(other_faction, StringName(other.name)):
				continue
			var dist: float = _ship.global_position.distance_to(other.global_position)
			if dist < fallback_dist:
				var other_health = other.get_node_or_null("HealthSystem")
				if other_health and other_health.is_dead():
					continue
				fallback_dist = dist
				fallback_threat = other

	return fallback_threat


func is_faction_allied(target_faction: StringName, target_id: StringName = &"") -> bool:
	var my_fac: StringName = _ship.faction

	if target_faction == my_fac:
		return true

	if my_fac == &"player_fleet":
		return target_faction == &"player_fleet" or target_id == &"player_ship"
	if target_faction == &"player_fleet" or target_id == &"player_ship":
		var gi = GameManager.get_node_or_null("GameplayIntegrator")
		if gi == null:
			return false
		var fm = gi.get_node_or_null("FactionManager")
		if fm:
			return my_fac == fm.player_faction
		return false

	if my_fac == &"hostile" or my_fac == &"lawless" or my_fac == &"pirate":
		return false
	if target_faction == &"hostile" or target_faction == &"lawless" or target_faction == &"pirate":
		return false

	var gi2 = GameManager.get_node_or_null("GameplayIntegrator")
	if gi2 == null:
		return false
	var fm2 = gi2.get_node_or_null("FactionManager")
	if fm2:
		return not fm2.are_enemies(my_fac, target_faction)

	return false


func on_damage_taken(attacker: Node3D, amount: float = 0.0) -> Dictionary:
	## Returns { "should_engage": bool, "attacker": Node3D } if state change needed
	if attacker == null or not is_instance_valid(attacker) or attacker == _ship:
		return {}

	var aid: int = attacker.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if threat_table.has(aid):
		threat_table[aid]["threat"] += amount
		threat_table[aid]["last_hit"] = now
		threat_table[aid]["node"] = attacker
	else:
		threat_table[aid] = { "node": attacker, "threat": amount, "last_hit": now }

	return { "should_engage": true, "attacker": attacker }


func update_threat_table(dt: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []
	for aid: int in threat_table:
		var entry: Dictionary = threat_table[aid]
		entry["threat"] -= THREAT_DECAY_RATE * dt
		var raw_node = entry["node"]
		if entry["threat"] <= 0.0 or (now - entry["last_hit"]) > THREAT_CLEANUP_TIME:
			to_remove.append(aid)
		elif raw_node == null or not is_instance_valid(raw_node) or not raw_node.is_inside_tree():
			to_remove.append(aid)
	for aid: int in to_remove:
		threat_table.erase(aid)


func maybe_switch_target(current_target: Node3D) -> Node3D:
	if current_target == null or not is_instance_valid(current_target):
		return get_highest_threat()

	var current_tid: int = current_target.get_instance_id()
	var current_threat: float = 0.0
	if threat_table.has(current_tid):
		current_threat = threat_table[current_tid]["threat"]

	var best_node: Node3D = null
	var best_threat: float = 0.0
	for aid: int in threat_table:
		var entry: Dictionary = threat_table[aid]
		if entry["threat"] > best_threat:
			var node: Node3D = entry["node"] as Node3D
			if node and is_instance_valid(node) and node.is_inside_tree():
				best_threat = entry["threat"]
				best_node = node

	if best_node and best_node != current_target and best_threat > current_threat * THREAT_SWITCH_RATIO:
		return best_node
	return null  # No switch


func get_highest_threat() -> Node3D:
	var best_node: Node3D = null
	var best_threat: float = 0.0
	for aid: int in threat_table:
		var entry: Dictionary = threat_table[aid]
		if entry["threat"] > best_threat:
			var node: Node3D = entry["node"] as Node3D
			if node and is_instance_valid(node) and node.is_inside_tree():
				best_threat = entry["threat"]
				best_node = node
	return best_node


func alert_to_threat(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker == _ship:
		return
	var aid: int = attacker.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if threat_table.has(aid):
		threat_table[aid]["threat"] += 50.0
		threat_table[aid]["last_hit"] = now
		threat_table[aid]["node"] = attacker
	else:
		threat_table[aid] = { "node": attacker, "threat": 50.0, "last_hit": now }
