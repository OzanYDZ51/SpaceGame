class_name WeaponManager
extends Node

# =============================================================================
# Weapon Manager - Manages all hardpoints and weapon groups on a ship
# =============================================================================

signal weapon_fired(hardpoint_id: int, weapon_name: StringName)
signal loadout_changed()
signal hit_landed(hit_type: int, damage_amount: float, shield_ratio: float)

enum HitType { SHIELD, HULL, KILL, SHIELD_BREAK }

# LOS mask: ships + stations + asteroids (same as AICombat)
const _LOS_MASK: int = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS

var hardpoints: Array[Hardpoint] = []
# 3 weapon groups, each is an array of hardpoint indices
var weapon_groups: Array[Array] = [[], [], []]
var _weapon_audio: WeaponAudio = null
var _ship: Node3D = null
var _fire_index: Dictionary = {}  # group_id -> int, for sequential firing

# Stations: all mounted weapons auto-track as turrets (set by StationFactory)
var all_weapons_are_turrets: bool = false

# --- Acceleration tracking for lead prediction ---
var _prev_target_vel: Vector3 = Vector3.ZERO
var _target_accel: Vector3 = Vector3.ZERO
var _has_prev_vel: bool = false
var _prev_turret_target: Variant = null

# Module multipliers (set by EquipmentManager)
var weapon_energy_mult: float = 1.0
var weapon_range_mult: float = 1.0


## Creates hardpoints from config dictionaries (extracted from HardpointSlot nodes in ship scenes).
## hardpoint_parent: Node3D to parent hardpoints under (e.g. HardpointRoot). Falls back to ship_node.
func setup_hardpoints_from_configs(configs: Array[Dictionary], ship_node: Node3D, hardpoint_parent: Node3D = null) -> void:
	_ship = ship_node

	# Create weapon audio
	_weapon_audio = WeaponAudio.new()
	_weapon_audio.name = "WeaponAudio"
	add_child(_weapon_audio)

	var parent: Node3D = hardpoint_parent if hardpoint_parent else ship_node
	_create_hardpoints_from_configs(configs, parent)


func _create_hardpoints_from_configs(configs: Array[Dictionary], parent: Node3D) -> void:
	for cfg in configs:
		var hp =Hardpoint.new()
		hp.setup_from_config(cfg)
		parent.add_child(hp)
		hardpoints.append(hp)

	# Default: all hardpoints in group 0
	for i in hardpoints.size():
		weapon_groups[0].append(i)

	_fire_index = {0: 0, 1: 0, 2: 0}


func equip_weapons(weapon_names: Array[StringName]) -> void:
	if hardpoints.is_empty() and not weapon_names.is_empty():
		push_warning("WeaponManager.equip_weapons: hardpoints is EMPTY but %d weapons requested!" % weapon_names.size())
	for i in mini(weapon_names.size(), hardpoints.size()):
		if weapon_names[i] == &"":
			hardpoints[i].unmount_weapon()
		else:
			var weapon = WeaponRegistry.get_weapon(weapon_names[i])
			if weapon == null:
				push_warning("WeaponManager.equip_weapons[%d]: weapon '%s' NOT FOUND in registry" % [i, weapon_names[i]])
			elif not hardpoints[i].mount_weapon(weapon):
				push_warning("WeaponManager.equip_weapons[%d]: mount_weapon FAILED for '%s' (slot=%s turret=%s)" % [i, weapon_names[i], hardpoints[i].slot_size, hardpoints[i].is_turret])
	_recalculate_groups()


func toggle_hardpoint(index: int) -> void:
	if index >= 0 and index < hardpoints.size():
		hardpoints[index].toggle()
		loadout_changed.emit()


func get_hardpoint_count() -> int:
	return hardpoints.size()


func get_hardpoint_status(index: int) -> Dictionary:
	if index < 0 or index >= hardpoints.size():
		return {}
	var hp =hardpoints[index]
	var wname: StringName = &""
	var wtype: int = -1
	if hp.mounted_weapon:
		wname = hp.mounted_weapon.weapon_name
		wtype = hp.mounted_weapon.weapon_type
	# Determine which fire group(s) this hardpoint belongs to
	var fire_grp: int = -1
	for g in weapon_groups.size():
		if index in weapon_groups[g]:
			fire_grp = g
			break
	var result ={}
	result["weapon_name"] = wname
	result["weapon_type"] = wtype
	result["slot_size"] = hp.slot_size
	result["enabled"] = hp.enabled
	result["cooldown_ratio"] = hp.get_cooldown_ratio()
	result["fire_group"] = fire_grp
	return result


