-- Discord integration: link accounts, clan mapping, game events, changelogs

ALTER TABLE players ADD COLUMN IF NOT EXISTS discord_id TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS discord_link_code TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS discord_link_expires TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_players_discord ON players(discord_id);

CREATE TABLE IF NOT EXISTS discord_clan_mapping (
    clan_id UUID PRIMARY KEY REFERENCES clans(id) ON DELETE CASCADE,
    discord_role_id TEXT NOT NULL,
    discord_channel_id TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS game_events (
    id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    actor_name TEXT,
    target_name TEXT,
    details JSONB,
    system_id INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_game_events_type ON game_events(event_type, created_at DESC);

CREATE TABLE IF NOT EXISTS changelogs (
    id BIGSERIAL PRIMARY KEY,
    version TEXT NOT NULL,
    summary TEXT NOT NULL,
    is_major BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
