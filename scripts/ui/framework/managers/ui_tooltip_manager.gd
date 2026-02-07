class_name UITooltipManager
extends Control

# =============================================================================
# UI Tooltip Manager - Manages a single tooltip instance
# Add as child of UI CanvasLayer. Components call show/hide.
# =============================================================================

var _tooltip: UITooltip = null
var _hover_timer: float = 0.0
var _pending_pos: Vector2 = Vector2.ZERO
var _pending_title: String = ""
var _pending_lines: Array[Dictionary] = []
var _has_pending: bool = false

const HOVER_DELAY := 0.3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)

	_tooltip = UITooltip.new()
	add_child(_tooltip)


## Request a tooltip to appear after the hover delay.
func request_tooltip(pos: Vector2, title: String, lines: Array[Dictionary] = []) -> void:
	_pending_pos = pos
	_pending_title = title
	_pending_lines = lines
	_has_pending = true
	_hover_timer = 0.0


## Immediately hide the tooltip and cancel any pending request.
func cancel_tooltip() -> void:
	_has_pending = false
	_hover_timer = 0.0
	_tooltip.hide_tooltip()


func _process(delta: float) -> void:
	if _has_pending:
		_hover_timer += delta
		if _hover_timer >= HOVER_DELAY:
			_tooltip.show_at(_pending_pos, _pending_title, _pending_lines)
			_has_pending = false
