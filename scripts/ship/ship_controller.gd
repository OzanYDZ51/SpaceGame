class_name ShipController
extends RigidBody3D

# =============================================================================
# Ship Controller - 6DOF Space Flight
# Direct acceleration model. Mouse controls rotation. Keyboard controls thrust.
# Supports both player and AI control via is_player_controlled flag.
# Stats are data-driven from ShipData when available, falls back to Constants.
# =============================================================================

signal cruise_enter_triggered    ## Emitted when entering cruise mode (spool-up starts)
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
var cockpit_view_offset: Vector3 = Vector3.ZERO  ## Cockpit camera position from CockpitView marker

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
var cruise_disabled: bool = false  ## Prevents cruise mode (used by convoy NPCs)
var cinematic_mode: bool = false   ## Blocks all player input (photo mode)

# --- Combat lock (no cruise while in combat) ---
const COMBAT_LOCK_DURATION: float = 5.0
var _last_combat_time: float = -100.0  # Time of last combat action (fire/hit)
var combat_locked: bool = false  ## Read by HUD for warning display

# --- Cruise warp (phase 2 punch: no collision, invisible to others) ---
var cruise_warp_active: bool = false

# --- Cruise two-phase system ---
const CRUISE_SPOOL_DURATION: float = 10.0  ## Phase 1: slow spool-up
const CRUISE_PUNCH_DURATION: float = 10.0  ## Phase 2: explosive acceleration
var cruise_time: float = 0.0               ## Time spent in current cruise (read by camera for FOV)
var _cruise_punched: bool = false

# --- Post-cruise smooth deceleration ---
var _post_cruise_decel_active: bool = false
var _post_cruise_speed_cap: float = 0.0
const POST_CRUISE_DECEL_RATE: float = 3.0

# --- Gate approach speed cap (set by autopilot, consumed by _integrate_forces) ---
var _gate_approach_speed_cap: float = 0.0

# --- Autopilot ---
var autopilot_active: bool = false
var ai_navigation_active: bool = false  # Fleet AI: enables approach speed boost (3 km/s)
var autopilot_target_id: String = ""
var autopilot_target_name: String = ""
var autopilot_is_gate: bool = false  # True when navigating to a jump gate (closer approach)
var _autopilot_aligned: bool = false  # True when ship faces target (dot > 0.5) — gates speed boost
var _autopilot_grace_frames: int = 0  # Ignore mouse input for N frames after engage
var _was_ui_blocking: bool = false    # Track UI blocking transition for autopilot grace reset
const AUTOPILOT_ARRIVAL_DIST: float = 200.0           # 200m — disengage autopilot (stations/general)
const AUTOPILOT_GATE_ARRIVAL_DIST: float = 30.0      # 30m — inside 40m gate trigger sphere
const AUTOPILOT_DECEL_DIST: float = 5000.0           # 5 km — drop cruise, start decelerating
const AUTOPILOT_GATE_DECEL_DIST: float = 5000.0      # 5 km — decel for gate approach
const AUTOPILOT_ALIGN_THRESHOLD: float = 0.98        # dot product threshold to engage cruise
const AUTOPILOT_APPROACH_SPEED: float = 3000.0       # 3 km/s — fast final approach during autopilot
const AUTOPILOT_PLANET_ORBIT_MARGIN: float = 50000.0 # 50 km above surface for planet orbit stop
const AUTOPILOT_PLANET_AVOIDANCE_MARGIN: float = 1.5 # Avoidance radius = render_radius * this
const AUTOPILOT_SHIP_ARRIVAL_DIST: float = 120.0     # 120m — arrivée sur cible vaisseau (serré)

# --- Rotation state ---
var _target_pitch_rate: float = 0.0
var _target_yaw_rate: float = 0.0
var _target_roll_rate: float = 0.0
var _current_pitch_rate: float = 0.0
var _current_yaw_rate: float = 0.0
var _current_roll_rate: float = 0.0

# --- Mouse ---
var _mouse_delta: Vector2 = Vector2.ZERO
var cruise_look_delta: Vector2 = Vector2.ZERO  ## Mouse delta redirected to camera during free look
var free_look_active: bool = false              ## True while free look is toggled (W key) — camera should NOT snap back

# --- Cached refs ---
var _cached_energy_sys = null
var _cached_weapon_mgr = null
var _cached_model = null
var _cached_targeting = null
var _cached_mining_sys = null
var _refs_cached: bool = false

