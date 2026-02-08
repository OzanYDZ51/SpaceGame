class_name AsteroidBeltData
extends Resource

# =============================================================================
# Asteroid Belt Data — Editable in Godot inspector
# =============================================================================

@export var belt_name: String = ""
@export var field_id: StringName = &""
@export var orbital_radius: float = 75_000_000.0
@export var width: float = 5_000_000.0
@export var dominant_resource: StringName = &"iron"
@export var secondary_resource: StringName = &"copper"
@export var rare_resource: StringName = &"gold"
@export var asteroid_count: int = 300
@export var zone: String = "mid"  # "inner", "mid", "outer"
