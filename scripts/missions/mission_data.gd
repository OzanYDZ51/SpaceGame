class_name MissionData
extends RefCounted

# =============================================================================
# Mission Data - Runtime mission instance (generated procedurally per station)
# Lightweight RefCounted — not a Resource, no disk persistence by default.
# =============================================================================

# --- Identity ---
var mission_id: String = ""
var mission_type: StringName = &""  # &"kill", &"cargo_hunt"
var title: String = ""
var description: String = ""

# --- Context ---
var faction_id: StringName = &""  # Which faction gives this mission
var system_id: int = -1           # Where the mission takes place
var danger_level: int = 1         # Difficulty 1-5

# --- Rewards ---
var reward_credits: int = 0
var reward_reputation: float = 0.0

# --- Objectives ---
# Each: {"type": "kill", "target_faction": "hostile", "count": 3, "current": 0, "label": "..."}
var objectives: Array[Dictionary] = []

# --- State ---
var is_completed: bool = false
var is_failed: bool = false

# --- Time ---
var time_limit: float = -1.0      # Seconds, -1 = no limit
var time_remaining: float = -1.0


## Check if a specific objective is complete.
func is_objective_complete(idx: int) -> bool:
	if idx < 0 or idx >= objectives.size():
		return false
	var obj: Dictionary = objectives[idx]
	return obj.get("current", 0) >= obj.get("count", 1)


## Returns a human-readable progress string for display.
func get_progress_text() -> String:
	if is_completed:
		return "TERMINEE"
	if is_failed:
		return "ECHOUEE"

	var parts: PackedStringArray = PackedStringArray()
	for obj in objectives:
		var current: int = obj.get("current", 0)
		var total: int = obj.get("count", 1)
		var label: String = obj.get("label", "Objectif")
		parts.append("%s (%d/%d)" % [label, current, total])
	return " | ".join(parts)


## Check if ALL objectives are done. Sets is_completed if so. Returns true on completion.
func check_completion() -> bool:
	if is_completed or is_failed:
		return is_completed
	for obj in objectives:
		if obj.get("current", 0) < obj.get("count", 1):
			return false
	is_completed = true
	return true


## Serialize to Dictionary for save/load.
func serialize() -> Dictionary:
	var obj_list: Array = []
	for obj in objectives:
		obj_list.append(obj.duplicate())
	return {
		"mission_id": mission_id,
		"mission_type": String(mission_type),
		"title": title,
		"description": description,
		"faction_id": String(faction_id),
		"system_id": system_id,
		"danger_level": danger_level,
		"reward_credits": reward_credits,
		"reward_reputation": reward_reputation,
		"objectives": obj_list,
		"is_completed": is_completed,
		"is_failed": is_failed,
		"time_limit": time_limit,
		"time_remaining": time_remaining,
	}


## Create a MissionData from a serialized Dictionary.
static func deserialize(data: Dictionary) -> MissionData:
	var m := MissionData.new()
	m.mission_id = data.get("mission_id", "")
	m.mission_type = StringName(data.get("mission_type", ""))
	m.title = data.get("title", "")
	m.description = data.get("description", "")
	m.faction_id = StringName(data.get("faction_id", ""))
	m.system_id = int(data.get("system_id", -1))
	m.danger_level = int(data.get("danger_level", 1))
	m.reward_credits = int(data.get("reward_credits", 0))
	m.reward_reputation = float(data.get("reward_reputation", 0.0))
	m.is_completed = data.get("is_completed", false)
	m.is_failed = data.get("is_failed", false)
	m.time_limit = float(data.get("time_limit", -1.0))
	m.time_remaining = float(data.get("time_remaining", -1.0))

	var obj_raw: Array = data.get("objectives", []) if data.get("objectives") is Array else []
	m.objectives.clear()
	for obj in obj_raw:
		m.objectives.append(obj.duplicate() if obj is Dictionary else {})
	return m