# --- Planetary physics (set by PlanetApproachManager) ---
var planetary_gravity: Vector3 = Vector3.ZERO         ## Gravity direction * strength (m/s²)
var atmospheric_drag: float = 0.0                     ## 0-1 drag factor
var planetary_max_speed_override: float = 0.0         ## 0 = no override, >0 = cap speed
var planetary_orbit_velocity: Vector3 = Vector3.ZERO  ## Frame-dragging: planet orbital velocity (target)
var planetary_rotation_velocity: Vector3 = Vector3.ZERO  ## Frame-dragging: planet axial rotation velocity (target)
var _smoothed_orbit_vel: Vector3 = Vector3.ZERO  ## Smoothed frame-dragging velocity (actually applied)
var _near_planet_surface: bool = false                ## True when in atmosphere (blocks cruise)

# --- Planet proximity guard (used per-frame in _integrate_forces) ---
var _planet_guard_center: Vector3 = Vector3.ZERO  ## Nearest planet center (world coords)
var _planet_guard_radius: float = 0.0             ## Nearest planet surface_radius including terrain (0 = no planet)
var _planet_guard_body: PlanetBody = null          ## Direct ref for per-frame position update

# --- Planet collision avoidance (pure distance-based) ---
var _planet_check_timer: float = 0.0
const PLANET_CHECK_INTERVAL: float = 0.25       # 4 Hz
const PLANET_CRUISE_EXIT_MARGIN: float = 30_000.0  # 30 km above surface — exit cruise
var planet_avoidance_active: bool = false   ## Read by HUD for warning display

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
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_TERRAIN
	_cache_refs.call_deferred()


func _cache_refs() -> void:
	_cached_energy_sys = get_node_or_null("EnergySystem")
	_cached_weapon_mgr = get_node_or_null("WeaponManager")
	_cached_model = get_node_or_null("ShipModel")
	_cached_targeting = get_node_or_null("TargetingSystem")
	_cached_mining_sys = get_node_or_null("MiningSystem")
	_refs_cached = true

	# Connect health system damage signal for combat lock
	var health = get_node_or_null("HealthSystem")
	if health and not health.damage_taken.is_connected(_on_combat_damage):
		health.damage_taken.connect(_on_combat_damage)

	# Dynamic environment lighting (player ship only)
	if is_player_controlled and get_node_or_null("EnvLighting") == null:
		var env_light := ShipEnvironmentLighting.new()
		env_light.name = "EnvLighting"
		add_child(env_light)


func _notification(what: int) -> void:
	if not is_player_controlled:
		return
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Window lost focus — zero all input so _integrate_forces doesn't
		# keep accelerating with stale throttle while _process is paused.
		throttle_input = Vector3.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
		_target_roll_rate = 0.0
		_mouse_delta = Vector2.ZERO
		cruise_look_delta = Vector2.ZERO
		free_look_active = false
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		# Window regained focus — clear residual rotation smoothing
		throttle_input = Vector3.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
		_target_roll_rate = 0.0
		_current_pitch_rate = 0.0
		_current_yaw_rate = 0.0
		_current_roll_rate = 0.0
		_mouse_delta = Vector2.ZERO
		cruise_look_delta = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if not is_player_controlled or cinematic_mode:
		return
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_delta += event.relative


func _physics_process(_delta: float) -> void:
	# Read input at physics rate so mouse delta is consumed once per physics tick
	# with the FULL accumulated movement. Reading in _process() caused stutter:
	# multiple frames consumed partial deltas, physics only saw the last one.
	if is_player_controlled:
		_read_input()


func _process(delta: float) -> void:
	if is_player_controlled:
		_check_planet_collision(delta)
		_aim_timer -= delta
		_handle_player_weapon_input()
	_update_visuals()


