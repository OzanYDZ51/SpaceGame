class_name RemotePlayerShip
extends Node3D

# =============================================================================
# Remote Player Ship - Visual puppet for a remote player.
# Receives state snapshots and interpolates smoothly between them.
# Uses Hermite interpolation (position + velocity) for smooth curves.
# No physics simulation — purely visual.
# =============================================================================

var peer_id: int = -1
var player_name: String = ""
var corporation_tag: String = ""
var ship_id: StringName = Constants.DEFAULT_SHIP_ID
var ship_class: StringName = &"Fighter"
var linear_velocity: Vector3 = Vector3.ZERO
var _was_dead: bool = false
var _is_cruising: bool = false
var _remote_beam = null

# Interpolation buffer (ring buffer of snapshots)
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 30
const EXTRAPOLATION_MAX: float = 0.5  # Max extrapolation time (seconds)

# Visual
var _ship_model = null
var _name_label: Label3D = null
var _health_system: HealthSystem = null


func _ready() -> void:
	_setup_model()
	_setup_name_label()
	_setup_collision()
	_setup_health_proxy()
	# Set faction for HUD color coding (remote players = friendly)
	set_meta("faction", &"player")
	# NOTE: starts hidden + NOT in "ships" group. The first receive_state()
	# with valid position makes us visible and adds us to the group.
	# This prevents the puppet flashing at (0,0,0) before real data arrives.


func _setup_model() -> void:
	var data = ShipRegistry.get_ship_data(ship_id)
	_ship_model = ShipModel.new()
	_ship_model.name = "ShipModel"
	if data:
		_ship_model.model_path = data.model_path
		_ship_model.model_scale = ShipFactory.get_scene_model_scale(ship_id)
		_ship_model.model_rotation_degrees = ShipFactory.get_model_rotation(ship_id)
	else:
		_ship_model.model_path = "res://assets/models/tie.glb"
		_ship_model.model_scale = 2.0
	# Blue tint for other players (distinct from NPCs)
	_ship_model.color_tint = Color(0.6, 0.85, 1.0)
	_ship_model.engine_light_color = Color(0.3, 0.7, 1.0)
	add_child(_ship_model)


func _setup_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = _build_display_name()
	_name_label.font_size = 64
	_name_label.pixel_size = 0.04
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	var data_lbl = ShipRegistry.get_ship_data(ship_id)
	var label_height: float = 15.0
	if data_lbl:
		label_height = data_lbl.collision_size.y * 0.5 + 8.0
	_name_label.position = Vector3(0, label_height, 0)
	_name_label.modulate = Color(0.3, 0.85, 1.0, 0.9)
	add_child(_name_label)


func _setup_collision() -> void:
	var data = ShipRegistry.get_ship_data(ship_id)
	var body = StaticBody3D.new()
	body.name = "HitBody"
	body.collision_layer = 0  # Starts disabled — enabled by receive_state() when visible
	body.collision_mask = 0  # Doesn't detect anything, only gets hit
	add_child(body)
	var shape = CollisionShape3D.new()
	shape.name = "HitShape"
	var box := BoxShape3D.new()
	box.size = data.collision_size if data else Vector3(28, 12, 36)
	shape.shape = box
	body.add_child(shape)


func _setup_health_proxy() -> void:
	# Lightweight HealthSystem child so the targeting HUD can read health/shield ratios.
	# We use max=1.0 so current value IS the ratio directly.
	# Shield regen is disabled — the real values come from the network.
	_health_system = HealthSystem.new()
	_health_system.name = "HealthSystem"
	_health_system.hull_max = 1.0
	_health_system.hull_current = 1.0
	_health_system.shield_max_per_facing = 1.0
	for i in 4:
		_health_system.shield_current[i] = 1.0
	add_child(_health_system)
	_health_system.set_process(false)  # No local shield regen


