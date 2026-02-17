-- Rename all clan tables and columns to corporation

-- 1. Drop old FK from players to clans (will re-add after renames)
ALTER TABLE players DROP CONSTRAINT IF EXISTS fk_players_clan;

-- 2. Rename tables
ALTER TABLE clans RENAME TO corporations;
ALTER TABLE clan_ranks RENAME TO corporation_ranks;
ALTER TABLE clan_members RENAME TO corporation_members;
ALTER TABLE clan_activity RENAME TO corporation_activity;
ALTER TABLE clan_diplomacy RENAME TO corporation_diplomacy;
ALTER TABLE clan_transactions RENAME TO corporation_transactions;
ALTER TABLE discord_clan_mapping RENAME TO discord_corporation_mapping;

-- 3. Rename columns in corporations table
ALTER TABLE corporations RENAME COLUMN clan_name TO corporation_name;
ALTER TABLE corporations RENAME COLUMN clan_tag TO corporation_tag;
ALTER TABLE corporations RENAME COLUMN clan_color TO corporation_color;

-- 4. Rename clan_id columns in child tables
ALTER TABLE corporation_ranks RENAME COLUMN clan_id TO corporation_id;
ALTER TABLE corporation_members RENAME COLUMN clan_id TO corporation_id;
ALTER TABLE corporation_activity RENAME COLUMN clan_id TO corporation_id;
ALTER TABLE corporation_transactions RENAME COLUMN clan_id TO corporation_id;
ALTER TABLE corporation_diplomacy RENAME COLUMN clan_id TO corporation_id;
ALTER TABLE corporation_diplomacy RENAME COLUMN target_clan_id TO target_corporation_id;
ALTER TABLE discord_corporation_mapping RENAME COLUMN clan_id TO corporation_id;

-- 5. Rename clan_id in players table
ALTER TABLE players RENAME COLUMN clan_id TO corporation_id;

-- 6. Re-add FK from players to corporations
ALTER TABLE players ADD CONSTRAINT fk_players_corporation FOREIGN KEY (corporation_id) REFERENCES corporations(id) ON DELETE SET NULL;

-- 7. Rename indexes for clarity
ALTER INDEX IF EXISTS idx_players_clan RENAME TO idx_players_corporation;
ALTER INDEX IF EXISTS idx_clan_members_clan RENAME TO idx_corporation_members_corporation;
ALTER INDEX IF EXISTS idx_clan_activity_clan_created RENAME TO idx_corporation_activity_created;
ALTER INDEX IF EXISTS idx_clan_transactions_clan RENAME TO idx_corporation_transactions;

-- 8. Rename unique constraint on corporation_ranks
-- PostgreSQL auto-renames constraints with table renames, but update the unique constraint name
ALTER INDEX IF EXISTS clan_ranks_clan_id_priority_key RENAME TO corporation_ranks_corporation_id_priority_key;