func _read_input() -> void:
	# Guard: InputRouter registers runtime actions after GameManager._initialize_game().
	# On the first frame, the PlayerShip._process() can run before those actions exist.
	if not InputMap.has_action("pip_weapons"):
		return

	# Cinematic / photo mode — block all ship input, ship drifts inertially
	if cinematic_mode:
		throttle_input = Vector3.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
		_target_roll_rate = 0.0
		_mouse_delta = Vector2.ZERO
		cruise_look_delta = Vector2.ZERO
		free_look_active = false
		return

	# === COMBAT LOCK UPDATE (always runs) ===
	combat_locked = (Time.get_ticks_msec() * 0.001 - _last_combat_time) < COMBAT_LOCK_DURATION

	# === UI SCREEN CHECK — block all ship input when a UI screen is open ===
	var _ui_blocking: bool = (GameManager._screen_manager != null and GameManager._screen_manager.is_any_screen_open()) or get_viewport().gui_get_focus_owner() != null

	# Reset autopilot grace when UI closes (mouse recapture generates spurious delta)
	if _was_ui_blocking and not _ui_blocking and autopilot_active:
		_autopilot_grace_frames = 10
		_mouse_delta = Vector2.ZERO
	_was_ui_blocking = _ui_blocking

	# === AUTOPILOT (runs even when GUI has focus, e.g. during screen close transition) ===
	if autopilot_active:
		# Grace period: ignore mouse input right after engage (mouse recapture generates spurious motion)
		if _autopilot_grace_frames > 0:
			_autopilot_grace_frames -= 1
			_mouse_delta = Vector2.ZERO
			_run_autopilot()
			return
		# Only manual flight input cancels autopilot (not combat lock — cruise is blocked separately)
		var has_manual_input =false
		if not _ui_blocking:
			# In cruise, mouse is free look (camera orbit) — not manual flight input
			if speed_mode != Constants.SpeedMode.CRUISE:
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
			# Free look: redirect mouse to camera si W est maintenu
			free_look_active = Input.is_action_pressed("toggle_freelook")
			if free_look_active:
				cruise_look_delta = _mouse_delta
			else:
				cruise_look_delta = Vector2.ZERO
			_mouse_delta = Vector2.ZERO
			return

	# === GUI FOCUS CHECK — block manual flight when UI is active ===
	if _ui_blocking:
		throttle_input = Vector3.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
		_target_roll_rate = 0.0
		_mouse_delta = Vector2.ZERO
		cruise_look_delta = Vector2.ZERO
		free_look_active = false
		return

	# === THRUST ===
	var thrust =Vector3.ZERO
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

	# === FREELOOK (W maintenu) ===
	# W est aussi move_forward : maintenir W = vue libre + poussée simultanément.
	# Relâcher W = retour caméra derrière le vaisseau.
	free_look_active = Input.is_action_pressed("toggle_freelook")

	# === ROTATION from mouse (W toggle → free look) ===
	if free_look_active:
		# Free look: redirect mouse delta to camera, ship flies straight
		cruise_look_delta = _mouse_delta
		_mouse_delta = Vector2.ZERO
		_target_pitch_rate = 0.0
		_target_yaw_rate = 0.0
	else:
		cruise_look_delta = Vector2.ZERO
		var pitch_speed =(ship_data.rotation_pitch_speed if ship_data else Constants.ROTATION_PITCH_SPEED) * engine_rotation_mult
		var yaw_speed =(ship_data.rotation_yaw_speed if ship_data else Constants.ROTATION_YAW_SPEED) * engine_rotation_mult
		_target_pitch_rate = -_mouse_delta.y * Constants.MOUSE_SENSITIVITY * pitch_speed
		_target_yaw_rate = -_mouse_delta.x * Constants.MOUSE_SENSITIVITY * yaw_speed
		_mouse_delta = Vector2.ZERO

	# Roll from keyboard
	var roll_speed =(ship_data.rotation_roll_speed if ship_data else Constants.ROTATION_ROLL_SPEED) * engine_rotation_mult
	_target_roll_rate = 0.0
	if Input.is_action_pressed("roll_left"):
		_target_roll_rate = roll_speed
	if Input.is_action_pressed("roll_right"):
		_target_roll_rate = -roll_speed

	# === SPEED MODE ===
	if Input.is_action_just_pressed("toggle_cruise"):
		if speed_mode == Constants.SpeedMode.CRUISE:
			_exit_cruise()
		elif not combat_locked and not _near_planet_surface:
			speed_mode = Constants.SpeedMode.CRUISE
			cruise_time = 0.0
			_cruise_punched = false
			cruise_enter_triggered.emit()

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
	if not InputMap.has_action("target_cycle") or cinematic_mode:
		return
	# Lazy-cache: refs may be null if _cache_refs ran before GameManager added children
	if _cached_targeting == null or _cached_weapon_mgr == null:
		_cache_refs()

	# Targeting works regardless of mouse mode
	var targeting = _cached_targeting
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
	var target_pos =_aim_point

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
	var ship_fwd_point: Vector3 = global_position + (-global_transform.basis.z) * WEAPON_CONVERGENCE_DISTANCE

	# Free-look: camera is decoupled from ship, always fire ship-forward
	if free_look_active:
		return ship_fwd_point

	# Raycast from camera through screen center to find where crosshair actually points
	var cam =get_viewport().get_camera_3d()
	if cam == null:
		return ship_fwd_point

	# Check if camera is in free-look mode (e.g. returning to center)
	if cam is ShipCamera and (cam as ShipCamera).is_free_looking:
		return ship_fwd_point

	var screen_center =get_viewport().get_visible_rect().size / 2.0
	var ray_origin =cam.project_ray_origin(screen_center)
	var ray_dir =cam.project_ray_normal(screen_center)

	# Physics raycast to check if we hit something
	var world =get_world_3d()
	if world == null:
		return ship_fwd_point
	var space_state =world.direct_space_state
	var query =PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 5000.0)
	query.collision_mask = Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_SHIPS | Constants.LAYER_TERRAIN
	query.exclude = [get_rid()]  # Don't hit ourselves

	var result =space_state.intersect_ray(query)
	if result.size() > 0:
		return result["position"]

	# Nothing hit: converge ahead of the SHIP (not the camera)
	return ship_fwd_point


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	var ship_basis: Basis = state.transform.basis

	# Engine multiplier from energy system
	var engine_mult =1.0
	if _cached_energy_sys:
		engine_mult = _cached_energy_sys.get_engine_multiplier()

	# =========================================================================
	# FIX 6 — BOOST ENERGY DRAIN
	# =========================================================================
	if speed_mode == Constants.SpeedMode.BOOST and _cached_energy_sys:
		var drain =(ship_data.boost_energy_drain if ship_data else 15.0) * engine_boost_drain_mult * dt
		if not _cached_energy_sys.drain_engine_energy(drain):
			speed_mode = Constants.SpeedMode.NORMAL

	# Get stats from ship_data or constants
	var accel_fwd =(ship_data.accel_forward if ship_data else Constants.ACCEL_FORWARD) * engine_mult * engine_accel_mult
	var accel_bwd =(ship_data.accel_backward if ship_data else Constants.ACCEL_BACKWARD) * engine_mult * engine_accel_mult
	var accel_str =(ship_data.accel_strafe if ship_data else Constants.ACCEL_STRAFE) * engine_mult * engine_accel_mult
	var accel_vert =(ship_data.accel_vertical if ship_data else Constants.ACCEL_VERTICAL) * engine_mult * engine_accel_mult

	# Cruise mode: two-phase acceleration system
	# Phase 1 (0-10s): Gentle spool-up — FTL drive charging, speed builds slowly
	# Phase 2 (10-20s): Explosive punch — massive acceleration to max cruise speed
	if speed_mode == Constants.SpeedMode.CRUISE and ship_data and not cruise_disabled:
		cruise_time += dt
		var cruise_mult: float
		if cruise_time <= CRUISE_SPOOL_DURATION:
			# Phase 1: quadratic ease-in (slow start, builds momentum)
			var t =cruise_time / CRUISE_SPOOL_DURATION
			cruise_mult = lerpf(1.0, 15.0, t * t)
		else:
			# Phase 2: explosive punch
			if not _cruise_punched:
				_cruise_punched = true
				if is_player_controlled:
					cruise_punch_triggered.emit()
					_enter_cruise_warp()
			var t2 =clampf((cruise_time - CRUISE_SPOOL_DURATION) / CRUISE_PUNCH_DURATION, 0.0, 1.0)
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
		var local_accel =Vector3.ZERO
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
	var max_speed_normal =ship_data.max_speed_normal if ship_data else Constants.MAX_SPEED_NORMAL
	var rot_damp_min =ship_data.rotation_damp_min_factor if ship_data else 0.15
	var rot_damp_factor =1.0
	var speed_threshold =max_speed_normal * 1.1
	var max_speed_cruise =ship_data.max_speed_cruise if ship_data else Constants.MAX_SPEED_CRUISE
	current_speed = state.linear_velocity.length()
	if current_speed > speed_threshold:
		var t =clampf((current_speed - speed_threshold) / (max_speed_cruise - speed_threshold), 0.0, 1.0)
		rot_damp_factor = lerpf(1.0, rot_damp_min, t)

	_current_pitch_rate = lerp(_current_pitch_rate, _target_pitch_rate * rot_damp_factor, response)
	_current_yaw_rate = lerp(_current_yaw_rate, _target_yaw_rate * rot_damp_factor, response)
	_current_roll_rate = lerp(_current_roll_rate, _target_roll_rate * rot_damp_factor, response)

	# Fix 5 — auto-roll: yaw induces a slight bank unless player is manually rolling
	var auto_roll =0.0
	if abs(auto_roll_factor) > 0.001 and abs(_target_roll_rate) < 0.1:
		auto_roll = -_current_yaw_rate * auto_roll_factor

	var desired_angular_vel =ship_basis * Vector3(
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
	# PLANETARY PHYSICS (gravity + atmospheric drag)
	# =========================================================================
	if planetary_gravity.length_squared() > 0.001:
		state.linear_velocity += planetary_gravity * dt

	if atmospheric_drag > 0.001:
		var drag_mult: float = maxf(0.0, 1.0 - atmospheric_drag * 2.0 * dt)
		state.linear_velocity *= drag_mult

	# =========================================================================
	# FRAME-DRAGGING: subtract orbital velocity before speed limits, add back after.
	# Speed caps apply to movement RELATIVE to the planet, so the ship naturally
	# matches the planet's orbit without it eating into flight speed.
	# Smoothed to avoid velocity jumps when PlanetApproachManager updates at 10Hz.
	# =========================================================================
	var target_orbit_vel =planetary_orbit_velocity
	_smoothed_orbit_vel = _smoothed_orbit_vel.lerp(target_orbit_vel, minf(16.0 * dt, 1.0))
	var has_orbit_drag =_smoothed_orbit_vel.length_squared() > 0.1
	if has_orbit_drag:
		state.linear_velocity -= _smoothed_orbit_vel

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

	# Autopilot / AI navigation approach: use higher speed limit ONLY when aligned with target
	# When not aligned, keep normal max so rot_damp_factor allows full rotation to realign
	if (autopilot_active or ai_navigation_active) and speed_mode == Constants.SpeedMode.NORMAL:
		if not autopilot_active or _autopilot_aligned:
			max_speed_fwd = maxf(max_speed_fwd, AUTOPILOT_APPROACH_SPEED)

	# Planetary speed cap (atmosphere/surface limit)
	if planetary_max_speed_override > 0.0:
		max_speed_fwd = minf(max_speed_fwd, planetary_max_speed_override)

	# Post-cruise smooth deceleration (Fix 1: no more speed wall)
	if _post_cruise_decel_active:
		var target_cap: float = max_speed_fwd
		_post_cruise_speed_cap = lerpf(_post_cruise_speed_cap, target_cap, POST_CRUISE_DECEL_RATE * dt)
		if absf(_post_cruise_speed_cap - target_cap) < 50.0:
			_post_cruise_decel_active = false
		else:
			max_speed_fwd = _post_cruise_speed_cap

	# Gate approach speed cap (Fix 3: prevent overshooting gate trigger)
	if _gate_approach_speed_cap > 0.0:
		max_speed_fwd = minf(max_speed_fwd, _gate_approach_speed_cap)

	var max_lat: float = (ship_data.max_speed_lateral if ship_data else 150.0) * engine_speed_mult
	var max_vert: float = (ship_data.max_speed_vertical if ship_data else 150.0) * engine_speed_mult

	# Also apply planetary speed cap to lateral/vertical
	if planetary_max_speed_override > 0.0:
		max_lat = minf(max_lat, planetary_max_speed_override)
		max_vert = minf(max_vert, planetary_max_speed_override)

	# Planet proximity: exit cruise warp when close to surface
	if _planet_guard_radius > 0.0:
		if _planet_guard_body and is_instance_valid(_planet_guard_body):
			_planet_guard_center = _planet_guard_body.global_position
		var alt: float = state.transform.origin.distance_to(_planet_guard_center) - _planet_guard_radius
		if cruise_warp_active and alt < 50_000.0:
			_exit_cruise_warp()

	var local_vel: Vector3 = ship_basis.inverse() * state.linear_velocity
	local_vel.x = clampf(local_vel.x, -max_lat, max_lat)
	local_vel.y = clampf(local_vel.y, -max_vert, max_vert)
	local_vel.z = clampf(local_vel.z, -max_speed_fwd, max_speed_fwd)
	state.linear_velocity = ship_basis * local_vel

	# Re-add orbital velocity after speed clamping (frame-dragging)
	if has_orbit_drag:
		state.linear_velocity += _smoothed_orbit_vel

	current_speed = state.linear_velocity.length()


func _fa_axis_brake(vel: float, input: float, dt: float) -> float:
	if abs(input) < 0.1:
		# No input: standard damping
		vel *= maxf(0.0, 1.0 - Constants.FA_LINEAR_BRAKE * dt)
	elif signf(input) != signf(vel) and absf(vel) > 0.5:
		# Input opposes velocity: boosted counter-brake
		var brake =absf(vel) * Constants.FA_COUNTER_BRAKE * dt
		if brake >= absf(vel):
			vel = 0.0
		else:
			vel -= brake * signf(vel)
	return vel


# === Planet collision avoidance (cruise/boost safety) ===

func _check_planet_collision(delta: float) -> void:
	_planet_check_timer -= delta
	if _planet_check_timer > 0.0:
		return
	# Check more frequently at high speed (up to every frame at cruise speeds)
	var interval: float = PLANET_CHECK_INTERVAL if current_speed < 5000.0 else maxf(0.016, 500.0 / maxf(current_speed, 1.0))
	_planet_check_timer = interval
	planet_avoidance_active = false

	var upos: Array = FloatingOrigin.to_universe_pos(global_position)

	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET):
		var is_autopilot_target: bool = autopilot_active and ent.get("id", "") == autopilot_target_id
		var extra: Dictionary = ent.get("extra", {})
		var rr: float = extra.get("render_radius", 50_000.0)

		var dx: float = ent["pos_x"] - upos[0]
		var dy: float = ent["pos_y"] - upos[1]
		var dz: float = ent["pos_z"] - upos[2]
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		var alt: float = dist - rr

		# Cruise exit at fixed 30km above surface (not speed-dependent)
		var cruise_exit_alt: float = PLANET_CRUISE_EXIT_MARGIN
		if alt < cruise_exit_alt:
			var to_planet =Vector3(float(dx), float(dy), float(dz)).normalized()
			var ship_fwd =(-global_transform.basis.z).normalized()
			var heading_toward: bool = ship_fwd.dot(to_planet) > 0.2

			if is_autopilot_target:
				if speed_mode == Constants.SpeedMode.CRUISE:
					_exit_cruise()
			elif heading_toward:
				planet_avoidance_active = true
				if speed_mode == Constants.SpeedMode.CRUISE:
					_exit_cruise()
				break
			elif alt < rr * 0.2:
				# Very close to surface — block regardless of direction
				planet_avoidance_active = true
				if speed_mode == Constants.SpeedMode.CRUISE:
					_exit_cruise()
				break

	# NOTE: Planet proximity guard (_planet_guard_center/radius) is now set exclusively
	# by PlanetApproachManager._apply_to_ship() which has the correct surface radius
	# (including terrain amplitude). Do NOT override it here to avoid conflicts.


