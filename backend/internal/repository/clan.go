package repository

import (
	"context"
	"fmt"
	"time"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ClanRepository struct {
	pool *pgxpool.Pool
}

func NewClanRepository(pool *pgxpool.Pool) *ClanRepository {
	return &ClanRepository{pool: pool}
}

func (r *ClanRepository) Create(ctx context.Context, req *model.CreateClanRequest) (*model.Clan, error) {
	c := &model.Clan{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO clans (clan_name, clan_tag, description, motto, clan_color, emblem_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, clan_name, clan_tag, description, motto, motd, clan_color, emblem_id,
		          treasury, reputation, max_members, is_recruiting, created_at, updated_at
	`, req.ClanName, req.ClanTag, req.Description, req.Motto, req.ClanColor, req.EmblemID).Scan(
		&c.ID, &c.ClanName, &c.ClanTag, &c.Description, &c.Motto, &c.MOTD, &c.ClanColor, &c.EmblemID,
		&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (r *ClanRepository) GetByID(ctx context.Context, id string) (*model.Clan, error) {
	c := &model.Clan{}
	err := r.pool.QueryRow(ctx, `
		SELECT c.id, c.clan_name, c.clan_tag, c.description, c.motto, c.motd, c.clan_color, c.emblem_id,
		       c.treasury, c.reputation, c.max_members, c.is_recruiting, c.created_at, c.updated_at,
		       (SELECT COUNT(*) FROM clan_members WHERE clan_id = c.id)
		FROM clans c WHERE c.id = $1
	`, id).Scan(
		&c.ID, &c.ClanName, &c.ClanTag, &c.Description, &c.Motto, &c.MOTD, &c.ClanColor, &c.EmblemID,
		&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
		&c.MemberCount,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (r *ClanRepository) Search(ctx context.Context, query string, limit int) ([]*model.Clan, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id, c.clan_name, c.clan_tag, c.description, c.motto, c.motd, c.clan_color, c.emblem_id,
		       c.treasury, c.reputation, c.max_members, c.is_recruiting, c.created_at, c.updated_at,
		       (SELECT COUNT(*) FROM clan_members WHERE clan_id = c.id)
		FROM clans c
		WHERE c.clan_name ILIKE '%' || $1 || '%' OR c.clan_tag ILIKE '%' || $1 || '%'
		ORDER BY c.reputation DESC
		LIMIT $2
	`, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var clans []*model.Clan
	for rows.Next() {
		c := &model.Clan{}
		if err := rows.Scan(
			&c.ID, &c.ClanName, &c.ClanTag, &c.Description, &c.Motto, &c.MOTD, &c.ClanColor, &c.EmblemID,
			&c.Treasury, &c.Reputation, &c.MaxMembers, &c.IsRecruiting, &c.CreatedAt, &c.UpdatedAt,
			&c.MemberCount,
		); err != nil {
			return nil, err
		}
		clans = append(clans, c)
	}
	return clans, nil
}

func (r *ClanRepository) Update(ctx context.Context, id string, req *model.UpdateClanRequest) error {
	// Build dynamic update — only set provided fields
	query := "UPDATE clans SET updated_at = NOW()"
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
	if req.ClanColor != nil {
		query += fmt.Sprintf(", clan_color = $%d", i)
		args = append(args, *req.ClanColor)
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

func (r *ClanRepository) Delete(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM clans WHERE id = $1`, id)
	return err
}

func (r *ClanRepository) CountTotal(ctx context.Context) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM clans`).Scan(&count)
	return count, err
}

// --- Members ---

func (r *ClanRepository) AddMember(ctx context.Context, clanID, playerID string, rankPriority int) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO clan_members (player_id, clan_id, rank_priority) VALUES ($1, $2, $3)
	`, playerID, clanID, rankPriority)
	return err
}

func (r *ClanRepository) RemoveMember(ctx context.Context, playerID string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM clan_members WHERE player_id = $1`, playerID)
	return err
}

func (r *ClanRepository) GetMembers(ctx context.Context, clanID string) ([]*model.ClanMember, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT cm.player_id, p.username, cm.clan_id, cm.rank_priority,
		       COALESCE(cr.rank_name, 'Member'), cm.contribution, cm.joined_at
		FROM clan_members cm
		JOIN players p ON cm.player_id = p.id
		LEFT JOIN clan_ranks cr ON cr.clan_id = cm.clan_id AND cr.priority = cm.rank_priority
		WHERE cm.clan_id = $1
		ORDER BY cm.rank_priority DESC, cm.joined_at ASC
	`, clanID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []*model.ClanMember
	for rows.Next() {
		m := &model.ClanMember{}
		if err := rows.Scan(&m.PlayerID, &m.Username, &m.ClanID, &m.RankPriority, &m.RankName, &m.Contribution, &m.JoinedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	return members, nil
}

func (r *ClanRepository) GetMember(ctx context.Context, playerID string) (*model.ClanMember, error) {
	m := &model.ClanMember{}
	err := r.pool.QueryRow(ctx, `
		SELECT cm.player_id, p.username, cm.clan_id, cm.rank_priority,
		       COALESCE(cr.rank_name, 'Member'), cm.contribution, cm.joined_at
		FROM clan_members cm
		JOIN players p ON cm.player_id = p.id
		LEFT JOIN clan_ranks cr ON cr.clan_id = cm.clan_id AND cr.priority = cm.rank_priority
		WHERE cm.player_id = $1
	`, playerID).Scan(&m.PlayerID, &m.Username, &m.ClanID, &m.RankPriority, &m.RankName, &m.Contribution, &m.JoinedAt)
	if err != nil {
		return nil, err
	}
	return m, nil
}

func (r *ClanRepository) SetMemberRank(ctx context.Context, playerID string, rankPriority int) error {
	_, err := r.pool.Exec(ctx, `UPDATE clan_members SET rank_priority = $2 WHERE player_id = $1`, playerID, rankPriority)
	return err
}

func (r *ClanRepository) GetMemberCount(ctx context.Context, clanID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM clan_members WHERE clan_id = $1`, clanID).Scan(&count)
	return count, err
}

// --- Ranks ---

func (r *ClanRepository) CreateDefaultRanks(ctx context.Context, clanID string) error {
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
			INSERT INTO clan_ranks (clan_id, rank_name, priority, permissions)
			VALUES ($1, $2, $3, $4)
		`, clanID, rank.name, rank.priority, rank.perms)
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *ClanRepository) GetRanks(ctx context.Context, clanID string) ([]*model.ClanRank, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, clan_id, rank_name, priority, permissions FROM clan_ranks
		WHERE clan_id = $1 ORDER BY priority ASC
	`, clanID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ranks []*model.ClanRank
	for rows.Next() {
		rank := &model.ClanRank{}
		if err := rows.Scan(&rank.ID, &rank.ClanID, &rank.RankName, &rank.Priority, &rank.Permissions); err != nil {
			return nil, err
		}
		ranks = append(ranks, rank)
	}
	return ranks, nil
}

// --- Treasury ---

func (r *ClanRepository) UpdateTreasury(ctx context.Context, clanID string, amount int64) (int64, error) {
	var newBalance int64
	err := r.pool.QueryRow(ctx, `
		UPDATE clans SET treasury = treasury + $2, updated_at = NOW()
		WHERE id = $1 AND treasury + $2 >= 0
		RETURNING treasury
	`, clanID, amount).Scan(&newBalance)
	return newBalance, err
}

func (r *ClanRepository) AddTransaction(ctx context.Context, clanID, playerID, actorName, txType string, amount int64) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO clan_transactions (clan_id, player_id, actor_name, tx_type, amount)
		VALUES ($1, $2, $3, $4, $5)
	`, clanID, playerID, actorName, txType, amount)
	return err
}

func (r *ClanRepository) GetTransactions(ctx context.Context, clanID string, limit int) ([]*model.ClanTransaction, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, clan_id, player_id, actor_name, tx_type, amount, created_at
		FROM clan_transactions WHERE clan_id = $1 ORDER BY created_at DESC LIMIT $2
	`, clanID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var txs []*model.ClanTransaction
	for rows.Next() {
		tx := &model.ClanTransaction{}
		if err := rows.Scan(&tx.ID, &tx.ClanID, &tx.PlayerID, &tx.ActorName, &tx.TxType, &tx.Amount, &tx.CreatedAt); err != nil {
			return nil, err
		}
		txs = append(txs, tx)
	}
	return txs, nil
}

