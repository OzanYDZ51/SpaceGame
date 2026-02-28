CREATE TABLE market_listings (
    id              BIGSERIAL PRIMARY KEY,
    seller_id       UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    seller_name     VARCHAR(32) NOT NULL,
    system_id       INTEGER NOT NULL,
    station_id      VARCHAR(128) NOT NULL,
    station_name    VARCHAR(128) NOT NULL,
    item_category   VARCHAR(32) NOT NULL,
    item_id         VARCHAR(64) NOT NULL,
    item_name       VARCHAR(128) NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    unit_price      BIGINT NOT NULL,
    listing_fee     BIGINT NOT NULL DEFAULT 0,
    status          VARCHAR(16) NOT NULL DEFAULT 'active',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    sold_to_id      UUID REFERENCES players(id),
    sold_to_name    VARCHAR(32),
    sold_at         TIMESTAMPTZ
);

CREATE INDEX idx_market_status ON market_listings(status) WHERE status = 'active';
CREATE INDEX idx_market_seller ON market_listings(seller_id);
CREATE INDEX idx_market_station ON market_listings(system_id, station_id) WHERE status = 'active';
CREATE INDEX idx_market_category ON market_listings(item_category) WHERE status = 'active';
CREATE INDEX idx_market_expires ON market_listings(expires_at) WHERE status = 'active';
