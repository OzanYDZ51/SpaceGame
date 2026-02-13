class_name AsteroidFieldManager
extends Node

# =============================================================================
# Asteroid Field Manager - Local Procedural Generation
# Generates asteroids dynamically in cells around the player's position.
# Only cells that fall within a belt ring AND are near the player get loaded.
# Deterministic seeding ensures the same cell always produces the same asteroids.
# =============================================================================

# --- LOD ---
const LOD_FULL_DIST: float = 500.0
const LOD_SIMPLIFIED_DIST: float = 2000.0
const LOD_DOT_DIST: float = 6000.0
const LOD_FULL_MAX: int = 50
const LOD_SIMPLIFIED_MAX: int = 200
const MAX_PROMOTIONS_PER_TICK: int = 10
const LOD_EVAL_INTERVAL: float = 0.3
const RESPAWN_CHECK_INTERVAL: float = 10.0

# --- Cell-based generation ---
const CELL_SIZE: float = 1000.0        # 1 km generation cells
const LOAD_RADIUS: float = 8000.0      # Load cells within 8 km
const UNLOAD_RADIUS: float = 10000.0   # Unload cells beyond 10 km
const CELL_EVAL_INTERVAL: float = 0.5  # Check cells every 0.5s
const ASTEROIDS_PER_CELL_MIN: int = 3
const ASTEROIDS_PER_CELL_MAX: int = 6
const VERTICAL_SPREAD: float = 400.0   # ±200 m vertical spread
const SCAN_NEUTRAL_COLOR := Color(0.35, 0.33, 0.3)
const SCAN_BARREN_RATE: float = 0.60
const SCAN_REVEAL_DURATION: float = 30.0  # seconds before scan expires
const SCAN_EXPIRY_CHECK_INTERVAL: float = 2.0

enum AsteroidLOD { FULL, SIMPLIFIED, DOT, DATA_ONLY }

var _grid: SpatialGrid = null
var _fields: Array[AsteroidFieldData] = []
var _system_seed: int = 0

# Cell tracking: Vector2i (universe-space cell coords) -> Array[StringName] (asteroid ids)
var _loaded_cells: Dictionary = {}

# Asteroid data (only for loaded cells)
var _all_asteroids: Dictionary = {}   # id -> AsteroidData
var _lod_levels: Dictionary = {}      # id -> AsteroidLOD
var _full_nodes: Dictionary = {}      # id -> AsteroidNode
var _simplified_meshes: Dictionary = {} # id -> MeshInstance3D

# Depleted tracking (persists across cell load/unload within the session)
var _depleted_ids: Dictionary = {}    # StringName -> float (unix timestamp)

# MultiMesh for DOT-level asteroids (single draw call)
var _multimesh_instance: MultiMeshInstance3D = null
var _dot_ids: Array[StringName] = []

var _universe_node: Node3D = null
var _lod_timer: float = 0.0
var _cell_timer: float = 0.0
var _respawn_timer: float = 0.0
var _scan_expiry_timer: float = 0.0
var _dots_dirty: bool = false


func _ready() -> void:
	_grid = SpatialGrid.new(500.0)
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func initialize(universe: Node3D) -> void:
	_universe_node = universe
	_setup_multimesh()


func set_system_seed(seed_val: int) -> void:
	_system_seed = seed_val


func _setup_multimesh() -> void:
	if _universe_node == null:
		return
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "AsteroidDots"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 3.0
	dot_mesh.height = 6.0
	dot_mesh.radial_segments = 4
	dot_mesh.rings = 2
	mm.mesh = dot_mesh
	_multimesh_instance.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	mat.emission_enabled = false
	mat.roughness = 0.95
	_multimesh_instance.material_override = mat
	_universe_node.add_child(_multimesh_instance)


## Register a belt (metadata only — no pre-generated asteroids).
func populate_field(field: AsteroidFieldData) -> void:
	_fields.append(field)


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

	_all_asteroids.clear()
	_lod_levels.clear()
	_dot_ids.clear()
	_loaded_cells.clear()
	_depleted_ids.clear()
	_fields.clear()
	_grid.clear()
	_system_seed = 0

	if _multimesh_instance and _multimesh_instance.multimesh:
		_multimesh_instance.multimesh.instance_count = 0


