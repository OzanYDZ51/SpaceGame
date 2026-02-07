class_name HangarScene
extends Node3D

# =============================================================================
# Hangar Scene - 3D interior for docked state
# Camera + lights + model are positioned in the .tscn via the Godot editor.
# This script only handles: mouse parallax, idle sway, prompt overlay.
# =============================================================================

const LOOK_YAW_RANGE: float = 40.0
const LOOK_PITCH_RANGE: float = 20.0
const LOOK_SMOOTH: float = 4.0

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
	var cy := s.y - 60.0
	var pulse := sin(_cam_t * 2.5) * 0.15 + 0.85

	# Dark pill background
	var pill_w := 360.0
	var pill_h := 36.0
	var pill_rect := Rect2((s.x - pill_w) * 0.5, cy - pill_h * 0.5, pill_w, pill_h)
	_prompt_ctrl.draw_rect(pill_rect, Color(0.0, 0.02, 0.06, 0.7))
	_prompt_ctrl.draw_rect(pill_rect, Color(0.2, 0.8, 0.9, 0.25 * pulse), false, 1.0)

	# "HANGAR" title at top center
	_prompt_ctrl.draw_string(font, Vector2(0, 40), "HANGAR",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 18, Color(0.3, 0.9, 1.0, 0.5))

	# Key prompts
	var col := Color(0.3, 0.9, 1.0, pulse)
	_prompt_ctrl.draw_string(font, Vector2(0, cy + 5),
		"TERMINAL  [F]        DÉCOLLER  [Échap]",
		HORIZONTAL_ALIGNMENT_CENTER, int(s.x), 13, col)


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

	if _prompt_ctrl:
		_prompt_ctrl.queue_redraw()


func display_ship(ship_model_path: String, _ship_model_scale: float) -> void:
	# Place a copy of the player's ship in the hangar.
	# Uses the exact transform from ShipPreview (editor placement) so WYSIWYG.
	if _docked_ship:
		_docked_ship.queue_free()
		_docked_ship = null

	_docked_ship = ShipModel.new()
	_docked_ship.model_path = ship_model_path
	# Use the scale the user set on ShipPreview in the editor (X component as uniform)
	_docked_ship.model_scale = _preview_local_scale.x
	_docked_ship.engine_light_color = Color(0.3, 0.5, 1.0)
	_docked_ship.name = "DockedShip"

	# Add as child of ShipSpawnPoint so it inherits the marker's world transform
	var spawn_point := get_node_or_null("ShipSpawnPoint") as Marker3D
	if spawn_point:
		spawn_point.add_child(_docked_ship)
		# Apply the same local offset as ShipPreview had in the editor
		_docked_ship.position = _preview_local_pos
		_docked_ship.rotation_degrees = _preview_local_rot
	else:
		# Fallback: in front of camera
		add_child(_docked_ship)
		_docked_ship.position = Vector3(_cam_base_pos.x, _cam_base_pos.y - 5.0, _cam_base_pos.z - 6.0)
		_docked_ship.rotation_degrees.y = 180.0


func activate() -> void:
	if _camera:
		_camera.current = true
	terminal_open = false
	_look_yaw = 0.0
	_look_pitch = 0.0


func deactivate() -> void:
	if _camera:
		_camera.current = false
	if _docked_ship:
		_docked_ship.queue_free()
		_docked_ship = null
