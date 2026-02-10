class_name HudWeaponPanel
extends Control

# =============================================================================
# HUD Weapon Panel — 3D holographic ship model with hardpoints + weapon list
# =============================================================================

var ship: ShipController = null
var weapon_manager: WeaponManager = null
var energy_system: EnergySystem = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _cached_hp_screen: Array[Vector2] = []
var _cached_wp_size: Vector2 = Vector2.ZERO

var _weapon_panel: Control = null

# 3D hologram viewer
var _vp_container: SubViewportContainer = null
var _vp: SubViewport = null
var _holo_camera: Camera3D = null
var _holo_model: ShipModel = null
var _holo_ship_ref: Node3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_weapon_panel = HudDrawHelpers.make_ctrl(0.5, 1.0, 0.5, 1.0, 140, -175, 390, -10)
	_weapon_panel.draw.connect(_draw_weapon_panel.bind(_weapon_panel))
	add_child(_weapon_panel)


func set_cockpit_mode(is_cockpit: bool) -> void:
	_weapon_panel.visible = not is_cockpit


func redraw_slow() -> void:
	_weapon_panel.queue_redraw()


func invalidate_cache() -> void:
	_cleanup_holo_viewer()
	_holo_ship_ref = null
	_cached_wp_size = Vector2.ZERO


# =============================================================================
# 3D HOLOGRAM VIEWER
# =============================================================================
func _setup_holo_viewer() -> void:
	_cleanup_holo_viewer()
	_holo_ship_ref = ship
	_cached_hp_screen = []
	_cached_wp_size = Vector2.ZERO
	if ship == null or ship.ship_data == null:
		return

	# SubViewportContainer — renders behind 2D markers
	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = false
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_container.show_behind_parent = true
	_weapon_panel.add_child(_vp_container)

	# SubViewport with its own isolated world
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_vp)

	# Environment — transparent background with subtle ambient
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.3, 0.5)
	env.ambient_light_energy = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_vp.add_child(world_env)

	# Key light — blue-cyan from above-left
	var dir_light := DirectionalLight3D.new()
	dir_light.light_color = Color(0.3, 0.6, 0.9)
	dir_light.light_energy = 1.5
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	_vp.add_child(dir_light)

	# Rim light — warm orange/amber from behind-right
	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(0.9, 0.6, 0.2)
	rim_light.light_energy = 1.0
	rim_light.omni_range = 50.0
	rim_light.position = Vector3(5, 3, -8)
	_vp.add_child(rim_light)

	# Camera — positioned from EquipmentCamera data or fallback
	_holo_camera = Camera3D.new()
	var cam_data := ShipFactory.get_equipment_camera_data(ship.ship_data.ship_id)
	if not cam_data.is_empty():
		_holo_camera.position = cam_data["position"]
		_holo_camera.transform.basis = cam_data["basis"]
		_holo_camera.fov = cam_data["fov"]
		if cam_data.has("projection"):
			_holo_camera.projection = cam_data["projection"]
		if cam_data.has("size"):
			_holo_camera.size = cam_data["size"]
	else:
		_holo_camera.position = Vector3(0, 30, 12)
		_holo_camera.rotation_degrees = Vector3(-60, 0, 0)
		_holo_camera.fov = 45.0
	_holo_camera.current = true
	_vp.add_child(_holo_camera)

	# Ship model
	_holo_model = ShipModel.new()
	_holo_model.model_path = ship.ship_data.model_path
	_holo_model.model_scale = ShipFactory.get_scene_model_scale(ship.ship_data.ship_id)
	_holo_model.model_rotation_degrees = ShipFactory.get_model_rotation(ship.ship_data.ship_id)
	_vp.add_child(_holo_model)

	# Apply holographic material to all meshes
	_apply_holographic_material(_holo_model)

	# Initial layout
	_layout_holo_viewer()