func is_any_weapon_ready(group_index: int) -> bool:
	if group_index < 0 or group_index >= weapon_groups.size():
		return false
	for hp_idx in weapon_groups[group_index]:
		if hp_idx < hardpoints.size():
			var hp =hardpoints[hp_idx]
			if hp.enabled and hp.mounted_weapon and hp.get_cooldown_ratio() == 0.0:
				return true
	return false


func fire_group(group_index: int, sequential: bool, target_pos: Vector3) -> void:
	if group_index < 0 or group_index >= weapon_groups.size():
		return
	var group: Array = weapon_groups[group_index]
	if group.is_empty():
		return

	var ship_vel: Vector3 = (_ship as RigidBody3D).linear_velocity if _ship is RigidBody3D else Vector3.ZERO

	if sequential:
		# Fire one hardpoint at a time, cycling through (skip disabled, mining lasers, turrets)
		var attempts =0
		while attempts < group.size():
			var idx: int = _fire_index.get(group_index, 0) % group.size()
			_fire_index[group_index] = idx + 1
			var hp_idx: int = group[idx]
			if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled:
				if hardpoints[hp_idx].mounted_weapon:
					var wtype: int = hardpoints[hp_idx].mounted_weapon.weapon_type
					# Skip mining lasers (MiningSystem) and turrets (update_turrets)
					if wtype == WeaponResource.WeaponType.MINING_LASER or wtype == WeaponResource.WeaponType.TURRET:
						attempts += 1
						continue
				var bolt = hardpoints[hp_idx].try_fire(target_pos, ship_vel)
				if bolt:
					weapon_fired.emit(hp_idx, hardpoints[hp_idx].mounted_weapon.weapon_name if hardpoints[hp_idx].mounted_weapon else &"")
					if _weapon_audio:
						_weapon_audio.play_fire(hardpoints[hp_idx].global_position)
					return
			attempts += 1
	else:
		# Fire all hardpoints in group simultaneously (skip disabled, mining lasers, turrets)
		for hp_idx in group:
			if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled:
				if hardpoints[hp_idx].mounted_weapon:
					var wtype: int = hardpoints[hp_idx].mounted_weapon.weapon_type
					if wtype == WeaponResource.WeaponType.MINING_LASER or wtype == WeaponResource.WeaponType.TURRET:
						continue
				var bolt = hardpoints[hp_idx].try_fire(target_pos, ship_vel)
				if bolt:
					weapon_fired.emit(hp_idx, hardpoints[hp_idx].mounted_weapon.weapon_name if hardpoints[hp_idx].mounted_weapon else &"")
					if _weapon_audio:
						_weapon_audio.play_fire(hardpoints[hp_idx].global_position)


func update_cooldowns(_delta: float) -> void:
	# Hardpoint cooldowns are handled in Hardpoint._process()
	pass