# === Cruise exit ===

func _exit_cruise() -> void:
	if speed_mode == Constants.SpeedMode.CRUISE:
		_post_cruise_decel_active = true
		_post_cruise_speed_cap = current_speed
		speed_mode = Constants.SpeedMode.NORMAL
		cruise_time = 0.0
		_cruise_punched = false
		_exit_cruise_warp()
		cruise_exit_triggered.emit()


## Public API for PlanetApproachManager to exit cruise without accessing private method.
func exit_cruise() -> void:
	_exit_cruise()


## Public API for PlanetApproachManager to set planet proximity state.
func set_near_planet_surface(value: bool) -> void:
	_near_planet_surface = value


## Public API for PlanetApproachManager to set planet guard (collision avoidance).
func set_planet_guard(body: PlanetBody, center: Vector3, radius: float) -> void:
	_planet_guard_body = body
	_planet_guard_center = center
	_planet_guard_radius = radius


func clear_planet_guard() -> void:
	_planet_guard_body = null
	_planet_guard_radius = 0.0


func _enter_cruise_warp() -> void:
	if cruise_warp_active:
		return
	var act_ctrl = get_node_or_null("ShipActivationController")
	if act_ctrl:
		act_ctrl.deactivate(ShipActivationController.DeactivationMode.INTANGIBLE)
	cruise_warp_active = true


