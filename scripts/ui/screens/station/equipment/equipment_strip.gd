class_name EquipmentStrip
extends Control

# =============================================================================
# Equipment Screen — Fleet Carousel + Bottom Strips (HP/Module/Shield/Engine)
# =============================================================================

signal fleet_ship_selected(idx: int)
signal hardpoint_clicked(idx: int)
signal module_slot_clicked(idx: int)
signal shield_remove_requested
signal engine_remove_requested
signal weapon_remove_requested(idx: int)
signal module_remove_requested(idx: int)

const EC =preload("res://scripts/ui/screens/station/equipment/equipment_constants.gd")

# --- State ---
var _adapter: RefCounted = null
var _fleet = null
var _fleet_index: int = 0
var _current_tab: int = 0
var _selected_hardpoint: int = -1
var _selected_module_slot: int = -1
var _fleet_scroll_offset: float = 0.0
var _fleet_hovered_index: int = -1
var _hp_hovered_index: int = -1
var _module_hovered_index: int = -1
var _is_station_mode: bool = false
var _current_station_id: String = ""


func setup(adapter: RefCounted, fleet, fleet_index: int, is_station: bool) -> void:
	_adapter = adapter
	_fleet = fleet
	_fleet_index = fleet_index
	_is_station_mode = is_station
	_fleet_scroll_offset = 0.0
	_fleet_hovered_index = -1
	_hp_hovered_index = -1
	_module_hovered_index = -1
	# Resolve current station ID from active fleet ship
	if fleet and fleet.get_active():
		_current_station_id = fleet.get_active().docked_station_id
	else:
		_current_station_id = ""


## Returns true if this fleet ship is available for equipment editing at the current station.
func _is_ship_available(index: int, fs) -> bool:
	if _fleet and index == _fleet.active_index:
		return true  # Active ship is always editable
	if fs.deployment_state != FleetShip.DeploymentState.DOCKED:
		return false
	if _current_station_id != "" and fs.docked_station_id != _current_station_id:
		return false
	return true


func set_tab(tab: int) -> void:
	_current_tab = tab
	_hp_hovered_index = -1
	_module_hovered_index = -1
	queue_redraw()


func set_selected_hardpoint(idx: int) -> void:
	_selected_hardpoint = idx
	queue_redraw()


func set_selected_module_slot(idx: int) -> void:
	_selected_module_slot = idx
	queue_redraw()


func set_fleet_index(idx: int) -> void:
	_fleet_index = idx
	queue_redraw()


func refresh() -> void:
	queue_redraw()


# =============================================================================
# INPUT
# =============================================================================
func handle_fleet_input(event: InputEvent, screen_size: Vector2) -> bool:
	if _is_station_mode:
		return false
	var fleet_strip_bottom =EC.FLEET_STRIP_TOP + EC.FLEET_STRIP_H

	if event is InputEventMouseButton and event.pressed:
		if event.position.y >= EC.FLEET_STRIP_TOP and event.position.y <= fleet_strip_bottom:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var idx =_get_fleet_card_at(event.position.x, screen_size)
				if idx >= 0 and idx < _fleet.ships.size() and _is_ship_available(idx, _fleet.ships[idx]):
					fleet_ship_selected.emit(idx)
				return true
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var card_step =EC.FLEET_CARD_W + EC.FLEET_CARD_GAP
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_fleet_scroll_offset = maxf(0.0, _fleet_scroll_offset - card_step)
				else:
					var total_w =card_step * _fleet.ships.size() - EC.FLEET_CARD_GAP
					var area_w =screen_size.x - 40 - 16
					var max_scroll =maxf(0.0, total_w - area_w)
					_fleet_scroll_offset = minf(max_scroll, _fleet_scroll_offset + card_step)
				queue_redraw()
				return true

	if event is InputEventMouseMotion:
		if event.position.y >= EC.FLEET_STRIP_TOP and event.position.y <= fleet_strip_bottom:
			var idx =_get_fleet_card_at(event.position.x, screen_size)
			if idx != _fleet_hovered_index:
				_fleet_hovered_index = idx
				queue_redraw()
		elif _fleet_hovered_index >= 0:
			_fleet_hovered_index = -1
			queue_redraw()

	return false