# === Public API ===

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
		if asteroid and not asteroid.is_depleted and asteroid.has_resource:
			return asteroid
	return null


func get_nearest_minable_asteroid_filtered(pos: Vector3, radius: float, resource_filter: Array) -> AsteroidData:
	var results := _grid.query_nearest(pos, radius, 20)
	for entry in results:
		var asteroid: AsteroidData = _all_asteroids.get(entry["id"])
		if asteroid and not asteroid.is_depleted and asteroid.has_resource:
			if asteroid.primary_resource in resource_filter:
				return asteroid
	return null


func get_asteroid_data(id: StringName) -> AsteroidData:
	return _all_asteroids.get(id)


## Returns asteroid data objects within radius of pos (for radar).
func get_asteroids_in_radius(pos: Vector3, radius: float) -> Array[AsteroidData]:
	var ids := _grid.query_radius(pos, radius)
	var result: Array[AsteroidData] = []
	for id in ids:
		var ast: AsteroidData = _all_asteroids.get(id)
		if ast and not ast.is_depleted:
			result.append(ast)
	return result


## Returns belt name if (universe_x, universe_z) is inside a belt, empty string otherwise.
func get_belt_at_position(universe_x: float, universe_z: float) -> String:
	var dist: float = sqrt(universe_x * universe_x + universe_z * universe_z)
	for field in _fields:
		if absf(dist - field.orbital_radius) < field.width * 0.5:
			return field.field_name
	return ""


## Called when an asteroid is depleted (persists across cell load/unload).
func on_asteroid_depleted(id: StringName) -> void:
	_depleted_ids[id] = Time.get_unix_time_from_system()


# === Process ===

func _process(delta: float) -> void:
	if _fields.is_empty():
		return

	# Cell evaluation (load/unload cells around player)
	_cell_timer += delta
	if _cell_timer >= CELL_EVAL_INTERVAL:
		_cell_timer -= CELL_EVAL_INTERVAL
		_evaluate_cells()

	# LOD evaluation (throttled)
	if not _all_asteroids.is_empty():
		_lod_timer += delta
		if _lod_timer >= LOD_EVAL_INTERVAL:
			_lod_timer -= LOD_EVAL_INTERVAL
			_evaluate_lod()

	# Respawn check (throttled)
	_respawn_timer += delta
	if _respawn_timer >= RESPAWN_CHECK_INTERVAL:
		_respawn_timer -= RESPAWN_CHECK_INTERVAL
		_tick_respawns()

	# Scan expiry check (throttled)
	_scan_expiry_timer += delta
	if _scan_expiry_timer >= SCAN_EXPIRY_CHECK_INTERVAL:
		_scan_expiry_timer -= SCAN_EXPIRY_CHECK_INTERVAL
		_tick_scan_expiry()


# === Cell Generation ===

func _evaluate_cells() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	var universe_x: float = cam_pos.x + FloatingOrigin.origin_offset_x
	var universe_z: float = cam_pos.z + FloatingOrigin.origin_offset_z

	# Determine which cells should be loaded
	var desired_cells: Dictionary = {}  # Vector2i -> field_idx
	var cell_range: int = ceili(LOAD_RADIUS / CELL_SIZE)
	var player_cell_x: int = floori(universe_x / CELL_SIZE)
	var player_cell_z: int = floori(universe_z / CELL_SIZE)

	for cx in range(player_cell_x - cell_range, player_cell_x + cell_range + 1):
		for cz in range(player_cell_z - cell_range, player_cell_z + cell_range + 1):
			var cell_center_x: float = (cx + 0.5) * CELL_SIZE
			var cell_center_z: float = (cz + 0.5) * CELL_SIZE
			var dx: float = cell_center_x - universe_x
			var dz: float = cell_center_z - universe_z
			if dx * dx + dz * dz > LOAD_RADIUS * LOAD_RADIUS:
				continue

			# Check if cell center falls within any belt ring
			var dist_from_star: float = sqrt(cell_center_x * cell_center_x + cell_center_z * cell_center_z)
			for fi in _fields.size():
				var f: AsteroidFieldData = _fields[fi]
				if absf(dist_from_star - f.orbital_radius) < f.width * 0.5:
					desired_cells[Vector2i(cx, cz)] = fi
					break

	# Unload cells beyond UNLOAD_RADIUS (hysteresis prevents thrashing)
	var cells_to_remove: Array[Vector2i] = []
	for key: Vector2i in _loaded_cells:
		if desired_cells.has(key):
			continue
		var ccx: float = (key.x + 0.5) * CELL_SIZE
		var ccz: float = (key.y + 0.5) * CELL_SIZE
		var dx: float = ccx - universe_x
		var dz: float = ccz - universe_z
		if dx * dx + dz * dz > UNLOAD_RADIUS * UNLOAD_RADIUS:
			cells_to_remove.append(key)

	for key in cells_to_remove:
		_unload_cell(key)

	# Load new cells
	for key: Vector2i in desired_cells:
		if not _loaded_cells.has(key):
			_load_cell(key, desired_cells[key])


