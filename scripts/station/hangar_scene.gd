class_name HangarScene
extends Node3D

# =============================================================================
# Hangar Scene - 3D interior for docked state
# Camera + lights + model are positioned in the .tscn via the Godot editor.
# Handles: mouse parallax, idle sway, prompt overlay, ship selection cycling.
# =============================================================================

signal ship_selected(ship_id: StringName)

const LOOK_YAW_RANGE: float = 40.0
const LOOK_PITCH_RANGE: float = 20.0
const LOOK_SMOOTH: float = 4.0
const ARROW_X_OFFSET: float = 6.0

var _camera: Camera3D = null
var _cam_t: float = 0.0
var _prompt_layer: CanvasLayer = null
var _prompt_ctrl: Control = null

## Set by GameManager when station terminal UI is open (hides prompt)
var terminal_open: bool = false

var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_base_rot: Vector3 = Vector3.ZERO
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _docked_ship: ShipModel = null
var _preview_local_pos: Vector3 = Vector3.ZERO
var _preview_local_rot: Vector3 = Vector3.ZERO
var _preview_local_scale: Vector3 = Vector3.ONE

# Equipment data for current player ship (passed from DockInstance)
var _current_hp_configs: Array[Dictionary] = []
var _current_weapon_names: Array[StringName] = []

# Ship selection state
var _ship_ids: Array[StringName] = []
var _current_index: int = 0
var _arrow_left: MeshInstance3D = null
var _arrow_right: MeshInstance3D = null
var _label_name: Label3D = null
var _label_stats: Label3D = null
var _selection_active: bool = false


func _ready() -> void:
	_camera = $HangarCamera as Camera3D
	if _camera == null:
		push_error("HangarScene: No 'HangarCamera' node found — add one in the .tscn")
		return

	# Use the camera position/rotation as placed in the editor
	_cam_base_pos = _camera.position
	_cam_base_rot = _camera.rotation_degrees

	# Save ShipPreview transform from editor, then remove preview (replaced by display_ship)
	var spawn_point := get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point:
		var preview := spawn_point.get_node_or_null("ShipPreview") as Node3D
		if preview:
			_preview_local_pos = preview.position
			_preview_local_rot = preview.rotation_degrees
			_preview_local_scale = preview.scale
			preview.queue_free()

	_setup_prompt_overlay()


func _setup_prompt_overlay() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 10
	add_child(_prompt_layer)

	_prompt_ctrl = Control.new()
	_prompt_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_ctrl.draw.connect(_draw_prompt)
	_prompt_layer.add_child(_prompt_ctrl)


