class_name EquipmentViewer
extends Control

# =============================================================================
# Equipment Screen — 3D Ship Viewer + Orbit Camera + Hardpoint Markers
# =============================================================================

signal hardpoint_selected(idx: int)

const EC =preload("res://scripts/ui/screens/station/equipment/equipment_constants.gd")

# --- 3D scene ---
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _viewer_camera: Camera3D = null
var _ship_model = null
var _hp_markers: Array[Dictionary] = []  # {mesh: MeshInstance3D, body: StaticBody3D, index: int}

# --- Model config (set via setup()) ---
var _model_path: String = ""
var _model_scale: float = 1.0
var _model_rotation: Vector3 = Vector3.ZERO
var _center_offset: Vector3 = Vector3.ZERO
var _root_basis: Basis = Basis.IDENTITY
var _is_station: bool = false

# --- Orbit camera ---
var orbit_yaw: float = 30.0
var orbit_pitch: float = -15.0
var orbit_distance: float = 8.0
var _orbit_min_dist: float = 3.0
var _orbit_max_dist: float = 60.0
var _orbit_dragging: bool = false
var _last_input_time: float = 0.0
var _pulse_time: float = 0.0

# --- References (set by parent) ---
var adapter: RefCounted = null
var weapon_manager = null
var is_live_mode: bool = false


func _process(delta: float) -> void:
	_pulse_time += delta
	_last_input_time += delta

	if not visible:
		return

	if not _orbit_dragging and _last_input_time > EC.AUTO_ROTATE_DELAY:
		orbit_yaw += EC.AUTO_ROTATE_SPEED * delta
		_update_orbit_camera()


# =============================================================================
# SETUP / CLEANUP
# =============================================================================
func setup(p_adapter: RefCounted, model_path: String, model_scale: float,
		center_offset: Vector3, model_rotation: Vector3, root_basis: Basis,
		p_weapon_manager, p_is_live: bool, p_is_station: bool) -> void:
	adapter = p_adapter
	weapon_manager = p_weapon_manager
	is_live_mode = p_is_live
	_is_station = p_is_station
	_model_path = model_path
	_model_scale = model_scale
	_model_rotation = model_rotation
	_center_offset = center_offset
	_root_basis = root_basis
	_last_input_time = 0.0
	orbit_yaw = 30.0
	orbit_pitch = -15.0
	_rebuild_viewport()


func cleanup() -> void:
	_hp_markers.clear()
	if _viewport_container:
		_viewport_container.queue_free()
		_viewport_container = null
		_viewport = null
		_viewer_camera = null
		_ship_model = null


func refresh_weapons() -> void:
	if _ship_model == null:
		return
	if is_live_mode and weapon_manager:
		var hp_configs: Array[Dictionary] = []
		var weapon_names: Array[StringName] = []
		for hp in weapon_manager.hardpoints:
			hp_configs.append({"position": hp.position, "rotation_degrees": hp.rotation_degrees, "id": hp.slot_id, "size": hp.slot_size, "is_turret": hp.is_turret})
			weapon_names.append(hp.mounted_weapon.weapon_name if hp.mounted_weapon else &"")
		_ship_model.apply_equipment(hp_configs, weapon_names, _root_basis)
	elif _is_station and adapter:
		var sta = adapter
		if sta:
			var hp_configs: Array[Dictionary] = sta._hp_configs
			var weapon_names: Array[StringName] = []
			for i in hp_configs.size():
				weapon_names.append(sta.get_mounted_weapon_name(i))
			_ship_model.apply_equipment(hp_configs, weapon_names, Basis.IDENTITY)
	elif adapter:
		var sd = adapter.get_ship_data()
		if sd == null:
			return
		var hp_configs: Array[Dictionary] = []
		var weapon_names: Array[StringName] = []
		for i in sd.hardpoints.size():
			hp_configs.append(sd.hardpoints[i])
			weapon_names.append(adapter.get_mounted_weapon_name(i))
		_ship_model.apply_equipment(hp_configs, weapon_names, _root_basis)


