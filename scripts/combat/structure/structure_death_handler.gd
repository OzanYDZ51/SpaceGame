class_name StructureDeathHandler
extends Node

# =============================================================================
# Structure Death Handler — Explosion VFX, hide, respawn timer
# Connects to StructureHealth.structure_destroyed on the same parent.
# =============================================================================

signal station_destroyed(station_name: String)
signal station_respawned(station_name: String)

const RESPAWN_TIME: float = 300.0  # 5 minutes

var _station: Node3D = null
var _health = null
var _respawn_timer: float = -1.0
var _collision_shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_station = get_parent() as Node3D
	if _station == null:
		return
	_health = _station.get_node_or_null("StructureHealth")
	if _health:
		_health.structure_destroyed.connect(_on_destroyed)


func _process(delta: float) -> void:
	if _respawn_timer < 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		_respawn()


func _on_destroyed() -> void:
	if _station == null:
		return

	# Explosion VFX
	_spawn_explosion()

	# Hide model (children that are visual)
	for child in _station.get_children():
		if child is MeshInstance3D or child is Node3D and not (child is CollisionShape3D) and not (child is Node):
			if child != self and child != _health:
				child.visible = false

	# Specifically hide all mesh instances recursively
	for child in _get_all_children(_station):
		if child is MeshInstance3D:
			child.visible = false

	# Disable collision
	_collision_shapes.clear()
	for child in _get_all_children(_station):
		if child is CollisionShape3D:
			_collision_shapes.append(child)
			child.disabled = true

	# Remove from structures group
	if _station.is_in_group("structures"):
		_station.remove_from_group("structures")

	# Drop loot (server only — clients receive via StructureAuthority)
	if NetworkManager.is_server():
		_drop_loot()

	station_destroyed.emit(_station.station_name if "station_name" in _station else _station.name)

	# Start respawn timer
	_respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	if _station == null or _health == null:
		return

	_health.revive()

	# Show model
	for child in _get_all_children(_station):
		if child is MeshInstance3D:
			child.visible = true

	# Re-enable collision
	for col in _collision_shapes:
		if is_instance_valid(col):
			col.disabled = false
	_collision_shapes.clear()

	# Re-add to group
	if not _station.is_in_group("structures"):
		_station.add_to_group("structures")

	station_respawned.emit(_station.station_name if "station_name" in _station else _station.name)


func _drop_loot() -> void:
	var station_type: int = 0
	if "station_type" in _station:
		station_type = _station.station_type
	var drops: Array[Dictionary] = StructureLootTable.roll_drops(station_type)
	if drops.is_empty():
		return

	# Spawn a cargo crate at station position
	var crate =CargoCrate.new()
	crate.global_position = _station.global_position + Vector3(0, 50, 0)
	crate.contents = drops
	var universe =GameManager.universe_node
	if universe:
		universe.add_child(crate)


func _spawn_explosion() -> void:
	# Large explosion effect at station position
	var scene_root =get_tree().current_scene
	if scene_root == null:
		return
	var effect =HullHitEffect.new()
	scene_root.add_child(effect)
	effect.global_position = _station.global_position
	effect.setup(Vector3.UP, 8.0)  # Large intensity


func _get_all_children(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_children(child))
	return result
