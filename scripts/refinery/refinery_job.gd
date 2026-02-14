class_name RefineryJob
extends RefCounted

# =============================================================================
# Refinery Job — a single queued refining task with unix timestamp tracking.
# Timer progresses even offline (compare now vs complete_at on load).
# =============================================================================

var job_id: String = ""
var recipe_id: StringName = &""
var quantity: int = 1
var started_at: float = 0.0   # unix timestamp (0 = not started yet)
var complete_at: float = 0.0  # unix timestamp when done
var collected: bool = false    # true once output placed in storage


static func create(recipe: RefineryRecipe, qty: int) -> RefineryJob:
	var j := RefineryJob.new()
	j.job_id = "j_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	j.recipe_id = recipe.recipe_id
	j.quantity = qty
	return j


func get_total_duration() -> float:
	var recipe := RefineryRegistry.get_recipe(recipe_id)
	if recipe == null:
		return 0.0
	return recipe.duration * quantity


func get_progress() -> float:
	if started_at <= 0.0:
		return 0.0
	if collected:
		return 1.0
	var now: float = Time.get_unix_time_from_system()
	var total: float = complete_at - started_at
	if total <= 0.0:
		return 1.0
	return clampf((now - started_at) / total, 0.0, 1.0)


func is_complete() -> bool:
	if started_at <= 0.0:
		return false
	return Time.get_unix_time_from_system() >= complete_at


func start() -> void:
	started_at = Time.get_unix_time_from_system()
	complete_at = started_at + get_total_duration()


func serialize() -> Dictionary:
	return {
		"job_id": job_id,
		"recipe_id": str(recipe_id),
		"quantity": quantity,
		"started_at": started_at,
		"complete_at": complete_at,
		"collected": collected,
	}


static func deserialize(data: Dictionary) -> RefineryJob:
	var j := RefineryJob.new()
	j.job_id = data.get("job_id", "")
	j.recipe_id = StringName(str(data.get("recipe_id", "")))
	j.quantity = int(data.get("quantity", 1))
	j.started_at = float(data.get("started_at", 0.0))
	j.complete_at = float(data.get("complete_at", 0.0))
	j.collected = data.get("collected", false)
	return j
