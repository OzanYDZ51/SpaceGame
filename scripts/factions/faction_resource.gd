class_name FactionResource
extends Resource

# =============================================================================
# Faction Resource — Data-only definition of a faction.
# Loaded from .tres files in data/factions/.
# =============================================================================

@export_group("Identity")
@export var faction_id: StringName = &""
@export var faction_name: String = ""
@export var description: String = ""

@export_group("Visuals")
@export var color_primary: Color = Color.WHITE
@export var color_secondary: Color = Color.WHITE

@export_group("Gameplay")
@export var is_playable: bool = false
@export var enemy_faction_ids: Array[StringName] = []
