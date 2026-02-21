class_name HudStatusPanels
extends Control

# =============================================================================
# HUD Status Panels — Left panel (systems/shields/energy), economy panel (top-left)
# Shield diamond replaced by 3D holographic ship model with directional shields.
# =============================================================================

var ship = null
var health_system = null
var energy_system = null
var player_economy = null
var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _left_panel: Control = null
var _economy_panel: Control = null
var _left_bg_alpha: float = 0.0
var _left_bg_target: float = 0.0
var _eco_bg_alpha: float = 0.0
var _eco_bg_target: float = 0.0

# 3D shield hologram
var _vp_container: SubViewportContainer = null
var _vp: SubViewport = null
var _holo_camera: Camera3D = null
var _holo_model = null
var _holo_pivot: Node3D = null
var _shield_mesh: MeshInstance3D = null
var _shield_mat: ShaderMaterial = null
var _hit_flash_light: OmniLight3D = null
var _holo_ship_ref: Node3D = null
var _hit_facing: int = -1
var _hit_timer: float = 1.0
var _prev_shields: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _shield_half_extents: Vector3 = Vector3.ONE * 10.0
var _shield_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_left_panel = HudDrawHelpers.make_ctrl(0.0, 0.5, 0.0, 0.5, 16, -195, 242, 145)
	_left_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_left_panel.mouse_entered.connect(func(): _left_bg_target = 1.0)
	_left_panel.mouse_exited.connect(func(): _left_bg_target = 0.0)
	_left_panel.draw.connect(_draw_left_panel.bind(_left_panel))
	add_child(_left_panel)

	_economy_panel = HudDrawHelpers.make_ctrl(0.0, 0.0, 0.0, 0.0, 16, 12, 230, 180)
	_economy_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_economy_panel.mouse_entered.connect(func(): _eco_bg_target = 1.0)
	_economy_panel.mouse_exited.connect(func(): _eco_bg_target = 0.0)
	_economy_panel.draw.connect(_draw_economy_panel.bind(_economy_panel))
	add_child(_economy_panel)


func _process(delta: float) -> void:
	_left_bg_alpha = move_toward(_left_bg_alpha, _left_bg_target, delta * 5.0)
	_eco_bg_alpha = move_toward(_eco_bg_alpha, _eco_bg_target, delta * 5.0)

	if not _left_panel or not _left_panel.visible:
		return

	# Sync hologram rotation with player ship orientation
	if _holo_pivot and ship:
		_holo_pivot.transform.basis = ship.global_transform.basis

	# Hit timer always advances for flash light fade
	_hit_timer += delta

	# Update shield shader uniforms every frame
	if _shield_mat and health_system:
		_shield_mat.set_shader_parameter("shield_ratios", Vector4(
			health_system.get_shield_ratio(HealthSystem.ShieldFacing.FRONT),
			health_system.get_shield_ratio(HealthSystem.ShieldFacing.REAR),
			health_system.get_shield_ratio(HealthSystem.ShieldFacing.LEFT),
			health_system.get_shield_ratio(HealthSystem.ShieldFacing.RIGHT),
		))
		_shield_mat.set_shader_parameter("pulse_time", pulse_t)

		# Detect shield hits by comparing current vs previous values
		for i in 4:
			var cur: float = health_system.shield_current[i]
			if cur < _prev_shields[i] - 0.5:
				_hit_facing = i
				_hit_timer = 0.0
				_trigger_hit_flash(i)
			_prev_shields[i] = cur

		_shield_mat.set_shader_parameter("hit_facing", _hit_facing)
		_shield_mat.set_shader_parameter("hit_time", _hit_timer)

	# Fade hit flash light
	if _hit_flash_light:
		if _hit_timer < 0.5:
			_hit_flash_light.light_energy = 3.0 * maxf(0.0, 1.0 - _hit_timer * 4.0)
		else:
			_hit_flash_light.light_energy = 0.0


func set_cockpit_mode(is_cockpit: bool) -> void:
	_left_panel.visible = not is_cockpit
	_economy_panel.visible = not is_cockpit


func redraw_slow() -> void:
	_left_panel.queue_redraw()
	_economy_panel.queue_redraw()


func invalidate_cache() -> void:
	_cleanup_shield_holo()
	_holo_ship_ref = null


