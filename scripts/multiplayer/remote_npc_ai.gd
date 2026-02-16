class_name RemoteNpcAI
extends RefCounted

# =============================================================================
# Remote NPC AI — Headless data-only simulation for NPCs in systems where the
# server has no scene nodes loaded. Pure math on NPC state dictionaries.
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
	var npc_pos := Vector3(npc.get("px", 0.0), npc.get("py", 0.0), npc.get("pz", 0.0))
	var npc_vel := Vector3(npc.get("vx", 0.0), npc.get("vy", 0.0), npc.get("vz", 0.0))
	var faction: String = npc.get("fac", "hostile")

	# Detect nearest hostile peer
	var target_pid: int = -1
	var target_pos := Vector3.ZERO
	var target_dist: float = INF

	for pid in peers_in_system:
		var pstate = peers_in_system[pid]
		if pstate.is_docked or pstate.is_dead:
			continue
		# Don't attack same faction
		if faction == "neutral":
			continue
		var pp := Vector3(pstate.pos_x, pstate.pos_y, pstate.pos_z)
		var d: float = npc_pos.distance_to(pp)
		if d < target_dist and d < DETECTION_RANGE:
			target_dist = d
			target_pos = pp
			target_pid = pid

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

	# Execute state behavior
	match state:
		State.PATROL:
			_do_patrol(npc, npc_pos, npc_vel, delta, max_speed)
		State.PURSUE:
			_do_pursue(npc, npc_pos, npc_vel, target_pos, delta, accel, max_speed)
		State.ATTACK:
			_do_attack(npc, npc_pos, npc_vel, target_pos, target_pid, delta, accel, max_speed, ship_data)
		State.EVADE:
			_do_evade(npc, npc_pos, npc_vel, target_pos, delta, accel, max_speed)
		State.FLEE:
			_do_flee(npc, npc_pos, npc_vel, target_pos, delta, accel, max_speed)

	npc["t"] = Time.get_ticks_msec() / 1000.0


static func _do_patrol(npc: Dictionary, pos: Vector3, vel: Vector3, delta: float, max_speed: float) -> void:
	# Circle around patrol center (stored as spawn position if no explicit center)
	var cx: float = npc.get("_patrol_cx", npc.get("px", 0.0))
	var cz: float = npc.get("_patrol_cz", npc.get("pz", 0.0))
	if not npc.has("_patrol_cx"):
		npc["_patrol_cx"] = pos.x
		npc["_patrol_cz"] = pos.z

	var center := Vector3(cx, pos.y, cz)
	var to_center := center - pos
	var dist_from_center: float = to_center.length()

	# If too far from center, steer back
	if dist_from_center > 1500.0:
		var dir: Vector3 = to_center.normalized()
		vel = vel.move_toward(dir * PATROL_SPEED, 40.0 * delta)
	else:
		# Orbit: perpendicular to radial direction
		var radial: Vector3 = to_center.normalized() if dist_from_center > 1.0 else Vector3.FORWARD
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		vel = vel.move_toward(tangent * PATROL_SPEED, 30.0 * delta)

	_apply_velocity(npc, pos, vel, delta, max_speed * 0.3)


static func _do_pursue(npc: Dictionary, pos: Vector3, vel: Vector3, target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	var dir: Vector3 = (target - pos)
	if dir.length_squared() < 1.0:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	vel = vel.move_toward(dir * max_speed * 0.7, accel * delta)
	_update_rotation_toward(npc, dir, delta)
	_apply_velocity(npc, pos, vel, delta, max_speed * 0.7)


static func _do_attack(npc: Dictionary, pos: Vector3, vel: Vector3, target: Vector3, target_pid: int, delta: float, accel: float, max_speed: float, ship_data: ShipData) -> void:
	var to_target: Vector3 = target - pos
	var dist: float = to_target.length()
	var dir: Vector3 = to_target.normalized() if dist > 1.0 else Vector3.FORWARD

	# Maintain optimal combat range: approach if too far, retreat if too close
	var desired_dir: Vector3
	if dist > OPTIMAL_COMBAT_RANGE * 1.3:
		desired_dir = dir
	elif dist < OPTIMAL_COMBAT_RANGE * 0.5:
		desired_dir = -dir
	else:
		# Strafe: orbit around target
		desired_dir = Vector3(-dir.z, 0.0, dir.x)

	vel = vel.move_toward(desired_dir * max_speed * 0.5, accel * delta)
	_update_rotation_toward(npc, dir, delta)
	_apply_velocity(npc, pos, vel, delta, max_speed * 0.6)

	# Try firing
	_try_fire(npc, pos, dir, dist, target_pid, delta, ship_data)


static func _do_evade(npc: Dictionary, pos: Vector3, vel: Vector3, target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	# Move perpendicular to threat
	var away: Vector3 = (pos - target)
	if away.length_squared() < 1.0:
		away = Vector3.FORWARD
	away = away.normalized()
	var evade_dir := Vector3(-away.z, randf_range(-0.3, 0.3), away.x)
	vel = vel.move_toward(evade_dir * max_speed * 0.8, accel * 1.5 * delta)
	_apply_velocity(npc, pos, vel, delta, max_speed * 0.8)


static func _do_flee(npc: Dictionary, pos: Vector3, vel: Vector3, target: Vector3, delta: float, accel: float, max_speed: float) -> void:
	var away: Vector3 = (pos - target)
	if away.length_squared() < 1.0:
		away = Vector3.FORWARD
	away = away.normalized()
	vel = vel.move_toward(away * max_speed, accel * delta)
	_update_rotation_toward(npc, away, delta)
	_apply_velocity(npc, pos, vel, delta, max_speed)


static func _try_fire(npc: Dictionary, pos: Vector3, dir_to_target: Vector3, dist: float, target_pid: int, delta: float, ship_data: ShipData) -> void:
	if dist > ENGAGEMENT_RANGE:
		return

	# Cooldown
	var cooldown: float = npc.get("_fire_cd", 0.0) - delta
	if cooldown > 0.0:
		npc["_fire_cd"] = cooldown
		return

	# Check firing cone (use NPC's current facing direction)
	var ry_rad: float = deg_to_rad(npc.get("ry", 0.0))
	var facing := Vector3(-sin(ry_rad), 0.0, -cos(ry_rad))
	var dot: float = facing.dot(dir_to_target)
	if dot < FIRE_CONE_COS:
		return

	# Fire! Set cooldown based on DPS
	var dps: float = ship_data.lod_combat_dps if ship_data else 15.0
	var damage_per_shot: float = dps * 0.5  # 2 shots/sec equivalent
	npc["_fire_cd"] = 0.5

	# Store pending fire event for NpcAuthority to relay
	npc["_pending_fire"] = {
		"npc_id": npc.get("nid", ""),
		"target_pid": target_pid,
		"pos": [pos.x, pos.y, pos.z],
		"dir": [facing.x, facing.y, facing.z],
		"damage": damage_per_shot,
		"dist": dist,
	}


static func _apply_velocity(npc: Dictionary, pos: Vector3, vel: Vector3, delta: float, speed_limit: float) -> void:
	if vel.length() > speed_limit:
		vel = vel.normalized() * speed_limit
	pos += vel * delta
	npc["px"] = pos.x
	npc["py"] = pos.y
	npc["pz"] = pos.z
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
