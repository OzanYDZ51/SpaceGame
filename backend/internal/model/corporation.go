package model

import "time"

type Corporation struct {
	ID              string    `json:"id"`
	CorporationName string    `json:"corporation_name"`
	CorporationTag  string    `json:"corporation_tag"`
	Description     string    `json:"description"`
	Motto           string    `json:"motto"`
	MOTD            string    `json:"motd"`
	CorporationColor string   `json:"corporation_color"`
	EmblemID        int       `json:"emblem_id"`
	Treasury        int64     `json:"treasury"`
	Reputation      int       `json:"reputation"`
	MaxMembers      int       `json:"max_members"`
	IsRecruiting    bool      `json:"is_recruiting"`
	MemberCount     int       `json:"member_count,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type CorporationRank struct {
	ID            int64  `json:"id"`
	CorporationID string `json:"corporation_id"`
	RankName      string `json:"rank_name"`
	Priority      int    `json:"priority"`
	Permissions   int    `json:"permissions"`
}

type CorporationMember struct {
	PlayerID      string    `json:"player_id"`
	Username      string    `json:"username"`
	CorporationID string    `json:"corporation_id"`
	RankPriority  int       `json:"rank_priority"`
	RankName      string    `json:"rank_name,omitempty"`
	Contribution  int64     `json:"contribution"`
	JoinedAt      time.Time `json:"joined_at"`
	IsOnline      bool      `json:"is_online,omitempty"`
}

type CorporationActivity struct {
	ID         int64     `json:"id"`
	CorporationID string `json:"corporation_id"`
	EventType  int       `json:"event_type"`
	ActorName  string    `json:"actor_name"`
	TargetName string    `json:"target_name"`
	Details    string    `json:"details"`
	CreatedAt  time.Time `json:"created_at"`
}

type CorporationDiplomacy struct {
	CorporationID       string    `json:"corporation_id"`
	TargetCorporationID string    `json:"target_corporation_id"`
	TargetName          string    `json:"target_name,omitempty"`
	TargetTag           string    `json:"target_tag,omitempty"`
	Relation            string    `json:"relation"`
	Since               time.Time `json:"since"`
}

type CorporationTransaction struct {
	ID            int64     `json:"id"`
	CorporationID string    `json:"corporation_id"`
	PlayerID      *string   `json:"player_id,omitempty"`
	ActorName     string    `json:"actor_name"`
	TxType        string    `json:"tx_type"`
	Amount        int64     `json:"amount"`
	CreatedAt     time.Time `json:"created_at"`
}

// Request types

type CreateCorporationRequest struct {
	CorporationName  string `json:"corporation_name"`
	CorporationTag   string `json:"corporation_tag"`
	Description      string `json:"description"`
	Motto            string `json:"motto"`
	CorporationColor string `json:"corporation_color"`
	EmblemID         int    `json:"emblem_id"`
}

type UpdateCorporationRequest struct {
	Description      *string `json:"description,omitempty"`
	Motto            *string `json:"motto,omitempty"`
	MOTD             *string `json:"motd,omitempty"`
	CorporationColor *string `json:"corporation_color,omitempty"`
	EmblemID         *int    `json:"emblem_id,omitempty"`
	IsRecruiting     *bool   `json:"is_recruiting,omitempty"`
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
	TargetCorporationID string `json:"target_corporation_id"`
	Relation            string `json:"relation"`
}

type CreateRankRequest struct {
	RankName    string `json:"rank_name"`
	Priority    int    `json:"priority"`
	Permissions int    `json:"permissions"`
}

type UpdateRankRequest struct {
	RankName    string `json:"rank_name"`
	Permissions int    `json:"permissions"`
}
