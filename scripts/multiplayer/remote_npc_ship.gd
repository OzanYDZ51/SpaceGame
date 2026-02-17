class_name RemoteNPCShip
extends Node3D

# =============================================================================
# Remote NPC Ship - Visual puppet for a server-authoritative NPC.
# Receives state snapshots from the server and interpolates smoothly.
# Similar to RemotePlayerShip but for NPCs.
# =============================================================================

var npc_id: StringName = &""
var ship_id: StringName = Constants.DEFAULT_SHIP_ID
var faction: StringName = &"hostile"
var linear_velocity: Vector3 = Vector3.ZERO

# Interpolation buffer
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 20

# Visual
var _ship_model = null
var _name_label: Label3D = null

# Health proxy (synced from network state)
var _health: HealthSystem = null


func _ready() -> void:
	_setup_model()
	_setup_name_label()
	_setup_collision()
	_setup_health_proxy()
	add_to_group("ships")
	set_meta("faction", faction)


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
	var data =ShipRegistry.get_ship_data(ship_id)
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
	var label_height: float = 15.0
	if data:
		label_height = data.collision_size.y * 0.5 + 8.0
	_name_label.position = Vector3(0, label_height, 0)

	if faction == &"hostile":
		_name_label.modulate = Color(1.0, 0.4, 0.3, 0.8)
	elif faction == &"friendly":
		_name_label.modulate = Color(0.3, 1.0, 0.5, 0.8)
	elif faction == &"player_fleet":
		_name_label.modulate = Color(0.4, 0.65, 1.0, 0.9)
	else:
		_name_label.modulate = Color(0.7, 0.6, 1.0, 0.8)

	add_child(_name_label)


func _setup_collision() -> void:
	var data = ShipRegistry.get_ship_data(ship_id)
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.collision_layer = Constants.LAYER_SHIPS
	body.collision_mask = 0  # Only gets hit, doesn't detect
	add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "HitShape"
	var box := BoxShape3D.new()
	box.size = data.collision_size if data else Vector3(28, 12, 36)
	shape.shape = box
	body.add_child(shape)


func _setup_health_proxy() -> void:
	_health = HealthSystem.new()
	_health.name = "HealthSystem"
	# Initialize with ship data if available
	var data = ShipRegistry.get_ship_data(ship_id)
	if data:
		_health.hull_max = data.hull_hp
		_health.hull_current = data.hull_hp
		var spf: float = data.shield_hp / 4.0
		_health.shield_max_per_facing = spf
		_health.shield_current = [spf, spf, spf, spf]
	# Disable processing — we update manually from network state
	_health.set_process(false)
	_health.set_physics_process(false)
	add_child(_health)


## Update health proxy from network hull/shield ratios.
func _sync_health(hull_ratio: float, shield_ratio: float) -> void:
	if _health == null:
		return
	_health.hull_current = hull_ratio * _health.hull_max
	var shd_per := shield_ratio * _health.shield_max_per_facing
	for i in 4:
		_health.shield_current[i] = shd_per


## Receive a state snapshot from the server (via NPCSyncState dict).
func receive_state(state_dict: Dictionary) -> void:
	# Stamp with LOCAL arrival time — server's timestamp is from a different clock
	# (each Godot process has its own Time.get_ticks_msec starting at 0).
	# Using local time ensures render_time and snapshot times share the same clock.
	var snapshot ={
		"pos": [state_dict.get("px", 0.0), state_dict.get("py", 0.0), state_dict.get("pz", 0.0)],
		"vel": Vector3(state_dict.get("vx", 0.0), state_dict.get("vy", 0.0), state_dict.get("vz", 0.0)),
		"rot": Vector3(state_dict.get("rx", 0.0), state_dict.get("ry", 0.0), state_dict.get("rz", 0.0)),
		"thr": state_dict.get("thr", 0.0),
		"hull": state_dict.get("hull", 1.0),
		"shd": state_dict.get("shd", 1.0),
		"time": Time.get_ticks_msec() / 1000.0,
	}

	_snapshots.append(snapshot)
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()

	# Sync health proxy from latest state
	_sync_health(snapshot["hull"], snapshot["shd"])


func _process(_delta: float) -> void:
	if _snapshots.is_empty():
		return

	var render_time: float = (Time.get_ticks_msec() / 1000.0) - Constants.NET_INTERPOLATION_DELAY

	if _snapshots.size() < 2:
		var snap: Dictionary = _snapshots[0]
		global_position = FloatingOrigin.to_local_pos(snap["pos"])
		rotation_degrees = snap["rot"]
		linear_velocity = snap["vel"]
		_update_engine_glow(snap.get("thr", 0.0))
		return

	var from_idx: int = -1
	for i in range(_snapshots.size() - 2, -1, -1):
		if _snapshots[i]["time"] <= render_time and _snapshots[i + 1]["time"] >= render_time:
			from_idx = i
			break

	if from_idx >= 0:
		_interpolate_between(_snapshots[from_idx], _snapshots[from_idx + 1], render_time)
	else:
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

	linear_velocity = from["vel"].lerp(to["vel"], t)
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
	linear_velocity = vel
	_update_engine_glow(snap.get("thr", 0.0))


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)


## Play death animation and clean up.
func play_death() -> void:
	# Spawn explosion effect
	var explosion =ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Scale down and free
	var tween =create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(queue_free)
