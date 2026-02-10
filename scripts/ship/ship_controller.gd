class_name ShipController
extends RigidBody3D

# =============================================================================
# Ship Controller - 6DOF Space Flight
# Direct acceleration model. Mouse controls rotation. Keyboard controls thrust.
# Supports both player and AI control via is_player_controlled flag.
# Stats are data-driven from ShipData when available, falls back to Constants.
# =============================================================================

signal cruise_punch_triggered   ## Emitted when cruise enters explosive phase 2
signal cruise_exit_triggered    ## Emitted when leaving cruise mode (for VFX)
signal autopilot_disengaged_by_player  ## Emitted when player manually cancels autopilot

@export_group("Control")
@export var is_player_controlled: bool = true
@export var flight_assist: bool = true
@export var faction: StringName = &"neutral"
@export var rotation_responsiveness: float = 1.0  ## AI ships use higher values
@export var auto_roll_factor: float = 0.35

@export_group("Ship Data")
@export var ship_data: ShipData = null
var center_offset: Vector3 = Vector3.ZERO  ## Visual center from ship scene ShipCenter marker

# --- Engine equipment multipliers (set by EquipmentManager) ---
var engine_accel_mult: float = 1.0
var engine_speed_mult: float = 1.0
var engine_rotation_mult: float = 1.0
var engine_cruise_mult: float = 1.0
var engine_boost_drain_mult: float = 1.0

# --- Public state (read by HUD/camera/AI) ---
var speed_mode: int = Constants.SpeedMode.NORMAL
var current_speed: float = 0.0
var throttle_input: Vector3 = Vector3.ZERO

# --- Combat lock (no cruise while in combat) ---
const COMBAT_LOCK_DURATION: float = 5.0
var _last_combat_time: float = -100.0  # Time of last combat action (fire/hit)
var combat_locked: bool = false  ## Read by HUD for warning display

# --- Cruise warp (phase 2 punch: no collision, invisible to others) ---
var cruise_warp_active: bool = false
var _pre_warp_collision_layer: int = 0
var _pre_warp_collision_mask: int = 0

# --- Cruise two-phase system ---
const CRUISE_SPOOL_DURATION: float = 10.0  ## Phase 1: slow spool-up
const CRUISE_PUNCH_DURATION: float = 10.0  ## Phase 2: explosive acceleration
var cruise_time: float = 0.0               ## Time spent in current cruise (read by camera for FOV)
var _cruise_punched: bool = false

# --- Autopilot ---
var autopilot_active: bool = false
var autopilot_target_id: String = ""
var autopilot_target_name: String = ""
var autopilot_is_gate: bool = false  # True when navigating to a jump gate (closer approach)
var _autopilot_grace_frames: int = 0  # Ignore mouse input for N frames after engage
const AUTOPILOT_ARRIVAL_DIST: float = 10000.0        # 10 km — disengage autopilot (general)
const AUTOPILOT_GATE_ARRIVAL_DIST: float = 30.0      # 30m — inside 40m gate trigger sphere
const AUTOPILOT_DECEL_DIST: float = 30000.0          # 30 km — drop cruise, approach at 3 km/s
const AUTOPILOT_GATE_DECEL_DIST: float = 5000.0      # 5 km — decel for gate approach
const AUTOPILOT_ALIGN_THRESHOLD: float = 0.98        # dot product threshold to engage cruise
const AUTOPILOT_APPROACH_SPEED: float = 3000.0        # 3 km/s — fast final approach during autopilot

# --- Rotation state ---
var _target_pitch_rate: float = 0.0
var _target_yaw_rate: float = 0.0
var _target_roll_rate: float = 0.0
var _current_pitch_rate: float = 0.0
var _current_yaw_rate: float = 0.0
var _current_roll_rate: float = 0.0

# --- Mouse ---
var _mouse_delta: Vector2 = Vector2.ZERO

