class_name CorporationMember
extends RefCounted

# =============================================================================
# Corporation Member - Player data within a corporation
# =============================================================================

var player_id: String = ""
var display_name: String = ""
var rank_index: int = 0
var join_timestamp: int = 0
var last_online_timestamp: int = 0
var contribution_total: float = 0.0
var kills: int = 0
var deaths: int = 0
var is_online: bool = false


func get_kd_ratio() -> float:
	if deaths == 0:
		return float(kills)
	return float(kills) / float(deaths)
