class_name MapFleetPanel
extends Control

# =============================================================================
# Map Fleet Panel - Left-side fleet overview on stellar/galaxy map
# Groups ships by system > station, scrollable, clickable
# Supports multi-select: click = single, Ctrl+click = add/remove
# Left click = select ships for move, Right click on deployed = recall
# Full custom _draw(), no child Controls
# =============================================================================

signal ship_selected(fleet_index: int, system_id: int)
signal ship_move_selected(fleet_index: int)
signal selection_changed(fleet_indices: Array)
signal squadron_header_clicked(squadron_id: int)
signal squadron_rename_requested(squadron_id: int, screen_pos: Vector2)
signal ship_rename_requested(fleet_index: int, screen_pos: Vector2)
signal ship_context_menu_requested(fleet_index: int, screen_pos: Vector2)
signal squadron_disband_requested(squadron_id: int)
signal squadron_remove_member_requested(fleet_index: int)
signal squadron_formation_requested(squadron_id: int, formation_type: StringName)
signal squadron_add_ship_requested(fleet_index: int, squadron_id: int)

const PANEL_W: float = 240.0
const HEADER_H: float = 32.0
const GROUP_H: float = 22.0
const SHIP_H: float = 20.0
const MARGIN: float = 10.0
const SCROLL_SPEED: float = 28.0
const CORNER_LEN: float = 8.0

var _fleet = null
var _galaxy = null
var _active_index: int = -1
var _selected_fleet_indices: Array[int] = []

# Grouped data rebuilt on fleet_changed
var _groups: Array[Dictionary] = []

var _scroll_offset: float = 0.0
var _max_scroll: float = 0.0

# Hover tracking for cargo tooltip
var _hover_fleet_index: int = -1

# Squadron section
var _squadron_mgr = null
var _sq_disband_btn_rects: Array[Dictionary] = []  # [{rect, squadron_id}]
var _sq_formation_btn_rects: Array[Dictionary] = []  # [{rect, formation_id, squadron_id}]
var _sq_remove_btn_rects: Array[Dictionary] = []  # [{rect, fleet_index}]
var _sq_add_btn_rects: Array[Dictionary] = []  # [{rect, fleet_index}]
var _squadron_section_height: float = 0.0

# Double-click header tracking
var _last_header_click_sq: int = -1
var _last_header_click_time: float = 0.0
var _last_ship_click_index: int = -1
var _last_ship_click_time: float = 0.0
var _last_single_select_index: int = -1  # Anchor for Shift+click range select


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fleet(fleet) -> void:
	if _fleet:
		if _fleet.fleet_changed.is_connected(_rebuild):
			_fleet.fleet_changed.disconnect(_rebuild)
		if _fleet.active_ship_changed.is_connected(_on_active_changed):
			_fleet.active_ship_changed.disconnect(_on_active_changed)
	_fleet = fleet
	if _fleet:
		_fleet.fleet_changed.connect(_rebuild)
		_fleet.active_ship_changed.connect(_on_active_changed)
		_active_index = _fleet.active_index
	_rebuild()


func _on_active_changed(_ship) -> void:
	_rebuild()


func set_galaxy(galaxy) -> void:
	_galaxy = galaxy
	_rebuild()


func set_squadron_manager(mgr) -> void:
	_squadron_mgr = mgr


func get_selected_fleet_indices() -> Array[int]:
	return _selected_fleet_indices


func clear_selection() -> void:
	_selected_fleet_indices.clear()
	queue_redraw()


func set_selected_fleet_indices(indices: Array[int]) -> void:
	_selected_fleet_indices = indices.duplicate()
	queue_redraw()


