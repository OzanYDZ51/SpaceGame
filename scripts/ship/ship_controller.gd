class_name ShipController
extends RigidBody3D

# =============================================================================
# Ship Controller - 6DOF Space Flight
# Direct acceleration model. Mouse controls rotation. Keyboard controls thrust.
# Supports both player and AI control via is_player_controlled flag.
# Stats are data-driven from ShipData when available, falls back to Constants.
# =============================================================================

@export_group("Control")
@export var is_player_controlled: bool = true
@export var flight_assist: bool = true
@export var faction: StringName = &"neutral"
@export var rotation_responsiveness: float = 1.0  ## AI ships use higher values
@export var auto_roll_factor: float = 0.35

@export_group("Ship Data")
@export var ship_data: ShipData = null

# --- Public state (read by HUD/camera/AI) ---
var speed_mode: int = Constants.SpeedMode.NORMAL
var current_speed: float = 0.0
var throttle_input: Vector3 = Vector3.ZERO

# --- Rotation state ---
var _target_pitch_rate: float = 0.0
var _target_yaw_rate: float = 0.0
var _target_roll_rate: float = 0.0
var _current_pitch_rate: float = 0.0
var _current_yaw_rate: float = 0.0
var _current_roll_rate: float = 0.0

# --- Mouse ---
var _mouse_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	can_sleep = false
	freeze = false
	custom_integrator = true
	mass = ship_data.mass if ship_data else Constants.SHIP_MASS
	linear_damp = 0.0
	angular_damp = 0.0
	collision_layer = Constants.LAYER_SHIPS
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS


func _input(event: InputEvent) -> void:
	if not is_player_controlled:
		return
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_delta += event.relative


func _process(_delta: float) -> void:
	if is_player_controlled:
		_read_input()
		_handle_player_weapon_input()
	_update_visuals()


func _read_input() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		throttle_input = Vector3.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
		_target_roll_rate = 0.0
		_mouse_delta = Vector2.ZERO
		return

	# === THRUST ===
	var thrust := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		thrust.z -= 1.0
	if Input.is_action_pressed("move_backward"):
		thrust.z += 1.0
	if Input.is_action_pressed("strafe_left"):
		thrust.x -= 1.0
	if Input.is_action_pressed("strafe_right"):
		thrust.x += 1.0
	if Input.is_action_pressed("strafe_up"):
		thrust.y += 1.0
	if Input.is_action_pressed("strafe_down"):
		thrust.y -= 1.0
	if thrust.length_squared() > 1.0:
		thrust = thrust.normalized()
	throttle_input = thrust

	# === ROTATION from mouse ===
	var pitch_speed := ship_data.rotation_pitch_speed if ship_data else Constants.ROTATION_PITCH_SPEED
	var yaw_speed := ship_data.rotation_yaw_speed if ship_data else Constants.ROTATION_YAW_SPEED
	_target_pitch_rate = -_mouse_delta.y * Constants.MOUSE_SENSITIVITY * pitch_speed
	_target_yaw_rate = -_mouse_delta.x * Constants.MOUSE_SENSITIVITY * yaw_speed
	_mouse_delta = Vector2.ZERO

	# Roll from keyboard
	var roll_speed := ship_data.rotation_roll_speed if ship_data else Constants.ROTATION_ROLL_SPEED
	_target_roll_rate = 0.0
	if Input.is_action_pressed("roll_left"):
		_target_roll_rate = roll_speed
	if Input.is_action_pressed("roll_right"):
		_target_roll_rate = -roll_speed

	# === SPEED MODE ===
	if Input.is_action_just_pressed("toggle_cruise"):
		speed_mode = Constants.SpeedMode.NORMAL if speed_mode == Constants.SpeedMode.CRUISE else Constants.SpeedMode.CRUISE

	if Input.is_action_pressed("boost") and speed_mode != Constants.SpeedMode.CRUISE:
		speed_mode = Constants.SpeedMode.BOOST
	elif not Input.is_action_pressed("boost") and speed_mode == Constants.SpeedMode.BOOST:
		speed_mode = Constants.SpeedMode.NORMAL

	if Input.is_action_just_pressed("toggle_flight_assist"):
		flight_assist = not flight_assist

	# === ENERGY PIPS ===
	var energy_sys := get_node_or_null("EnergySystem") as EnergySystem
	if energy_sys:
		if Input.is_action_just_pressed("pip_weapons"):
			energy_sys.increase_pip(&"weapons")
		if Input.is_action_just_pressed("pip_shields"):
			energy_sys.increase_pip(&"shields")
		if Input.is_action_just_pressed("pip_engines"):
			energy_sys.increase_pip(&"engines")
		if Input.is_action_just_pressed("pip_reset"):
			energy_sys.reset_pips()


