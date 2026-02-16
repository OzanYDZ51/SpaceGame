class_name ShipAnimator
extends Node

# =============================================================================
# Ship Animator - Drives model animations based on flight state.
# Searches the model tree for known animated node names and drives them
# procedurally based on ShipController input (nacelle tilt, fan spin, etc.).
# Automatically stops imported AnimationPlayers to avoid conflicts.
# =============================================================================

var _controller: ShipController = null

# --- Nacelle nodes (engine pods that tilt) ---
var _nacelle_r: Node3D = null  # R_Engine
var _nacelle_l: Node3D = null  # L_Engine
var _nacelle_base_quat_r: Quaternion = Quaternion.IDENTITY
var _nacelle_base_quat_l: Quaternion = Quaternion.IDENTITY

# --- Spinning parts (fans, turbines inside engines) ---
var _fans: Array[Node3D] = []

# --- Flap nodes (engine intake/exhaust flaps) ---
var _flaps_r: Array[Dictionary] = []  # { "node": Node3D, "base_quat": Quaternion }
var _flaps_l: Array[Dictionary] = []

# --- Animation state ---
var _nacelle_tilt: float = 0.0       # Current nacelle pitch offset (degrees)
var _nacelle_yaw_diff: float = 0.0   # Differential tilt for yaw (degrees)
var _fan_angle: float = 0.0          # Cumulative fan rotation (degrees)
var _flap_open: float = 0.0          # Flap opening amount (0-1)

# --- Config ---
const NACELLE_PITCH_RANGE: float = 20.0    # Max nacelle tilt from pitch input (degrees)
const NACELLE_YAW_RANGE: float = 12.0      # Max differential tilt from yaw (degrees)
const NACELLE_SPEED_TILT: float = -8.0     # Nacelle tilt in cruise mode (degrees, negative = backward)
const NACELLE_LERP_SPEED: float = 2.5      # Interpolation speed
const FAN_MAX_RPM: float = 1080.0          # Degrees per second at full throttle
const FAN_IDLE_RPM: float = 180.0          # Degrees per second at idle
const FLAP_LERP_SPEED: float = 3.0
const FLAP_MAX_ANGLE: float = 10.0         # Max flap opening (degrees)


func setup(ship_model) -> void:
	_controller = get_parent() as ShipController
	if _controller == null:
		push_error("ShipAnimator: Parent is not a ShipController")
		return

	# Find the actual model instance inside ShipModel → ModelPivot → child
	var model_pivot = ship_model.get_node_or_null("ModelPivot")
	if model_pivot == null or model_pivot.get_child_count() == 0:
		return
	var model_root: Node3D = model_pivot.get_child(0) as Node3D
	if model_root == null:
		return

	_find_animated_nodes(model_root)
	_stop_imported_animations(model_root)


func _find_animated_nodes(node: Node) -> void:
	if node is Node3D:
		var n3d: Node3D = node as Node3D
		var node_name: String = String(node.name)

		# Engine nacelles (the whole pod that tilts)
		if node_name == "R_Engine":
			_nacelle_r = n3d
			_nacelle_base_quat_r = n3d.quaternion
		elif node_name == "L_Engine":
			_nacelle_l = n3d
			_nacelle_base_quat_l = n3d.quaternion

		# Fans and turbines (spin around their local axis)
		# Target the actual spinning mesh nodes, not the _Rot parents
		elif node_name in ["Fan_01", "Fan_02", "Fan_03", "Turbine_01"]:
			_fans.append(n3d)

		# Engine flaps (articulated panels)
		elif node_name.begins_with("Flap_"):
			# Determine which engine this flap belongs to by checking ancestry
			var parent_engine: String = _find_ancestor_engine(n3d)
			var flap_data: Dictionary = {
				"node": n3d,
				"base_quat": n3d.quaternion,
			}
			if parent_engine == "R_Engine":
				_flaps_r.append(flap_data)
			elif parent_engine == "L_Engine":
				_flaps_l.append(flap_data)

	for child in node.get_children():
		_find_animated_nodes(child)


func _find_ancestor_engine(node: Node) -> String:
	var current: Node = node.get_parent()
	while current != null:
		if current.name == "R_Engine":
			return "R_Engine"
		elif current.name == "L_Engine":
			return "L_Engine"
		current = current.get_parent()
	return ""


