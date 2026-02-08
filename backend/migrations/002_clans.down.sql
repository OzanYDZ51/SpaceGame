DROP TABLE IF EXISTS clan_transactions;
DROP TABLE IF EXISTS clan_diplomacy;
DROP TABLE IF EXISTS clan_activity;
DROP TABLE IF EXISTS clan_members;
DROP TABLE IF EXISTS clan_ranks;
ALTER TABLE players DROP CONSTRAINT IF EXISTS fk_players_clan;
DROP TABLE IF EXISTS clans;
