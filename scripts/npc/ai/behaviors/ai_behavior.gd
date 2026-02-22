class_name AIBehavior
extends RefCounted

# =============================================================================
# AI Behavior — Base class for all pluggable behaviors.
# Behaviors are owned by AIController and swapped at runtime.
# =============================================================================

var controller = null  # AIController ref


func enter() -> void:
	pass


func exit() -> void:
	pass


func tick(_dt: float) -> void:
	pass


func get_behavior_name() -> StringName:
	return &""
