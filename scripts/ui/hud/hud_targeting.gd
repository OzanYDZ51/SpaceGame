class_name HudTargeting
extends Control

# =============================================================================
# HUD Targeting — Target bracket, lead indicator, 3D holographic info panel
# =============================================================================

var targeting_system = null
var ship = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _target_shield_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _target_hull_flash: float = 0.0
var _connected_target_health = null
var _prev_target_shields: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_target_hull: float = 0.0
var _last_tracked_target: Node3D = null

var _connected_struct_health = null

var _target_overlay: Control = null
var _target_panel: Control = null

# 3D target hologram
var _target_vp_container: SubViewportContainer = null
var _target_vp: SubViewport = null
var _target_holo_camera: Camera3D = null
var _target_holo_model = null
var _target_holo_pivot: Node3D = null
var _target_shield_mesh: MeshInstance3D = null
var _target_shield_mat: ShaderMaterial = null
var _target_hit_flash_light: OmniLight3D = null
var _holo_hit_facing: int = -1
var _holo_hit_timer: float = 1.0
var _target_shield_half: Vector3 = Vector3.ONE * 10.0
var _target_shield_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_target_overlay = HudDrawHelpers.make_ctrl(0.0, 0.0, 1.0, 1.0, 0, 0, 0, 0)
	_target_overlay.draw.connect(_draw_target_overlay.bind(_target_overlay))
	add_child(_target_overlay)

	_target_panel = HudDrawHelpers.make_ctrl(1.0, 1.0, 1.0, 1.0, -276, -296, -16, -16)
	_target_panel.draw.connect(_draw_target_info_panel.bind(_target_panel))
	_target_panel.visible = false
	add_child(_target_panel)


func update(delta: float, is_cockpit: bool) -> void:
	var current_target: Node3D = null
	if targeting_system and targeting_system.current_target and is_instance_valid(targeting_system.current_target):
		current_target = targeting_system.current_target
	_track_target(current_target)

	for i in 4:
		_target_shield_flash[i] = maxf(_target_shield_flash[i] - delta * 3.0, 0.0)
	_target_hull_flash = maxf(_target_hull_flash - delta * 3.0, 0.0)

	# Sync target hologram
	_holo_hit_timer += delta
	if _target_holo_pivot and _last_tracked_target and is_instance_valid(_last_tracked_target):
		_target_holo_pivot.transform.basis = _last_tracked_target.global_transform.basis.orthonormalized()

	if _target_shield_mat:
		if _connected_target_health:
			_target_shield_mat.set_shader_parameter("shield_ratios", Vector4(
				_connected_target_health.get_shield_ratio(HealthSystem.ShieldFacing.FRONT),
				_connected_target_health.get_shield_ratio(HealthSystem.ShieldFacing.REAR),
				_connected_target_health.get_shield_ratio(HealthSystem.ShieldFacing.LEFT),
				_connected_target_health.get_shield_ratio(HealthSystem.ShieldFacing.RIGHT),
			))
		elif _connected_struct_health:
			var sr =_connected_struct_health.get_shield_ratio()
			_target_shield_mat.set_shader_parameter("shield_ratios", Vector4(sr, sr, sr, sr))
		_target_shield_mat.set_shader_parameter("pulse_time", pulse_t)
		_target_shield_mat.set_shader_parameter("hit_facing", _holo_hit_facing)
		_target_shield_mat.set_shader_parameter("hit_time", _holo_hit_timer)

	if _target_hit_flash_light:
		if _holo_hit_timer < 0.5:
			_target_hit_flash_light.light_energy = 3.0 * maxf(0.0, 1.0 - _holo_hit_timer * 4.0)
		else:
			_target_hit_flash_light.light_energy = 0.0

	_target_overlay.queue_redraw()

	if _target_panel:
		_target_panel.visible = current_target != null and not is_cockpit
		if _target_panel.visible:
			_target_panel.queue_redraw()