## Call every frame to keep turrets tracking + auto-firing at the current target.
## When target is null, turrets smoothly return to their rest (forward) orientation.
func update_turrets(target_node: Variant = null) -> void:
	if target_node != null and not is_instance_valid(target_node):
		target_node = null
	if target_node == null:
		# No target: return all turrets to forward rest position + reset tracking
		_has_prev_vel = false
		_target_accel = Vector3.ZERO
		_prev_turret_target = null
		for hp in hardpoints:
			if hp.is_turret and hp.enabled and hp.mounted_weapon != null:
				hp.clear_target_direction()
		return

	# Reset acceleration tracking when target changes
	if target_node != _prev_turret_target:
		_has_prev_vel = false
		_target_accel = Vector3.ZERO
		_prev_turret_target = target_node

	var target_pos: Vector3 = TargetingSystem.get_ship_center(target_node)

	var target_vel =Vector3.ZERO
	if target_node is RigidBody3D:
		target_vel = (target_node as RigidBody3D).linear_velocity
	elif "linear_velocity" in target_node:
		target_vel = target_node.linear_velocity
	var ship_vel: Vector3 = (_ship as RigidBody3D).linear_velocity if _ship is RigidBody3D else Vector3.ZERO

	# Track target acceleration for better lead prediction on maneuvering targets
	var delta: float = get_process_delta_time()
	if _has_prev_vel and delta > 0.001:
		var raw_accel: Vector3 = (target_vel - _prev_target_vel) / delta
		# Heavy smoothing: only reacts to sustained acceleration, ignores frame jitter
		_target_accel = _target_accel.lerp(raw_accel, 0.08)
		if _target_accel.length() > 200.0:
			_target_accel = _target_accel.normalized() * 200.0
	else:
		_has_prev_vel = true
	_prev_target_vel = target_vel

	# LOS check: shared raycast setup (one per frame, not per turret — target is same)
	var los_blocked: bool = false
	var space = _ship.get_world_3d().direct_space_state if _ship else null
	if space:
		var los_query := PhysicsRayQueryParameters3D.create(
			_ship.global_position, target_pos)
		los_query.collision_mask = _LOS_MASK
		los_query.collide_with_areas = false
		var exclude_rids: Array[RID] = []
		if _ship is CollisionObject3D:
			exclude_rids.append(_ship.get_rid())
		if target_node is CollisionObject3D:
			exclude_rids.append((target_node as CollisionObject3D).get_rid())
		else:
			var hit_body = target_node.get_node_or_null("HitBody")
			if hit_body and hit_body is CollisionObject3D:
				exclude_rids.append(hit_body.get_rid())
		los_query.exclude = exclude_rids
		var los_hit = space.intersect_ray(los_query)
		los_blocked = not los_hit.is_empty()

	for hp in hardpoints:
		if not hp.is_turret or not hp.enabled or hp.mounted_weapon == null:
			continue
		# Stations: all weapons auto-track. Ships: only TURRET-type weapons.
		if not all_weapons_are_turrets and hp.mounted_weapon.weapon_type != WeaponResource.WeaponType.TURRET:
			continue

		# Acceleration-aware lead prediction per turret
		var lead_pos =_solve_turret_lead(hp.global_position, ship_vel, target_pos, target_vel, hp.mounted_weapon.projectile_speed, _target_accel)

		# Update aim direction (keep tracking even when LOS blocked)
		var aim_dir =(lead_pos - hp.global_position).normalized()
		hp.set_target_direction(aim_dir)

		# Don't fire if LOS blocked by a structure/asteroid
		if los_blocked:
			continue

		# Auto-fire when aligned
		var bolt = hp.try_fire(lead_pos, ship_vel)
		if bolt:
			weapon_fired.emit(hp.slot_id, hp.mounted_weapon.weapon_name)
			if _weapon_audio:
				_weapon_audio.play_fire(hp.global_position)


## Intercept prediction with optional acceleration correction.
## Solves the standard quadratic for time-of-flight, then applies acceleration
## to predict where a maneuvering target will actually be (curved trajectory).
static func _solve_turret_lead(turret_pos: Vector3, ship_vel: Vector3, target_pos: Vector3, target_vel: Vector3, projectile_speed: float, target_accel: Vector3 = Vector3.ZERO) -> Vector3:
	var rel_pos: Vector3 = target_pos - turret_pos
	var rel_vel: Vector3 = target_vel - ship_vel

	# Solve |rel_pos + rel_vel * t|² = (projectile_speed * t)²
	var a: float = rel_vel.dot(rel_vel) - projectile_speed * projectile_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.dot(rel_pos)

	var tof: float = 0.0
	var discriminant: float = b * b - 4.0 * a * c

	if absf(a) < 0.001:
		if absf(b) > 0.001:
			tof = -c / b
	elif discriminant >= 0.0:
		var sqrt_d: float = sqrt(discriminant)
		var t1: float = (-b - sqrt_d) / (2.0 * a)
		var t2: float = (-b + sqrt_d) / (2.0 * a)
		if t1 > 0.01 and t2 > 0.01:
			tof = minf(t1, t2)
		elif t1 > 0.01:
			tof = t1
		elif t2 > 0.01:
			tof = t2

	tof = clampf(tof, 0.0, 5.0)
	# Apply acceleration correction: predict curved trajectory instead of straight line
	return target_pos + target_vel * tof + 0.5 * target_accel * tof * tof