func _cleanup_holo_viewer() -> void:
	if _vp_container and is_instance_valid(_vp_container):
		_vp_container.queue_free()
	_vp_container = null
	_vp = null
	_holo_camera = null
	_holo_model = null


func _layout_holo_viewer() -> void:
	if _vp_container == null or _vp == null:
		return
	var s := _weapon_panel.size
	var header_h := 20.0
	var x := 6.0
	var y := header_h + 2.0
	var w := 132.0  # sil_area_w(140) - 2*margin
	var h := maxf(s.y - y - 4.0, 10.0)
	_vp_container.position = Vector2(x, y)
	_vp_container.size = Vector2(w, h)
	_vp.size = Vector2i(int(w), int(h))


func _apply_holographic_material(model: ShipModel) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.45, 0.9, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.25, 0.6)
	mat.emission_energy_multiplier = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


# =============================================================================
# HARDPOINT PROJECTION CACHE
# =============================================================================
func _rebuild_weapon_panel_cache(s: Vector2) -> void:
	_cached_wp_size = s
	_cached_hp_screen = []

	if weapon_manager == null or ship == null or ship.ship_data == null:
		return
	var hp_count := weapon_manager.get_hardpoint_count()
	if hp_count == 0:
		return

	var sil_area_w := 140.0
	var header_h := 20.0
	var a_l := 6.0
	var a_t := header_h + 2.0
	var a_r := sil_area_w - 2.0
	var a_b := s.y - 4.0

	if _holo_camera == null or _vp == null:
		return
	var vp_size := Vector2(_vp.size)
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return

	# Project hardpoint 3D positions through the hologram camera — raw positions
	var root_basis := ShipFactory.get_root_basis(ship.ship_data.ship_id)
	for i in hp_count:
		var world_pos: Vector3 = root_basis * weapon_manager.hardpoints[i].position
		var screen_pos := _holo_camera.unproject_position(world_pos)
		var hp_screen_x := a_l + screen_pos.x / vp_size.x * (a_r - a_l)
		var hp_screen_y := a_t + screen_pos.y / vp_size.y * (a_b - a_t)
		_cached_hp_screen.append(Vector2(hp_screen_x, hp_screen_y))


# =============================================================================
# TYPE HELPERS
# =============================================================================
func _get_weapon_type_color(wtype: int) -> Color:
	match wtype:
		0: return Color(0.0, 0.9, 1.0)   # LASER
		1: return Color(0.2, 1.0, 0.3)   # PLASMA
		2: return Color(1.0, 0.6, 0.1)   # MISSILE
		3: return Color(1.0, 1.0, 0.2)   # RAILGUN
		4: return Color(1.0, 0.2, 0.2)   # MINE
	return UITheme.PRIMARY


func _get_weapon_type_abbr(wtype: int) -> String:
	match wtype:
		0: return "LASE"
		1: return "PLAS"
		2: return "MISS"
		3: return "RAIL"
		4: return "MINE"
	return "----"