# =============================================================================
# TARGET OVERLAY
# =============================================================================
func _draw_target_overlay(ctrl: Control) -> void:
	if targeting_system == null:
		return
	if targeting_system.current_target == null or not is_instance_valid(targeting_system.current_target):
		return
	var cam =get_viewport().get_camera_3d()
	if cam == null:
		return
	var target =targeting_system.current_target
	var cf: Vector3 = -cam.global_transform.basis.z

	var target_pos: Vector3 = TargetingSystem.get_ship_center(target)

	var to_t: Vector3 = (target_pos - cam.global_position).normalized()
	if cf.dot(to_t) > 0.1:
		_draw_target_bracket(ctrl, cam.unproject_position(target_pos))

	if ship and ship.current_speed > 0.1:
		var lp: Vector3 = targeting_system.get_lead_indicator_position()
		var to_l: Vector3 = (lp - cam.global_position).normalized()
		if cf.dot(to_l) > 0.1:
			_draw_lead_indicator(ctrl, cam.unproject_position(lp))


func _draw_target_bracket(ctrl: Control, sp: Vector2) -> void:
	var bk =22.0
	var bl =10.0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var corner: Vector2 = sp + s * bk
		ctrl.draw_line(corner, corner + Vector2(-s.x * bl, 0), UITheme.TARGET, 1.5)
		ctrl.draw_line(corner, corner + Vector2(0, -s.y * bl), UITheme.TARGET, 1.5)


func _draw_lead_indicator(ctrl: Control, sp: Vector2) -> void:
	ctrl.draw_arc(sp, 8.0, 0, TAU, 16, UITheme.LEAD, 1.5, true)
	ctrl.draw_line(sp + Vector2(-4, 0), sp + Vector2(4, 0), UITheme.LEAD, 1.0)
	ctrl.draw_line(sp + Vector2(0, -4), sp + Vector2(0, 4), UITheme.LEAD, 1.0)


