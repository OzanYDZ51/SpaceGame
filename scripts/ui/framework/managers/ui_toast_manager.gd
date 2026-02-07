class_name UIToastManager
extends Control

# =============================================================================
# UI Toast Manager - Stack of toast notifications (top-right)
# Add as child of UI CanvasLayer. Call show_toast() to display.
# =============================================================================

var _toasts: Array[UIToast] = []

const TOAST_MARGIN := 16.0
const TOAST_SPACING := 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_offsets_preset(Control.PRESET_FULL_RECT)


## Show a new toast notification.
func show_toast(message: String, type: UIToast.ToastType = UIToast.ToastType.INFO, lifetime: float = 4.0) -> void:
	var toast := UIToast.new()
	toast.message = message
	toast.toast_type = type
	toast.lifetime = lifetime
	toast.tree_exiting.connect(_on_toast_removed.bind(toast))

	_toasts.append(toast)
	add_child(toast)

	_reposition_toasts()


func _on_toast_removed(toast: UIToast) -> void:
	_toasts.erase(toast)
	# Defer reposition to next frame (toast is being freed)
	call_deferred("_reposition_toasts")


func _reposition_toasts() -> void:
	var vp_w: float = get_viewport_rect().size.x
	var y: float = TOAST_MARGIN

	for toast in _toasts:
		if is_instance_valid(toast):
			toast.position = Vector2(vp_w - UIToast.TOAST_WIDTH - TOAST_MARGIN, y)
			y += UIToast.TOAST_HEIGHT + TOAST_SPACING
