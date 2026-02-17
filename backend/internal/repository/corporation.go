package repository

import (
	"context"
	"fmt"
	"time"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type CorporationRepository struct {
	pool *pgxpool.Pool
}

func NewCorporationRepository(pool *pgxpool.Pool) *CorporationRepository {
	return &CorporationRepository{pool: pool}
}

func (r *CorporationRepository) Create(ctx context.Context, req *model.CreateCorporationRequest) (*model.Corporation, error) {
	c := &model.Corporation{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO corporations (corporation_name, corporation_tag, description, motto, corporation_color, emblem_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, corporation_name, corporation_tag, description, motto, motd, corporation_color, emblem_id,
		          treasury, reputation, max_members, is_recruiting, created_at, updated_at
	`, req.CorporationName, req.CorporationTag, req.Description, req.Motto, req.CorporationColor, req.EmblemID).Scan(
		&c.ID, &c.CorporationName, &c.CorporationTag, &c.Description, &c.Motto, &c.MOTD, &c.CorporationColor, &c.EmblemID,
		&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (r *CorporationRepository) GetByID(ctx context.Context, id string) (*model.Corporation, error) {
	c := &model.Corporation{}
	err := r.pool.QueryRow(ctx, `
		SELECT c.id, c.corporation_name, c.corporation_tag, c.description, c.motto, c.motd, c.corporation_color, c.emblem_id,
		       c.treasury, c.reputation, c.max_members, c.is_recruiting, c.created_at, c.updated_at,
		       (SELECT COUNT(*) FROM corporation_members WHERE corporation_id = c.id)
		FROM corporations c WHERE c.id = $1
	`, id).Scan(
		&c.ID, &c.CorporationName, &c.CorporationTag, &c.Description, &c.Motto, &c.MOTD, &c.CorporationColor, &c.EmblemID,
		&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
		&c.MemberCount,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (r *CorporationRepository) Search(ctx context.Context, query string, limit int) ([]*model.Corporation, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id, c.corporation_name, c.corporation_tag, c.description, c.motto, c.motd, c.corporation_color, c.emblem_id,
		       c.treasury, c.reputation, c.max_members, c.is_recruiting, c.created_at, c.updated_at,
		       (SELECT COUNT(*) FROM corporation_members WHERE corporation_id = c.id)
		FROM corporations c
		WHERE c.corporation_name ILIKE '%' || $1 || '%' OR c.corporation_tag ILIKE '%' || $1 || '%'
		ORDER BY c.reputation DESC
		LIMIT $2
	`, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var corporations []*model.Corporation
	for rows.Next() {
		c := &model.Corporation{}
		if err := rows.Scan(
			&c.ID, &c.CorporationName, &c.CorporationTag, &c.Description, &c.Motto, &c.MOTD, &c.CorporationColor, &c.EmblemID,
			&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
			&c.MemberCount,
		); err != nil {
			return nil, err
		}
		corporations = append(corporations, c)
	}
	return corporations, nil
}

func (r *CorporationRepository) Update(ctx context.Context, id string, req *model.UpdateCorporationRequest) error {
	// Build dynamic update — only set provided fields
	query := "UPDATE corporations SET updated_at = NOW()"
	args := []interface{}{id}
	i := 2

	if req.Description != nil {
		query += fmt.Sprintf(", description = $%d", i)
		args = append(args, *req.Description)
		i++
	}
	if req.Motto != nil {
		query += fmt.Sprintf(", motto = $%d", i)
		args = append(args, *req.Motto)
		i++
	}
	if req.MOTD != nil {
		query += fmt.Sprintf(", motd = $%d", i)
		args = append(args, *req.MOTD)
		i++
	}
	if req.CorporationColor != nil {
		query += fmt.Sprintf(", corporation_color = $%d", i)
		args = append(args, *req.CorporationColor)
		i++
	}
	if req.EmblemID != nil {
		query += fmt.Sprintf(", emblem_id = $%d", i)
		args = append(args, *req.EmblemID)
		i++
	}
	if req.IsRecruiting != nil {
		query += fmt.Sprintf(", is_recruiting = $%d", i)
		args = append(args, *req.IsRecruiting)
		i++
	}

	query += " WHERE id = $1"
	_, err := r.pool.Exec(ctx, query, args...)
	return err
}

func (r *CorporationRepository) Delete(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM corporations WHERE id = $1`, id)
	return err
}

func (r *CorporationRepository) CountTotal(ctx context.Context) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM corporations`).Scan(&count)
	return count, err
}

// --- Members ---

func (r *CorporationRepository) AddMember(ctx context.Context, corporationID, playerID string, rankPriority int) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO corporation_members (player_id, corporation_id, rank_priority) VALUES ($1, $2, $3)
	`, playerID, corporationID, rankPriority)
	return err
}

func (r *CorporationRepository) RemoveMember(ctx context.Context, playerID string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM corporation_members WHERE player_id = $1`, playerID)
	return err
}

