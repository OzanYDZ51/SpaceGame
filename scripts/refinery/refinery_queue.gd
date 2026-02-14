class_name RefineryQueue
extends RefCounted

# =============================================================================
# Refinery Queue — ordered job list per station. Max 10 jobs.
# Only the first non-collected job is "active" (running).
# =============================================================================

const MAX_JOBS: int = 10

var station_key: String = ""
var jobs: Array[RefineryJob] = []


func get_active_job() -> RefineryJob:
	for j in jobs:
		if not j.collected:
			return j
	return null


func get_completed_jobs() -> Array[RefineryJob]:
	var result: Array[RefineryJob] = []
	for j in jobs:
		if j.is_complete() and not j.collected:
			result.append(j)
	return result


func get_pending_jobs() -> Array[RefineryJob]:
	var result: Array[RefineryJob] = []
	for j in jobs:
		if j.started_at <= 0.0:
			result.append(j)
	return result


func can_add() -> bool:
	# Count non-collected jobs
	var active_count: int = 0
	for j in jobs:
		if not j.collected:
			active_count += 1
	return active_count < MAX_JOBS


func add_job(job: RefineryJob) -> bool:
	if not can_add():
		return false
	jobs.append(job)
	return true


func remove_collected() -> void:
	var i: int = jobs.size() - 1
	while i >= 0:
		if jobs[i].collected:
			jobs.remove_at(i)
		i -= 1


## Advances the queue: starts next job if current is complete, auto-chains.
func tick(storage: StationStorage) -> void:
	# Remove fully collected jobs
	remove_collected()

	# Process jobs in order
	for i in jobs.size():
		var job: RefineryJob = jobs[i]
		if job.collected:
			continue

		if job.started_at <= 0.0:
			# Not started yet — only start if it's the first non-collected
			if i == _first_uncollected_index():
				job.start()
			return

		if job.is_complete() and not job.collected:
			# Deliver output to storage
			var recipe := RefineryRegistry.get_recipe(job.recipe_id)
			if recipe:
				storage.add(recipe.output_id, recipe.output_qty * job.quantity)
			job.collected = true
			# Continue to start next job
			continue

		# Job is running but not yet complete — nothing more to do
		return


func _first_uncollected_index() -> int:
	for i in jobs.size():
		if not jobs[i].collected:
			return i
	return -1


func serialize() -> Array:
	var result: Array = []
	for j in jobs:
		if not j.collected:
			result.append(j.serialize())
	return result


func deserialize(data: Array) -> void:
	jobs.clear()
	for entry in data:
		if entry is Dictionary:
			jobs.append(RefineryJob.deserialize(entry))
