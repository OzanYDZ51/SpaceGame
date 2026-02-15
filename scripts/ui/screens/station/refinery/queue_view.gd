class_name QueueView
extends Control

# =============================================================================
# Queue View — shows active job progress, pending jobs, completed jobs.
# =============================================================================

var _manager = null
var _station_key: String = ""

var _job_list: UIScrollList = null


func _ready() -> void:
	clip_contents = true

	_job_list = UIScrollList.new()
	_job_list.row_height = 50.0
	_job_list.item_draw_callback = _draw_job_row
	add_child(_job_list)


func setup(mgr, station_key: String) -> void:
	_manager = mgr
	_station_key = station_key


func refresh() -> void:
	_rebuild_list()
	_layout()
	queue_redraw()


func _rebuild_list() -> void:
	if _manager == null:
		_job_list.items = []
		return
	var queue =_manager.get_queue(_station_key)
	# Show all non-collected jobs
	var visible_jobs: Array = []
	for j in queue.jobs:
		if not j.collected:
			visible_jobs.append(j)
	_job_list.items = visible_jobs
	_job_list.queue_redraw()


func _layout() -> void:
	var s: Vector2 = size
	var header_h: float = 36.0
	_job_list.position = Vector2(0, header_h)
	_job_list.size = Vector2(s.x, s.y - header_h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _process(_delta: float) -> void:
	if visible:
		_rebuild_list()
		queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var font: Font = UITheme.get_font()

	# Header
	draw_rect(Rect2(0, 0, 3, 14), UITheme.PRIMARY)
	draw_string(font, Vector2(10, 16), "FILE DE RAFFINAGE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)

	var queue: RefineryQueue = null
	if _manager:
		queue = _manager.get_queue(_station_key)

	var job_count: int = 0
	if queue:
		for j in queue.jobs:
			if not j.collected:
				job_count += 1
	var count_text: String = "%d / %d jobs" % [job_count, RefineryQueue.MAX_JOBS]
	draw_string(font, Vector2(s.x - 120, 16), count_text,
		HORIZONTAL_ALIGNMENT_RIGHT, 110, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	draw_line(Vector2(0, 28), Vector2(s.x, 28), UITheme.BORDER, 1.0)

	if job_count == 0:
		draw_string(font, Vector2(12, 70), "Aucun job en cours.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _draw_job_row(ctrl: Control, _idx: int, rect: Rect2, item: Variant) -> void:
	var job =item as RefineryJob
	if job == null:
		return
	var font: Font = UITheme.get_font()
	var x: float = rect.position.x + 8
	var y: float = rect.position.y
	var w: float = rect.size.x - 16
	var h: float = rect.size.y

	var recipe =RefineryRegistry.get_recipe(job.recipe_id)
	var rname: String = recipe.display_name if recipe else str(job.recipe_id)
	var col: Color = recipe.icon_color if recipe else UITheme.TEXT

	# Status
	var status_text: String = ""
	var status_col: Color = UITheme.TEXT_DIM
	var progress: float = job.get_progress()

	if job.is_complete():
		status_text = "TERMINE"
		status_col = UITheme.ACCENT
	elif job.started_at > 0.0:
		var remaining: float = maxf(0.0, job.complete_at - Time.get_unix_time_from_system())
		status_text = "EN COURS — %s" % RecipeBrowserView._format_time(remaining)
		status_col = UITheme.PRIMARY
	else:
		status_text = "EN ATTENTE"
		status_col = UITheme.TEXT_DIM

	# Name + qty
	var name_text: String = "%s x%d" % [rname, job.quantity]
	ctrl.draw_string(font, Vector2(x, y + 16), name_text,
		HORIZONTAL_ALIGNMENT_LEFT, int(w * 0.6), UITheme.FONT_SIZE_SMALL, col)

	# Status text
	ctrl.draw_string(font, Vector2(x + w * 0.6, y + 16), status_text,
		HORIZONTAL_ALIGNMENT_LEFT, int(w * 0.4), UITheme.FONT_SIZE_TINY, status_col)

	# Progress bar (only for started jobs)
	if job.started_at > 0.0:
		var bar_x: float = x
		var bar_y: float = y + 24
		var bar_w: float = w
		var bar_h: float = 8.0

		# Background
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.08, 0.05, 0.5))

		# Fill
		var fill_w: float = bar_w * progress
		var fill_col: Color = UITheme.ACCENT if job.is_complete() else UITheme.PRIMARY
		if fill_w > 0:
			ctrl.draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), fill_col)

		# Border
		ctrl.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), UITheme.BORDER, false, 1.0)

		# Percentage
		var pct_text: String = "%d%%" % int(progress * 100)
		ctrl.draw_string(font, Vector2(bar_x + bar_w + 4, bar_y + 8), pct_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# Bottom separator
	ctrl.draw_line(Vector2(x, y + h - 1), Vector2(x + w, y + h - 1),
		Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.2), 1.0)
