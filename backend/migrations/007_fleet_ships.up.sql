CREATE TABLE fleet_ships (
    id              BIGSERIAL PRIMARY KEY,
    player_id       UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    fleet_index     SMALLINT NOT NULL,
    ship_id         VARCHAR(64) NOT NULL,
    custom_name     VARCHAR(128) NOT NULL DEFAULT '',
    deployment_state SMALLINT NOT NULL DEFAULT 0,  -- 0=DOCKED, 1=DEPLOYED, 2=DESTROYED
    system_id       INT NOT NULL DEFAULT 0,
    station_id      VARCHAR(128) NOT NULL DEFAULT '',
    pos_x           DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y           DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z           DOUBLE PRECISION NOT NULL DEFAULT 0,
    command         VARCHAR(64) NOT NULL DEFAULT '',
    command_params  JSONB NOT NULL DEFAULT '{}',
    weapons         JSONB NOT NULL DEFAULT '[]',
    shield_name     VARCHAR(64) NOT NULL DEFAULT '',
    engine_name     VARCHAR(64) NOT NULL DEFAULT '',
    modules         JSONB NOT NULL DEFAULT '[]',
    cargo           JSONB NOT NULL DEFAULT '[]',
    ship_resources  JSONB NOT NULL DEFAULT '{}',
    hull_ratio      REAL NOT NULL DEFAULT 1.0,
    shield_ratio    REAL NOT NULL DEFAULT 1.0,
    squadron_id     SMALLINT NOT NULL DEFAULT -1,
    squadron_role   VARCHAR(32) NOT NULL DEFAULT '',
    deployed_at     TIMESTAMPTZ,
    destroyed_at    TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(player_id, fleet_index)
);

CREATE INDEX idx_fleet_ships_player ON fleet_ships(player_id);
CREATE INDEX idx_fleet_ships_deployed ON fleet_ships(deployment_state) WHERE deployment_state = 1;
CREATE INDEX idx_fleet_ships_system ON fleet_ships(system_id) WHERE deployment_state = 1;