func _rebuild() -> void:
	_groups.clear()
	if _fleet == null:
		return

	_active_index = _fleet.active_index

	# Build a mapping: system_id -> station_id -> Array of {fleet_index, ship}
	var sys_map: Dictionary = {}  # int -> Dictionary
	for i in _fleet.ships.size():
		var fs = _fleet.ships[i]
		# Skip destroyed and empty ships
		if fs.ship_id == &"" or fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
			continue
		var sys_id: int = fs.docked_system_id
		if sys_id < 0:
			sys_id = -1  # unknown
		if not sys_map.has(sys_id):
			sys_map[sys_id] = {"docked": {}, "deployed": []}
		if fs.deployment_state == FleetShip.DeploymentState.DOCKED or i == _active_index:
			var st_id: String = fs.docked_station_id if fs.docked_station_id != "" else "_none"
			if not sys_map[sys_id]["docked"].has(st_id):
				sys_map[sys_id]["docked"][st_id] = []
			sys_map[sys_id]["docked"][st_id].append({"fleet_index": i, "ship": fs})
		elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
			sys_map[sys_id]["deployed"].append({"fleet_index": i, "ship": fs})

	# Move mining-docked DEPLOYED ships to station docked groups
	for sys_id in sys_map:
		var sdata: Dictionary = sys_map[sys_id]
		var remaining: Array = []
		for entry in sdata["deployed"]:
			var fs = entry["ship"]
			var npc_id_str: String = String(fs.deployed_npc_id) if fs.deployed_npc_id != &"" else ""
			var ent: Dictionary = EntityRegistry.get_entity(npc_id_str) if npc_id_str != "" else {}
			if ent.get("extra", {}).get("mining_docked", false):
				var dock_st: String = ent.get("extra", {}).get("mining_docked_station", "_none")
				if dock_st == "":
					dock_st = "_none"
				if not sdata["docked"].has(dock_st):
					sdata["docked"][dock_st] = []
				sdata["docked"][dock_st].append(entry)
			else:
				remaining.append(entry)
		sdata["deployed"] = remaining

	# Convert to sorted groups
	var sys_ids: Array = sys_map.keys()
	sys_ids.sort()
	for sys_id in sys_ids:
		var data: Dictionary = sys_map[sys_id]
		var sys_name: String = Locale.t("map.fleet.unknown_system")
		if _galaxy and sys_id >= 0:
			sys_name = _galaxy.get_system_name(sys_id)

		var stations: Array[Dictionary] = []
		var st_ids: Array = data["docked"].keys()
		st_ids.sort()
		for st_id in st_ids:
			var ships_arr: Array = data["docked"][st_id]
			ships_arr.sort_custom(_compare_ships_by_name)
			var st_name: String = st_id if st_id != "_none" else "En vol"
			# Try to get station name from EntityRegistry
			if st_id != "_none":
				var ent =EntityRegistry.get_entity(st_id)
				if not ent.is_empty():
					st_name = ent.get("name", st_id)
			stations.append({"station_id": st_id, "name": st_name, "ships": ships_arr})

		data["deployed"].sort_custom(_compare_ships_by_name)
		_groups.append({
			"system_id": sys_id,
			"system_name": sys_name,
			"collapsed": false,
			"stations": stations,
			"deployed": data["deployed"],
		})


func get_panel_rect() -> Rect2:
	return Rect2(0, 0, PANEL_W, size.y)


func _check_squadron_section_click(pos: Vector2) -> bool:
	# Disband buttons
	for entry in _sq_disband_btn_rects:
		if entry["rect"].has_point(pos):
			squadron_disband_requested.emit(entry["squadron_id"])
			return true
	# Formation buttons
	for entry in _sq_formation_btn_rects:
		if entry["rect"].has_point(pos):
			squadron_formation_requested.emit(entry["squadron_id"], entry["formation_id"])
			return true
	# Remove member buttons
	for entry in _sq_remove_btn_rects:
		if entry["rect"].has_point(pos):
			squadron_remove_member_requested.emit(entry["fleet_index"])
			return true
	# Add ship buttons
	for entry in _sq_add_btn_rects:
		if entry["rect"].has_point(pos):
			squadron_add_ship_requested.emit(entry["fleet_index"], entry["squadron_id"])
			return true
	return false


func _get_player_squadron():
	if _fleet == null:
		return null
	return _fleet.get_ship_squadron(-1)


func handle_click(pos: Vector2, ctrl_pressed: bool = false, shift_pressed: bool = false) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		return false
	if _fleet == null or _fleet.ships.is_empty():
		return false

	# Check squadron section click first
	if _check_squadron_section_click(pos):
		queue_redraw()
		return true

	# Check squadron header click first
	var hit_sq_id: int = _get_squadron_header_at(pos)
	if hit_sq_id >= 0:
		var sq = _fleet.get_squadron(hit_sq_id)
		if sq:
			# Double-click detection for rename
			var now: float = Time.get_ticks_msec() / 1000.0
			if hit_sq_id == _last_header_click_sq and (now - _last_header_click_time) < 0.4:
				squadron_rename_requested.emit(hit_sq_id, pos)
				_last_header_click_sq = -1
			else:
				_last_header_click_sq = hit_sq_id
				_last_header_click_time = now
				# Select all ships in the squadron
				var all_indices: Array[int] = sq.get_all_indices()
				_selected_fleet_indices = all_indices
				if not all_indices.is_empty():
					_last_single_select_index = all_indices[-1]
				selection_changed.emit(_selected_fleet_indices.duplicate())
				squadron_header_clicked.emit(hit_sq_id)
			queue_redraw()
			return true

	var hit_index: int = _get_fleet_index_at(pos)
	if hit_index >= 0:
		# Double-click = rename ship
		var now: float = Time.get_ticks_msec() / 1000.0
		if hit_index == _last_ship_click_index and (now - _last_ship_click_time) < 0.4:
			ship_rename_requested.emit(hit_index, pos)
			_last_ship_click_index = -1
		else:
			_last_ship_click_index = hit_index
			_last_ship_click_time = now
		if shift_pressed and _last_single_select_index >= 0:
			# Shift+click = range select from anchor to clicked item
			var visible_order: Array[int] = _get_visible_fleet_indices()
			var anchor_pos: int = visible_order.find(_last_single_select_index)
			var click_pos: int = visible_order.find(hit_index)
			if anchor_pos >= 0 and click_pos >= 0:
				var from_idx: int = mini(anchor_pos, click_pos)
				var to_idx: int = maxi(anchor_pos, click_pos)
				if ctrl_pressed:
					# Shift+Ctrl = add range to existing selection
					for i in range(from_idx, to_idx + 1):
						if not _selected_fleet_indices.has(visible_order[i]):
							_selected_fleet_indices.append(visible_order[i])
				else:
					# Shift only = replace selection with range
					_selected_fleet_indices.clear()
					for i in range(from_idx, to_idx + 1):
						_selected_fleet_indices.append(visible_order[i])
			# Don't update anchor on shift-click (standard behavior)
		elif ctrl_pressed:
			# Ctrl+click = toggle in multi-select
			var idx: int = _selected_fleet_indices.find(hit_index)
			if idx >= 0:
				_selected_fleet_indices.remove_at(idx)
			else:
				_selected_fleet_indices.append(hit_index)
			_last_single_select_index = hit_index
		else:
			# Normal click = toggle single selection
			if _selected_fleet_indices.size() == 1 and _selected_fleet_indices[0] == hit_index:
				_selected_fleet_indices.clear()
			else:
				_selected_fleet_indices = [hit_index]
			_last_single_select_index = hit_index
		selection_changed.emit(_selected_fleet_indices.duplicate())
		if _selected_fleet_indices.size() == 1:
			var fi: int = _selected_fleet_indices[0]
			ship_move_selected.emit(fi)
			if _fleet and fi < _fleet.ships.size():
				ship_selected.emit(fi, _fleet.ships[fi].docked_system_id)
		queue_redraw()
		return true

	# Check group header collapse
	var y: float = HEADER_H + MARGIN - _scroll_offset + _squadron_section_height
	for g_idx in _groups.size():
		var group: Dictionary = _groups[g_idx]
		if _hit_row(pos.y, y, GROUP_H):
			group["collapsed"] = not group["collapsed"]
			queue_redraw()
			return true
		y += GROUP_H
		if group["collapsed"]:
			continue
		for st in group["stations"]:
			y += 2
			y += SHIP_H  # station sub-header
			for _entry in st["ships"]:
				y += SHIP_H
		for _entry in group["deployed"]:
			y += SHIP_H
		y += 6

	return true  # consumed (clicked in panel area)


