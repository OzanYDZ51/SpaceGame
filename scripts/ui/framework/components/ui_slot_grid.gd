class_name UISlotGrid
extends UIComponent

# =============================================================================
# UI Slot Grid - Grid of slots (inventory, loadout)
# Empty slot = dim rect + diamond. Selection pulses cyan.
# =============================================================================

signal slot_clicked(index: int)

@export var columns: int = 4
@export var slot_size: float = 64.0
@export var slot_gap: float = 4.0

var slot_count: int = 0
var selected_slot: int = -1

## Callback: func(ctrl: Control, index: int, rect: Rect2) -> void
var slot_draw_callback: Callable = Callable()

var _hovered_slot: int = -1


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _hovered_slot = -1; queue_redraw())


func _draw() -> void:
	for i in slot_count:
		var rect := _slot_rect(i)

		# Background
		draw_rect(rect, UITheme.BG_DARK)

		# Hover
		if i == _hovered_slot:
			draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.08))

		# Selection (pulsing)
		if i == selected_slot:
			var pulse: float = UITheme.get_pulse(1.0)
			var alpha: float = lerpf(0.1, 0.2, pulse)
			draw_rect(rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, alpha))
			draw_rect(rect, UITheme.BORDER_ACTIVE, false, 1.5)
		else:
			draw_rect(rect, UITheme.BORDER, false, 1.0)

		# Custom draw or empty diamond
		if slot_draw_callback.is_valid():
			slot_draw_callback.call(self, i, rect)
		else:
			_draw_empty_diamond(rect)


func _draw_empty_diamond(rect: Rect2) -> void:
	var cx: float = rect.position.x + rect.size.x * 0.5
	var cy: float = rect.position.y + rect.size.y * 0.5
	var ds: float = 6.0
	var diamond := PackedVector2Array([
		Vector2(cx, cy - ds),
		Vector2(cx + ds, cy),
		Vector2(cx, cy + ds),
		Vector2(cx - ds, cy),
		Vector2(cx, cy - ds),
	])
	draw_polyline(diamond, UITheme.PRIMARY_FAINT, 1.0)


func _slot_rect(index: int) -> Rect2:
	var col: int = index % columns
	var row: int = index / columns
	var x: float = col * (slot_size + slot_gap)
	var y: float = row * (slot_size + slot_gap)
	return Rect2(x, y, slot_size, slot_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var idx := _hit_test(event.position)
		if idx != _hovered_slot:
			_hovered_slot = idx
			queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx := _hit_test(event.position)
		if idx >= 0:
			selected_slot = idx
			slot_clicked.emit(idx)
			queue_redraw()
		accept_event()


func _hit_test(pos: Vector2) -> int:
	for i in slot_count:
		if _slot_rect(i).has_point(pos):
			return i
	return -1


func _process(_delta: float) -> void:
	if selected_slot >= 0:
		queue_redraw()