func _load_cell(cell: Vector2i, field_idx: int) -> void:
	var field: AsteroidFieldData = _fields[field_idx]

	var rng := RandomNumberGenerator.new()
	# Deterministic seed from system_seed + field_index + cell coords
	rng.seed = _hash_cell(field_idx, cell.x, cell.y)

	var count: int = rng.randi_range(ASTEROIDS_PER_CELL_MIN, ASTEROIDS_PER_CELL_MAX)
	var ids: Array[StringName] = []

	for i in count:
		var id := StringName("ast_%d_%d_%d_%d" % [field_idx, cell.x, cell.y, i])

		# Skip depleted asteroids
		if _depleted_ids.has(id):
			# Still consume RNG draws to keep determinism for subsequent asteroids
			_consume_rng_draws(rng)
			continue

		var asteroid := AsteroidData.new()
		asteroid.id = id
		asteroid.field_id = field.field_id

		# Universe position (deterministic within cell)
		var uni_x: float = (cell.x + rng.randf()) * CELL_SIZE
		var uni_z: float = (cell.y + rng.randf()) * CELL_SIZE
		var vert: float = (rng.randf() - 0.5) * VERTICAL_SPREAD

		# Scene position (subtract floating origin offset)
		asteroid.position = Vector3(
			uni_x - FloatingOrigin.origin_offset_x,
			vert,
			uni_z - FloatingOrigin.origin_offset_z,
		)

		# Rotation
		asteroid.rotation_axis = Vector3(
			rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5
		).normalized()
		asteroid.rotation_speed = rng.randf_range(0.02, 0.15)

		# Size distribution: 60% small, 30% medium, 10% large
		var size_roll: float = rng.randf()
		if size_roll < 0.6:
			asteroid.size = AsteroidData.AsteroidSize.SMALL
		elif size_roll < 0.9:
			asteroid.size = AsteroidData.AsteroidSize.MEDIUM
		else:
			asteroid.size = AsteroidData.AsteroidSize.LARGE

		asteroid.visual_radius = asteroid.get_radius_for_size()
		asteroid.health_max = asteroid.get_health_for_size()
		asteroid.health_current = asteroid.health_max

		# Non-uniform scale for rocky appearance
		asteroid.scale_distort = Vector3(
			rng.randf_range(0.7, 1.3),
			rng.randf_range(0.6, 1.2),
			rng.randf_range(0.7, 1.3),
		)

		# Barren roll: 60% of asteroids have no resource
		var barren_roll: float = rng.randf()
		if barren_roll < SCAN_BARREN_RATE:
			asteroid.has_resource = false
			asteroid.primary_resource = &""

		# Resource distribution: 60% dominant, 25% secondary, 15% rare
		var res_roll: float = rng.randf()
		if asteroid.has_resource:
			if res_roll < 0.60:
				asteroid.primary_resource = field.dominant_resource
			elif res_roll < 0.85:
				asteroid.primary_resource = field.secondary_resource
			else:
				asteroid.primary_resource = field.rare_resource

		# Color: compute true resource_color but display neutral until scanned
		var res := MiningRegistry.get_resource(asteroid.primary_resource) if asteroid.has_resource else null
		if res:
			asteroid.resource_color = Color(
				res.color.r + rng.randf_range(-0.08, 0.08),
				res.color.g + rng.randf_range(-0.08, 0.08),
				res.color.b + rng.randf_range(-0.08, 0.08),
			).clamp()
		else:
			# Consume the 3 RNG draws for barren asteroids to keep determinism
			rng.randf_range(-0.08, 0.08); rng.randf_range(-0.08, 0.08); rng.randf_range(-0.08, 0.08)
			asteroid.resource_color = SCAN_NEUTRAL_COLOR
		asteroid.color_tint = SCAN_NEUTRAL_COLOR

		_all_asteroids[id] = asteroid
		_lod_levels[id] = AsteroidLOD.DATA_ONLY
		_grid.insert(id, asteroid.position, asteroid)
		ids.append(id)

	_loaded_cells[cell] = ids


