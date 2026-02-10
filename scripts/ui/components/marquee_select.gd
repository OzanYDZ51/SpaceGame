class_name MarqueeSelect
extends RefCounted

# =============================================================================
# Reusable rubber-band rectangle selection helper.
# Call begin/update/end from input; read rect/active for drawing.
# =============================================================================

var active: bool = false
var start_pos: Vector2 = Vector2.ZERO
var current_pos: Vector2 = Vector2.ZERO

const MIN_DRAG: float = 5.0


func begin(pos: Vector2) -> void:
	active = true
	start_pos = pos
	current_pos = pos


func update_pos(pos: Vector2) -> void:
	if active:
		current_pos = pos


func end() -> void:
	active = false


func cancel() -> void:
	active = false


func get_rect() -> Rect2:
	var tl := Vector2(minf(start_pos.x, current_pos.x), minf(start_pos.y, current_pos.y))
	var br := Vector2(maxf(start_pos.x, current_pos.x), maxf(start_pos.y, current_pos.y))
	return Rect2(tl, br - tl)


func is_drag() -> bool:
	return start_pos.distance_to(current_pos) > MIN_DRAG
