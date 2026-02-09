class_name AsteroidNode
extends StaticBody3D

# =============================================================================
# Asteroid Node - Physical asteroid with mesh, collision, and mining interaction
# =============================================================================

signal depleted(asteroid_id: StringName)

var data: AsteroidData = null
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _label: Label3D = null
var _label_visible: bool = false


func setup(p_data: AsteroidData) -> void:
	data = p_data
	data.node_ref = self
	name = String(data.id)
	position = data.position

	# Collision
	_collision = CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = data.visual_radius
	_collision.shape = shape
	add_child(_collision)
	collision_layer = Constants.LAYER_ASTEROIDS
	collision_mask = 0

	# Mesh: low-poly sphere with non-uniform scale for rocky look
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = data.visual_radius
	sphere.height = data.visual_radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 6
	_mesh_instance.mesh = sphere
	_mesh_instance.scale = data.scale_distort

	# Material
	var mat := StandardMaterial3D.new()
	var res := MiningRegistry.get_resource(data.primary_resource)
	var base_col: Color = data.color_tint if data.color_tint != Color.GRAY else (res.color if res else Color.GRAY)
	mat.albedo_color = base_col
	mat.roughness = 0.85
	mat.metallic = 0.15
	# Subtle emission based on resource rarity
	if res and res.rarity >= MiningResource.Rarity.RARE:
		mat.emission_enabled = true
		mat.emission = base_col * 0.3
		mat.emission_energy_multiplier = 0.5
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	if data == null:
		return
	# Slow tumble rotation
	rotate(data.rotation_axis, data.rotation_speed * delta)


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
	# Dim the asteroid visually
	if _mesh_instance and _mesh_instance.material_override:
		var mat: StandardMaterial3D = _mesh_instance.material_override
		mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = false
	# Shrink slightly
	var tw := create_tween()
	tw.tween_property(_mesh_instance, "scale", data.scale_distort * 0.6, 0.5)


func respawn() -> void:
	data.is_depleted = false
	data.health_current = data.health_max
	data.respawn_timer = 0.0
	# Restore visuals
	if _mesh_instance:
		_mesh_instance.scale = data.scale_distort
		if _mesh_instance.material_override:
			var mat: StandardMaterial3D = _mesh_instance.material_override
			var res := MiningRegistry.get_resource(data.primary_resource)
			mat.albedo_color = data.color_tint if data.color_tint != Color.GRAY else (res.color if res else Color.GRAY)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			if res and res.rarity >= MiningResource.Rarity.RARE:
				mat.emission_enabled = true
				mat.emission = mat.albedo_color * 0.3
				mat.emission_energy_multiplier = 0.5


func show_scan_info() -> void:
	if _label_visible:
		return
	_label_visible = true
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.font_size = 28
		_label.outline_size = 4
		_label.modulate = Color(0.7, 0.9, 1.0, 0.9)
		_label.pixel_size = 0.05
		add_child(_label)
	_label.position = Vector3(0, data.visual_radius + 5.0, 0)
	_update_label_text()
	_label.visible = true


func hide_scan_info() -> void:
	_label_visible = false
	if _label:
		_label.visible = false


func _update_label_text() -> void:
	if _label == null or data == null:
		return
	var res := MiningRegistry.get_resource(data.primary_resource)
	var res_name: String = res.display_name if res else "?"
	var size_name: String
	match data.size:
		AsteroidData.AsteroidSize.SMALL: size_name = "S"
		AsteroidData.AsteroidSize.MEDIUM: size_name = "M"
		AsteroidData.AsteroidSize.LARGE: size_name = "L"
		_: size_name = "?"
	var hp_pct: int = int(data.health_current / data.health_max * 100.0) if data.health_max > 0 else 0
	if data.is_depleted:
		_label.text = "%s [%s] ÉPUISÉ" % [res_name, size_name]
		_label.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		_label.text = "%s [%s] %d%%" % [res_name, size_name, hp_pct]
		_label.modulate = Color(0.7, 0.9, 1.0, 0.9)