func _draw_prompt() -> void:
	if terminal_open:
		return

	var s := _prompt_ctrl.size
	var font := ThemeDB.fallback_font
	var pulse := sin(_cam_t * 2.5) * 0.15 + 0.85

	# "HANGAR" title at top center — thin, understated
	_prompt_ctrl.draw_string(font, Vector2(0, 32), "HANGAR",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 11, Color(0.2, 0.7, 0.85, 0.35))
	# Thin underline accent
	var title_w: float = font.get_string_size("HANGAR", HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
	var line_x: float = (s.x - title_w) * 0.5
	_prompt_ctrl.draw_line(Vector2(line_x, 36), Vector2(line_x + title_w, 36),
		Color(0.15, 0.6, 0.8, 0.2 * pulse), 1.0)

	# Ship selection prompt (above main prompt)
	if _selection_active and _ship_ids.size() > 1:
		var sel_cy := s.y - 84.0
		var sel_pill_w := 300.0
		var sel_pill_h := 22.0
		var sel_rect := Rect2((s.x - sel_pill_w) * 0.5, sel_cy - sel_pill_h * 0.5, sel_pill_w, sel_pill_h)
		_prompt_ctrl.draw_rect(sel_rect, Color(0.0, 0.02, 0.06, 0.5))
		_prompt_ctrl.draw_rect(sel_rect, Color(0.15, 0.6, 0.8, 0.15 * pulse), false, 1.0)
		var sel_col := Color(0.25, 0.8, 0.95, 0.7 * pulse)
		_prompt_ctrl.draw_string(font, Vector2(0, sel_cy + 4),
			"\u25C0  [A]   CHANGER DE VAISSEAU   [D]  \u25B6",
			HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 9, sel_col)

	# Main prompt pill
	var cy := s.y - 52.0
	var pill_w := 260.0
	var pill_h := 24.0
	var pill_rect := Rect2((s.x - pill_w) * 0.5, cy - pill_h * 0.5, pill_w, pill_h)
	_prompt_ctrl.draw_rect(pill_rect, Color(0.0, 0.02, 0.06, 0.55))
	_prompt_ctrl.draw_rect(pill_rect, Color(0.15, 0.6, 0.8, 0.18 * pulse), false, 1.0)

	# Key prompts
	var col := Color(0.25, 0.8, 0.95, 0.7 * pulse)
	_prompt_ctrl.draw_string(font, Vector2(0, cy + 4),
		"TERMINAL  [F]        DÉCOLLER  [Échap]",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 10, col)


func _process(delta: float) -> void:
	_cam_t += delta
	if _camera == null:
		return

	# Mouse parallax
	var vp := get_viewport()
	if vp:
		var mouse := vp.get_mouse_position()
		var screen := vp.get_visible_rect().size
		if screen.x > 0 and screen.y > 0:
			var nx: float = clampf((mouse.x / screen.x - 0.5) * 2.0, -1.0, 1.0)
			var ny: float = clampf((mouse.y / screen.y - 0.5) * 2.0, -1.0, 1.0)
			_look_yaw = lerp(_look_yaw, -nx * LOOK_YAW_RANGE, LOOK_SMOOTH * delta)
			_look_pitch = lerp(_look_pitch, -ny * LOOK_PITCH_RANGE, LOOK_SMOOTH * delta)

	# Subtle idle sway
	var sway_yaw: float = sin(_cam_t * 0.08) * 0.8
	var sway_x: float = sin(_cam_t * 0.12) * 0.1
	var sway_y: float = sin(_cam_t * 0.09) * 0.05

	_camera.rotation_degrees.x = _cam_base_rot.x + _look_pitch
	_camera.rotation_degrees.y = _cam_base_rot.y + _look_yaw + sway_yaw
	_camera.position.x = _cam_base_pos.x + sway_x
	_camera.position.y = _cam_base_pos.y + sway_y

	# Arrow pulse animation
	if _selection_active and _ship_ids.size() > 1:
		var pulse_scale: float = 1.0 + sin(_cam_t * 3.0) * 0.1
		if _arrow_left:
			_arrow_left.scale = Vector3.ONE * pulse_scale
		if _arrow_right:
			_arrow_right.scale = Vector3.ONE * pulse_scale

	if _prompt_ctrl:
		_prompt_ctrl.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _selection_active or terminal_open:
		return
	if _ship_ids.size() <= 1:
		return
	if not (event is InputEventKey) or not event.pressed:
		return

	var changed := false
	if event.physical_keycode == KEY_A:
		_current_index = (_current_index - 1 + _ship_ids.size()) % _ship_ids.size()
		changed = true
	elif event.physical_keycode == KEY_D:
		_current_index = (_current_index + 1) % _ship_ids.size()
		changed = true

	if changed:
		get_viewport().set_input_as_handled()
		var new_id: StringName = _ship_ids[_current_index]
		var data := ShipRegistry.get_ship_data(new_id)
		if data:
			var configs := ShipFactory.get_hardpoint_configs(new_id)
			var model_rot := ShipFactory.get_model_rotation(new_id)
			var rb := ShipFactory.get_root_basis(new_id)
			var sms := ShipFactory.get_scene_model_scale(new_id)
			display_ship(data.model_path, sms, configs, data.default_loadout, model_rot, rb)
			_update_ship_labels(data)
			ship_selected.emit(new_id)


func display_ship(ship_model_path: String, ship_model_scale: float, hp_configs: Array[Dictionary] = [], weapon_names: Array[StringName] = [], model_rotation: Vector3 = Vector3.ZERO, root_basis: Basis = Basis.IDENTITY) -> void:
	# Uses actual scene model_scale (no override). ShipPreview's scale applied
	# to the node itself for uniform hangar fit (mesh + weapons scale together).
	if _docked_ship:
		_docked_ship.queue_free()
		_docked_ship = null

	_docked_ship = ShipModel.new()
	_docked_ship.model_path = ship_model_path
	_docked_ship.model_scale = ship_model_scale  # actual scene value — never overridden
	_docked_ship.model_rotation_degrees = model_rotation
	_docked_ship.skip_centering = true  # keep raw positions so weapons align with mesh
	_docked_ship.engine_light_color = Color(0.3, 0.5, 1.0)
	_docked_ship.name = "DockedShip"

	var spawn_point := get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point:
		spawn_point.add_child(_docked_ship)
		_docked_ship.position = _preview_local_pos
		_docked_ship.rotation_degrees = _preview_local_rot
		# Uniform node scale from ShipPreview — scales everything together
		_docked_ship.scale = _preview_local_scale
	else:
		add_child(_docked_ship)
		_docked_ship.position = Vector3(_cam_base_pos.x, _cam_base_pos.y - 5.0, _cam_base_pos.z - 6.0)
		_docked_ship.rotation_degrees.y = 180.0

	if not hp_configs.is_empty():
		_docked_ship.apply_equipment(hp_configs, weapon_names, root_basis)


func setup_ship_selection(current_ship_id: StringName) -> void:
	_ship_ids.clear()
	_ship_ids = ShipRegistry.get_all_ship_ids()
	# Sort for consistent ordering
	_ship_ids.sort()
	_current_index = _ship_ids.find(current_ship_id)
	if _current_index < 0:
		_current_index = 0
	_selection_active = true

	if _ship_ids.size() > 1:
		_create_3d_arrows()
		_create_ship_labels()
		# Set initial label text
		var data := ShipRegistry.get_ship_data(_ship_ids[_current_index])
		if data:
			_update_ship_labels(data)


func _create_3d_arrows() -> void:
	var spawn_point := get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point == null:
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.12, 0.7, 0.9, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.85)
	mat.emission_energy_multiplier = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Left arrow (slim chevron)
	var prism_left := PrismMesh.new()
	prism_left.size = Vector3(0.35, 0.7, 0.12)
	_arrow_left = MeshInstance3D.new()
	_arrow_left.mesh = prism_left
	_arrow_left.material_override = mat
	_arrow_left.name = "ArrowLeft"
	spawn_point.add_child(_arrow_left)
	_arrow_left.position = _preview_local_pos + Vector3(-ARROW_X_OFFSET, 0, 0)
	_arrow_left.rotation_degrees = Vector3(0, 0, 90)  # Point left

	# Right arrow (slim chevron)
	var prism_right := PrismMesh.new()
	prism_right.size = Vector3(0.35, 0.7, 0.12)
	_arrow_right = MeshInstance3D.new()
	_arrow_right.mesh = prism_right
	_arrow_right.material_override = mat
	_arrow_right.name = "ArrowRight"
	spawn_point.add_child(_arrow_right)
	_arrow_right.position = _preview_local_pos + Vector3(ARROW_X_OFFSET, 0, 0)
	_arrow_right.rotation_degrees = Vector3(0, 0, -90)  # Point right


