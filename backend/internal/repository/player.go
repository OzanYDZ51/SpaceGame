package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PlayerRepository struct {
	pool *pgxpool.Pool
}

func NewPlayerRepository(pool *pgxpool.Pool) *PlayerRepository {
	return &PlayerRepository{pool: pool}
}

func (r *PlayerRepository) Create(ctx context.Context, username, email, passwordHash string) (*model.Player, error) {
	p := &model.Player{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO players (username, email, password_hash)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING
		RETURNING id, username, email, password_hash, current_ship_id, galaxy_seed, system_id,
		          pos_x, pos_y, pos_z, rotation_x, rotation_y, rotation_z,
		          credits, kills, deaths, corporation_id, is_banned, last_login_at, last_save_at, created_at, updated_at
	`, username, email, passwordHash).Scan(
		&p.ID, &p.Username, &p.Email, &p.PasswordHash, &p.CurrentShipID, &p.GalaxySeed, &p.SystemID,
		&p.PosX, &p.PosY, &p.PosZ, &p.RotationX, &p.RotationY, &p.RotationZ,
		&p.Credits, &p.Kills, &p.Deaths, &p.CorporationID, &p.IsBanned, &p.LastLoginAt, &p.LastSaveAt, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("duplicate key")
		}
		return nil, err
	}
	return p, nil
}

func (r *PlayerRepository) GetByID(ctx context.Context, id string) (*model.Player, error) {
	p := &model.Player{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, username, email, password_hash, current_ship_id, galaxy_seed, system_id,
		       pos_x, pos_y, pos_z, rotation_x, rotation_y, rotation_z,
		       credits, kills, deaths, corporation_id, is_banned, last_login_at, last_save_at, created_at, updated_at
		FROM players WHERE id = $1
	`, id).Scan(
		&p.ID, &p.Username, &p.Email, &p.PasswordHash, &p.CurrentShipID, &p.GalaxySeed, &p.SystemID,
		&p.PosX, &p.PosY, &p.PosZ, &p.RotationX, &p.RotationY, &p.RotationZ,
		&p.Credits, &p.Kills, &p.Deaths, &p.CorporationID, &p.IsBanned, &p.LastLoginAt, &p.LastSaveAt, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (r *PlayerRepository) GetByUsername(ctx context.Context, username string) (*model.Player, error) {
	p := &model.Player{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, username, email, password_hash, current_ship_id, galaxy_seed, system_id,
		       pos_x, pos_y, pos_z, rotation_x, rotation_y, rotation_z,
		       credits, kills, deaths, corporation_id, is_banned, last_login_at, last_save_at, created_at, updated_at
		FROM players WHERE username = $1
	`, username).Scan(
		&p.ID, &p.Username, &p.Email, &p.PasswordHash, &p.CurrentShipID, &p.GalaxySeed, &p.SystemID,
		&p.PosX, &p.PosY, &p.PosZ, &p.RotationX, &p.RotationY, &p.RotationZ,
		&p.Credits, &p.Kills, &p.Deaths, &p.CorporationID, &p.IsBanned, &p.LastLoginAt, &p.LastSaveAt, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (r *PlayerRepository) GetProfile(ctx context.Context, id string) (*model.PlayerProfile, error) {
	p := &model.PlayerProfile{}
	err := r.pool.QueryRow(ctx, `
		SELECT p.id, p.username, p.current_ship_id, p.kills, p.deaths, p.corporation_id, c.corporation_name, c.corporation_tag
		FROM players p
		LEFT JOIN corporations c ON p.corporation_id = c.id
		WHERE p.id = $1
	`, id).Scan(&p.ID, &p.Username, &p.CurrentShipID, &p.Kills, &p.Deaths, &p.CorporationID, &p.CorporationName, &p.CorporationTag)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (r *PlayerRepository) UpdateLoginTime(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `UPDATE players SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1`, id)
	return err
}

func (r *PlayerRepository) CountTotal(ctx context.Context) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM players`).Scan(&count)
	return count, err
}

// --- Full state save/load ---

func (r *PlayerRepository) GetFullState(ctx context.Context, playerID string) (*model.PlayerState, error) {
	p, err := r.GetByID(ctx, playerID)
	if err != nil {
		return nil, err
	}

	// Fleet + StationServices + Settings + GameplayState (JSONB columns on players table)
	var fleetRaw, stationServicesRaw, settingsRaw, gameplayStateRaw []byte
	_ = r.pool.QueryRow(ctx, `SELECT fleet, station_services, settings, gameplay_state FROM players WHERE id = $1`, playerID).Scan(&fleetRaw, &stationServicesRaw, &settingsRaw, &gameplayStateRaw)

	state := &model.PlayerState{
		CurrentShipID: p.CurrentShipID,
		GalaxySeed:    p.GalaxySeed,
		SystemID:      p.SystemID,
		PosX:          p.PosX,
		PosY:          p.PosY,
		PosZ:          p.PosZ,
		RotationX:     p.RotationX,
		RotationY:     p.RotationY,
		RotationZ:     p.RotationZ,
		Credits:       p.Credits,
		Kills:         p.Kills,
		Deaths:        p.Deaths,
		Fleet:           json.RawMessage(fleetRaw),
		StationServices: json.RawMessage(stationServicesRaw),
		Settings:        json.RawMessage(settingsRaw),
	}

	// Unbundle gameplay_state JSONB into individual fields
	if len(gameplayStateRaw) > 2 { // more than "{}"
		var gp map[string]json.RawMessage
		if err := json.Unmarshal(gameplayStateRaw, &gp); err == nil {
			state.Missions = gp["missions"]
			state.Factions = gp["factions"]
			state.EconomySim = gp["economy_sim"]
			state.Pois = gp["pois"]
		}
	}

	// Resources
	rows, err := r.pool.Query(ctx, `SELECT resource_id, quantity FROM player_resources WHERE player_id = $1`, playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var res model.PlayerResource
		if err := rows.Scan(&res.ResourceID, &res.Quantity); err != nil {
			return nil, err
		}
		state.Resources = append(state.Resources, res)
	}

	// Inventory
	rows, err = r.pool.Query(ctx, `SELECT category, item_name, quantity FROM player_inventory WHERE player_id = $1`, playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var item model.InventoryItem
		if err := rows.Scan(&item.Category, &item.ItemName, &item.Quantity); err != nil {
			return nil, err
		}
		state.Inventory = append(state.Inventory, item)
	}

	// Cargo
	rows, err = r.pool.Query(ctx, `SELECT item_name, item_type, quantity, icon_color FROM player_cargo WHERE player_id = $1`, playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var item model.CargoItem
		if err := rows.Scan(&item.ItemName, &item.ItemType, &item.Quantity, &item.IconColor); err != nil {
			return nil, err
		}
		state.Cargo = append(state.Cargo, item)
	}

	// Equipment
	var eq model.PlayerEquipment
	var hardpoints, modules []byte
	err = r.pool.QueryRow(ctx, `
		SELECT hardpoints, shield_name, engine_name, modules FROM player_equipment WHERE player_id = $1
	`, playerID).Scan(&hardpoints, &eq.ShieldName, &eq.EngineName, &modules)
	if err == nil {
		eq.Hardpoints = json.RawMessage(hardpoints)
		eq.Modules = json.RawMessage(modules)
		state.Equipment = &eq
	}
	// pgx.ErrNoRows is fine — no equipment row yet

	return state, nil
}

func (r *PlayerRepository) SaveFullState(ctx context.Context, playerID string, state *model.PlayerState) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	now := time.Now()

	// Default fleet/station_services/settings to empty JSON if nil
	fleetJSON := state.Fleet
	if fleetJSON == nil {
		fleetJSON = json.RawMessage(`[]`)
	}
	stationServicesJSON := state.StationServices
	if stationServicesJSON == nil {
		stationServicesJSON = json.RawMessage(`[]`)
	}
	settingsJSON := state.Settings
	if settingsJSON == nil {
		settingsJSON = json.RawMessage(`{}`)
	}

	// Bundle gameplay state (missions, factions, economy_sim, pois) into single JSONB
	gameplayState := map[string]json.RawMessage{}
	if state.Missions != nil {
		gameplayState["missions"] = state.Missions
	}
	if state.Factions != nil {
		gameplayState["factions"] = state.Factions
	}
	if state.EconomySim != nil {
		gameplayState["economy_sim"] = state.EconomySim
	}
	if state.Pois != nil {
		gameplayState["pois"] = state.Pois
	}
	gameplayJSON, _ := json.Marshal(gameplayState)

	// Update player core fields
	_, err = tx.Exec(ctx, `
		UPDATE players SET
			current_ship_id = $2, galaxy_seed = $3, system_id = $4,
			pos_x = $5, pos_y = $6, pos_z = $7,
			rotation_x = $8, rotation_y = $9, rotation_z = $10,
			credits = $11, kills = $12, deaths = $13,
			fleet = $14, station_services = $15, settings = $16,
			gameplay_state = $18,
			last_save_at = $17, updated_at = $17
		WHERE id = $1
	`, playerID, state.CurrentShipID, state.GalaxySeed, state.SystemID,
		state.PosX, state.PosY, state.PosZ,
		state.RotationX, state.RotationY, state.RotationZ,
		state.Credits, state.Kills, state.Deaths, fleetJSON, stationServicesJSON, settingsJSON, now, gameplayJSON)
	if err != nil {
		return err
	}

	// Resources — delete and re-insert
	_, err = tx.Exec(ctx, `DELETE FROM player_resources WHERE player_id = $1`, playerID)
	if err != nil {
		return err
	}
	for _, res := range state.Resources {
		_, err = tx.Exec(ctx, `
			INSERT INTO player_resources (player_id, resource_id, quantity) VALUES ($1, $2, $3)
		`, playerID, res.ResourceID, res.Quantity)
		if err != nil {
			return err
		}
	}

	// Inventory
	_, err = tx.Exec(ctx, `DELETE FROM player_inventory WHERE player_id = $1`, playerID)
	if err != nil {
		return err
	}
	for _, item := range state.Inventory {
		_, err = tx.Exec(ctx, `
			INSERT INTO player_inventory (player_id, category, item_name, quantity) VALUES ($1, $2, $3, $4)
		`, playerID, item.Category, item.ItemName, item.Quantity)
		if err != nil {
			return err
		}
	}

	// Cargo
	_, err = tx.Exec(ctx, `DELETE FROM player_cargo WHERE player_id = $1`, playerID)
	if err != nil {
		return err
	}
	for _, item := range state.Cargo {
		_, err = tx.Exec(ctx, `
			INSERT INTO player_cargo (player_id, item_name, item_type, quantity, icon_color) VALUES ($1, $2, $3, $4, $5)
		`, playerID, item.ItemName, item.ItemType, item.Quantity, item.IconColor)
		if err != nil {
			return err
		}
	}

	// Equipment
	if state.Equipment != nil {
		_, err = tx.Exec(ctx, `
			INSERT INTO player_equipment (player_id, hardpoints, shield_name, engine_name, modules)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (player_id) DO UPDATE SET
				hardpoints = EXCLUDED.hardpoints,
				shield_name = EXCLUDED.shield_name,
				engine_name = EXCLUDED.engine_name,
				modules = EXCLUDED.modules
		`, playerID, state.Equipment.Hardpoints, state.Equipment.ShieldName, state.Equipment.EngineName, state.Equipment.Modules)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *PlayerRepository) SetCorporationID(ctx context.Context, playerID string, corporationID *string) error {
	_, err := r.pool.Exec(ctx, `UPDATE players SET corporation_id = $2, updated_at = NOW() WHERE id = $1`, playerID, corporationID)
	return err
}

func (r *PlayerRepository) GetCorporationID(ctx context.Context, playerID string) (*string, error) {
	var corporationID *string
	err := r.pool.QueryRow(ctx, `SELECT corporation_id FROM players WHERE id = $1`, playerID).Scan(&corporationID)
	if err == pgx.ErrNoRows {
		return nil, nil // Player not found — treat as no corporation
	}
	return corporationID, err
}

// Ensure rows interface is consumed even on error
var _ pgx.Rows = (pgx.Rows)(nil)
