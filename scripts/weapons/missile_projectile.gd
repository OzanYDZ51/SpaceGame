class_name MissileProjectile
extends BaseProjectile

# =============================================================================
# Missile Projectile - Tracking/dumbfire/torpedo projectile
# Has HP (can be shot down), trail particles, AOE damage, missile model.
# =============================================================================

var target: Node3D = null
var tracking_strength: float = 90.0  # degrees per second
var missile_category: int = 0  # WeaponResource.MissileCategory
var missile_hp: float = 30.0
var aoe_radius: float = 0.0
var _arm_timer: float = 0.3  # seconds before tracking activates

# Trail / model
var _trail: GPUParticles3D = null
var _exhaust_light: OmniLight3D = null
var _missile_model: Node3D = null
var _model_scale: float = 1.0

# Floating origin connection
var _origin_connected: bool = false


func _ready() -> void:
	# Override base collision layer to MISSILES instead of PROJECTILES
	collision_layer = Constants.LAYER_MISSILES
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_TERRAIN
	monitoring = true
	monitorable = true  # So projectiles can detect us
	body_entered.connect(_on_body_hit)
	area_entered.connect(_on_area_hit)
	add_to_group("missiles")

	if not _origin_connected:
		FloatingOrigin.origin_shifted.connect(_on_origin_shifted)
		_origin_connected = true


func _physics_process(delta: float) -> void:
	if not visible:
		return

	_arm_timer -= delta

	# Tracking: only for GUIDED and TORPEDO (not DUMBFIRE)
	if _arm_timer <= 0.0 and missile_category != 1 and target != null and is_instance_valid(target):
		var target_pos: Vector3 = TargetingSystem.get_ship_center(target) if target.has_method("get_node_or_null") else target.global_position
		var to_target: Vector3 = (target_pos - global_position).normalized()
		var current_dir: Vector3 = velocity.normalized()
		if current_dir.length_squared() < 0.01:
			current_dir = -global_transform.basis.z
		var angle_to: float = current_dir.angle_to(to_target)
		if angle_to > 0.001:
			var max_turn: float = deg_to_rad(tracking_strength) * delta
			var t: float = minf(max_turn / angle_to, 1.0)
			var new_dir: Vector3 = current_dir.slerp(to_target, t)
			velocity = new_dir * velocity.length()

	# Align visual rotation with velocity
	if velocity.length_squared() > 1.0:
		var up: Vector3 = global_transform.basis.y
		var fwd: Vector3 = velocity.normalized()
		if absf(fwd.dot(up)) > 0.99:
			up = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		look_at(global_position + velocity, up)

	# Movement (no sweep raycast for missiles — they're larger and slower)
	global_position += velocity * delta
	_lifetime += delta
	if _lifetime >= max_lifetime:
		_explode()


func take_damage(amount: float) -> void:
	if missile_hp <= 0.0:
		return  # Already dead or indestructible
	missile_hp -= amount
	if missile_hp <= 0.0:
		_explode()


func setup_missile_model(model_path: String, desired_length: float) -> void:
	if model_path.is_empty():
		return
	var scene: PackedScene = load(model_path) as PackedScene
	if scene == null:
		push_warning("MissileProjectile: failed to load model '%s'" % model_path)
		return
	_missile_model = scene.instantiate()
	add_child(_missile_model)  # Triggers MissileModelExtractor._ready()

	# Auto-scale: measure AABB and scale to desired_length
	var aabb := _compute_model_aabb(_missile_model)
	var longest_axis: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest_axis > 0.001 and desired_length > 0.0:
		var scale_factor: float = desired_length / longest_axis
		_missile_model.scale = Vector3.ONE * scale_factor
		_model_scale = scale_factor
	else:
		_missile_model.scale = Vector3.ONE * desired_length
		_model_scale = desired_length


func _compute_model_aabb(root: Node) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_find_visible_meshes(root, meshes)
	if meshes.is_empty():
		return AABB()
	var root_inv: Transform3D = root.global_transform.affine_inverse()
	var result: AABB = root_inv * meshes[0].global_transform * meshes[0].mesh.get_aabb()
	for i in range(1, meshes.size()):
		var mesh_aabb: AABB = root_inv * meshes[i].global_transform * meshes[i].mesh.get_aabb()
		result = result.merge(mesh_aabb)
	return result


func _find_visible_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.visible and node.mesh:
		meshes.append(node)
	for child in node.get_children():
		_find_visible_meshes(child, meshes)


