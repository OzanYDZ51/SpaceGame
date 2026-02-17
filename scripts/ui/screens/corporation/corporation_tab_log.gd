class_name ClanTabLog
extends UIComponent

# =============================================================================
# Clan Tab: Activity Log - Rich filtered timeline with bigger items
# =============================================================================

var _cm = null
var _filter_dropdown: UIDropdown = null
var _btn_24h: UIButton = null
var _btn_week: UIButton = null
var _btn_all: UIButton = null
var _log_list: UIScrollList = null

var _time_filter: int = 0
var _type_filter: int = -1
var _filtered_log: Array[ClanActivity] = []


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_filter_dropdown = UIDropdown.new()
	var opts: Array[String] = ["Tous les types"]
	for key in ClanActivity.EVENT_LABELS:
		opts.append(ClanActivity.EVENT_LABELS[key])
	_filter_dropdown.options.assign(opts)
	_filter_dropdown.option_selected.connect(_on_type_filter_changed)
	add_child(_filter_dropdown)

	_btn_24h = UIButton.new()
	_btn_24h.text = "24H"
	_btn_24h.pressed.connect(func(): _set_time_filter(0))
	add_child(_btn_24h)

	_btn_week = UIButton.new()
	_btn_week.text = "7 Jours"
	_btn_week.pressed.connect(func(): _set_time_filter(1))
	add_child(_btn_week)

	_btn_all = UIButton.new()
	_btn_all.text = "Tout"
	_btn_all.pressed.connect(func(): _set_time_filter(2))
	add_child(_btn_all)

	_log_list = UIScrollList.new()
	_log_list.row_height = 36.0
	_log_list.item_draw_callback = _draw_log_item
	add_child(_log_list)


func refresh(cm) -> void:
	_cm = cm
	_rebuild_list()


func _set_time_filter(val: int) -> void:
	_time_filter = val
	_rebuild_list()


func _on_type_filter_changed(index: int) -> void:
	if index == 0:
		_type_filter = -1
	else:
		var type_keys =ClanActivity.EVENT_LABELS.keys()
		if index - 1 < type_keys.size():
			_type_filter = type_keys[index - 1]
		else:
			_type_filter = -1
	_rebuild_list()


func _rebuild_list() -> void:
	if _cm == null:
		return

	var now =int(Time.get_unix_time_from_system())
	var cutoff: int = 0
	match _time_filter:
		0: cutoff = now - 86400
		1: cutoff = now - 86400 * 7
		2: cutoff = 0

	_filtered_log.clear()
	for entry in _cm.activity_log:
		if cutoff > 0 and entry.timestamp < cutoff:
			continue
		if _type_filter >= 0 and entry.event_type != _type_filter:
			continue
		_filtered_log.append(entry)

	_log_list.items.clear()
	for i in _filtered_log.size():
		_log_list.items.append(i)
	_log_list.selected_index = -1
	_log_list.queue_redraw()


func _draw_log_item(ctrl: Control, _index: int, rect: Rect2, item: Variant) -> void:
	var font: Font = UITheme.get_font()
	var log_idx: int = item as int
	if log_idx >= _filtered_log.size():
		return

	var entry: ClanActivity = _filtered_log[log_idx]
	var event_col: Color = ClanActivity.EVENT_COLORS.get(entry.event_type, UITheme.TEXT_DIM)
	var event_label: String = ClanActivity.EVENT_LABELS.get(entry.event_type, "?")

	var tx: float = rect.position.x + 12
	var cy: float = rect.position.y + rect.size.y * 0.5

	# ─── Timestamp ──────
	var time_str =_format_timestamp(entry.timestamp)
	ctrl.draw_string(font, Vector2(tx, cy + 5), time_str, HORIZONTAL_ALIGNMENT_LEFT, 74, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# ─── Badge (colored background + border + text) ──────
	var badge_x: float = tx + 82
	var badge_w: float = 84.0
	var badge_h: float = 22.0
	var badge_y: float = cy - badge_h * 0.5
	var badge_rect =Rect2(badge_x, badge_y, badge_w, badge_h)

	ctrl.draw_rect(badge_rect, Color(event_col.r, event_col.g, event_col.b, 0.12))
	ctrl.draw_rect(badge_rect, Color(event_col.r, event_col.g, event_col.b, 0.45), false, 1.0)
	# Left accent on badge
	ctrl.draw_rect(Rect2(badge_x, badge_y, 3, badge_h), Color(event_col.r, event_col.g, event_col.b, 0.7))
	ctrl.draw_string(font, Vector2(badge_x + 8, badge_y + badge_h - 5), event_label, HORIZONTAL_ALIGNMENT_CENTER, badge_w - 12, UITheme.FONT_SIZE_BODY, event_col)

	# ─── Details text ──────
	var detail_x: float = badge_x + badge_w + 14
	ctrl.draw_string(font, Vector2(detail_x, cy + 5), entry.details, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - detail_x - 10, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# ─── Bottom separator line ──────
	var sep_col =Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.25)
	ctrl.draw_line(Vector2(tx, rect.end.y - 1), Vector2(rect.end.x - 8, rect.end.y - 1), sep_col, 1.0)


func _format_timestamp(ts: int) -> String:
	var dt =Time.get_datetime_dict_from_unix_time(ts)
	var now =Time.get_datetime_dict_from_system()
	var day_diff: int = now.get("day", 0) - dt.get("day", 0)
	if day_diff == 0:
		return "%02d:%02d" % [dt.get("hour", 0), dt.get("minute", 0)]
	elif day_diff == 1:
		return "Hier %02d:%02d" % [dt.get("hour", 0), dt.get("minute", 0)]
	return "%02d/%02d" % [dt.get("day", 0), dt.get("month", 0)]


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0

	# Filter bar
	_filter_dropdown.position = Vector2(m, m)
	if _filter_dropdown._expanded:
		_filter_dropdown.size.x = 180
	else:
		_filter_dropdown.size = Vector2(180, 30)

	_btn_24h.position = Vector2(m + 200, m)
	_btn_24h.size = Vector2(60, 30)
	_btn_week.position = Vector2(m + 268, m)
	_btn_week.size = Vector2(80, 30)
	_btn_all.position = Vector2(m + 356, m)
	_btn_all.size = Vector2(60, 30)

	# Log list
	_log_list.position = Vector2(0, m + 44)
	_log_list.size = Vector2(size.x, size.y - m - 44)


func _draw() -> void:
	var m: float = 12.0

	# Filter bar background
	draw_rect(Rect2(0, 0, size.x, m + 40), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.02))
	draw_line(Vector2(0, m + 40), Vector2(size.x, m + 40), UITheme.BORDER, 1.0)

	# Filter label
	var font: Font = UITheme.get_font()
	draw_string(font, Vector2(size.x - 200, m + 20), "%d entrees" % _filtered_log.size(), HORIZONTAL_ALIGNMENT_RIGHT, 190, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