## Rebuild ship model when the remote player changes ship.
func change_ship_model(new_ship_id: StringName) -> void:
	if new_ship_id == ship_id:
		return
	ship_id = new_ship_id
	# Remove old model
	if _ship_model and is_instance_valid(_ship_model):
		remove_child(_ship_model)
		_ship_model.queue_free()
		_ship_model = null
	# Build new model
	_setup_model()
	if _name_label:
		_name_label.position = Vector3(0, 15, 0)


## Called when we receive a new state snapshot from the network.
func receive_state(state) -> void:
	# Update player name if it was missing at creation or changed
	if state.player_name != "" and state.player_name != player_name:
		player_name = state.player_name
		_update_name_display()

	# Detect corporation tag change
	if state.corporation_tag != corporation_tag:
		corporation_tag = state.corporation_tag
		_update_name_display()

	# Detect ship change from state
	if state.ship_id != &"" and state.ship_id != ship_id:
		change_ship_model(state.ship_id)

	# Track cruise state for visual effects (engine glow)
	_is_cruising = state.is_cruising

	# Hide puppet only when docked or dead — cruise stays visible (LOD handles distance)
	var should_hide: bool = state.is_docked or state.is_dead
	if visible != (not should_hide):
		# When becoming visible: teleport to correct position FIRST,
		# otherwise the puppet flashes at stale (0,0,0) = near spawn station
		if not visible and not should_hide:
			global_position = FloatingOrigin.to_local_pos([state.pos_x, state.pos_y, state.pos_z])
			rotation_degrees = state.rotation_deg
			_snapshots.clear()
		visible = not should_hide
		# Remove from targeting group + disable collision when hidden
		if should_hide:
			if is_in_group("ships"):
				remove_from_group("ships")
			var hit_body = get_node_or_null("HitBody") as StaticBody3D
			if hit_body:
				hit_body.collision_layer = 0
		else:
			if not is_in_group("ships"):
				add_to_group("ships")
			var hit_body = get_node_or_null("HitBody") as StaticBody3D
			if hit_body:
				hit_body.collision_layer = Constants.LAYER_SHIPS

	# Detect death/respawn transitions and clear stale snapshots
	if state.is_dead and not _was_dead:
		_was_dead = true
		_snapshots.clear()
	elif not state.is_dead and _was_dead:
		_was_dead = false
		_snapshots.clear()

	# Update health proxy from network state (even when hidden, so targeting is correct on reveal)
	if _health_system:
		var new_hull: float = state.hull_ratio
		if new_hull != _health_system.hull_current:
			_health_system.hull_current = new_hull
			_health_system.hull_changed.emit(new_hull, 1.0)
		for i in 4:
			if i < state.shield_ratios.size():
				var new_shd: float = state.shield_ratios[i]
				if new_shd != _health_system.shield_current[i]:
					_health_system.shield_current[i] = new_shd
					_health_system.shield_changed.emit(i, new_shd, 1.0)

	if should_hide:
		return  # Don't update interpolation while hidden

	# Stamp with LOCAL arrival time — sender's timestamp is from a different clock
	# (each Godot process has its own Time.get_ticks_msec starting at 0).
	# Using local time ensures render_time and snapshot times share the same clock.
	var snapshot: Dictionary = {
		"pos": [state.pos_x, state.pos_y, state.pos_z],
		"vel": state.velocity,
		"rot": state.rotation_deg,
		"thr": state.throttle,
		"time": Time.get_ticks_msec() / 1000.0,
	}

	_snapshots.append(snapshot)
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func _process(_delta: float) -> void:
	if _snapshots.is_empty():
		return

	var render_time: float = (Time.get_ticks_msec() / 1000.0) - Constants.NET_INTERPOLATION_DELAY

	if _snapshots.size() < 2:
		# Single snapshot — place at snapshot position, extrapolate with velocity
		var snap: Dictionary = _snapshots[0]
		var dt: float = clampf(render_time - snap["time"], 0.0, EXTRAPOLATION_MAX)
		var vel: Vector3 = snap["vel"]
		var pos_arr: Array = snap["pos"]
		var extrap_pos: Array = [
			pos_arr[0] + vel.x * dt,
			pos_arr[1] + vel.y * dt,
			pos_arr[2] + vel.z * dt,
		]
		global_position = FloatingOrigin.to_local_pos(extrap_pos)
		rotation_degrees = snap["rot"]
		linear_velocity = vel
		_update_engine_glow(snap.get("thr", 0.0))
		return

	# Find two snapshots to interpolate between (search from end — most recent first)
	var from_idx: int = -1
	for i in range(_snapshots.size() - 2, -1, -1):
		if _snapshots[i]["time"] <= render_time and _snapshots[i + 1]["time"] >= render_time:
			from_idx = i
			break

	if from_idx >= 0:
		_hermite_interpolate(_snapshots[from_idx], _snapshots[from_idx + 1], render_time)
	elif render_time > _snapshots.back()["time"]:
		# render_time past all snapshots — extrapolate from last two snapshots
		_extrapolate_smooth(render_time)
	else:
		# render_time before all snapshots — use earliest
		var snap: Dictionary = _snapshots[0]
		global_position = FloatingOrigin.to_local_pos(snap["pos"])
		rotation_degrees = snap["rot"]
		linear_velocity = snap["vel"]
		_update_engine_glow(snap.get("thr", 0.0))


