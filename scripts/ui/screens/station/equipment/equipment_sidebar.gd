class_name EquipmentSidebar
extends Control

# =============================================================================
# Equipment Screen — Arsenal List + Comparison Panel + Procedural Icons
# =============================================================================

signal arsenal_selected(item_name: StringName)
signal arsenal_double_clicked(item_name: StringName)

const EC =preload("res://scripts/ui/screens/station/equipment/equipment_constants.gd")

# --- State ---
var _adapter: RefCounted = null
var _inventory = null
var _arsenal_list: UIScrollList = null
var _arsenal_items: Array[StringName] = []
var _current_tab: int = 0
var _selected_hardpoint: int = -1
var _selected_module_slot: int = -1
var _showing_missiles: bool = false


func _ready() -> void:
	_arsenal_list = UIScrollList.new()
	_arsenal_list.row_height = EC.ARSENAL_ROW_H
	_arsenal_list.item_draw_callback = _draw_arsenal_row
	_arsenal_list.item_selected.connect(_on_arsenal_selected)
	_arsenal_list.item_double_clicked.connect(_on_arsenal_double_clicked)
	_arsenal_list.visible = false
	add_child(_arsenal_list)


func setup(adapter: RefCounted, inventory) -> void:
	_adapter = adapter
	_inventory = inventory


func set_tab(tab: int) -> void:
	_current_tab = tab
	_arsenal_list.selected_index = -1
	refresh()


func set_selected_hardpoint(idx: int) -> void:
	_selected_hardpoint = idx
	_arsenal_list.selected_index = -1
	refresh()


func set_selected_module_slot(idx: int) -> void:
	_selected_module_slot = idx
	_arsenal_list.selected_index = -1
	refresh()


func get_selected_item() -> StringName:
	var idx =_arsenal_list.selected_index
	if idx >= 0 and idx < _arsenal_items.size():
		return _arsenal_items[idx]
	return &""


func get_selected_hardpoint() -> int:
	return _selected_hardpoint


func get_selected_module_slot() -> int:
	return _selected_module_slot


func refresh() -> void:
	_refresh_arsenal()
	queue_redraw()


func show_list() -> void:
	_arsenal_list.visible = true


func hide_list() -> void:
	_arsenal_list.visible = false


func layout_list(pos: Vector2, sz: Vector2) -> void:
	_arsenal_list.position = pos
	_arsenal_list.size = sz


# =============================================================================
# ARSENAL REFRESH
# =============================================================================
func _refresh_arsenal() -> void:
	_arsenal_items.clear()
	if _inventory == null:
		_arsenal_list.items = []
		_arsenal_list.queue_redraw()
		return

	_showing_missiles = false
	match _current_tab:
		0:
			if _selected_hardpoint >= 0 and _adapter:
				var mounted: WeaponResource = _adapter.get_mounted_weapon(_selected_hardpoint)
				if mounted and mounted.weapon_type == WeaponResource.WeaponType.MISSILE:
					_showing_missiles = true
					_arsenal_items = _inventory.get_ammo_for_launcher_size(mounted.compatible_missile_size)
				else:
					var hp_sz: String = _adapter.get_hardpoint_slot_size(_selected_hardpoint)
					var hp_turret: bool = _adapter.is_hardpoint_turret(_selected_hardpoint)
					_arsenal_items = _inventory.get_weapons_for_slot(hp_sz, hp_turret)
			else:
				_arsenal_items = _inventory.get_all_weapons()
		1:
			if _selected_module_slot >= 0 and _adapter:
				var slot_sz: String = _adapter.get_module_slot_size(_selected_module_slot)
				_arsenal_items = _inventory.get_modules_for_slot(slot_sz)
			else:
				_arsenal_items = _inventory.get_all_modules()
		2:
			if _adapter:
				_arsenal_items = _inventory.get_shields_for_slot(_adapter.get_shield_slot_size())
			else:
				_arsenal_items = _inventory.get_all_shields()
		3:
			if _adapter:
				_arsenal_items = _inventory.get_engines_for_slot(_adapter.get_engine_slot_size())
			else:
				_arsenal_items = _inventory.get_all_engines()

	var list_items: Array = []
	for item_name in _arsenal_items:
		list_items.append(item_name)
	_arsenal_list.items = list_items
	_arsenal_list.selected_index = -1
	_arsenal_list._scroll_offset = 0.0
	_arsenal_list.queue_redraw()


