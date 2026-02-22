class_name StationDefenseAI
extends Node

# =============================================================================
# Station Defense AI — Scans for hostiles and fires turrets automatically.
# =============================================================================

const SCAN_INTERVAL: float = 0.5
const DETECTION_RANGE: float = 4000.0
const THREAT_DECAY_TIME: float = 30.0
const GUARD_REALERT_INTERVAL: float = 3.0

var _station = null
var _weapon_manager = null
var _current_target: Node3D = null
var _scan_timer: float = 0.0
var _guard_alert_timer: float = 0.0

# Threat table: node instance_id -> {node_ref, last_hit_time, total_damage}
var _threat_table: Dictionary = {}


func initialize(station, wm) -> void:
	_station = station
	_weapon_manager = wm

	# Connect to damage signal for reactive targeting
	if station.structure_health:
		station.structure_health.damage_taken.connect(_on_damage_taken)


func _process(delta: float) -> void:
	if _station == null or _weapon_manager == null:
		return

	# Decay old threats
	_decay_threats()

	# Periodic scan for best target
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		var prev_target = _current_target
		_current_target = _find_best_target()
		# Alert guards when station acquires a new hostile target
		if _current_target != null and _current_target != prev_target:
			alert_guards(_current_target)
			_guard_alert_timer = GUARD_REALERT_INTERVAL

	# Re-alert guards periodically while we have a target (in case they disengaged)
	if _current_target != null:
		_guard_alert_timer -= delta
		if _guard_alert_timer <= 0.0:
			_guard_alert_timer = GUARD_REALERT_INTERVAL
			alert_guards(_current_target)

	# Validate current target
	if _current_target != null and not is_instance_valid(_current_target):
		_current_target = null

	# Update turrets
	_weapon_manager.update_turrets(_current_target)


func _on_damage_taken(attacker: Node3D, amount: float) -> void:
	var effective_attacker: Node3D = attacker
	# If attacker is null (e.g. multiplayer node resolution failed),
	# scan for the nearest hostile as fallback
	if effective_attacker == null or not is_instance_valid(effective_attacker):
		effective_attacker = _find_nearest_hostile()
		if effective_attacker == null:
			return
	var aid: int = effective_attacker.get_instance_id()
	if _threat_table.has(aid):
		_threat_table[aid]["last_hit_time"] = Time.get_ticks_msec() * 0.001
		_threat_table[aid]["total_damage"] += amount
	else:
		_threat_table[aid] = {
			"node_ref": effective_attacker,
			"last_hit_time": Time.get_ticks_msec() * 0.001,
			"total_damage": amount,
		}
	alert_guards(effective_attacker)


func _decay_threats() -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	var to_remove: Array[int] = []
	for aid in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		if now - entry["last_hit_time"] > THREAT_DECAY_TIME:
			to_remove.append(aid)
		elif not is_instance_valid(entry["node_ref"]):
			to_remove.append(aid)
	for aid in to_remove:
		_threat_table.erase(aid)


func _find_best_target() -> Node3D:
	if _station == null:
		return null

	var station_pos: Vector3 = _station.global_position
	var best_node: Node3D = null
	var best_score: float = -1.0

	# Priority 1: Ships in threat table (sorted by cumulative damage)
	# No range limit — they already attacked us, target them regardless of distance
	for aid in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		var node: Node3D = entry["node_ref"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var score: float = entry["total_damage"]
		if score > best_score:
			best_score = score
			best_node = node

	if best_node != null:
		return best_node

	# Priority 2: Any hostile-faction ship in range (proactive defense)
	var station_faction: StringName = _station.faction if "faction" in _station else &"nova_terra"
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == null or not is_instance_valid(ship) or ship.is_queued_for_deletion():
			continue
		# Skip our own guards
		var brain = ship.get_node_or_null("AIBrain")
		if brain and brain.guard_station == _station:
			continue
		# Check faction — target hostile/pirate/lawless ships
		var ship_faction: StringName = ship.faction if "faction" in ship else &""
		if ship_faction == &"" or ship_faction == station_faction:
			continue
		# Skip player-side factions (don't fire at players/fleet unprovoked)
		if ship_faction == &"neutral" or ship_faction == &"player" or ship_faction == &"player_fleet" or ship_faction == &"friendly":
			continue
		# Skip same-faction NPCs and non-hostile factions
		if ship_faction != &"hostile" and ship_faction != &"pirate" and ship_faction != &"lawless":
			# Use FactionManager for dynamic faction wars
			var gi = GameManager.get_node_or_null("GameplayIntegrator")
			if gi:
				var fm = gi.get_node_or_null("FactionManager")
				if fm and not fm.are_enemies(station_faction, ship_faction):
					continue
		var dist: float = station_pos.distance_to(ship.global_position)
		if dist > DETECTION_RANGE:
			continue
		# Check if target is alive
		var health = ship.get_node_or_null("HealthSystem")
		if health and health.is_dead():
			continue
		# Pick closest hostile
		var score: float = DETECTION_RANGE - dist
		if score > best_score:
			best_score = score
			best_node = ship

	return best_node


func _find_nearest_hostile() -> Node3D:
	if _station == null:
		return null
	var station_pos: Vector3 = _station.global_position
	var nearest: Node3D = null
	var nearest_dist: float = DETECTION_RANGE * 2.0
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == null or not is_instance_valid(ship) or ship.is_queued_for_deletion():
			continue
		var ship_faction: StringName = ship.faction if "faction" in ship else &""
		if ship_faction == &"" or ship_faction == &"neutral" or ship_faction == &"friendly":
			continue
		# Players are valid targets when they're shooting us
		var dist: float = station_pos.distance_to(ship.global_position)
		if dist < nearest_dist:
			var health = ship.get_node_or_null("HealthSystem")
			if health and health.is_dead():
				continue
			nearest_dist = dist
			nearest = ship
	return nearest


func alert_guards(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	# Add attacker to station's own threat table (turrets will fire)
	var aid: int = attacker.get_instance_id()
	if not _threat_table.has(aid):
		_threat_table[aid] = {
			"node_ref": attacker,
			"last_hit_time": Time.get_ticks_msec() * 0.001,
			"total_damage": 50.0,
		}
	# Alert all guard NPCs
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == null or not is_instance_valid(ship):
			continue
		var brain = ship.get_node_or_null("AIBrain")
		if brain and brain.guard_station == _station:
			brain.alert_to_threat(attacker)
