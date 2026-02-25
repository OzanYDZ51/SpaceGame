class_name HangarScene
extends Node3D

# =============================================================================
# Hangar Scene - 3D interior for docked state
# Camera + lights + model are positioned in the .tscn via the Godot editor.
# Handles: mouse parallax, idle sway, prompt overlay, ship selection cycling.
# =============================================================================

signal ship_selected(fleet_index: int)

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
var _docked_ship = null
var _preview_local_pos: Vector3 = Vector3.ZERO
var _preview_local_rot: Vector3 = Vector3.ZERO
var _preview_local_scale: Vector3 = Vector3.ONE

# Ship selection state
var _fleet_indices: Array[int] = []
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
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# Use the camera position/rotation as placed in the editor
	_cam_base_pos = _camera.position
	_cam_base_rot = _camera.rotation_degrees

	# Load hangar 3D model dynamically (avoids broken ext_resource if .glb import is stale)
	_load_hangar_model()

	# Default ship preview transform (was previously baked from ShipPreview node in .tscn)
	_preview_local_pos = Vector3(0, -1.1458678, -8.755791)
	_preview_local_rot = Vector3.ZERO
	_preview_local_scale = Vector3(0.15, 0.15, 0.15)

	_setup_prompt_overlay()


func _load_hangar_model() -> void:
	var glb_path := "res://assets/models/hangar_interior.glb"
	if not ResourceLoader.exists(glb_path):
		push_warning("HangarScene: %s not found — hangar visuals skipped" % glb_path)
		return
	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		push_warning("HangarScene: Failed to load %s — hangar visuals skipped" % glb_path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return
	model.name = "HangarModel"
	model.transform = Transform3D(
		Vector3(0.0024, 0, 0), Vector3(0, 0.0024, 0), Vector3(0, 0, 0.0024),
		Vector3(0, -8.34769, 0)
	)
	add_child(model)
	move_child(model, 0)  # Keep model behind camera/lights in tree


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

	var s =_prompt_ctrl.size
	var font =UITheme.get_font_medium()
	var pulse =sin(_cam_t * 2.5) * 0.15 + 0.85

	# "HANGAR" title at top center — thin, understated
	_prompt_ctrl.draw_string(font, Vector2(0, 32), "HANGAR",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 13, Color(0.2, 0.7, 0.85, 0.35))
	# Thin underline accent
	var title_w: float = font.get_string_size("HANGAR", HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
	var line_x: float = (s.x - title_w) * 0.5
	_prompt_ctrl.draw_line(Vector2(line_x, 36), Vector2(line_x + title_w, 36),
		Color(0.15, 0.6, 0.8, 0.2 * pulse), 1.0)

	# Ship selection prompt (above main prompt)
	if _selection_active and _fleet_indices.size() > 1:
		var sel_cy =s.y - 84.0
		var sel_pill_w =300.0
		var sel_pill_h =22.0
		var sel_rect =Rect2((s.x - sel_pill_w) * 0.5, sel_cy - sel_pill_h * 0.5, sel_pill_w, sel_pill_h)
		_prompt_ctrl.draw_rect(sel_rect, Color(0.0, 0.02, 0.06, 0.5))
		_prompt_ctrl.draw_rect(sel_rect, Color(0.15, 0.6, 0.8, 0.15 * pulse), false, 1.0)
		var sel_col =Color(0.25, 0.8, 0.95, 0.7 * pulse)
		_prompt_ctrl.draw_string(font, Vector2(0, sel_cy + 4),
			"\u25C0  [A]   CHANGER DE VAISSEAU   [D]  \u25B6",
			HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 12, sel_col)

	# Main prompt pill
	var cy =s.y - 52.0
	var pill_w =260.0
	var pill_h =24.0
	var pill_rect =Rect2((s.x - pill_w) * 0.5, cy - pill_h * 0.5, pill_w, pill_h)
	_prompt_ctrl.draw_rect(pill_rect, Color(0.0, 0.02, 0.06, 0.55))
	_prompt_ctrl.draw_rect(pill_rect, Color(0.15, 0.6, 0.8, 0.18 * pulse), false, 1.0)

	# Key prompts
	var col =Color(0.25, 0.8, 0.95, 0.7 * pulse)
	_prompt_ctrl.draw_string(font, Vector2(0, cy + 4),
		"TERMINAL  [F]        DÉCOLLER  [Échap]",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 12, col)


func _process(delta: float) -> void:
	_cam_t += delta
	if _camera == null:
		return

	# Mouse parallax
	var vp =get_viewport()
	if vp:
		var mouse =vp.get_mouse_position()
		var screen =vp.get_visible_rect().size
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
	if _selection_active and _fleet_indices.size() > 1:
		var pulse_scale: float = 1.0 + sin(_cam_t * 3.0) * 0.1
		if _arrow_left:
			_arrow_left.scale = Vector3.ONE * pulse_scale
		if _arrow_right:
			_arrow_right.scale = Vector3.ONE * pulse_scale

	if _prompt_ctrl:
		_prompt_ctrl.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _selection_active or terminal_open:
		return
	if _fleet_indices.size() <= 1:
		return
	if not (event is InputEventKey) or not event.pressed:
		return

	var changed =false
	if event.physical_keycode == KEY_A:
		_current_index = (_current_index - 1 + _fleet_indices.size()) % _fleet_indices.size()
		changed = true
	elif event.physical_keycode == KEY_D:
		_current_index = (_current_index + 1) % _fleet_indices.size()
		changed = true

	if changed:
		get_viewport().set_input_as_handled()
		var fleet_idx: int = _fleet_indices[_current_index]
		_display_fleet_ship(fleet_idx)
		ship_selected.emit(fleet_idx)


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

	var spawn_point =get_node_or_null("ShipSpawnPoint") as Marker3D
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


func setup_ship_selection(active_fleet_index: int, fleet_indices: Array[int]) -> void:
	_fleet_indices.clear()
	_fleet_indices.assign(fleet_indices)
	_current_index = _fleet_indices.find(active_fleet_index)
	if _current_index < 0:
		_current_index = 0
	_selection_active = true

	if _fleet_indices.size() > 1:
		_create_3d_arrows()
		_create_ship_labels()
		# Set initial label text
		if _current_index < _fleet_indices.size():
			var fleet =GameManager.player_fleet
			if fleet:
				var fs =fleet.ships[_fleet_indices[_current_index]]
				var data =ShipRegistry.get_ship_data(fs.ship_id)
				if data:
					_update_ship_labels(data, fs.custom_name)


## Refresh the ship list (called when fleet changes, e.g. after buying a ship).
func refresh_ship_list(active_fleet_index: int, fleet_indices: Array[int]) -> void:
	_cleanup_selection_visuals()
	setup_ship_selection(active_fleet_index, fleet_indices)
	# Re-display the currently selected ship
	if _current_index >= 0 and _current_index < _fleet_indices.size():
		_display_fleet_ship(_fleet_indices[_current_index])


## Display a fleet ship in the hangar by fleet index.
func _display_fleet_ship(fleet_idx: int) -> void:
	var fleet =GameManager.player_fleet
	if fleet == null or fleet_idx < 0 or fleet_idx >= fleet.ships.size():
		return
	var fs =fleet.ships[fleet_idx]
	var ship_id =fs.ship_id
	var data =ShipRegistry.get_ship_data(ship_id)
	if data == null:
		return
	var configs =ShipFactory.get_hardpoint_configs(ship_id)
	var model_rot =ShipFactory.get_model_rotation(ship_id)
	var rb =ShipFactory.get_root_basis(ship_id)
	var sms =ShipFactory.get_scene_model_scale(ship_id)
	# Show equipped weapons from FleetShip loadout (not defaults)
	display_ship(data.model_path, sms, configs, fs.weapons, model_rot, rb)
	_update_ship_labels(data, fs.custom_name)


func _create_3d_arrows() -> void:
	var spawn_point =get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point == null:
		return

	var mat =StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.12, 0.7, 0.9, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.85)
	mat.emission_energy_multiplier = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Left arrow (slim chevron)
	var prism_left =PrismMesh.new()
	prism_left.size = Vector3(0.35, 0.7, 0.12)
	_arrow_left = MeshInstance3D.new()
	_arrow_left.mesh = prism_left
	_arrow_left.material_override = mat
	_arrow_left.name = "ArrowLeft"
	spawn_point.add_child(_arrow_left)
	_arrow_left.position = _preview_local_pos + Vector3(-ARROW_X_OFFSET, 0, 0)
	_arrow_left.rotation_degrees = Vector3(0, 0, 90)  # Point left

	# Right arrow (slim chevron)
	var prism_right =PrismMesh.new()
	prism_right.size = Vector3(0.35, 0.7, 0.12)
	_arrow_right = MeshInstance3D.new()
	_arrow_right.mesh = prism_right
	_arrow_right.material_override = mat
	_arrow_right.name = "ArrowRight"
	spawn_point.add_child(_arrow_right)
	_arrow_right.position = _preview_local_pos + Vector3(ARROW_X_OFFSET, 0, 0)
	_arrow_right.rotation_degrees = Vector3(0, 0, -90)  # Point right


func _create_ship_labels() -> void:
	var spawn_point =get_node_or_null("ShipSpawnPoint") as Marker3D
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


func _update_ship_labels(data: ShipData, custom_name: String = "") -> void:
	if _label_name:
		var display_name =custom_name if custom_name != "" else String(data.ship_name)
		_label_name.text = display_name.to_upper()
	if _label_stats:
		var weapons_count: int = data.hardpoints.size()
		_label_stats.text = "Coque: %d  |  Bouclier: %d  |  Vitesse: %d  |  Emplacements: %d" % [
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
