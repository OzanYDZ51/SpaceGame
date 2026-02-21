class_name EncounterConfig
extends RefCounted

# =============================================================================
# Encounter Config - Data-driven danger-level composition.
# Queries ShipRegistry for ships by npc_tier to build encounter groups.
# Shared by EncounterManager (local) and NpcAuthority (remote systems).
# =============================================================================


## Returns an array of spawn group configs for a given danger level.
## Each entry: { "count": int, "ship": StringName, "fac": StringName, "radius": float }
static func get_danger_config(danger_level: int) -> Array[Dictionary]:
	# Categorize ships by npc_tier
	var tier0: Array[StringName] = []  # low (fighters)
	var tier1: Array[StringName] = []  # mid
	var tier2: Array[StringName] = []  # high (frigates)

	for sid in ShipRegistry.get_all_ship_ids():
		var data := ShipRegistry.get_ship_data(sid)
		if data == null:
			continue
		match data.npc_tier:
			0: tier0.append(sid)
			1: tier1.append(sid)
			2: tier2.append(sid)

	# Fallback IDs in case tiers are empty
	var t0: StringName = tier0[0] if not tier0.is_empty() else Constants.DEFAULT_SHIP_ID
	var t1: StringName = tier1[0] if not tier1.is_empty() else t0
	var t2: StringName = tier2[0] if not tier2.is_empty() else t1

	# Find a freighter for pirate cargo encounters
	var freighter: StringName = &""
	for sid in ShipRegistry.get_all_ship_ids():
		var data := ShipRegistry.get_ship_data(sid)
		if data and data.ship_class == &"Freighter":
			freighter = sid
			break

	var configs: Array[Dictionary] = []
	match danger_level:
		0:
			configs = [{"count": 1, "ship": t0, "fac": &"pirate", "radius": 400.0}]
		1:
			configs = [{"count": 2, "ship": t0, "fac": &"pirate", "radius": 300.0}]
		2:
			configs = [{"count": 2, "ship": t0, "fac": &"pirate", "radius": 400.0}]
		3:
			configs = [
				{"count": 1, "ship": t1, "fac": &"pirate", "radius": 500.0},
				{"count": 2, "ship": t0, "fac": &"pirate", "radius": 400.0},
			]
			if freighter != &"":
				configs.append({"count": 1, "ship": freighter, "fac": &"pirate", "radius": 600.0})
		4:
			configs = [
				{"count": 1, "ship": t2, "fac": &"pirate", "radius": 600.0},
				{"count": 2, "ship": t1, "fac": &"pirate", "radius": 400.0},
				{"count": 1, "ship": t0, "fac": &"pirate", "radius": 300.0},
			]
			if freighter != &"":
				configs.append({"count": 1, "ship": freighter, "fac": &"pirate", "radius": 600.0})
				configs.append({"count": 2, "ship": t0, "fac": &"pirate", "radius": 500.0})
		5:
			configs = [
				{"count": 1, "ship": t2, "fac": &"pirate", "radius": 500.0},
				{"count": 2, "ship": t1, "fac": &"pirate", "radius": 400.0},
			]
			if freighter != &"":
				configs.append({"count": 1, "ship": freighter, "fac": &"pirate", "radius": 600.0})
				configs.append({"count": 2, "ship": t0, "fac": &"pirate", "radius": 500.0})
	return configs