# =============================================================================
# DRAW WEAPON PANEL
# =============================================================================
func _draw_weapon_panel(ctrl: Control) -> void:
	var font := UITheme.get_font_medium()
	var s := ctrl.size

	ctrl.draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.02, 0.06, 0.45))
	ctrl.draw_line(Vector2(0, 0), Vector2(s.x, 0), UITheme.PRIMARY_DIM, 1.0)
	ctrl.draw_line(Vector2(0, 0), Vector2(0, 12), UITheme.PRIMARY, 1.5)
	ctrl.draw_line(Vector2(s.x, 0), Vector2(s.x, 12), UITheme.PRIMARY, 1.5)
	var sly: float = fmod(scan_line_y, s.y)
	ctrl.draw_line(Vector2(0, sly), Vector2(s.x, sly), UITheme.SCANLINE, 1.0)

	if weapon_manager == null or ship == null or ship.ship_data == null:
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "---", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 13, UITheme.TEXT_DIM)
		return

	var hp_count := weapon_manager.get_hardpoint_count()
	if hp_count == 0:
		ctrl.draw_string(font, Vector2(0, s.y * 0.5 + 5), "AUCUNE ARME", HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 13, UITheme.TEXT_DIM)
		return

	if ship != _holo_ship_ref:
		_setup_holo_viewer()

	if _cached_wp_size != s or _cached_hp_screen.is_empty():
		_layout_holo_viewer()
		_rebuild_weapon_panel_cache(s)

	# Header
	ctrl.draw_string(font, Vector2(8, 13), "ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.HEADER)
	var hdr_w := font.get_string_size("ARMEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ctrl.draw_line(Vector2(8 + hdr_w + 6, 7), Vector2(s.x - 8, 7), UITheme.PRIMARY_DIM, 1.0)
	var class_str: String = ship.ship_data.ship_class
	if class_str == "":
		class_str = "---"
	var csw := font.get_string_size(class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ctrl.draw_string(font, Vector2(s.x - csw - 8, 13), class_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)

	var sil_area_w := 140.0
	var list_x := sil_area_w + 4.0
	var list_w := s.x - list_x - 4.0
	var header_h := 20.0

	ctrl.draw_line(Vector2(sil_area_w, header_h), Vector2(sil_area_w, s.y), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.15), 1.0)

	# Hardpoint markers (drawn over the 3D hologram via show_behind_parent)
	for i in _cached_hp_screen.size():
		var status := weapon_manager.get_hardpoint_status(i)
		_draw_hardpoint_marker(ctrl, font, _cached_hp_screen[i], i, status)

	_draw_weapon_list(ctrl, font, list_x, header_h + 2.0, list_w, hp_count)


# =============================================================================
# HARDPOINT MARKER
# =============================================================================
func _draw_hardpoint_marker(ctrl: Control, font: Font, pos: Vector2, index: int, status: Dictionary) -> void:
	if status.is_empty():
		return
	var is_on: bool = status["enabled"]
	var wname: String = str(status["weapon_name"])
	var ssize: String = status["slot_size"]
	var cd: float = float(status["cooldown_ratio"])
	var wtype: int = int(status.get("weapon_type", -1))
	var armed: bool = wname != ""

	var r := 5.0
	match ssize:
		"M": r = 7.0
		"L": r = 9.0

	var type_col: Color = _get_weapon_type_color(wtype) if armed else UITheme.PRIMARY
	var is_missile: bool = wtype == 2

	if is_on and armed:
		var ga := sin(pulse_t * 2.0 + float(index) * 1.5) * 0.12 + 0.2
		ctrl.draw_arc(pos, r + 3, 0, TAU, 16, Color(type_col.r, type_col.g, type_col.b, ga), 2.0, true)

		if is_missile:
			var d := r * 0.85
			var diamond := PackedVector2Array([
				pos + Vector2(0, -d), pos + Vector2(d, 0),
				pos + Vector2(0, d), pos + Vector2(-d, 0),
			])
			ctrl.draw_colored_polygon(diamond, Color(type_col.r, type_col.g, type_col.b, 0.15))
			diamond.append(diamond[0])
			if cd > 0.01:
				ctrl.draw_polyline(diamond, Color(type_col.r, type_col.g, type_col.b, 0.3), 1.5)
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r + 1, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_polyline(diamond, type_col, 2.0)
		else:
			ctrl.draw_circle(pos, r, Color(type_col.r, type_col.g, type_col.b, 0.12))
			if cd > 0.01:
				ctrl.draw_arc(pos, r, 0, TAU, 20, Color(type_col.r, type_col.g, type_col.b, 0.25), 1.5, true)
				var sweep := (1.0 - cd) * TAU
				ctrl.draw_arc(pos, r, -PI * 0.5, -PI * 0.5 + sweep, 20, type_col, 2.5, true)
			else:
				ctrl.draw_arc(pos, r, 0, TAU, 20, type_col, 2.0, true)
	elif is_on:
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.25), 1.0, true)
	else:
		ctrl.draw_circle(pos, r, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.08))
		ctrl.draw_arc(pos, r, 0, TAU, 16, Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.3), 1.5, true)
		var xsz := r * 0.5
		ctrl.draw_line(pos + Vector2(-xsz, -xsz), pos + Vector2(xsz, xsz), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)
		ctrl.draw_line(pos + Vector2(xsz, -xsz), pos + Vector2(-xsz, xsz), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5), 1.5)

	# Number label just above marker
	var num_col: Color = type_col if (is_on and armed) else (UITheme.PRIMARY if is_on else Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.4))
	var num_str := str(index + 1)
	var num_w := font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ctrl.draw_string(font, pos + Vector2(-num_w * 0.5, -r - 2.0), num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, num_col)


