class_name UIBar
extends UIComponent

# =============================================================================
# UI Bar - Status / progress bar with holographic style
# =============================================================================

@export var ratio: float = 1.0
@export var bar_color: Color = UITheme.PRIMARY
@export var label_text: String = ""
@export var show_percentage: bool = false
## If true, color auto-interpolates ACCENT → WARNING → DANGER based on ratio.
@export var auto_color: bool = false


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var col: Color = bar_color
	if auto_color:
		col = UITheme.ratio_color(ratio)

	draw_status_bar(Rect2(Vector2.ZERO, size), ratio, col, label_text, show_percentage)