func (r *CorporationRepository) GetMembers(ctx context.Context, corporationID string) ([]*model.CorporationMember, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT cm.player_id, p.username, cm.corporation_id, cm.rank_priority,
		       COALESCE(cr.rank_name, 'Member'), cm.contribution, cm.joined_at
		FROM corporation_members cm
		JOIN players p ON cm.player_id = p.id
		LEFT JOIN corporation_ranks cr ON cr.corporation_id = cm.corporation_id AND cr.priority = cm.rank_priority
		WHERE cm.corporation_id = $1
		ORDER BY cm.rank_priority DESC, cm.joined_at ASC
	`, corporationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []*model.CorporationMember
	for rows.Next() {
		m := &model.CorporationMember{}
		if err := rows.Scan(&m.PlayerID, &m.Username, &m.CorporationID, &m.RankPriority, &m.RankName, &m.Contribution, &m.JoinedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	return members, nil
}

func (r *CorporationRepository) GetMember(ctx context.Context, playerID string) (*model.CorporationMember, error) {
	m := &model.CorporationMember{}
	err := r.pool.QueryRow(ctx, `
		SELECT cm.player_id, p.username, cm.corporation_id, cm.rank_priority,
		       COALESCE(cr.rank_name, 'Member'), cm.contribution, cm.joined_at
		FROM corporation_members cm
		JOIN players p ON cm.player_id = p.id
		LEFT JOIN corporation_ranks cr ON cr.corporation_id = cm.corporation_id AND cr.priority = cm.rank_priority
		WHERE cm.player_id = $1
	`, playerID).Scan(&m.PlayerID, &m.Username, &m.CorporationID, &m.RankPriority, &m.RankName, &m.Contribution, &m.JoinedAt)
	if err != nil {
		return nil, err
	}
	return m, nil
}

func (r *CorporationRepository) SetMemberRank(ctx context.Context, playerID string, rankPriority int) error {
	_, err := r.pool.Exec(ctx, `UPDATE corporation_members SET rank_priority = $2 WHERE player_id = $1`, playerID, rankPriority)
	return err
}

func (r *CorporationRepository) GetMemberCount(ctx context.Context, corporationID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM corporation_members WHERE corporation_id = $1`, corporationID).Scan(&count)
	return count, err
}

// --- Ranks ---

func (r *CorporationRepository) CreateDefaultRanks(ctx context.Context, corporationID string) error {
	ranks := []struct {
		name     string
		priority int
		perms    int
	}{
		{"Recrue", 0, 0},
		{"Membre", 1, 1},
		{"Officier", 2, 7},
		{"Commandant", 3, 15},
		{"Leader", 4, 255},
	}
	for _, rank := range ranks {
		_, err := r.pool.Exec(ctx, `
			INSERT INTO corporation_ranks (corporation_id, rank_name, priority, permissions)
			VALUES ($1, $2, $3, $4)
		`, corporationID, rank.name, rank.priority, rank.perms)
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *CorporationRepository) GetRanks(ctx context.Context, corporationID string) ([]*model.CorporationRank, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, corporation_id, rank_name, priority, permissions FROM corporation_ranks
		WHERE corporation_id = $1 ORDER BY priority ASC
	`, corporationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ranks []*model.CorporationRank
	for rows.Next() {
		rank := &model.CorporationRank{}
		if err := rows.Scan(&rank.ID, &rank.CorporationID, &rank.RankName, &rank.Priority, &rank.Permissions); err != nil {
			return nil, err
		}
		ranks = append(ranks, rank)
	}
	return ranks, nil
}

func (r *CorporationRepository) InsertRank(ctx context.Context, corporationID, rankName string, priority, permissions int) (*model.CorporationRank, error) {
	rank := &model.CorporationRank{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO corporation_ranks (corporation_id, rank_name, priority, permissions)
		VALUES ($1, $2, $3, $4)
		RETURNING id, corporation_id, rank_name, priority, permissions
	`, corporationID, rankName, priority, permissions).Scan(
		&rank.ID, &rank.CorporationID, &rank.RankName, &rank.Priority, &rank.Permissions,
	)
	if err != nil {
		return nil, err
	}
	return rank, nil
}

