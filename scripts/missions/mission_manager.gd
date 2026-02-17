class_name MissionManager
extends Node

# =============================================================================
# Mission Manager - Tracks accepted missions, processes kill events, awards
# completion rewards. Add as child of GameManager.
# =============================================================================

signal mission_accepted(mission: MissionData)
signal mission_completed(mission: MissionData)
signal mission_failed(mission: MissionData)
signal mission_progress(mission: MissionData, objective_idx: int)

const MAX_ACTIVE: int = 5

var _active_missions: Array[MissionData] = []
var _completed_ids: Dictionary = {}  # mission_id -> true (prevents re-accept)


# =============================================================================
# MISSION LIFECYCLE
# =============================================================================

## Accept a mission. Returns false if at capacity or already accepted/completed.
func accept_mission(mission: MissionData) -> bool:
	if mission == null:
		return false
	if _active_missions.size() >= MAX_ACTIVE:
		return false
	if has_mission(mission.mission_id):
		return false
	if _completed_ids.has(mission.mission_id):
		return false

	_active_missions.append(mission)
	mission_accepted.emit(mission)
	return true


## Abandon (remove) a mission by ID.
func abandon_mission(mission_id: String) -> void:
	for i in _active_missions.size():
		if _active_missions[i].mission_id == mission_id:
			_active_missions.remove_at(i)
			return


## Get all active missions.
func get_active_missions() -> Array[MissionData]:
	return _active_missions


## Get the count of active missions.
func get_active_count() -> int:
	return _active_missions.size()


## Check if a mission is currently active.
func has_mission(mission_id: String) -> bool:
	for m in _active_missions:
		if m.mission_id == mission_id:
			return true
	return false


# =============================================================================
# EVENT PROCESSING
# =============================================================================

## Called when an NPC is killed. Checks all active kill/cargo_hunt missions for
## matching objectives and increments progress.
func on_npc_killed(npc_faction: StringName, system_id: int, ship_class: StringName = &"") -> void:
	var faction_str: String = String(npc_faction)
	var class_str: String = String(ship_class)

	for m in _active_missions:
		if m.is_completed or m.is_failed:
			continue
		if m.mission_type != &"kill" and m.mission_type != &"cargo_hunt":
			continue
		# Mission must be in the same system (or -1 = any system)
		if m.system_id >= 0 and m.system_id != system_id:
			continue

		for obj_idx in m.objectives.size():
			var obj: Dictionary = m.objectives[obj_idx]
			if obj.get("type", "") != "kill":
				continue
			# Check faction match
			var target_fac: String = obj.get("target_faction", "")
			if target_fac != "" and target_fac != faction_str:
				continue
			# Check ship class match (cargo_hunt requires specific class)
			var target_class: String = obj.get("target_ship_class", "")
			if target_class != "" and target_class != class_str:
				continue
			# Check if objective already done
			var current: int = obj.get("current", 0)
			var count: int = obj.get("count", 1)
			if current >= count:
				continue

			# Increment progress
			obj["current"] = current + 1
			mission_progress.emit(m, obj_idx)

			# Check overall completion
			if m.check_completion():
				_complete_mission(m)
			break  # Only credit one objective per kill per mission


## Complete a mission: mark done, remove from active, record in completed.
func _complete_mission(mission: MissionData) -> void:
	mission.is_completed = true
	_completed_ids[mission.mission_id] = true
	_active_missions.erase(mission)
	mission_completed.emit(mission)


## Fail a mission: mark failed, remove from active.
func _fail_mission(mission: MissionData) -> void:
	mission.is_failed = true
	_active_missions.erase(mission)
	mission_failed.emit(mission)


# =============================================================================
# TICK (timed missions)
# =============================================================================

func _process(delta: float) -> void:
	# Iterate backwards so removal during iteration is safe
	for i in range(_active_missions.size() - 1, -1, -1):
		var m: MissionData = _active_missions[i]
		if m.is_completed or m.is_failed:
			continue
		if m.time_limit > 0.0 and m.time_remaining > 0.0:
			m.time_remaining -= delta
			if m.time_remaining <= 0.0:
				m.time_remaining = 0.0
				_fail_mission(m)


# =============================================================================
# SERIALIZATION (save/load)
# =============================================================================

func serialize() -> Dictionary:
	var active_list: Array = []
	for m in _active_missions:
		active_list.append(m.serialize())
	var completed_list: Array = []
	for mid in _completed_ids:
		completed_list.append(mid)
	return {
		"active_missions": active_list,
		"completed_ids": completed_list,
	}


func deserialize(data: Dictionary) -> void:
	_active_missions.clear()
	_completed_ids.clear()

	var active_raw: Array = data.get("active_missions", []) if data.get("active_missions") is Array else []
	for raw in active_raw:
		if raw is Dictionary:
			var m := MissionData.deserialize(raw)
			_active_missions.append(m)

	var completed_raw: Array = data.get("completed_ids", []) if data.get("completed_ids") is Array else []
	for mid in completed_raw:
		_completed_ids[mid] = true
