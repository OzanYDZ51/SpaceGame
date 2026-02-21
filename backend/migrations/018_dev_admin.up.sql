-- Set dev account as admin
UPDATE players SET role = 'admin' WHERE username = 'dev';
