class_name ClanRank
extends Resource

# =============================================================================
# Clan Rank - Defines a rank with permission bitfield
# =============================================================================

const PERM_INVITE       := 1 << 0
const PERM_KICK         := 1 << 1
const PERM_PROMOTE      := 1 << 2
const PERM_DEMOTE       := 1 << 3
const PERM_EDIT_MOTD    := 1 << 4
const PERM_WITHDRAW     := 1 << 5
const PERM_DIPLOMACY    := 1 << 6
const PERM_MANAGE_RANKS := 1 << 7
const ALL_PERMISSIONS   := 0xFF

const PERM_NAMES := {
	PERM_INVITE: "Inviter des membres",
	PERM_KICK: "Expulser des membres",
	PERM_PROMOTE: "Promouvoir",
	PERM_DEMOTE: "Retrograder",
	PERM_EDIT_MOTD: "Modifier le MOTD",
	PERM_WITHDRAW: "Retirer des fonds",
	PERM_DIPLOMACY: "Gerer la diplomatie",
	PERM_MANAGE_RANKS: "Gerer les rangs",
}

@export var rank_name: String = ""
@export var priority: int = 0
@export var permissions: int = 0


func has_permission(perm: int) -> bool:
	return (permissions & perm) != 0