func handle_right_click(pos: Vector2) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		return false
	if _fleet == null or _fleet.ships.is_empty():
		return false

	var hit_index: int = _get_fleet_index_at(pos)
	if hit_index >= 0:
		ship_context_menu_requested.emit(hit_index, pos)
		return true
	return false


func handle_scroll(pos: Vector2, dir: int) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		return false
	if _fleet == null or _fleet.ships.is_empty():
		return false
	_scroll_offset = clampf(_scroll_offset - dir * SCROLL_SPEED, 0.0, _max_scroll)
	queue_redraw()
	return true


func handle_mouse_move(pos: Vector2) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		if _hover_fleet_index >= 0:
			_hover_fleet_index = -1
			queue_redraw()
		return false
	if _fleet == null or _fleet.ships.is_empty():
		if _hover_fleet_index >= 0:
			_hover_fleet_index = -1
			queue_redraw()
		return false
	var new_hover: int = _get_fleet_index_at(pos)
	if new_hover != _hover_fleet_index:
		_hover_fleet_index = new_hover
		queue_redraw()
	return _hover_fleet_index >= 0


func _get_row_y_for_index(fleet_index: int) -> float:
	var y: float = HEADER_H + MARGIN - _scroll_offset + _squadron_section_height
	for group in _groups:
		y += GROUP_H
		if group["collapsed"]:
			continue
		for st in group["stations"]:
			y += 2
			y += SHIP_H  # station sub-header
			for entry in st["ships"]:
				if entry["fleet_index"] == fleet_index:
					return y
				y += SHIP_H
		for entry in group["deployed"]:
			if entry["fleet_index"] == fleet_index:
				return y
			y += SHIP_H
		y += 6
	return -1.0


func _get_squadron_header_at(_pos: Vector2) -> int:
	# Squadron headers only exist in the top squadron section (handled by
	# _check_squadron_section_click). No squadron headers in the group view.
	return -1


func _get_fleet_index_at(pos: Vector2) -> int:
	var y: float = HEADER_H + MARGIN - _scroll_offset + _squadron_section_height
	for group in _groups:
		y += GROUP_H  # system header
		if group["collapsed"]:
			continue
		for st in group["stations"]:
			y += 2
			y += SHIP_H  # station sub-header
			for entry in st["ships"]:
				if _hit_row(pos.y, y, SHIP_H):
					return entry["fleet_index"]
				y += SHIP_H
		for entry in group["deployed"]:
			if _hit_row(pos.y, y, SHIP_H):
				return entry["fleet_index"]
			y += SHIP_H
		y += 6
	return -1


func _get_system_id_for_fleet_index(fleet_index: int) -> int:
	for group in _groups:
		for st in group["stations"]:
			for entry in st["ships"]:
				if entry["fleet_index"] == fleet_index:
					return group["system_id"]
		for entry in group["deployed"]:
			if entry["fleet_index"] == fleet_index:
				return group["system_id"]
	return -1


## Returns all fleet indices in the order they appear visually in the panel.
func _get_visible_fleet_indices() -> Array[int]:
	var result: Array[int] = []
	for group in _groups:
		if group["collapsed"]:
			continue
		for st in group["stations"]:
			for entry in st["ships"]:
				result.append(entry["fleet_index"])
		for entry in group["deployed"]:
			result.append(entry["fleet_index"])
	return result