# =============================================================================
# TARGET INFO PANEL
# =============================================================================
func _draw_target_info_panel(ctrl: Control) -> void:
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y)
	var font =UITheme.get_font_medium()
	var x =12.0
	var w =ctrl.size.x - 24.0
	var cx =ctrl.size.x / 2.0
	var y =22.0

	if targeting_system == null or targeting_system.current_target == null:
		return
	if not is_instance_valid(targeting_system.current_target):
		return

	var target =targeting_system.current_target
	var t_health = target.get_node_or_null("HealthSystem")
	var t_struct = target.get_node_or_null("StructureHealth")

	# Determine hostility
	var is_hostile =false
	if target.get("ship_data") != null:
		is_hostile = target.faction != &"player_fleet" and target.faction != &"neutral" and target.faction != &"friendly"

	# Hostile: red top accent line
	if is_hostile:
		var lock_pulse =sin(pulse_t * 3.0) * 0.2 + 0.5
		ctrl.draw_line(Vector2(0, 0), Vector2(ctrl.size.x, 0), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, lock_pulse), 2.0)

	# Header
	if is_hostile:
		var hdr_pulse =sin(pulse_t * 3.0) * 0.3 + 0.7
		var hdr_col =Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, hdr_pulse)
		ctrl.draw_rect(Rect2(x, y - 11, 3, 14), hdr_col)
		var lock_text: String = Locale.t("hud.target_locked")
		ctrl.draw_string(font, Vector2(x + 9, y), lock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hdr_col)
		var tw =font.get_string_size(lock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lx =x + 9 + tw + 8
		if lx < x + w:
			ctrl.draw_line(Vector2(lx, y - 4), Vector2(x + w, y - 4), Color(UITheme.DANGER.r, UITheme.DANGER.g, UITheme.DANGER.b, 0.3), 1.0)
		y += 18
	else:
		y = HudDrawHelpers.draw_section_header(ctrl, font, x, y, w, Locale.t("hud.target"))
	y += 4

	# Target name (prominent)
	var display_name: String = target.name
	if target.get("player_name") != null and target.player_name != "":
		var pname: String = target.player_name
		if target.get("corporation_tag") != null and target.corporation_tag != "":
			pname = "[%s] %s" % [target.corporation_tag, pname]
		display_name = pname
	elif "station_name" in target and target.station_name != "":
		display_name = target.station_name
	elif target.get("owner_name") != null and target.owner_name != "":
		# Fleet NPC belonging to another player — show "[Owner] ShipName"
		var sd = ShipRegistry.get_ship_data(target.ship_id) if target.get("ship_id") != null else null
		var sname: String = String(sd.ship_name) if sd else String(target.ship_id)
		display_name = "[%s] %s" % [target.owner_name, sname]
	elif target.get("ship_id") != null and target.get("faction") == &"player_fleet":
		# Fleet NPC without owner name yet — show ship name at minimum
		var sd = ShipRegistry.get_ship_data(target.ship_id)
		display_name = String(sd.ship_name) if sd else String(target.ship_id)
	var name_col =UITheme.DANGER if is_hostile else UITheme.TARGET
	ctrl.draw_string(font, Vector2(x, y), display_name, HORIZONTAL_ALIGNMENT_LEFT, int(w), 16, name_col)
	y += 20

	# Class / type + distance
	var class_text =""
	if target.get("ship_data") != null and target.ship_data:
		class_text = str(target.ship_data.ship_class)
	elif target.get("ship_class") != null and str(target.ship_class) != "":
		class_text = str(target.ship_class)
	elif t_struct:
		class_text = Locale.t("hud.station")
	ctrl.draw_string(font, Vector2(x, y), class_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)

	var dist =targeting_system.get_target_distance()
	if dist >= 0.0:
		var dt: String = HudDrawHelpers.format_nav_distance(dist)
		var dtw =font.get_string_size(dt, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14).x
		ctrl.draw_string(font, Vector2(x + w - dtw, y), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)
	y += 22

	# Separator
	ctrl.draw_line(Vector2(x, y - 8), Vector2(x + w, y - 8), UITheme.PRIMARY_FAINT, 1.0)

	if t_struct:
		y += 110  # Hologram viewport space
		_draw_structure_health(ctrl, font, x, y, w, t_struct)
	else:
		# 3D hologram renders the shield diagram (SubViewport behind _draw layer)
		y += 110

		if t_health:
			var f_r =t_health.get_shield_ratio(HealthSystem.ShieldFacing.FRONT)
			var r_r =t_health.get_shield_ratio(HealthSystem.ShieldFacing.REAR)
			var l_r =t_health.get_shield_ratio(HealthSystem.ShieldFacing.LEFT)
			var d_r =t_health.get_shield_ratio(HealthSystem.ShieldFacing.RIGHT)
			var col_x2 =cx + 10
			ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.shield_front") + ": %d%%" % int(f_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(f_r))
			ctrl.draw_string(font, Vector2(col_x2, y), Locale.t("hud.shield_rear") + ": %d%%" % int(r_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(r_r))
			y += 14
			ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.shield_left") + ": %d%%" % int(l_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(l_r))
			ctrl.draw_string(font, Vector2(col_x2, y), Locale.t("hud.shield_right") + ": %d%%" % int(d_r * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _shield_ratio_color(d_r))
			y += 20
		else:
			y += 34

		# Separator before hull
		ctrl.draw_line(Vector2(x, y - 6), Vector2(x + w, y - 6), UITheme.PRIMARY_FAINT, 1.0)

		var hull_r =t_health.get_hull_ratio() if t_health else 0.0
		var hull_c =UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
		ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.hull"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
		var hp ="%d%%" % int(hull_r * 100)
		ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hull_c)
		y += 8
		HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)

		if _target_hull_flash > 0.01:
			var bar_fw: float = w * clampf(hull_r, 0.0, 1.0)
			if bar_fw > 0:
				ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_hull_flash * 0.5))