func _create_ship_labels() -> void:
	var spawn_point := get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point == null:
		return

	# Ship name label — compact holographic tag
	_label_name = Label3D.new()
	_label_name.name = "ShipNameLabel"
	_label_name.font_size = 18
	_label_name.modulate = Color(0.2, 0.8, 0.95, 0.85)
	_label_name.outline_modulate = Color(0, 0.02, 0.05, 0.6)
	_label_name.outline_size = 2
	_label_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_name.no_depth_test = true
	_label_name.fixed_size = true
	_label_name.pixel_size = 0.002
	spawn_point.add_child(_label_name)
	_label_name.position = _preview_local_pos + Vector3(0, -3.0, 0)

	# Stats label — small, dim secondary info
	_label_stats = Label3D.new()
	_label_stats.name = "ShipStatsLabel"
	_label_stats.font_size = 11
	_label_stats.modulate = Color(0.35, 0.55, 0.68, 0.6)
	_label_stats.outline_modulate = Color(0, 0.01, 0.04, 0.5)
	_label_stats.outline_size = 1
	_label_stats.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_stats.no_depth_test = true
	_label_stats.fixed_size = true
	_label_stats.pixel_size = 0.002
	spawn_point.add_child(_label_stats)
	_label_stats.position = _preview_local_pos + Vector3(0, -3.6, 0)


func _update_ship_labels(data: ShipData) -> void:
	if _label_name:
		_label_name.text = String(data.ship_name).to_upper()
	if _label_stats:
		var weapons_count: int = data.default_loadout.size()
		_label_stats.text = "Coque: %d  |  Bouclier: %d  |  Vitesse: %d  |  Armes: %d" % [
			int(data.hull_hp), int(data.shield_hp), int(data.max_speed_normal), weapons_count
		]


func _cleanup_selection_visuals() -> void:
	if _arrow_left:
		_arrow_left.queue_free()
		_arrow_left = null
	if _arrow_right:
		_arrow_right.queue_free()
		_arrow_right = null
	if _label_name:
		_label_name.queue_free()
		_label_name = null
	if _label_stats:
		_label_stats.queue_free()
		_label_stats = null
	_selection_active = false


func activate() -> void:
	if _camera:
		_camera.current = true
	terminal_open = false
	_look_yaw = 0.0
	_look_pitch = 0.0


func deactivate() -> void:
	if _camera:
		_camera.current = false
	_cleanup_selection_visuals()
	if _docked_ship:
		_docked_ship.queue_free()
		_docked_ship = null