static func _compare_ships_by_name(a: Dictionary, b: Dictionary) -> bool:
	var na: String = a["ship"].custom_name if a["ship"].custom_name != "" else String(a["ship"].ship_id)
	var nb: String = b["ship"].custom_name if b["ship"].custom_name != "" else String(b["ship"].ship_id)
	return na.naturalcasecmp_to(nb) < 0


func _hit_row(mouse_y: float, row_y: float, row_h: float) -> bool:
	return mouse_y >= row_y and mouse_y < row_y + row_h


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if _fleet == null or _fleet.ships.is_empty():
		return

	var font: Font = UITheme.get_font()
	var rect =get_panel_rect()

	# Background
	draw_rect(rect, MapColors.FLEET_PANEL_BG)
	draw_rect(rect, MapColors.PANEL_BORDER, false, 1.0)

	# Corner accents
	var px: float = rect.position.x
	var py: float = rect.position.y
	var pw: float = rect.size.x
	var ph: float = rect.size.y
	var cc =MapColors.CORNER
	draw_line(Vector2(px, py), Vector2(px + CORNER_LEN, py), cc, 1.5)
	draw_line(Vector2(px, py), Vector2(px, py + CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px + pw, py), Vector2(px + pw - CORNER_LEN, py), cc, 1.5)
	draw_line(Vector2(px + pw, py), Vector2(px + pw, py + CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px, py + ph), Vector2(px + CORNER_LEN, py + ph), cc, 1.5)
	draw_line(Vector2(px, py + ph), Vector2(px, py + ph - CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px + pw, py + ph), Vector2(px + pw - CORNER_LEN, py + ph), cc, 1.5)
	draw_line(Vector2(px + pw, py + ph), Vector2(px + pw, py + ph - CORNER_LEN), cc, 1.5)

	# Header
	var ship_count: int = _fleet.ships.size()
	var header_text = Locale.t("map.fleet.header") % ship_count
	draw_string(font, Vector2(MARGIN, HEADER_H - 8), header_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_HEADER, MapColors.TEXT_HEADER)
	draw_line(Vector2(MARGIN, HEADER_H), Vector2(PANEL_W - MARGIN, HEADER_H), MapColors.PANEL_BORDER, 1.0)

	# Clip region
	var clip =Rect2(0, HEADER_H + 2, PANEL_W, size.y - HEADER_H - 2)

	# Squadron section (drawn before groups, affects scroll content)
	var sq_y: float = HEADER_H + MARGIN - _scroll_offset
	sq_y = _draw_squadron_section(font, sq_y, clip)
	_squadron_section_height = sq_y - (HEADER_H + MARGIN - _scroll_offset)

	var y: float = sq_y
	for group in _groups:
		y = _draw_group(font, y, group, clip)

	_max_scroll = maxf(y + _scroll_offset - size.y + 20, 0.0)

	# Selection hint
	var sel_count: int = _selected_fleet_indices.size()
	if sel_count > 0:
		var hint_text: String
		if sel_count == 1:
			hint_text = Locale.t("map.fleet.hint_autopilot") if _selected_fleet_indices[0] == _active_index else Locale.t("map.fleet.hint_move")
		else:
			hint_text = Locale.t("map.fleet.hint_move_n") % sel_count
		var hint_y: float = size.y - 16.0
		if hint_y > HEADER_H + 20:
			draw_rect(Rect2(0, hint_y - 14, PANEL_W, 20), Color(0.0, 0.05, 0.1, 0.8))
			var pulse: float = sin(Time.get_ticks_msec() / 500.0) * 0.2 + 0.8
			draw_string(font, Vector2(MARGIN, hint_y), hint_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_TINY, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, pulse))

	# Scanline
	var scan_y: float = fmod(Time.get_ticks_msec() / 40.0, size.y)
	if scan_y > HEADER_H:
		draw_line(Vector2(0, scan_y), Vector2(PANEL_W, scan_y), MapColors.SCANLINE, 1.0)

	# Cargo tooltip on hover
	if _hover_fleet_index >= 0 and _hover_fleet_index < _fleet.ships.size():
		_draw_cargo_tooltip(font)


