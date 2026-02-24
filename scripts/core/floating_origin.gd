class_name FloatingOriginSystem
extends Node

# =============================================================================
# Floating Origin System
# Prevents float32 precision loss by keeping the player near world origin.
# All objects shift when the player drifts too far from (0,0,0).
#
# Usage:
#   FloatingOrigin.to_universe_pos(local_pos) -> universe position
#   FloatingOrigin.to_local_pos(universe_pos) -> scene position
#   Connect to origin_shifted signal if you cache absolute positions
# =============================================================================

# Emitted when origin shifts. delta is the Vector3 shift applied.
signal origin_shifted(delta: Vector3)

# True universe offset from scene origin. Stored as separate float64 vars
# because GDScript float is 64-bit but Vector3 components are 32-bit.
var origin_offset_x: float = 0.0
var origin_offset_y: float = 0.0
var origin_offset_z: float = 0.0

# Reference to the tracked node (player ship)
var _tracked_node: Node3D = null

# Reference to the universe container (all shiftable objects)
var _universe_node: Node3D = null

# Stats
var total_shifts: int = 0


func set_tracked_node(node: Node3D) -> void:
	_tracked_node = node


func set_universe_node(node: Node3D) -> void:
	_universe_node = node


func _physics_process(_delta: float) -> void:
	if _tracked_node == null or _universe_node == null:
		return

	var pos: Vector3 = _tracked_node.global_position
	if pos.length() > Constants.ORIGIN_SHIFT_THRESHOLD:
		_perform_shift(pos)


func _perform_shift(shift: Vector3) -> void:
	# Update the 64-bit origin offset
	origin_offset_x += float(shift.x)
	origin_offset_y += float(shift.y)
	origin_offset_z += float(shift.z)

	# Shift the tracked node (player ship) back to near origin
	_tracked_node.global_position -= shift
	_tracked_node.reset_physics_interpolation()

	# Shift all children of the universe container
	for child in _universe_node.get_children():
		if child is Node3D:
			child.global_position -= shift
			child.reset_physics_interpolation()

	total_shifts += 1
	origin_shifted.emit(shift)


# Convert a local scene position to universe position (float64)
func to_universe_pos(local_pos: Vector3) -> Array:
	return [
		origin_offset_x + float(local_pos.x),
		origin_offset_y + float(local_pos.y),
		origin_offset_z + float(local_pos.z)
	]


# Convert a universe position (float64 array) to local scene position
func to_local_pos(universe_pos: Array) -> Vector3:
	return Vector3(
		float(universe_pos[0]) - origin_offset_x,
		float(universe_pos[1]) - origin_offset_y,
		float(universe_pos[2]) - origin_offset_z
	)


# Get the universe position as a formatted string (for HUD display)
func get_universe_pos_string() -> String:
	if _tracked_node == null:
		return "0, 0, 0"
	var pos: Vector3 = _tracked_node.global_position
	var ux: float = origin_offset_x + float(pos.x)
	var uy: float = origin_offset_y + float(pos.y)
	var uz: float = origin_offset_z + float(pos.z)
	return "%.0f, %.0f, %.0f" % [ux, uy, uz]


# Reset origin (for when jumping to a new star system)
func reset_origin() -> void:
	origin_offset_x = 0.0
	origin_offset_y = 0.0
	origin_offset_z = 0.0
	total_shifts = 0
