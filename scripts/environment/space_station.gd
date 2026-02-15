class_name SpaceStation
extends StaticBody3D

# =============================================================================
# Space Station — Babbage Station model with blast doors that open on approach,
# navigation lights, bay interior lighting, and slow ring rotation.
# =============================================================================

signal ship_entered_bay(ship: Node3D)
signal ship_exited_bay(ship: Node3D)

@export var station_name: String = "Alpha Station"
@export var station_type: int = 0  # StationData.StationType value

var structure_health = null
var weapon_manager = null
var station_equipment = null
var defense_ai = null

# --- Internal refs ---
var _model: Node3D = null
var _bay_area: Area3D = null
var _ring_nodes: Array[Node3D] = []
var _nav_lights: Array[OmniLight3D] = []
var _light_time: float = 0.0

# --- Bay geometry (model-local coords, pre-scale) ---
const BAY_OPENING_Y: float = 441.0
const BAY_RADIUS: float = 688.0

# Inner bay box half-extents (model-local)
const BAY_BOX_HALF: Vector3 = Vector3(500.0, 600.0, 500.0)
const BAY_CENTER_Y: float = 150.0
const LANDING_POS: Vector3 = Vector3(0.0, 308.0, 0.0)

# Ring rotation speed (radians per second)
const RING_ROTATION_SPEED: float = 0.03


func _ready() -> void:
	collision_layer = Constants.LAYER_STATIONS
	collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_PROJECTILES
	add_to_group("structures")

	structure_health = StructureHealth.new()
	structure_health.name = "StructureHealth"
	structure_health.apply_preset(station_type)
	add_child(structure_health)

	var death_handler = StructureDeathHandler.new()
	death_handler.name = "StructureDeathHandler"
	add_child(death_handler)

	await _load_model()
	_build_bay_area()
	_build_lights()
	_find_ring_nodes()

	if station_equipment == null:
		station_equipment = StationEquipment.create_empty(name, station_type)
	StationFactory.setup_station(self, station_equipment)


func _process(delta: float) -> void:
	# Slow ring rotation
	for ring in _ring_nodes:
		if is_instance_valid(ring):
			ring.rotate_y(RING_ROTATION_SPEED * delta)

	# Blinking red nav lights
	_light_time += delta
	var blink: float = 0.5 + 0.5 * sin(_light_time * 2.5)
	for nav in _nav_lights:
		if is_instance_valid(nav):
			nav.light_energy = 1.0 + blink * 2.0


func _load_model() -> void:
	var scene: PackedScene = load("res://assets/models/babbage_station.glb")
	if scene == null:
		push_warning("SpaceStation: Could not load Babbage model, using fallback")
		_build_fallback()
		return

	_model = scene.instantiate()
	add_child(_model)

	await get_tree().process_frame

	for child in _get_all_children(_model):
		if child is MeshInstance3D and child.mesh != null:
			_create_trimesh_collision(child)


func _find_ring_nodes() -> void:
	if _model == null:
		return
	for child in _model.get_children():
		var cname: String = child.name.to_lower()
		if "ring" in cname and "big" in cname:
			_ring_nodes.append(child)
		elif "ring" in cname and "small" in cname:
			_ring_nodes.append(child)




# =========================================================================
# LIGHTS — Docking Bay interior + Navigation
# =========================================================================

