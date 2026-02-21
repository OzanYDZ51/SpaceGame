-- Revoke admin role from dev account
UPDATE players SET role = 'player' WHERE username = 'dev';