func _exit_cruise_warp() -> void:
	if not cruise_warp_active:
		return
	var act_ctrl = get_node_or_null("ShipActivationController")
	if act_ctrl:
		act_ctrl.activate()
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
	var was_planet_approach: bool = false
	var was_static_approach: bool = false
	if autopilot_active and autopilot_target_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(autopilot_target_id)
		var target_type: int = ent.get("type", -1)
		if target_type == EntityRegistrySystem.EntityType.PLANET:
			was_planet_approach = true
		elif target_type not in [
			EntityRegistrySystem.EntityType.SHIP_NPC,
			EntityRegistrySystem.EntityType.SHIP_FLEET,
			EntityRegistrySystem.EntityType.SHIP_PLAYER,
		] and not autopilot_is_gate:
			was_static_approach = true
	autopilot_active = false
	autopilot_target_id = ""
	autopilot_target_name = ""
	autopilot_is_gate = false
	_autopilot_aligned = false
	_gate_approach_speed_cap = 0.0
	# Zero rotation rates and throttle to prevent lingering spin after disengage
	_target_pitch_rate = 0.0
	_target_yaw_rate = 0.0
	_target_roll_rate = 0.0
	throttle_input = Vector3.ZERO
	if speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()
	# Arrêt net à l'arrivée : stopper la vélocité pour les cibles statiques (stations)
	# et les planètes (éviter de dériver dans la planète)
	if was_planet_approach or was_static_approach:
		linear_velocity = Vector3.ZERO
		_post_cruise_decel_active = false