func handle_strip_hover(event: InputEvent, screen_size: Vector2) -> void:
	if not (event is InputEventMouseMotion):
		return
	var hover_strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var hover_viewer_w =screen_size.x * EC.VIEWER_RATIO
	if event.position.x < hover_viewer_w and event.position.y >= hover_strip_y and event.position.y <= hover_strip_y + EC.HP_STRIP_H:
		var new_hover =_get_strip_card_at(event.position, screen_size)
		if _current_tab == 0:
			if new_hover != _hp_hovered_index:
				_hp_hovered_index = new_hover
				queue_redraw()
		elif _current_tab == 1:
			if new_hover != _module_hovered_index:
				_module_hovered_index = new_hover
				queue_redraw()
	else:
		if _hp_hovered_index >= 0 or _module_hovered_index >= 0:
			_hp_hovered_index = -1
			_module_hovered_index = -1
			queue_redraw()


func handle_strip_click(event: InputEvent, screen_size: Vector2) -> bool:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return false

	match _current_tab:
		0: return _try_click_hp_strip(event.position, screen_size)
		1: return _try_click_module_strip(event.position, screen_size)
		2: return _try_click_shield_remove(event.position, screen_size)
		3: return _try_click_engine_remove(event.position, screen_size)
	return false


# =============================================================================
# DRAW — called from parent's _draw()
# =============================================================================
func draw_fleet_strip(parent: Control, font: Font, s: Vector2) -> void:
	if _is_station_mode or _fleet == null or _fleet.ships.is_empty():
		return

	var strip_rect =Rect2(20, EC.FLEET_STRIP_TOP, s.x - 40, EC.FLEET_STRIP_H)
	parent.draw_panel_bg(strip_rect)

	var ship_count = _fleet.ships.size()
	parent.draw_section_header(28, EC.FLEET_STRIP_TOP + 2, 120, "FLOTTE")
	parent.draw_string(font, Vector2(152, EC.FLEET_STRIP_TOP + 14),
		"%d vaisseau%s" % [ship_count, "x" if ship_count > 1 else ""],
		HORIZONTAL_ALIGNMENT_LEFT, 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	var cards_area_x =strip_rect.position.x + 8.0
	var cards_area_w =strip_rect.size.x - 16.0
	var card_step =EC.FLEET_CARD_W + EC.FLEET_CARD_GAP
	var total_cards_w =card_step * ship_count - EC.FLEET_CARD_GAP
	var card_y =EC.FLEET_STRIP_TOP + 20.0

	var base_x: float
	if total_cards_w <= cards_area_w:
		base_x = cards_area_x + (cards_area_w - total_cards_w) * 0.5
	else:
		base_x = cards_area_x - _fleet_scroll_offset

	var clip_left =cards_area_x
	var clip_right =cards_area_x + cards_area_w

	for i in ship_count:
		var cx =base_x + i * card_step
		if cx + EC.FLEET_CARD_W < clip_left or cx > clip_right:
			continue
		var fs = _fleet.ships[i]
		var sd =ShipRegistry.get_ship_data(fs.ship_id)
		_draw_fleet_card(parent, font, cx, card_y, i, fs, sd)

	if total_cards_w > cards_area_w:
		var arrow_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.6)
		if _fleet_scroll_offset > 0:
			var ax =cards_area_x + 2
			var ay =card_y + EC.FLEET_CARD_H * 0.5
			parent.draw_line(Vector2(ax + 8, ay - 8), Vector2(ax, ay), arrow_col, 2.0)
			parent.draw_line(Vector2(ax, ay), Vector2(ax + 8, ay + 8), arrow_col, 2.0)
		var max_scroll =total_cards_w - cards_area_w
		if _fleet_scroll_offset < max_scroll:
			var ax =clip_right - 10
			var ay =card_y + EC.FLEET_CARD_H * 0.5
			parent.draw_line(Vector2(ax - 8, ay - 8), Vector2(ax, ay), arrow_col, 2.0)
			parent.draw_line(Vector2(ax, ay), Vector2(ax - 8, ay + 8), arrow_col, 2.0)


func draw_bottom_strip(parent: Control, font: Font, s: Vector2) -> void:
	match _current_tab:
		0: _draw_hardpoint_strip(parent, font, s)
		1: _draw_module_slot_strip(parent, font, s)
		2: _draw_shield_status_panel(parent, font, s)
		3: _draw_engine_status_panel(parent, font, s)


