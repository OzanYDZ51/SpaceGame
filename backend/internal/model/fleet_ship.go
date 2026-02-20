package model

import (
	"encoding/json"
	"time"
)

// FleetShipDB represents a single fleet ship row in the database.
type FleetShipDB struct {
	ID              int64            `json:"id"`
	PlayerID        string           `json:"player_id"`
	FleetIndex      int              `json:"fleet_index"`
	ShipID          string           `json:"ship_id"`
	CustomName      string           `json:"custom_name"`
	DeploymentState int              `json:"deployment_state"` // 0=DOCKED, 1=DEPLOYED, 2=DESTROYED
	SystemID        int              `json:"system_id"`
	StationID       string           `json:"station_id"`
	PosX            float64          `json:"pos_x"`
	PosY            float64          `json:"pos_y"`
	PosZ            float64          `json:"pos_z"`
	Command         string           `json:"command"`
	CommandParams   json.RawMessage  `json:"command_params"`
	Weapons         json.RawMessage  `json:"weapons"`
	ShieldName      string           `json:"shield_name"`
	EngineName      string           `json:"engine_name"`
	Modules         json.RawMessage  `json:"modules"`
	Cargo           json.RawMessage  `json:"cargo"`
	ShipResources   json.RawMessage  `json:"ship_resources"`
	HullRatio       float32          `json:"hull_ratio"`
	ShieldRatio     float32          `json:"shield_ratio"`
	SquadronID      int              `json:"squadron_id"`
	SquadronRole    string           `json:"squadron_role"`
	DeployedAt      *time.Time       `json:"deployed_at,omitempty"`
	DestroyedAt     *time.Time       `json:"destroyed_at,omitempty"`
	UpdatedAt       time.Time        `json:"updated_at"`
}

// FleetSyncUpdate is the payload for batch position/health sync from the game server.
type FleetSyncUpdate struct {
	PlayerID      string          `json:"player_id"`
	FleetIndex    int             `json:"fleet_index"`
	PosX          float64         `json:"pos_x"`
	PosY          float64         `json:"pos_y"`
	PosZ          float64         `json:"pos_z"`
	HullRatio     float32         `json:"hull_ratio"`
	ShieldRatio   float32         `json:"shield_ratio"`
	Command       string          `json:"command,omitempty"`
	CommandParams json.RawMessage `json:"command_params,omitempty"`
}

// FleetDeathReport is the payload when a fleet ship is destroyed.
type FleetDeathReport struct {
	PlayerID   string `json:"player_id"`
	FleetIndex int    `json:"fleet_index"`
}
