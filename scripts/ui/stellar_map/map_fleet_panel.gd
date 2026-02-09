class_name MapFleetPanel
extends Control

# =============================================================================
# Map Fleet Panel - Left-side fleet overview on stellar/galaxy map
# Groups ships by system > station, scrollable, clickable
# Full custom _draw(), no child Controls
# =============================================================================

signal ship_selected(fleet_index: int, system_id: int)

const PANEL_W: float = 240.0
const HEADER_H: float = 32.0
const GROUP_H: float = 22.0
const SHIP_H: float = 20.0
const MARGIN: float = 10.0
const SCROLL_SPEED: float = 28.0
const CORNER_LEN: float = 8.0

var _fleet: PlayerFleet = null
var _galaxy: GalaxyData = null
var _active_index: int = -1

# Grouped data rebuilt on fleet_changed
var _groups: Array[Dictionary] = []
# { "system_id": int, "system_name": String, "collapsed": bool,
#   "stations": [{ "station_id": String, "name": String,
#                   "ships": [{ "fleet_index": int, "ship": FleetShip }] }],
#   "deployed": [{ "fleet_index": int, "ship": FleetShip }] }

var _scroll_offset: float = 0.0
var _max_scroll: float = 0.0
var _hovered_row: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fleet(fleet: PlayerFleet) -> void:
	if _fleet and _fleet.fleet_changed.is_connected(_rebuild):
		_fleet.fleet_changed.disconnect(_rebuild)
	_fleet = fleet
	if _fleet:
		_fleet.fleet_changed.connect(_rebuild)
		_active_index = _fleet.active_index
	_rebuild()


func set_galaxy(galaxy: GalaxyData) -> void:
	_galaxy = galaxy
	_rebuild()


func _rebuild() -> void:
	_groups.clear()
	if _fleet == null:
		return

	_active_index = _fleet.active_index

	# Build a mapping: system_id -> station_id -> Array of {fleet_index, ship}
	var sys_map: Dictionary = {}  # int -> Dictionary
	for i in _fleet.ships.size():
		var fs := _fleet.ships[i]
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
		elif fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
			var st_id: String = fs.docked_station_id if fs.docked_station_id != "" else "_none"
			if not sys_map[sys_id]["docked"].has(st_id):
				sys_map[sys_id]["docked"][st_id] = []
			sys_map[sys_id]["docked"][st_id].append({"fleet_index": i, "ship": fs})

	# Convert to sorted groups
	var sys_ids: Array = sys_map.keys()
	sys_ids.sort()
	for sys_id in sys_ids:
		var data: Dictionary = sys_map[sys_id]
		var sys_name: String = "Inconnu"
		if _galaxy and sys_id >= 0:
			sys_name = _galaxy.get_system_name(sys_id)

		var stations: Array[Dictionary] = []
		var st_ids: Array = data["docked"].keys()
		st_ids.sort()
		for st_id in st_ids:
			var ships_arr: Array = data["docked"][st_id]
			var st_name: String = st_id if st_id != "_none" else "En vol"
			# Try to get station name from EntityRegistry
			if st_id != "_none":
				var ent := EntityRegistry.get_entity(st_id)
				if not ent.is_empty():
					st_name = ent.get("name", st_id)
			stations.append({"station_id": st_id, "name": st_name, "ships": ships_arr})

		_groups.append({
			"system_id": sys_id,
			"system_name": sys_name,
			"collapsed": false,
			"stations": stations,
			"deployed": data["deployed"],
		})


func get_panel_rect() -> Rect2:
	return Rect2(0, 0, PANEL_W, size.y)


func handle_click(pos: Vector2) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		return false
	if _fleet == null or _fleet.ships.is_empty():
		return false

	var y: float = HEADER_H + MARGIN - _scroll_offset
	for g_idx in _groups.size():
		var group: Dictionary = _groups[g_idx]
		# System header
		if _hit_row(pos.y, y, GROUP_H):
			group["collapsed"] = not group["collapsed"]
			queue_redraw()
			return true
		y += GROUP_H

		if group["collapsed"]:
			continue

		# Stations
		for st in group["stations"]:
			y += 2  # spacing
			# Station sub-header (not clickable for now)
			y += SHIP_H
			for entry in st["ships"]:
				if _hit_row(pos.y, y, SHIP_H):
					ship_selected.emit(entry["fleet_index"], group["system_id"])
					queue_redraw()
					return true
				y += SHIP_H

		# Deployed
		for entry in group["deployed"]:
			if _hit_row(pos.y, y, SHIP_H):
				ship_selected.emit(entry["fleet_index"], group["system_id"])
				queue_redraw()
				return true
			y += SHIP_H

		y += 6  # group spacing

	return true  # consumed (clicked in panel area)


