class_name ShipActivationController
extends Node

# =============================================================================
# Ship Activation Controller — Centralized ship deactivation/activation.
# Handles visibility, collision, group membership, map presence, targeting.
# Idempotent: double-deactivate is a no-op, double-activate is a no-op.
# =============================================================================

signal deactivated(mode: DeactivationMode)
signal activated()

enum DeactivationMode {
	FULL,        ## Docking, death: invisible, no collision, removed from "ships", hidden on map
	INTANGIBLE,  ## Cruise warp phase 2: no collision, but visible and on map
}

var _ship: RigidBody3D = null
var _active_mode: int = -1  ## Current mode or -1 if not deactivated
var _saved_state: Dictionary = {}


func _ready() -> void:
	_ship = get_parent() as RigidBody3D


func deactivate(mode: DeactivationMode, freeze_physics: bool = false) -> void:
	if _active_mode >= 0:
		return  # Already deactivated — no-op to protect saved state

	_active_mode = mode

	# Save state before any changes
	_saved_state = {
		"collision_layer": _ship.collision_layer,
		"collision_mask": _ship.collision_mask,
	}

	match mode:
		DeactivationMode.FULL:
			_apply_full(freeze_physics)
		DeactivationMode.INTANGIBLE:
			_apply_intangible()

	deactivated.emit(mode)


func activate() -> void:
	if _active_mode < 0:
		return  # Not deactivated — no-op

	# Restore collision
	_ship.collision_layer = _saved_state.get("collision_layer", Constants.LAYER_SHIPS)
	_ship.collision_mask = _saved_state.get("collision_mask", Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS)

	# Restore visibility (only FULL hides it)
	if _saved_state.has("was_visible"):
		_ship.visible = _saved_state["was_visible"]

	# Restore freeze (only FULL with freeze_physics sets it)
	if _saved_state.has("was_frozen"):
		_ship.freeze = _saved_state["was_frozen"]

	# Restore group membership
	if _saved_state.get("in_ships_group", false) and not _ship.is_in_group("ships"):
		_ship.add_to_group("ships")

	# Restore map visibility
	var player_ent: Dictionary = EntityRegistry.get_entity("player_ship")
	if not player_ent.is_empty() and player_ent.has("extra"):
		player_ent["extra"]["hidden"] = false

	# Restore targeting system
	if _saved_state.has("targeting_process_mode"):
		var targeting := _ship.get_node_or_null("TargetingSystem") as TargetingSystem
		if targeting:
			targeting.process_mode = _saved_state["targeting_process_mode"] as Node.ProcessMode

	_saved_state.clear()
	_active_mode = -1

	activated.emit()


func is_deactivated() -> bool:
	return _active_mode >= 0


func get_mode() -> int:
	return _active_mode


# === Private ===

func _apply_full(freeze_physics: bool) -> void:
	# Save extra state for FULL mode
	_saved_state["was_visible"] = _ship.visible
	_saved_state["in_ships_group"] = _ship.is_in_group("ships")
	_saved_state["was_frozen"] = _ship.freeze

	# Hide ship
	_ship.visible = false

	# Remove collision
	_ship.collision_layer = 0
	_ship.collision_mask = 0

	# Remove from targeting group
	if _ship.is_in_group("ships"):
		_ship.remove_from_group("ships")

	# Hide on stellar map
	var player_ent: Dictionary = EntityRegistry.get_entity("player_ship")
	if not player_ent.is_empty() and player_ent.has("extra"):
		player_ent["extra"]["hidden"] = true

	# Disable targeting system
	var targeting := _ship.get_node_or_null("TargetingSystem") as TargetingSystem
	if targeting:
		_saved_state["targeting_process_mode"] = targeting.process_mode
		targeting.clear_target()
		targeting.process_mode = Node.PROCESS_MODE_DISABLED

	# Freeze physics if requested (death)
	if freeze_physics:
		_ship.freeze = true


func _apply_intangible() -> void:
	# Only remove collision — ship stays visible, in group, on map
	_ship.collision_layer = 0
	_ship.collision_mask = 0