func update_marker_visuals(selected_hardpoint: int) -> void:
	if adapter == null:
		return
	var hp_count: int = adapter.get_hardpoint_count()
	for marker in _hp_markers:
		var idx: int = marker.index
		var mesh: MeshInstance3D = marker.mesh
		var mat: StandardMaterial3D = mesh.material_override
		if idx >= hp_count:
			continue
		var mounted: WeaponResource = adapter.get_mounted_weapon(idx)
		var has_weapon_model: bool = mounted != null and mounted.weapon_model_scene != ""

		if idx == selected_hardpoint:
			mesh.visible = true
			var type_col =_get_marker_color_for(mounted)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			var pulse =1.0 + sin(_pulse_time * 4.0) * 0.5
			mat.emission_energy_multiplier = pulse
		elif has_weapon_model:
			mesh.visible = false
		elif mounted:
			mesh.visible = true
			var type_col =_get_marker_color_for(mounted)
			mat.albedo_color = type_col
			mat.emission_enabled = true
			mat.emission = type_col
			mat.emission_energy_multiplier = 0.5
		else:
			mesh.visible = true
			mat.albedo_color = Color(0.3, 0.3, 0.3)
			mat.emission_enabled = false


func select_hardpoint(idx: int) -> void:
	hardpoint_selected.emit(idx)


func clear_selection() -> void:
	hardpoint_selected.emit(-1)


# =============================================================================
# PROJECTED LABELS — called from parent's _draw()
# =============================================================================
func draw_projected_labels(parent: Control, font: Font, viewer_w: float, viewer_h: float,
		selected_hardpoint: int) -> void:
	if _viewer_camera == null or adapter == null or _viewport == null:
		return

	var cam_fwd =-_viewer_camera.global_transform.basis.z
	var hp_count: int = adapter.get_hardpoint_count()

	for i in hp_count:
		var world_pos =Vector3.ZERO
		if is_live_mode and weapon_manager and i < weapon_manager.hardpoints.size():
			world_pos = _root_basis * weapon_manager.hardpoints[i].position
		elif i < _hp_markers.size():
			world_pos = _hp_markers[i].mesh.position

		var to_marker =(world_pos - _viewer_camera.global_position).normalized()
		if cam_fwd.dot(to_marker) < 0.1:
			continue

		if not _viewer_camera.is_position_behind(world_pos):
			var screen_pos =_viewer_camera.unproject_position(world_pos)
			var vp_size =Vector2(_viewport.size)
			if vp_size.x <= 0 or vp_size.y <= 0:
				continue
			var label_x =screen_pos.x / vp_size.x * viewer_w
			var label_y =screen_pos.y / vp_size.y * viewer_h + EC.CONTENT_TOP

			label_x = clampf(label_x, 10.0, viewer_w - 80.0)
			label_y = clampf(label_y, EC.CONTENT_TOP + 10, EC.CONTENT_TOP + viewer_h - 20)

			var slot_size: String = adapter.get_hardpoint_slot_size(i)
			var is_turret: bool = adapter.is_hardpoint_turret(i)
			var mounted: WeaponResource = adapter.get_mounted_weapon(i)
			var label_text ="%s%d" % [slot_size, i + 1]
			if is_turret:
				label_text += " T"
			if mounted:
				label_text += ": " + str(mounted.weapon_name)

			var col =UITheme.TEXT_DIM
			if i == selected_hardpoint:
				col = UITheme.PRIMARY
			elif mounted:
				col = EC.TYPE_COLORS.get(mounted.weapon_type, UITheme.TEXT_DIM)

			var tw =font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL).x
			parent.draw_rect(Rect2(label_x + 8, label_y - 10, tw + 8, 14), Color(0, 0, 0, 0.5))
			parent.draw_string(font, Vector2(label_x + 12, label_y), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, 150, UITheme.FONT_SIZE_SMALL, col)
			parent.draw_line(Vector2(label_x, label_y - 3), Vector2(label_x + 8, label_y - 3),
				Color(col.r, col.g, col.b, 0.4), 1.0)


# =============================================================================
# INPUT (orbit drag, zoom, marker click)
# =============================================================================
func handle_input(event: InputEvent, viewer_w: float, strip_top: float) -> bool:
	var in_viewer =false
	if "position" in event:
		in_viewer = event.position.x < viewer_w and event.position.y > EC.CONTENT_TOP and event.position.y < strip_top

	if event is InputEventMouseButton and in_viewer:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_orbit_dragging = true
				_last_input_time = 0.0
			else:
				if _orbit_dragging:
					_orbit_dragging = false
					_try_select_marker(event.position, viewer_w, strip_top)
			return true

		var zoom_step =orbit_distance * 0.08
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(_orbit_min_dist, orbit_distance - zoom_step)
			_last_input_time = 0.0
			_update_orbit_camera()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(_orbit_max_dist, orbit_distance + zoom_step)
			_last_input_time = 0.0
			_update_orbit_camera()
			return true

	if event is InputEventMouseMotion and _orbit_dragging:
		orbit_yaw += event.relative.x * EC.ORBIT_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch - event.relative.y * EC.ORBIT_SENSITIVITY,
			EC.ORBIT_PITCH_MIN, EC.ORBIT_PITCH_MAX)
		_last_input_time = 0.0
		_update_orbit_camera()
		return true

	return false