# =============================================================================
# FLEET CARD DRAW
# =============================================================================
func _draw_fleet_card(parent: Control, font: Font, cx: float, cy: float,
		index: int, fs, sd) -> void:
	var card_rect =Rect2(cx, cy, EC.FLEET_CARD_W, EC.FLEET_CARD_H)
	var is_selected =index == _fleet_index
	var is_hovered =index == _fleet_hovered_index
	var is_active =_fleet != null and index == _fleet.active_index
	var available =_is_ship_available(index, fs)

	if is_selected:
		var pulse =UITheme.get_pulse(1.0)
		var sel_a =lerpf(0.08, 0.2, pulse)
		parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
		parent.draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
		parent.draw_rect(Rect2(cx, cy, 3, EC.FLEET_CARD_H), UITheme.PRIMARY)
	elif not available:
		parent.draw_rect(card_rect, Color(0.02, 0.02, 0.04, 0.6))
		parent.draw_rect(card_rect, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.3), false, 1.0)
	elif is_hovered:
		parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
		parent.draw_rect(card_rect, UITheme.BORDER, false, 1.0)
	else:
		parent.draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
		parent.draw_rect(card_rect, UITheme.BORDER, false, 1.0)

	if sd == null:
		parent.draw_string(font, Vector2(cx + 6, cy + 14), String(fs.ship_id),
			HORIZONTAL_ALIGNMENT_LEFT, EC.FLEET_CARD_W - 12, UITheme.FONT_SIZE_BODY, UITheme.TEXT)
		return

	var display_name: String = fs.custom_name if fs.custom_name != "" else String(sd.ship_name)
	var name_col: Color
	if is_selected:
		name_col = UITheme.PRIMARY
	elif not available:
		name_col = UITheme.TEXT_DIM
	else:
		name_col = UITheme.TEXT
	parent.draw_string(font, Vector2(cx + 6, cy + 13), display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, EC.FLEET_CARD_W - 46, UITheme.FONT_SIZE_BODY, name_col)

	parent.draw_string(font, Vector2(cx + 6, cy + 25), String(sd.ship_class).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, 80, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Weapon dots
	var hp_count =sd.hardpoints.size()
	var dot_r =3.0
	var dot_spacing =9.0
	var dots_x =cx + EC.FLEET_CARD_W - 10 - hp_count * dot_spacing
	for i in hp_count:
		var dot_cx =dots_x + i * dot_spacing + dot_r
		var dot_cy =cy + 22.0
		var weapon_name: StringName = fs.weapons[i] if i < fs.weapons.size() else &""
		if weapon_name != &"":
			var w =WeaponRegistry.get_weapon(weapon_name)
			var wcol: Color = EC.TYPE_COLORS.get(w.weapon_type, UITheme.PRIMARY) if w else UITheme.PRIMARY
			parent.draw_circle(Vector2(dot_cx, dot_cy), dot_r, wcol)
		else:
			parent.draw_arc(Vector2(dot_cx, dot_cy), dot_r, 0, TAU, 8,
				Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.4), 1.0)

	# Hull bar
	var bar_x =cx + 6
	var bar_y =cy + 31
	var bar_w =EC.FLEET_CARD_W - 12
	var bar_h =3.0
	parent.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.15, 0.2, 0.5))
	var hull_ratio =clampf(sd.hull_hp / 5000.0, 0.05, 1.0)
	parent.draw_rect(Rect2(bar_x, bar_y, bar_w * hull_ratio, bar_h), UITheme.ACCENT)

	# Slot summary
	var equipped_w =0
	for wn in fs.weapons:
		if wn != &"":
			equipped_w += 1
	var has_shield =1 if fs.shield_name != &"" else 0
	var has_engine =1 if fs.engine_name != &"" else 0
	var equipped_m =0
	for mn in fs.modules:
		if mn != &"":
			equipped_m += 1
	var slot_str ="%d/%dW %dS %dE %d/%dM" % [equipped_w, hp_count, has_shield, has_engine, equipped_m, sd.module_slots.size()]
	parent.draw_string(font, Vector2(cx + 6, cy + 44), slot_str,
		HORIZONTAL_ALIGNMENT_LEFT, EC.FLEET_CARD_W - 12, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

	# Equipment fill bar
	var total_slots =hp_count + 1 + 1 + sd.module_slots.size()
	var filled_slots =equipped_w + has_shield + has_engine + equipped_m
	var fill_x =cx + 6
	var fill_y =cy + 50
	var fill_w =EC.FLEET_CARD_W - 12
	var fill_h =4.0
	parent.draw_rect(Rect2(fill_x, fill_y, fill_w, fill_h), Color(0.1, 0.15, 0.2, 0.5))
	if total_slots > 0:
		var fill_ratio =float(filled_slots) / float(total_slots)
		var fill_col =UITheme.PRIMARY if fill_ratio < 1.0 else UITheme.ACCENT
		parent.draw_rect(Rect2(fill_x, fill_y, fill_w * fill_ratio, fill_h), fill_col)

	# Status badge
	var badge_w =52.0
	var badge_h =13.0
	var badge_x =cx + EC.FLEET_CARD_W - badge_w - 4
	var badge_y =cy + EC.FLEET_CARD_H - badge_h - 4
	if is_active:
		badge_w = 36.0
		badge_x = cx + EC.FLEET_CARD_W - badge_w - 4
		var badge_col =UITheme.ACCENT
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(badge_x + 2, badge_y + 10), Locale.t("equip.status_active"),
			HORIZONTAL_ALIGNMENT_CENTER, badge_w - 4, UITheme.FONT_SIZE_TINY, badge_col)
	elif fs.deployment_state == FleetShip.DeploymentState.DEPLOYED:
		var badge_col =Color(0.2, 0.6, 1.0)
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(badge_x + 2, badge_y + 10), Locale.t("equip.status_deployed"),
			HORIZONTAL_ALIGNMENT_CENTER, badge_w - 4, UITheme.FONT_SIZE_TINY, badge_col)
	elif fs.deployment_state == FleetShip.DeploymentState.DESTROYED:
		var badge_col =Color(1.0, 0.3, 0.2)
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(badge_x + 2, badge_y + 10), Locale.t("equip.status_destroyed"),
			HORIZONTAL_ALIGNMENT_CENTER, badge_w - 4, UITheme.FONT_SIZE_TINY, badge_col)
	elif _current_station_id != "" and fs.docked_station_id != _current_station_id:
		var badge_col =UITheme.TEXT_DIM
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.1))
		parent.draw_rect(Rect2(badge_x, badge_y, badge_w, badge_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(badge_x + 2, badge_y + 10), Locale.t("equip.status_elsewhere"),
			HORIZONTAL_ALIGNMENT_CENTER, badge_w - 4, UITheme.FONT_SIZE_TINY, badge_col)


# =============================================================================
# HARDPOINT STRIP (tab 0)
# =============================================================================
func _draw_hardpoint_strip(parent: Control, font: Font, s: Vector2) -> void:
	if _adapter == null:
		return
	var viewer_w =s.x * EC.VIEWER_RATIO
	var strip_y =s.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)

	parent.draw_panel_bg(strip_rect)
	parent.draw_section_header(28, strip_y + 2, viewer_w - 56, "POINTS D'EMPORT")

	var hp_count: int = _adapter.get_hardpoint_count()
	if hp_count == 0:
		return

	var card_w =minf(140.0, (strip_rect.size.x - 16) / hp_count)
	var total_w =card_w * hp_count
	var start_x =strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y =strip_y + 20
	var card_h: float = EC.HP_STRIP_H - 24

	for i in hp_count:
		var slot_size: String = _adapter.get_hardpoint_slot_size(i)
		var is_turret: bool = _adapter.is_hardpoint_turret(i)
		var mounted: WeaponResource = _adapter.get_mounted_weapon(i)
		var card_x =start_x + i * card_w
		var card_rect =Rect2(card_x, card_y, card_w - 4, card_h)
		var is_selected =i == _selected_hardpoint
		var is_hovered =i == _hp_hovered_index

		if is_selected:
			var pulse =UITheme.get_pulse(1.0)
			var sel_a =lerpf(0.08, 0.2, pulse)
			parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
			parent.draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
			parent.draw_rect(Rect2(card_x, card_y, 3, card_h), UITheme.PRIMARY)
		elif is_hovered:
			parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
			parent.draw_rect(card_rect, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.7), false, 1.0)
		else:
			parent.draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
			parent.draw_rect(card_rect, UITheme.BORDER, false, 1.0)

		# Slot badge
		var badge_col =EC.get_slot_size_color(slot_size)
		var badge_text ="%s%d" % [slot_size, i + 1]
		var bdg_x =card_x + 6
		var bdg_y =card_y + 5
		var bdg_w =28.0
		var bdg_h =16.0
		parent.draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		parent.draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(bdg_x + 3, bdg_y + 12), badge_text,
			HORIZONTAL_ALIGNMENT_LEFT, bdg_w - 4, UITheme.FONT_SIZE_SMALL, badge_col)

		if is_turret:
			var turret_col =Color(EC.TYPE_COLORS[5].r, EC.TYPE_COLORS[5].g, EC.TYPE_COLORS[5].b, 0.7)
			parent.draw_string(font, Vector2(bdg_x + bdg_w + 4, bdg_y + 12), "TUR",
				HORIZONTAL_ALIGNMENT_LEFT, 30, UITheme.FONT_SIZE_TINY, turret_col)

		if mounted:
			# [X] remove button
			var xb_sz =18.0
			var xb_x =card_x + card_w - 4 - xb_sz - 4
			var xb_y =card_y + 4
			var xb_col =Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
			parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
			parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
			parent.draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
				HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)

			# Weapon name
			var type_col: Color = EC.TYPE_COLORS.get(mounted.weapon_type, UITheme.PRIMARY)
			parent.draw_string(font, Vector2(card_x + 8, card_y + 38), str(mounted.weapon_name),
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, UITheme.FONT_SIZE_BODY, type_col)

			# Type + DPS
			var stats_y =card_y + 54
			_draw_weapon_icon(parent, Vector2(card_x + 14, stats_y - 2), 5.0, mounted.weapon_type, type_col)
			var type_name: String = EC.TYPE_NAMES[mounted.weapon_type] if mounted.weapon_type < EC.TYPE_NAMES.size() else ""
			var dps =mounted.damage_per_hit * mounted.fire_rate
			parent.draw_string(font, Vector2(card_x + 24, stats_y), "%s  %.0f DPS" % [type_name, dps],
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 32, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		else:
			var empty_label = Locale.t("equip.turret") if is_turret else Locale.t("equip.empty")
			var empty_col =Color(EC.TYPE_COLORS[5].r, EC.TYPE_COLORS[5].g, EC.TYPE_COLORS[5].b, 0.4) if is_turret else UITheme.TEXT_DIM
			parent.draw_string(font, Vector2(card_x, card_y + card_h * 0.5 + 6), empty_label,
				HORIZONTAL_ALIGNMENT_CENTER, card_w - 4, UITheme.FONT_SIZE_BODY, empty_col)


# =============================================================================
# MODULE SLOT STRIP (tab 1)
# =============================================================================
func _draw_module_slot_strip(parent: Control, font: Font, s: Vector2) -> void:
	if _adapter == null:
		return
	var viewer_w =s.x * EC.VIEWER_RATIO
	var strip_y =s.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)

	parent.draw_panel_bg(strip_rect)
	parent.draw_section_header(28, strip_y + 2, viewer_w - 56, "SLOTS MODULES")

	var slot_count: int = _adapter.get_module_slot_count()
	if slot_count == 0:
		return

	var card_w =minf(160.0, (strip_rect.size.x - 16) / slot_count)
	var total_w =card_w * slot_count
	var start_x =strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y =strip_y + 20
	var card_h: float = EC.HP_STRIP_H - 24

	for i in slot_count:
		var slot_size: String = _adapter.get_module_slot_size(i)
		var mod: ModuleResource = _adapter.get_equipped_module(i)
		var card_x =start_x + i * card_w
		var card_rect =Rect2(card_x, card_y, card_w - 4, card_h)
		var is_selected =i == _selected_module_slot
		var is_hovered =i == _module_hovered_index

		if is_selected:
			var pulse =UITheme.get_pulse(1.0)
			var sel_a =lerpf(0.08, 0.2, pulse)
			parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, sel_a))
			parent.draw_rect(card_rect, UITheme.BORDER_ACTIVE, false, 1.5)
			parent.draw_rect(Rect2(card_x, card_y, 3, card_h), UITheme.PRIMARY)
		elif is_hovered:
			parent.draw_rect(card_rect, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
			parent.draw_rect(card_rect, Color(UITheme.BORDER.r, UITheme.BORDER.g, UITheme.BORDER.b, 0.7), false, 1.0)
		else:
			parent.draw_rect(card_rect, Color(0, 0.02, 0.05, 0.3))
			parent.draw_rect(card_rect, UITheme.BORDER, false, 1.0)

		var badge_col =EC.get_slot_size_color(slot_size)
		var bdg_x =card_x + 6
		var bdg_y =card_y + 5
		var bdg_w =28.0
		var bdg_h =16.0
		parent.draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), Color(badge_col.r, badge_col.g, badge_col.b, 0.15))
		parent.draw_rect(Rect2(bdg_x, bdg_y, bdg_w, bdg_h), badge_col, false, 1.0)
		parent.draw_string(font, Vector2(bdg_x + 3, bdg_y + 12), "%s%d" % [slot_size, i + 1],
			HORIZONTAL_ALIGNMENT_LEFT, bdg_w - 4, UITheme.FONT_SIZE_SMALL, badge_col)

		if mod:
			var mod_col: Color = EC.MODULE_COLORS.get(mod.module_type, UITheme.PRIMARY)

			var xb_sz =18.0
			var xb_x =card_x + card_w - 4 - xb_sz - 4
			var xb_y =card_y + 4
			var xb_col =Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
			parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
			parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
			parent.draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
				HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)

			parent.draw_string(font, Vector2(card_x + 8, card_y + 38), str(mod.module_name),
				HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, UITheme.FONT_SIZE_BODY, mod_col)

			var bonuses =mod.get_bonuses_text()
			if bonuses.size() > 0:
				parent.draw_string(font, Vector2(card_x + 8, card_y + 54), bonuses[0],
					HORIZONTAL_ALIGNMENT_LEFT, card_w - 16, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
		else:
			parent.draw_string(font, Vector2(card_x, card_y + card_h * 0.5 + 6), Locale.t("equip.empty"),
				HORIZONTAL_ALIGNMENT_CENTER, card_w - 4, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# SHIELD STATUS PANEL (tab 2)
# =============================================================================
func _draw_shield_status_panel(parent: Control, font: Font, s: Vector2) -> void:
	var viewer_w =s.x * EC.VIEWER_RATIO
	var strip_y =s.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)

	parent.draw_panel_bg(strip_rect)
	parent.draw_section_header(28, strip_y + 2, viewer_w - 56, "BOUCLIER EQUIPE")

	if _adapter == null:
		return

	var y =strip_y + 24
	var sh: ShieldResource = _adapter.get_equipped_shield()
	if sh:
		parent.draw_string(font, Vector2(32, y + 10), str(sh.shield_name),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w * 0.5, UITheme.FONT_SIZE_BODY, EC.SHIELD_COLOR)

		var slot_str: String = ["S", "M", "L"][sh.slot_size]
		var bdg_col =EC.get_slot_size_color(slot_str)
		var bdg_x =32.0 + font.get_string_size(str(sh.shield_name), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY).x + 8
		bdg_x = minf(bdg_x, viewer_w * 0.45)
		parent.draw_rect(Rect2(bdg_x, y + 1, 22, 14), Color(bdg_col.r, bdg_col.g, bdg_col.b, 0.15))
		parent.draw_rect(Rect2(bdg_x, y + 1, 22, 14), bdg_col, false, 1.0)
		parent.draw_string(font, Vector2(bdg_x + 5, y + 12), slot_str,
			HORIZONTAL_ALIGNMENT_LEFT, 16, UITheme.FONT_SIZE_SMALL, bdg_col)

		parent.draw_string(font, Vector2(32, y + 30),
			"%d HP/face  |  %.0f HP/s regen  |  %.1fs delai  |  %.0f%% infiltration" % [
				int(sh.shield_hp_per_facing), sh.regen_rate, sh.regen_delay, sh.bleedthrough * 100],
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		var xb_sz =18.0
		var xb_x =viewer_w - 52
		var xb_y =y + 1
		var xb_col =Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
		parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
		parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
		parent.draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
			HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)
	else:
		parent.draw_string(font, Vector2(32, y + 20), Locale.t("equip.no_shield"),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 60, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# ENGINE STATUS PANEL (tab 3)
# =============================================================================
func _draw_engine_status_panel(parent: Control, font: Font, s: Vector2) -> void:
	var viewer_w =s.x * EC.VIEWER_RATIO
	var strip_y =s.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)

	parent.draw_panel_bg(strip_rect)
	parent.draw_section_header(28, strip_y + 2, viewer_w - 56, "MOTEUR EQUIPE")

	if _adapter == null:
		return

	var y =strip_y + 24
	var en: EngineResource = _adapter.get_equipped_engine()
	if en:
		parent.draw_string(font, Vector2(32, y + 10), str(en.engine_name),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w * 0.5, UITheme.FONT_SIZE_BODY, EC.ENGINE_COLOR)

		var slot_str: String = ["S", "M", "L"][en.slot_size]
		var bdg_col =EC.get_slot_size_color(slot_str)
		var bdg_x =32.0 + font.get_string_size(str(en.engine_name), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY).x + 8
		bdg_x = minf(bdg_x, viewer_w * 0.45)
		parent.draw_rect(Rect2(bdg_x, y + 1, 22, 14), Color(bdg_col.r, bdg_col.g, bdg_col.b, 0.15))
		parent.draw_rect(Rect2(bdg_x, y + 1, 22, 14), bdg_col, false, 1.0)
		parent.draw_string(font, Vector2(bdg_x + 5, y + 12), slot_str,
			HORIZONTAL_ALIGNMENT_LEFT, 16, UITheme.FONT_SIZE_SMALL, bdg_col)

		parent.draw_string(font, Vector2(32, y + 30),
			"Accel x%.2f  |  Vitesse x%.2f  |  Rotation x%.2f  |  Cruise x%.2f" % [
				en.accel_mult, en.speed_mult, en.rotation_mult, en.cruise_mult],
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 100, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)

		var xb_sz =18.0
		var xb_x =viewer_w - 52
		var xb_y =y + 1
		var xb_col =Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.6)
		parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), Color(0, 0, 0, 0.3))
		parent.draw_rect(Rect2(xb_x, xb_y, xb_sz, xb_sz), xb_col, false, 1.0)
		parent.draw_string(font, Vector2(xb_x + 3, xb_y + 13), "X",
			HORIZONTAL_ALIGNMENT_LEFT, 14, UITheme.FONT_SIZE_SMALL, xb_col)
	else:
		parent.draw_string(font, Vector2(32, y + 20), Locale.t("equip.no_engine"),
			HORIZONTAL_ALIGNMENT_LEFT, viewer_w - 60, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)


