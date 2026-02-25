-- Set dev account as admin (both existing and future registrations)
UPDATE players SET role = 'admin' WHERE username = 'dev';

-- Trigger: auto-grant admin to 'dev' on INSERT (covers fresh DB where user registers after migration)
CREATE OR REPLACE FUNCTION set_dev_admin() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.username = 'dev' THEN
        NEW.role := 'admin';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dev_admin
    BEFORE INSERT ON players
    FOR EACH ROW
    EXECUTE FUNCTION set_dev_admin();
