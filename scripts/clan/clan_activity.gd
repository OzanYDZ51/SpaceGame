class_name ClanActivity
extends RefCounted

# =============================================================================
# Clan Activity - Log entry for clan events
# =============================================================================

enum EventType { JOIN, LEAVE, PROMOTE, DEMOTE, KICK, DEPOSIT, WITHDRAW, DIPLOMACY, MOTD_CHANGE, RANK_CHANGE, CREATED }

const EVENT_COLORS := {
	EventType.JOIN: Color(0.0, 1.0, 0.6, 0.9),
	EventType.LEAVE: Color(1.0, 0.7, 0.1, 0.9),
	EventType.PROMOTE: Color(0.15, 0.85, 1.0, 0.9),
	EventType.DEMOTE: Color(1.0, 0.55, 0.1, 0.9),
	EventType.KICK: Color(1.0, 0.2, 0.15, 0.9),
	EventType.DEPOSIT: Color(0.0, 1.0, 0.6, 0.9),
	EventType.WITHDRAW: Color(1.0, 0.7, 0.1, 0.9),
	EventType.DIPLOMACY: Color(0.5, 0.3, 1.0, 0.9),
	EventType.MOTD_CHANGE: Color(0.15, 0.85, 1.0, 0.9),
	EventType.RANK_CHANGE: Color(0.15, 0.85, 1.0, 0.9),
	EventType.CREATED: Color(1.0, 0.85, 0.2, 0.9),
}

const EVENT_LABELS := {
	EventType.JOIN: "REJOINT",
	EventType.LEAVE: "QUITTE",
	EventType.PROMOTE: "PROMU",
	EventType.DEMOTE: "RETROGR.",
	EventType.KICK: "EXPULSE",
	EventType.DEPOSIT: "DEPOT",
	EventType.WITHDRAW: "RETRAIT",
	EventType.DIPLOMACY: "DIPLO.",
	EventType.MOTD_CHANGE: "MOTD",
	EventType.RANK_CHANGE: "RANG",
	EventType.CREATED: "CREATION",
}

var timestamp: int = 0
var event_type: EventType = EventType.JOIN
var actor_name: String = ""
var target_name: String = ""
var details: String = ""