# =============================================================================
# LEFT PANEL
# =============================================================================
func _draw_left_panel(ctrl: Control) -> void:
	HudDrawHelpers.draw_panel_bg(ctrl, scan_line_y, _left_bg_alpha)
	var font =UITheme.get_font_medium()
	var x =12.0
	var w =ctrl.size.x - 24.0
	var y =22.0

	y = HudDrawHelpers.draw_section_header(ctrl, font, x, y, w, Locale.t("hud.systems"))
	y += 2

	# Hull + Shield (fusionnés — coque en barre principale, bouclier en fine bande bleue collée dessus)
	var hull_r =health_system.get_hull_ratio() if health_system else 1.0
	var shd_r =health_system.get_total_shield_ratio() if health_system else 0.85
	var hull_c =UITheme.ACCENT if hull_r > 0.5 else (UITheme.WARNING if hull_r > 0.25 else UITheme.DANGER)
	var shd_c =UITheme.SHIELD

	# Label: "COQUE" à gauche, bouclier% (bleu petit) + coque% à droite
	ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.hull_label"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var hp :="%d%%" % int(hull_r * 100)
	var sp :="%d%%" % int(shd_r * 100)
	var hp_w :=font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var sp_w :=font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	# Bouclier% en bleu dim, légèrement avant le coque%
	ctrl.draw_string(font, Vector2(x + w - hp_w - sp_w - 6, y), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(shd_c.r, shd_c.g, shd_c.b, 0.65))
	ctrl.draw_string(font, Vector2(x + w - hp_w, y), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hull_c)
	y += 8

	# Bande bouclier (fine, bleue, collée au-dessus de la barre de coque)
	ctrl.draw_rect(Rect2(x, y, w, 3), Color(shd_c.r * 0.15, shd_c.g * 0.15, shd_c.b * 0.15, 0.9))
	if shd_r > 0.0:
		ctrl.draw_rect(Rect2(x, y, w * shd_r, 3), Color(shd_c.r, shd_c.g, shd_c.b, 0.75))
	y += 3

	# Barre principale coque (directement sous le bouclier, sans espace)
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, hull_r, hull_c)
	y += 22

	# Energy
	var nrg_r =energy_system.get_energy_ratio() if energy_system else 0.7
	var nrg_c =Color(0.2, 0.6, 1.0, 0.9)
	ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.energy"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	var np ="%d%%" % int(nrg_r * 100)
	ctrl.draw_string(font, Vector2(x + w - font.get_string_size(np, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), np, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, nrg_c)
	y += 8
	HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, nrg_r, nrg_c)
	y += 24

	# 3D Shield Hologram area (SubViewport renders behind this _draw layer)
	if ship != _holo_ship_ref:
		_setup_shield_holo()
	# Hologram occupies y=128..218 (position.y=128, size.y=90) — align y below it
	y = 228

	# Separator
	ctrl.draw_line(Vector2(x, y), Vector2(x + w, y), UITheme.PRIMARY_FAINT, 1.0)
	y += 10

	# --- Cargo hold (soute) — always visible, same style as hull/shield/energy ---
	var _fs = null
	if GameManager.player_data and GameManager.player_data.fleet:
		_fs = GameManager.player_data.fleet.get_active()
	if _fs:
		var cap: int = _fs.get_cargo_capacity()
		var used: int = _fs.get_total_stored()
		var cargo_r: float = clampf(float(used) / float(cap) if cap > 0 else 0.0, 0.0, 1.0)
		var cargo_c: Color
		if cargo_r < 0.5:
			cargo_c = Color(0.2, 0.8, 0.5).lerp(Color(1.0, 0.9, 0.2), cargo_r * 2.0)
		elif cargo_r < 0.85:
			cargo_c = Color(1.0, 0.9, 0.2).lerp(Color(1.0, 0.5, 0.1), (cargo_r - 0.5) / 0.35)
		else:
			cargo_c = Color(1.0, 0.5, 0.1).lerp(Color(1.0, 0.2, 0.1), (cargo_r - 0.85) / 0.15)
		ctrl.draw_string(font, Vector2(x, y), Locale.t("hud.mining_cargo"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
		var cp := "%d/%d" % [used, cap]
		ctrl.draw_string(font, Vector2(x + w - font.get_string_size(cp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y), cp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cargo_c)
		y += 8
		HudDrawHelpers.draw_bar(ctrl, Vector2(x, y), w, cargo_r, cargo_c)



# =============================================================================
# 3D SHIELD HOLOGRAM
# =============================================================================
func _setup_shield_holo() -> void:
	_cleanup_shield_holo()
	_holo_ship_ref = ship
	if ship == null or ship.ship_data == null:
		return

	# SubViewportContainer — renders behind 2D draw layer
	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_container.show_behind_parent = true
	_vp_container.position = Vector2(4, 128)
	_vp_container.size = Vector2(218, 90)
	_left_panel.add_child(_vp_container)

	# SubViewport with isolated world
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(218, 90)
	_vp_container.add_child(_vp)

	# Environment — transparent bg with subtle blue ambient
	var env =Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.3, 0.5)
	env.ambient_light_energy = 0.3
	var world_env =WorldEnvironment.new()
	world_env.environment = env
	_vp.add_child(world_env)

	# Key light — blue-cyan from above-left
	var dir_light =DirectionalLight3D.new()
	dir_light.light_color = Color(0.3, 0.6, 0.9)
	dir_light.light_energy = 1.5
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	_vp.add_child(dir_light)

	# Rim light — cool cyan from behind-right
	var rim_light =OmniLight3D.new()
	rim_light.light_color = Color(0.2, 0.6, 0.9)
	rim_light.light_energy = 1.0
	rim_light.omni_range = 50.0
	rim_light.position = Vector3(5, 3, -8)
	_vp.add_child(rim_light)

	# Camera — from EquipmentCamera data or fallback top-down
	_holo_camera = Camera3D.new()
	var cam_data =ShipFactory.get_equipment_camera_data(ship.ship_data.ship_id)
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

	# Rotating pivot — tracks player ship orientation
	_holo_pivot = Node3D.new()
	_holo_pivot.name = "ShipPivot"
	_vp.add_child(_holo_pivot)

	# Ship model — holographic blue
	_holo_model = ShipModel.new()
	_holo_model.model_path = ship.ship_data.model_path
	_holo_model.model_scale = ShipFactory.get_scene_model_scale(ship.ship_data.ship_id)
	_holo_model.model_rotation_degrees = ShipFactory.get_model_rotation(ship.ship_data.ship_id)
	_holo_pivot.add_child(_holo_model)

	_apply_holo_material(_holo_model)
	_create_shield_mesh()

	# Flash light for shield impacts
	_hit_flash_light = OmniLight3D.new()
	_hit_flash_light.light_color = Color(0.12, 0.35, 1.0)
	_hit_flash_light.light_energy = 0.0
	_hit_flash_light.omni_range = 30.0
	_hit_flash_light.shadow_enabled = false
	_holo_pivot.add_child(_hit_flash_light)

	# Initialize shield tracking
	_prev_shields = [0.0, 0.0, 0.0, 0.0]
	_hit_facing = -1
	_hit_timer = 1.0
	if health_system:
		for i in 4:
			_prev_shields[i] = health_system.shield_current[i]


func _cleanup_shield_holo() -> void:
	if _vp_container and is_instance_valid(_vp_container):
		_vp_container.queue_free()
	_vp_container = null
	_vp = null
	_holo_camera = null
	_holo_model = null
	_holo_pivot = null
	_shield_mesh = null
	_shield_mat = null
	_hit_flash_light = null


func _apply_holo_material(model) -> void:
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


func _create_shield_mesh() -> void:
	if _holo_model == null or _holo_pivot == null:
		return

	var aabb =_holo_model.get_visual_aabb()
	_shield_half_extents = aabb.size * 0.5 * 1.3
	_shield_center = aabb.get_center()
	_shield_half_extents = _shield_half_extents.clamp(Vector3.ONE * 2.0, Vector3.ONE * 200.0)

	var shader =load("res://shaders/hud_shield_holo.gdshader") as Shader
	if shader == null:
		push_warning("HudStatusPanels: shield hologram shader not found")
		return

	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = shader
	_shield_mat.set_shader_parameter("shield_scale", _shield_half_extents)
	_shield_mat.set_shader_parameter("shield_ratios", Vector4(1, 1, 1, 1))
	_shield_mat.set_shader_parameter("hit_facing", -1)
	_shield_mat.set_shader_parameter("hit_time", 1.0)

	_shield_mesh = MeshInstance3D.new()
	var sphere =SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_shield_mesh.mesh = sphere
	_shield_mesh.scale = _shield_half_extents
	_shield_mesh.position = _shield_center
	_shield_mesh.material_override = _shield_mat
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo_pivot.add_child(_shield_mesh)


func _trigger_hit_flash(facing: int) -> void:
	if _hit_flash_light == null:
		return
	var dir: Vector3
	match facing:
		0: dir = Vector3(0, 0, -_shield_half_extents.z)
		1: dir = Vector3(0, 0, _shield_half_extents.z)
		2: dir = Vector3(-_shield_half_extents.x, 0, 0)
		3: dir = Vector3(_shield_half_extents.x, 0, 0)
		_: dir = Vector3.ZERO
	_hit_flash_light.position = _shield_center + dir
	var ratio =health_system.get_shield_ratio(facing) if health_system else 1.0
	_hit_flash_light.light_color = Color(0.12, 0.35, 1.0) if ratio > 0.3 else Color(1.0, 0.3, 0.08)
	_hit_flash_light.light_energy = 3.0




# =============================================================================
# ECONOMY PANEL
# =============================================================================
func _draw_economy_panel(ctrl: Control) -> void:
	if player_economy == null:
		return
	var font =UITheme.get_font_medium()
	var w =ctrl.size.x

	# Collect resources with qty > 0
	var active_resources: Array[Dictionary] = []
	for res_id: StringName in PlayerEconomy.RESOURCE_DEFS:
		var qty: int = player_economy.get_resource(res_id)
		if qty > 0:
			var res_def: Dictionary = PlayerEconomy.RESOURCE_DEFS[res_id]
			active_resources.append({
				"name": res_def["name"],
				"color": res_def["color"],
				"qty": qty,
			})

	# Calculate panel height dynamically
	var row_h =18.0
	var res_rows: int = ceili(active_resources.size() / 2.0)
	var panel_h: float = 16.0 + 28.0 + 8.0 + res_rows * row_h + 10.0  # top + credits + sep + resources + bottom
	ctrl.custom_minimum_size.y = panel_h
	ctrl.size.y = panel_h

	# --- Panel background (fade in on hover) ---
	if _eco_bg_alpha > 0.001:
		var bg =Rect2(Vector2.ZERO, Vector2(w, panel_h))
		ctrl.draw_rect(bg, Color(0.0, 0.02, 0.05, 0.6 * _eco_bg_alpha))
		var pd =UITheme.PRIMARY_DIM
		ctrl.draw_line(Vector2(0, 0), Vector2(w, 0), Color(pd.r, pd.g, pd.b, pd.a * _eco_bg_alpha), 1.0)
		var p =UITheme.PRIMARY
		ctrl.draw_line(Vector2(0, 0), Vector2(0, 10), Color(p.r, p.g, p.b, p.a * _eco_bg_alpha), 1.5)
		var pf =UITheme.PRIMARY_FAINT
		ctrl.draw_line(Vector2(4, panel_h - 1), Vector2(w - 4, panel_h - 1), Color(pf.r, pf.g, pf.b, pf.a * _eco_bg_alpha), 1.0)

	var x =10.0
	var y =16.0

	# --- Credits (prominent, golden) ---
	var cr_col =PlayerEconomy.CREDITS_COLOR
	# Diamond icon
	HudDrawHelpers.draw_diamond(ctrl, Vector2(x + 5, y - 3), 5.0, cr_col)
	# Amount
	var cr_amount =PlayerEconomy.format_credits(player_economy.credits)
	ctrl.draw_string(font, Vector2(x + 16, y), cr_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, cr_col)
	# "CR" label dimmer, to the right
	var amt_w =font.get_string_size(cr_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	ctrl.draw_string(font, Vector2(x + 18 + amt_w, y), "CR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(cr_col.r, cr_col.g, cr_col.b, 0.5))

	y += 14.0

	# --- Separator ---
	ctrl.draw_line(Vector2(x, y), Vector2(w - x, y), UITheme.PRIMARY_FAINT, 1.0)
	y += 10.0

	# --- Resources (2-column grid, only qty > 0) ---
	if active_resources.is_empty():
		ctrl.draw_string(font, Vector2(x + 2, y + 10), Locale.t("hud.no_resource"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	else:
		var col_w: float = (w - x * 2) / 2.0
		for i in active_resources.size():
			var col: int = i % 2
			var row: int = int(i * 0.5)
			var rx: float = x + col * col_w
			var ry: float = y + row * row_h

			var res: Dictionary = active_resources[i]
			var rc: Color = res["color"]

			# Colored square icon
			ctrl.draw_rect(Rect2(rx, ry, 8, 8), rc)
			ctrl.draw_rect(Rect2(rx, ry, 8, 8), Color(rc.r, rc.g, rc.b, 0.35), false, 1.0)

			# Quantity (bright)
			var qty_str =str(res["qty"])
			ctrl.draw_string(font, Vector2(rx + 13, ry + 8), qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(rc.r, rc.g, rc.b, 0.95))

			# Name (dimmer, after quantity)
			var qty_w =font.get_string_size(qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			ctrl.draw_string(font, Vector2(rx + 15 + qty_w, ry + 8), res["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(rc.r, rc.g, rc.b, 0.45))

	# Scanline
	if _eco_bg_alpha > 0.001:
		var sl =UITheme.SCANLINE
		var sy: float = fmod(scan_line_y, panel_h)
		ctrl.draw_line(Vector2(0, sy), Vector2(w, sy), Color(sl.r, sl.g, sl.b, sl.a * _eco_bg_alpha), 1.0)
