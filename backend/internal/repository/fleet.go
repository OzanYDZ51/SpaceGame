package repository

import (
	"context"
	"encoding/json"
	"time"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type FleetRepository struct {
	pool *pgxpool.Pool
}

func NewFleetRepository(pool *pgxpool.Pool) *FleetRepository {
	return &FleetRepository{pool: pool}
}

// GetPlayerFleet returns all fleet ships for a player.
func (r *FleetRepository) GetPlayerFleet(ctx context.Context, playerID string) ([]model.FleetShipDB, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, player_id, fleet_index, ship_id, custom_name, deployment_state,
		       system_id, station_id, pos_x, pos_y, pos_z,
		       command, command_params, weapons, shield_name, engine_name, modules,
		       cargo, ship_resources, hull_ratio, shield_ratio,
		       squadron_id, squadron_role, deployed_at, destroyed_at, updated_at
		FROM fleet_ships WHERE player_id = $1 ORDER BY fleet_index
	`, playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ships []model.FleetShipDB
	for rows.Next() {
		var s model.FleetShipDB
		if err := rows.Scan(
			&s.ID, &s.PlayerID, &s.FleetIndex, &s.ShipID, &s.CustomName, &s.DeploymentState,
			&s.SystemID, &s.StationID, &s.PosX, &s.PosY, &s.PosZ,
			&s.Command, &s.CommandParams, &s.Weapons, &s.ShieldName, &s.EngineName, &s.Modules,
			&s.Cargo, &s.ShipResources, &s.HullRatio, &s.ShieldRatio,
			&s.SquadronID, &s.SquadronRole, &s.DeployedAt, &s.DestroyedAt, &s.UpdatedAt,
		); err != nil {
			return nil, err
		}
		ships = append(ships, s)
	}
	return ships, nil
}

// GetDeployedShips returns all fleet ships with deployment_state=1 (DEPLOYED) across all players.
func (r *FleetRepository) GetDeployedShips(ctx context.Context) ([]model.FleetShipDB, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, player_id, fleet_index, ship_id, custom_name, deployment_state,
		       system_id, station_id, pos_x, pos_y, pos_z,
		       command, command_params, weapons, shield_name, engine_name, modules,
		       cargo, ship_resources, hull_ratio, shield_ratio,
		       squadron_id, squadron_role, deployed_at, destroyed_at, updated_at
		FROM fleet_ships WHERE deployment_state = 1
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ships []model.FleetShipDB
	for rows.Next() {
		var s model.FleetShipDB
		if err := rows.Scan(
			&s.ID, &s.PlayerID, &s.FleetIndex, &s.ShipID, &s.CustomName, &s.DeploymentState,
			&s.SystemID, &s.StationID, &s.PosX, &s.PosY, &s.PosZ,
			&s.Command, &s.CommandParams, &s.Weapons, &s.ShieldName, &s.EngineName, &s.Modules,
			&s.Cargo, &s.ShipResources, &s.HullRatio, &s.ShieldRatio,
			&s.SquadronID, &s.SquadronRole, &s.DeployedAt, &s.DestroyedAt, &s.UpdatedAt,
		); err != nil {
			return nil, err
		}
		ships = append(ships, s)
	}
	return ships, nil
}

// BulkUpsertFleetShips inserts or updates fleet ships for a player.
func (r *FleetRepository) BulkUpsertFleetShips(ctx context.Context, ships []model.FleetShipDB) error {
	if len(ships) == 0 {
		return nil
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	now := time.Now()
	for _, s := range ships {
		cmdParams := s.CommandParams
		if cmdParams == nil {
			cmdParams = json.RawMessage(`{}`)
		}
		weapons := s.Weapons
		if weapons == nil {
			weapons = json.RawMessage(`[]`)
		}
		modules := s.Modules
		if modules == nil {
			modules = json.RawMessage(`[]`)
		}
		cargo := s.Cargo
		if cargo == nil {
			cargo = json.RawMessage(`[]`)
		}
		resources := s.ShipResources
		if resources == nil {
			resources = json.RawMessage(`{}`)
		}

		_, err := tx.Exec(ctx, `
			INSERT INTO fleet_ships (
				player_id, fleet_index, ship_id, custom_name, deployment_state,
				system_id, station_id, pos_x, pos_y, pos_z,
				command, command_params, weapons, shield_name, engine_name, modules,
				cargo, ship_resources, hull_ratio, shield_ratio,
				squadron_id, squadron_role, deployed_at, destroyed_at, updated_at
			) VALUES (
				$1, $2, $3, $4, $5,
				$6, $7, $8, $9, $10,
				$11, $12, $13, $14, $15, $16,
				$17, $18, $19, $20,
				$21, $22, $23, $24, $25
			)
			ON CONFLICT (player_id, fleet_index) DO UPDATE SET
				ship_id = EXCLUDED.ship_id,
				custom_name = EXCLUDED.custom_name,
				deployment_state = EXCLUDED.deployment_state,
				system_id = EXCLUDED.system_id,
				station_id = EXCLUDED.station_id,
				pos_x = EXCLUDED.pos_x,
				pos_y = EXCLUDED.pos_y,
				pos_z = EXCLUDED.pos_z,
				command = EXCLUDED.command,
				command_params = EXCLUDED.command_params,
				weapons = EXCLUDED.weapons,
				shield_name = EXCLUDED.shield_name,
				engine_name = EXCLUDED.engine_name,
				modules = EXCLUDED.modules,
				cargo = EXCLUDED.cargo,
				ship_resources = EXCLUDED.ship_resources,
				hull_ratio = EXCLUDED.hull_ratio,
				shield_ratio = EXCLUDED.shield_ratio,
				squadron_id = EXCLUDED.squadron_id,
				squadron_role = EXCLUDED.squadron_role,
				deployed_at = EXCLUDED.deployed_at,
				destroyed_at = EXCLUDED.destroyed_at,
				updated_at = EXCLUDED.updated_at
		`, s.PlayerID, s.FleetIndex, s.ShipID, s.CustomName, s.DeploymentState,
			s.SystemID, s.StationID, s.PosX, s.PosY, s.PosZ,
			s.Command, cmdParams, weapons, s.ShieldName, s.EngineName, modules,
			cargo, resources, s.HullRatio, s.ShieldRatio,
			s.SquadronID, s.SquadronRole, s.DeployedAt, s.DestroyedAt, now)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// BatchUpdatePositions updates positions and health for multiple deployed ships.
func (r *FleetRepository) BatchUpdatePositions(ctx context.Context, updates []model.FleetSyncUpdate) error {
	if len(updates) == 0 {
		return nil
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	now := time.Now()
	for _, u := range updates {
		cmdParams := u.CommandParams
		if len(cmdParams) == 0 {
			cmdParams = json.RawMessage(`{}`)
		}
		_, err := tx.Exec(ctx, `
			UPDATE fleet_ships SET
				pos_x = $3, pos_y = $4, pos_z = $5,
				hull_ratio = $6, shield_ratio = $7,
				command = CASE WHEN $8 != '' THEN $8 ELSE command END,
				command_params = CASE WHEN $10::jsonb != '{}'::jsonb THEN $10 ELSE command_params END,
				updated_at = $9
			WHERE player_id = $1 AND fleet_index = $2 AND deployment_state = 1
		`, u.PlayerID, u.FleetIndex, u.PosX, u.PosY, u.PosZ, u.HullRatio, u.ShieldRatio, u.Command, now, cmdParams)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// MarkDestroyed marks a fleet ship as destroyed.
func (r *FleetRepository) MarkDestroyed(ctx context.Context, playerID string, fleetIndex int) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx, `
		UPDATE fleet_ships SET
			deployment_state = 2,
			destroyed_at = $3,
			updated_at = $3
		WHERE player_id = $1 AND fleet_index = $2
	`, playerID, fleetIndex, now)
	return err
}