# =============================================================================
# ARSENAL ROW CALLBACKS
# =============================================================================
func _draw_arsenal_row(ctrl: Control, index: int, rect: Rect2, _item: Variant) -> void:
	if index < 0 or index >= _arsenal_items.size():
		return
	match _current_tab:
		0:
			if _showing_missiles:
				_draw_missile_ammo_row(ctrl, index, rect)
			else:
				_draw_weapon_row(ctrl, index, rect)
		1: _draw_module_row(ctrl, index, rect)
		2: _draw_shield_row(ctrl, index, rect)
		3: _draw_engine_row(ctrl, index, rect)


func _draw_weapon_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var weapon_name: StringName = _arsenal_items[index]
	var weapon =WeaponRegistry.get_weapon(weapon_name)
	if weapon == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = _inventory.get_weapon_count(weapon_name) if _inventory else 0
	var slot_size_str: String = ["S", "M", "L"][weapon.slot_size]
	var compatible =true
	if _selected_hardpoint >= 0 and _adapter:
		var hp_sz: String = _adapter.get_hardpoint_slot_size(_selected_hardpoint)
		var hp_turret: bool = _adapter.is_hardpoint_turret(_selected_hardpoint)
		compatible = _inventory.is_compatible(weapon_name, hp_sz, hp_turret) if _inventory else false

	var alpha_mult: float = 1.0 if compatible else 0.3
	var type_col: Color = EC.TYPE_COLORS.get(weapon.weapon_type, UITheme.PRIMARY)
	if not compatible:
		type_col = Color(type_col.r, type_col.g, type_col.b, 0.3)

	var icon_cx =rect.position.x + 24.0
	var icon_cy =rect.position.y + rect.size.y * 0.5
	var icon_r =16.0
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.15 * alpha_mult), icon_r * 0.7)
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(type_col.r, type_col.g, type_col.b, 0.6 * alpha_mult), 1.5)
	_draw_weapon_icon_on(ctrl, Vector2(icon_cx, icon_cy), 8.0, weapon.weapon_type,
		Color(type_col.r, type_col.g, type_col.b, alpha_mult))

	var text_col =Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x =rect.position.x + 48
	var name_max_w =rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(weapon_name),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col =Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var dps =weapon.damage_per_hit * weapon.fire_rate
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38), "%.0f DPS" % dps,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_shield_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var sn: StringName = _arsenal_items[index]
	var shield =ShieldRegistry.get_shield(sn)
	if shield == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = _inventory.get_shield_count(sn) if _inventory else 0
	var slot_size_str: String = ["S", "M", "L"][shield.slot_size]
	var compatible =true
	if _adapter:
		compatible = _inventory.is_shield_compatible(sn, _adapter.get_shield_slot_size()) if _inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var col =Color(EC.SHIELD_COLOR.r, EC.SHIELD_COLOR.g, EC.SHIELD_COLOR.b, alpha_mult)

	var icon_cx =rect.position.x + 24.0
	var icon_cy =rect.position.y + rect.size.y * 0.5
	_draw_shield_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col =Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x =rect.position.x + 48
	var name_max_w =rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(sn),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col =Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38),
		"%d HP/f, %.0f HP/s" % [int(shield.shield_hp_per_facing), shield.regen_rate],
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_engine_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var en: StringName = _arsenal_items[index]
	var engine =EngineRegistry.get_engine(en)
	if engine == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = _inventory.get_engine_count(en) if _inventory else 0
	var slot_size_str: String = ["S", "M", "L"][engine.slot_size]
	var compatible =true
	if _adapter:
		compatible = _inventory.is_engine_compatible(en, _adapter.get_engine_slot_size()) if _inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var col =Color(EC.ENGINE_COLOR.r, EC.ENGINE_COLOR.g, EC.ENGINE_COLOR.b, alpha_mult)

	var icon_cx =rect.position.x + 24.0
	var icon_cy =rect.position.y + rect.size.y * 0.5
	_draw_engine_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col =Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x =rect.position.x + 48
	var name_max_w =rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(en),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col =Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var best_stat =EC.get_engine_best_stat(engine)
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38), best_stat,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_module_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var mn: StringName = _arsenal_items[index]
	var module =ModuleRegistry.get_module(mn)
	if module == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = _inventory.get_module_count(mn) if _inventory else 0
	var slot_size_str: String = ["S", "M", "L"][module.slot_size]
	var compatible =true
	if _selected_module_slot >= 0 and _adapter:
		var slot_sz: String = _adapter.get_module_slot_size(_selected_module_slot)
		compatible = _inventory.is_module_compatible(mn, slot_sz) if _inventory else false
	var alpha_mult: float = 1.0 if compatible else 0.3
	var mod_col: Color = EC.MODULE_COLORS.get(module.module_type, UITheme.PRIMARY)
	var col =Color(mod_col.r, mod_col.g, mod_col.b, alpha_mult)

	var icon_cx =rect.position.x + 24.0
	var icon_cy =rect.position.y + rect.size.y * 0.5
	_draw_module_icon_on(ctrl, Vector2(icon_cx, icon_cy), 14.0, col)

	var text_col =Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, alpha_mult)
	var name_x =rect.position.x + 48
	var name_max_w =rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(mn),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, text_col)

	var dim_col =Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7 * alpha_mult)
	var bonuses =module.get_bonuses_text()
	var bonus_str =bonuses[0] if bonuses.size() > 0 else ""
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38), bonus_str,
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, slot_size_str, compatible, alpha_mult)