# =============================================================================
# 3D TARGET HOLOGRAM
# =============================================================================
func _setup_target_holo(target: Node3D) -> void:
	_cleanup_target_holo()
	if target == null or not is_instance_valid(target):
		return

	# Resolve ship_id and ship_data for any target type
	var target_ship_id: StringName = &""
	var target_ship_data: ShipData = null
	var is_station =target.get("station_name") != null
	if target.get("ship_data") != null:
		if target.ship_data == null:
			return
		target_ship_id = target.ship_data.ship_id
		target_ship_data = target.ship_data
	elif target.get("peer_id") != null:
		target_ship_id = target.ship_id
		target_ship_data = ShipRegistry.get_ship_data(target_ship_id)
	elif target.get("npc_id") != null:
		target_ship_id = target.ship_id
		target_ship_data = ShipRegistry.get_ship_data(target_ship_id)
	if target_ship_data == null and not is_station:
		return

	# SubViewportContainer — renders behind 2D draw layer
	_target_vp_container = SubViewportContainer.new()
	_target_vp_container.stretch = true
	_target_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_vp_container.show_behind_parent = true
	_target_vp_container.position = Vector2(4, 84)
	_target_vp_container.size = Vector2(252, 110)
	_target_panel.add_child(_target_vp_container)

	# SubViewport with isolated world
	_target_vp = SubViewport.new()
	_target_vp.own_world_3d = true
	_target_vp.transparent_bg = true
	_target_vp.msaa_3d = Viewport.MSAA_2X
	_target_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_target_vp.size = Vector2i(252, 110)
	_target_vp_container.add_child(_target_vp)

	# Environment — transparent bg with subtle blue ambient
	var env =Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.3, 0.5)
	env.ambient_light_energy = 0.3
	var world_env =WorldEnvironment.new()
	world_env.environment = env
	_target_vp.add_child(world_env)

	# Key light — blue-cyan from above-left
	var dir_light =DirectionalLight3D.new()
	dir_light.light_color = Color(0.3, 0.6, 0.9)
	dir_light.light_energy = 1.5
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	_target_vp.add_child(dir_light)

	# Rim light — cool cyan from behind-right
	var rim_light =OmniLight3D.new()
	rim_light.light_color = Color(0.2, 0.6, 0.9)
	rim_light.light_energy = 1.0
	rim_light.omni_range = 50.0
	rim_light.position = Vector3(5, 3, -8)
	_target_vp.add_child(rim_light)

	# Camera — positioned based on target type
	_target_holo_camera = Camera3D.new()
	if not is_station:
		var cam_data =ShipFactory.get_equipment_camera_data(target_ship_id)
		if not cam_data.is_empty():
			_target_holo_camera.position = cam_data["position"]
			_target_holo_camera.transform.basis = cam_data["basis"]
			_target_holo_camera.fov = cam_data["fov"]
			if cam_data.has("projection"):
				_target_holo_camera.projection = cam_data["projection"]
			if cam_data.has("size"):
				_target_holo_camera.size = cam_data["size"]
		else:
			_target_holo_camera.position = Vector3(0, 30, 12)
			_target_holo_camera.rotation_degrees = Vector3(-60, 0, 0)
			_target_holo_camera.fov = 45.0
	_target_holo_camera.current = true
	_target_vp.add_child(_target_holo_camera)

	# Rotating pivot — tracks target ship orientation
	_target_holo_pivot = Node3D.new()
	_target_holo_pivot.name = "TargetPivot"
	_target_vp.add_child(_target_holo_pivot)

	# Model — holographic blue
	_target_holo_model = ShipModel.new()
	if is_station:
		_target_holo_model.model_path = "res://assets/models/babbage_station.glb"
	else:
		_target_holo_model.model_path = target_ship_data.model_path
		_target_holo_model.model_scale = ShipFactory.get_scene_model_scale(target_ship_id)
		_target_holo_model.model_rotation_degrees = ShipFactory.get_model_rotation(target_ship_id)
	_target_holo_pivot.add_child(_target_holo_model)

	_apply_target_holo_material(_target_holo_model)

	# Station camera: position based on actual model AABB after loading
	if is_station:
		var aabb =_target_holo_model.get_visual_aabb()
		var center =aabb.get_center()
		var max_dim =maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if max_dim < 0.01:
			max_dim = 2.0
		_target_holo_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_target_holo_camera.size = max_dim * 2.5
		_target_holo_camera.position = center + Vector3(0, max_dim * 1.2, max_dim * 0.9)
		_target_holo_camera.rotation_degrees = Vector3(-50, 0, 0)

	_create_target_shield_mesh()

	# Flash light for shield impacts
	_target_hit_flash_light = OmniLight3D.new()
	_target_hit_flash_light.light_color = Color(0.12, 0.35, 1.0)
	_target_hit_flash_light.light_energy = 0.0
	_target_hit_flash_light.omni_range = 30.0
	_target_hit_flash_light.shadow_enabled = false
	_target_holo_pivot.add_child(_target_hit_flash_light)

	_holo_hit_facing = -1
	_holo_hit_timer = 1.0


