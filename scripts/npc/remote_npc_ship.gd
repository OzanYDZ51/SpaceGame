class_name RemoteNPCShip
extends Node3D

# =============================================================================
# Remote NPC Ship - Visual puppet for a server-authoritative NPC.
# Receives state snapshots from the server and interpolates smoothly.
# Uses Hermite interpolation (position + velocity) for smooth curves.
# Similar to RemotePlayerShip but for NPCs.
# =============================================================================

var npc_id: StringName = &""
var ship_id: StringName = Constants.DEFAULT_SHIP_ID
var faction: StringName = &"hostile"
var owner_name: String = ""  # Non-empty for player_fleet NPCs: identifies the owner
var linear_velocity: Vector3 = Vector3.ZERO
var fleet_weapons: Array[StringName] = []  # Weapon loadout for fleet NPC visuals

# Interpolation buffer
var _snapshots: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = 30
const EXTRAPOLATION_MAX: float = Constants.NPC_EXTRAPOLATION_MAX

# Visual
var _ship_model = null
var _engine_exhaust: EngineExhaust = null
# Health proxy (synced from network state)
var _health: HealthSystem = null


func _ready() -> void:
	_setup_model()
	_setup_collision()
	_setup_health_proxy()
	if not fleet_weapons.is_empty():
		setup_weapon_visuals(fleet_weapons)
	add_to_group("ships")
	set_meta("faction", faction)


func _setup_model() -> void:
	var data = ShipRegistry.get_ship_data(ship_id)
	_ship_model = ShipModel.new()
	_ship_model.name = "ShipModel"
	_ship_model.skip_centering = true  # Match local ships — keeps visual aligned with collision hull
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
	elif faction == &"pirate":
		_ship_model.color_tint = Color(1.0, 0.7, 0.2)
		_ship_model.engine_light_color = Color(1.0, 0.5, 0.1)
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
	_setup_engine_exhaust()


func _setup_engine_exhaust() -> void:
	if _ship_model == null:
		return
	var vfx_pts: Array[Dictionary] = ShipFactory.get_vfx_points(ship_id)
	var data: ShipData = ShipRegistry.get_ship_data(ship_id)
	_engine_exhaust = EngineExhaust.new()
	_engine_exhaust.name = "EngineExhaust"
	_ship_model.add_child(_engine_exhaust)
	_engine_exhaust.setup(_ship_model.model_scale, _ship_model.engine_light_color, vfx_pts, data)


func _setup_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.collision_layer = Constants.LAYER_SHIPS
	body.collision_mask = 0  # Only gets hit, doesn't detect
	add_child(body)
	var col := CollisionShape3D.new()
	col.name = "HitShape"
	# Use convex hull from mesh (matches visual model exactly) with fallback to box
	var convex: ConvexPolygonShape3D = ShipFactory.get_convex_shape_for_ship(ship_id)
	if convex:
		col.shape = convex
		col.rotation_degrees = ShipFactory.get_model_rotation(ship_id)
	else:
		var data = ShipRegistry.get_ship_data(ship_id)
		var box := BoxShape3D.new()
		box.size = data.collision_size if data else Vector3(28, 12, 36)
		col.shape = box
	body.add_child(col)


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