func _draw_missile_ammo_row(ctrl: Control, index: int, rect: Rect2) -> void:
	var missile_name: StringName = _arsenal_items[index]
	var missile = MissileRegistry.get_missile(missile_name)
	if missile == null:
		return
	var font: Font = UITheme.get_font()
	var count: int = _inventory.get_ammo_count(missile_name) if _inventory else 0
	var size_str: String = ["S", "M", "L"][missile.missile_size]
	var col: Color = UITheme.DANGER

	# Missile icon
	var icon_cx: float = rect.position.x + 24.0
	var icon_cy: float = rect.position.y + rect.size.y * 0.5
	var icon_r: float = 16.0
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(col.r, col.g, col.b, 0.15), icon_r * 0.7)
	ctrl.draw_arc(Vector2(icon_cx, icon_cy), icon_r, 0, TAU, 20,
		Color(col.r, col.g, col.b, 0.6), 1.5)
	var r: float = 8.0
	ctrl.draw_line(Vector2(icon_cx, icon_cy - r), Vector2(icon_cx, icon_cy + r * 0.6), col, 1.5)
	ctrl.draw_line(Vector2(icon_cx, icon_cy - r), Vector2(icon_cx - r * 0.3, icon_cy - r * 0.5), col, 1.0)
	ctrl.draw_line(Vector2(icon_cx, icon_cy - r), Vector2(icon_cx + r * 0.3, icon_cy - r * 0.5), col, 1.0)
	ctrl.draw_line(Vector2(icon_cx - r * 0.4, icon_cy + r * 0.6), Vector2(icon_cx, icon_cy + r * 0.3), col, 1.0)
	ctrl.draw_line(Vector2(icon_cx + r * 0.4, icon_cy + r * 0.6), Vector2(icon_cx, icon_cy + r * 0.3), col, 1.0)

	# Name
	var name_x: float = rect.position.x + 48
	var name_max_w: float = rect.size.x - 48 - 90
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 22), str(missile_name),
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# Stats
	var cat_names: Array = ["Guide", "Dumbfire", "Torpille"]
	var cat_str: String = cat_names[missile.missile_category] if missile.missile_category < cat_names.size() else ""
	var dim_col: Color = Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.7)
	ctrl.draw_string(font, Vector2(name_x, rect.position.y + 38),
		"%s  %.0f DMG" % [cat_str, missile.damage_per_hit],
		HORIZONTAL_ALIGNMENT_LEFT, name_max_w, UITheme.FONT_SIZE_SMALL, dim_col)

	_draw_qty_and_size_badges(ctrl, font, rect, count, size_str, true, 1.0)


