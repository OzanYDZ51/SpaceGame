class_name Hardpoint
extends Node3D

# =============================================================================
# Hardpoint - A weapon mount point on a ship
# Manages a single weapon: cooldown, firing, energy consumption.
# Supports turret rotation for TURRET and MISSILE weapon types.
# =============================================================================

signal toggled(hp_id: int, is_enabled: bool)

var slot_id: int = 0
var slot_size: String = "S"  # "S", "M", "L"
var mounted_weapon: WeaponResource = null
var enabled: bool = true

# --- Turret properties ---
var is_turret: bool = false
var turret_arc_degrees: float = 180.0
var turret_speed_deg_s: float = 90.0
var turret_pitch_min: float = -45.0  # Lowest pitch (negative = aim down)
var turret_pitch_max: float = 45.0   # Highest pitch (positive = aim up)
var _turret_pivot: Node3D = null
var _target_direction: Vector3 = Vector3.FORWARD  # Local-space desired aim direction
var _current_yaw: float = 0.0
var _current_pitch: float = 0.0
var _can_fire: bool = true  # Turret aligned within tolerance

# --- Weapon mesh ---
var _weapon_mesh_instance: Node3D = null

# --- Muzzle points (detected from weapon model scene) ---
var _muzzle_points: Array[Node3D] = []
var _muzzle_index: int = 0
var _turret_base: Node3D = null  # Future: static turret base mesh

# --- Internals ---
var _cooldown_timer: float = 0.0
var _projectile_scene: PackedScene = null
var _cached_ship: Node3D = null
var _cached_energy_sys: EnergySystem = null
var _cached_pool: ProjectilePool = null
var _refs_cached: bool = false


func _ready() -> void:
	if is_turret:
		_setup_turret_pivot()
		set_process(true)  # Turrets always process for rotation
	else:
		set_process(false)  # Fixed hardpoints only process during cooldown


func _process(delta: float) -> void:
	if is_turret:
		_update_turret_rotation(delta)

	# Cooldown tick
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0
			if not is_turret:
				set_process(false)


## Legacy setup: creates a hardpoint from code-defined position data.
func setup(id: int, size: String, pos: Vector3, _dir: Vector3) -> void:
	slot_id = id
	slot_size = size
	position = pos
	name = "Hardpoint_%d" % id


## New setup: creates a hardpoint from a config dictionary (from HardpointSlot or converted legacy).
func setup_from_config(cfg: Dictionary) -> void:
	slot_id = cfg.get("id", 0)
	slot_size = cfg.get("size", "S")
	position = cfg.get("position", Vector3.ZERO)
	rotation_degrees = cfg.get("rotation_degrees", Vector3.ZERO)
	is_turret = cfg.get("is_turret", false)
	turret_arc_degrees = cfg.get("turret_arc_degrees", 180.0)
	turret_speed_deg_s = cfg.get("turret_speed_deg_s", 90.0)
	turret_pitch_min = cfg.get("turret_pitch_min", -45.0)
	turret_pitch_max = cfg.get("turret_pitch_max", 45.0)
	name = "Hardpoint_%d" % slot_id

	if is_turret:
		_setup_turret_pivot()
		set_process(true)


func _setup_turret_pivot() -> void:
	_turret_pivot = Node3D.new()
	_turret_pivot.name = "TurretPivot"
	add_child(_turret_pivot)


func mount_weapon(weapon: WeaponResource) -> bool:
	if not can_mount(weapon):
		return false
	# Clean up previous weapon if re-mounting (e.g. save load after factory default)
	if mounted_weapon:
		_remove_weapon_mesh()
		_muzzle_points.clear()
		_muzzle_index = 0
		_turret_base = null
	mounted_weapon = weapon
	if weapon.projectile_scene_path != "":
		_projectile_scene = load(weapon.projectile_scene_path) as PackedScene
		if _projectile_scene == null:
			push_warning("Hardpoint: Could not load projectile scene '%s'" % weapon.projectile_scene_path)

	# Load weapon mesh if defined
	_load_weapon_mesh(weapon)
	return true


func unmount_weapon() -> void:
	mounted_weapon = null
	_projectile_scene = null
	_muzzle_points.clear()
	_muzzle_index = 0
	_turret_base = null
	_remove_weapon_mesh()


func can_mount(weapon: WeaponResource) -> bool:
	if weapon == null:
		return false
	# TURRET weapons can only mount on turret slots
	if weapon.weapon_type == WeaponResource.WeaponType.TURRET and not is_turret:
		return false
	var size_order := {"S": 0, "M": 1, "L": 2}
	var weapon_size_str: String = ["S", "M", "L"][weapon.slot_size]
	return size_order.get(weapon_size_str, 0) <= size_order.get(slot_size, 0)


func toggle() -> void:
	enabled = not enabled
	toggled.emit(slot_id, enabled)


