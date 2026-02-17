package model

import "time"

// DiscordLinkRequest is sent by the game client to confirm a Discord link code.
type DiscordLinkRequest struct {
	Code string `json:"code"`
}

// DiscordLinkStatus is returned when checking if a Discord account is linked.
type DiscordLinkStatus struct {
	Linked    bool   `json:"linked"`
	DiscordID string `json:"discord_id,omitempty"`
}

// DiscordCorporationMapping stores the relationship between a game corporation and Discord role/channel.
type DiscordCorporationMapping struct {
	CorporationID    string `json:"corporation_id"`
	DiscordRoleID    string `json:"discord_role_id"`
	DiscordChannelID string `json:"discord_channel_id"`
}

// DiscordLinkData holds link code info for a player.
type DiscordLinkData struct {
	PlayerID    string
	DiscordID   string
	LinkCode    string
	LinkExpires time.Time
}