## Consume RNG draws to keep the sequence aligned (when skipping depleted asteroids).
func _consume_rng_draws(rng: RandomNumberGenerator) -> void:
	# Match the number of randf/randi calls in _load_cell per asteroid
	rng.randf(); rng.randf(); rng.randf()  # pos x, z, vert
	rng.randf(); rng.randf(); rng.randf()  # rotation axis
	rng.randf_range(0.02, 0.15)            # rotation speed
	rng.randf()                             # size
	rng.randf_range(0.7, 1.3); rng.randf_range(0.6, 1.2); rng.randf_range(0.7, 1.3)  # scale
	rng.randf()                             # barren roll
	rng.randf()                             # resource
	rng.randf_range(-0.08, 0.08); rng.randf_range(-0.08, 0.08); rng.randf_range(-0.08, 0.08)  # color


func _unload_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell):
		return
	var ids: Array = _loaded_cells[cell]
	for id: StringName in ids:
		_remove_lod_representation(id)
		_grid.remove(id)
		_lod_levels.erase(id)
		_all_asteroids.erase(id)
	_loaded_cells.erase(cell)
	_dots_dirty = true


func _remove_lod_representation(id: StringName) -> void:
	if _full_nodes.has(id):
		var node: AsteroidNode = _full_nodes[id]
		var asteroid: AsteroidData = _all_asteroids.get(id)
		if asteroid:
			asteroid.node_ref = null
		if is_instance_valid(node):
			node.queue_free()
		_full_nodes.erase(id)
	if _simplified_meshes.has(id):
		var mesh: MeshInstance3D = _simplified_meshes[id]
		if is_instance_valid(mesh):
			mesh.queue_free()
		_simplified_meshes.erase(id)


func _hash_cell(field_idx: int, cx: int, cz: int) -> int:
	# Large primes for hash mixing
	return _system_seed * 73856093 + field_idx * 19349669 + cx * 83492791 + cz * 41234329


