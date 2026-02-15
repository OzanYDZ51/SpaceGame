class_name LootTable
extends RefCounted

# =============================================================================
# Loot Table - Data-driven drops from ShipData loot fields.
# =============================================================================

# Item types
const TYPE_CREDITS := "credits"
const TYPE_METAL := "metal"
const TYPE_ELECTRONICS := "electronics"
const TYPE_WEAPON_PART := "weapon_part"
const TYPE_DATA_CHIP := "data_chip"
const TYPE_WATER := "water"
const TYPE_IRON := "iron"

# Colors per type (for UI display)
const TYPE_COLORS := {
	"credits": Color(1.0, 0.85, 0.2),
	"metal": Color(0.7, 0.7, 0.75),
	"electronics": Color(0.3, 0.8, 1.0),
	"weapon_part": Color(1.0, 0.5, 0.2),
	"data_chip": Color(0.6, 1.0, 0.4),
	"water": Color(0.3, 0.75, 1.0),
	"iron": Color(0.72, 0.72, 0.78),
}

# Material pool for random rolls (includes economy resources)
const MATERIAL_POOL: Array[String] = ["metal", "electronics", "water", "iron"]


## Data-driven loot: reads parameters from ShipData fields.
static func roll_drops_for_ship(ship_data: ShipData) -> Array[Dictionary]:
	return _roll(
		ship_data.loot_credits_min, ship_data.loot_credits_max,
		ship_data.loot_mat_count_min, ship_data.loot_mat_count_max,
		ship_data.loot_weapon_part_chance, 0.0)


## Legacy compat wrapper — looks up ShipData by class, falls back to defaults.
static func roll_drops(ship_class: StringName) -> Array[Dictionary]:
	# Find first ship with matching class to get loot params
	for sid in ShipRegistry.get_all_ship_ids():
		var data := ShipRegistry.get_ship_data(sid)
		if data and data.ship_class == ship_class:
			return roll_drops_for_ship(data)
	# Fallback defaults
	return _roll(100, 300, 1, 1, 0.0, 0.0)


static func _roll(credit_min: int, credit_max: int, mat_min: int, mat_max: int,
		wp_chance: float, dc_chance: float) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []

	# Credits always drop
	drops.append({
		"name": "Credits",
		"type": TYPE_CREDITS,
		"quantity": randi_range(credit_min, credit_max),
		"icon_color": TYPE_COLORS[TYPE_CREDITS],
	})

	# Random materials
	var mat_count: int = randi_range(mat_min, mat_max)
	for i in mat_count:
		var mat_type: String = MATERIAL_POOL[randi() % MATERIAL_POOL.size()]
		var mat_name: String = mat_type.capitalize()
		# Try to stack with existing same-type entry
		var found := false
		for d in drops:
			if d["type"] == mat_type:
				d["quantity"] += randi_range(1, 3)
				found = true
				break
		if not found:
			drops.append({
				"name": mat_name,
				"type": mat_type,
				"quantity": randi_range(1, 3),
				"icon_color": TYPE_COLORS[mat_type],
			})

	# Rare: weapon part
	if wp_chance > 0.0 and randf() < wp_chance:
		drops.append({
			"name": "Weapon Part",
			"type": TYPE_WEAPON_PART,
			"quantity": 1,
			"icon_color": TYPE_COLORS[TYPE_WEAPON_PART],
		})

	# Rare: data chip
	if dc_chance > 0.0 and randf() < dc_chance:
		drops.append({
			"name": "Data Chip",
			"type": TYPE_DATA_CHIP,
			"quantity": 1,
			"icon_color": TYPE_COLORS[TYPE_DATA_CHIP],
		})

	return drops
