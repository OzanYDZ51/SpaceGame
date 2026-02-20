CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE players (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        VARCHAR(32) NOT NULL UNIQUE,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    current_ship_id VARCHAR(32) NOT NULL DEFAULT 'chasseur_viper',
    galaxy_seed     BIGINT NOT NULL DEFAULT 12345,
    system_id       INTEGER NOT NULL DEFAULT 0,
    pos_x           DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y           DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z           DOUBLE PRECISION NOT NULL DEFAULT 0,
    rotation_x      DOUBLE PRECISION NOT NULL DEFAULT 0,
    rotation_y      DOUBLE PRECISION NOT NULL DEFAULT 0,
    rotation_z      DOUBLE PRECISION NOT NULL DEFAULT 0,
    credits         BIGINT NOT NULL DEFAULT 1500,
    kills           INTEGER NOT NULL DEFAULT 0,
    deaths          INTEGER NOT NULL DEFAULT 0,
    clan_id         UUID,
    is_banned       BOOLEAN NOT NULL DEFAULT FALSE,
    last_login_at   TIMESTAMPTZ,
    last_save_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE player_resources (
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    resource_id VARCHAR(32) NOT NULL,
    quantity    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id, resource_id)
);

CREATE TABLE player_inventory (
    id          BIGSERIAL PRIMARY KEY,
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    category    VARCHAR(16) NOT NULL,
    item_name   VARCHAR(64) NOT NULL,
    quantity    INTEGER NOT NULL DEFAULT 1,
    UNIQUE (player_id, category, item_name)
);

CREATE TABLE player_cargo (
    id          BIGSERIAL PRIMARY KEY,
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_name   VARCHAR(64) NOT NULL,
    item_type   VARCHAR(32) NOT NULL DEFAULT '',
    quantity    INTEGER NOT NULL DEFAULT 1,
    icon_color  VARCHAR(32),
    UNIQUE (player_id, item_name)
);

CREATE TABLE player_equipment (
    player_id   UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    hardpoints  JSONB NOT NULL DEFAULT '[]',
    shield_name VARCHAR(64),
    engine_name VARCHAR(64),
    modules     JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
