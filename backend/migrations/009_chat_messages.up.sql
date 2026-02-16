CREATE TABLE chat_messages (
    id          BIGSERIAL PRIMARY KEY,
    channel     SMALLINT NOT NULL,          -- 0=GLOBAL, 1=SYSTEM, 2=CLAN, 3=TRADE
    system_id   INT NOT NULL DEFAULT 0,     -- only relevant for channel=1 (SYSTEM)
    sender_name VARCHAR(32) NOT NULL,
    text        VARCHAR(500) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_global ON chat_messages(channel, created_at DESC) WHERE channel != 1;
CREATE INDEX idx_chat_system ON chat_messages(system_id, created_at DESC) WHERE channel = 1;