# =============================================================================
# BADGE DRAWING
# =============================================================================
func _draw_qty_and_size_badges(ctrl: Control, font: Font, rect: Rect2,
		count: int, slot_size_str: String, compatible: bool, alpha_mult: float) -> void:
	var qty_x =rect.position.x + rect.size.x - 80
	var qty_y =rect.position.y + (rect.size.y - 20) * 0.5
	var qty_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.8 * alpha_mult)
	ctrl.draw_rect(Rect2(qty_x, qty_y, 32, 20), Color(qty_col.r, qty_col.g, qty_col.b, 0.1))
	ctrl.draw_rect(Rect2(qty_x, qty_y, 32, 20), Color(qty_col.r, qty_col.g, qty_col.b, 0.4), false, 1.0)
	ctrl.draw_string(font, Vector2(qty_x + 2, qty_y + 15), "x%d" % count,
		HORIZONTAL_ALIGNMENT_CENTER, 28, UITheme.FONT_SIZE_BODY, qty_col)

	var badge_col =EC.get_slot_size_color(slot_size_str)
	if not compatible:
		badge_col = Color(badge_col.r, badge_col.g, badge_col.b, 0.3)
	var badge_x =rect.position.x + rect.size.x - 40
	var badge_y =rect.position.y + (rect.size.y - EC.SIZE_BADGE_H) * 0.5
	ctrl.draw_rect(Rect2(badge_x, badge_y, EC.SIZE_BADGE_W, EC.SIZE_BADGE_H),
		Color(badge_col.r, badge_col.g, badge_col.b, 0.12))
	ctrl.draw_rect(Rect2(badge_x, badge_y, EC.SIZE_BADGE_W, EC.SIZE_BADGE_H), badge_col, false, 1.0)
	ctrl.draw_string(font, Vector2(badge_x + 5, badge_y + 16), slot_size_str,
		HORIZONTAL_ALIGNMENT_LEFT, EC.SIZE_BADGE_W, UITheme.FONT_SIZE_BODY, badge_col)

	if not compatible:
		var lock_x =rect.end.x - 16
		var lock_y =rect.position.y + rect.size.y * 0.5
		ctrl.draw_rect(Rect2(lock_x - 5, lock_y - 2, 10, 8),
			Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5))
		ctrl.draw_arc(Vector2(lock_x, lock_y - 4), 4.0, PI, TAU, 8,
			Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)


# =============================================================================
# COMPARISON PANEL — called from parent's _draw()
# =============================================================================
func draw_comparison(parent: Control, font: Font, px: float, start_y: float, pw: float,
		selected_weapon: StringName, selected_shield: StringName,
		selected_engine: StringName, selected_module: StringName) -> void:
	match _current_tab:
		0: _draw_weapon_comparison(parent, font, px, start_y, pw, selected_weapon)
		1: _draw_module_comparison(parent, font, px, start_y, pw, selected_module)
		2: _draw_shield_comparison(parent, font, px, start_y, pw, selected_shield)
		3: _draw_engine_comparison(parent, font, px, start_y, pw, selected_engine)