func _draw_cargo_tooltip(font: Font) -> void:
	var fs = _fleet.ships[_hover_fleet_index]
	var row_y: float = _get_row_y_for_index(_hover_fleet_index)
	if row_y < 0.0:
		return

	const TT_W: float = 200.0
	const TT_PAD: float = 8.0
	const LINE_H: float = 16.0
	const SWATCH_SIZE: float = 8.0
	const BAR_H: float = 4.0

	# --- Gather data ---
	var ship_name: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
	var sdata =ShipRegistry.get_ship_data(fs.ship_id)
	var class_text: String = String(sdata.ship_class) if sdata else ""

	var cargo_used: int = fs.cargo.get_total_count() if fs.cargo else 0
	var cargo_max: int = fs.cargo.capacity if fs.cargo else (sdata.cargo_capacity if sdata else 50)
	var res_total: int = 0
	for res_id in fs.ship_resources:
		res_total += fs.ship_resources[res_id]
	var total_stored: int = cargo_used + res_total
	var fill_ratio: float = clampf(float(total_stored) / float(maxi(cargo_max, 1)), 0.0, 1.0)

	# --- Build content lines (after header block) ---
	var content_lines: Array[Dictionary] = []

	# Resources section
	var has_resources: bool = false
	for res_id in PlayerEconomy.RESOURCE_DEFS:
		var qty: int = fs.ship_resources.get(res_id, 0)
		if qty > 0:
			if not has_resources:
				content_lines.append({"text": Locale.t("map.fleet.ores_count") % res_total, "color": MapColors.TEXT_DIM, "swatch": Color()})
				has_resources = true
			var def: Dictionary = PlayerEconomy.RESOURCE_DEFS[res_id]
			content_lines.append({"text": "  %s  %d" % [def["name"], qty], "color": MapColors.LABEL_VALUE, "swatch": def["color"]})

	# Cargo section
	var has_cargo: bool = false
	if fs.cargo:
		for item in fs.cargo.get_all():
			var qty: int = item.get("quantity", 0)
			if qty > 0:
				if not has_cargo:
					content_lines.append({"text": Locale.t("map.fleet.cargo_items") % cargo_used, "color": MapColors.TEXT_DIM, "swatch": Color()})
					has_cargo = true
				content_lines.append({"text": "  %s  x%d" % [item.get("name", "?"), qty], "color": MapColors.LABEL_VALUE, "swatch": Color()})

	# --- Calculate tooltip height ---
	# name_line + sep(6) + capacity_line + bar(BAR_H+4) + content
	var tt_h: float = TT_PAD + LINE_H + 6 + LINE_H + BAR_H + 4 + content_lines.size() * LINE_H + TT_PAD
	if content_lines.is_empty():
		tt_h += 2

	# Position tooltip
	var tt_x: float = PANEL_W + 8.0
	var tt_y: float = row_y
	if tt_y + tt_h > size.y - 10:
		tt_y = size.y - tt_h - 10
	if tt_y < HEADER_H + 4:
		tt_y = HEADER_H + 4

	# --- Draw background ---
	var bg_rect =Rect2(tt_x, tt_y, TT_W, tt_h)
	draw_rect(bg_rect, MapColors.BG_PANEL)
	draw_rect(bg_rect, MapColors.PANEL_BORDER, false, 1.0)

	# Corner accents
	var cl: float = 6.0
	draw_line(Vector2(tt_x, tt_y), Vector2(tt_x + cl, tt_y), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x, tt_y), Vector2(tt_x, tt_y + cl), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x + TT_W, tt_y), Vector2(tt_x + TT_W - cl, tt_y), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x + TT_W, tt_y), Vector2(tt_x + TT_W, tt_y + cl), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x, tt_y + tt_h), Vector2(tt_x + cl, tt_y + tt_h), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x, tt_y + tt_h), Vector2(tt_x, tt_y + tt_h - cl), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x + TT_W, tt_y + tt_h), Vector2(tt_x + TT_W - cl, tt_y + tt_h), MapColors.CORNER, 1.5)
	draw_line(Vector2(tt_x + TT_W, tt_y + tt_h), Vector2(tt_x + TT_W, tt_y + tt_h - cl), MapColors.CORNER, 1.5)

	# --- Draw content with cursor ---
	var tx: float = tt_x + TT_PAD
	var inner_w: float = TT_W - TT_PAD * 2
	var cy: float = tt_y + TT_PAD

	# Ship name + class on same line
	draw_string(font, Vector2(tx, cy + LINE_H - 3), ship_name, HORIZONTAL_ALIGNMENT_LEFT, inner_w - 50, UITheme.FONT_SIZE_BODY, MapColors.TEXT)
	if class_text != "":
		draw_string(font, Vector2(tt_x + TT_W - TT_PAD, cy + LINE_H - 3), class_text, HORIZONTAL_ALIGNMENT_RIGHT, 80, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)
	cy += LINE_H

	# Separator
	cy += 2
	draw_line(Vector2(tx, cy), Vector2(tx + inner_w, cy), Color(MapColors.PANEL_BORDER.r, MapColors.PANEL_BORDER.g, MapColors.PANEL_BORDER.b, 0.4), 1.0)
	cy += 4

	# Capacity text: SOUTE  12 / 50
	var cap_text = Locale.t("map.fleet.cargo_capacity") % [total_stored, cargo_max]
	var cap_col: Color = MapColors.LABEL_VALUE if fill_ratio < 0.85 else UITheme.WARNING
	draw_string(font, Vector2(tx, cy + LINE_H - 3), cap_text, HORIZONTAL_ALIGNMENT_LEFT, inner_w, UITheme.FONT_SIZE_SMALL, cap_col)
	cy += LINE_H

	# Fill bar
	draw_rect(Rect2(tx, cy, inner_w, BAR_H), Color(0.1, 0.2, 0.3, 0.4))
	if fill_ratio > 0.01:
		var fill_col: Color
		if fill_ratio < 0.6:
			fill_col = Color(0.15, 0.65, 0.85, 0.7)
		elif fill_ratio < 0.85:
			fill_col = Color(0.85, 0.7, 0.15, 0.7)
		else:
			fill_col = Color(0.95, 0.35, 0.15, 0.8)
		draw_rect(Rect2(tx, cy, inner_w * fill_ratio, BAR_H), fill_col)
		draw_line(Vector2(tx, cy), Vector2(tx + inner_w * fill_ratio, cy), Color(fill_col.r, fill_col.g, fill_col.b, 0.9), 1.0)
	cy += BAR_H + 4

	# Content lines (resources + cargo items)
	for line_data in content_lines:
		var text: String = line_data["text"]
		var col: Color = line_data["color"]
		var swatch: Color = line_data["swatch"]
		var lx: float = tx
		if swatch.a > 0.01:
			draw_rect(Rect2(lx, cy + LINE_H - 3 - SWATCH_SIZE + 1, SWATCH_SIZE, SWATCH_SIZE), swatch)
			lx += SWATCH_SIZE + 4.0
		draw_string(font, Vector2(lx, cy + LINE_H - 3), text, HORIZONTAL_ALIGNMENT_LEFT, inner_w - 12, UITheme.FONT_SIZE_SMALL, col)
		cy += LINE_H


