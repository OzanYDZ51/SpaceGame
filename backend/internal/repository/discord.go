package repository

import (
	"context"
	"crypto/rand"
	"fmt"
	"time"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type DiscordRepository struct {
	db *pgxpool.Pool
}

func NewDiscordRepository(db *pgxpool.Pool) *DiscordRepository {
	return &DiscordRepository{db: db}
}

// GenerateLinkCode creates a 6-digit link code for a Discord user and stores it.
func (r *DiscordRepository) GenerateLinkCode(ctx context.Context, discordID string) (string, error) {
	// Generate 6-digit code
	b := make([]byte, 3)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	code := fmt.Sprintf("%06d", int(b[0])<<16|int(b[1])<<8|int(b[2])%1000000)
	if len(code) > 6 {
		code = code[:6]
	}

	expires := time.Now().Add(10 * time.Minute)

	// Store the code temporarily — we store it by discord_id in a temp approach:
	// We look for any player with this discord_link_code and clear it first,
	// then set it on the "unclaimed" row. Since there's no player yet, we store
	// in a simple approach: use discord_id to find existing linked player, or
	// store in a dedicated temp table. For simplicity, we use the players table
	// approach where we set code on any row that already has this discord_id,
	// or we just return the code for the bot to relay.
	// The actual flow: bot generates code + tells user → user types code in-game
	// → game POSTs /player/discord-link with code → we match.

	// Store the pending link: set discord_link_code and discord_link_expires
	// for any player whose discord_id matches OR create a temporary record.
	// Since the player isn't linked yet, we need a different approach:
	// Store (discord_id, code, expires) — we'll use a simple upsert on discord_id.
	// But discord_id is on players table... We need a temp store.
	// Simplest: just return the code, the bot remembers it in-memory.
	// The confirm endpoint will match code against in-memory store.

	// Actually, let's store it properly: when a user runs !link in Discord,
	// the bot calls this which stores the (discordID, code, expires) mapping.
	// We'll add a simple key-value approach using the players table spare columns.
	// But the player may not exist yet. Let's use game_events as a temp store.
	_, err := r.db.Exec(ctx,
		`INSERT INTO game_events (event_type, actor_name, target_name, details, system_id, created_at)
		 VALUES ('discord_link_pending', $1, $2, '{}', 0, $3)`,
		discordID, code, expires,
	)
	if err != nil {
		return "", err
	}
	return code, nil
}

// ConfirmLinkCode validates a code submitted by a player and links their Discord account.
func (r *DiscordRepository) ConfirmLinkCode(ctx context.Context, playerID, code string) error {
	// Find the pending link event
	var discordID string
	var expires time.Time
	err := r.db.QueryRow(ctx,
		`SELECT actor_name, created_at FROM game_events
		 WHERE event_type = 'discord_link_pending' AND target_name = $1
		 ORDER BY created_at DESC LIMIT 1`,
		code,
	).Scan(&discordID, &expires)
	if err != nil {
		return fmt.Errorf("code invalide ou expiré")
	}

	if time.Now().After(expires) {
		return fmt.Errorf("code expiré")
	}

	// Link the discord_id to the player
	_, err = r.db.Exec(ctx,
		`UPDATE players SET discord_id = $1, discord_link_code = NULL, discord_link_expires = NULL WHERE id = $2`,
		discordID, playerID,
	)
	if err != nil {
		return err
	}

	// Clean up the pending event
	_, _ = r.db.Exec(ctx,
		`DELETE FROM game_events WHERE event_type = 'discord_link_pending' AND actor_name = $1`,
		discordID,
	)
	return nil
}

// GetDiscordID returns the Discord ID linked to a player, if any.
func (r *DiscordRepository) GetDiscordID(ctx context.Context, playerID string) (string, error) {
	var discordID *string
	err := r.db.QueryRow(ctx,
		`SELECT discord_id FROM players WHERE id = $1`, playerID,
	).Scan(&discordID)
	if err != nil {
		return "", err
	}
	if discordID == nil {
		return "", nil
	}
	return *discordID, nil
}

// GetPlayerByDiscordID finds a player by their linked Discord ID.
func (r *DiscordRepository) GetPlayerByDiscordID(ctx context.Context, discordID string) (*model.Player, error) {
	var p model.Player
	err := r.db.QueryRow(ctx,
		`SELECT id, username, current_ship_id, kills, deaths, clan_id FROM players WHERE discord_id = $1`,
		discordID,
	).Scan(&p.ID, &p.Username, &p.CurrentShipID, &p.Kills, &p.Deaths, &p.ClanID)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// SetClanMapping stores the Discord role and channel IDs for a clan.
func (r *DiscordRepository) SetClanMapping(ctx context.Context, clanID, roleID, channelID string) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO discord_clan_mapping (clan_id, discord_role_id, discord_channel_id)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (clan_id) DO UPDATE SET discord_role_id = $2, discord_channel_id = $3`,
		clanID, roleID, channelID,
	)
	return err
}

// GetClanMapping returns the Discord mapping for a clan.
func (r *DiscordRepository) GetClanMapping(ctx context.Context, clanID string) (*model.DiscordClanMapping, error) {
	var m model.DiscordClanMapping
	err := r.db.QueryRow(ctx,
		`SELECT clan_id, discord_role_id, discord_channel_id FROM discord_clan_mapping WHERE clan_id = $1`,
		clanID,
	).Scan(&m.ClanID, &m.DiscordRoleID, &m.DiscordChannelID)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// DeleteClanMapping removes the Discord mapping for a clan.
func (r *DiscordRepository) DeleteClanMapping(ctx context.Context, clanID string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM discord_clan_mapping WHERE clan_id = $1`, clanID)
	return err
}
