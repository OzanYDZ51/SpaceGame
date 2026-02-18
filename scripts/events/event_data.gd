class_name EventData
extends RefCounted

# =============================================================================
# Event Data — Data container for an active random event.
# =============================================================================

var event_id: String = ""            # "evt_<system_id>_<counter>"
var event_type: StringName = &""     # &"pirate_convoy" etc.
var tier: int = 1                    # 1/2/3
var system_id: int = -1
var center_x: float = 0.0           # universe float64 spawn center
var center_z: float = 0.0
var waypoints: Array[Vector3] = []   # patrol waypoints (local coords relative to center)
var npc_ids: Array[StringName] = []  # all NPCs spawned for this event
var leader_id: StringName = &""      # the freighter (bonus loot on kill)
var spawn_time: float = 0.0         # unix time
var duration: float = 600.0         # seconds before despawn
var is_active: bool = true
var faction: StringName = &"pirate"


func get_time_remaining() -> float:
	return maxf(0.0, (spawn_time + duration) - Time.get_unix_time_from_system())


func is_expired() -> bool:
	return Time.get_unix_time_from_system() > spawn_time + duration


## Serialize for RPC: event start notification.
func to_start_dict() -> Dictionary:
	return {
		"eid": event_id,
		"type": String(event_type),
		"tier": tier,
		"name": get_display_name(),
		"color": get_color().to_html(),
		"cx": center_x,
		"cz": center_z,
		"dur": duration,
		"t0": spawn_time,
		"lid": String(leader_id),
		"sys": system_id,
	}


## Build an event-end RPC dict (static — doesn't require a live EventData).
static func make_end_dict(eid: String, etype: String, t: int, was_completed: bool, killer_pid: int, bonus: int, sys: int) -> Dictionary:
	return {
		"eid": eid,
		"type": etype,
		"tier": t,
		"done": was_completed,
		"killer": killer_pid,
		"bonus": bonus,
		"sys": sys,
	}


func get_display_name() -> String:
	match event_type:
		&"pirate_convoy":
			match tier:
				1: return "CONVOI PIRATE"
				2: return "CONVOI PIRATE LOURD"
				3: return "ARMADA PIRATE"
	return "ÉVÉNEMENT"


func get_color() -> Color:
	match tier:
		1: return Color(1.0, 0.9, 0.2)    # yellow
		2: return Color(1.0, 0.6, 0.0)    # orange
		3: return Color(1.0, 0.2, 0.15)   # red
	return Color(1.0, 0.9, 0.2)