func _cleanup_target_holo() -> void:
	if _target_vp_container and is_instance_valid(_target_vp_container):
		_target_vp_container.queue_free()
	_target_vp_container = null
	_target_vp = null
	_target_holo_camera = null
	_target_holo_model = null
	_target_holo_pivot = null
	_target_shield_mesh = null
	_target_shield_mat = null
	_target_hit_flash_light = null


func _apply_target_holo_material(model) -> void:
	var mat =StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.45, 0.9, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.25, 0.6)
	mat.emission_energy_multiplier = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


func _create_target_shield_mesh() -> void:
	if _target_holo_model == null or _target_holo_pivot == null:
		return

	var aabb =_target_holo_model.get_visual_aabb()
	_target_shield_half = aabb.size * 0.5 * 1.3
	_target_shield_center = aabb.get_center()
	_target_shield_half = _target_shield_half.clamp(Vector3.ONE * 2.0, Vector3.ONE * 200.0)

	var shader =load("res://shaders/hud_shield_holo.gdshader") as Shader
	if shader == null:
		return

	_target_shield_mat = ShaderMaterial.new()
	_target_shield_mat.shader = shader
	_target_shield_mat.set_shader_parameter("shield_scale", _target_shield_half)
	_target_shield_mat.set_shader_parameter("shield_ratios", Vector4(1, 1, 1, 1))
	_target_shield_mat.set_shader_parameter("hit_facing", -1)
	_target_shield_mat.set_shader_parameter("hit_time", 1.0)

	_target_shield_mesh = MeshInstance3D.new()
	var sphere =SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_target_shield_mesh.mesh = sphere
	_target_shield_mesh.scale = _target_shield_half
	_target_shield_mesh.position = _target_shield_center
	_target_shield_mesh.material_override = _target_shield_mat
	_target_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_target_holo_pivot.add_child(_target_shield_mesh)


func _trigger_target_hit_flash(facing: int) -> void:
	if _target_hit_flash_light == null:
		return
	var dir: Vector3
	match facing:
		0: dir = Vector3(0, 0, -_target_shield_half.z)
		1: dir = Vector3(0, 0, _target_shield_half.z)
		2: dir = Vector3(-_target_shield_half.x, 0, 0)
		3: dir = Vector3(_target_shield_half.x, 0, 0)
		_: dir = Vector3.ZERO
	_target_hit_flash_light.position = _target_shield_center + dir
	var ratio =_connected_target_health.get_shield_ratio(facing) if _connected_target_health else 1.0
	_target_hit_flash_light.light_color = Color(0.12, 0.35, 1.0) if ratio > 0.3 else Color(1.0, 0.3, 0.08)
	_target_hit_flash_light.light_energy = 3.0


