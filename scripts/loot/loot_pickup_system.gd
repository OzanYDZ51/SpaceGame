class_name LootPickupSystem
extends Node

# =============================================================================
# Loot Pickup System - Scans for nearby cargo crates via EntityRegistry.
# Used by both PlayerShip (manual X pickup) and NPC ships (auto-collect).
# =============================================================================

signal crate_in_range(crate: CargoCrate)
signal crate_out_of_range()
signal crate_detected(crate: CargoCrate, dist: float)
signal crate_lost()

@export var pickup_range: float = 200.0
@export var awareness_range: float = 1000.0
@export var scan_interval: float = 0.25

## Override peer_id for loot ownership check. -1 = use local player peer.
## NPCs set this to 0 so they only loot unowned/abandoned crates.
var override_peer_id: int = -1

var nearest_crate: CargoCrate = null
var can_pickup: bool = false

## Closest crate within awareness_range (even if not yet lootable)
var nearest_crate_any: CargoCrate = null
var nearest_dist: float = INF

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

	# Awareness range: track any crate within 1km (even if not lootable)
	var had_awareness: bool = nearest_crate_any != null
	if best_crate and best_dist < awareness_range:
		nearest_crate_any = best_crate
		nearest_dist = best_dist
		if not had_awareness:
			crate_detected.emit(best_crate, best_dist)
	else:
		nearest_crate_any = null
		nearest_dist = INF
		if had_awareness:
			crate_lost.emit()

	# Pickup range: can actually loot within 200m + ownership check
	var was_available: bool = can_pickup

	var peer_id: int = override_peer_id if override_peer_id >= 0 else NetworkManager.local_peer_id
	if best_crate and best_dist < pickup_range and best_crate.can_be_looted_by(peer_id):
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
