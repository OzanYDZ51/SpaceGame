-- Migration 017: Retire fighter_mk1 ship — replace with chasseur_viper

-- 1. fleet_ships table: replace ship_id, reset to DOCKED if was DEPLOYED
UPDATE fleet_ships
SET ship_id = 'chasseur_viper',
    deployment_state = CASE WHEN deployment_state = 1 THEN 0 ELSE deployment_state END,
    updated_at = NOW()
WHERE ship_id = 'fighter_mk1';

-- 2. players.current_ship_id: replace default ship
UPDATE players
SET current_ship_id = 'chasseur_viper',
    updated_at = NOW()
WHERE current_ship_id = 'fighter_mk1';

-- 3. players.fleet JSONB column: replace fighter_mk1 in fleet array
UPDATE players
SET fleet = (
    SELECT COALESCE(jsonb_agg(
        CASE
            WHEN elem->>'ship_id' = 'fighter_mk1'
            THEN jsonb_set(
                jsonb_set(elem, '{ship_id}', '"chasseur_viper"'),
                '{deployment_state}',
                CASE WHEN (elem->>'deployment_state')::int = 1 THEN '0'::jsonb ELSE elem->'deployment_state' END
            )
            ELSE elem
        END
    ), '[]'::jsonb)
    FROM jsonb_array_elements(fleet) AS elem
)
WHERE fleet IS NOT NULL
  AND fleet::text LIKE '%fighter_mk1%';

-- 4. Update column default for new players
ALTER TABLE players ALTER COLUMN current_ship_id SET DEFAULT 'chasseur_viper';
