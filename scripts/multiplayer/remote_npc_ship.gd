class_name RemoteNPCShip
extends Node3D

# =============================================================================
# Remote NPC Ship - Visual puppet for a server-authoritative NPC.
# Receives state snapshots from the server and interpolates smoothly.
# Similar to RemotePlayerShip but for NPCs.
# =============================================================================

var npc_id: StringName = &""
var ship_id: StringName = &"fighter_mk1"
var faction: StringName = &"hostile"

# Interpolation buffer
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 20

# Visual
var _ship_model: ShipModel = null
var _name_label: Label3D = null


func _ready() -> void:
	_setup_model()
	_setup_name_label()
	add_to_group("ships")
	set_meta("faction", faction)


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

	# Faction color tint
	if faction == &"hostile":
		_ship_model.color_tint = Color(1.0, 0.55, 0.5)
		_ship_model.engine_light_color = Color(1.0, 0.3, 0.2)
	elif faction == &"friendly":
		_ship_model.color_tint = Color(0.5, 1.0, 0.6)
		_ship_model.engine_light_color = Color(0.2, 1.0, 0.4)
	elif faction == &"player_fleet":
		_ship_model.color_tint = Color(0.5, 0.7, 1.0)
		_ship_model.engine_light_color = Color(0.3, 0.5, 1.0)
	else:
		_ship_model.color_tint = Color(0.8, 0.7, 1.0)
		_ship_model.engine_light_color = Color(0.5, 0.4, 1.0)

	add_child(_ship_model)


func _setup_name_label() -> void:
	var data := ShipRegistry.get_ship_data(ship_id)
	var display_name: String = String(data.ship_name) if data else String(ship_id)
	if faction == &"player_fleet":
		display_name += " [FLOTTE]"

	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = display_name
	_name_label.font_size = 48
	_name_label.pixel_size = 0.05
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, 15, 0)

	if faction == &"hostile":
		_name_label.modulate = Color(1.0, 0.4, 0.3, 0.8)
	elif faction == &"friendly":
		_name_label.modulate = Color(0.3, 1.0, 0.5, 0.8)
	elif faction == &"player_fleet":
		_name_label.modulate = Color(0.4, 0.65, 1.0, 0.9)
	else:
		_name_label.modulate = Color(0.7, 0.6, 1.0, 0.8)

	add_child(_name_label)


## Receive a state snapshot from the server (via NPCSyncState dict).
func receive_state(state_dict: Dictionary) -> void:
	var snapshot := {
		"pos": [state_dict.get("px", 0.0), state_dict.get("py", 0.0), state_dict.get("pz", 0.0)],
		"vel": Vector3(state_dict.get("vx", 0.0), state_dict.get("vy", 0.0), state_dict.get("vz", 0.0)),
		"rot": Vector3(state_dict.get("rx", 0.0), state_dict.get("ry", 0.0), state_dict.get("rz", 0.0)),
		"thr": state_dict.get("thr", 0.0),
		"hull": state_dict.get("hull", 1.0),
		"shd": state_dict.get("shd", 1.0),
		"time": state_dict.get("t", Time.get_ticks_msec() / 1000.0),
	}

	_snapshots.append(snapshot)
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func _process(_delta: float) -> void:
	if _snapshots.is_empty():
		return

	var render_time: float = (Time.get_ticks_msec() / 1000.0) - Constants.NET_INTERPOLATION_DELAY

	if _snapshots.size() < 2:
		_apply_snapshot(_snapshots[0])
		return

	# Find two snapshots to interpolate between
	var from_idx: int = -1
	for i in range(_snapshots.size() - 2, -1, -1):
		if _snapshots[i]["time"] <= render_time and _snapshots[i + 1]["time"] >= render_time:
			from_idx = i
			break

	if from_idx == -1:
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

	if global_position.distance_to(local_pos) > Constants.NET_SNAP_THRESHOLD * 10.0:
		global_position = local_pos
	else:
		global_position = global_position.lerp(local_pos, 0.5)

	rotation_degrees = snap["rot"]
	_update_engine_glow(snap.get("thr", 0.0))


func _interpolate_between(from: Dictionary, to: Dictionary, t: float) -> void:
	var pos_from := from["pos"] as Array
	var pos_to := to["pos"] as Array
	var interp_pos: Array = [
		lerpf(pos_from[0], pos_to[0], t),
		lerpf(pos_from[1], pos_to[1], t),
		lerpf(pos_from[2], pos_to[2], t),
	]

	var local_pos := FloatingOrigin.to_local_pos(interp_pos)

	if global_position.distance_to(local_pos) > Constants.NET_SNAP_THRESHOLD * 10.0:
		global_position = local_pos
	else:
		global_position = global_position.lerp(local_pos, 0.65)

	var rot_from: Vector3 = from["rot"]
	var rot_to: Vector3 = to["rot"]
	rotation_degrees = Vector3(
		lerp_angle(deg_to_rad(rot_from.x), deg_to_rad(rot_to.x), t),
		lerp_angle(deg_to_rad(rot_from.y), deg_to_rad(rot_to.y), t),
		lerp_angle(deg_to_rad(rot_from.z), deg_to_rad(rot_to.z), t),
	) * (180.0 / PI)

	var thr := lerpf(from.get("thr", 0.0), to.get("thr", 0.0), t)
	_update_engine_glow(thr)


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)


## Play death animation and clean up.
func play_death() -> void:
	# Spawn explosion effect
	var explosion := ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Scale down and free
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(queue_free)
