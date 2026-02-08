CREATE TABLE clans (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clan_name     VARCHAR(32) NOT NULL UNIQUE,
    clan_tag      VARCHAR(5) NOT NULL UNIQUE,
    description   TEXT NOT NULL DEFAULT '',
    motto         VARCHAR(128) NOT NULL DEFAULT '',
    motd          TEXT NOT NULL DEFAULT '',
    clan_color    VARCHAR(32) NOT NULL DEFAULT '0.15,0.85,1.0,1.0',
    emblem_id     INTEGER NOT NULL DEFAULT 0,
    treasury      BIGINT NOT NULL DEFAULT 0,
    reputation    INTEGER NOT NULL DEFAULT 0,
    max_members   INTEGER NOT NULL DEFAULT 50,
    is_recruiting BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add FK from players to clans now that clans table exists
ALTER TABLE players ADD CONSTRAINT fk_players_clan FOREIGN KEY (clan_id) REFERENCES clans(id) ON DELETE SET NULL;

CREATE TABLE clan_ranks (
    id          BIGSERIAL PRIMARY KEY,
    clan_id     UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    rank_name   VARCHAR(32) NOT NULL,
    priority    INTEGER NOT NULL DEFAULT 0,
    permissions INTEGER NOT NULL DEFAULT 0,
    UNIQUE (clan_id, priority)
);

CREATE TABLE clan_members (
    player_id     UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    clan_id       UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    rank_priority INTEGER NOT NULL DEFAULT 0,
    contribution  BIGINT NOT NULL DEFAULT 0,
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE clan_activity (
    id          BIGSERIAL PRIMARY KEY,
    clan_id     UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    event_type  SMALLINT NOT NULL,
    actor_name  VARCHAR(32) NOT NULL DEFAULT '',
    target_name VARCHAR(32) NOT NULL DEFAULT '',
    details     TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE clan_diplomacy (
    clan_id        UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    target_clan_id UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    relation       VARCHAR(16) NOT NULL DEFAULT 'NEUTRAL',
    since          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (clan_id, target_clan_id)
);

CREATE TABLE clan_transactions (
    id          BIGSERIAL PRIMARY KEY,
    clan_id     UUID NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
    player_id   UUID REFERENCES players(id) ON DELETE SET NULL,
    actor_name  VARCHAR(32) NOT NULL,
    tx_type     VARCHAR(16) NOT NULL,
    amount      BIGINT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
