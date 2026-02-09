class_name FleetManagementPanel
extends UIScreen

# =============================================================================
# Fleet Management Panel — Manage ships at a station
# Opened via long-press on station in system map.
# =============================================================================

signal fleet_action_completed

var station_id: String = ""
var station_name: String = ""
var system_id: int = -1

var _fleet: PlayerFleet = null
var _deployment_mgr: FleetDeploymentManager = null
var _selected_index: int = -1
var _ship_cards: Array[FleetShipCard] = []
var _command_picker: FleetCommandPicker = null
var _pending_deploy_index: int = -1

# Layout constants
const LIST_X: float = 40.0
const LIST_Y: float = 80.0
const LIST_W: float = 320.0
const DETAIL_X: float = 380.0
const DETAIL_Y: float = 80.0
const DETAIL_W: float = 400.0
const CARD_H: float = 60.0
const CARD_SPACING: float = 4.0
const BTN_W: float = 180.0
const BTN_H: float = 36.0

# Action button rects (computed in draw)
var _btn_deploy: Rect2 = Rect2()
var _btn_retrieve: Rect2 = Rect2()
var _btn_command: Rect2 = Rect2()
var _card_rects: Array[Rect2] = []
var _scroll_offset: float = 0.0


func _init() -> void:
	screen_title = "GESTION DE FLOTTE"
	screen_mode = ScreenMode.FULLSCREEN


func setup(p_station_id: String, p_station_name: String, p_system_id: int) -> void:
	station_id = p_station_id
	station_name = p_station_name
	system_id = p_system_id
	_fleet = GameManager.player_fleet
	_deployment_mgr = GameManager._fleet_deployment_mgr
	_rebuild_cards()
	_selected_index = -1


func _on_opened() -> void:
	_rebuild_cards()
	queue_redraw()


func _on_closed() -> void:
	if _command_picker and is_instance_valid(_command_picker):
		_command_picker.queue_free()
		_command_picker = null


func _rebuild_cards() -> void:
	_ship_cards.clear()
	_card_rects.clear()
	if _fleet == null:
		return

	# Gather ships docked at this station + deployed in this system
	var docked_indices: Array[int] = _fleet.get_ships_at_station(station_id)
	var deployed_indices: Array[int] = _fleet.get_deployed_in_system(system_id)

	# Add docked ships first, then deployed
	for idx in docked_indices:
		_ship_cards.append(FleetShipCard.from_fleet_ship(_fleet.ships[idx], idx, _fleet.active_index))
	for idx in deployed_indices:
		if idx not in docked_indices:
			_ship_cards.append(FleetShipCard.from_fleet_ship(_fleet.ships[idx], idx, _fleet.active_index))


func _process(delta: float) -> void:
	super._process(delta)
	if _is_open:
		queue_redraw()


func _draw() -> void:
	super._draw()
	if _fleet == null:
		return

	var font: Font = UITheme.get_font()
	var s := size

	# Station name subtitle
	draw_string(font, Vector2(LIST_X, LIST_Y - 10), "Station: %s" % station_name, HORIZONTAL_ALIGNMENT_LEFT, s.x - LIST_X * 2, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)

	# === LEFT: Ship list ===
	_draw_ship_list(font)

	# === RIGHT: Detail panel ===
	_draw_detail_panel(font)