func _draw_squadron_section(font: Font, y: float, clip: Rect2) -> float:
	if _fleet == null:
		return y
	# Clear hit rects
	_sq_disband_btn_rects.clear()
	_sq_formation_btn_rects.clear()
	_sq_remove_btn_rects.clear()
	_sq_add_btn_rects.clear()

	if _fleet.squadrons.is_empty():
		return y

	# Iterate ALL squadrons
	for sq in _fleet.squadrons:
		y = _draw_single_squadron(font, y, clip, sq)

	# Separator after all squadrons
	y += 2
	if _in_clip(y, 2, clip):
		draw_line(Vector2(MARGIN, y), Vector2(PANEL_W - MARGIN, y), Color(MapColors.PANEL_BORDER, 0.4), 1.0)
	y += 4
	return y


func _draw_single_squadron(font: Font, y: float, clip: Rect2, sq) -> float:
	var sq_id: int = sq.squadron_id

	# Header: name + DISSOUDRE button
	if _in_clip(y, SHIP_H, clip):
		draw_string(font, Vector2(MARGIN, y + SHIP_H - 4), sq.squadron_name, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2 - 70, UITheme.FONT_SIZE_BODY, MapColors.SQUADRON_HEADER)
		# Disband button
		var disband_w: float = 62.0
		var disband_rect := Rect2(PANEL_W - MARGIN - disband_w, y + 2, disband_w, SHIP_H - 4)
		draw_rect(disband_rect, Color(0.8, 0.2, 0.1, 0.15))
		draw_rect(disband_rect, Color(0.8, 0.2, 0.1, 0.5), false, 1.0)
		draw_string(font, Vector2(disband_rect.position.x + 4, y + SHIP_H - 5), Locale.t("map.fleet.disband"), HORIZONTAL_ALIGNMENT_LEFT, disband_w - 8, UITheme.FONT_SIZE_TINY, Color(0.9, 0.3, 0.2))
		_sq_disband_btn_rects.append({"rect": disband_rect, "squadron_id": sq_id})
	y += SHIP_H

	# Formation buttons row
	var formations: Array[Dictionary] = SquadronFormation.get_available_formations()
	if _in_clip(y, SHIP_H, clip):
		var btn_w: float = (PANEL_W - MARGIN * 2 - (formations.size() - 1) * 2) / formations.size()
		var bx: float = MARGIN
		for form in formations:
			var is_active: bool = sq.formation_type == form["id"]
			var btn_rect := Rect2(bx, y + 1, btn_w, SHIP_H - 2)
			var bg_col: Color = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.2) if is_active else Color(0.15, 0.2, 0.25, 0.3)
			var border_col: Color = UITheme.PRIMARY if is_active else Color(0.3, 0.4, 0.5, 0.4)
			var text_col: Color = UITheme.PRIMARY if is_active else MapColors.TEXT_DIM
			draw_rect(btn_rect, bg_col)
			draw_rect(btn_rect, border_col, false, 1.0)
			draw_string(font, Vector2(bx + 2, y + SHIP_H - 4), form["display"], HORIZONTAL_ALIGNMENT_CENTER, btn_w - 4, UITheme.FONT_SIZE_TINY, text_col)
			_sq_formation_btn_rects.append({"rect": btn_rect, "formation_id": form["id"], "squadron_id": sq_id})
			bx += btn_w + 2
	y += SHIP_H + 2

	# Leader line
	if _in_clip(y, SHIP_H, clip):
		if sq.leader_fleet_index == -1:
			# Player is the leader
			draw_string(font, Vector2(MARGIN + 4, y + SHIP_H - 4), Locale.t("map.fleet.you_leader"), HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_SMALL, MapColors.SQUADRON_HEADER)
		else:
			# Fleet ship is the leader
			var leader_name: String = ""
			if sq.leader_fleet_index >= 0 and sq.leader_fleet_index < _fleet.ships.size():
				var lfs = _fleet.ships[sq.leader_fleet_index]
				leader_name = lfs.custom_name if lfs.custom_name != "" else String(lfs.ship_id)
			draw_string(font, Vector2(MARGIN + 4, y + SHIP_H - 4), "* %s (CHEF)" % leader_name, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_SMALL, MapColors.SQUADRON_HEADER)
	y += SHIP_H

	# Members
	if sq.member_fleet_indices.is_empty():
		if _in_clip(y, SHIP_H, clip):
			draw_string(font, Vector2(MARGIN + 8, y + SHIP_H - 4), Locale.t("map.fleet.no_members"), HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_TINY, Color(MapColors.TEXT_DIM, 0.5))
		y += SHIP_H
	else:
		for member_idx in sq.member_fleet_indices:
			if member_idx < 0 or member_idx >= _fleet.ships.size():
				continue
			var fs = _fleet.ships[member_idx]
			if _in_clip(y, SHIP_H, clip):
				# Status badge
				var badge: String = "[>]"
				var badge_col: Color = MapColors.FLEET_STATUS_DEPLOYED
				if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
					badge = "[D]"
					badge_col = MapColors.FLEET_STATUS_DOCKED
				elif fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
					badge = "[X]"
					badge_col = MapColors.FLEET_STATUS_DESTROYED

				draw_string(font, Vector2(MARGIN + 8, y + SHIP_H - 4), badge, HORIZONTAL_ALIGNMENT_LEFT, 28, UITheme.FONT_SIZE_TINY, badge_col)

				# Ship name
				var name_text: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
				draw_string(font, Vector2(MARGIN + 38, y + SHIP_H - 4), name_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2 - 70, UITheme.FONT_SIZE_LABEL, MapColors.TEXT_DIM)

				# Ship class (small)
				var ship_data = ShipRegistry.get_ship_data(fs.ship_id)
				if ship_data:
					draw_string(font, Vector2(PANEL_W - MARGIN - 30, y + SHIP_H - 4), String(ship_data.ship_class), HORIZONTAL_ALIGNMENT_RIGHT, 28, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)

				# Remove button "x"
				var x_rect := Rect2(PANEL_W - MARGIN - 2, y + 2, 12, SHIP_H - 4)
				draw_string(font, Vector2(PANEL_W - MARGIN, y + SHIP_H - 4), "x", HORIZONTAL_ALIGNMENT_LEFT, 12, UITheme.FONT_SIZE_TINY, Color(0.8, 0.3, 0.2, 0.7))
				_sq_remove_btn_rects.append({"rect": x_rect, "fleet_index": member_idx})
			y += SHIP_H

	return y


