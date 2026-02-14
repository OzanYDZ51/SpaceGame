class_name RefineryRecipe
extends RefCounted

# =============================================================================
# Refinery Recipe — defines inputs, output, duration, tier for a refining job.
# =============================================================================

var recipe_id: StringName = &""
var display_name: String = ""
var tier: int = 0
var inputs: Array[Dictionary] = []  # [{id: StringName, qty: int}, ...]
var output_id: StringName = &""
var output_qty: int = 1
var duration: float = 0.0  # seconds
var value: int = 0  # CR value of output
var icon_color: Color = Color.WHITE
