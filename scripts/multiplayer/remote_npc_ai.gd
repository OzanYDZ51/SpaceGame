class_name RemoteNpcAI
extends RefCounted

# =============================================================================
# Remote NPC AI — Headless data-only simulation for NPCs in systems where the
# server has no scene nodes loaded. Pure math on NPC state dictionaries.
#
# IMPORTANT: All position math uses float64 (GDScript `float`) to avoid
# precision loss. Vector3 is float32 and fails at universe-scale coordinates.
#
# States: PATROL (1), PURSUE (2), ATTACK (3), EVADE (4), FLEE (5) — aligned with AIBrain
# =============================================================================

enum State { PATROL = 1, PURSUE = 2, ATTACK = 3, EVADE = 4, FLEE = 5 }

const DETECTION_RANGE: float = 3000.0
const ENGAGEMENT_RANGE: float = 800.0
const OPTIMAL_COMBAT_RANGE: float = 400.0
const FIRE_CONE_COS: float = 0.866  # cos(30°) — 60° cone
const FLEE_HULL_THRESHOLD: float = 0.2
const EVADE_DURATION: float = 3.0
const PATROL_SPEED: float = 60.0
const TURN_RATE: float = 2.0  # radians/sec


## Main tick — update a single NPC dict. Returns fire event dict or null.
static func tick(npc: Dictionary, peers_in_system: Dictionary, _all_npcs: Array, delta: float) -> void:
	if npc.get("is_dead", false):
		return

	var state: int = npc.get("ai", State.PATROL)
	var ship_data: ShipData = ShipRegistry.get_ship_data(StringName(npc.get("sid", "")))
	var max_speed: float = ship_data.max_speed_normal if ship_data else 300.0
	var accel: float = ship_data.accel_forward if ship_data else 80.0
	# Use float64 for NPC position (dictionary stores float64, Vector3 is float32)
	var npx: float = npc.get("px", 0.0)
	var npy: float = npc.get("py", 0.0)
	var npz: float = npc.get("pz", 0.0)
	var nvx: float = npc.get("vx", 0.0)
	var nvy: float = npc.get("vy", 0.0)
	var nvz: float = npc.get("vz", 0.0)
	var faction: String = npc.get("fac", "hostile")

	# Detect nearest hostile peer (all math in float64)
	var target_pid: int = -1
	var tpx: float = 0.0
	var tpy: float = 0.0
	var tpz: float = 0.0
	var target_dist_sq: float = INF

	for pid in peers_in_system:
		var pstate = peers_in_system[pid]
		if pstate.is_docked or pstate.is_dead:
			continue
		if faction == "neutral":
			continue
		var dx: float = pstate.pos_x - npx
		var dy: float = pstate.pos_y - npy
		var dz: float = pstate.pos_z - npz
		var dsq: float = dx * dx + dy * dy + dz * dz
		if dsq < target_dist_sq and dsq < DETECTION_RANGE * DETECTION_RANGE:
			target_dist_sq = dsq
			tpx = pstate.pos_x
			tpy = pstate.pos_y
			tpz = pstate.pos_z
			target_pid = pid

	var target_dist: float = sqrt(target_dist_sq) if target_dist_sq < INF else INF

	# State transitions
	var hull: float = npc.get("hull", 1.0)
	match state:
		State.PATROL:
			if target_pid >= 0:
				state = State.PURSUE
				npc["tid"] = str(target_pid)
		State.PURSUE:
			if target_pid < 0:
				state = State.PATROL
				npc["tid"] = ""
			elif target_dist < ENGAGEMENT_RANGE:
				state = State.ATTACK
			if hull < FLEE_HULL_THRESHOLD:
				state = State.FLEE
		State.ATTACK:
			if target_pid < 0:
				state = State.PATROL
				npc["tid"] = ""
			elif target_dist > DETECTION_RANGE:
				state = State.PURSUE
			if hull < FLEE_HULL_THRESHOLD:
				state = State.FLEE
		State.EVADE:
			var evade_t: float = npc.get("_evade_timer", 0.0) - delta
			if evade_t <= 0.0:
				state = State.ATTACK if target_pid >= 0 else State.PATROL
				npc.erase("_evade_timer")
			else:
				npc["_evade_timer"] = evade_t
		State.FLEE:
			if hull > FLEE_HULL_THRESHOLD + 0.1:
				state = State.PATROL

	npc["ai"] = state

	# For movement math, use RELATIVE positions (float64 deltas → safe in Vector3)
	# This avoids float32 precision loss when absolute coords are large.
	var rel_target := Vector3.ZERO
	if target_pid >= 0:
		rel_target = Vector3(tpx - npx, tpy - npy, tpz - npz)
	var npc_vel := Vector3(nvx, nvy, nvz)

	# Execute state behavior (all movement in local/relative coordinates)
	match state:
		State.PATROL:
			_do_patrol(npc, npx, npy, npz, npc_vel, delta, max_speed)
		State.PURSUE:
			_do_pursue(npc, npx, npy, npz, npc_vel, rel_target, delta, accel, max_speed)
		State.ATTACK:
			_do_attack(npc, npx, npy, npz, npc_vel, rel_target, target_dist, target_pid, delta, accel, max_speed, ship_data)
		State.EVADE:
			_do_evade(npc, npx, npy, npz, npc_vel, rel_target, delta, accel, max_speed)
		State.FLEE:
			_do_flee(npc, npx, npy, npz, npc_vel, rel_target, delta, accel, max_speed)

	npc["t"] = Time.get_ticks_msec() / 1000.0


