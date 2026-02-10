class_name StationDefenseAI
extends Node

# =============================================================================
# Station Defense AI — Scans for hostiles and fires turrets automatically.
# =============================================================================

const SCAN_INTERVAL: float = 0.5
const DETECTION_RANGE: float = 2000.0
const THREAT_DECAY_TIME: float = 30.0

var _station: SpaceStation = null
var _weapon_manager: WeaponManager = null
var _current_target: Node3D = null
var _scan_timer: float = 0.0

# Threat table: node instance_id -> {node_ref, last_hit_time, total_damage}
var _threat_table: Dictionary = {}


func initialize(station: SpaceStation, wm: WeaponManager) -> void:
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
		_current_target = _find_best_target()

	# Validate current target
	if _current_target != null and not is_instance_valid(_current_target):
		_current_target = null

	# Update turrets
	_weapon_manager.update_turrets(_current_target)


func _on_damage_taken(attacker: Node3D, amount: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var aid: int = attacker.get_instance_id()
	if _threat_table.has(aid):
		_threat_table[aid]["last_hit_time"] = Time.get_ticks_msec() * 0.001
		_threat_table[aid]["total_damage"] += amount
	else:
		_threat_table[aid] = {
			"node_ref": attacker,
			"last_hit_time": Time.get_ticks_msec() * 0.001,
			"total_damage": amount,
		}


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

	# Priority 1: Ships in threat table within range (sorted by cumulative damage)
	for aid in _threat_table:
		var entry: Dictionary = _threat_table[aid]
		var node: Node3D = entry["node_ref"]
		if not is_instance_valid(node):
			continue
		var dist: float = station_pos.distance_to(node.global_position)
		if dist > DETECTION_RANGE:
			continue
		var score: float = entry["total_damage"]
		if score > best_score:
			best_score = score
			best_node = node

	if best_node != null:
		return best_node

	# Priority 2: Any hostile ship in range from "ships" group
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == null or not is_instance_valid(ship):
			continue
		# Skip player
		if ship == GameManager.player_ship:
			continue
		# Only target hostile NPCs (faction check via AIBrain)
		var brain := ship.get_node_or_null("AIBrain") as AIBrain
		if brain == null:
			continue
		# Target ships that are in ATTACK or PURSUE state (actively hostile)
		if brain.current_state != AIBrain.State.ATTACK and brain.current_state != AIBrain.State.PURSUE:
			continue
		var dist: float = station_pos.distance_to(ship.global_position)
		if dist > DETECTION_RANGE:
			continue
		# Pick closest hostile
		var score: float = DETECTION_RANGE - dist
		if score > best_score:
			best_score = score
			best_node = ship

	return best_node
