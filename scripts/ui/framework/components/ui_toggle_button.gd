class_name UIToggleButton
extends UIButton

# =============================================================================
# UI Toggle Button - On/off button with diamond indicator
# =============================================================================

signal toggled(is_on: bool)

var is_on: bool = false


func _ready() -> void:
	super._ready()
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	is_on = not is_on
	toggled.emit(is_on)
	queue_redraw()


func _draw() -> void:
	super._draw()

	# Diamond indicator on the right side
	var cx: float = size.x - 16
	var cy: float = size.y * 0.5
	var ds: float = 5.0  # diamond half-size

	var diamond := PackedVector2Array([
		Vector2(cx, cy - ds),
		Vector2(cx + ds, cy),
		Vector2(cx, cy + ds),
		Vector2(cx - ds, cy),
	])

	if is_on:
		var col := UITheme.ACCENT
		draw_colored_polygon(diamond, col)
		# Glow
		draw_colored_polygon(diamond, Color(col.r, col.g, col.b, 0.2))
	else:
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), UITheme.TEXT_DIM, 1.0)
