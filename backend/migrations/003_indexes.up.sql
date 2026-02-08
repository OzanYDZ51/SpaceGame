CREATE INDEX idx_players_clan ON players(clan_id);
CREATE INDEX idx_player_resources_player ON player_resources(player_id);
CREATE INDEX idx_player_inventory_player ON player_inventory(player_id);
CREATE INDEX idx_player_cargo_player ON player_cargo(player_id);
CREATE INDEX idx_refresh_tokens_player ON refresh_tokens(player_id);
CREATE INDEX idx_clan_members_clan ON clan_members(clan_id);
CREATE INDEX idx_clan_activity_clan_created ON clan_activity(clan_id, created_at DESC);
CREATE INDEX idx_clan_transactions_clan ON clan_transactions(clan_id, created_at DESC);
