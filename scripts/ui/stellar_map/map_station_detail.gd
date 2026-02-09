class_name MapStationDetail
extends Control

# =============================================================================
# Map Station Detail - Right-side panel replacing MapInfoPanel
# Shows station info + docked fleet ships with deploy/recall/order buttons
# Full custom _draw(), no child Controls
# =============================================================================

signal deploy_requested(fleet_index: int, command: StringName, params: Dictionary)
signal retrieve_requested(fleet_index: int)
signal command_change_requested(fleet_index: int, command: StringName, params: Dictionary)
signal closed

const PANEL_W: float = 260.0
const MARGIN_RIGHT: float = 16.0
const MARGIN_INNER: float = 14.0
const HEADER_H: float = 36.0
const ROW_H: float = 22.0
const BUTTON_W: float = 80.0
const BUTTON_H: float = 22.0
const BUTTON_GAP: float = 6.0
const CORNER_LEN: float = 10.0
const SCROLL_SPEED: float = 28.0

var _fleet: PlayerFleet = null
var _station_id: String = ""
var _station_name: String = ""
var _station_type: String = ""
var _system_id: int = -1
var _active: bool = false
var _scroll_offset: float = 0.0
var _max_scroll: float = 0.0
var _hovered_button: String = ""  # "deploy_3", "recall_3", "cmd_3"

# Command picker state (inline)
var _picking_command: bool = false
var _pick_fleet_index: int = -1
var _pick_is_change: bool = false  # true = change order, false = deploy
var _deployable_cmds: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deployable_cmds = FleetCommand.get_deployable_commands()


func open_station(station_id: String, station_name: String, station_type: String, system_id: int) -> void:
	_station_id = station_id
	_station_name = station_name
	_station_type = station_type
	_system_id = system_id
	_scroll_offset = 0.0
	_picking_command = false
	_hovered_button = ""
	_active = true
	visible = true
	queue_redraw()


func set_fleet(fleet: PlayerFleet) -> void:
	if _fleet and _fleet.fleet_changed.is_connected(_on_fleet_changed):
		_fleet.fleet_changed.disconnect(_on_fleet_changed)
	_fleet = fleet
	if _fleet:
		_fleet.fleet_changed.connect(_on_fleet_changed)


func _on_fleet_changed() -> void:
	if _active:
		queue_redraw()


func is_active() -> bool:
	return _active


func close() -> void:
	if not _active:
		return
	_active = false
	_picking_command = false
	visible = false
	closed.emit()


func _get_panel_rect() -> Rect2:
	var px: float = size.x - PANEL_W - MARGIN_RIGHT
	return Rect2(px, 16, PANEL_W, size.y - 32)


func handle_click(pos: Vector2) -> bool:
	if not _active:
		return false
	var rect := _get_panel_rect()
	if not rect.has_point(pos):
		close()
		return true

	# Command picker active?
	if _picking_command:
		return _handle_command_pick_click(pos)

	# Check button hits
	var ships := _get_station_ships()
	var y: float = rect.position.y + HEADER_H + ROW_H * 3 - _scroll_offset  # after header + station info
	y += ROW_H  # "VAISSEAUX" header

	for entry in ships:
		var fi: int = entry["fleet_index"]
		var fs: FleetShip = entry["ship"]
		y += ROW_H  # ship name row

		# Button row
		var btn_x: float = rect.position.x + MARGIN_INNER
		if fi != _fleet.active_index:
			if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
				var btn_rect := Rect2(btn_x, y, BUTTON_W, BUTTON_H)
				if btn_rect.has_point(pos):
					_start_command_pick(fi, false)
					return true
			elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
				# RECALL button
				var recall_rect := Rect2(btn_x, y, BUTTON_W, BUTTON_H)
				if recall_rect.has_point(pos):
					retrieve_requested.emit(fi)
					return true
				# ORDRE button
				var order_rect := Rect2(btn_x + BUTTON_W + BUTTON_GAP, y, BUTTON_W, BUTTON_H)
				if order_rect.has_point(pos):
					_start_command_pick(fi, true)
					return true
		y += BUTTON_H + 4
	return true  # consumed


func handle_scroll(pos: Vector2, dir: int) -> bool:
	if not _active:
		return false
	var rect := _get_panel_rect()
	if not rect.has_point(pos):
		return false
	_scroll_offset = clampf(_scroll_offset - dir * SCROLL_SPEED, 0.0, _max_scroll)
	queue_redraw()
	return true


func _start_command_pick(fleet_index: int, is_change: bool) -> void:
	_picking_command = true
	_pick_fleet_index = fleet_index
	_pick_is_change = is_change
	queue_redraw()


