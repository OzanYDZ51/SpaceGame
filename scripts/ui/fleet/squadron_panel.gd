class_name SquadronPanel
extends Control

# =============================================================================
# Squadron Panel — Popup for squadron management (create/manage/assign)
# Currently a placeholder — squadron actions are handled via context menu.
# This panel can be expanded for a dedicated squadron management UI.
# =============================================================================

signal squadron_action(action: StringName, data: Dictionary)

var _visible_mode: StringName = &""  # "create", "manage", "assign_role", "set_formation"


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