func _draw_group(font: Font, y: float, group: Dictionary, clip: Rect2) -> float:
	var collapsed: bool = group["collapsed"]
	var arrow: String = ">" if collapsed else "v"

	# System header
	if _in_clip(y, GROUP_H, clip):
		var label ="%s %s" % [arrow, group["system_name"]]
		draw_string(font, Vector2(MARGIN, y + GROUP_H - 5), label, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_BODY, MapColors.TEXT_HEADER)
		draw_line(Vector2(MARGIN, y + GROUP_H), Vector2(PANEL_W - MARGIN, y + GROUP_H), Color(MapColors.PANEL_BORDER, 0.3), 1.0)
	y += GROUP_H

	if collapsed:
		return y

	# Stations (docked ships)
	for st in group["stations"]:
		y += 2
		# Station sub-header
		if _in_clip(y, SHIP_H, clip):
			draw_string(font, Vector2(MARGIN + 8, y + SHIP_H - 4), st["name"], HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2 - 8, UITheme.FONT_SIZE_LABEL, MapColors.STATION_TEAL)
		y += SHIP_H

		for entry in st["ships"]:
			if _in_clip(y, SHIP_H, clip):
				_draw_ship_row(font, y, entry["fleet_index"], entry["ship"])
			y += SHIP_H

	# Deployed ships — flat list (squadron details are in the top section)
	for entry in group["deployed"]:
		if _in_clip(y, SHIP_H, clip):
			_draw_ship_row(font, y, entry["fleet_index"], entry["ship"])
		y += SHIP_H

	y += 6
	return y


