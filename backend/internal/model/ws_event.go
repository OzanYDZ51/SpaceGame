package model

import "encoding/json"

type WSEvent struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data,omitempty"`
}

type WSAnnounce struct {
	Message string `json:"message"`
}
