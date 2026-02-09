package repository

import (
	"context"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ChangelogRepository struct {
	db *pgxpool.Pool
}

func NewChangelogRepository(db *pgxpool.Pool) *ChangelogRepository {
	return &ChangelogRepository{db: db}
}

func (r *ChangelogRepository) Create(ctx context.Context, version, summary string, isMajor bool) (*model.Changelog, error) {
	var c model.Changelog
	err := r.db.QueryRow(ctx,
		`INSERT INTO changelogs (version, summary, is_major) VALUES ($1, $2, $3)
		 RETURNING id, version, summary, is_major, created_at`,
		version, summary, isMajor,
	).Scan(&c.ID, &c.Version, &c.Summary, &c.IsMajor, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *ChangelogRepository) List(ctx context.Context, limit int) ([]model.Changelog, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := r.db.Query(ctx,
		`SELECT id, version, summary, is_major, created_at FROM changelogs ORDER BY created_at DESC LIMIT $1`,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []model.Changelog
	for rows.Next() {
		var c model.Changelog
		if err := rows.Scan(&c.ID, &c.Version, &c.Summary, &c.IsMajor, &c.CreatedAt); err != nil {
			return nil, err
		}
		entries = append(entries, c)
	}
	return entries, nil
}
