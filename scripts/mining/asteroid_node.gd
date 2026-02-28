class_name AsteroidNode
extends StaticBody3D

# =============================================================================
# Asteroid Node - Physical asteroid with GLB mesh, collision, and mining interaction
# Uses material_overlay (semi-transparent) to preserve PBR materials from GLB
# while supporting scan color reveal on top.
# =============================================================================

const _AsteroidMeshLib = preload("res://scripts/mining/asteroid_mesh_lib.gd")

signal depleted(asteroid_id: StringName)

var data = null
var _mesh_pivot: Node3D = null          # Pivot at asteroid center — rotated each frame
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _glb_scale: Vector3 = Vector3.ONE  # Scale computed from GLB normalization


func setup(p_data) -> void:
	data = p_data
	data.node_ref = self
	name = String(data.id)
	position = data.position

	# Collision — SphereShape3D unchanged
	_collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = data.visual_radius
	_collision.shape = shape
	add_child(_collision)
	collision_layer = Constants.LAYER_ASTEROIDS
	collision_mask = 0

	# Pivot node — rotated each frame so mesh spins around its visual center
	_mesh_pivot = Node3D.new()
	add_child(_mesh_pivot)

	# Mesh: GLB variant from AsteroidMeshLib
	_mesh_instance = MeshInstance3D.new()
	var variant: Dictionary = _AsteroidMeshLib.get_variant(data.mesh_variant_idx)
	if not variant.is_empty():
		_mesh_instance.mesh = variant["mesh"]
		_glb_scale = _AsteroidMeshLib.compute_scale_for_radius(variant, data.visual_radius)
		_mesh_instance.scale = _glb_scale * data.scale_distort
		# Center mesh so rotation orbits around the visual center, not the GLB pivot
		var aabb_center: Vector3 = variant.get("aabb_center", Vector3.ZERO)
		_mesh_instance.position = -aabb_center * _mesh_instance.scale
	else:
		# Fallback: procedural sphere if GLB failed to load
		var sphere = SphereMesh.new()
		sphere.radius = data.visual_radius
		sphere.height = data.visual_radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 6
		_mesh_instance.mesh = sphere
		_glb_scale = Vector3.ONE
		_mesh_instance.scale = data.scale_distort

	# Overlay material — semi-transparent tint on top of PBR
	var overlay = StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(data.color_tint, 0.0)  # Start invisible (PBR shows through)
	overlay.roughness = 1.0
	overlay.metallic = 0.0
	# Show scan emission if already scanned with rare resource
	if data.is_scanned and data.has_resource:
		var res = MiningRegistry.get_resource(data.primary_resource)
		if res and res.rarity >= MiningResource.Rarity.RARE:
			overlay.emission_enabled = true
			overlay.emission = data.resource_color * 0.3
			overlay.emission_energy_multiplier = 0.5
			overlay.albedo_color = Color(data.color_tint, 0.35)
	_mesh_instance.material_overlay = overlay
	_mesh_pivot.add_child(_mesh_instance)


func _process(delta: float) -> void:
	if data == null or _mesh_pivot == null:
		return
	# Rotate the pivot — mesh is centered inside so it spins in place
	_mesh_pivot.rotate(data.rotation_axis, data.rotation_speed * delta)


func take_mining_damage(amount: float) -> Dictionary:
	if data == null or data.is_depleted:
		return {}

	data.health_current -= amount
	var yield_qty: int = data.get_yield_per_hit()

	if data.health_current <= 0.0:
		data.health_current = 0.0
		data.is_depleted = true
		data.respawn_timer = Constants.ASTEROID_RESPAWN_TIME
		_on_depleted()
		depleted.emit(data.id)

	return {
		"resource_id": data.primary_resource,
		"quantity": yield_qty,
	}