func (r *CorporationRepository) UpdateRank(ctx context.Context, rankID int64, rankName string, permissions int) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE corporation_ranks SET rank_name = $2, permissions = $3 WHERE id = $1
	`, rankID, rankName, permissions)
	return err
}

func (r *CorporationRepository) DeleteRank(ctx context.Context, rankID int64) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM corporation_ranks WHERE id = $1`, rankID)
	return err
}

// --- Treasury ---

func (r *CorporationRepository) UpdateTreasury(ctx context.Context, corporationID string, amount int64) (int64, error) {
	var newBalance int64
	err := r.pool.QueryRow(ctx, `
		UPDATE corporations SET treasury = treasury + $2, updated_at = NOW()
		WHERE id = $1 AND treasury + $2 >= 0
		RETURNING treasury
	`, corporationID, amount).Scan(&newBalance)
	return newBalance, err
}

func (r *CorporationRepository) AddTransaction(ctx context.Context, corporationID, playerID, actorName, txType string, amount int64) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO corporation_transactions (corporation_id, player_id, actor_name, tx_type, amount)
		VALUES ($1, $2, $3, $4, $5)
	`, corporationID, playerID, actorName, txType, amount)
	return err
}

func (r *CorporationRepository) GetTransactions(ctx context.Context, corporationID string, limit int) ([]*model.CorporationTransaction, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, corporation_id, player_id, actor_name, tx_type, amount, created_at
		FROM corporation_transactions WHERE corporation_id = $1 ORDER BY created_at DESC LIMIT $2
	`, corporationID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var txs []*model.CorporationTransaction
	for rows.Next() {
		tx := &model.CorporationTransaction{}
		if err := rows.Scan(&tx.ID, &tx.CorporationID, &tx.PlayerID, &tx.ActorName, &tx.TxType, &tx.Amount, &tx.CreatedAt); err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
	return txs, nil
}

// --- Activity ---

func (r *CorporationRepository) AddActivity(ctx context.Context, corporationID string, eventType int, actorName, targetName, details string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO corporation_activity (corporation_id, event_type, actor_name, target_name, details)
		VALUES ($1, $2, $3, $4, $5)
	`, corporationID, eventType, actorName, targetName, details)
	return err
}

func (r *CorporationRepository) GetActivity(ctx context.Context, corporationID string, limit int) ([]*model.CorporationActivity, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, corporation_id, event_type, actor_name, target_name, details, created_at
		FROM corporation_activity WHERE corporation_id = $1 ORDER BY created_at DESC LIMIT $2
	`, corporationID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var activities []*model.CorporationActivity
	for rows.Next() {
		a := &model.CorporationActivity{}
		if err := rows.Scan(&a.ID, &a.CorporationID, &a.EventType, &a.ActorName, &a.TargetName, &a.Details, &a.CreatedAt); err != nil {
			return nil, err
		}
		activities = append(activities, a)
	}
	return activities, nil
}

// --- Diplomacy ---

func (r *CorporationRepository) GetDiplomacy(ctx context.Context, corporationID string) ([]*model.CorporationDiplomacy, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT d.corporation_id, d.target_corporation_id, c.corporation_name, c.corporation_tag, d.relation, d.since
		FROM corporation_diplomacy d
		JOIN corporations c ON d.target_corporation_id = c.id
		WHERE d.corporation_id = $1
	`, corporationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var relations []*model.CorporationDiplomacy
	for rows.Next() {
		d := &model.CorporationDiplomacy{}
		if err := rows.Scan(&d.CorporationID, &d.TargetCorporationID, &d.TargetName, &d.TargetTag, &d.Relation, &d.Since); err != nil {
			return nil, err
		}
		relations = append(relations, d)
	}
	return relations, nil
}

func (r *CorporationRepository) SetDiplomacy(ctx context.Context, corporationID, targetCorporationID, relation string) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx, `
		INSERT INTO corporation_diplomacy (corporation_id, target_corporation_id, relation, since)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (corporation_id, target_corporation_id) DO UPDATE SET relation = EXCLUDED.relation, since = EXCLUDED.since
	`, corporationID, targetCorporationID, relation, now)
	return err
}
