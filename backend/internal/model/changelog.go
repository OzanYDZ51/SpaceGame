package model

import "time"

// Changelog represents a version entry displayed in the launcher and Discord.
type Changelog struct {
	ID        int64     `json:"id"`
	Version   string    `json:"version"`
	Summary   string    `json:"summary"`
	IsMajor   bool      `json:"is_major"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateChangelogRequest is sent by CI to record a new changelog entry.
type CreateChangelogRequest struct {
	Version string `json:"version"`
	Summary string `json:"summary"`
	IsMajor bool   `json:"is_major,omitempty"`
}
