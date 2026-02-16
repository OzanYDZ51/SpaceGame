package model

import "time"

// ChatMessage represents a stored chat message row.
type ChatMessage struct {
	ID         int64     `json:"id"`
	Channel    int       `json:"channel"`
	SystemID   int       `json:"system_id"`
	SenderName string    `json:"sender_name"`
	Text       string    `json:"text"`
	CreatedAt  time.Time `json:"created_at"`
}

// ChatPostRequest is the payload for storing a new chat message.
type ChatPostRequest struct {
	Channel    int    `json:"channel"`
	SystemID   int    `json:"system_id"`
	SenderName string `json:"sender_name"`
	Text       string `json:"text"`
}