# === LOD ===

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
				if current_lod == AsteroidLOD.DOT:
					new_dot_ids.append(id)
				continue
			_transition_lod(id, asteroid, current_lod, target_lod)
			_lod_levels[id] = target_lod
			promotions += 1

			if target_lod == AsteroidLOD.FULL:
				full_count += 1
			elif target_lod == AsteroidLOD.SIMPLIFIED:
				simplified_count += 1
		else:
			if current_lod == AsteroidLOD.DOT:
				new_dot_ids.append(id)

	# Rebuild DOT multimesh if changed
	if new_dot_ids.size() != _dot_ids.size() or _dots_dirty:
		_dot_ids = new_dot_ids
		_rebuild_multimesh()
		_dots_dirty = false


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
	# Connect depleted signal for persistence across cell loads
	node.depleted.connect(_on_node_depleted)
	# Show scan info only if already scanned
	if asteroid.is_scanned and asteroid.has_resource:
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
	var base_col: Color = asteroid.color_tint if asteroid.color_tint != Color.GRAY else Color(0.35, 0.33, 0.3)
	# Darken the color so simplified asteroids look like dark rocks, not bright blobs
	mat.albedo_color = Color(base_col.r * 0.4, base_col.g * 0.4, base_col.b * 0.4)
	if asteroid.is_depleted:
		mat.albedo_color = Color(0.15, 0.15, 0.15, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.95
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


# === Respawns ===

func _tick_respawns() -> void:
	var now: float = Time.get_unix_time_from_system()
	var expired: Array[StringName] = []
	for id: StringName in _depleted_ids:
		if now - _depleted_ids[id] > Constants.ASTEROID_RESPAWN_TIME:
			expired.append(id)
	for id in expired:
		_depleted_ids.erase(id)

	# Respawn loaded depleted asteroids whose timer expired
	for id: StringName in _all_asteroids:
		var asteroid: AsteroidData = _all_asteroids[id]
		if not asteroid.is_depleted:
			continue
		if _depleted_ids.has(id):
			continue
		# Timer expired — respawn
		asteroid.is_depleted = false
		asteroid.health_current = asteroid.health_max
		if _full_nodes.has(id):
			var node: AsteroidNode = _full_nodes[id]
			if is_instance_valid(node):
				node.respawn()


func _on_node_depleted(asteroid_id: StringName) -> void:
	on_asteroid_depleted(asteroid_id)


# === Origin Shift ===

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


# === Scanner Reveal ===

## Reveals asteroids within radius of center. Returns count of resource-bearing asteroids found.
func reveal_asteroids_in_radius(center: Vector3, radius: float) -> int:
	var ids := _grid.query_radius(center, radius)
	var revealed_count: int = 0
	var now: float = Time.get_ticks_msec() / 1000.0

	for id: StringName in ids:
		var ast: AsteroidData = _all_asteroids.get(id)
		if ast == null or ast.is_depleted or ast.is_scanned:
			continue

		ast.is_scanned = true
		ast.scan_expire_time = now + SCAN_REVEAL_DURATION

		if ast.has_resource:
			ast.color_tint = ast.resource_color
			revealed_count += 1
			_update_asteroid_visual(ast, true)
		else:
			_flash_barren_asteroid(ast)

	if revealed_count > 0:
		_dots_dirty = true
	return revealed_count


## Reveal a single asteroid (e.g. when mining it).
func reveal_single_asteroid(ast: AsteroidData) -> void:
	if ast.is_scanned:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	ast.is_scanned = true
	ast.scan_expire_time = now + SCAN_REVEAL_DURATION
	if ast.has_resource:
		ast.color_tint = ast.resource_color
		_update_asteroid_visual(ast, true)
		_dots_dirty = true


func _update_asteroid_visual(ast: AsteroidData, reveal: bool) -> void:
	# FULL LOD — tween the color on the AsteroidNode
	if ast.node_ref and is_instance_valid(ast.node_ref):
		var node := ast.node_ref as AsteroidNode
		if reveal:
			node.apply_scan_reveal(ast)
		else:
			node.apply_scan_expire()
	# SIMPLIFIED LOD — update material directly
	if _simplified_meshes.has(ast.id):
		var mesh: MeshInstance3D = _simplified_meshes[ast.id]
		if is_instance_valid(mesh) and mesh.material_override:
			var mat: StandardMaterial3D = mesh.material_override
			var col: Color = ast.color_tint
			mat.albedo_color = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4)


func _flash_barren_asteroid(ast: AsteroidData) -> void:
	if ast.node_ref and is_instance_valid(ast.node_ref):
		var node := ast.node_ref as AsteroidNode
		node.flash_barren()


func _tick_scan_expiry() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var any_expired: bool = false

	for id: StringName in _all_asteroids:
		var ast: AsteroidData = _all_asteroids[id]
		if not ast.is_scanned:
			continue
		if ast.scan_expire_time > 0.0 and now >= ast.scan_expire_time:
			ast.is_scanned = false
			ast.scan_expire_time = 0.0
			ast.color_tint = SCAN_NEUTRAL_COLOR
			_update_asteroid_visual(ast, false)
			any_expired = true

	if any_expired:
		_dots_dirty = true
