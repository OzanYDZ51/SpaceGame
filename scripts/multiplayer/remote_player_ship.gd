class_name RemotePlayerShip
extends Node3D

# =============================================================================
# Remote Player Ship - Visual puppet for a remote player.
# Receives state snapshots and interpolates smoothly between them.
# No physics simulation — purely visual.
# =============================================================================

var peer_id: int = -1
var player_name: String = ""
var clan_tag: String = ""
var ship_id: StringName = Constants.DEFAULT_SHIP_ID
var ship_class: StringName = &"Fighter"
var _was_dead: bool = false
var _remote_beam = null

# Interpolation buffer (ring buffer of snapshots)
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 20

# Visual
var _ship_model = null
var _name_label: Label3D = null


func _ready() -> void:
	_setup_model()
	_setup_name_label()
	_setup_collision()
	# Add to ships group for radar/targeting
	add_to_group("ships")
	# Set faction for HUD color coding (remote players = friendly)
	set_meta("faction", &"player")


func _setup_model() -> void:
	var data =ShipRegistry.get_ship_data(ship_id)
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
	_name_label.position = Vector3(0, 15, 0)
	_name_label.modulate = Color(0.3, 0.85, 1.0, 0.9)
	add_child(_name_label)


func _setup_collision() -> void:
	var body =StaticBody3D.new()
	body.name = "HitBody"
	body.collision_layer = Constants.LAYER_SHIPS
	body.collision_mask = 0  # Doesn't detect anything, only gets hit
	add_child(body)
	var shape =CollisionShape3D.new()
	shape.name = "HitShape"
	var sphere =SphereShape3D.new()
	sphere.radius = 8.0  # Generous hitbox for ship
	shape.shape = sphere
	body.add_child(shape)


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
	# Detect clan tag change
	if state.clan_tag != clan_tag:
		clan_tag = state.clan_tag
		_update_name_display()

	# Detect ship change from state
	if state.ship_id != &"" and state.ship_id != ship_id:
		change_ship_model(state.ship_id)

	# Hide puppet when the remote player is docked, dead, or in cruise warp
	var should_hide: bool = state.is_docked or state.is_dead or state.is_cruising
	if visible != (not should_hide):
		visible = not should_hide
		# Remove from targeting group + disable collision when hidden
		if should_hide:
			if is_in_group("ships"):
				remove_from_group("ships")
			var hit_body =get_node_or_null("HitBody") as StaticBody3D
			if hit_body:
				hit_body.collision_layer = 0
		else:
			if not is_in_group("ships"):
				add_to_group("ships")
			var hit_body =get_node_or_null("HitBody") as StaticBody3D
			if hit_body:
				hit_body.collision_layer = Constants.LAYER_SHIPS

	# Detect death/respawn transitions and clear stale snapshots
	if state.is_dead and not _was_dead:
		_was_dead = true
		_snapshots.clear()
	elif not state.is_dead and _was_dead:
		_was_dead = false
		_snapshots.clear()

	if should_hide:
		return  # Don't update interpolation while hidden

	# Stamp with LOCAL arrival time — sender's timestamp is from a different clock
	# (each Godot process has its own Time.get_ticks_msec starting at 0).
	# Using local time ensures render_time and snapshot times share the same clock.
	var snapshot ={
		"pos": [state.pos_x, state.pos_y, state.pos_z],
		"vel": state.velocity,
		"rot": state.rotation_deg,
		"thr": state.throttle,
		"hull": state.hull_ratio,
		"shd": state.shield_ratios,
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
		# Single snapshot — place directly, no smoothing
		var snap: Dictionary = _snapshots[0]
		global_position = FloatingOrigin.to_local_pos(snap["pos"])
		rotation_degrees = snap["rot"]
		_update_engine_glow(snap.get("thr", 0.0))
		return

	# Find two snapshots to interpolate between (search from end — most recent first)
	var from_idx: int = -1
	for i in range(_snapshots.size() - 2, -1, -1):
		if _snapshots[i]["time"] <= render_time and _snapshots[i + 1]["time"] >= render_time:
			from_idx = i
			break

	if from_idx >= 0:
		_interpolate_between(_snapshots[from_idx], _snapshots[from_idx + 1], render_time)
	else:
		# render_time past all snapshots — extrapolate from last snapshot using velocity
		_extrapolate(_snapshots.back(), render_time)


func _interpolate_between(from: Dictionary, to: Dictionary, render_time: float) -> void:
	var t_range: float = to["time"] - from["time"]
	var t: float = clampf((render_time - from["time"]) / t_range, 0.0, 1.0) if t_range > 0.001 else 1.0

	var pos_from =from["pos"] as Array
	var pos_to =to["pos"] as Array
	var interp_pos: Array = [
		lerpf(pos_from[0], pos_to[0], t),
		lerpf(pos_from[1], pos_to[1], t),
		lerpf(pos_from[2], pos_to[2], t),
	]
	global_position = FloatingOrigin.to_local_pos(interp_pos)

	var rot_from: Vector3 = from["rot"]
	var rot_to: Vector3 = to["rot"]
	rotation_degrees = Vector3(
		lerp_angle(deg_to_rad(rot_from.x), deg_to_rad(rot_to.x), t),
		lerp_angle(deg_to_rad(rot_from.y), deg_to_rad(rot_to.y), t),
		lerp_angle(deg_to_rad(rot_from.z), deg_to_rad(rot_to.z), t),
	) * (180.0 / PI)

	_update_engine_glow(lerpf(from.get("thr", 0.0), to.get("thr", 0.0), t))


func _extrapolate(snap: Dictionary, render_time: float) -> void:
	var dt: float = clampf(render_time - snap["time"], 0.0, 0.25)
	var vel: Vector3 = snap["vel"]
	var pos_arr: Array = snap["pos"]
	var extrap_pos: Array = [
		pos_arr[0] + vel.x * dt,
		pos_arr[1] + vel.y * dt,
		pos_arr[2] + vel.z * dt,
	]
	global_position = FloatingOrigin.to_local_pos(extrap_pos)
	rotation_degrees = snap["rot"]
	_update_engine_glow(snap.get("thr", 0.0))


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)


## Spawn a death explosion at this puppet's location.
func show_death_explosion() -> void:
	var pos =global_position
	var scene_root =get_tree().current_scene
	if scene_root == null:
		return
	var explosion =ExplosionEffect.new()
	scene_root.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * 3.0


## Show a remote mining beam from source to target (universe positions).
func show_mining_beam(source_pos: Array, target_pos: Array) -> void:
	var local_src =FloatingOrigin.to_local_pos(source_pos)
	var local_tgt =FloatingOrigin.to_local_pos(target_pos)
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
	if clan_tag != "":
		return "[%s] %s" % [clan_tag, base]
	return base


func _update_name_display() -> void:
	if _name_label:
		_name_label.text = _build_display_name()