# --- Cached refs ---
var _cached_energy_sys: EnergySystem = null
var _cached_weapon_mgr: WeaponManager = null
var _cached_model: ShipModel = null
var _cached_targeting: TargetingSystem = null
var _cached_mining_sys: MiningSystem = null
var _refs_cached: bool = false

# --- Crosshair raycast throttle ---
var _aim_point: Vector3 = Vector3.ZERO
var _aim_timer: float = 0.0
const AIM_RAYCAST_INTERVAL: float = 0.05  # 20 Hz


func _ready() -> void:
	can_sleep = false
	freeze = false
	custom_integrator = true
	mass = ship_data.mass if ship_data else Constants.SHIP_MASS
	linear_damp = 0.0
	angular_damp = 0.0
	collision_layer = Constants.LAYER_SHIPS
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS
	_cache_refs.call_deferred()


func _cache_refs() -> void:
	_cached_energy_sys = get_node_or_null("EnergySystem") as EnergySystem
	_cached_weapon_mgr = get_node_or_null("WeaponManager") as WeaponManager
	_cached_model = get_node_or_null("ShipModel") as ShipModel
	_cached_targeting = get_node_or_null("TargetingSystem") as TargetingSystem
	_cached_mining_sys = get_node_or_null("MiningSystem") as MiningSystem
	_refs_cached = true

	# Connect health system damage signal for combat lock
	var health := get_node_or_null("HealthSystem") as HealthSystem
	if health and not health.damage_taken.is_connected(_on_combat_damage):
		health.damage_taken.connect(_on_combat_damage)


func _input(event: InputEvent) -> void:
	if not is_player_controlled:
		return
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_delta += event.relative


func _process(delta: float) -> void:
	if is_player_controlled:
		_read_input()
		_aim_timer -= delta
		_handle_player_weapon_input()
	_update_visuals()


func _read_input() -> void:
	# === COMBAT LOCK UPDATE (always runs) ===
	combat_locked = (Time.get_ticks_msec() * 0.001 - _last_combat_time) < COMBAT_LOCK_DURATION

	# === AUTOPILOT (runs even when GUI has focus, e.g. during screen close transition) ===
	if autopilot_active:
		# Grace period: ignore mouse input right after engage (mouse recapture generates spurious motion)
		if _autopilot_grace_frames > 0:
			_autopilot_grace_frames -= 1
			_mouse_delta = Vector2.ZERO
			_run_autopilot()
			return
		# Only manual flight input cancels autopilot (not combat lock — cruise is blocked separately)
		var has_manual_input := false
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and _mouse_delta.length_squared() > 4.0:
			has_manual_input = true
		for act in ["move_forward", "move_backward", "strafe_left", "strafe_right", "strafe_up", "strafe_down"]:
			if Input.is_action_pressed(act):
				has_manual_input = true
				break
		if has_manual_input:
			disengage_autopilot()
			autopilot_disengaged_by_player.emit()
		else:
			_run_autopilot()
			_mouse_delta = Vector2.ZERO
			return

	# === GUI FOCUS CHECK (only for manual flight, not autopilot) ===
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
	var pitch_speed := (ship_data.rotation_pitch_speed if ship_data else Constants.ROTATION_PITCH_SPEED) * engine_rotation_mult
	var yaw_speed := (ship_data.rotation_yaw_speed if ship_data else Constants.ROTATION_YAW_SPEED) * engine_rotation_mult
	_target_pitch_rate = -_mouse_delta.y * Constants.MOUSE_SENSITIVITY * pitch_speed
	_target_yaw_rate = -_mouse_delta.x * Constants.MOUSE_SENSITIVITY * yaw_speed
	_mouse_delta = Vector2.ZERO

	# Roll from keyboard
	var roll_speed := (ship_data.rotation_roll_speed if ship_data else Constants.ROTATION_ROLL_SPEED) * engine_rotation_mult
	_target_roll_rate = 0.0
	if Input.is_action_pressed("roll_left"):
		_target_roll_rate = roll_speed
	if Input.is_action_pressed("roll_right"):
		_target_roll_rate = -roll_speed

	# === SPEED MODE ===
	if Input.is_action_just_pressed("toggle_cruise"):
		if speed_mode == Constants.SpeedMode.CRUISE:
			_exit_cruise()
		elif not combat_locked:
			speed_mode = Constants.SpeedMode.CRUISE
			cruise_time = 0.0
			_cruise_punched = false

	if Input.is_action_pressed("boost") and speed_mode != Constants.SpeedMode.CRUISE:
		speed_mode = Constants.SpeedMode.BOOST
	elif not Input.is_action_pressed("boost") and speed_mode == Constants.SpeedMode.BOOST:
		speed_mode = Constants.SpeedMode.NORMAL

	if Input.is_action_just_pressed("toggle_flight_assist"):
		flight_assist = not flight_assist

	# === ENERGY PIPS ===
	if _cached_energy_sys:
		if Input.is_action_just_pressed("pip_weapons"):
			_cached_energy_sys.increase_pip(&"weapons")
		if Input.is_action_just_pressed("pip_shields"):
			_cached_energy_sys.increase_pip(&"shields")
		if Input.is_action_just_pressed("pip_engines"):
			_cached_energy_sys.increase_pip(&"engines")
		if Input.is_action_just_pressed("pip_reset"):
			_cached_energy_sys.reset_pips()


