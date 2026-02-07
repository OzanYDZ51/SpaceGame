class_name Hardpoint
extends Node3D

# =============================================================================
# Hardpoint - A weapon mount point on a ship
# Manages a single weapon: cooldown, firing, energy consumption.
# =============================================================================

signal toggled(hp_id: int, is_enabled: bool)

var slot_id: int = 0
var slot_size: String = "S"  # "S", "M", "L"
var mounted_weapon: WeaponResource = null
var enabled: bool = true
var _cooldown_timer: float = 0.0
var _projectile_scene: PackedScene = null


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func setup(id: int, size: String, pos: Vector3, _dir: Vector3) -> void:
	slot_id = id
	slot_size = size
	position = pos
	# Direction not used yet (all forward-facing), but stored for turrets later
	name = "Hardpoint_%d" % id


func mount_weapon(weapon: WeaponResource) -> bool:
	if not can_mount(weapon):
		return false
	mounted_weapon = weapon
	_projectile_scene = load(weapon.projectile_scene_path) as PackedScene
	if _projectile_scene == null:
		push_warning("Hardpoint: Could not load projectile scene '%s'" % weapon.projectile_scene_path)
	return true


func unmount_weapon() -> void:
	mounted_weapon = null
	_projectile_scene = null


func can_mount(weapon: WeaponResource) -> bool:
	if weapon == null:
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


func try_fire(target_pos: Vector3, ship_velocity: Vector3) -> BaseProjectile:
	if not enabled:
		return null

	if mounted_weapon == null or _projectile_scene == null:
		return null

	if _cooldown_timer > 0.0:
		return null

	# Check energy
	var energy_sys := _get_energy_system()
	if energy_sys and mounted_weapon.ammo_type == WeaponResource.AmmoType.ENERGY:
		if not energy_sys.consume_energy(mounted_weapon.energy_cost_per_shot):
			return null

	_cooldown_timer = 1.0 / mounted_weapon.fire_rate

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

	var spawn_pos: Vector3 = global_position
	var ship_basis: Basis = ship_node.global_transform.basis if ship_node else Basis.IDENTITY

	# Calculate fire direction: converge toward target point (crosshair aim)
	var fire_dir: Vector3 = (target_pos - spawn_pos).normalized()
	# Safety: if target is too close or behind, fall back to ship forward
	if fire_dir.length() < 0.5 or ship_basis.z.dot(fire_dir) > 0.5:
		fire_dir = (ship_basis * Vector3.FORWARD).normalized()

	bolt.velocity = fire_dir * mounted_weapon.projectile_speed + ship_velocity
	bolt.global_transform = Transform3D(Basis.looking_at(fire_dir, ship_basis.y), spawn_pos)

	# For missiles, set tracking target and reset arm timer (needed for pool reuse)
	if bolt is MissileProjectile and mounted_weapon.weapon_type == WeaponResource.WeaponType.MISSILE:
		var missile := bolt as MissileProjectile
		missile._arm_timer = 0.3
		missile.target = null
		var targeting := ship_node.get_node_or_null("TargetingSystem") as TargetingSystem
		if targeting and targeting.current_target:
			missile.target = targeting.current_target
			missile.tracking_strength = mounted_weapon.tracking_strength

	return bolt


func _get_energy_system() -> EnergySystem:
	var ship := _get_ship_node()
	if ship:
		return ship.get_node_or_null("EnergySystem") as EnergySystem
	return null


func _get_ship_node() -> Node3D:
	# Walk up to find the ship (RigidBody3D parent)
	var node := get_parent()
	while node:
		if node is RigidBody3D:
			return node as Node3D
		node = node.get_parent()
	return null


func _get_projectile_pool() -> ProjectilePool:
	var mgr := GameManager.get_node_or_null("ShipLODManager")
	if mgr and mgr is ShipLODManager:
		return mgr.get_node_or_null("ProjectilePool") as ProjectilePool
	return null
