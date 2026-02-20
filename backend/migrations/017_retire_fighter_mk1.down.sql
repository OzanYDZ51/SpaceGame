-- Migration 017 DOWN: Restore fighter_mk1 as default (data already converted)

-- Ships were converted to chasseur_viper.
-- This migration only restores the column default.
ALTER TABLE players ALTER COLUMN current_ship_id SET DEFAULT 'fighter_mk1';
