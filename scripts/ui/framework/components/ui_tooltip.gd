class_name UITooltip
extends UIComponent

# =============================================================================
# UI Tooltip - Floating info panel near cursor
# Title + key/value lines. Managed by UITooltipManager.
# =============================================================================

var title: String = ""
var lines: Array[Dictionary] = []  # [{ "key": String, "value": String }]

const PADDING := 10.0
const LINE_HEIGHT := 16.0
const MAX_WIDTH := 250.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 100


## Show the tooltip with given content near a position.
func show_at(pos: Vector2, p_title: String, p_lines: Array[Dictionary] = []) -> void:
	title = p_title
	lines = p_lines
	visible = true
	_update_size()
	# Offset slightly from cursor
	position = pos + Vector2(16, 8)
	# Clamp to screen
	var vp_size := get_viewport_rect().size
	if position.x + size.x > vp_size.x:
		position.x = pos.x - size.x - 8
	if position.y + size.y > vp_size.y:
		position.y = vp_size.y - size.y - 4
	queue_redraw()


func hide_tooltip() -> void:
	visible = false


func _update_size() -> void:
	var h: float = PADDING * 2 + LINE_HEIGHT  # title
	h += lines.size() * LINE_HEIGHT
	size = Vector2(MAX_WIDTH, h)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font: Font = UITheme.get_font()

	draw_panel_bg(rect, UITheme.BG_MODAL)

	# Title
	var y: float = PADDING + UITheme.FONT_SIZE_LABEL
	draw_string(font, Vector2(PADDING, y), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - PADDING * 2, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	# Separator
	y += 4
	draw_line(Vector2(PADDING, y), Vector2(size.x - PADDING, y), UITheme.BORDER, 1.0)
	y += 4

	# Key-value lines
	for line in lines:
		y = draw_key_value(PADDING, y, size.x - PADDING * 2, line.get("key", ""), line.get("value", ""))