func _build_lights() -> void:
	# --- BAY INTERIOR — heavy flood lighting (Pic3 reference: bright lit bay) ---
	_add_light(Vector3(0, 350, 0), Color(0.75, 0.85, 1.0), 12.0, 3000.0)
	_add_light(Vector3(0, 200, 0), Color(0.7, 0.82, 1.0), 10.0, 2500.0)
	_add_light(Vector3(0, 0, 0), Color(0.65, 0.78, 1.0), 10.0, 2500.0)
	_add_light(Vector3(0, -300, 0), Color(0.6, 0.75, 0.95), 8.0, 2000.0)
	_add_light(Vector3(0, -700, 0), Color(0.5, 0.65, 0.9), 6.0, 1800.0)

	# Wall-mounted fill lights around the bay cylinder (4 sides x 3 depths)
	for depth_y in [250, -100, -500]:
		var wall_r: float = BAY_RADIUS * 0.7
		var e: float = 5.0 if depth_y > 0 else 3.5
		_add_light(Vector3(wall_r, depth_y, 0), Color(0.6, 0.75, 1.0), e, 1200.0)
		_add_light(Vector3(-wall_r, depth_y, 0), Color(0.6, 0.75, 1.0), e, 1200.0)
		_add_light(Vector3(0, depth_y, wall_r), Color(0.6, 0.75, 1.0), e, 1200.0)
		_add_light(Vector3(0, depth_y, -wall_r), Color(0.6, 0.75, 1.0), e, 1200.0)

	# --- GREEN LANDING GUIDE LIGHTS (Pic3: bright green spots) ---
	var green = Color(0.1, 1.0, 0.2)
	_add_light(Vector3(500, 380, 0), green, 4.0, 800.0)
	_add_light(Vector3(-500, 380, 0), green, 4.0, 800.0)
	_add_light(Vector3(0, 380, 500), green, 4.0, 800.0)
	_add_light(Vector3(0, 380, -500), green, 4.0, 800.0)
	_add_light(Vector3(400, 100, 0), green, 2.5, 500.0)
	_add_light(Vector3(-400, 100, 0), green, 2.5, 500.0)

	# --- RED NAV LIGHTS around hangar exterior ---
	var red = Color(1.0, 0.15, 0.05)
	for i in 8:
		var angle: float = i * TAU / 8.0
		var r: float = BAY_RADIUS + 80.0
		var pos = Vector3(cos(angle) * r, BAY_OPENING_Y + 30.0, sin(angle) * r)
		var nav = _add_light(pos, red, 2.0, 600.0)
		_nav_lights.append(nav)

	for i in 4:
		var y: float = BAY_OPENING_Y - 400.0 * (i + 1)
		var nav1 = _add_light(Vector3(BAY_RADIUS + 50, y, 0), red, 1.5, 500.0)
		var nav2 = _add_light(Vector3(-BAY_RADIUS - 50, y, 0), red, 1.5, 500.0)
		_nav_lights.append(nav1)
		_nav_lights.append(nav2)

	# --- WHITE NAV LIGHTS on extremities ---
	var white = Color(1.0, 1.0, 0.9)
	_add_light(Vector3(0, -3800, 0), white, 4.0, 2000.0)
	_add_light(Vector3(2500, -1500, 0), white, 3.0, 1000.0)
	_add_light(Vector3(-2500, -1500, 0), white, 3.0, 1000.0)
	_add_light(Vector3(0, -1500, 2500), white, 3.0, 1000.0)
	_add_light(Vector3(0, -1500, -2500), white, 3.0, 1000.0)

	# --- ORANGE ACCENT LIGHTS on ring bands ---
	var orange = Color(1.0, 0.5, 0.1)
	_add_light(Vector3(0, -650, 2100), orange, 2.0, 800.0)
	_add_light(Vector3(0, -650, -2100), orange, 2.0, 800.0)
	_add_light(Vector3(2100, -650, 0), orange, 2.0, 800.0)
	_add_light(Vector3(-2100, -650, 0), orange, 2.0, 800.0)


func _add_light(pos: Vector3, color: Color, energy: float, range_val: float) -> OmniLight3D:
	var light = OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_val
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	add_child(light)
	return light


# =========================================================================
# AREA3D ZONES
# =========================================================================

func _build_bay_area() -> void:
	_bay_area = Area3D.new()
	_bay_area.name = "BayArea"
	_bay_area.collision_layer = 0
	_bay_area.collision_mask = Constants.LAYER_SHIPS
	_bay_area.monitoring = true
	_bay_area.monitorable = false
	_bay_area.position = Vector3(0, BAY_CENTER_Y, 0)

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = BAY_BOX_HALF * 2.0
	col.shape = shape
	_bay_area.add_child(col)
	add_child(_bay_area)

	_bay_area.body_entered.connect(_on_bay_body_entered)
	_bay_area.body_exited.connect(_on_bay_body_exited)


# =========================================================================
# CALLBACKS
# =========================================================================

func _on_bay_body_entered(body: Node3D) -> void:
	if body.is_in_group("ships"):
		ship_entered_bay.emit(body)


func _on_bay_body_exited(body: Node3D) -> void:
	if body.is_in_group("ships"):
		ship_exited_bay.emit(body)


# =========================================================================
# COLLISION
# =========================================================================

func _create_trimesh_collision(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return

	var rel_transform: Transform3D = global_transform.affine_inverse() * mesh_instance.global_transform
	var transformed_faces = PackedVector3Array()
	transformed_faces.resize(faces.size())
	for i in range(faces.size()):
		transformed_faces[i] = rel_transform * faces[i]

	var shape = ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(transformed_faces)

	var col = CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _get_all_children(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_children(child))
	return result


func _build_fallback() -> void:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(50, 20, 50)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4)
	mat.metallic = 0.7
	mesh.material_override = mat
	add_child(mesh)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	add_child(col)


## Returns the bay exit in global coordinates (for undock positioning)
func get_bay_exit_global() -> Vector3:
	var exit_local = Vector3(0, BAY_OPENING_Y + 200.0, 0)
	return global_transform * exit_local


## Returns the landing platform position in global coordinates
func get_landing_pos_global() -> Vector3:
	return global_transform * LANDING_POS