## Full flight state reset — clears ALL transient flags. Called on system transition.
func reset_flight_state() -> void:
	disengage_autopilot()
	cruise_time = 0.0
	_cruise_punched = false
	if cruise_warp_active:
		_exit_cruise_warp()
	_post_cruise_decel_active = false
	_post_cruise_speed_cap = 0.0
	_gate_approach_speed_cap = 0.0
	speed_mode = Constants.SpeedMode.NORMAL
	_last_combat_time = -100.0
	combat_locked = false
	planetary_gravity = Vector3.ZERO
	atmospheric_drag = 0.0
	planetary_max_speed_override = 0.0
	planetary_orbit_velocity = Vector3.ZERO
	planetary_rotation_velocity = Vector3.ZERO
	_smoothed_orbit_vel = Vector3.ZERO
	_near_planet_surface = false
	planet_avoidance_active = false
	_planet_guard_center = Vector3.ZERO
	_planet_guard_radius = 0.0
	_planet_guard_body = null
	throttle_input = Vector3.ZERO
	_target_pitch_rate = 0.0
	_target_yaw_rate = 0.0
	_target_roll_rate = 0.0
	_current_pitch_rate = 0.0
	_current_yaw_rate = 0.0
	_current_roll_rate = 0.0
	_mouse_delta = Vector2.ZERO
	cruise_look_delta = Vector2.ZERO
	free_look_active = false


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

	# --- Détection type de cible ---
	var target_type: int = ent.get("type", -1)
	var is_ship_target: bool = target_type in [
		EntityRegistrySystem.EntityType.SHIP_NPC,
		EntityRegistrySystem.EntityType.SHIP_FLEET,
		EntityRegistrySystem.EntityType.SHIP_PLAYER,
	]

	# --- Arrival distance selon type ---
	var arrival_dist: float
	if autopilot_is_gate:
		arrival_dist = AUTOPILOT_GATE_ARRIVAL_DIST
	elif target_type == EntityRegistrySystem.EntityType.PLANET:
		var extra: Dictionary = ent.get("extra", {})
		var rr: float = extra.get("render_radius", 50_000.0)
		arrival_dist = rr + AUTOPILOT_PLANET_ORBIT_MARGIN
	elif is_ship_target:
		arrival_dist = AUTOPILOT_SHIP_ARRIVAL_DIST
	else:
		arrival_dist = AUTOPILOT_ARRIVAL_DIST

	# Arrival: arrêt net — instant stop at destination
	# Speed-adaptive distance prevents frame-skip overshoot at high cruise speeds
	var effective_arrival: float = maxf(arrival_dist, current_speed * 0.05)
	if dist < effective_arrival:
		if speed_mode == Constants.SpeedMode.CRUISE:
			_exit_cruise()
		linear_velocity = Vector3.ZERO
		_post_cruise_decel_active = false
		_gate_approach_speed_cap = 0.0
		disengage_autopilot()
		return

	# Deceleration zone — only for planets (orbit approach) and actual gate navigation.
	# Everything else: cruise at full speed → arrêt net at arrival.
	var decel_dist: float
	var is_actual_gate: bool = autopilot_is_gate and target_type == EntityRegistrySystem.EntityType.JUMP_GATE
	if is_actual_gate:
		decel_dist = AUTOPILOT_GATE_DECEL_DIST
	elif target_type == EntityRegistrySystem.EntityType.PLANET:
		decel_dist = arrival_dist + 40_000.0  # Start slowing 40km before orbit
	else:
		decel_dist = 0.0  # No early decel — arrêt net at arrival
	if decel_dist > 0.0 and dist < decel_dist and speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()

	# --- Planet avoidance: steer around planets in the flight path ---
	var dir: Vector3 = to_target.normalized()
	dir = _autopilot_avoid_planets(dir, dist)

	var ship_fwd: Vector3 = -global_transform.basis.z
	var dot: float = ship_fwd.dot(dir)

	# Compute pitch/yaw needed in ship local space
	var local_dir: Vector3 = global_transform.basis.inverse() * dir
	var pitch_speed =ship_data.rotation_pitch_speed if ship_data else 30.0
	var yaw_speed =ship_data.rotation_yaw_speed if ship_data else 25.0

	# Proportional steering (stronger when far off, gentle when nearly aligned)
	_target_pitch_rate = clampf(local_dir.y * 3.0, -1.0, 1.0) * pitch_speed
	_target_yaw_rate = clampf(-local_dir.x * 3.0, -1.0, 1.0) * yaw_speed
	_target_roll_rate = 0.0

	# Track alignment for speed boost decision in _integrate_forces
	_autopilot_aligned = dot > 0.5

	# Not aligned: exit cruise and actively brake so the ship can turn
	if not _autopilot_aligned and speed_mode == Constants.SpeedMode.CRUISE:
		_exit_cruise()

	# Throttle: full forward once aligned, active brake when misaligned
	var is_planet: bool = target_type == EntityRegistrySystem.EntityType.PLANET
	if _autopilot_aligned:
		if is_planet and dist < arrival_dist + 50_000.0:
			if _gate_approach_speed_cap > 0.0 and current_speed > _gate_approach_speed_cap * 1.2:
				throttle_input = Vector3.ZERO
			else:
				var approach_factor: float = clampf((dist - arrival_dist) / 50_000.0, 0.05, 1.0)
				throttle_input = Vector3(0, 0, -approach_factor)
		else:
			# Full throttle until arrival_dist — ship stops net when it gets there
			throttle_input = Vector3(0, 0, -1)
	else:
		# Target is to the side/behind: actively brake to allow turning
		var max_normal: float = ship_data.max_speed_normal if ship_data else 300.0
		if current_speed > max_normal * 0.5:
			throttle_input = Vector3(0, 0, 1)  # Reverse throttle = active braking
		else:
			throttle_input = Vector3.ZERO

	# Speed cap — only for planets (surface safety) and actual gate approach (trigger zone precision)
	if is_planet:
		var margin: float = dist - arrival_dist
		if margin < 100_000.0:
			_gate_approach_speed_cap = lerpf(50.0, 5000.0, clampf(margin / 100_000.0, 0.0, 1.0))
		else:
			_gate_approach_speed_cap = 0.0
	elif is_actual_gate and dist < 2000.0:
		# Actual gate: slow down near trigger zone for reliable jump detection
		_gate_approach_speed_cap = maxf(5.0, 500.0 * pow(dist / 2000.0, 2.0))
	else:
		_gate_approach_speed_cap = 0.0

	# Engage cruise once well aligned (and outside decel zone if one exists)
	if dot > AUTOPILOT_ALIGN_THRESHOLD and (decel_dist <= 0.0 or dist > decel_dist) and not combat_locked:
		if speed_mode != Constants.SpeedMode.CRUISE:
			speed_mode = Constants.SpeedMode.CRUISE
			cruise_time = 0.0
			_cruise_punched = false
			_post_cruise_decel_active = false
			cruise_enter_triggered.emit()