func start_trail(color: Color) -> void:
	# Smoke trail (world-space particles)
	_trail = GPUParticles3D.new()
	_trail.emitting = true
	_trail.amount = 48
	_trail.lifetime = 2.0
	_trail.local_coords = false  # World space — trail persists behind missile
	_trail.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 1)  # Emit backwards
	mat.spread = 3.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.0
	mat.damping_max = 4.0

	# Scale: start small, grow as smoke expands
	mat.scale_min = 0.15
	mat.scale_max = 0.3
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 1.5))
	scale_curve.curve = curve
	mat.scale_curve = scale_curve

	# Color: bright exhaust → gray smoke → transparent
	var color_ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r * 1.5, color.g * 1.2, color.b, 0.9))
	gradient.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	gradient.add_point(0.15, Color(color.r, color.g * 0.8, color.b * 0.5, 0.7))
	gradient.add_point(0.4, Color(0.6, 0.5, 0.4, 0.3))
	mat.color_ramp = color_ramp

	_trail.process_material = mat

	# Soft circle particle mesh (not a hard-edged quad)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.albedo_texture = _create_soft_circle_texture()
	mesh.material = mesh_mat
	_trail.draw_pass_1 = mesh

	add_child(_trail)

	# Exhaust glow light
	_exhaust_light = OmniLight3D.new()
	_exhaust_light.light_color = color
	_exhaust_light.light_energy = 2.0
	_exhaust_light.omni_range = 5.0
	_exhaust_light.shadow_enabled = false
	add_child(_exhaust_light)


static var _soft_circle_tex: ImageTexture = null

static func _create_soft_circle_texture() -> ImageTexture:
	if _soft_circle_tex != null:
		return _soft_circle_tex
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) / 2.0
	for y in size:
		for x in size:
			var dx: float = (x - center) / center
			var dy: float = (y - center) / center
			var dist: float = sqrt(dx * dx + dy * dy)
			var alpha: float = clampf(1.0 - dist, 0.0, 1.0)
			alpha *= alpha  # Quadratic falloff for soft edge
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_soft_circle_tex = ImageTexture.create_from_image(img)
	return _soft_circle_tex


func _explode() -> void:
	# AOE damage
	if aoe_radius > 0.0:
		_apply_aoe_damage()

	# Explosion effect
	_spawn_hit_effect()

	# Detach trail so it persists visually
	_detach_trail()

	_return_to_pool()


func _apply_aoe_damage() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	# Use a sphere query for AOE
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = aoe_radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS
	if owner_ship and is_instance_valid(owner_ship) and owner_ship is CollisionObject3D:
		query.exclude = [owner_ship.get_rid()]

	var results := space.intersect_shape(query, 32)
	for result in results:
		var body: Node3D = result.get("collider") as Node3D
		if body == null or body == owner_ship:
			continue
		if _is_friendly(body):
			continue
		# Distance falloff: full damage at center, 25% at edge
		var dist: float = global_position.distance_to(body.global_position)
		var falloff: float = 1.0 - (dist / aoe_radius) * 0.75
		falloff = clampf(falloff, 0.25, 1.0)
		var aoe_dmg: float = damage * falloff

		var health = body.get_node_or_null("HealthSystem")
		if health:
			var hit_dir: Vector3 = (body.global_position - global_position).normalized()
			health.apply_damage(aoe_dmg, damage_type, hit_dir, owner_ship if is_instance_valid(owner_ship) else null)
		var struct_health = body.get_node_or_null("StructureHealth")
		if struct_health:
			var hit_dir: Vector3 = (body.global_position - global_position).normalized()
			struct_health.apply_damage(aoe_dmg, damage_type, hit_dir, owner_ship if is_instance_valid(owner_ship) else null)


func reset_for_pool() -> void:
	target = null
	missile_hp = 30.0
	missile_category = 0
	aoe_radius = 0.0
	tracking_strength = 90.0
	_arm_timer = 0.3
	_lifetime = 0.0

	# Clean up trail
	if _trail and is_instance_valid(_trail):
		_trail.queue_free()
	_trail = null
	if _exhaust_light and is_instance_valid(_exhaust_light):
		_exhaust_light.queue_free()
	_exhaust_light = null

	# Clean up model
	if _missile_model and is_instance_valid(_missile_model):
		_missile_model.queue_free()
	_missile_model = null

	# Reset collision to missile layer
	collision_layer = Constants.LAYER_MISSILES
	monitorable = true


func _return_to_pool() -> void:
	remove_from_group("missiles")
	reset_for_pool()
	if _pool:
		_pool.release(self)
	else:
		queue_free()


func _on_body_hit(body: Node3D) -> void:
	if not visible:
		return
	if owner_ship != null and not is_instance_valid(owner_ship):
		owner_ship = null
	if body == owner_ship:
		return
	if _is_friendly(body):
		return

	# AOE on impact (before returning to pool)
	if aoe_radius > 0.0:
		_apply_aoe_damage()

	# Detach trail before pool return
	_detach_trail()

	# Use base class for full hit logic (network claims, damage, effects)
	super._on_body_hit(body)


func _detach_trail() -> void:
	if _trail and is_instance_valid(_trail):
		_trail.emitting = false
		var scene_root := get_tree().current_scene
		if scene_root:
			var trail_ref := _trail
			_trail.reparent(scene_root)
			_trail = null
			var tw := trail_ref.create_tween()
			tw.tween_interval(trail_ref.lifetime)
			tw.tween_callback(trail_ref.queue_free)


func _on_origin_shifted(delta: Vector3) -> void:
	if visible:
		global_position += delta


func _on_area_hit(area: Area3D) -> void:
	if not visible:
		return
	# Don't self-collide with other missiles from same owner
	if area is MissileProjectile:
		return
	_spawn_hit_effect()
	_explode()


func _exit_tree() -> void:
	if _origin_connected and FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.disconnect(_on_origin_shifted)
		_origin_connected = false
