class_name WeaponManager
extends Node

# =============================================================================
# Weapon Manager - Manages all hardpoints and weapon groups on a ship
# =============================================================================

signal weapon_fired(hardpoint_id: int, weapon_name: StringName)
signal loadout_changed()
signal hit_landed(hit_type: int, damage_amount: float, shield_ratio: float)

enum HitType { SHIELD, HULL, KILL, SHIELD_BREAK }

var hardpoints: Array[Hardpoint] = []
# 3 weapon groups, each is an array of hardpoint indices
var weapon_groups: Array[Array] = [[], [], []]
var _weapon_audio: WeaponAudio = null
var _ship: RigidBody3D = null
var _fire_index: Dictionary = {}  # group_id -> int, for sequential firing


## Creates hardpoints from config dictionaries (extracted from HardpointSlot nodes in ship scenes).
func setup_hardpoints_from_configs(configs: Array[Dictionary], ship_node: RigidBody3D) -> void:
	_ship = ship_node

	# Create weapon audio
	_weapon_audio = WeaponAudio.new()
	_weapon_audio.name = "WeaponAudio"
	add_child(_weapon_audio)

	_create_hardpoints_from_configs(configs, ship_node)


func _create_hardpoints_from_configs(configs: Array[Dictionary], ship_node: RigidBody3D) -> void:
	for cfg in configs:
		var hp := Hardpoint.new()
		hp.setup_from_config(cfg)
		ship_node.add_child(hp)
		hardpoints.append(hp)

	# Default: all hardpoints in group 0
	for i in hardpoints.size():
		weapon_groups[0].append(i)

	_fire_index = {0: 0, 1: 0, 2: 0}


func equip_weapons(weapon_names: Array[StringName]) -> void:
	for i in mini(weapon_names.size(), hardpoints.size()):
		var weapon := WeaponRegistry.get_weapon(weapon_names[i])
		if weapon:
			hardpoints[i].mount_weapon(weapon)


func toggle_hardpoint(index: int) -> void:
	if index >= 0 and index < hardpoints.size():
		hardpoints[index].toggle()
		loadout_changed.emit()


func get_hardpoint_count() -> int:
	return hardpoints.size()


func get_hardpoint_status(index: int) -> Dictionary:
	if index < 0 or index >= hardpoints.size():
		return {}
	var hp := hardpoints[index]
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
	var result := {}
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
			var hp := hardpoints[hp_idx]
			if hp.enabled and hp.mounted_weapon and hp.get_cooldown_ratio() == 0.0:
				return true
	return false


func fire_group(group_index: int, sequential: bool, target_pos: Vector3) -> void:
	if group_index < 0 or group_index >= weapon_groups.size():
		return
	var group: Array = weapon_groups[group_index]
	if group.is_empty():
		return

	var ship_vel: Vector3 = _ship.linear_velocity if _ship else Vector3.ZERO

	# Update turret aim direction for all turrets in this group
	for hp_idx in group:
		if hp_idx < hardpoints.size() and hardpoints[hp_idx].is_turret:
			var aim_dir := (target_pos - hardpoints[hp_idx].global_position).normalized()
			hardpoints[hp_idx].set_target_direction(aim_dir)

	if sequential:
		# Fire one hardpoint at a time, cycling through (skip disabled + mining lasers)
		var attempts := 0
		while attempts < group.size():
			var idx: int = _fire_index.get(group_index, 0) % group.size()
			_fire_index[group_index] = idx + 1
			var hp_idx: int = group[idx]
			if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled:
				# Skip mining lasers — handled by MiningSystem
				if hardpoints[hp_idx].mounted_weapon and hardpoints[hp_idx].mounted_weapon.weapon_type == WeaponResource.WeaponType.MINING_LASER:
					attempts += 1
					continue
				var bolt := hardpoints[hp_idx].try_fire(target_pos, ship_vel)
				if bolt:
					weapon_fired.emit(hp_idx, hardpoints[hp_idx].mounted_weapon.weapon_name if hardpoints[hp_idx].mounted_weapon else &"")
					if _weapon_audio:
						_weapon_audio.play_fire(hardpoints[hp_idx].global_position)
					return
			attempts += 1
	else:
		# Fire all hardpoints in group simultaneously (skip disabled + mining lasers)
		for hp_idx in group:
			if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled:
				# Skip mining lasers — handled by MiningSystem
				if hardpoints[hp_idx].mounted_weapon and hardpoints[hp_idx].mounted_weapon.weapon_type == WeaponResource.WeaponType.MINING_LASER:
					continue
				var bolt := hardpoints[hp_idx].try_fire(target_pos, ship_vel)
				if bolt:
					weapon_fired.emit(hp_idx, hardpoints[hp_idx].mounted_weapon.weapon_name if hardpoints[hp_idx].mounted_weapon else &"")
					if _weapon_audio:
						_weapon_audio.play_fire(hardpoints[hp_idx].global_position)


func update_cooldowns(_delta: float) -> void:
	# Hardpoint cooldowns are handled in Hardpoint._process()
	pass


func swap_weapon(hardpoint_index: int, weapon_name: StringName) -> StringName:
	if hardpoint_index < 0 or hardpoint_index >= hardpoints.size():
		return &""
	var hp := hardpoints[hardpoint_index]
	var old_name: StringName = hp.mounted_weapon.weapon_name if hp.mounted_weapon else &""
	var new_weapon := WeaponRegistry.get_weapon(weapon_name)
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
	var hp := hardpoints[hardpoint_index]
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


func has_combat_weapons_in_group(group_index: int) -> bool:
	if group_index < 0 or group_index >= weapon_groups.size():
		return false
	for hp_idx in weapon_groups[group_index]:
		if hp_idx < hardpoints.size() and hardpoints[hp_idx].enabled and hardpoints[hp_idx].mounted_weapon:
			if hardpoints[hp_idx].mounted_weapon.weapon_type != WeaponResource.WeaponType.MINING_LASER:
				return true
	return false
