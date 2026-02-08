class_name LootPickupSystem
extends Node

# =============================================================================
# Loot Pickup System - Child of PlayerShip, scans for nearby cargo crates
# Same pattern as DockingSystem (periodic scan of EntityRegistry).
# =============================================================================

signal crate_in_range(crate: CargoCrate)
signal crate_out_of_range()

@export var pickup_range: float = 200.0
@export var scan_interval: float = 0.25

var nearest_crate: CargoCrate = null
var can_pickup: bool = false

var _ship: Node3D = null
var _check_timer: float = 0.0


func _ready() -> void:
	_ship = get_parent() as Node3D


func _process(delta: float) -> void:
	if _ship == null:
		return

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = scan_interval
		_scan_crates()


func _scan_crates() -> void:
	var crates := EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.CARGO_CRATE)
	var best_dist: float = INF
	var best_crate: CargoCrate = null

	for ent in crates:
		var node_ref = ent.get("node")
		if node_ref == null or not is_instance_valid(node_ref):
			continue
		var node: Node3D = node_ref
		if not node is CargoCrate:
			continue
		var dist: float = _ship.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_crate = node as CargoCrate

	var was_available: bool = can_pickup

	if best_crate and best_dist < pickup_range:
		can_pickup = true
		nearest_crate = best_crate
		if not was_available:
			crate_in_range.emit(best_crate)
	else:
		if was_available:
			crate_out_of_range.emit()
		can_pickup = false
		nearest_crate = null


func request_pickup() -> CargoCrate:
	if not can_pickup or nearest_crate == null:
		return null
	return nearest_crate