## Hermite interpolation using position + velocity at both endpoints.
## Produces smooth curves that respect velocity direction and magnitude.
func _hermite_interpolate(from: Dictionary, to: Dictionary, render_time: float) -> void:
	var dt: float = to["time"] - from["time"]
	var t: float = clampf((render_time - from["time"]) / dt, 0.0, 1.0) if dt > 0.001 else 1.0

	# Hermite basis functions
	var t2: float = t * t
	var t3: float = t2 * t
	var h00: float = 2.0 * t3 - 3.0 * t2 + 1.0  # Position at start
	var h10: float = t3 - 2.0 * t2 + t            # Tangent at start
	var h01: float = -2.0 * t3 + 3.0 * t2         # Position at end
	var h11: float = t3 - t2                       # Tangent at end

	var pos_from: Array = from["pos"]
	var pos_to: Array = to["pos"]
	var vel_from: Vector3 = from["vel"]
	var vel_to: Vector3 = to["vel"]

	# Hermite position: H(t) = h00*P0 + h10*dt*V0 + h01*P1 + h11*dt*V1
	var interp_pos: Array = [
		h00 * pos_from[0] + h10 * dt * vel_from.x + h01 * pos_to[0] + h11 * dt * vel_to.x,
		h00 * pos_from[1] + h10 * dt * vel_from.y + h01 * pos_to[1] + h11 * dt * vel_to.y,
		h00 * pos_from[2] + h10 * dt * vel_from.z + h01 * pos_to[2] + h11 * dt * vel_to.z,
	]
	global_position = FloatingOrigin.to_local_pos(interp_pos)

	# Smooth rotation via lerp_angle (handles wrapping correctly)
	var rot_from: Vector3 = from["rot"]
	var rot_to: Vector3 = to["rot"]
	rotation_degrees = Vector3(
		lerp_angle(deg_to_rad(rot_from.x), deg_to_rad(rot_to.x), t),
		lerp_angle(deg_to_rad(rot_from.y), deg_to_rad(rot_to.y), t),
		lerp_angle(deg_to_rad(rot_from.z), deg_to_rad(rot_to.z), t),
	) * (180.0 / PI)

	# Use linear velocity interpolation (NOT Hermite derivative which amplifies noise
	# through position/dt division — causes lead indicator jitter on targeting HUD)
	linear_velocity = vel_from.lerp(vel_to, t)

	# Engine glow: use cruise state for max glow, otherwise interpolate throttle
	if _is_cruising:
		_update_engine_glow(1.0)
	else:
		_update_engine_glow(lerpf(from.get("thr", 0.0), to.get("thr", 0.0), t))


