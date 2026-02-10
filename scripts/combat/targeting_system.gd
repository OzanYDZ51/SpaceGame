class_name TargetingSystem
extends Node

# =============================================================================
# Targeting System - Lock-on, target cycling, lead indicator
# =============================================================================

signal target_changed(new_target: Node3D)
signal target_lost()

var current_target: Node3D = null
var target_lock_range: float = 5000.0

var _targetable_ships: Array[Node3D] = []
var _scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.5
var _current_target_index: int = -1
var _cached_target_health: HealthSystem = null
var _cached_target_ref: Node3D = null  # tracks which target the cached health belongs to


func _process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_gather_targetable_ships()

	# Check if target still valid
	if current_target != null:
		if not is_instance_valid(current_target) or not current_target.is_inside_tree():
			clear_target()
			return
		# Check if target has a health system and is dead (cached)
		if _cached_target_ref != current_target:
			_cached_target_ref = current_target
			_cached_target_health = current_target.get_node_or_null("HealthSystem") as HealthSystem
		if _cached_target_health and _cached_target_health.is_dead():
			clear_target()
			return
		# Also check StructureHealth (stations)
		if _cached_target_health == null:
			var sh := current_target.get_node_or_null("StructureHealth") as StructureHealth
			if sh and sh.is_dead():
				clear_target()
				return
		# Check range
		var ship := get_parent() as Node3D
		if ship and ship.global_position.distance_to(current_target.global_position) > target_lock_range * 1.5:
			clear_target()


func cycle_target_forward() -> void:
	if _targetable_ships.is_empty():
		clear_target()
		return
	_current_target_index = (_current_target_index + 1) % _targetable_ships.size()
	_set_target(_targetable_ships[_current_target_index])


func target_nearest_hostile() -> void:
	target_nearest_to_crosshair()


func target_nearest_to_crosshair() -> void:
	var ship := get_parent() as Node3D
	if ship == null:
		return
	var cam := ship.get_viewport().get_camera_3d()
	if cam == null:
		return

	var screen_center := ship.get_viewport().get_visible_rect().size / 2.0
	var nearest: Node3D = null
	var nearest_angle: float = INF

	for t in _targetable_ships:
		if not is_instance_valid(t) or not t.is_inside_tree():
			continue
		# Check if target is in front of camera
		var to_target: Vector3 = t.global_position - cam.global_position
		var cam_fwd: Vector3 = -cam.global_transform.basis.z
		if to_target.dot(cam_fwd) <= 0.0:
			continue  # Behind camera

		# Project to screen and measure distance from crosshair center
		var screen_pos := cam.unproject_position(t.global_position)
		var dist_to_center: float = screen_pos.distance_to(screen_center)

		if dist_to_center < nearest_angle:
			nearest_angle = dist_to_center
			nearest = t

	if nearest:
		_set_target(nearest)
		_current_target_index = _targetable_ships.find(nearest)


func clear_target() -> void:
	if current_target != null:
		current_target = null
		_current_target_index = -1
		_cached_target_ref = null
		_cached_target_health = null
		target_lost.emit()


func get_lead_indicator_position() -> Vector3:
	if current_target == null or not is_instance_valid(current_target):
		var parent_ship := get_parent() as Node3D
		if parent_ship:
			return parent_ship.global_position + parent_ship.global_transform.basis * Vector3.FORWARD * 1000.0
		return Vector3.ZERO

	var ship := get_parent() as RigidBody3D
	if ship == null:
		return _get_target_center()

	# Get weapon speed (use first mounted weapon or default)
	var projectile_speed := 800.0
	var wm := ship.get_node_or_null("WeaponManager") as WeaponManager  # Called rarely (only when target exists)
	if wm and not wm.hardpoints.is_empty() and wm.hardpoints[0].mounted_weapon:
		projectile_speed = wm.hardpoints[0].mounted_weapon.projectile_speed

	var target_pos: Vector3 = _get_target_center()
	var target_vel := Vector3.ZERO
	if current_target is RigidBody3D:
		target_vel = (current_target as RigidBody3D).linear_velocity

	var my_vel: Vector3 = ship.linear_velocity

	# Relative velocity: how the target moves relative to shooter
	# Projectile velocity = fire_dir * projectile_speed + my_vel
	# So in the target's reference frame, projectile moves at projectile_speed
	# and target moves at (target_vel - my_vel)
	var rel_vel: Vector3 = target_vel - my_vel
	var rel_pos: Vector3 = target_pos - ship.global_position

	# Solve quadratic: |rel_pos + rel_vel * t|^2 = (projectile_speed * t)^2
	var a: float = rel_vel.dot(rel_vel) - projectile_speed * projectile_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.dot(rel_pos)

	var tof: float = 0.0
	var discriminant: float = b * b - 4.0 * a * c

	if abs(a) < 0.001:
		# Linear case: projectile_speed ~= relative speed
		if abs(b) > 0.001:
			tof = -c / b
	elif discriminant >= 0.0:
		var sqrt_d: float = sqrt(discriminant)
		var t1: float = (-b - sqrt_d) / (2.0 * a)
		var t2: float = (-b + sqrt_d) / (2.0 * a)
		# Pick smallest positive solution
		if t1 > 0.01 and t2 > 0.01:
			tof = minf(t1, t2)
		elif t1 > 0.01:
			tof = t1
		elif t2 > 0.01:
			tof = t2

	tof = clampf(tof, 0.0, 5.0)  # Cap at 5 seconds
	return target_pos + target_vel * tof