func _draw_no_selection_msg(parent: Control, font: Font, px: float, start_y: float, pw: float, msg: String) -> void:
	var center_x =px + pw * 0.5
	var center_y =start_y + 40
	var cr =14.0
	parent.draw_arc(Vector2(center_x, center_y), cr, 0, TAU, 24, UITheme.TEXT_DIM, 1.0)
	parent.draw_line(Vector2(center_x - cr - 5, center_y), Vector2(center_x - cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
	parent.draw_line(Vector2(center_x + cr - 5, center_y), Vector2(center_x + cr + 5, center_y), UITheme.TEXT_DIM, 1.0)
	parent.draw_line(Vector2(center_x, center_y - cr - 5), Vector2(center_x, center_y - cr + 5), UITheme.TEXT_DIM, 1.0)
	parent.draw_line(Vector2(center_x, center_y + cr - 5), Vector2(center_x, center_y + cr + 5), UITheme.TEXT_DIM, 1.0)
	parent.draw_string(font, Vector2(px, center_y + 22), msg,
		HORIZONTAL_ALIGNMENT_CENTER, pw, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	parent.draw_string(font, Vector2(px, center_y + 38), Locale.t("equip.quick_equip"),
		HORIZONTAL_ALIGNMENT_CENTER, pw, UITheme.FONT_SIZE_TINY, Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.35))


func _draw_weapon_comparison(parent: Control, font: Font, px: float, start_y: float, pw: float, selected_weapon: StringName) -> void:
	if _selected_hardpoint < 0 or selected_weapon == &"":
		_draw_no_selection_msg(parent, font, px, start_y, pw, Locale.t("equip.select_weapon"))
		return

	var new_weapon =WeaponRegistry.get_weapon(selected_weapon)
	if new_weapon == null:
		return

	var current_weapon: WeaponResource = null
	if _adapter:
		current_weapon = _adapter.get_mounted_weapon(_selected_hardpoint)

	var cur_dmg =current_weapon.damage_per_hit if current_weapon else 0.0
	var new_dmg =new_weapon.damage_per_hit
	var cur_rate =current_weapon.fire_rate if current_weapon else 0.0
	var new_rate =new_weapon.fire_rate
	var cur_dps =cur_dmg * cur_rate
	var new_dps =new_dmg * new_rate
	var cur_energy =current_weapon.energy_cost_per_shot if current_weapon else 0.0
	var new_energy =new_weapon.energy_cost_per_shot
	var cur_range =(current_weapon.projectile_speed * current_weapon.projectile_lifetime) if current_weapon else 0.0
	var new_range =new_weapon.projectile_speed * new_weapon.projectile_lifetime

	var stats: Array = [
		["stat.damage", cur_dmg, new_dmg, true],
		["stat.fire_rate", cur_rate, new_rate, true],
		["stat.dps", cur_dps, new_dps, true],
		["stat.energy_cost", cur_energy, new_energy, false],
		["stat.range", cur_range, new_range, true],
	]
	_draw_stat_rows(parent, font, px, start_y, pw, stats)


func _draw_shield_comparison(parent: Control, font: Font, px: float, start_y: float, pw: float, selected_shield: StringName) -> void:
	if selected_shield == &"":
		_draw_no_selection_msg(parent, font, px, start_y, pw, Locale.t("equip.select_shield"))
		return

	var new_shield =ShieldRegistry.get_shield(selected_shield)
	if new_shield == null:
		return

	var cur: ShieldResource = _adapter.get_equipped_shield() if _adapter else null

	var stats: Array = [
		["stat.capacity", cur.shield_hp_per_facing if cur else 0.0, new_shield.shield_hp_per_facing, true],
		["stat.regen", cur.regen_rate if cur else 0.0, new_shield.regen_rate, true],
		["stat.delay", cur.regen_delay if cur else 0.0, new_shield.regen_delay, false],
		["stat.infiltration", (cur.bleedthrough * 100) if cur else 0.0, new_shield.bleedthrough * 100, false],
	]
	_draw_stat_rows(parent, font, px, start_y, pw, stats)


func _draw_engine_comparison(parent: Control, font: Font, px: float, start_y: float, pw: float, selected_engine: StringName) -> void:
	if selected_engine == &"":
		_draw_no_selection_msg(parent, font, px, start_y, pw, Locale.t("equip.select_engine"))
		return

	var new_engine =EngineRegistry.get_engine(selected_engine)
	if new_engine == null:
		return

	var cur: EngineResource = _adapter.get_equipped_engine() if _adapter else null

	var stats: Array = [
		["stat.acceleration", cur.accel_mult if cur else 1.0, new_engine.accel_mult, true],
		["stat.speed", cur.speed_mult if cur else 1.0, new_engine.speed_mult, true],
		["stat.cruise", cur.cruise_mult if cur else 1.0, new_engine.cruise_mult, true],
		["stat.rotation", cur.rotation_mult if cur else 1.0, new_engine.rotation_mult, true],
		["stat.boost_drain", cur.boost_drain_mult if cur else 1.0, new_engine.boost_drain_mult, false],
	]
	_draw_stat_rows(parent, font, px, start_y, pw, stats)


func _draw_module_comparison(parent: Control, font: Font, px: float, start_y: float, pw: float, selected_module: StringName) -> void:
	if _selected_module_slot < 0 or selected_module == &"":
		_draw_no_selection_msg(parent, font, px, start_y, pw, Locale.t("equip.select_slot"))
		return

	var new_mod =ModuleRegistry.get_module(selected_module)
	if new_mod == null:
		return

	var cur: ModuleResource = null
	if _adapter:
		cur = _adapter.get_equipped_module(_selected_module_slot)

	var stats: Array = []
	if new_mod.hull_bonus > 0 or (cur and cur.hull_bonus > 0):
		stats.append(["stat.hull", cur.hull_bonus if cur else 0.0, new_mod.hull_bonus, true])
	if new_mod.armor_bonus > 0 or (cur and cur.armor_bonus > 0):
		stats.append(["stat.armor", cur.armor_bonus if cur else 0.0, new_mod.armor_bonus, true])
	if new_mod.energy_cap_bonus > 0 or (cur and cur.energy_cap_bonus > 0):
		stats.append(["stat.energy_max", cur.energy_cap_bonus if cur else 0.0, new_mod.energy_cap_bonus, true])
	if new_mod.energy_regen_bonus > 0 or (cur and cur.energy_regen_bonus > 0):
		stats.append(["stat.energy_regen", cur.energy_regen_bonus if cur else 0.0, new_mod.energy_regen_bonus, true])
	if new_mod.shield_regen_mult != 1.0 or (cur and cur.shield_regen_mult != 1.0):
		stats.append(["stat.shield_regen", (cur.shield_regen_mult if cur else 1.0) * 100, new_mod.shield_regen_mult * 100, true])
	if new_mod.shield_cap_mult != 1.0 or (cur and cur.shield_cap_mult != 1.0):
		stats.append(["stat.shield_cap", (cur.shield_cap_mult if cur else 1.0) * 100, new_mod.shield_cap_mult * 100, true])
	if new_mod.weapon_energy_mult != 1.0 or (cur and cur.weapon_energy_mult != 1.0):
		stats.append(["stat.weapon_drain", (cur.weapon_energy_mult if cur else 1.0) * 100, new_mod.weapon_energy_mult * 100, false])
	if new_mod.weapon_range_mult != 1.0 or (cur and cur.weapon_range_mult != 1.0):
		stats.append(["stat.weapon_range", (cur.weapon_range_mult if cur else 1.0) * 100, new_mod.weapon_range_mult * 100, true])

	if stats.is_empty():
		_draw_no_selection_msg(parent, font, px, start_y, pw, Locale.t("equip.no_bonus"))
		return

	_draw_stat_rows(parent, font, px, start_y, pw, stats)


# =============================================================================
# STAT ROWS
# =============================================================================
func _draw_stat_rows(parent: Control, font: Font, px: float, start_y: float, pw: float, stats: Array) -> void:
	var row_h =24.0
	var label_x =px + 8
	var val_x =px + pw * 0.38
	var new_val_x =px + pw * 0.58
	var delta_x =px + pw - 8

	for row_i in stats.size():
		var stat: Array = stats[row_i]
		var label: String = stat[0]
		var cur_val: float = stat[1]
		var new_val: float = stat[2]
		var higher_better: bool = stat[3]
		var delta: float = new_val - cur_val
		var ry =start_y + row_i * row_h

		if row_i % 2 == 0:
			parent.draw_rect(Rect2(px + 4, ry - 4, pw - 8, row_h), Color(0, 0.02, 0.05, 0.15))

		var is_better: bool = (delta > 0.01 and higher_better) or (delta < -0.01 and not higher_better)
		var is_worse: bool = (delta > 0.01 and not higher_better) or (delta < -0.01 and higher_better)

		parent.draw_string(font, Vector2(label_x, ry + 10), Locale.t(label),
			HORIZONTAL_ALIGNMENT_LEFT, 90, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_DIM)
		parent.draw_string(font, Vector2(val_x, ry + 10), EC.format_stat(cur_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_LABEL, UITheme.TEXT)

		if absf(delta) > 0.01:
			var arr_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			parent.draw_string(font, Vector2(new_val_x - 12, ry + 10), ">",
				HORIZONTAL_ALIGNMENT_LEFT, 10, UITheme.FONT_SIZE_LABEL, arr_col)

		var new_text_col =UITheme.TEXT
		if is_better:
			new_text_col = UITheme.ACCENT
		elif is_worse:
			new_text_col = UITheme.DANGER
		parent.draw_string(font, Vector2(new_val_x, ry + 10), EC.format_stat(new_val, label),
			HORIZONTAL_ALIGNMENT_LEFT, 60, UITheme.FONT_SIZE_LABEL, new_text_col)

		if absf(delta) > 0.01:
			var delta_col: Color = UITheme.ACCENT if is_better else UITheme.DANGER
			var sign_str ="+" if delta > 0.0 else ""
			parent.draw_string(font, Vector2(delta_x - 60, ry + 10), sign_str + EC.format_stat(delta, label),
				HORIZONTAL_ALIGNMENT_RIGHT, 60, UITheme.FONT_SIZE_LABEL, delta_col)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_arsenal_selected(index: int) -> void:
	if index >= 0 and index < _arsenal_items.size():
		arsenal_selected.emit(_arsenal_items[index])
	else:
		arsenal_selected.emit(&"")


func _on_arsenal_double_clicked(index: int) -> void:
	if index >= 0 and index < _arsenal_items.size():
		arsenal_double_clicked.emit(_arsenal_items[index])


# =============================================================================
# PROCEDURAL ICONS
# =============================================================================
func _draw_weapon_icon_on(ctrl: Control, center: Vector2, r: float, weapon_type: int, col: Color) -> void:
	match weapon_type:
		0:
			ctrl.draw_line(center + Vector2(-r, -r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_line(center + Vector2(-r, r * 0.6), center + Vector2(r, 0), col, 1.5)
			ctrl.draw_circle(center + Vector2(r, 0), 2.0, col)
		1:
			ctrl.draw_circle(center, r * 0.65, Color(col.r, col.g, col.b, 0.4))
			ctrl.draw_arc(center, r * 0.65, 0, TAU, 12, col, 1.5)
			ctrl.draw_circle(center, r * 0.25, col)
		2:
			var pts =PackedVector2Array([
				center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.5),
				center + Vector2(-r * 0.3, 0), center + Vector2(-r * 0.5, r * 0.5),
			])
			ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.4))
			pts.append(pts[0])
			ctrl.draw_polyline(pts, col, 1.5)
		3:
			ctrl.draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 2.0)
			ctrl.draw_circle(center + Vector2(-r, 0), 2.5, col)
			ctrl.draw_circle(center + Vector2(r, 0), 2.5, col)
		4:
			ctrl.draw_arc(center, r * 0.45, 0, TAU, 12, col, 1.5)
			for spike_i in 6:
				var angle =TAU * spike_i / 6.0
				var inner_pt =center + Vector2(cos(angle), sin(angle)) * r * 0.45
				var outer_pt =center + Vector2(cos(angle), sin(angle)) * r * 0.9
				ctrl.draw_line(inner_pt, outer_pt, col, 1.5)
				ctrl.draw_circle(outer_pt, 1.5, col)
		5:
			ctrl.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), Color(col.r, col.g, col.b, 0.4))
			ctrl.draw_rect(Rect2(center.x - r * 0.4, center.y, r * 0.8, r * 0.5), col, false, 1.5)
			ctrl.draw_line(center + Vector2(0, 0), center + Vector2(0, -r * 0.6), col, 1.5)
			ctrl.draw_circle(center + Vector2(0, -r * 0.6), r * 0.25, col)