func get_cooldown_ratio() -> float:
	if mounted_weapon == null or mounted_weapon.fire_rate <= 0.0:
		return 0.0
	var cooldown_duration := 1.0 / mounted_weapon.fire_rate
	return clampf(_cooldown_timer / cooldown_duration, 0.0, 1.0)


## Called by WeaponManager to set the desired aim direction (world space).
func set_target_direction(world_dir: Vector3) -> void:
	if not is_turret:
		return
	# Convert world direction to hardpoint local space
	_target_direction = global_transform.basis.inverse() * world_dir


func _update_turret_rotation(delta: float) -> void:
	if _turret_pivot == null:
		return

	# Decompose target direction into yaw and pitch in local space
	var dir := _target_direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD

	# Yaw = rotation around Y axis (horizontal)
	# Negate dir.x: in Godot, positive rotation_degrees.y = CCW from above = turn LEFT
	# So target to the right (dir.x > 0) needs negative yaw
	var raw_yaw := rad_to_deg(atan2(-dir.x, -dir.z))
	# Pitch = rotation around X axis (vertical)
	# Positive dir.y = target above = need positive rotation_degrees.x to tilt up
	var horizontal_dist := sqrt(dir.x * dir.x + dir.z * dir.z)
	var raw_pitch := rad_to_deg(atan2(dir.y, horizontal_dist))

	# Check if target is within arc BEFORE clamping
	var half_arc := turret_arc_degrees * 0.5
	var target_in_arc := absf(raw_yaw) <= half_arc + 5.0 and raw_pitch >= turret_pitch_min - 5.0 and raw_pitch <= turret_pitch_max + 5.0

	# Clamp to arc limits (turret still tracks to edge even if out of arc)
	var clamped_yaw := clampf(raw_yaw, -half_arc, half_arc)
	var clamped_pitch := clampf(raw_pitch, turret_pitch_min, turret_pitch_max)

	# Smooth but fast rotation: move_toward at 2x speed for responsive tracking
	var max_step := turret_speed_deg_s * delta * 2.0
	_current_yaw = move_toward(_current_yaw, clamped_yaw, max_step)
	_current_pitch = move_toward(_current_pitch, clamped_pitch, max_step)

	# Apply rotation to pivot
	_turret_pivot.rotation_degrees = Vector3(_current_pitch, _current_yaw, 0.0)

	# Can fire only if: target is within arc AND turret is aligned to it
	var yaw_error := absf(_current_yaw - clamped_yaw)
	var pitch_error := absf(_current_pitch - clamped_pitch)
	_can_fire = target_in_arc and (yaw_error < 3.0 and pitch_error < 3.0)


func try_fire(target_pos: Vector3, ship_velocity: Vector3) -> BaseProjectile:
	if not enabled:
		return null

	if mounted_weapon == null or _projectile_scene == null:
		return null

	if _cooldown_timer > 0.0:
		return null

	# Turrets refuse to fire if not aligned
	if is_turret and not _can_fire:
		return null

	# Check energy
	var energy_sys := _get_energy_system()
	if energy_sys and mounted_weapon.ammo_type == WeaponResource.AmmoType.ENERGY:
		if not energy_sys.consume_energy(mounted_weapon.energy_cost_per_shot):
			return null

	_cooldown_timer = 1.0 / mounted_weapon.fire_rate
	if not is_turret:
		set_process(true)

	# Spawn projectile (prefer pool, fallback to instantiate)
	var bolt: BaseProjectile = null
	var pool := _get_projectile_pool()
	if pool and mounted_weapon.projectile_scene_path != "":
		bolt = pool.acquire(mounted_weapon.projectile_scene_path)
		if bolt:
			bolt._pool = pool
	if bolt == null:
		bolt = _projectile_scene.instantiate() as BaseProjectile
		if bolt == null:
			return null
		get_tree().current_scene.add_child(bolt)

	var ship_node := _get_ship_node()
	bolt.damage = mounted_weapon.damage_per_hit
	bolt.damage_type = mounted_weapon.damage_type
	bolt.max_lifetime = mounted_weapon.projectile_lifetime
	bolt.owner_ship = ship_node

	var spawn_pos: Vector3
	var fire_dir: Vector3
	var up_hint: Vector3

	var muzzle := get_muzzle_transform()
	spawn_pos = muzzle.origin

	if is_turret and _turret_pivot:
		# Turret: fire from muzzle directly toward the lead target position
		# (not along muzzle -Z, which has rotation lag and pivot offset error)
		fire_dir = (target_pos - spawn_pos).normalized()
		# Safety: if target is too close, fall back to muzzle forward
		if fire_dir.length_squared() < 0.25:
			fire_dir = (-muzzle.basis.z).normalized()
		up_hint = muzzle.basis.y
	else:
		# Fixed: aim from muzzle toward target
		fire_dir = (target_pos - spawn_pos).normalized()
		var ship_basis: Basis = ship_node.global_transform.basis if ship_node else Basis.IDENTITY
		# Safety: if target is too close or behind, fall back to muzzle forward
		if fire_dir.length() < 0.5 or ship_basis.z.dot(fire_dir) > 0.5:
			fire_dir = (-muzzle.basis.z).normalized()
		up_hint = muzzle.basis.y

	bolt.velocity = fire_dir * mounted_weapon.projectile_speed + ship_velocity
	bolt.global_transform = Transform3D(Basis.looking_at(fire_dir, up_hint), spawn_pos)

	# For missiles, set tracking target and reset arm timer (needed for pool reuse)
	if bolt is MissileProjectile and mounted_weapon.weapon_type in [WeaponResource.WeaponType.MISSILE, WeaponResource.WeaponType.TURRET]:
		var missile := bolt as MissileProjectile
		missile._arm_timer = 0.3
		missile.target = null
		var targeting := ship_node.get_node_or_null("TargetingSystem") as TargetingSystem
		if targeting and targeting.current_target:
			missile.target = targeting.current_target
			missile.tracking_strength = mounted_weapon.tracking_strength

	return bolt


