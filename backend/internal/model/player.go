package model

import (
	"encoding/json"
	"time"
)

type Player struct {
	ID            string     `json:"id"`
	Username      string     `json:"username"`
	Email         string     `json:"email,omitempty"`
	PasswordHash  string     `json:"-"`
	CurrentShipID string     `json:"current_ship_id"`
	GalaxySeed    int64      `json:"galaxy_seed"`
	SystemID      int        `json:"system_id"`
	PosX          float64    `json:"pos_x"`
	PosY          float64    `json:"pos_y"`
	PosZ          float64    `json:"pos_z"`
	RotationX     float64    `json:"rotation_x"`
	RotationY     float64    `json:"rotation_y"`
	RotationZ     float64    `json:"rotation_z"`
	Credits       int64      `json:"credits"`
	Kills         int        `json:"kills"`
	Deaths        int        `json:"deaths"`
	ClanID        *string    `json:"clan_id,omitempty"`
	IsBanned      bool       `json:"is_banned"`
	LastLoginAt   *time.Time `json:"last_login_at,omitempty"`
	LastSaveAt    *time.Time `json:"last_save_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type PlayerProfile struct {
	ID            string  `json:"id"`
	Username      string  `json:"username"`
	CurrentShipID string  `json:"current_ship_id"`
	Kills         int     `json:"kills"`
	Deaths        int     `json:"deaths"`
	ClanID        *string `json:"clan_id,omitempty"`
	ClanName      *string `json:"clan_name,omitempty"`
	ClanTag       *string `json:"clan_tag,omitempty"`
}

type PlayerResource struct {
	ResourceID string `json:"resource_id"`
	Quantity   int    `json:"quantity"`
}

type InventoryItem struct {
	Category string `json:"category"`
	ItemName string `json:"item_name"`
	Quantity int    `json:"quantity"`
}

type CargoItem struct {
	ItemName  string  `json:"item_name"`
	ItemType  string  `json:"item_type"`
	Quantity  int     `json:"quantity"`
	IconColor *string `json:"icon_color,omitempty"`
}

type PlayerEquipment struct {
	Hardpoints json.RawMessage `json:"hardpoints"`
	ShieldName *string         `json:"shield_name,omitempty"`
	EngineName *string         `json:"engine_name,omitempty"`
	Modules    json.RawMessage `json:"modules"`
}

// PlayerState is the full save/load payload
type PlayerState struct {
	CurrentShipID string          `json:"current_ship_id"`
	GalaxySeed    int64           `json:"galaxy_seed"`
	SystemID      int             `json:"system_id"`
	PosX          float64         `json:"pos_x"`
	PosY          float64         `json:"pos_y"`
	PosZ          float64         `json:"pos_z"`
	RotationX     float64         `json:"rotation_x"`
	RotationY     float64         `json:"rotation_y"`
	RotationZ     float64         `json:"rotation_z"`
	Credits       int64           `json:"credits"`
	Kills         int             `json:"kills"`
	Deaths        int             `json:"deaths"`
	Resources     []PlayerResource `json:"resources"`
	Inventory     []InventoryItem  `json:"inventory"`
	Cargo         []CargoItem      `json:"cargo"`
	Equipment     *PlayerEquipment `json:"equipment,omitempty"`
	Fleet           json.RawMessage  `json:"fleet,omitempty"`
	StationServices json.RawMessage  `json:"station_services,omitempty"`
	Settings        json.RawMessage  `json:"settings,omitempty"`
	// Gameplay integrator state (stored as single gameplay_state JSONB column)
	Missions   json.RawMessage `json:"missions,omitempty"`
	Factions   json.RawMessage `json:"factions,omitempty"`
	EconomySim json.RawMessage `json:"economy_sim,omitempty"`
	Pois       json.RawMessage `json:"pois,omitempty"`
}