func _draw_shield_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	for seg in 6:
		var a1 =TAU * seg / 6.0 - PI / 6.0
		var a2 =TAU * (seg + 1) / 6.0 - PI / 6.0
		ctrl.draw_line(
			center + Vector2(cos(a1), sin(a1)) * r,
			center + Vector2(cos(a2), sin(a2)) * r,
			col, 1.5)
	ctrl.draw_arc(center, r * 0.5, -PI * 0.3, PI * 0.3, 8, col, 1.5)


func _draw_engine_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	var pts =PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r * 0.5, -r * 0.3),
		center + Vector2(r * 0.3, r * 0.5),
		center + Vector2(0, r * 0.2),
		center + Vector2(-r * 0.3, r * 0.5),
		center + Vector2(-r * 0.5, -r * 0.3),
	])
	ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5)
	ctrl.draw_line(center + Vector2(-r * 0.15, r * 0.5), center + Vector2(-r * 0.15, r), Color(col.r, col.g, col.b, 0.5), 1.0)
	ctrl.draw_line(center + Vector2(r * 0.15, r * 0.5), center + Vector2(r * 0.15, r), Color(col.r, col.g, col.b, 0.5), 1.0)


func _draw_module_icon_on(ctrl: Control, center: Vector2, r: float, col: Color) -> void:
	ctrl.draw_rect(Rect2(center.x - r * 0.6, center.y - r * 0.6, r * 1.2, r * 1.2),
		Color(col.r, col.g, col.b, 0.2))
	ctrl.draw_rect(Rect2(center.x - r * 0.6, center.y - r * 0.6, r * 1.2, r * 1.2), col, false, 1.5)
	for i in 3:
		var offset =(i - 1) * r * 0.35
		ctrl.draw_line(center + Vector2(-r * 0.6, offset), center + Vector2(-r, offset), col, 1.0)
		ctrl.draw_line(center + Vector2(r * 0.6, offset), center + Vector2(r, offset), col, 1.0)
	ctrl.draw_circle(center, r * 0.15, col)