func _handle_player_weapon_input() -> void:
	var wm := get_node_or_null("WeaponManager") as WeaponManager
	if wm == null:
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Aim where the crosshair points: raycast from camera through screen center
	# Lead indicator is displayed on HUD as a guide, but player must aim manually
	var target_pos := _get_crosshair_aim_point()
	var targeting := get_node_or_null("TargetingSystem") as TargetingSystem

	# Weapon toggles
	for i in mini(4, wm.get_hardpoint_count()):
		if Input.is_action_just_pressed("toggle_weapon_%d" % (i + 1)):
			wm.toggle_hardpoint(i)

	if Input.is_action_pressed("fire_primary"):
		wm.fire_group(0, true, target_pos)
	if Input.is_action_pressed("fire_secondary"):
		wm.fire_group(1, false, target_pos)

	# Targeting
	if targeting:
		if Input.is_action_just_pressed("target_cycle"):
			targeting.cycle_target_forward()
		if Input.is_action_just_pressed("target_nearest"):
			targeting.target_nearest_hostile()
		if Input.is_action_just_pressed("target_clear"):
			targeting.clear_target()


const WEAPON_CONVERGENCE_DISTANCE: float = 500.0  ## Meters ahead of ship where projectiles meet

func _get_crosshair_aim_point() -> Vector3:
	# Raycast from camera through screen center to find where crosshair actually points
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + global_transform.basis * Vector3.FORWARD * WEAPON_CONVERGENCE_DISTANCE

	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var ray_origin := cam.project_ray_origin(screen_center)
	var ray_dir := cam.project_ray_normal(screen_center)

	# Physics raycast to check if we hit something
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 5000.0)
	query.collision_mask = Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_SHIPS
	query.exclude = [get_rid()]  # Don't hit ourselves

	var result := space_state.intersect_ray(query)
	if result.size() > 0:
		return result["position"]

	# Nothing hit: converge at fixed distance ahead of ship along camera aim ray
	var cam_to_ship := maxf((global_position - ray_origin).dot(ray_dir), 0.0)
	return ray_origin + ray_dir * (cam_to_ship + WEAPON_CONVERGENCE_DISTANCE)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	var ship_basis: Basis = state.transform.basis

	# Engine multiplier from energy system
	var engine_mult := 1.0
	var energy_sys := get_node_or_null("EnergySystem") as EnergySystem
	if energy_sys:
		engine_mult = energy_sys.get_engine_multiplier()

	# =========================================================================
	# FIX 6 — BOOST ENERGY DRAIN
	# =========================================================================
	if speed_mode == Constants.SpeedMode.BOOST and energy_sys:
		var drain := (ship_data.boost_energy_drain if ship_data else 15.0) * dt
		if not energy_sys.drain_engine_energy(drain):
			speed_mode = Constants.SpeedMode.NORMAL

	# Get stats from ship_data or constants
	var accel_fwd := (ship_data.accel_forward if ship_data else Constants.ACCEL_FORWARD) * engine_mult
	var accel_bwd := (ship_data.accel_backward if ship_data else Constants.ACCEL_BACKWARD) * engine_mult
	var accel_str := (ship_data.accel_strafe if ship_data else Constants.ACCEL_STRAFE) * engine_mult
	var accel_vert := (ship_data.accel_vertical if ship_data else Constants.ACCEL_VERTICAL) * engine_mult

	# =========================================================================
	# THRUST (Fix 1: throttle_input already normalized in _read_input/set_throttle)
	# =========================================================================
	if throttle_input.length_squared() > 0.01:
		var local_accel := Vector3.ZERO
		local_accel.x = throttle_input.x * accel_str
		local_accel.y = throttle_input.y * accel_vert
		if throttle_input.z < 0.0:
			local_accel.z = throttle_input.z * accel_fwd
		else:
			local_accel.z = throttle_input.z * accel_bwd
		state.linear_velocity += (ship_basis * local_accel) * dt

	# =========================================================================
	# ROTATION (Fix 4: speed-damped rotation + Fix 5: auto-roll)
	# =========================================================================
	var response: float = Constants.ROTATION_RESPONSE * rotation_responsiveness * dt

	# Fix 4 — rotation damping at high speed
	var max_speed_normal := ship_data.max_speed_normal if ship_data else Constants.MAX_SPEED_NORMAL
	var rot_damp_min := ship_data.rotation_damp_min_factor if ship_data else 0.15
	var rot_damp_factor := 1.0
	var speed_threshold := max_speed_normal * 1.1
	var max_speed_cruise := ship_data.max_speed_cruise if ship_data else Constants.MAX_SPEED_CRUISE
	current_speed = state.linear_velocity.length()
	if current_speed > speed_threshold:
		var t := clampf((current_speed - speed_threshold) / (max_speed_cruise - speed_threshold), 0.0, 1.0)
		rot_damp_factor = lerpf(1.0, rot_damp_min, t)

	_current_pitch_rate = lerp(_current_pitch_rate, _target_pitch_rate * rot_damp_factor, response)
	_current_yaw_rate = lerp(_current_yaw_rate, _target_yaw_rate * rot_damp_factor, response)
	_current_roll_rate = lerp(_current_roll_rate, _target_roll_rate * rot_damp_factor, response)

	# Fix 5 — auto-roll: yaw induces a slight bank unless player is manually rolling
	var auto_roll := 0.0
	if abs(auto_roll_factor) > 0.001 and abs(_target_roll_rate) < 0.1:
		auto_roll = -_current_yaw_rate * auto_roll_factor

	var desired_angular_vel := ship_basis * Vector3(
		deg_to_rad(_current_pitch_rate),
		deg_to_rad(_current_yaw_rate),
		deg_to_rad(_current_roll_rate + auto_roll)
	)
	state.angular_velocity = desired_angular_vel

	# =========================================================================
	# FLIGHT ASSIST (Fix 3: counter-brake when input opposes velocity)
	# =========================================================================
	if flight_assist:
		var fa_vel: Vector3 = ship_basis.inverse() * state.linear_velocity
		fa_vel.x = _fa_axis_brake(fa_vel.x, throttle_input.x, dt)
		fa_vel.y = _fa_axis_brake(fa_vel.y, throttle_input.y, dt)
		fa_vel.z = _fa_axis_brake(fa_vel.z, throttle_input.z, dt)
		state.linear_velocity = ship_basis * fa_vel

	# =========================================================================
	# SPEED LIMIT (Fix 2: per-axis cap in local space)
	# =========================================================================
	var max_speed_fwd: float
	if ship_data:
		match speed_mode:
			Constants.SpeedMode.BOOST: max_speed_fwd = ship_data.max_speed_boost
			Constants.SpeedMode.CRUISE: max_speed_fwd = ship_data.max_speed_cruise
			_: max_speed_fwd = ship_data.max_speed_normal
	else:
		max_speed_fwd = Constants.get_max_speed(speed_mode)

	var max_lat := ship_data.max_speed_lateral if ship_data else 150.0
	var max_vert := ship_data.max_speed_vertical if ship_data else 150.0

	var local_vel: Vector3 = ship_basis.inverse() * state.linear_velocity
	local_vel.x = clampf(local_vel.x, -max_lat, max_lat)
	local_vel.y = clampf(local_vel.y, -max_vert, max_vert)
	local_vel.z = clampf(local_vel.z, -max_speed_fwd, max_speed_fwd)
	state.linear_velocity = ship_basis * local_vel
	current_speed = state.linear_velocity.length()


func _fa_axis_brake(vel: float, input: float, dt: float) -> float:
	if abs(input) < 0.1:
		# No input: standard damping
		vel *= maxf(0.0, 1.0 - Constants.FA_LINEAR_BRAKE * dt)
	elif signf(input) != signf(vel) and absf(vel) > 0.5:
		# Input opposes velocity: boosted counter-brake
		var brake := absf(vel) * Constants.FA_COUNTER_BRAKE * dt
		if brake >= absf(vel):
			vel = 0.0
		else:
			vel -= brake * signf(vel)
	return vel


# === AI Interface ===

func set_throttle(thrust: Vector3) -> void:
	if thrust.length_squared() > 1.0:
		thrust = thrust.normalized()
	throttle_input = thrust


func set_rotation_target(pitch: float, yaw: float, roll: float) -> void:
	_target_pitch_rate = pitch
	_target_yaw_rate = yaw
	_target_roll_rate = roll


func _update_visuals() -> void:
	var model := get_node_or_null("ShipModel") as ShipModel
	if model:
		model.update_engine_glow(clamp(throttle_input.length(), 0.0, 1.0))
