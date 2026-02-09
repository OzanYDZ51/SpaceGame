class_name LootTable
extends RefCounted

# =============================================================================
# Loot Table - Defines drops by ship class
# Placeholder items for now; real economy items plug in later.
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


static func roll_drops(ship_class: StringName) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []

	# Per-class loot parameters
	var credit_min: int
	var credit_max: int
	var mat_count_min: int
	var mat_count_max: int
	var weapon_part_chance: float
	var data_chip_chance: float

	match ship_class:
		&"Fighter":
			credit_min = 150; credit_max = 400
			mat_count_min = 1; mat_count_max = 2
			weapon_part_chance = 0.0
			data_chip_chance = 0.0
		&"Frigate":
			credit_min = 500; credit_max = 1200
			mat_count_min = 3; mat_count_max = 4
			weapon_part_chance = 0.25
			data_chip_chance = 0.0
		_:
			credit_min = 100; credit_max = 300
			mat_count_min = 1; mat_count_max = 1
			weapon_part_chance = 0.0
			data_chip_chance = 0.0

	# Credits always drop
	drops.append({
		"name": "Credits",
		"type": TYPE_CREDITS,
		"quantity": randi_range(credit_min, credit_max),
		"icon_color": TYPE_COLORS[TYPE_CREDITS],
	})

	# Random materials
	var mat_count: int = randi_range(mat_count_min, mat_count_max)
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
	if weapon_part_chance > 0.0 and randf() < weapon_part_chance:
		drops.append({
			"name": "Weapon Part",
			"type": TYPE_WEAPON_PART,
			"quantity": 1,
			"icon_color": TYPE_COLORS[TYPE_WEAPON_PART],
		})

	# Rare: data chip
	if data_chip_chance > 0.0 and randf() < data_chip_chance:
		drops.append({
			"name": "Data Chip",
			"type": TYPE_DATA_CHIP,
			"quantity": 1,
			"icon_color": TYPE_COLORS[TYPE_DATA_CHIP],
		})

	return drops