## Steer autopilot direction away from planets/stars that block the flight path.
## Returns adjusted direction vector.
func _autopilot_avoid_planets(desired_dir: Vector3, target_dist: float) -> Vector3:
	var best_avoidance =Vector3.ZERO
	var worst_penetration: float = 0.0

	# Collect obstacles: planets + star (exclude our autopilot destination)
	var obstacles: Array[Dictionary] = []
	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.PLANET):
		if ent.get("id", "") == autopilot_target_id:
			continue
		var extra: Dictionary = ent.get("extra", {})
		obstacles.append({"pos_x": ent["pos_x"], "pos_y": ent["pos_y"], "pos_z": ent["pos_z"],
			"radius": extra.get("render_radius", 50_000.0)})
	for ent in EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STAR):
		if ent.get("id", "") == autopilot_target_id:
			continue
		obstacles.append({"pos_x": ent["pos_x"], "pos_y": ent["pos_y"], "pos_z": ent["pos_z"],
			"radius": ent.get("radius", 300_000.0)})

	for obs in obstacles:
		var avoid_radius: float = obs["radius"] * AUTOPILOT_PLANET_AVOIDANCE_MARGIN

		# Vector from ship to obstacle center
		var obs_world =FloatingOrigin.to_local_pos([obs["pos_x"], obs["pos_y"], obs["pos_z"]])
		var to_obs: Vector3 = obs_world - global_position
		var obs_dist: float = to_obs.length()

		# Skip obstacles farther than our target or very far away
		if obs_dist > target_dist + avoid_radius:
			continue
		# Skip obstacles behind us
		var proj: float = to_obs.dot(desired_dir)
		if proj < 0.0:
			continue

		# Closest approach point along the desired flight line
		var closest_point: Vector3 = global_position + desired_dir * proj
		var offset: Vector3 = obs_world - closest_point
		var offset_dist: float = offset.length()

		if offset_dist < avoid_radius:
			# We would pass through the avoidance sphere — compute deflection
			var penetration: float = avoid_radius - offset_dist

			# Deflection: push away from obstacle center, perpendicular to desired_dir
			var deflect: Vector3
			if offset_dist > 1.0:
				deflect = -offset.normalized()
			else:
				# Heading straight at center — deflect up
				deflect = global_transform.basis.y

			var strength: float = clampf(penetration / avoid_radius, 0.1, 1.0)

			if penetration > worst_penetration:
				worst_penetration = penetration
				best_avoidance = deflect * strength

	if worst_penetration > 0.0:
		# Blend avoidance into desired direction (stronger avoidance overrides more)
		var blend: float = clampf(worst_penetration / (50_000.0), 0.3, 0.95)
		return (desired_dir * (1.0 - blend) + best_avoidance * blend).normalized()

	return desired_dir


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