func _handle_player_weapon_input() -> void:
	# Lazy-cache: refs may be null if _cache_refs ran before GameManager added children
	if _cached_targeting == null or _cached_weapon_mgr == null:
		_cache_refs()

	# Targeting works regardless of mouse mode
	var targeting := _cached_targeting as TargetingSystem
	if targeting:
		if Input.is_action_just_pressed("target_cycle"):
			targeting.cycle_target_forward()
		if Input.is_action_just_pressed("target_nearest"):
			targeting.target_nearest_hostile()
		if Input.is_action_just_pressed("target_clear"):
			targeting.clear_target()

	if _cached_weapon_mgr == null:
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Skip weapon input during autopilot grace period (prevents firing from UI click)
	if autopilot_active and _autopilot_grace_frames > 0:
		return

	# Aim where the crosshair points: raycast throttled to 20Hz
	if _aim_timer <= 0.0:
		_aim_point = _get_crosshair_aim_point()
		_aim_timer = AIM_RAYCAST_INTERVAL
	var target_pos := _aim_point

	# Weapon toggles
	for i in mini(4, _cached_weapon_mgr.get_hardpoint_count()):
		if Input.is_action_just_pressed("toggle_weapon_%d" % (i + 1)):
			_cached_weapon_mgr.toggle_hardpoint(i)

	if Input.is_action_pressed("fire_primary"):
		# Fire combat weapons (mining lasers are skipped by fire_group)
		_cached_weapon_mgr.fire_group(0, true, target_pos)
		# Fire mining laser if equipped
		if _cached_mining_sys and _cached_mining_sys.has_mining_laser():
			_cached_mining_sys.try_fire(target_pos)
		# Only mark combat if we have non-mining weapons in primary group
		if _cached_weapon_mgr.has_combat_weapons_in_group(0):
			mark_combat()
	elif _cached_mining_sys and _cached_mining_sys._is_firing:
		# Fire released — stop mining beam
		_cached_mining_sys.stop_firing()

	if Input.is_action_pressed("fire_secondary"):
		_cached_weapon_mgr.fire_group(1, false, target_pos)
		mark_combat()

	# Turrets auto-track and auto-fire at current target (return to rest when no target)
	if targeting:
		var turret_target: Node3D = targeting.current_target if is_instance_valid(targeting.current_target) else null
		_cached_weapon_mgr.update_turrets(turret_target)
		if turret_target and _cached_weapon_mgr.is_any_weapon_ready(1):
			mark_combat()


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
	var world := get_world_3d()
	if world == null:
		return ray_origin + ray_dir * WEAPON_CONVERGENCE_DISTANCE
	var space_state := world.direct_space_state
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
	if _cached_energy_sys:
		engine_mult = _cached_energy_sys.get_engine_multiplier()

	# =========================================================================
	# FIX 6 — BOOST ENERGY DRAIN
	# =========================================================================
	if speed_mode == Constants.SpeedMode.BOOST and _cached_energy_sys:
		var drain := (ship_data.boost_energy_drain if ship_data else 15.0) * engine_boost_drain_mult * dt
		if not _cached_energy_sys.drain_engine_energy(drain):
			speed_mode = Constants.SpeedMode.NORMAL

	# Get stats from ship_data or constants
	var accel_fwd := (ship_data.accel_forward if ship_data else Constants.ACCEL_FORWARD) * engine_mult * engine_accel_mult
	var accel_bwd := (ship_data.accel_backward if ship_data else Constants.ACCEL_BACKWARD) * engine_mult * engine_accel_mult
	var accel_str := (ship_data.accel_strafe if ship_data else Constants.ACCEL_STRAFE) * engine_mult * engine_accel_mult
	var accel_vert := (ship_data.accel_vertical if ship_data else Constants.ACCEL_VERTICAL) * engine_mult * engine_accel_mult

	# Cruise mode: two-phase acceleration system
	# Phase 1 (0-10s): Gentle spool-up — FTL drive charging, speed builds slowly
	# Phase 2 (10-20s): Explosive punch — massive acceleration to max cruise speed
	if speed_mode == Constants.SpeedMode.CRUISE and ship_data:
		cruise_time += dt
		var cruise_mult: float
		if cruise_time <= CRUISE_SPOOL_DURATION:
			# Phase 1: quadratic ease-in (slow start, builds momentum)
			var t := cruise_time / CRUISE_SPOOL_DURATION
			cruise_mult = lerpf(1.0, 15.0, t * t)
		else:
			# Phase 2: explosive punch — emit signal on first frame
			if not _cruise_punched:
				_cruise_punched = true
				cruise_punch_triggered.emit()
				_enter_cruise_warp()
			var t2 := clampf((cruise_time - CRUISE_SPOOL_DURATION) / CRUISE_PUNCH_DURATION, 0.0, 1.0)
			cruise_mult = lerpf(50.0, 3000.0, t2)
		accel_fwd *= cruise_mult
	else:
		cruise_time = 0.0
		if _cruise_punched:
			_exit_cruise_warp()
		_cruise_punched = false

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
			Constants.SpeedMode.BOOST: max_speed_fwd = ship_data.max_speed_boost * engine_speed_mult
			Constants.SpeedMode.CRUISE: max_speed_fwd = ship_data.max_speed_cruise * engine_cruise_mult
			_: max_speed_fwd = ship_data.max_speed_normal * engine_speed_mult
	else:
		max_speed_fwd = Constants.get_max_speed(speed_mode)

	# Autopilot approach: use higher speed limit so final approach doesn't crawl
	if autopilot_active and speed_mode == Constants.SpeedMode.NORMAL:
		max_speed_fwd = maxf(max_speed_fwd, AUTOPILOT_APPROACH_SPEED)

	var max_lat := (ship_data.max_speed_lateral if ship_data else 150.0) * engine_speed_mult
	var max_vert := (ship_data.max_speed_vertical if ship_data else 150.0) * engine_speed_mult

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


