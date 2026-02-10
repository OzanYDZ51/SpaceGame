class_name MapSearch
extends Control

# =============================================================================
# Map Search Bar - Entity name search overlay
# Pure custom-drawn, holographic theme. Toggle with '/' key.
# =============================================================================

signal entity_selected(id: String)

var _search_text: String = ""
var _results: Array = []  # Array of {id, name, type}
var _selected_index: int = 0
var _cursor_blink: float = 0.0

const MAX_RESULTS: int = 8
const BAR_WIDTH: float = 360.0
const BAR_HEIGHT: float = 28.0
const ROW_HEIGHT: float = 22.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_cursor_blink += delta


func open() -> void:
	_search_text = ""
	_results.clear()
	_selected_index = 0
	_cursor_blink = 0.0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_search_text = ""
	_results.clear()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
			return

		if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
			if _results.size() > 0 and _selected_index < _results.size():
				entity_selected.emit(_results[_selected_index]["id"])
				close()
			get_viewport().set_input_as_handled()
			return

		if event.physical_keycode == KEY_UP:
			_selected_index = maxi(_selected_index - 1, 0)
			queue_redraw()
			get_viewport().set_input_as_handled()
			return

		if event.physical_keycode == KEY_DOWN:
			_selected_index = mini(_selected_index + 1, _results.size() - 1)
			queue_redraw()
			get_viewport().set_input_as_handled()
			return

		if event.physical_keycode == KEY_BACKSPACE:
			if _search_text.length() > 0:
				_search_text = _search_text.left(_search_text.length() - 1)
				_update_results()
				queue_redraw()
			get_viewport().set_input_as_handled()
			return

		# Character input via unicode
		if event.unicode > 0:
			var ch: String = char(event.unicode)
			if ch.length() == 1 and ch != "/":
				_search_text += ch.to_lower()
				_update_results()
				queue_redraw()

		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.pressed:
		get_viewport().set_input_as_handled()


func _update_results() -> void:
	_results.clear()
	_selected_index = 0
	if _search_text.is_empty():
		return

	var entities: Dictionary = EntityRegistry.get_all()
	var query: String = _search_text.to_lower()
	for ent in entities.values():
		if ent["type"] == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue
		var name_lower: String = ent["name"].to_lower()
		if name_lower.contains(query):
			_results.append({
				"id": ent["id"],
				"name": ent["name"],
				"type": ent["type"],
			})
			if _results.size() >= MAX_RESULTS:
				break


func _draw() -> void:
	if not visible:
		return

	var font: Font = UITheme.get_font()

	# Position at top center
	var bx: float = (size.x - BAR_WIDTH) * 0.5
	var by: float = 70.0

	# Search bar background
	draw_rect(Rect2(bx, by, BAR_WIDTH, BAR_HEIGHT), MapColors.BG_PANEL)
	draw_rect(Rect2(bx, by, BAR_WIDTH, BAR_HEIGHT), MapColors.PANEL_BORDER, false, 1.0)

	# Search icon / label
	draw_string(font, Vector2(bx + 8, by + 19), "/", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.TEXT_DIM)

	# Search text + blinking cursor
	var display_text: String = _search_text
	var cursor_visible: bool = fmod(_cursor_blink, 1.0) < 0.6
	if cursor_visible:
		display_text += "_"
	draw_string(font, Vector2(bx + 22, by + 19), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.TEXT)

	# Results dropdown
	if _results.size() > 0:
		var dropdown_h: float = _results.size() * ROW_HEIGHT + 4.0
		var dy: float = by + BAR_HEIGHT
		draw_rect(Rect2(bx, dy, BAR_WIDTH, dropdown_h), MapColors.BG_PANEL)
		draw_rect(Rect2(bx, dy, BAR_WIDTH, dropdown_h), MapColors.PANEL_BORDER, false, 1.0)

		for i in _results.size():
			var ry: float = dy + 2.0 + i * ROW_HEIGHT
			# Highlight selected
			if i == _selected_index:
				draw_rect(Rect2(bx + 2, ry, BAR_WIDTH - 4, ROW_HEIGHT), MapColors.PRIMARY_FAINT)

			var r: Dictionary = _results[i]
			var type_prefix: String = _type_prefix(r["type"])
			var label: String = type_prefix + " " + r["name"]
			var col: Color = MapColors.TEXT if i == _selected_index else MapColors.TEXT_DIM
			draw_string(font, Vector2(bx + 10, ry + 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	elif not _search_text.is_empty():
		# No results message
		var dy: float = by + BAR_HEIGHT
		draw_rect(Rect2(bx, dy, BAR_WIDTH, ROW_HEIGHT + 4), MapColors.BG_PANEL)
		draw_string(font, Vector2(bx + 10, dy + 17), "Aucun résultat", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MapColors.TEXT_DIM)


func _type_prefix(type: int) -> String:
	match type:
		EntityRegistrySystem.EntityType.STAR: return "[*]"
		EntityRegistrySystem.EntityType.PLANET: return "[P]"
		EntityRegistrySystem.EntityType.STATION: return "[S]"
		EntityRegistrySystem.EntityType.SHIP_PLAYER: return "[>]"
		EntityRegistrySystem.EntityType.SHIP_NPC: return "[^]"
	return "[?]"
