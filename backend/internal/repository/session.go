package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SessionRepository struct {
	pool *pgxpool.Pool
}

func NewSessionRepository(pool *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{pool: pool}
}

func (r *SessionRepository) StoreRefreshToken(ctx context.Context, playerID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO refresh_tokens (player_id, token_hash, expires_at)
		VALUES ($1, $2, $3)
	`, playerID, tokenHash, expiresAt)
	return err
}

func (r *SessionRepository) ValidateRefreshToken(ctx context.Context, tokenHash string) (string, error) {
	var playerID string
	err := r.pool.QueryRow(ctx, `
		SELECT player_id FROM refresh_tokens
		WHERE token_hash = $1 AND revoked = FALSE AND expires_at > NOW()
	`, tokenHash).Scan(&playerID)
	return playerID, err
}

func (r *SessionRepository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1
	`, tokenHash)
	return err
}

func (r *SessionRepository) RevokeAllForPlayer(ctx context.Context, playerID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE refresh_tokens SET revoked = TRUE WHERE player_id = $1
	`, playerID)
	return err
}

func (r *SessionRepository) CleanupExpired(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE expires_at < NOW() OR revoked = TRUE`)
	return err
}