static func _do_patrol(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, delta: float, max_speed: float) -> void:
	# Patrol center stored as float64 offsets
	var cx: float = npc.get("_patrol_cx", px)
	var cz: float = npc.get("_patrol_cz", pz)
	if not npc.has("_patrol_cx"):
		npc["_patrol_cx"] = px
		npc["_patrol_cz"] = pz

	# Relative to NPC (safe for Vector3)
	var to_center := Vector3(cx - px, 0.0, cz - pz)
	var dist_from_center: float = to_center.length()

	if dist_from_center > 1500.0:
		var dir: Vector3 = to_center.normalized()
		vel = vel.move_toward(dir * PATROL_SPEED, 40.0 * delta)
	else:
		var radial: Vector3 = to_center.normalized() if dist_from_center > 1.0 else Vector3.FORWARD
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		vel = vel.move_toward(tangent * PATROL_SPEED, 30.0 * delta)

	_apply_velocity(npc, px, py, pz, vel, delta, max_speed * 0.3)


static func _do_pursue(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, rel_target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	var dir: Vector3 = rel_target.normalized() if rel_target.length_squared() > 1.0 else Vector3.FORWARD
	vel = vel.move_toward(dir * max_speed * 0.7, accel * delta)
	_update_rotation_toward(npc, dir, delta)
	_apply_velocity(npc, px, py, pz, vel, delta, max_speed * 0.7)


static func _do_attack(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, rel_target: Vector3, dist: float, target_pid: int, delta: float, accel: float, max_speed: float, ship_data: ShipData) -> void:
	var dir: Vector3 = rel_target.normalized() if dist > 1.0 else Vector3.FORWARD

	var desired_dir: Vector3
	if dist > OPTIMAL_COMBAT_RANGE * 1.3:
		desired_dir = dir
	elif dist < OPTIMAL_COMBAT_RANGE * 0.5:
		desired_dir = -dir
	else:
		desired_dir = Vector3(-dir.z, 0.0, dir.x)

	vel = vel.move_toward(desired_dir * max_speed * 0.5, accel * delta)
	_update_rotation_toward(npc, dir, delta)
	_apply_velocity(npc, px, py, pz, vel, delta, max_speed * 0.6)

	_try_fire(npc, px, py, pz, dir, dist, target_pid, delta, ship_data)


static func _do_evade(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, rel_target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	var away: Vector3 = -rel_target.normalized() if rel_target.length_squared() > 1.0 else Vector3.FORWARD
	var evade_dir := Vector3(-away.z, randf_range(-0.3, 0.3), away.x)
	vel = vel.move_toward(evade_dir * max_speed * 0.8, accel * 1.5 * delta)
	_apply_velocity(npc, px, py, pz, vel, delta, max_speed * 0.8)


static func _do_flee(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, rel_target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	var away: Vector3 = -rel_target.normalized() if rel_target.length_squared() > 1.0 else Vector3.FORWARD
	vel = vel.move_toward(away * max_speed, accel * delta)
	_update_rotation_toward(npc, away, delta)
	_apply_velocity(npc, px, py, pz, vel, delta, max_speed)


static func _try_fire(npc: Dictionary, px: float, py: float, pz: float, dir_to_target: Vector3, dist: float, target_pid: int, delta: float, ship_data: ShipData) -> void:
	if dist > ENGAGEMENT_RANGE:
		return

	var cooldown: float = npc.get("_fire_cd", 0.0) - delta
	if cooldown > 0.0:
		npc["_fire_cd"] = cooldown
		return

	var ry_rad: float = deg_to_rad(npc.get("ry", 0.0))
	var facing := Vector3(-sin(ry_rad), 0.0, -cos(ry_rad))
	var dot: float = facing.dot(dir_to_target)
	if dot < FIRE_CONE_COS:
		return

	var dps: float = ship_data.lod_combat_dps if ship_data else 15.0
	var damage_per_shot: float = dps * 0.5
	npc["_fire_cd"] = 0.5

	npc["_pending_fire"] = {
		"npc_id": npc.get("nid", ""),
		"target_pid": target_pid,
		"pos": [px, py, pz],
		"dir": [facing.x, facing.y, facing.z],
		"damage": damage_per_shot,
		"dist": dist,
	}


## Apply velocity to NPC position using float64 arithmetic.
## Velocity is Vector3 (float32) but deltas are small, so precision is fine.
## Positions are stored as float64 in the dictionary.
static func _apply_velocity(npc: Dictionary, px: float, py: float, pz: float, vel: Vector3, delta: float, speed_limit: float) -> void:
	if vel.length() > speed_limit:
		vel = vel.normalized() * speed_limit
	# Apply velocity delta in float64
	npc["px"] = px + float(vel.x) * delta
	npc["py"] = py + float(vel.y) * delta
	npc["pz"] = pz + float(vel.z) * delta
	npc["vx"] = vel.x
	npc["vy"] = vel.y
	npc["vz"] = vel.z


static func _update_rotation_toward(npc: Dictionary, dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	var target_yaw: float = rad_to_deg(atan2(-dir.x, -dir.z))
	var current_yaw: float = npc.get("ry", 0.0)
	var diff: float = fmod(target_yaw - current_yaw + 540.0, 360.0) - 180.0
	var max_turn: float = rad_to_deg(TURN_RATE) * delta
	npc["ry"] = current_yaw + clampf(diff, -max_turn, max_turn)
