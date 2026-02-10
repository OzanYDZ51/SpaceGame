class_name UITransition
extends RefCounted

# =============================================================================
# UI Transition - Tween-based transition presets for screens and components
# All methods return the Tween so callers can await or chain.
# =============================================================================

## Slide in from the right with fade.
static func slide_in_right(node: Control, duration: float = 0.4) -> Tween:
	node.modulate = Color(1.0, 1.0, 1.0, 0.0)
	node.position.x += 80.0
	var target_x: float = node.position.x - 80.0
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:x", target_x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "modulate", Color.WHITE, duration * 0.7).from(Color(1.0, 1.0, 1.0, 0.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


## Slide out to the right with fade.
static func slide_out_right(node: Control, duration: float = 0.3) -> Tween:
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:x", node.position.x + 80.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 0.0), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	return tw


## Scale in with slight bounce (for modals/popups).
static func scale_in(node: Control, duration: float = 0.35) -> Tween:
	node.modulate = Color(1.0, 1.0, 1.0, 0.0)
	node.scale = Vector2(0.92, 0.92)
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate", Color.WHITE, duration * 0.6).from(Color(1.0, 1.0, 1.0, 0.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


## Scale out (for closing modals).
static func scale_out(node: Control, duration: float = 0.25) -> Tween:
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector2(0.92, 0.92), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 0.0), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	return tw


## Holographic boot effect — flash bright then settle.
static func holo_boot(node: Control, duration: float = 0.6) -> Tween:
	node.modulate = Color(3.0, 2.0, 0.5, 0.0)
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", Color.WHITE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	return tw


## Cascade children — each child appears with a small delay.
static func cascade_children(parent: Control, delay_per: float = 0.05, duration: float = 0.3) -> Tween:
	var tw := parent.create_tween()
	var idx: int = 0
	for child in parent.get_children():
		if child is Control:
			child.modulate = Color(1.0, 1.0, 1.0, 0.0)
			child.position.y += 12.0
			var target_y: float = child.position.y - 12.0
			tw.tween_property(child, "modulate", Color.WHITE, duration).from(Color(1.0, 1.0, 1.0, 0.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(idx * delay_per)
			tw.parallel().tween_property(child, "position:y", target_y, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(idx * delay_per)
			idx += 1
	return tw


## Simple fade in.
static func fade_in(node: Control, duration: float = 0.3) -> Tween:
	node.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", Color.WHITE, duration).from(Color(1.0, 1.0, 1.0, 0.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


## Simple fade out.
static func fade_out(node: Control, duration: float = 0.25) -> Tween:
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 0.0), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	return tw