# =============================================================================
# PRIVATE
# =============================================================================
func _rebuild_viewport() -> void:
	cleanup()

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_viewport_container.show_behind_parent = true
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	var env =Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_color = Color(0.15, 0.2, 0.25)
	env.ambient_light_energy = 0.3
	var world_env =WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key_light =DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.95, 0.9)
	key_light.light_energy = 1.2
	key_light.rotation_degrees = Vector3(-45, 30, 0)
	_viewport.add_child(key_light)

	var light_scale =maxf(1.0, _model_scale)
	if _is_station:
		light_scale = 5.0
	var fill_light =OmniLight3D.new()
	fill_light.light_color = Color(0.8, 0.85, 0.9)
	fill_light.light_energy = 0.6
	fill_light.omni_range = 30.0 * light_scale
	fill_light.position = Vector3(-6, 2, -4) * light_scale
	_viewport.add_child(fill_light)

	var rim_light =OmniLight3D.new()
	rim_light.light_color = Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b)
	rim_light.light_energy = 0.4
	rim_light.omni_range = 30.0 * light_scale
	rim_light.position = Vector3(5, 1, 5) * light_scale
	_viewport.add_child(rim_light)

	_viewer_camera = Camera3D.new()
	if _is_station:
		var cam_data =StationHardpointConfig.get_equipment_camera_data()
		_viewer_camera.fov = cam_data.get("fov", 45.0)
	else:
		_viewer_camera.fov = 40.0
	_viewer_camera.near = 0.1
	_viewer_camera.far = 500.0
	_viewport.add_child(_viewer_camera)

	_ship_model = ShipModel.new()
	_ship_model.model_path = _model_path
	_ship_model.model_scale = _model_scale
	_ship_model.model_rotation_degrees = _model_rotation
	_ship_model.skip_centering = true
	_ship_model.engine_light_color = Color(0.3, 0.5, 1.0)
	_viewport.add_child(_ship_model)

	refresh_weapons()
	_create_hardpoint_markers()
	_auto_fit_camera()
	_update_orbit_camera()


func _auto_fit_camera() -> void:
	var max_radius: float = 2.0
	if _ship_model:
		var aabb =_ship_model.get_visual_aabb()
		for i in 8:
			var corner: Vector3 = aabb.get_endpoint(i) - _center_offset
			max_radius = maxf(max_radius, corner.length())

	if weapon_manager and is_live_mode:
		for hp in weapon_manager.hardpoints:
			var pos: Vector3 = _root_basis * hp.position - _center_offset
			max_radius = maxf(max_radius, pos.length())
	elif _is_station and adapter:
		var sta = adapter
		if sta:
			for cfg in sta._hp_configs:
				var pos: Vector3 = cfg.get("position", Vector3.ZERO) - _center_offset
				max_radius = maxf(max_radius, pos.length())

	var half_fov =deg_to_rad(_viewer_camera.fov * 0.5) if _viewer_camera else deg_to_rad(20.0)
	var ideal =max_radius / tan(half_fov) * 1.3
	orbit_distance = ideal
	_orbit_min_dist = ideal * 0.4
	_orbit_max_dist = ideal * 3.0

	if _viewer_camera:
		_viewer_camera.far = maxf(500.0, _orbit_max_dist + max_radius * 2.0)


func _update_orbit_camera() -> void:
	if _viewer_camera == null:
		return
	var yaw_rad =deg_to_rad(orbit_yaw)
	var pitch_rad =deg_to_rad(orbit_pitch)
	var offset =Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * orbit_distance
	_viewer_camera.position = _center_offset + offset
	_viewer_camera.look_at(_center_offset)