func _draw_ship_list(font: Font) -> void:
	var y: float = LIST_Y + 20.0 - _scroll_offset
	_card_rects.clear()

	# Section: DOCKED
	var has_docked := false
	var has_deployed := false
	for card in _ship_cards:
		if card.deployment_state == FleetShip.DeploymentState.DOCKED:
			has_docked = true
		elif card.deployment_state == FleetShip.DeploymentState.DEPLOYED:
			has_deployed = true

	if has_docked:
		draw_string(font, Vector2(LIST_X, y + 14), "VAISSEAUX DOCKES", HORIZONTAL_ALIGNMENT_LEFT, LIST_W, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_HEADER)
		y += 24.0

		for card in _ship_cards:
			if card.deployment_state != FleetShip.DeploymentState.DOCKED:
				continue
			var rect := Rect2(LIST_X, y, LIST_W, CARD_H)
			_card_rects.append(rect)
			_draw_ship_card(font, rect, card)
			y += CARD_H + CARD_SPACING

	if has_deployed:
		y += 10.0
		draw_string(font, Vector2(LIST_X, y + 14), "VAISSEAUX DEPLOYES", HORIZONTAL_ALIGNMENT_LEFT, LIST_W, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_HEADER)
		y += 24.0

		for card in _ship_cards:
			if card.deployment_state != FleetShip.DeploymentState.DEPLOYED:
				continue
			var rect := Rect2(LIST_X, y, LIST_W, CARD_H)
			_card_rects.append(rect)
			_draw_ship_card(font, rect, card)
			y += CARD_H + CARD_SPACING

	# Empty state
	if _ship_cards.is_empty():
		draw_string(font, Vector2(LIST_X, LIST_Y + 60), "Aucun vaisseau dans ce systeme", HORIZONTAL_ALIGNMENT_LEFT, LIST_W, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


func _draw_ship_card(font: Font, rect: Rect2, card: FleetShipCard) -> void:
	var is_selected: bool = card.fleet_index == _selected_index
	var bg_col := Color(0.08, 0.25, 0.35, 0.7) if is_selected else Color(0.04, 0.1, 0.18, 0.6)
	draw_rect(rect, bg_col)

	var border_col := UITheme.PRIMARY if is_selected else UITheme.BORDER
	draw_rect(rect, border_col, false, 1.0)

	# Ship name
	var name_col: Color = UITheme.TEXT if not card.is_active else Color(0.2, 1.0, 0.5, 0.9)
	draw_string(font, rect.position + Vector2(12, 22), card.custom_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, UITheme.FONT_SIZE_BODY, name_col)

	# Status label
	var status_text: String = ""
	var status_col: Color = UITheme.TEXT_DIM
	if card.is_active:
		status_text = "[ACTIF]"
		status_col = Color(0.2, 1.0, 0.5, 0.8)
	elif card.deployment_state == FleetShip.DeploymentState.DOCKED:
		status_text = "[DOCKE]"
		status_col = UITheme.TEXT_DIM
	elif card.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		status_text = "[%s]" % card.command_name if card.command_name != "" else "[DEPLOYE]"
		status_col = Color(0.4, 0.7, 1.0, 0.9)
	elif card.deployment_state == FleetShip.DeploymentState.DESTROYED:
		status_text = "[DETRUIT]"
		status_col = Color(1.0, 0.3, 0.2, 0.8)
	draw_string(font, rect.position + Vector2(12, 44), status_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, UITheme.FONT_SIZE_SMALL, status_col)

	# Ship class on the right
	var ship_data := ShipRegistry.get_ship_data(card.ship_id)
	if ship_data:
		var class_text: String = String(ship_data.ship_class)
		draw_string(font, rect.position + Vector2(rect.size.x - 12, 22), class_text, HORIZONTAL_ALIGNMENT_RIGHT, 120, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)


func _draw_detail_panel(font: Font) -> void:
	# Panel background
	var panel_rect := Rect2(DETAIL_X, DETAIL_Y, DETAIL_W, size.y - DETAIL_Y - 40)
	draw_rect(panel_rect, Color(0.02, 0.06, 0.1, 0.6))
	draw_rect(panel_rect, UITheme.BORDER, false, 1.0)

	if _selected_index < 0 or _fleet == null or _selected_index >= _fleet.ships.size():
		draw_string(font, Vector2(DETAIL_X + 20, DETAIL_Y + 60), "Selectionnez un vaisseau", HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
		return

	var fs := _fleet.ships[_selected_index]
	var ship_data := ShipRegistry.get_ship_data(fs.ship_id)
	if ship_data == null:
		return

	var y: float = DETAIL_Y + 30.0

	# Ship name
	draw_string(font, Vector2(DETAIL_X + 20, y), fs.custom_name, HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)
	y += 30.0

	# Ship class
	draw_string(font, Vector2(DETAIL_X + 20, y), "Classe: %s" % ship_data.ship_class, HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	y += 22.0

	# Hull
	draw_string(font, Vector2(DETAIL_X + 20, y), "Coque: %d PV" % ship_data.hull_hp, HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	y += 22.0

	# Hardpoints
	draw_string(font, Vector2(DETAIL_X + 20, y), "Emplacements: %d" % ship_data.hardpoints.size(), HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	y += 22.0

	# Weapons list
	var weapon_count: int = 0
	for wn in fs.weapons:
		if wn != &"":
			weapon_count += 1
	draw_string(font, Vector2(DETAIL_X + 20, y), "Armes equipees: %d/%d" % [weapon_count, fs.weapons.size()], HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
	y += 30.0

	# Separator
	draw_line(Vector2(DETAIL_X + 20, y), Vector2(DETAIL_X + DETAIL_W - 20, y), UITheme.BORDER, 1.0)
	y += 15.0

	# Action buttons
	var is_active: bool = _selected_index == _fleet.active_index
	var btn_x: float = DETAIL_X + 20.0

	if fs.deployment_state == FleetShip.DeploymentState.DOCKED and not is_active:
		# DEPLOYER button
		_btn_deploy = Rect2(btn_x, y, BTN_W, BTN_H)
		_draw_action_button(font, _btn_deploy, "DEPLOYER", Color(0.1, 0.5, 0.9, 0.9))
		y += BTN_H + 8.0
	else:
		_btn_deploy = Rect2()

	if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		# RAPPELER button
		_btn_retrieve = Rect2(btn_x, y, BTN_W, BTN_H)
		_draw_action_button(font, _btn_retrieve, "RAPPELER", Color(0.8, 0.6, 0.1, 0.9))
		y += BTN_H + 8.0

		# CHANGER ORDRE button
		_btn_command = Rect2(btn_x, y, BTN_W, BTN_H)
		_draw_action_button(font, _btn_command, "CHANGER ORDRE", Color(0.3, 0.7, 0.9, 0.9))
		y += BTN_H + 8.0
	else:
		_btn_retrieve = Rect2()
		_btn_command = Rect2()

	if is_active:
		draw_string(font, Vector2(DETAIL_X + 20, y + 16), "Vaisseau actif — ne peut pas etre deploye", HORIZONTAL_ALIGNMENT_LEFT, DETAIL_W - 40, UITheme.FONT_SIZE_SMALL, Color(0.8, 0.6, 0.2, 0.7))


func _draw_action_button(font: Font, rect: Rect2, text: String, col: Color) -> void:
	draw_rect(rect, Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.7))
	draw_rect(rect, col, false, 1.5)
	draw_string(font, rect.position + Vector2(12, rect.size.y * 0.65), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, UITheme.FONT_SIZE_BODY, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Check close button (parent handles)
		var close_x: float = size.x - UITheme.MARGIN_SCREEN - 28
		var close_y: float = UITheme.MARGIN_SCREEN
		var close_rect := Rect2(close_x, close_y, 32, 28)
		if close_rect.has_point(event.position):
			close()
			accept_event()
			return

		# Check card clicks
		var card_idx: int = 0
		for card in _ship_cards:
			if card.deployment_state == FleetShip.DeploymentState.DOCKED:
				if card_idx < _card_rects.size() and _card_rects[card_idx].has_point(event.position):
					_selected_index = card.fleet_index
					queue_redraw()
					accept_event()
					return
				card_idx += 1
		for card in _ship_cards:
			if card.deployment_state == FleetShip.DeploymentState.DEPLOYED:
				if card_idx < _card_rects.size() and _card_rects[card_idx].has_point(event.position):
					_selected_index = card.fleet_index
					queue_redraw()
					accept_event()
					return
				card_idx += 1

		# Check action buttons
		if _btn_deploy.has_area() and _btn_deploy.has_point(event.position):
			_on_deploy_pressed()
			accept_event()
			return
		if _btn_retrieve.has_area() and _btn_retrieve.has_point(event.position):
			_on_retrieve_pressed()
			accept_event()
			return
		if _btn_command.has_area() and _btn_command.has_point(event.position):
			_on_change_command_pressed()
			accept_event()
			return

	# Scroll in ship list area
	if event is InputEventMouseButton:
		if event.position.x >= LIST_X and event.position.x <= LIST_X + LIST_W:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_scroll_offset = maxf(0.0, _scroll_offset - 30.0)
				queue_redraw()
				accept_event()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_scroll_offset += 30.0
				queue_redraw()
				accept_event()
				return

	accept_event()


func _on_deploy_pressed() -> void:
	if _selected_index < 0 or _deployment_mgr == null:
		return
	_pending_deploy_index = _selected_index
	_show_command_picker()


func _on_retrieve_pressed() -> void:
	if _selected_index < 0 or _deployment_mgr == null:
		return
	_deployment_mgr.request_retrieve(_selected_index)
	_rebuild_cards()
	queue_redraw()
	fleet_action_completed.emit()


func _on_change_command_pressed() -> void:
	if _selected_index < 0 or _deployment_mgr == null:
		return
	_pending_deploy_index = _selected_index
	_show_command_picker()


func _show_command_picker() -> void:
	if _command_picker and is_instance_valid(_command_picker):
		_command_picker.queue_free()

	_command_picker = FleetCommandPicker.new()
	_command_picker.name = "FleetCommandPicker"
	_command_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_command_picker)

	# Center the picker on screen
	_command_picker.reposition(size * 0.5)

	_command_picker.command_selected.connect(_on_command_chosen)
	_command_picker.cancelled.connect(_on_command_cancelled)


func _on_command_chosen(command_id: StringName) -> void:
	if _command_picker and is_instance_valid(_command_picker):
		_command_picker.queue_free()
		_command_picker = null

	if _pending_deploy_index < 0 or _deployment_mgr == null:
		return

	var fs := _fleet.ships[_pending_deploy_index]
	if fs.deployment_state == FleetShip.DeploymentState.DOCKED:
		_deployment_mgr.request_deploy(_pending_deploy_index, command_id, {"station_id": station_id})
	elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		_deployment_mgr.request_change_command(_pending_deploy_index, command_id, {})

	_pending_deploy_index = -1
	_rebuild_cards()
	queue_redraw()
	fleet_action_completed.emit()


func _on_command_cancelled() -> void:
	if _command_picker and is_instance_valid(_command_picker):
		_command_picker.queue_free()
		_command_picker = null
	_pending_deploy_index = -1
