CREATE TABLE corporation_applications (
    id             BIGSERIAL PRIMARY KEY,
    corporation_id UUID NOT NULL REFERENCES corporations(id) ON DELETE CASCADE,
    player_id      UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    player_name    VARCHAR(32) NOT NULL DEFAULT '',
    note           TEXT NOT NULL DEFAULT '',
    status         VARCHAR(16) NOT NULL DEFAULT 'pending',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(corporation_id, player_id)
);

CREATE INDEX idx_corporation_applications_corp ON corporation_applications(corporation_id, status);
CREATE INDEX idx_corporation_applications_player ON corporation_applications(player_id, status);
