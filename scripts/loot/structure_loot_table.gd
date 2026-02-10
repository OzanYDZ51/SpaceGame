class_name StructureLootTable
extends RefCounted

# =============================================================================
# Structure Loot Table — Drops when a station is destroyed
# =============================================================================

static func roll_drops(station_type: int) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []

	var credit_min: int
	var credit_max: int
	var mats: Array[String] = []
	var mat_count_min: int
	var mat_count_max: int

	match station_type:
		0:  # REPAIR
			credit_min = 2000; credit_max = 5000
			mats = ["metal", "electronics"]
			mat_count_min = 2; mat_count_max = 4
		1:  # TRADE
			credit_min = 5000; credit_max = 12000
			mats = ["electronics", "metal", "water"]
			mat_count_min = 3; mat_count_max = 5
		2:  # MILITARY
			credit_min = 3000; credit_max = 8000
			mats = ["weapon_part", "metal", "electronics"]
			mat_count_min = 2; mat_count_max = 4
		3:  # MINING
			credit_min = 1000; credit_max = 3000
			mats = ["iron", "metal", "water"]
			mat_count_min = 2; mat_count_max = 3
		_:
			credit_min = 1500; credit_max = 4000
			mats = ["metal"]
			mat_count_min = 1; mat_count_max = 2

	# Credits
	drops.append({
		"name": "Credits",
		"type": LootTable.TYPE_CREDITS,
		"quantity": randi_range(credit_min, credit_max),
		"icon_color": LootTable.TYPE_COLORS[LootTable.TYPE_CREDITS],
	})

	# Materials
	var mat_count: int = randi_range(mat_count_min, mat_count_max)
	for i in mat_count:
		var mat_type: String = mats[randi() % mats.size()]
		var mat_name: String = mat_type.capitalize()
		var found := false
		for d in drops:
			if d["type"] == mat_type:
				d["quantity"] += randi_range(2, 6)
				found = true
				break
		if not found:
			drops.append({
				"name": mat_name,
				"type": mat_type,
				"quantity": randi_range(2, 6),
				"icon_color": LootTable.TYPE_COLORS.get(mat_type, Color.WHITE),
			})

	return drops