# =============================================================================
# HIT-TESTING HELPERS
# =============================================================================
func _try_click_hp_strip(mouse_pos: Vector2, screen_size: Vector2) -> bool:
	if _adapter == null:
		return false
	var viewer_w =screen_size.x * EC.VIEWER_RATIO
	var strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)
	if not strip_rect.has_point(mouse_pos):
		return false

	var hp_count: int = _adapter.get_hardpoint_count()
	if hp_count == 0:
		return false

	var card_w =minf(140.0, (strip_rect.size.x - 16) / hp_count)
	var total_w =card_w * hp_count
	var start_x =strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y =strip_rect.position.y + 20

	for i in hp_count:
		var card_x =start_x + i * card_w
		var card_rect =Rect2(card_x, card_y, card_w - 4, EC.HP_STRIP_H - 24)
		if card_rect.has_point(mouse_pos):
			if _adapter.get_mounted_weapon(i) != null:
				var xb_sz =18.0
				var xb_rect =Rect2(card_x + card_w - 4 - xb_sz - 4, card_y + 4, xb_sz, xb_sz)
				if xb_rect.has_point(mouse_pos):
					weapon_remove_requested.emit(i)
					return true
			hardpoint_clicked.emit(i)
			return true
	return false


func _try_click_module_strip(mouse_pos: Vector2, screen_size: Vector2) -> bool:
	if _adapter == null:
		return false
	var viewer_w =screen_size.x * EC.VIEWER_RATIO
	var strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var strip_rect =Rect2(20, strip_y, viewer_w - 40, EC.HP_STRIP_H)
	if not strip_rect.has_point(mouse_pos):
		return false

	var slot_count: int = _adapter.get_module_slot_count()
	if slot_count == 0:
		return false

	var card_w =minf(160.0, (strip_rect.size.x - 16) / slot_count)
	var total_w =card_w * slot_count
	var start_x =strip_rect.position.x + (strip_rect.size.x - total_w) * 0.5
	var card_y =strip_rect.position.y + 20

	for i in slot_count:
		var card_x =start_x + i * card_w
		var card_rect =Rect2(card_x, card_y, card_w - 4, EC.HP_STRIP_H - 24)
		if card_rect.has_point(mouse_pos):
			var mod: ModuleResource = _adapter.get_equipped_module(i)
			if mod:
				var xb_sz =18.0
				var xb_rect =Rect2(card_x + card_w - 4 - xb_sz - 4, card_y + 4, xb_sz, xb_sz)
				if xb_rect.has_point(mouse_pos):
					module_remove_requested.emit(i)
					return true
			module_slot_clicked.emit(i)
			return true
	return false


