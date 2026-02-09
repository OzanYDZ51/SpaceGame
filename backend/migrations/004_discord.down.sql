DROP TABLE IF EXISTS changelogs;
DROP TABLE IF EXISTS game_events;
DROP TABLE IF EXISTS discord_clan_mapping;
ALTER TABLE players DROP COLUMN IF EXISTS discord_link_expires;
ALTER TABLE players DROP COLUMN IF EXISTS discord_link_code;
ALTER TABLE players DROP COLUMN IF EXISTS discord_id;
