package repository

import (
	"context"
	"encoding/json"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type EventRepository struct {
	db *pgxpool.Pool
}

func NewEventRepository(db *pgxpool.Pool) *EventRepository {
	return &EventRepository{db: db}
}

func (r *EventRepository) Create(ctx context.Context, eventType, actorName, targetName string, details json.RawMessage, systemID int) (*model.GameEvent, error) {
	var e model.GameEvent
	err := r.db.QueryRow(ctx,
		`INSERT INTO game_events (event_type, actor_name, target_name, details, system_id)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, event_type, actor_name, target_name, details, system_id, created_at`,
		eventType, actorName, targetName, details, systemID,
	).Scan(&e.ID, &e.EventType, &e.ActorName, &e.TargetName, &e.Details, &e.SystemID, &e.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

func (r *EventRepository) ListByType(ctx context.Context, eventType string, limit int) ([]model.GameEvent, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows, err := r.db.Query(ctx,
		`SELECT id, event_type, actor_name, target_name, details, system_id, created_at
		 FROM game_events WHERE event_type = $1 ORDER BY created_at DESC LIMIT $2`,
		eventType, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []model.GameEvent
	for rows.Next() {
		var e model.GameEvent
		if err := rows.Scan(&e.ID, &e.EventType, &e.ActorName, &e.TargetName, &e.Details, &e.SystemID, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, nil
}
