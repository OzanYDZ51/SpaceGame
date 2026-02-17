-- Add role column to players (default 'player', admin gets special chat display)
ALTER TABLE players ADD COLUMN role VARCHAR(16) NOT NULL DEFAULT 'player';

-- Set LeSultan as admin
UPDATE players SET role = 'admin' WHERE username = 'LeSultan';