# =============================================================================
# STRUCTURE HEALTH (stations — omnidirectional shield + hull bars)
# =============================================================================
func _draw_structure_health(ctrl: Control, font: Font, x: float, y: float, w: float, sh) -> void:
	# Shield bar
	var shd_r =sh.get_shield_ratio()
	var shd_c =_shield_ratio_color(shd_r)
	ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.shield"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var sp ="%d%%" % int(shd_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, shd_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, shd_r, shd_c)

	if _target_shield_flash[0] > 0.01:
		var bar_fw: float = w * clampf(shd_r, 0.0, 1.0)
		if bar_fw > 0:
			ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_shield_flash[0] * 0.5))

	y += 20

	# Hull bar
	var hull_r =sh.get_hull_ratio()
	var hull_c =UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
	ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.hull"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var hp ="%d%%" % int(hull_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hull_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)

	if _target_hull_flash > 0.01:
		var bar_fw: float = w * clampf(hull_r, 0.0, 1.0)
		if bar_fw > 0:
			ctrl.draw_rect(Rect2(x, y, bar_fw, 8.0), Color(1, 1, 1, _target_hull_flash * 0.5))


func _shield_ratio_color(ratio: float) -> Color:
	if ratio > 0.5: return UITheme.SHIELD
	elif ratio > 0.25: return UITheme.WARNING
	elif ratio > 0.0: return UITheme.DANGER
	return UITheme.PRIMARY_FAINT


# =============================================================================
# TARGET TRACKING
# =============================================================================
func _track_target(new_target: Node3D) -> void:
	if new_target == _last_tracked_target:
		return
	_disconnect_target_signals()
	_last_tracked_target = new_target
	_target_shield_flash = [0.0, 0.0, 0.0, 0.0]
	_target_hull_flash = 0.0

	# Rebuild hologram for new target (or cleanup if null)
	_setup_target_holo(new_target)

	if new_target and is_instance_valid(new_target):
		_connect_target_signals(new_target)


func _connect_target_signals(target: Node3D) -> void:
	var health = target.get_node_or_null("HealthSystem")
	if health:
		_connected_target_health = health
		health.shield_changed.connect(_on_target_shield_hit)
		health.hull_changed.connect(_on_target_hull_hit)
		for i in 4:
			_prev_target_shields[i] = health.shield_current[i]
		_prev_target_hull = health.hull_current
		return
	# Structure health (stations)
	var struct_health = target.get_node_or_null("StructureHealth")
	if struct_health:
		_connected_struct_health = struct_health
		struct_health.shield_changed.connect(_on_struct_shield_hit)
		struct_health.hull_changed.connect(_on_target_hull_hit)
		_prev_target_shields[0] = struct_health.shield_current
		_prev_target_hull = struct_health.hull_current


func _disconnect_target_signals() -> void:
	if _connected_target_health and is_instance_valid(_connected_target_health):
		if _connected_target_health.shield_changed.is_connected(_on_target_shield_hit):
			_connected_target_health.shield_changed.disconnect(_on_target_shield_hit)
		if _connected_target_health.hull_changed.is_connected(_on_target_hull_hit):
			_connected_target_health.hull_changed.disconnect(_on_target_hull_hit)
	_connected_target_health = null
	if _connected_struct_health and is_instance_valid(_connected_struct_health):
		if _connected_struct_health.shield_changed.is_connected(_on_struct_shield_hit):
			_connected_struct_health.shield_changed.disconnect(_on_struct_shield_hit)
		if _connected_struct_health.hull_changed.is_connected(_on_target_hull_hit):
			_connected_struct_health.hull_changed.disconnect(_on_target_hull_hit)
	_connected_struct_health = null


func _on_target_shield_hit(facing: int, current: float, _max_val: float) -> void:
	if facing >= 0 and facing < 4 and current < _prev_target_shields[facing]:
		_target_shield_flash[facing] = 1.0
		_holo_hit_facing = facing
		_holo_hit_timer = 0.0
		_trigger_target_hit_flash(facing)
	if facing >= 0 and facing < 4:
		_prev_target_shields[facing] = current


func _on_struct_shield_hit(current: float, _max_val: float) -> void:
	if current < _prev_target_shields[0]:
		_target_shield_flash[0] = 1.0
		_holo_hit_facing = 0
		_holo_hit_timer = 0.0
		_trigger_target_hit_flash(0)
	_prev_target_shields[0] = current


func _on_target_hull_hit(current: float, _max_val: float) -> void:
	if current < _prev_target_hull:
		_target_hull_flash = 1.0
	_prev_target_hull = current