func _create_hardpoint_markers() -> void:
	_hp_markers.clear()
	if _viewport == null:
		return

	var hp_count: int = 0
	var hp_positions: Array[Vector3] = []
	var hp_turrets: Array[bool] = []

	if is_live_mode and weapon_manager:
		hp_count = weapon_manager.hardpoints.size()
		for hp in weapon_manager.hardpoints:
			hp_positions.append(hp.position)
			hp_turrets.append(hp.is_turret)
	elif _is_station and adapter:
		var sta = adapter
		if sta:
			hp_count = sta.get_hardpoint_count()
			for j in hp_count:
				if j < sta._hp_configs.size():
					hp_positions.append(sta._hp_configs[j].get("position", Vector3.ZERO))
				else:
					hp_positions.append(Vector3.ZERO)
				hp_turrets.append(sta.is_hardpoint_turret(j))
	elif adapter:
		var sd = adapter.get_ship_data()
		if sd:
			hp_count = sd.hardpoints.size()
			var configs =ShipFactory.get_hardpoint_configs(adapter.fleet_ship.ship_id)
			for j in sd.hardpoints.size():
				if j < configs.size():
					hp_positions.append(configs[j].get("position", Vector3.ZERO))
				else:
					hp_positions.append(Vector3.ZERO)
				hp_turrets.append(sd.hardpoints[j].get("is_turret", false))

	var marker_sz: float = 0.18 * _model_scale
	if _is_station:
		marker_sz = 2.0

	for i in hp_count:
		var is_turret: bool = hp_turrets[i] if i < hp_turrets.size() else false
		var mesh_inst =MeshInstance3D.new()
		if is_turret:
			var box =BoxMesh.new()
			box.size = Vector3(marker_sz, marker_sz, marker_sz)
			mesh_inst.mesh = box
			mesh_inst.rotation_degrees = Vector3(0, 45, 0)
		else:
			var sphere =SphereMesh.new()
			sphere.radius = marker_sz * 0.83
			sphere.height = marker_sz * 1.67
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh_inst.mesh = sphere

		var mat =StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.3)
		mat.emission_enabled = false
		mat.no_depth_test = true
		mat.render_priority = 10
		mesh_inst.material_override = mat
		var pos: Vector3 = hp_positions[i] if i < hp_positions.size() else Vector3.ZERO
		mesh_inst.position = _root_basis * pos
		_viewport.add_child(mesh_inst)

		var body =StaticBody3D.new()
		body.position = _root_basis * pos
		var col_shape =CollisionShape3D.new()
		var shape =SphereShape3D.new()
		shape.radius = marker_sz * 1.67
		col_shape.shape = shape
		body.add_child(col_shape)
		body.set_meta("hp_index", i)
		_viewport.add_child(body)

		_hp_markers.append({mesh = mesh_inst, body = body, index = i})


func _try_select_marker(mouse_pos: Vector2, viewer_w: float, strip_top: float) -> void:
	if _viewport == null or _viewer_camera == null or adapter == null:
		return

	var viewer_h =strip_top - EC.CONTENT_TOP
	if viewer_w <= 0 or viewer_h <= 0:
		return

	var local_x =mouse_pos.x / viewer_w
	var local_y =(mouse_pos.y - EC.CONTENT_TOP) / viewer_h
	if local_x < 0 or local_x > 1 or local_y < 0 or local_y > 1:
		return

	var vp_size =_viewport.size
	var vp_pos =Vector2(local_x * vp_size.x, local_y * vp_size.y)
	var from =_viewer_camera.project_ray_origin(vp_pos)
	var dir =_viewer_camera.project_ray_normal(vp_pos)

	if _viewport.world_3d == null:
		return
	var space =_viewport.world_3d.direct_space_state
	var query =PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result =space.intersect_ray(query)

	if result and result.collider:
		var collider =result.collider as Node3D
		if collider.has_meta("hp_index"):
			var idx: int = collider.get_meta("hp_index")
			hardpoint_selected.emit(idx)
			return

	hardpoint_selected.emit(-1)


func _get_marker_color_for(weapon: WeaponResource) -> Color:
	if weapon:
		return EC.TYPE_COLORS.get(weapon.weapon_type, UITheme.PRIMARY)
	return UITheme.PRIMARY


func layout(pos: Vector2, sz: Vector2) -> void:
	position = pos
	size = sz
	if _viewport_container:
		_viewport_container.position = Vector2.ZERO
		_viewport_container.size = sz
