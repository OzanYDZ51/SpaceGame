-- Revert: rename corporation tables/columns back to clan

ALTER TABLE players DROP CONSTRAINT IF EXISTS fk_players_corporation;

-- Rename tables back
ALTER TABLE corporations RENAME TO clans;
ALTER TABLE corporation_ranks RENAME TO clan_ranks;
ALTER TABLE corporation_members RENAME TO clan_members;
ALTER TABLE corporation_activity RENAME TO clan_activity;
ALTER TABLE corporation_diplomacy RENAME TO clan_diplomacy;
ALTER TABLE corporation_transactions RENAME TO clan_transactions;
ALTER TABLE discord_corporation_mapping RENAME TO discord_clan_mapping;

-- Rename columns back
ALTER TABLE clans RENAME COLUMN corporation_name TO clan_name;
ALTER TABLE clans RENAME COLUMN corporation_tag TO clan_tag;
ALTER TABLE clans RENAME COLUMN corporation_color TO clan_color;

ALTER TABLE clan_ranks RENAME COLUMN corporation_id TO clan_id;
ALTER TABLE clan_members RENAME COLUMN corporation_id TO clan_id;
ALTER TABLE clan_activity RENAME COLUMN corporation_id TO clan_id;
ALTER TABLE clan_transactions RENAME COLUMN corporation_id TO clan_id;
ALTER TABLE clan_diplomacy RENAME COLUMN corporation_id TO clan_id;
ALTER TABLE clan_diplomacy RENAME COLUMN target_corporation_id TO target_clan_id;
ALTER TABLE discord_clan_mapping RENAME COLUMN corporation_id TO clan_id;

ALTER TABLE players RENAME COLUMN corporation_id TO clan_id;

ALTER TABLE players ADD CONSTRAINT fk_players_clan FOREIGN KEY (clan_id) REFERENCES clans(id) ON DELETE SET NULL;

ALTER INDEX IF EXISTS idx_players_corporation RENAME TO idx_players_clan;
ALTER INDEX IF EXISTS idx_corporation_members_corporation RENAME TO idx_clan_members_clan;
ALTER INDEX IF EXISTS idx_corporation_activity_created RENAME TO idx_clan_activity_clan_created;
ALTER INDEX IF EXISTS idx_corporation_transactions RENAME TO idx_clan_transactions_clan;
ALTER INDEX IF EXISTS corporation_ranks_corporation_id_priority_key RENAME TO clan_ranks_clan_id_priority_key;
