-- Auto-grant admin to 'dev' on registration (covers fresh DB where migration 018 ran before account existed)
CREATE OR REPLACE FUNCTION set_dev_admin() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.username = 'dev' THEN
        NEW.role := 'admin';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- DROP first in case 018 already created it (idempotent)
DROP TRIGGER IF EXISTS trg_dev_admin ON players;
CREATE TRIGGER trg_dev_admin
    BEFORE INSERT ON players
    FOR EACH ROW
    EXECUTE FUNCTION set_dev_admin();

-- Also fix existing dev account if it was already created with role='player'
UPDATE players SET role = 'admin' WHERE username = 'dev' AND role != 'admin';
