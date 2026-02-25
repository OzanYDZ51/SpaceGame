-- Remove dev admin trigger
DROP TRIGGER IF EXISTS trg_dev_admin ON players;
DROP FUNCTION IF EXISTS set_dev_admin();
UPDATE players SET role = 'player' WHERE username = 'dev';
