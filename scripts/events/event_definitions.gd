class_name EventDefinitions
extends RefCounted

# =============================================================================
# Event Definitions — Static templates for random event composition.
# Tier 1: Easy, Tier 2: Medium, Tier 3: Hard.
# =============================================================================

# Convoy composition per tier:
# Tier 1: freighter_arion + 2x chasseur_viper
# Tier 2: freighter_arion + 3x chasseur_arrw + 2x chasseur_viper
# Tier 3: croiseur_bodhammer (flagship) + 2x frigate_mk1 + 3x chasseur_arrw + 5x chasseur_viper

static func get_convoy_definition(tier: int) -> Dictionary:
	match tier:
		1:
			return {
				"leader": &"freighter_arion",
				"escorts": [
					{"ship_id": &"chasseur_viper", "count": 2},
				],
			}
		2:
			return {
				"leader": &"freighter_arion",
				"escorts": [
					{"ship_id": &"chasseur_arrw", "count": 3},
					{"ship_id": &"chasseur_viper", "count": 2},
				],
			}
		3:
			return {
				"leader": &"croiseur_bodhammer",
				"escorts": [
					{"ship_id": &"frigate_mk1", "count": 2},
					{"ship_id": &"chasseur_arrw", "count": 3},
					{"ship_id": &"chasseur_viper", "count": 5},
				],
			}
	# Fallback to tier 1
	return get_convoy_definition(1)


## Roll event tier based on system danger level.
static func roll_tier_for_danger(danger_level: int) -> int:
	var roll: float = randf()
	match danger_level:
		0, 1, 2:
			return 1
		3:
			return 2 if roll < 0.3 else 1
		4:
			if roll < 0.3:
				return 3
			elif roll < 0.7:
				return 2
			else:
				return 1
		5:
			if roll < 0.5:
				return 3
			else:
				return 2
	return 1


## Duration in seconds before the event despawns.
static func get_event_duration(tier: int) -> float:
	match tier:
		1: return 600.0   # 10 min
		2: return 750.0   # 12.5 min
		3: return 900.0   # 15 min
	return 600.0


## Spawn chance (0.0 to 1.0) when entering a system or on periodic check.
static func get_spawn_chance(danger_level: int) -> float:
	match danger_level:
		0: return 0.15
		1: return 0.25
		2: return 0.35
		3: return 0.50
		4: return 0.65
		5: return 0.80
	return 0.15


## Display name for an event type + tier (used by client when no EventData is available).
static func get_display_name_for_type(event_type: String, tier: int) -> String:
	match event_type:
		"pirate_convoy":
			match tier:
				1: return "CONVOI PIRATE"
				2: return "CONVOI PIRATE LOURD"
				3: return "ARMADA PIRATE"
	return "ÉVÉNEMENT"


## Credit reward for destroying the convoy leader.
static func get_leader_bonus_credits(tier: int) -> int:
	match tier:
		1: return 5000
		2: return 15000
		3: return 40000
	return 5000