func get_target_distance() -> float:
	if current_target == null or not is_instance_valid(current_target):
		return -1.0
	var ship := get_parent() as Node3D
	if ship == null:
		return -1.0
	return ship.global_position.distance_to(_get_target_center())


## Returns the visual center of the current target (using ShipCenter offset if available)
func _get_target_center() -> Vector3:
	return get_ship_center(current_target)


## Returns the visual center of any ship node (ShipController, RemoteNPCShip, RemotePlayerShip)
static func get_ship_center(node: Node3D) -> Vector3:
	# Only ShipController uses center_offset: its model is scene-based (skip_centering)
	# so the visual center differs from the node origin.
	# Remote ships (RemotePlayerShip, RemoteNPCShip) load from .glb and auto-center
	# the AABB at origin, so their visual center is already at global_position.
	if node is ShipController:
		var offset: Vector3 = (node as ShipController).center_offset
		if offset != Vector3.ZERO:
			return node.global_position + node.global_transform.basis * offset
	return node.global_position


func _set_target(new_target: Node3D) -> void:
	current_target = new_target
	target_changed.emit(new_target)


func _gather_targetable_ships() -> void:
	_targetable_ships.clear()
	var ship := get_parent() as Node3D
	if ship == null:
		return

	# Determine own faction for friendly-fire prevention
	var own_faction: StringName = ship.faction if "faction" in ship else &"neutral"

	# Use spatial grid via LOD manager if available (O(k) instead of O(n))
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr:
		var self_id := StringName(ship.name)
		var results := lod_mgr.get_nearest_ships(ship.global_position, target_lock_range, 50, self_id)
		for entry in results:
			var data := lod_mgr.get_ship_data(entry["id"])
			if data == null or data.is_dead:
				continue
			# Skip allied fleet ships (player can't target own fleet)
			if _is_allied(own_faction, data.faction):
				continue
			# Only target ships with a scene node (LOD0/LOD1), never self
			if data.node_ref and is_instance_valid(data.node_ref) and data.node_ref != ship:
				_targetable_ships.append(data.node_ref)
	else:
		# Legacy fallback: scan group
		var all_ships := get_tree().get_nodes_in_group("ships")
		for node in all_ships:
			if node == ship:
				continue
			if node is Node3D:
				# Skip allied fleet ships
				var node_faction: StringName = node.faction if "faction" in node else &"neutral"
				if _is_allied(own_faction, node_faction):
					continue
				var dist: float = ship.global_position.distance_to((node as Node3D).global_position)
				if dist <= target_lock_range:
					var health := node.get_node_or_null("HealthSystem") as HealthSystem
					if health and health.is_dead():
						continue
					_targetable_ships.append(node as Node3D)

	# Also gather targetable structures (stations)
	var structures := StructureTargetProvider.gather_targetable(ship.global_position, target_lock_range)
	_targetable_ships.append_array(structures)

	# Sort by distance
	_targetable_ships.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return ship.global_position.distance_squared_to(a.global_position) < ship.global_position.distance_squared_to(b.global_position)
	)

	# If current target no longer in list, clear
	if current_target and current_target not in _targetable_ships:
		clear_target()


## Returns true if two factions are allied (should not attack each other).
static func _is_allied(faction_a: StringName, faction_b: StringName) -> bool:
	# Player and player_fleet are allies
	if faction_a == &"neutral" and faction_b == &"player_fleet":
		return true
	if faction_a == &"player_fleet" and faction_b == &"neutral":
		return true
	if faction_a == &"player_fleet" and faction_b == &"player_fleet":
		return true
	# Friendly NPCs are allied with player
	if faction_a == &"neutral" and faction_b == &"friendly":
		return true
	if faction_a == &"friendly" and faction_b == &"neutral":
		return true
	if faction_a == &"player_fleet" and faction_b == &"friendly":
		return true
	if faction_a == &"friendly" and faction_b == &"player_fleet":
		return true
	return false
