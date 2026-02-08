class_name BaseProjectile
extends Area3D

# =============================================================================
# Base Projectile - Common logic for all projectile types
# Handles movement, lifetime, collision, damage application.
# Spawns ShieldHitEffect or HullHitEffect based on whether shields absorbed.
# =============================================================================

const _DissipateEffect = preload("res://scripts/effects/projectile_dissipate_effect.gd")

var velocity: Vector3 = Vector3.ZERO
var damage: float = 25.0
var damage_type: StringName = &"thermal"
var owner_ship: Node3D = null  # Prevents self-hit
var max_lifetime: float = 3.0
var _lifetime: float = 0.0
var _pool: ProjectilePool = null  # Set by pool on acquire


func _ready() -> void:
	collision_layer = Constants.LAYER_PROJECTILES
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_hit)
	area_entered.connect(_on_area_hit)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_lifetime += delta
	if _lifetime >= max_lifetime:
		_spawn_dissipate_effect()
		_return_to_pool()


var weapon_name: StringName = &""  # Set by WeaponManager on fire


func _on_body_hit(body: Node3D) -> void:
	if owner_ship != null and not is_instance_valid(owner_ship):
		owner_ship = null
	if body == owner_ship:
		return

	# Multiplayer client: send hit claim to server for server-managed NPCs only
	if NetworkManager.is_connected_to_server() and not NetworkManager.is_server():
		if body.is_in_group("ships"):
			var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
			if lod_mgr:
				var lod_data: ShipLODData = lod_mgr.get_ship_data(StringName(body.name))
				if lod_data and lod_data.is_server_npc:
					var hit_dir := (body.global_position - global_position).normalized()
					NetworkManager._rpc_hit_claim.rpc_id(1,
						body.name, String(weapon_name), damage,
						[hit_dir.x, hit_dir.y, hit_dir.z])
					_spawn_hit_effect(body, {"shield_absorbed": false})
					_return_to_pool()
					return

	var hit_info := _apply_damage_to(body)
	_spawn_hit_effect(body, hit_info)
	_report_hit_to_owner(body, hit_info)
	_return_to_pool()


func _on_area_hit(_area: Area3D) -> void:
	_spawn_hit_effect()
	_return_to_pool()


func _apply_damage_to(body: Node3D) -> Dictionary:
	var health := body.get_node_or_null("HealthSystem") as HealthSystem
	if health == null:
		return {"shield_absorbed": false}
	var hit_dir: Vector3 = (body.global_position - global_position).normalized()
	var attacker: Node3D = owner_ship if is_instance_valid(owner_ship) else null
	return health.apply_damage(damage, damage_type, hit_dir, attacker)


func _spawn_hit_effect(body: Node3D = null, hit_info: Dictionary = {}) -> void:
	var scene_root := get_tree().current_scene
	var intensity := clampf(damage / 25.0, 0.5, 3.0)

	if hit_info.get("shield_absorbed", false) and body != null:
		# Shield absorbed the hit — energy bubble on ship
		var effect := ShieldHitEffect.new()
		body.add_child(effect)
		effect.setup(global_position, body, hit_info.get("shield_ratio", 0.0), intensity)
	else:
		# Hull hit or non-ship target — sparks, debris, scorch
		var effect := HullHitEffect.new()
		scene_root.add_child(effect)
		effect.global_position = global_position
		var hit_normal := Vector3.UP
		if body:
			hit_normal = (global_position - body.global_position).normalized()
		elif velocity.length_squared() > 0.01:
			hit_normal = velocity.normalized()
		effect.setup(hit_normal, intensity)


func _report_hit_to_owner(body: Node3D, hit_info: Dictionary) -> void:
	if not is_instance_valid(owner_ship):
		return
	var wm := owner_ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm == null:
		return
	var killed := false
	var health := body.get_node_or_null("HealthSystem") as HealthSystem
	if health and health.is_dead():
		killed = true
	wm._on_projectile_hit(hit_info, damage, killed)


func _return_to_pool() -> void:
	if _pool:
		_pool.release(self)
	else:
		queue_free()


func _spawn_dissipate_effect() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var effect := _DissipateEffect.new()
	scene_root.add_child(effect)
	effect.global_position = global_position
	var dir := velocity.normalized() if velocity.length_squared() > 0.01 else Vector3.FORWARD
	var color := Color(0.5, 0.7, 1.0)
	if damage_type == &"thermal":
		color = Color(0.3, 0.6, 1.0)
	elif damage_type == &"kinetic":
		color = Color(0.8, 0.85, 1.0)
	elif damage_type == &"explosive":
		color = Color(1.0, 0.5, 0.2)
	effect.setup(dir, color)