func _stop_imported_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.stop()
		# Clear autoplay to prevent restart
		ap.autoplay = ""
	for child in node.get_children():
		_stop_imported_animations(child)


func _process(delta: float) -> void:
	if _controller == null:
		return
	_update_nacelles(delta)
	_update_fans(delta)
	_update_flaps(delta)


func _update_nacelles(delta: float) -> void:
	if _nacelle_r == null and _nacelle_l == null:
		return

	# Read normalized input from controller
	var pitch_norm: float = 0.0
	var yaw_norm: float = 0.0
	var speed_tilt: float = 0.0

	if _controller.ship_data:
		var pitch_max: float = maxf(_controller.ship_data.rotation_pitch_speed, 1.0)
		var yaw_max: float = maxf(_controller.ship_data.rotation_yaw_speed, 1.0)
		pitch_norm = clampf(_controller._current_pitch_rate / pitch_max, -1.0, 1.0)
		yaw_norm = clampf(_controller._current_yaw_rate / yaw_max, -1.0, 1.0)

	# In cruise/boost, tilt nacelles backward for "full thrust" look
	if _controller.speed_mode == Constants.SpeedMode.CRUISE:
		speed_tilt = NACELLE_SPEED_TILT
	elif _controller.speed_mode == Constants.SpeedMode.BOOST:
		speed_tilt = NACELLE_SPEED_TILT * 0.5

	var target_tilt: float = pitch_norm * NACELLE_PITCH_RANGE + speed_tilt
	var target_yaw: float = yaw_norm * NACELLE_YAW_RANGE

	_nacelle_tilt = lerpf(_nacelle_tilt, target_tilt, delta * NACELLE_LERP_SPEED)
	_nacelle_yaw_diff = lerpf(_nacelle_yaw_diff, target_yaw, delta * NACELLE_LERP_SPEED)

	# Apply rotation: both nacelles tilt the same for pitch, opposite for yaw
	if _nacelle_r:
		var angle_r: float = deg_to_rad(_nacelle_tilt + _nacelle_yaw_diff)
		_nacelle_r.quaternion = _nacelle_base_quat_r * Quaternion(Vector3.RIGHT, angle_r)

	if _nacelle_l:
		var angle_l: float = deg_to_rad(_nacelle_tilt - _nacelle_yaw_diff)
		_nacelle_l.quaternion = _nacelle_base_quat_l * Quaternion(Vector3.RIGHT, angle_l)


func _update_fans(delta: float) -> void:
	if _fans.is_empty():
		return

	# Fan speed based on throttle and speed mode
	var throttle: float = absf(_controller.throttle_input.z)
	if _controller.speed_mode == Constants.SpeedMode.CRUISE:
		throttle = 1.0
	elif _controller.speed_mode == Constants.SpeedMode.BOOST:
		throttle = 1.0

	var rpm: float = lerpf(FAN_IDLE_RPM, FAN_MAX_RPM, clampf(throttle, 0.0, 1.0))
	_fan_angle += rpm * delta
	if _fan_angle > 360.0:
		_fan_angle -= 360.0

	var fan_rad: float = deg_to_rad(_fan_angle)
	for fan in _fans:
		if is_instance_valid(fan):
			# Fans spin around their local Z axis (engine forward direction)
			fan.quaternion = Quaternion(Vector3.FORWARD, fan_rad)


func _update_flaps(delta: float) -> void:
	if _flaps_r.is_empty() and _flaps_l.is_empty():
		return

	# Flaps open with throttle
	var throttle: float = absf(_controller.throttle_input.z)
	if _controller.speed_mode == Constants.SpeedMode.BOOST:
		throttle = 1.0
	elif _controller.speed_mode == Constants.SpeedMode.CRUISE:
		throttle = 0.8

	var target_open: float = clampf(throttle, 0.0, 1.0)
	_flap_open = lerpf(_flap_open, target_open, delta * FLAP_LERP_SPEED)

	var flap_rad: float = deg_to_rad(_flap_open * FLAP_MAX_ANGLE)
	for flap_data in _flaps_r:
		var n: Node3D = flap_data["node"]
		if is_instance_valid(n):
			n.quaternion = flap_data["base_quat"] * Quaternion(Vector3.RIGHT, flap_rad)
	for flap_data in _flaps_l:
		var n: Node3D = flap_data["node"]
		if is_instance_valid(n):
			n.quaternion = flap_data["base_quat"] * Quaternion(Vector3.RIGHT, flap_rad)