func _handle_command_pick_click(pos: Vector2) -> bool:
	var rect := _get_panel_rect()
	# Command list is drawn centered in panel
	var cmd_y: float = rect.position.y + rect.size.y * 0.3
	var cmd_x: float = rect.position.x + MARGIN_INNER

	for cmd in _deployable_cmds:
		var btn_rect := Rect2(cmd_x, cmd_y, PANEL_W - MARGIN_INNER * 2, BUTTON_H + 4)
		if btn_rect.has_point(pos):
			_picking_command = false
			var cmd_id: StringName = cmd["id"]
			if _pick_is_change:
				command_change_requested.emit(_pick_fleet_index, cmd_id, {})
			else:
				deploy_requested.emit(_pick_fleet_index, cmd_id, {})
			queue_redraw()
			return true
		cmd_y += BUTTON_H + 8

	# Click outside commands = cancel
	_picking_command = false
	queue_redraw()
	return true


func _get_station_ships() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _fleet == null:
		return result
	# Docked at this station
	for i in _fleet.ships.size():
		var fs := _fleet.ships[i]
		if fs.docked_station_id == _station_id:
			if fs.deployment_state == FleetShip.DeploymentState.DOCKED or i == _fleet.active_index:
				result.append({"fleet_index": i, "ship": fs})
	# Deployed in this system
	for i in _fleet.ships.size():
		var fs := _fleet.ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.docked_system_id == _system_id:
			result.append({"fleet_index": i, "ship": fs})
	return result


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if not _active:
		return

	var font: Font = UITheme.get_font()
	var rect := _get_panel_rect()
	var px: float = rect.position.x
	var py: float = rect.position.y
	var pw: float = rect.size.x
	var ph: float = rect.size.y

	# Background
	draw_rect(rect, MapColors.STATION_DETAIL_BG)
	draw_rect(rect, MapColors.PANEL_BORDER, false, 1.0)

	# Corner accents
	var cc := MapColors.CORNER
	draw_line(Vector2(px, py), Vector2(px + CORNER_LEN, py), cc, 1.5)
	draw_line(Vector2(px, py), Vector2(px, py + CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px + pw, py), Vector2(px + pw - CORNER_LEN, py), cc, 1.5)
	draw_line(Vector2(px + pw, py), Vector2(px + pw, py + CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px, py + ph), Vector2(px + CORNER_LEN, py + ph), cc, 1.5)
	draw_line(Vector2(px, py + ph), Vector2(px, py + ph - CORNER_LEN), cc, 1.5)
	draw_line(Vector2(px + pw, py + ph), Vector2(px + pw - CORNER_LEN, py + ph), cc, 1.5)
	draw_line(Vector2(px + pw, py + ph), Vector2(px + pw, py + ph - CORNER_LEN), cc, 1.5)

	if _picking_command:
		_draw_command_picker(font, rect)
		return

	var x: float = px + MARGIN_INNER
	var w: float = pw - MARGIN_INNER * 2
	var y: float = py + 24 - _scroll_offset

	# Station name
	draw_string(font, Vector2(x, y), _station_name, HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_HEADER, MapColors.TEXT_HEADER)
	y += 6
	draw_line(Vector2(x, y), Vector2(px + pw - MARGIN_INNER, y), MapColors.PANEL_BORDER, 1.0)
	y += ROW_H

	# Type
	var type_label: String = _station_type_label(_station_type)
	_draw_kv(font, x, y, w, "TYPE", type_label)
	y += ROW_H

	# Separator
	y += 4
	draw_line(Vector2(x, y), Vector2(px + pw - MARGIN_INNER, y), MapColors.PANEL_BORDER, 1.0)
	y += ROW_H

	# Ships section
	var ships := _get_station_ships()
	draw_string(font, Vector2(x, y), "VAISSEAUX (%d)" % ships.size(), HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_BODY, MapColors.TEXT_HEADER)
	y += ROW_H

	if ships.is_empty():
		draw_string(font, Vector2(x + 4, y), "Aucun vaisseau ici", HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_SMALL, MapColors.TEXT_DIM)
		y += ROW_H
	else:
		for entry in ships:
			y = _draw_ship_entry(font, x, y, w, entry["fleet_index"], entry["ship"])

	# Close hint
	y += 10
	draw_string(font, Vector2(x, y), "[ESC] Fermer", HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)

	_max_scroll = maxf(y + _scroll_offset - (py + ph) + 20, 0.0)

	# Scanline
	var scan_y: float = fmod(Time.get_ticks_msec() / 40.0, ph) + py
	draw_line(Vector2(px, scan_y), Vector2(px + pw, scan_y), MapColors.SCANLINE, 1.0)