func _try_click_shield_remove(mouse_pos: Vector2, screen_size: Vector2) -> bool:
	if _adapter == null or _adapter.get_equipped_shield() == null:
		return false
	var viewer_w =screen_size.x * EC.VIEWER_RATIO
	var strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var y =strip_y + 24
	var xb_rect =Rect2(viewer_w - 52, y + 1, 18, 18)
	if xb_rect.has_point(mouse_pos):
		shield_remove_requested.emit()
		return true
	return false


func _try_click_engine_remove(mouse_pos: Vector2, screen_size: Vector2) -> bool:
	if _adapter == null or _adapter.get_equipped_engine() == null:
		return false
	var viewer_w =screen_size.x * EC.VIEWER_RATIO
	var strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var y =strip_y + 24
	var xb_rect =Rect2(viewer_w - 52, y + 1, 18, 18)
	if xb_rect.has_point(mouse_pos):
		engine_remove_requested.emit()
		return true
	return false


func _get_fleet_card_at(mouse_x: float, screen_size: Vector2) -> int:
	if _fleet == null or _fleet.ships.is_empty():
		return -1
	var cards_area_x =28.0
	var cards_area_w =screen_size.x - 40 - 16
	var card_step =EC.FLEET_CARD_W + EC.FLEET_CARD_GAP
	var total_cards_w =card_step * _fleet.ships.size() - EC.FLEET_CARD_GAP

	var base_x: float
	if total_cards_w <= cards_area_w:
		base_x = cards_area_x + (cards_area_w - total_cards_w) * 0.5
	else:
		base_x = cards_area_x - _fleet_scroll_offset

	for i in _fleet.ships.size():
		var cx =base_x + i * card_step
		if mouse_x >= cx and mouse_x <= cx + EC.FLEET_CARD_W:
			return i
	return -1


