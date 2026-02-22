class_name AIBehavior
extends RefCounted

# =============================================================================
# AI Behavior — Base class for all pluggable behaviors.
# Behaviors are owned by AIController and swapped at runtime.
# =============================================================================

# Behavior name constants (avoid scattered StringName literals)
const NAME_PATROL: StringName = &"patrol"
const NAME_COMBAT: StringName = &"combat"
const NAME_GUARD: StringName = &"guard"
const NAME_FORMATION: StringName = &"formation"
const NAME_LOOT: StringName = &"loot"

var controller = null  # AIController ref


func enter() -> void:
	pass


func exit() -> void:
	pass


func tick(_dt: float) -> void:
	pass


func get_behavior_name() -> StringName:
	return &""
