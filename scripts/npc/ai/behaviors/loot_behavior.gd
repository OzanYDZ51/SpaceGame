class_name LootBehavior
extends AIBehavior

# =============================================================================
# Loot Behavior — Fly toward nearest crate and collect it.
# Extracted from AIBrain._tick_loot_pickup.
# =============================================================================


func tick(dt: float) -> void:
	if controller == null:
		return
	var nav: AINavigation = controller.navigation
	if nav == null:
		return

	var loot_pickup = controller._loot_pickup
	if loot_pickup == null or not loot_pickup.can_pickup:
		controller._return_to_default_behavior()
		return

	var crate: CargoCrate = loot_pickup.nearest_crate
	if crate == null or not is_instance_valid(crate):
		controller._return_to_default_behavior()
		return

	var crate_pos: Vector3 = crate.global_position
	nav.fly_toward(crate_pos, 30.0)

	if nav.get_distance_to(crate_pos) < loot_pickup.pickup_range * 0.15:
		crate.collect()
		controller._return_to_default_behavior()


func get_behavior_name() -> StringName:
	return &"loot"
