class_name ClanData
extends Resource

# =============================================================================
# Clan Data - Identity, stats, ranks, and settings for a clan
# =============================================================================

# Identity
@export var clan_id: String = ""
@export var clan_name: String = ""
@export var clan_tag: String = ""
@export var description: String = ""
@export var motto: String = ""
@export var motd: String = ""

# Visual
@export var clan_color: Color = Color(0.15, 0.85, 1.0)
@export var emblem_id: int = 0

# Stats
@export var creation_timestamp: int = 0
@export var treasury_balance: float = 0.0
@export var reputation_score: int = 0

# Structure
@export var ranks: Array[ClanRank] = []
@export var max_members: int = 50
@export var is_recruiting: bool = true