func swap_weapon(hardpoint_index: int, weapon_name: StringName) -> StringName:
	if hardpoint_index < 0 or hardpoint_index >= hardpoints.size():
		return &""
	var hp =hardpoints[hardpoint_index]
	var old_name: StringName = hp.mounted_weapon.weapon_name if hp.mounted_weapon else &""
	var new_weapon =WeaponRegistry.get_weapon(weapon_name)
	if new_weapon == null:
		return old_name
	hp.unmount_weapon()
	hp.mount_weapon(new_weapon)
	_recalculate_groups()
	loadout_changed.emit()
	return old_name


func remove_weapon(hardpoint_index: int) -> StringName:
	if hardpoint_index < 0 or hardpoint_index >= hardpoints.size():
		return &""
	var hp =hardpoints[hardpoint_index]
	var old_name: StringName = hp.mounted_weapon.weapon_name if hp.mounted_weapon else &""
	hp.unmount_weapon()
	_recalculate_groups()
	loadout_changed.emit()
	return old_name


func _recalculate_groups() -> void:
	for g in weapon_groups.size():
		weapon_groups[g] = []
	for i in hardpoints.size():
		if hardpoints[i].mounted_weapon == null:
			continue
		var wtype: int = hardpoints[i].mounted_weapon.weapon_type
		# TURRET weapons go to group 1 (with missiles)
		if wtype == WeaponResource.WeaponType.TURRET:
			weapon_groups[1].append(i)
			continue
		# MISSILE goes to group 1
		if wtype == WeaponResource.WeaponType.MISSILE:
			weapon_groups[1].append(i)
			continue
		# RAILGUN and MINE go to group 2
		if wtype == WeaponResource.WeaponType.RAILGUN or wtype == WeaponResource.WeaponType.MINE:
			weapon_groups[2].append(i)
			continue
		# LASER, PLASMA go to group 0
		weapon_groups[0].append(i)
	# Fallback: if group 0 empty, copy group 1 so primary fire still works
	if weapon_groups[0].is_empty() and not weapon_groups[1].is_empty():
		weapon_groups[0] = weapon_groups[1].duplicate()
	_fire_index = {0: 0, 1: 0, 2: 0}


func _on_projectile_hit(hit_info: Dictionary, damage_amount: float, killed: bool) -> void:
	if killed:
		hit_landed.emit(HitType.KILL, damage_amount, 0.0)
	elif hit_info.get("shield_absorbed", false):
		var sr: float = hit_info.get("shield_ratio", 1.0)
		if sr <= 0.0:
			hit_landed.emit(HitType.SHIELD_BREAK, damage_amount, 0.0)
		else:
			hit_landed.emit(HitType.SHIELD, damage_amount, sr)
	else:
		hit_landed.emit(HitType.HULL, damage_amount, 0.0)


func set_weapon_group(group_index: int, hardpoint_indices: Array) -> void:
	if group_index >= 0 and group_index < weapon_groups.size():
		weapon_groups[group_index] = hardpoint_indices


func get_mining_hardpoints_in_group(group_index: int) -> Array[Hardpoint]:
	var result: Array[Hardpoint] = []
	if group_index < 0 or group_index >= weapon_groups.size():
		return result
	for hp_idx in weapon_groups[group_index]:
		if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled:
			if hardpoints[hp_idx].mounted_weapon and hardpoints[hp_idx].mounted_weapon.weapon_type == WeaponResource.WeaponType.MINING_LASER:
				result.append(hardpoints[hp_idx])
	return result


func apply_module_multipliers(energy_mult: float, range_mult: float) -> void:
	weapon_energy_mult = energy_mult
	weapon_range_mult = range_mult
	for hp in hardpoints:
		hp.energy_cost_mult = energy_mult
		hp.range_mult = range_mult


func has_combat_weapons_in_group(group_index: int) -> bool:
	if group_index < 0 or group_index >= weapon_groups.size():
		return false
	for hp_idx in weapon_groups[group_index]:
		if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled and hardpoints[hp_idx].mounted_weapon:
			if hardpoints[hp_idx].mounted_weapon.weapon_type != WeaponResource.WeaponType.MINING_LASER:
				return true
	return false
