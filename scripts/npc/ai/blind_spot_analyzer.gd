class_name BlindSpotAnalyzer

# =============================================================================
# Blind Spot Analyzer — Pure static utility (no Node, no state).
# Reads ship_data.hardpoints from the target to find fire cone gaps.
# Called by CombatBehavior to bias orbit direction toward blind spots.
# ZERO hardcoded values: adapts dynamically to any hardpoint configuration.
# =============================================================================

const _FIXED_HALF_ANGLE: float = 0.5  # cos(60°) — effective danger cone for fixed weapons


static func analyze(target: Node3D, attacker_pos: Vector3) -> Dictionary:
	var no_pref := {"orbit_side": 0.0, "vertical_bias": 0.0, "threat_level": 0.5}

	if target == null or not is_instance_valid(target):
		return no_pref

	var hardpoints: Array = _get_hardpoints(target)
	if hardpoints.is_empty():
		return no_pref

	# Attacker position in target's local space
	var inv_basis: Basis = target.global_transform.basis.inverse()
	var local_pos: Vector3 = inv_basis * (attacker_pos - target.global_position)

	# Current threat
	var threat: float = _calc_threat(hardpoints, local_pos)

	# --- Orbit side sampling (±25° in target's local XZ plane) ---
	var dist_xz: float = Vector2(local_pos.x, local_pos.z).length()
	if dist_xz < 1.0:
		# Too close to axis — no meaningful angle
		return {"orbit_side": 0.0, "vertical_bias": 0.0, "threat_level": threat}

	var current_angle: float = atan2(local_pos.x, local_pos.z)
	var sample_offset: float = deg_to_rad(25.0)
	var sample_dist: float = local_pos.length()

	# CW sample (positive angle offset)
	var angle_cw: float = current_angle + sample_offset
	var pos_cw := Vector3(sin(angle_cw) * dist_xz, local_pos.y, cos(angle_cw) * dist_xz).normalized() * sample_dist
	var threat_cw: float = _calc_threat(hardpoints, pos_cw)

	# CCW sample (negative angle offset)
	var angle_ccw: float = current_angle - sample_offset
	var pos_ccw := Vector3(sin(angle_ccw) * dist_xz, local_pos.y, cos(angle_ccw) * dist_xz).normalized() * sample_dist
	var threat_ccw: float = _calc_threat(hardpoints, pos_ccw)

	var orbit_side: float = 0.0
	if threat_cw < threat_ccw - 0.05:
		orbit_side = 1.0   # Orbit right (CW in local space)
	elif threat_ccw < threat_cw - 0.05:
		orbit_side = -1.0  # Orbit left (CCW in local space)

	# --- Vertical bias sampling (±15°) ---
	var vert_offset: float = deg_to_rad(15.0)
	var dist_3d: float = sample_dist

	# Upward sample
	var pitch_current: float = atan2(local_pos.y, dist_xz)
	var pitch_up: float = pitch_current + vert_offset
	var pos_up := Vector3(
		sin(current_angle) * cos(pitch_up) * dist_3d,
		sin(pitch_up) * dist_3d,
		cos(current_angle) * cos(pitch_up) * dist_3d)
	var threat_up: float = _calc_threat(hardpoints, pos_up)

	# Downward sample
	var pitch_down: float = pitch_current - vert_offset
	var pos_down := Vector3(
		sin(current_angle) * cos(pitch_down) * dist_3d,
		sin(pitch_down) * dist_3d,
		cos(current_angle) * cos(pitch_down) * dist_3d)
	var threat_down: float = _calc_threat(hardpoints, pos_down)

	var vertical_bias: float = 0.0
	if threat_up < threat_down - 0.05:
		vertical_bias = 1.0   # Prefer going up
	elif threat_down < threat_up - 0.05:
		vertical_bias = -1.0  # Prefer going down

	return {"orbit_side": orbit_side, "vertical_bias": vertical_bias, "threat_level": threat}


# =============================================================================
# INTERNALS
# =============================================================================

static func _get_hardpoints(target: Node3D) -> Array:
	# Case 1: ShipController — has ship_data directly
	if "ship_data" in target and target.ship_data != null:
		return target.ship_data.hardpoints
	# Case 2: RemoteNPCShip / RemotePlayerShip — has ship_id, look up from registry
	if "ship_id" in target:
		var data: ShipData = ShipRegistry.get_ship_data(target.ship_id)
		if data:
			return data.hardpoints
	return []


static func _calc_threat(hardpoints: Array, local_pos: Vector3) -> float:
	if hardpoints.is_empty():
		return 0.5
	var count: int = 0
	for hp: Dictionary in hardpoints:
		if _is_in_fire_cone(hp, local_pos):
			count += 1
	return float(count) / float(hardpoints.size())


static func _is_in_fire_cone(hp: Dictionary, local_pos: Vector3) -> bool:
	var hp_pos: Vector3 = hp.get("position", Vector3.ZERO)
	var to_test: Vector3 = (local_pos - hp_pos).normalized()
	var hp_dir: Vector3 = hp.get("direction", Vector3(0, 0, -1))

	if hp.get("is_turret", false):
		# Turret: check yaw arc + pitch limits
		var angle: float = acos(clampf(hp_dir.dot(to_test), -1.0, 1.0))
		var half_arc: float = deg_to_rad(hp.get("turret_arc_degrees", 180.0) * 0.5)
		if angle > half_arc:
			return false
		# Check pitch relative to turret's local horizontal plane
		# Project to_test onto the plane defined by hp_dir and UP to get pitch
		var pitch: float = rad_to_deg(asin(clampf(to_test.y, -1.0, 1.0)))
		if pitch < hp.get("turret_pitch_min", -45.0) or pitch > hp.get("turret_pitch_max", 45.0):
			return false
		return true
	else:
		# Fixed weapon: ~60° effective danger cone
		return hp_dir.dot(to_test) > _FIXED_HALF_ANGLE