func _on_depleted() -> void:
	# Dim the asteroid visually via overlay
	if _mesh_instance and _mesh_instance.material_overlay:
		var mat: StandardMaterial3D = _mesh_instance.material_overlay
		mat.albedo_color = Color(0.1, 0.1, 0.1, 0.7)
		mat.emission_enabled = false
	# Shrink via pivot so mesh centering offset stays correct
	if _mesh_pivot:
		var tw = create_tween()
		tw.tween_property(_mesh_pivot, "scale", Vector3.ONE * 0.6, 0.5)


## Tween mesh scale based on HP ratio (for cooperative mining visual feedback).
## At 100% HP → full scale. At 0% → 60% scale (matches depleted shrink).
func apply_health_visual_update(hp_ratio: float) -> void:
	if _mesh_pivot == null:
		return
	var scale_factor: float = lerpf(0.6, 1.0, clampf(hp_ratio, 0.0, 1.0))
	var tw = create_tween()
	tw.tween_property(_mesh_pivot, "scale", Vector3.ONE * scale_factor, 0.3).set_ease(Tween.EASE_OUT)


func respawn() -> void:
	data.is_depleted = false
	data.health_current = data.health_max
	data.respawn_timer = 0.0
	# Restore visuals
	if _mesh_pivot:
		_mesh_pivot.scale = Vector3.ONE
	if _mesh_instance:
		if _mesh_instance.material_overlay:
			var mat: StandardMaterial3D = _mesh_instance.material_overlay
			mat.albedo_color = Color(data.color_tint, 0.0)  # Invisible overlay
			mat.emission_enabled = false
			if data.is_scanned and data.has_resource:
				var res = MiningRegistry.get_resource(data.primary_resource)
				if res and res.rarity >= MiningResource.Rarity.RARE:
					mat.emission_enabled = true
					mat.emission = data.resource_color * 0.3
					mat.emission_energy_multiplier = 0.5
					mat.albedo_color = Color(data.color_tint, 0.35)


func apply_scan_reveal(ast_data) -> void:
	if _mesh_instance == null or _mesh_instance.material_overlay == null:
		return
	var mat: StandardMaterial3D = _mesh_instance.material_overlay
	var target_col: Color = ast_data.resource_color

	# Phase 1: Instant flash (0-0.15s) — bright white-tinted emission
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0).lerp(target_col, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color(target_col.lerp(Color.WHITE, 0.4), 0.6)

	# Phase 2: Settle (0.15-0.8s) — tween to resource color
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color", Color(target_col, 0.4), 0.65).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_property(mat, "emission", target_col * 0.5, 0.65).set_ease(Tween.EASE_OUT).set_delay(0.15)

	# Rare resources keep sustained emission, normal ones fade out
	var res = MiningRegistry.get_resource(ast_data.primary_resource)
	if res and res.rarity >= MiningResource.Rarity.RARE:
		tw.tween_property(mat, "emission_energy_multiplier", 0.5, 0.65).set_ease(Tween.EASE_OUT).set_delay(0.15)
	else:
		tw.tween_property(mat, "emission_energy_multiplier", 0.5, 0.65).set_ease(Tween.EASE_OUT).set_delay(0.15)
		var tw2 = create_tween()
		tw2.tween_property(mat, "emission_energy_multiplier", 0.0, 0.7).set_delay(1.5)
		tw2.tween_callback(func(): mat.emission_enabled = false)


func apply_scan_expire() -> void:
	if _mesh_instance == null or _mesh_instance.material_overlay == null:
		return
	var mat: StandardMaterial3D = _mesh_instance.material_overlay
	var tw = create_tween()
	tw.tween_property(mat, "albedo_color", Color(0.0, 0.0, 0.0, 0.0), 1.0).set_ease(Tween.EASE_IN)
	if mat.emission_enabled:
		tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.8)
		tw.tween_callback(func(): mat.emission_enabled = false)


func flash_barren() -> void:
	if _mesh_instance == null or _mesh_instance.material_overlay == null:
		return
	var mat: StandardMaterial3D = _mesh_instance.material_overlay
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.15, 0.05)
	mat.emission_energy_multiplier = 1.5
	var tw = create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): mat.emission_enabled = false)
