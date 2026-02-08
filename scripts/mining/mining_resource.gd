class_name MiningResource
extends Resource

# =============================================================================
# Mining Resource - Defines a minable ore/material type
# =============================================================================

enum Rarity { COMMON, UNCOMMON, RARE, VERY_RARE, LEGENDARY }

@export var resource_id: StringName = &""
@export var display_name: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var base_value: int = 10
@export var mining_difficulty: float = 1.0
@export var color: Color = Color.GRAY
@export var icon_color: Color = Color.WHITE
@export var description: String = ""