func _draw_ship_entry(font: Font, x: float, y: float, w: float, fi: int, fs: FleetShip) -> float:
	var is_active: bool = fi == _fleet.active_index

	# Status badge + name
	var badge: String
	var badge_col: Color
	if is_active:
		badge = "ACTIF"
		badge_col = MapColors.FLEET_STATUS_ACTIVE
	elif fs.deployment_state == FleetShip.DeploymentState.DOCKED:
		badge = "DOCKE"
		badge_col = MapColors.FLEET_STATUS_DOCKED
	elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		badge = "DEPLOYE"
		badge_col = MapColors.FLEET_STATUS_DEPLOYED
	else:
		badge = "DETRUIT"
		badge_col = MapColors.FLEET_STATUS_DESTROYED

	var name_text: String = fs.custom_name if fs.custom_name != "" else String(fs.ship_id)
	draw_string(font, Vector2(x + 4, y), name_text, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, UITheme.FONT_SIZE_BODY, MapColors.TEXT)
	draw_string(font, Vector2(x + w - 4, y), badge, HORIZONTAL_ALIGNMENT_RIGHT, 70, UITheme.FONT_SIZE_TINY, badge_col)
	y += ROW_H

	# Action buttons (not for active ship)
	if not is_active:
		var btn_x: float = x
		if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
			_draw_button(font, btn_x, y, BUTTON_W, BUTTON_H, "DEPLOYER", MapColors.ACTION_BUTTON)
		elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
			_draw_button(font, btn_x, y, BUTTON_W, BUTTON_H, "RAPPELER", Color(0.9, 0.5, 0.1, 0.9))
			btn_x += BUTTON_W + BUTTON_GAP
			_draw_button(font, btn_x, y, BUTTON_W, BUTTON_H, "ORDRE", MapColors.PRIMARY)
			# Show current command
			var cmd_data := FleetCommand.get_command(fs.deployed_command)
			if not cmd_data.is_empty():
				var cmd_label: String = cmd_data.get("display_name", "")
				draw_string(font, Vector2(btn_x + BUTTON_W + BUTTON_GAP, y + BUTTON_H - 5), cmd_label, HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_TINY, MapColors.FLEET_STATUS_DEPLOYED)
		y += BUTTON_H + 4
	else:
		y += 4

	return y


func _draw_button(font: Font, x: float, y: float, w: float, h: float, label: String, col: Color) -> void:
	var rect := Rect2(x, y, w, h)
	draw_rect(rect, Color(col, 0.15))
	draw_rect(rect, col, false, 1.0)
	draw_string(font, Vector2(x + 4, y + h - 6), label, HORIZONTAL_ALIGNMENT_CENTER, w - 8, UITheme.FONT_SIZE_TINY, col)


func _draw_command_picker(font: Font, rect: Rect2) -> void:
	var x: float = rect.position.x + MARGIN_INNER
	var w: float = rect.size.x - MARGIN_INNER * 2
	var y: float = rect.position.y + 24

	var title: String = "CHOISIR ORDRE" if _pick_is_change else "DEPLOYER AVEC ORDRE"
	draw_string(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_HEADER, MapColors.TEXT_HEADER)
	y += 8
	draw_line(Vector2(x, y), Vector2(x + w, y), MapColors.PANEL_BORDER, 1.0)
	y += ROW_H

	for cmd in _deployable_cmds:
		var btn_rect := Rect2(x, y, w, BUTTON_H + 4)
		draw_rect(btn_rect, Color(MapColors.ACTION_BUTTON, 0.1))
		draw_rect(btn_rect, MapColors.ACTION_BUTTON, false, 1.0)
		draw_string(font, Vector2(x + 8, y + BUTTON_H - 4), cmd["display_name"], HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, UITheme.FONT_SIZE_BODY, MapColors.ACTION_BUTTON)
		draw_string(font, Vector2(x + w * 0.45, y + BUTTON_H - 4), cmd["description"], HORIZONTAL_ALIGNMENT_LEFT, w * 0.55 - 8, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)
		y += BUTTON_H + 8

	y += 10
	draw_string(font, Vector2(x, y), "Cliquer pour choisir, ou cliquer ailleurs pour annuler", HORIZONTAL_ALIGNMENT_LEFT, w, UITheme.FONT_SIZE_TINY, MapColors.TEXT_DIM)


func _draw_kv(font: Font, x: float, y: float, w: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, w * 0.35, UITheme.FONT_SIZE_BODY, MapColors.LABEL_KEY)
	draw_string(font, Vector2(x + w * 0.35, y), value, HORIZONTAL_ALIGNMENT_LEFT, w * 0.65, UITheme.FONT_SIZE_BODY, MapColors.LABEL_VALUE)


func _station_type_label(stype: String) -> String:
	match stype:
		"repair": return "Reparation"
		"trade": return "Commerce"
		"military": return "Militaire"
		"mining": return "Extraction"
	return stype.capitalize()
