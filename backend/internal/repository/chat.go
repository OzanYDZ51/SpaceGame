package repository

import (
	"context"
	"fmt"
	"log"
	"strings"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ChatRepository struct {
	pool *pgxpool.Pool
}

func NewChatRepository(pool *pgxpool.Pool) *ChatRepository {
	return &ChatRepository{pool: pool}
}

// InsertMessage stores a single chat message.
func (r *ChatRepository) InsertMessage(ctx context.Context, msg model.ChatPostRequest) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO chat_messages (channel, system_id, sender_name, text)
		VALUES ($1, $2, $3, $4)
	`, msg.Channel, msg.SystemID, msg.SenderName, msg.Text)
	return err
}

// GetHistory retrieves recent messages for the given channels, ordered chronologically.
// For channel=1 (SYSTEM), only messages matching systemID are returned.
func (r *ChatRepository) GetHistory(ctx context.Context, channels []int, systemID int, limit int) ([]model.ChatMessage, error) {
	if len(channels) == 0 {
		return nil, nil
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	// Build WHERE clause: (channel IN (non-system channels)) OR (channel = 1 AND system_id = $systemID)
	var conditions []string
	var args []interface{}
	argIdx := 1

	var nonSystemChannels []int
	hasSystem := false
	for _, ch := range channels {
		if ch == 1 {
			hasSystem = true
		} else {
			nonSystemChannels = append(nonSystemChannels, ch)
		}
	}

	if len(nonSystemChannels) > 0 {
		placeholders := make([]string, len(nonSystemChannels))
		for i, ch := range nonSystemChannels {
			placeholders[i] = fmt.Sprintf("$%d", argIdx)
			args = append(args, ch)
			argIdx++
		}
		conditions = append(conditions, fmt.Sprintf("channel IN (%s)", strings.Join(placeholders, ",")))
	}

	if hasSystem {
		if systemID < 0 {
			// Sentinel value: load ALL system messages regardless of system_id
			conditions = append(conditions, "channel = 1")
		} else {
			conditions = append(conditions, fmt.Sprintf("(channel = 1 AND system_id = $%d)", argIdx))
			args = append(args, systemID)
			argIdx++
		}
	}

	where := strings.Join(conditions, " OR ")
	limitPlaceholder := fmt.Sprintf("$%d", argIdx)
	args = append(args, limit)

	// Select newest N rows DESC, then reverse for chronological order
	query := fmt.Sprintf(`
		SELECT id, channel, system_id, sender_name, text, created_at
		FROM chat_messages
		WHERE %s
		ORDER BY created_at DESC
		LIMIT %s
	`, where, limitPlaceholder)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		log.Printf("[Chat] GetHistory query error: %v (query=%s args=%v)", err, query, args)
		return nil, err
	}
	defer rows.Close()

	var msgs []model.ChatMessage
	for rows.Next() {
		var m model.ChatMessage
		if err := rows.Scan(&m.ID, &m.Channel, &m.SystemID, &m.SenderName, &m.Text, &m.CreatedAt); err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}

	// Reverse for chronological order (oldest first)
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}

	return msgs, nil
}

// DeleteOlderThan removes messages older than the given number of days.
// Returns the number of deleted rows.
func (r *ChatRepository) DeleteOlderThan(ctx context.Context, days int) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		DELETE FROM chat_messages WHERE created_at < NOW() - make_interval(days => $1)
	`, days)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