## Attach weapon model meshes at hardpoint positions (visual only, no firing logic).
func setup_weapon_visuals(weapons: Array[StringName]) -> void:
	if _ship_model == null:
		return
	var data = ShipRegistry.get_ship_data(ship_id)
	if data == null or data.hardpoints.is_empty():
		return
	var hp_configs: Array[Dictionary] = []
	for hp in data.hardpoints:
		hp_configs.append(hp)
	var root_basis: Basis = ShipFactory.get_root_basis(ship_id)
	_ship_model.apply_equipment(hp_configs, weapons, root_basis)


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
	var snapshot: Dictionary = {
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

	var render_time: float = (Time.get_ticks_msec() / 1000.0) - Constants.NPC_INTERPOLATION_DELAY

	if _snapshots.size() < 2:
		# Single snapshot — extrapolate with velocity
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
		# render_time past all snapshots — extrapolate with decay
		_extrapolate_smooth(render_time)
	else:
		# render_time before all snapshots — use earliest
		var snap: Dictionary = _snapshots[0]
		global_position = FloatingOrigin.to_local_pos(snap["pos"])
		rotation_degrees = snap["rot"]
		linear_velocity = snap["vel"]
		_update_engine_glow(snap.get("thr", 0.0))


## Hermite interpolation using position + velocity at both endpoints.
func _hermite_interpolate(from: Dictionary, to: Dictionary, render_time: float) -> void:
	var dt: float = to["time"] - from["time"]
	var t: float = clampf((render_time - from["time"]) / dt, 0.0, 1.0) if dt > 0.001 else 1.0

	# Hermite basis functions
	var t2: float = t * t
	var t3: float = t2 * t
	var h00: float = 2.0 * t3 - 3.0 * t2 + 1.0
	var h10: float = t3 - 2.0 * t2 + t
	var h01: float = -2.0 * t3 + 3.0 * t2
	var h11: float = t3 - t2

	var pos_from: Array = from["pos"]
	var pos_to: Array = to["pos"]
	var vel_from: Vector3 = from["vel"]
	var vel_to: Vector3 = to["vel"]

	var interp_pos: Array = [
		h00 * pos_from[0] + h10 * dt * vel_from.x + h01 * pos_to[0] + h11 * dt * vel_to.x,
		h00 * pos_from[1] + h10 * dt * vel_from.y + h01 * pos_to[1] + h11 * dt * vel_to.y,
		h00 * pos_from[2] + h10 * dt * vel_from.z + h01 * pos_to[2] + h11 * dt * vel_to.z,
	]
	global_position = FloatingOrigin.to_local_pos(interp_pos)

	var rot_from: Vector3 = from["rot"]
	var rot_to: Vector3 = to["rot"]
	rotation_degrees = Vector3(
		lerp_angle(deg_to_rad(rot_from.x), deg_to_rad(rot_to.x), t),
		lerp_angle(deg_to_rad(rot_from.y), deg_to_rad(rot_to.y), t),
		lerp_angle(deg_to_rad(rot_from.z), deg_to_rad(rot_to.z), t),
	) * (180.0 / PI)

	# Interpolate velocity (linear is fine for velocity — Hermite derivative would amplify noise)
	linear_velocity = vel_from.lerp(vel_to, t)
	_update_engine_glow(lerpf(from.get("thr", 0.0), to.get("thr", 0.0), t))


## Smooth extrapolation with gentle velocity decay to prevent infinite drift.
func _extrapolate_smooth(render_time: float) -> void:
	var last: Dictionary = _snapshots.back()
	var dt: float = clampf(render_time - last["time"], 0.0, EXTRAPOLATION_MAX)
	var vel: Vector3 = last["vel"]

	# Linear decay: full speed for first 50%, then gentle slowdown
	# This avoids the jarring quadratic decay that made NPCs visibly decelerate
	var decay: float = clampf(1.0 - maxf(dt - 0.5, 0.0) / (EXTRAPOLATION_MAX - 0.5), 0.0, 1.0)

	# Constant velocity for first 500ms, then linear deceleration
	var extrap_dt: float = minf(dt, 0.5) + maxf(dt - 0.5, 0.0) * decay
	var pos_arr: Array = last["pos"]
	var extrap_pos: Array = [
		pos_arr[0] + vel.x * extrap_dt,
		pos_arr[1] + vel.y * extrap_dt,
		pos_arr[2] + vel.z * extrap_dt,
	]
	global_position = FloatingOrigin.to_local_pos(extrap_pos)

	# Extrapolate rotation from last two snapshots
	if _snapshots.size() >= 2:
		var prev: Dictionary = _snapshots[_snapshots.size() - 2]
		var snap_dt: float = last["time"] - prev["time"]
		if snap_dt > 0.001:
			var rot_rate: Vector3 = (last["rot"] - prev["rot"]) / snap_dt
			rot_rate.x = wrapf(rot_rate.x, -180.0, 180.0) if absf(rot_rate.x) > 180.0 else rot_rate.x
			rot_rate.y = wrapf(rot_rate.y, -180.0, 180.0) if absf(rot_rate.y) > 180.0 else rot_rate.y
			rot_rate.z = wrapf(rot_rate.z, -180.0, 180.0) if absf(rot_rate.z) > 180.0 else rot_rate.z
			rotation_degrees = last["rot"] + rot_rate * dt * decay
		else:
			rotation_degrees = last["rot"]
	else:
		rotation_degrees = last["rot"]

	linear_velocity = vel * decay
	_update_engine_glow(last.get("thr", 0.0) * maxf(decay, 0.3))


func _update_engine_glow(throttle_amount: float) -> void:
	if _ship_model:
		_ship_model.update_engine_glow(throttle_amount)
	if _engine_exhaust and is_instance_valid(_engine_exhaust):
		var speed: float = linear_velocity.length()
		_engine_exhaust.update_intensity(throttle_amount, Constants.SpeedMode.NORMAL, speed)


## Play death animation and clean up.
func play_death() -> void:
	# Spawn explosion effect
	var explosion = ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	# Scale down and free
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(queue_free)
