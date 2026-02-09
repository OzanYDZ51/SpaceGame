class_name RemotePlayerShip
extends Node3D

# =============================================================================
# Remote Player Ship - Visual puppet for a remote player.
# Receives state snapshots and interpolates smoothly between them.
# No physics simulation — purely visual.
# =============================================================================

var peer_id: int = -1
var player_name: String = ""
var ship_id: StringName = &"fighter_mk1"
var ship_class: StringName = &"Fighter"
var _was_dead: bool = false

# Interpolation buffer (ring buffer of snapshots)
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 20

# Visual
var _ship_model: ShipModel = null
var _name_label: Label3D = null


func _ready() -> void:
	_setup_model()
	_setup_name_label()
	# Add to ships group for radar/targeting
	add_to_group("ships")
	# Set faction for HUD color coding (remote players = friendly)
	set_meta("faction", &"player")


func _setup_model() -> void:
	var data := ShipRegistry.get_ship_data(ship_id)
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
	_name_label.text = player_name if player_name != "" else "Pilote"
	_name_label.font_size = 64
	_name_label.pixel_size = 0.04
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, 15, 0)
	_name_label.modulate = Color(0.3, 0.85, 1.0, 0.9)
	add_child(_name_label)


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
func receive_state(state: NetworkState) -> void:
	# Detect ship change from state
	if state.ship_id != &"" and state.ship_id != ship_id:
		change_ship_model(state.ship_id)

	# Hide puppet when the remote player is docked, dead, or in cruise warp
	var should_hide: bool = state.is_docked or state.is_dead or state.is_cruising
	if visible != (not should_hide):
		visible = not should_hide

	# Detect death/respawn transitions and clear stale snapshots
	if state.is_dead and not _was_dead:
		_was_dead = true
		_snapshots.clear()
	elif not state.is_dead and _was_dead:
		_was_dead = false
		_snapshots.clear()

	if should_hide:
		return  # Don't update interpolation while hidden

	var snapshot := {
		"pos": [state.pos_x, state.pos_y, state.pos_z],
		"vel": state.velocity,
		"rot": state.rotation_deg,
		"thr": state.throttle,
		"hull": state.hull_ratio,
		"shd": state.shield_ratios,
		"time": state.timestamp,
	}

	_snapshots.append(snapshot)
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func _process(_delta: float) -> void:
	if _snapshots.is_empty():
		return

	# Interpolation: render at (current_time - interpolation_delay)
	# This gives us a smooth path between snapshots
	var render_time: float = (Time.get_ticks_msec() / 1000.0) - Constants.NET_INTERPOLATION_DELAY

	if _snapshots.size() < 2:
		# Only 1 snapshot: snap to it
		_apply_snapshot(_snapshots[0])
		return

	# Find two snapshots to interpolate between (search from end — most recent is most likely)
	var from_idx: int = -1
	for i in range(_snapshots.size() - 2, -1, -1):
		if _snapshots[i]["time"] <= render_time and _snapshots[i + 1]["time"] >= render_time:
			from_idx = i
			break

	if from_idx == -1:
		# Render time is beyond our buffer — use latest snapshot
		_apply_snapshot(_snapshots.back())
		return

	var from: Dictionary = _snapshots[from_idx]
	var to: Dictionary = _snapshots[from_idx + 1]
	var t_range: float = to["time"] - from["time"]
	if t_range < 0.001:
		_apply_snapshot(to)
		return

	var t: float = clampf((render_time - from["time"]) / t_range, 0.0, 1.0)
	_interpolate_between(from, to, t)


func _apply_snapshot(snap: Dictionary) -> void:
	var local_pos := FloatingOrigin.to_local_pos(snap["pos"])

	# Snap if teleported (system change, etc.), otherwise lerp for smoothing
	if global_position.distance_to(local_pos) > Constants.NET_SNAP_THRESHOLD * 10.0:
		global_position = local_pos
	else:
		global_position = global_position.lerp(local_pos, 0.5)

	rotation_degrees = snap["rot"]
	_update_engine_glow(snap.get("thr", 0.0))


func _interpolate_between(from: Dictionary, to: Dictionary, t: float) -> void:
	# Interpolate universe position, then convert to local
	var pos_from := from["pos"] as Array
	var pos_to := to["pos"] as Array
	var interp_pos: Array = [
		lerpf(pos_from[0], pos_to[0], t),
		lerpf(pos_from[1], pos_to[1], t),
		lerpf(pos_from[2], pos_to[2], t),
	]

	var local_pos := FloatingOrigin.to_local_pos(interp_pos)

	# Snap if too far (teleport/system change), otherwise use interpolated position directly
	if global_position.distance_to(local_pos) > Constants.NET_SNAP_THRESHOLD * 10.0:
		global_position = local_pos
	else:
		global_position = global_position.lerp(local_pos, 0.65)

	# Slerp rotation
	var rot_from: Vector3 = from["rot"]
	var rot_to: Vector3 = to["rot"]
	rotation_degrees = rot_from.lerp(rot_to, t)

	# Throttle
	var thr := lerpf(from.get("thr", 0.0), to.get("thr", 0.0), t)
	_update_engine_glow(thr)


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)


## Spawn a death explosion at this puppet's location.
func show_death_explosion() -> void:
	var pos := global_position
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var explosion := ExplosionEffect.new()
	scene_root.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * 3.0


## Update the name label text.
func set_player_name(pname: String) -> void:
	player_name = pname
	if _name_label:
		_name_label.text = pname
