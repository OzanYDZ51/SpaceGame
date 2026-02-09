package model

import (
	"encoding/json"
	"time"
)

// GameEvent represents a notable in-game event recorded in the DB.
type GameEvent struct {
	ID        int64           `json:"id"`
	EventType string          `json:"event_type"`
	ActorName string          `json:"actor_name,omitempty"`
	TargetName string         `json:"target_name,omitempty"`
	Details   json.RawMessage `json:"details,omitempty"`
	SystemID  int             `json:"system_id,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
}

// GameEventRequest is sent by the game server to record an event.
type GameEventRequest struct {
	Type       string          `json:"type"`
	Killer     string          `json:"killer,omitempty"`
	Victim     string          `json:"victim,omitempty"`
	Weapon     string          `json:"weapon,omitempty"`
	System     string          `json:"system,omitempty"`
	SystemID   int             `json:"system_id,omitempty"`
	ActorName  string          `json:"actor_name,omitempty"`
	TargetName string          `json:"target_name,omitempty"`
	Details    json.RawMessage `json:"details,omitempty"`
}

// BugReportRequest is sent by a player to report a bug.
type BugReportRequest struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	SystemID     int    `json:"system_id"`
	Position     string `json:"position"`
	ScreenshotB64 string `json:"screenshot_b64,omitempty"`
}