# === Cruise exit ===

func _exit_cruise() -> void:
	if speed_mode == Constants.SpeedMode.CRUISE:
		speed_mode = Constants.SpeedMode.NORMAL
		cruise_time = 0.0
		_cruise_punched = false
		_exit_cruise_warp()
		cruise_exit_triggered.emit()


func _enter_cruise_warp() -> void:
	if cruise_warp_active:
		return
	_pre_warp_collision_layer = collision_layer
	_pre_warp_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	cruise_warp_active = true


func _exit_cruise_warp() -> void:
	if not cruise_warp_active:
		return
	collision_layer = _pre_warp_collision_layer
	collision_mask = _pre_warp_collision_mask
	cruise_warp_active = false


# === Autopilot ===

func engage_autopilot(target_id: String, target_name: String, is_gate: bool = false) -> void:
	autopilot_active = true
	autopilot_target_id = target_id
	autopilot_target_name = target_name
	autopilot_is_gate = is_gate
	_mouse_delta = Vector2.ZERO
	_autopilot_grace_frames = 10  # Ignore mouse until map close transition finishes + mouse recapture settles
	# Release any lingering GUI focus so it doesn't interfere later
	get_viewport().gui_release_focus()


func disengage_autopilot() -> void:
	autopilot_active = false
	autopilot_target_id = ""
	autopilot_target_name = ""
	autopilot_is_gate = false
	if speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()


