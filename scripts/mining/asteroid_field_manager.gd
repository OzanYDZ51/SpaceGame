class_name AsteroidFieldManager
extends Node

# =============================================================================
# Asteroid Field Manager
# Manages ALL asteroids for the current star system using SpatialGrid + LOD.
# 3 LOD levels: FULL (<500m), SIMPLIFIED (500-2000m), DOT (2000-6000m)
# =============================================================================

const LOD_FULL_DIST: float = 500.0
const LOD_SIMPLIFIED_DIST: float = 2000.0
const LOD_DOT_DIST: float = 6000.0
const LOD_FULL_MAX: int = 50
const LOD_SIMPLIFIED_MAX: int = 200
const MAX_PROMOTIONS_PER_TICK: int = 10
const LOD_EVAL_INTERVAL: float = 0.3
const RESPAWN_CHECK_INTERVAL: float = 5.0

enum AsteroidLOD { FULL, SIMPLIFIED, DOT, DATA_ONLY }

var _grid: SpatialGrid = null
var _fields: Array[AsteroidFieldData] = []
var _all_asteroids: Dictionary = {}  # id -> AsteroidData
var _lod_levels: Dictionary = {}     # id -> AsteroidLOD
var _full_nodes: Dictionary = {}     # id -> AsteroidNode
var _simplified_meshes: Dictionary = {}  # id -> MeshInstance3D

# MultiMesh for DOT-level asteroids (single draw call)
var _multimesh_instance: MultiMeshInstance3D = null
var _dot_ids: Array[StringName] = []

var _universe_node: Node3D = null
var _lod_timer: float = 0.0
var _respawn_timer: float = 0.0


func _ready() -> void:
	_grid = SpatialGrid.new(500.0)
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func initialize(universe: Node3D) -> void:
	_universe_node = universe
	_setup_multimesh()


func _setup_multimesh() -> void:
	if _universe_node == null:
		return
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "AsteroidDots"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	# Small sphere for dots
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 3.0
	dot_mesh.height = 6.0
	dot_mesh.radial_segments = 4
	dot_mesh.rings = 2
	mm.mesh = dot_mesh
	_multimesh_instance.multimesh = mm
	# Emissive material so dots are visible at distance
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.45, 0.5)
	mat.emission_energy_multiplier = 1.5
	_multimesh_instance.material_override = mat
	_universe_node.add_child(_multimesh_instance)


func populate_field(field: AsteroidFieldData) -> void:
	_fields.append(field)
	for asteroid in field.asteroids:
		_all_asteroids[asteroid.id] = asteroid
		_lod_levels[asteroid.id] = AsteroidLOD.DATA_ONLY
		_grid.insert(asteroid.id, asteroid.position, asteroid)


func clear_all() -> void:
	# Free all LOD nodes
	for id in _full_nodes:
		var node: AsteroidNode = _full_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
	_full_nodes.clear()

	for id in _simplified_meshes:
		var mesh: MeshInstance3D = _simplified_meshes[id]
		if is_instance_valid(mesh):
			mesh.queue_free()
	_simplified_meshes.clear()

	# Clear data
	_all_asteroids.clear()
	_lod_levels.clear()
	_dot_ids.clear()
	_fields.clear()
	_grid.clear()

	# Reset multimesh
	if _multimesh_instance and _multimesh_instance.multimesh:
		_multimesh_instance.multimesh.instance_count = 0


func get_nearest_asteroid(pos: Vector3, radius: float) -> AsteroidData:
	var results := _grid.query_nearest(pos, radius, 1)
	if results.is_empty():
		return null
	var id: StringName = results[0]["id"]
	return _all_asteroids.get(id)


func get_nearest_minable_asteroid(pos: Vector3, radius: float) -> AsteroidData:
	var results := _grid.query_nearest(pos, radius, 10)
	for entry in results:
		var asteroid: AsteroidData = _all_asteroids.get(entry["id"])
		if asteroid and not asteroid.is_depleted:
			return asteroid
	return null


func get_asteroid_data(id: StringName) -> AsteroidData:
	return _all_asteroids.get(id)


func _process(delta: float) -> void:
	if _all_asteroids.is_empty():
		return

	# LOD evaluation (throttled)
	_lod_timer += delta
	if _lod_timer >= LOD_EVAL_INTERVAL:
		_lod_timer -= LOD_EVAL_INTERVAL
		_evaluate_lod()

	# Respawn check (throttled)
	_respawn_timer += delta
	if _respawn_timer >= RESPAWN_CHECK_INTERVAL:
		_respawn_timer -= RESPAWN_CHECK_INTERVAL
		_tick_respawns(RESPAWN_CHECK_INTERVAL)


