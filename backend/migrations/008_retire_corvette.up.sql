-- Migration 008: Retire corvette_mk1 ship — replace with fighter_mk1

-- 1. fleet_ships table: replace ship_id, reset to DOCKED if was DEPLOYED
UPDATE fleet_ships
SET ship_id = 'fighter_mk1',
    deployment_state = CASE WHEN deployment_state = 1 THEN 0 ELSE deployment_state END,
    updated_at = NOW()
WHERE ship_id = 'corvette_mk1';

-- 2. players.fleet JSONB column: replace corvette_mk1 in fleet array
UPDATE players
SET fleet = (
    SELECT COALESCE(jsonb_agg(
        CASE
            WHEN elem->>'ship_id' = 'corvette_mk1'
            THEN jsonb_set(
                jsonb_set(elem, '{ship_id}', '"fighter_mk1"'),
                '{deployment_state}',
                CASE WHEN (elem->>'deployment_state')::int = 1 THEN '0'::jsonb ELSE elem->'deployment_state' END
            )
            ELSE elem
        END
    ), '[]'::jsonb)
    FROM jsonb_array_elements(fleet) AS elem
)
WHERE fleet IS NOT NULL
  AND fleet::text LIKE '%corvette_mk1%';
