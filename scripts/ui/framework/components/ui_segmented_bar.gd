class_name UISegmentedBar
extends UIComponent

# =============================================================================
# UI Segmented Bar - Bar divided into N segments (e.g., energy pips)
# =============================================================================

@export var segments: int = 4
@export var ratio: float = 1.0
@export var bar_color: Color = UITheme.PRIMARY
@export var label_text: String = ""

const SEGMENT_GAP := 2.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font: Font = UITheme.get_font()
	var fsize: int = UITheme.FONT_SIZE_TINY

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.BG_DARK)

	if segments <= 0:
		return

	var total_gaps: float = SEGMENT_GAP * (segments - 1)
	var seg_w: float = (size.x - total_gaps) / segments
	var filled_count: float = ratio * segments

	for i in segments:
		var x: float = i * (seg_w + SEGMENT_GAP)
		var seg_rect := Rect2(x, 0, seg_w, size.y)

		if float(i) < filled_count:
			# Full or partial fill
			var fill: float = clampf(filled_count - float(i), 0.0, 1.0)
			if fill >= 1.0:
				draw_rect(seg_rect, bar_color)
			else:
				draw_rect(Rect2(x, 0, seg_w * fill, size.y), bar_color)
		else:
			# Empty segment - very dim
			draw_rect(seg_rect, Color(bar_color.r, bar_color.g, bar_color.b, 0.08))

		# Segment border
		draw_rect(seg_rect, UITheme.BORDER, false, 1.0)

	# Label
	if label_text != "":
		draw_string(font, Vector2(3, size.y - 2), label_text, HORIZONTAL_ALIGNMENT_LEFT, size.x, fsize, UITheme.TEXT_DIM)