## Smooth extrapolation using velocity from the last two snapshots.
## Blends from full velocity to zero over EXTRAPOLATION_MAX seconds to
## prevent infinite drift when packets stop arriving.
func _extrapolate_smooth(render_time: float) -> void:
	var last: Dictionary = _snapshots.back()
	var dt: float = clampf(render_time - last["time"], 0.0, EXTRAPOLATION_MAX)
	var vel: Vector3 = last["vel"]

	# Decay factor: full speed at t=0, zero at EXTRAPOLATION_MAX
	var decay: float = 1.0 - (dt / EXTRAPOLATION_MAX)
	decay = decay * decay  # Quadratic ease-out

	var pos_arr: Array = last["pos"]
	# Integrate velocity with decay: integral of vel*(1-(t/T))^2 dt
	# = vel * (t - t²/T + t³/(3T²))
	var T: float = EXTRAPOLATION_MAX
	var integrated_dt: float = dt - (dt * dt) / T + (dt * dt * dt) / (3.0 * T * T)
	var extrap_pos: Array = [
		pos_arr[0] + vel.x * integrated_dt,
		pos_arr[1] + vel.y * integrated_dt,
		pos_arr[2] + vel.z * integrated_dt,
	]
	global_position = FloatingOrigin.to_local_pos(extrap_pos)

	# Extrapolate rotation using the rate between the last two snapshots
	if _snapshots.size() >= 2:
		var prev: Dictionary = _snapshots[_snapshots.size() - 2]
		var snap_dt: float = last["time"] - prev["time"]
		if snap_dt > 0.001:
			var rot_rate: Vector3 = (last["rot"] - prev["rot"]) / snap_dt
			# Wrap rate components to avoid jumps from 359->1 deg
			rot_rate.x = wrapf(rot_rate.x, -180.0, 180.0) if absf(rot_rate.x) > 180.0 else rot_rate.x
			rot_rate.y = wrapf(rot_rate.y, -180.0, 180.0) if absf(rot_rate.y) > 180.0 else rot_rate.y
			rot_rate.z = wrapf(rot_rate.z, -180.0, 180.0) if absf(rot_rate.z) > 180.0 else rot_rate.z
			rotation_degrees = last["rot"] + rot_rate * dt * decay
		else:
			rotation_degrees = last["rot"]
	else:
		rotation_degrees = last["rot"]

	linear_velocity = vel * decay
	if _is_cruising:
		_update_engine_glow(1.0)
	else:
		_update_engine_glow(last.get("thr", 0.0) * decay)


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)


## Spawn a death explosion at this puppet's location.
func show_death_explosion() -> void:
	var pos = global_position
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	var explosion = ExplosionEffect.new()
	scene_root.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * 3.0


## Show a remote mining beam from source to target (universe positions).
func show_mining_beam(source_pos: Array, target_pos: Array) -> void:
	var local_src = FloatingOrigin.to_local_pos(source_pos)
	var local_tgt = FloatingOrigin.to_local_pos(target_pos)
	if _remote_beam == null:
		_remote_beam = MiningLaserBeam.new()
		_remote_beam.name = "RemoteMiningBeam"
		add_child(_remote_beam)
	if not _remote_beam._active:
		_remote_beam.activate(local_src, local_tgt)
	_remote_beam.update_beam(local_src, local_tgt)


## Hide the remote mining beam.
func hide_mining_beam() -> void:
	if _remote_beam and _remote_beam._active:
		_remote_beam.deactivate()


## Update the name label text.
func set_player_name(pname: String) -> void:
	player_name = pname
	_update_name_display()


func _build_display_name() -> String:
	var base: String = player_name if player_name != "" else "Pilote"
	if corporation_tag != "":
		return "[%s] %s" % [corporation_tag, base]
	return base


func _update_name_display() -> void:
	if _name_label:
		_name_label.text = _build_display_name()
