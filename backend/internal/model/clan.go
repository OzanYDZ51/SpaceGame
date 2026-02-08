package model

import "time"

type Clan struct {
	ID           string    `json:"id"`
	ClanName     string    `json:"clan_name"`
	ClanTag      string    `json:"clan_tag"`
	Description  string    `json:"description"`
	Motto        string    `json:"motto"`
	MOTD         string    `json:"motd"`
	ClanColor    string    `json:"clan_color"`
	EmblemID     int       `json:"emblem_id"`
	Treasury     int64     `json:"treasury"`
	Reputation   int       `json:"reputation"`
	MaxMembers   int       `json:"max_members"`
	IsRecruiting bool      `json:"is_recruiting"`
	MemberCount  int       `json:"member_count,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type ClanRank struct {
	ID          int64  `json:"id"`
	ClanID      string `json:"clan_id"`
	RankName    string `json:"rank_name"`
	Priority    int    `json:"priority"`
	Permissions int    `json:"permissions"`
}

type ClanMember struct {
	PlayerID     string    `json:"player_id"`
	Username     string    `json:"username"`
	ClanID       string    `json:"clan_id"`
	RankPriority int       `json:"rank_priority"`
	RankName     string    `json:"rank_name,omitempty"`
	Contribution int64     `json:"contribution"`
	JoinedAt     time.Time `json:"joined_at"`
	IsOnline     bool      `json:"is_online,omitempty"`
}

type ClanActivity struct {
	ID         int64     `json:"id"`
	ClanID     string    `json:"clan_id"`
	EventType  int       `json:"event_type"`
	ActorName  string    `json:"actor_name"`
	TargetName string    `json:"target_name"`
	Details    string    `json:"details"`
	CreatedAt  time.Time `json:"created_at"`
}

type ClanDiplomacy struct {
	ClanID       string    `json:"clan_id"`
	TargetClanID string    `json:"target_clan_id"`
	TargetName   string    `json:"target_name,omitempty"`
	TargetTag    string    `json:"target_tag,omitempty"`
	Relation     string    `json:"relation"`
	Since        time.Time `json:"since"`
}

type ClanTransaction struct {
	ID        int64     `json:"id"`
	ClanID    string    `json:"clan_id"`
	PlayerID  *string   `json:"player_id,omitempty"`
	ActorName string    `json:"actor_name"`
	TxType    string    `json:"tx_type"`
	Amount    int64     `json:"amount"`
	CreatedAt time.Time `json:"created_at"`
}

// Request types

type CreateClanRequest struct {
	ClanName    string `json:"clan_name"`
	ClanTag     string `json:"clan_tag"`
	Description string `json:"description"`
	Motto       string `json:"motto"`
	ClanColor   string `json:"clan_color"`
	EmblemID    int    `json:"emblem_id"`
}

type UpdateClanRequest struct {
	Description  *string `json:"description,omitempty"`
	Motto        *string `json:"motto,omitempty"`
	MOTD         *string `json:"motd,omitempty"`
	ClanColor    *string `json:"clan_color,omitempty"`
	EmblemID     *int    `json:"emblem_id,omitempty"`
	IsRecruiting *bool   `json:"is_recruiting,omitempty"`
}

type AddMemberRequest struct {
	PlayerID string `json:"player_id"`
}

type SetRankRequest struct {
	RankPriority int `json:"rank_priority"`
}

type TreasuryRequest struct {
	Amount int64 `json:"amount"`
}

type SetDiplomacyRequest struct {
	TargetClanID string `json:"target_clan_id"`
	Relation     string `json:"relation"`
}