func _draw_ship_row(font: Font, y: float, fleet_index: int, fs) -> void:
	var is_active: bool = fleet_index == _active_index
	var is_selected: bool = fleet_index in _selected_fleet_indices
	var x: float = MARGIN + 16

	# Selection highlight (pulsing cyan background)
	if is_selected:
		var pulse: float = sin(Time.get_ticks_msec() / 300.0) * 0.08 + 0.12
		draw_rect(Rect2(2, y, PANEL_W - 4, SHIP_H), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, pulse))

	# Squadron badge (leader star)
	var role_offset: float = 0.0
	if fs.squadron_id >= 0 and _fleet:
		var sq = _fleet.get_squadron(fs.squadron_id)
		if sq and sq.is_leader(fleet_index):
			draw_string(font, Vector2(x, y + SHIP_H - 4), "*", HORIZONTAL_ALIGNMENT_LEFT, 12, UITheme.FONT_SIZE_SMALL, MapColors.SQUADRON_HEADER)
			role_offset = 12.0

	# Status badge
	var badge: String = ""
	var badge_col: Color = MapColors.FLEET_STATUS_DOCKED
	if is_active:
		badge = "[A]"
		badge_col = MapColors.FLEET_STATUS_ACTIVE
	elif fs.deployment_state == FleetShip.DeploymentState.DOCKED:
		badge = "[D]"
		badge_col = MapColors.FLEET_STATUS_DOCKED
	elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		# Check if temporarily docked (mining sell cycle)
		var npc_id_str: String = String(fs.deployed_npc_id) if fs.deployed_npc_id != &"" else ""
		var ent_chk: Dictionary = EntityRegistry.get_entity(npc_id_str) if npc_id_str != "" else {}
		if ent_chk.get("extra", {}).get("mining_docked", false):
			badge = "[D]"
			badge_col = MapColors.FLEET_STATUS_DOCKED
		else:
			badge = "[>]"
			badge_col = MapColors.FLEET_STATUS_DEPLOYED
	elif fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
		badge = "[X]"
		badge_col = MapColors.FLEET_STATUS_DESTROYED

	draw_string(font, Vector2(x + role_offset, y + SHIP_H - 4), badge, HORIZONTAL_ALIGNMENT_LEFT, 28, UITheme.FONT_SIZE_TINY, badge_col)

	# Ship name
	var name_text: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
	var name_col: Color = UITheme.PRIMARY if is_selected else (MapColors.TEXT if is_active else MapColors.TEXT_DIM)
	draw_string(font, Vector2(x + role_offset + 30, y + SHIP_H - 4), name_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - x - role_offset - 36, UITheme.FONT_SIZE_LABEL, name_col)

	# Ship class (right-aligned, tiny) — shift left if "+" button will be drawn
	var ship_data = ShipRegistry.get_ship_data(fs.ship_id) if fs.ship_id != &"" else null
	if ship_data:
		var cls_text =String(ship_data.ship_class)
		var cls_right: float = PANEL_W - MARGIN - 2
		var has_single_sq: bool = _fleet != null and _fleet.squadrons.size() == 1
		if has_single_sq and not is_active and fs.squadron_id < 0 and fs.deployment_state != FleetShip.DeploymentState.DESTROYED:
			cls_right -= 14.0  # Make room for "+" button
		# Current order label (deployed ships only), drawn left of the class
		var order_label: String = _get_order_label(fs)
		if order_label != "":
			draw_string(font, Vector2(cls_right - 38, y + SHIP_H - 4), order_label, HORIZONTAL_ALIGNMENT_RIGHT, 34, UITheme.FONT_SIZE_TINY, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.55))
		draw_string(font, Vector2(cls_right, y + SHIP_H - 4), cls_text, HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)

	# Cargo fill micro-bar (thin line at bottom of row)
	var c_max: int = fs.cargo.capacity if fs.cargo else 0
	var c_stored: int = fs.cargo.get_total_count() if fs.cargo else 0
	for rid in fs.ship_resources:
		c_stored += fs.ship_resources[rid]
	if c_max > 0 and fs.deployment_state != FleetShip.DeploymentState.DESTROYED:
		var bar_x2: float = MARGIN + 16
		var bar_w2: float = PANEL_W - MARGIN * 2 - 16
		var bar_y2: float = y + SHIP_H - 1.5
		draw_rect(Rect2(bar_x2, bar_y2, bar_w2, 1.5), Color(0.1, 0.2, 0.3, 0.25))
		var f2: float = clampf(float(c_stored) / float(c_max), 0.0, 1.0)
		if f2 > 0.01:
			var fc2: Color
			if f2 < 0.6:
				fc2 = Color(0.15, 0.6, 0.8, 0.3)
			elif f2 < 0.85:
				fc2 = Color(0.8, 0.65, 0.1, 0.4)
			else:
				fc2 = Color(0.9, 0.3, 0.15, 0.5)
			draw_rect(Rect2(bar_x2, bar_y2, bar_w2 * f2, 1.5), fc2)

	# "+" button: add to squadron (only if exactly 1 squadron exists and ship is eligible)
	if _fleet and _fleet.squadrons.size() == 1 and not is_active and fs.squadron_id < 0 and fs.deployment_state != FleetShip.DeploymentState.DESTROYED:
		var target_sq = _fleet.squadrons[0]
		var plus_rect := Rect2(PANEL_W - MARGIN - 2, y + 2, 12, SHIP_H - 4)
		draw_string(font, Vector2(PANEL_W - MARGIN - 1, y + SHIP_H - 4), "+", HORIZONTAL_ALIGNMENT_LEFT, 12, UITheme.FONT_SIZE_SMALL, Color(UITheme.PRIMARY, 0.7))
		_sq_add_btn_rects.append({"rect": plus_rect, "fleet_index": fleet_index, "squadron_id": target_sq.squadron_id})


static func _get_order_label(fs) -> String:
	match fs.deployed_command:
		&"mine":               return "MINE"
		&"move_to":            return "NAV"
		&"patrol":             return "PTRL"
		&"attack":             return "ATK"
		&"return_to_station":  return "DOCK"
		&"construction":       return "CNST"
	return ""


func _in_clip(y: float, h: float, clip: Rect2) -> bool:
	return y + h > clip.position.y and y < clip.position.y + clip.size.y