func _run_autopilot() -> void:
	# Get target world position from EntityRegistry
	var ent: Dictionary = EntityRegistry.get_entity(autopilot_target_id)
	if ent.is_empty():
		disengage_autopilot()
		return

	var target_world: Vector3
	var node_ref = ent.get("node")
	if node_ref != null and is_instance_valid(node_ref):
		target_world = (node_ref as Node3D).global_position
	else:
		target_world = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])

	var to_target: Vector3 = target_world - global_position
	var dist: float = to_target.length()

	# Arrived — disengage (gate uses much closer distance)
	var arrival_dist: float = AUTOPILOT_GATE_ARRIVAL_DIST if autopilot_is_gate else AUTOPILOT_ARRIVAL_DIST
	if dist < arrival_dist:
		disengage_autopilot()
		return

	# Deceleration zone — drop cruise (gate uses shorter decel zone)
	var decel_dist: float = AUTOPILOT_GATE_DECEL_DIST if autopilot_is_gate else AUTOPILOT_DECEL_DIST
	if dist < decel_dist and speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()

	# Steer toward target
	var dir: Vector3 = to_target.normalized()
	var ship_fwd: Vector3 = -global_transform.basis.z
	var dot: float = ship_fwd.dot(dir)

	# Compute pitch/yaw needed in ship local space
	var local_dir: Vector3 = global_transform.basis.inverse() * dir
	var pitch_speed := ship_data.rotation_pitch_speed if ship_data else 30.0
	var yaw_speed := ship_data.rotation_yaw_speed if ship_data else 25.0

	# Proportional steering (stronger when far off, gentle when nearly aligned)
	_target_pitch_rate = clampf(local_dir.y * 3.0, -1.0, 1.0) * pitch_speed
	_target_yaw_rate = clampf(-local_dir.x * 3.0, -1.0, 1.0) * yaw_speed
	_target_roll_rate = 0.0

	# Throttle: full forward once reasonably aligned, gentle near gate
	if dot > 0.5:
		# When very close to a gate, reduce throttle to avoid overshooting
		if autopilot_is_gate and dist < 500.0:
			var approach_factor: float = clampf(dist / 500.0, 0.1, 1.0)
			throttle_input = Vector3(0, 0, -approach_factor)
		else:
			throttle_input = Vector3(0, 0, -1)
	else:
		throttle_input = Vector3.ZERO

	# Engage cruise once well aligned and outside decel zone
	if dot > AUTOPILOT_ALIGN_THRESHOLD and dist > decel_dist and not combat_locked:
		if speed_mode != Constants.SpeedMode.CRUISE:
			speed_mode = Constants.SpeedMode.CRUISE


# === Combat lock ===

func mark_combat() -> void:
	_last_combat_time = Time.get_ticks_msec() * 0.001
	# Force exit cruise if combat starts while cruising
	if speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()


func _on_combat_damage(_attacker: Node3D, _amount: float = 0.0) -> void:
	mark_combat()


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
	if _cached_model:
		_cached_model.update_engine_glow(clamp(throttle_input.length(), 0.0, 1.0))