// --- Activity ---

func (r *ClanRepository) AddActivity(ctx context.Context, clanID string, eventType int, actorName, targetName, details string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO clan_activity (clan_id, event_type, actor_name, target_name, details)
		VALUES ($1, $2, $3, $4, $5)
	`, clanID, eventType, actorName, targetName, details)
	return err
}

func (r *ClanRepository) GetActivity(ctx context.Context, clanID string, limit int) ([]*model.ClanActivity, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, clan_id, event_type, actor_name, target_name, details, created_at
		FROM clan_activity WHERE clan_id = $1 ORDER BY created_at DESC LIMIT $2
	`, clanID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var activities []*model.ClanActivity
	for rows.Next() {
		a := &model.ClanActivity{}
		if err := rows.Scan(&a.ID, &a.ClanID, &a.EventType, &a.ActorName, &a.TargetName, &a.Details, &a.CreatedAt); err != nil {
			return nil, err
		}
		activities = append(activities, a)
	}
	return activities, nil
}

// --- Diplomacy ---

func (r *ClanRepository) GetDiplomacy(ctx context.Context, clanID string) ([]*model.ClanDiplomacy, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT d.clan_id, d.target_clan_id, c.clan_name, c.clan_tag, d.relation, d.since
		FROM clan_diplomacy d
		JOIN clans c ON d.target_clan_id = c.id
		WHERE d.clan_id = $1
	`, clanID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var relations []*model.ClanDiplomacy
	for rows.Next() {
		d := &model.ClanDiplomacy{}
		if err := rows.Scan(&d.ClanID, &d.TargetClanID, &d.TargetName, &d.TargetTag, &d.Relation, &d.Since); err != nil {
			return nil, err
		}
		relations = append(relations, d)
	}
	return relations, nil
}

func (r *ClanRepository) SetDiplomacy(ctx context.Context, clanID, targetClanID, relation string) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx, `
		INSERT INTO clan_diplomacy (clan_id, target_clan_id, relation, since)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (clan_id, target_clan_id) DO UPDATE SET relation = EXCLUDED.relation, since = EXCLUDED.since
	`, clanID, targetClanID, relation, now)
	return err
}
