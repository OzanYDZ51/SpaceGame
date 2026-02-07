class_name AIBehaviorProfile
extends Resource

# =============================================================================
# AI Behavior Profile - Personality tuning for NPC pilots
# =============================================================================

@export var profile_name: StringName = &""

@export_range(0.0, 1.0) var aggression: float = 0.5
@export var preferred_range: float = 500.0
@export var evasion_frequency: float = 2.0       # evasive maneuvers per second
@export var evasion_amplitude: float = 30.0      # meters of jink offset
@export_range(0.0, 1.0) var flee_threshold: float = 0.2  # hull % to start fleeing
@export_range(0.0, 1.0) var accuracy: float = 0.7
@export_range(0.0, 1.0) var formation_discipline: float = 0.8