func _load_weapon_mesh(weapon: WeaponResource) -> void:
	if weapon.weapon_model_scene == "":
		return
	var scene: PackedScene = load(weapon.weapon_model_scene) as PackedScene
	if scene == null:
		return
	_weapon_mesh_instance = scene.instantiate()
	# No runtime scaling — weapon scene defines its own size (WYSIWYG with editor)

	# Detect TurretBase node: if present, base stays fixed on hardpoint,
	# only TurretGun (sibling or child) rotates on the pivot.
	_turret_base = _weapon_mesh_instance.get_node_or_null("TurretBase")
	var turret_gun: Node3D = _weapon_mesh_instance.get_node_or_null("TurretGun")

	if is_turret and _turret_base and turret_gun:
		# Advanced turret rig: base fixed, gun rotates
		add_child(_weapon_mesh_instance)  # Whole scene on hardpoint (fixed)
		turret_gun.reparent(_turret_pivot)  # Move gun under pivot (rotates)
	else:
		# Simple weapon: attach everything to turret pivot (or hardpoint if fixed)
		var attach_parent: Node3D = _turret_pivot if _turret_pivot else self
		attach_parent.add_child(_weapon_mesh_instance)

	# Find muzzle points in the weapon model
	_muzzle_points.clear()
	_muzzle_index = 0
	_find_muzzle_points(_weapon_mesh_instance)
	# Also search in turret gun if reparented
	if turret_gun:
		_find_muzzle_points(turret_gun)


func _find_muzzle_points(root: Node3D) -> void:
	for child in root.get_children():
		if child is Node3D:
			var child_name: String = child.name
			if child_name == "MuzzlePoint" or child_name.begins_with("MuzzlePoint_"):
				_muzzle_points.append(child as Node3D)
			# Recurse into children (e.g. TurretRotator/MuzzlePoint)
			_find_muzzle_points(child as Node3D)


## Returns the current muzzle's global transform (position + direction).
## Cycles _muzzle_index for multi-barrel alternation.
## Fallback: if no muzzle points, returns hardpoint/pivot transform.
func get_muzzle_transform() -> Transform3D:
	if _muzzle_points.is_empty():
		if _turret_pivot:
			return _turret_pivot.global_transform
		return global_transform

	var muzzle: Node3D = _muzzle_points[_muzzle_index % _muzzle_points.size()]
	_muzzle_index = (_muzzle_index + 1) % _muzzle_points.size()
	return muzzle.global_transform


## Returns the first muzzle's global transform without cycling.
## Use for continuous beams (mining laser) that shouldn't alternate barrels.
func get_muzzle_transform_stable() -> Transform3D:
	if _muzzle_points.is_empty():
		if _turret_pivot:
			return _turret_pivot.global_transform
		return global_transform
	return _muzzle_points[0].global_transform


func _remove_weapon_mesh() -> void:
	if _weapon_mesh_instance and is_instance_valid(_weapon_mesh_instance):
		_weapon_mesh_instance.queue_free()
	_weapon_mesh_instance = null


func _cache_refs_if_needed() -> void:
	if _refs_cached:
		return
	_refs_cached = true
	# Walk up to find the ship (RigidBody3D parent)
	var node := get_parent()
	while node:
		if node is RigidBody3D:
			_cached_ship = node as Node3D
			break
		node = node.get_parent()
	if _cached_ship:
		_cached_energy_sys = _cached_ship.get_node_or_null("EnergySystem") as EnergySystem
	var mgr := GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr is ShipLODManager:
		_cached_pool = mgr.get_node_or_null("ProjectilePool") as ProjectilePool


func _get_energy_system() -> EnergySystem:
	_cache_refs_if_needed()
	return _cached_energy_sys


func _get_ship_node() -> Node3D:
	_cache_refs_if_needed()
	return _cached_ship


func _get_projectile_pool() -> ProjectilePool:
	_cache_refs_if_needed()
	return _cached_pool


func _get_ship_model() -> ShipModel:
	var ship := _get_ship_node()
	if ship:
		return ship.get_node_or_null("ShipModel") as ShipModel
	return null