func _evaluate_lod() -> void:
	var cam_pos := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position

	var promotions: int = 0
	var new_dot_ids: Array[StringName] = []
	var full_count: int = _full_nodes.size()
	var simplified_count: int = _simplified_meshes.size()

	for id: StringName in _all_asteroids:
		var asteroid: AsteroidData = _all_asteroids[id]
		var dist: float = cam_pos.distance_to(asteroid.position)
		var current_lod: AsteroidLOD = _lod_levels.get(id, AsteroidLOD.DATA_ONLY)
		var target_lod: AsteroidLOD

		if dist < LOD_FULL_DIST and full_count < LOD_FULL_MAX:
			target_lod = AsteroidLOD.FULL
		elif dist < LOD_SIMPLIFIED_DIST and simplified_count < LOD_SIMPLIFIED_MAX:
			target_lod = AsteroidLOD.SIMPLIFIED
		elif dist < LOD_DOT_DIST:
			target_lod = AsteroidLOD.DOT
		else:
			target_lod = AsteroidLOD.DATA_ONLY

		if target_lod != current_lod:
			if promotions >= MAX_PROMOTIONS_PER_TICK:
				# Keep current LOD if we hit promotion limit
				if current_lod == AsteroidLOD.DOT:
					new_dot_ids.append(id)
				continue
			_transition_lod(id, asteroid, current_lod, target_lod)
			_lod_levels[id] = target_lod
			promotions += 1

			# Update counts
			if target_lod == AsteroidLOD.FULL:
				full_count += 1
			elif target_lod == AsteroidLOD.SIMPLIFIED:
				simplified_count += 1
		else:
			if current_lod == AsteroidLOD.DOT:
				new_dot_ids.append(id)

	# Rebuild DOT multimesh
	if target_lod_changed(new_dot_ids):
		_dot_ids = new_dot_ids
		_rebuild_multimesh()


func target_lod_changed(new_dots: Array[StringName]) -> bool:
	if new_dots.size() != _dot_ids.size():
		return true
	return false


func _transition_lod(id: StringName, asteroid: AsteroidData, from: AsteroidLOD, to: AsteroidLOD) -> void:
	# Remove old representation
	match from:
		AsteroidLOD.FULL:
			if _full_nodes.has(id):
				var node: AsteroidNode = _full_nodes[id]
				asteroid.node_ref = null
				if is_instance_valid(node):
					node.queue_free()
				_full_nodes.erase(id)
		AsteroidLOD.SIMPLIFIED:
			if _simplified_meshes.has(id):
				var mesh: MeshInstance3D = _simplified_meshes[id]
				if is_instance_valid(mesh):
					mesh.queue_free()
				_simplified_meshes.erase(id)

	# Create new representation
	match to:
		AsteroidLOD.FULL:
			_spawn_full(id, asteroid)
		AsteroidLOD.SIMPLIFIED:
			_spawn_simplified(id, asteroid)


func _spawn_full(id: StringName, asteroid: AsteroidData) -> void:
	if _universe_node == null:
		return
	var node := AsteroidNode.new()
	node.setup(asteroid)
	_universe_node.add_child(node)
	_full_nodes[id] = node
	# Show scan label for nearby asteroids
	node.show_scan_info()


func _spawn_simplified(id: StringName, asteroid: AsteroidData) -> void:
	if _universe_node == null:
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "AsteroidSimp_" + String(id)
	var sphere := SphereMesh.new()
	sphere.radius = asteroid.visual_radius
	sphere.height = asteroid.visual_radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 4
	mesh_inst.mesh = sphere
	mesh_inst.scale = asteroid.scale_distort

	var mat := StandardMaterial3D.new()
	var res := MiningRegistry.get_resource(asteroid.primary_resource)
	mat.albedo_color = asteroid.color_tint if asteroid.color_tint != Color.GRAY else (res.color if res else Color.GRAY)
	if asteroid.is_depleted:
		mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mesh_inst.material_override = mat
	mesh_inst.position = asteroid.position
	_universe_node.add_child(mesh_inst)
	_simplified_meshes[id] = mesh_inst


func _rebuild_multimesh() -> void:
	if _multimesh_instance == null or _multimesh_instance.multimesh == null:
		return
	var mm := _multimesh_instance.multimesh
	var count: int = _dot_ids.size()
	mm.instance_count = count

	for i in count:
		var id: StringName = _dot_ids[i]
		var asteroid: AsteroidData = _all_asteroids.get(id)
		if asteroid == null:
			continue
		var t := Transform3D.IDENTITY
		t = t.scaled(Vector3.ONE * (asteroid.visual_radius * 0.3))
		t.origin = asteroid.position
		mm.set_instance_transform(i, t)
		var col: Color = asteroid.color_tint if asteroid.color_tint != Color.GRAY else Color(0.5, 0.55, 0.6)
		if asteroid.is_depleted:
			col = Color(0.25, 0.25, 0.25)
		mm.set_instance_color(i, col)


func _tick_respawns(elapsed: float) -> void:
	for id: StringName in _all_asteroids:
		var asteroid: AsteroidData = _all_asteroids[id]
		if not asteroid.is_depleted:
			continue
		asteroid.respawn_timer -= elapsed
		if asteroid.respawn_timer <= 0.0:
			asteroid.is_depleted = false
			asteroid.health_current = asteroid.health_max
			asteroid.respawn_timer = 0.0
			# If currently at FULL LOD, respawn the node
			if _full_nodes.has(id):
				var node: AsteroidNode = _full_nodes[id]
				if is_instance_valid(node):
					node.respawn()


func _on_origin_shifted(shift: Vector3) -> void:
	# Shift all asteroid positions in data
	for id: StringName in _all_asteroids:
		var asteroid: AsteroidData = _all_asteroids[id]
		asteroid.position -= shift

	# Rebuild spatial grid
	_grid.apply_origin_shift(shift)

	# Shift simplified meshes (AsteroidNode positions are shifted by Universe parent)
	for id in _simplified_meshes:
		var mesh: MeshInstance3D = _simplified_meshes[id]
		if is_instance_valid(mesh):
			var asteroid: AsteroidData = _all_asteroids.get(id)
			if asteroid:
				mesh.position = asteroid.position

	# Rebuild multimesh with shifted positions
	_rebuild_multimesh()