func _get_strip_card_at(mouse_pos: Vector2, screen_size: Vector2) -> int:
	if _adapter == null:
		return -1
	var viewer_w =screen_size.x * EC.VIEWER_RATIO
	var strip_y =screen_size.y - EC.HP_STRIP_H - 50
	var strip_w =viewer_w - 40
	var count: int = 0
	var max_cw: float = 140.0
	if _current_tab == 0:
		count = _adapter.get_hardpoint_count()
	elif _current_tab == 1:
		count = _adapter.get_module_slot_count()
		max_cw = 160.0
	if count == 0:
		return -1
	var card_w =minf(max_cw, (strip_w - 16) / count)
	var total_w =card_w * count
	var start_x =20.0 + (strip_w - total_w) * 0.5
	var card_y =strip_y + 20
	var card_h: float = EC.HP_STRIP_H - 24
	for i in count:
		var cx =start_x + i * card_w
		if Rect2(cx, card_y, card_w - 4, card_h).has_point(mouse_pos):
			return i
	return -1


# =============================================================================
# WEAPON ICON (used in hardpoint strip cards)
# =============================================================================
func _draw_weapon_icon(parent: Control, center: Vector2, r: float, weapon_type: int, col: Color) -> void:
	match weapon_type:
		0:
			parent.draw_line(center + Vector2(-r, -r * 0.6), center + Vector2(r, 0), col, 1.5)
			parent.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 1.5)
			parent.draw_line(center + Vector2(-r, r * 0.6), center + Vector2(r, 0), col, 1.5)
			parent.draw_circle(center + Vector2(r, 0), 2.0, col)
		1:
			parent.draw_circle(center, r * 0.65, Color(col.r, col.g, col.b, 0.4))
			parent.draw_arc(center, r * 0.65, 0, TAU, 12, col, 1.5)
			parent.draw_circle(center, r * 0.25, col)
		2:
			var pts =PackedVector2Array([
				center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.5),
				center + Vector2(-r * 0.3, 0), center + Vector2(-r * 0.5, r * 0.5),
			])
			parent.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.4))
			pts.append(pts[0])
			parent.draw_polyline(pts, col, 1.5)
		3:
			parent.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 2.0)
			parent.draw_circle(center + Vector2(-r, 0), 2.5, col)
			parent.draw_circle(center + Vector2(r, 0), 2.5, col)
		4:
			parent.draw_arc(center, r * 0.45, 0, TAU, 12, col, 1.5)
			for spike_i in 6:
				var angle =TAU * spike_i / 6.0
				var inner_pt =center + Vector2(cos(angle), sin(angle)) * r * 0.45
				var outer_pt =center + Vector2(cos(angle), sin(angle)) * r * 0.9
				parent.draw_line(inner_pt, outer_pt, col, 1.5)
				parent.draw_circle(outer_pt, 1.5, col)
		5:
			parent.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), Color(col.r, col.g, col.b, 0.4))
			parent.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), col, false, 1.5)
			parent.draw_line(center + Vector2(0, 0), center + Vector2(0, -r * 0.6), col, 1.5)
			parent.draw_circle(center + Vector2(0, -r * 0.6), r * 0.25, col)