func handle_scroll(pos: Vector2, dir: int) -> bool:
	if pos.x > PANEL_W or pos.x < 0:
		return false
	if _fleet == null or _fleet.ships.is_empty():
		return false
	_scroll_offset = clampf(_scroll_offset - dir * SCROLL_SPEED, 0.0, _max_scroll)
	queue_redraw()
	return true


func _hit_row(mouse_y: float, row_y: float, row_h: float) -> bool:
	return mouse_y >= row_y and mouse_y < row_y + row_h


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if _fleet == null or _fleet.ships.is_empty():
		return

	var font: Font = UITheme.get_font()
	var rect := get_panel_rect()

	# Background
	draw_rect(rect, MapColors.FLEET_PANEL_BG)
	draw_rect(rect, MapColors.PANEL_BORDER, false, 1.0)

	# Corner accents
	var px: float = rect.position.x
	var py: float = rect.position.y
	var pw: float = rect.size.x
	var ph: float = rect.size.y
	var cc := MapColors.CORNER
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
	var header_text := "FLOTTE (%d)" % ship_count
	draw_string(font, Vector2(MARGIN, HEADER_H - 8), header_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2, UITheme.FONT_SIZE_HEADER, MapColors.TEXT_HEADER)
	draw_line(Vector2(MARGIN, HEADER_H), Vector2(PANEL_W - MARGIN, HEADER_H), MapColors.PANEL_BORDER, 1.0)

	# Clip region
	var clip := Rect2(0, HEADER_H + 2, PANEL_W, size.y - HEADER_H - 2)

	var y: float = HEADER_H + MARGIN - _scroll_offset
	for group in _groups:
		y = _draw_group(font, y, group, clip)

	_max_scroll = maxf(y + _scroll_offset - size.y + 20, 0.0)

	# Scanline
	var scan_y: float = fmod(Time.get_ticks_msec() / 40.0, size.y)
	if scan_y > HEADER_H:
		draw_line(Vector2(0, scan_y), Vector2(PANEL_W, scan_y), MapColors.SCANLINE, 1.0)


func _draw_group(font: Font, y: float, group: Dictionary, clip: Rect2) -> float:
	var collapsed: bool = group["collapsed"]
	var arrow: String = ">" if collapsed else "v"

	# System header
	if _in_clip(y, GROUP_H, clip):
		var label := "%s %s" % [arrow, group["system_name"]]
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
			draw_string(font, Vector2(MARGIN + 8, y + SHIP_H - 4), st["name"], HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - MARGIN * 2 - 8, UITheme.FONT_SIZE_SMALL, MapColors.STATION_TEAL)
		y += SHIP_H

		for entry in st["ships"]:
			if _in_clip(y, SHIP_H, clip):
				_draw_ship_row(font, y, entry["fleet_index"], entry["ship"])
			y += SHIP_H

	# Deployed ships
	for entry in group["deployed"]:
		if _in_clip(y, SHIP_H, clip):
			_draw_ship_row(font, y, entry["fleet_index"], entry["ship"])
		y += SHIP_H

	y += 6
	return y


func _draw_ship_row(font: Font, y: float, fleet_index: int, fs: FleetShip) -> void:
	var is_active: bool = fleet_index == _active_index
	var x: float = MARGIN + 16

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
		badge = "[>]"
		badge_col = MapColors.FLEET_STATUS_DEPLOYED
	elif fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
		badge = "[X]"
		badge_col = MapColors.FLEET_STATUS_DESTROYED

	draw_string(font, Vector2(x, y + SHIP_H - 4), badge, HORIZONTAL_ALIGNMENT_LEFT, 28, UITheme.FONT_SIZE_TINY, badge_col)

	# Ship name
	var name_text: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
	var name_col: Color = MapColors.TEXT if is_active else MapColors.TEXT_DIM
	draw_string(font, Vector2(x + 30, y + SHIP_H - 4), name_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - x - 36, UITheme.FONT_SIZE_SMALL, name_col)

	# Ship class (right-aligned, tiny)
	var ship_data := ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data:
		var cls_text := String(ship_data.ship_class)
		draw_string(font, Vector2(PANEL_W - MARGIN - 2, y + SHIP_H - 4), cls_text, HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)


func _in_clip(y: float, h: float, clip: Rect2) -> bool:
	return y + h > clip.position.y and y < clip.position.y + clip.size.y