# =============================================================================
# WEAPON LIST
# =============================================================================
func _draw_weapon_list(ctrl: Control, font: Font, x: float, y: float, w: float, hp_count: int) -> void:
	var line_h := 15.0
	var grp_colors: Array[Color] = [UITheme.PRIMARY, Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 1.0)]

	for i in hp_count:
		var status := weapon_manager.get_hardpoint_status(i)
		if status.is_empty():
			continue
		var ly := y + i * line_h
		var is_on: bool = status["enabled"]
		var wname: String = str(status["weapon_name"])
		var wtype: int = int(status.get("weapon_type", -1))
		var cd: float = float(status["cooldown_ratio"])
		var fire_grp: int = int(status.get("fire_group", -1))
		var armed: bool = wname != ""

		var num_col: Color
		if is_on and armed:
			num_col = _get_weapon_type_color(wtype)
		elif is_on:
			num_col = UITheme.TEXT_DIM
		else:
			num_col = Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.5)
		ctrl.draw_string(font, Vector2(x, ly + 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, num_col)

		if not armed:
			ctrl.draw_string(font, Vector2(x + 10, ly + 10), "Vide", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.3))
			continue

		var abbr := _get_weapon_type_abbr(wtype)
		var name_col: Color
		if not is_on:
			name_col = Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.4)
		else:
			name_col = Color(UITheme.TEXT.r, UITheme.TEXT.g, UITheme.TEXT.b, 0.8)
		ctrl.draw_string(font, Vector2(x + 10, ly + 10), abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, name_col)

		var short_name := wname.get_slice(" ", 0).left(5)
		ctrl.draw_string(font, Vector2(x + 40, ly + 10), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.6 if is_on else 0.3))

		if not is_on:
			var strike_y := ly + 6.0
			ctrl.draw_line(Vector2(x + 8, strike_y), Vector2(x + w - 4, strike_y), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.35), 1.0)
			continue

		# Ready/cooldown indicator
		var ind_x := x + w - 14.0
		if cd > 0.01:
			var bar_w := 12.0
			var bar_h := 3.0
			var bar_y := ly + 5.0
			ctrl.draw_rect(Rect2(ind_x, bar_y, bar_w, bar_h), Color(UITheme.TEXT_DIM.r, UITheme.TEXT_DIM.g, UITheme.TEXT_DIM.b, 0.15))
			var fill := (1.0 - cd) * bar_w
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_rect(Rect2(ind_x, bar_y, fill, bar_h), Color(type_c.r, type_c.g, type_c.b, 0.7))
		else:
			var type_c := _get_weapon_type_color(wtype)
			ctrl.draw_circle(Vector2(ind_x + 6.0, ly + 6.5), 2.0, type_c)

		if fire_grp >= 0 and fire_grp < grp_colors.size():
			ctrl.draw_circle(Vector2(ind_x - 6.0, ly + 6.5), 1.5, Color(grp_colors[fire_grp].r, grp_colors[fire_grp].g, grp_colors[fire_grp].b, 0.5))
