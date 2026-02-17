class_name JumpGate
extends Node3D

# =============================================================================
# Jump Gate - Massive tunnel-shaped portal for inter-system travel.
# Custom gate.glb model with animated portal energy, lighting effects, and
# automatic jump when the player flies through the tunnel for 3 seconds.
# The wider end of the tunnel always faces the star (system center).
# =============================================================================

signal player_nearby(target_system_id: int, target_system_name: String)
signal player_left()
signal auto_jump_requested(target_system_id: int)

@export var trigger_radius: float = 2000.0
@export var emission_color: Color = Color(0.15, 0.6, 1.0)

const GATE_MODEL_PATH: String = "res://assets/models/gate.glb"
const MODEL_SCALE: float = 5.0
# Offset to center the portal opening at the node's origin.
# Portal energy field (prim 1) center is at (-6.2, 166.5, -82.7) in model space.
const MODEL_OFFSET: Vector3 = Vector3(6.2, -166.5, 82.7)

# Tunnel auto-jump detection (world-space units at scale 5.0)
const TUNNEL_RADIUS: float = 450.0
const TUNNEL_HALF_DEPTH: float = 600.0
const AUTO_JUMP_TIME: float = 3.0

var target_system_id: int = -1
var target_system_name: String = ""
var gate_name: String = ""

var _model_pivot: Node3D = null
var _label: Label3D = null
var _portal_material: StandardMaterial3D = null
var _player_inside: bool = false
var _inside_tunnel: bool = false
var _tunnel_timer: float = 0.0
var _jump_triggered: bool = false
var _auto_jump_cooldown: float = 4.0  # Prevent re-jump on arrival


func _ready() -> void:
	_build_model()
	_build_lights()
	_build_label()


func _build_model() -> void:
	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	_model_pivot.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	add_child(_model_pivot)

	var scene: PackedScene = load(GATE_MODEL_PATH)
	if scene == null:
		push_error("JumpGate: Failed to load gate model: " + GATE_MODEL_PATH)
		return

	var model: Node3D = scene.instantiate()
	model.name = "GateModel"
	model.position = MODEL_OFFSET
	_model_pivot.add_child(model)

	# Find the MeshInstance3D and set up materials
	var mesh_instance: MeshInstance3D = _find_mesh_instance(model)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	var surf_count: int = mesh_instance.mesh.get_surface_count()

	# Portal energy field (surface 1) — animated emission + transparency
	if surf_count > 1:
		var mat = mesh_instance.mesh.surface_get_material(1)
		if mat is StandardMaterial3D:
			_portal_material = mat.duplicate() as StandardMaterial3D
			_portal_material.albedo_color = Color(emission_color.r, emission_color.g, emission_color.b, 0.3)
			_portal_material.emission_enabled = true
			_portal_material.emission = emission_color
			_portal_material.emission_energy_multiplier = 3.0
			_portal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_portal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.set_surface_override_material(1, _portal_material)

	# Structure materials (surfaces 0, 2, 3) — subtle powered glow
	for surf_idx in [0, 2, 3]:
		if surf_idx < surf_count:
			var struct_mat = mesh_instance.mesh.surface_get_material(surf_idx)
			if struct_mat is StandardMaterial3D:
				var sm: StandardMaterial3D = struct_mat.duplicate() as StandardMaterial3D
				sm.emission_enabled = true
				sm.emission = Color(emission_color.r * 0.2, emission_color.g * 0.2, emission_color.b * 0.2)
				sm.emission_energy_multiplier = 0.4
				mesh_instance.set_surface_override_material(surf_idx, sm)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance(child)
		if found:
			return found
	return null


func _build_lights() -> void:
	# Central portal glow — large omni illuminating the tunnel interior
	var portal_light := OmniLight3D.new()
	portal_light.name = "PortalLight"
	portal_light.light_color = emission_color
	portal_light.light_energy = 5.0
	portal_light.omni_range = 1500.0
	portal_light.omni_attenuation = 1.5
	portal_light.position = Vector3.ZERO
	add_child(portal_light)

	# Accent lights around the ring (4 cardinal positions)
	var accent_r: float = 400.0
	for i in 4:
		var angle: float = float(i) * TAU / 4.0
		var light := OmniLight3D.new()
		light.name = "AccentLight_%d" % i
		light.light_color = Color(emission_color.r * 0.6, emission_color.g * 0.6, emission_color.b * 0.6)
		light.light_energy = 2.0
		light.omni_range = 600.0
		light.omni_attenuation = 1.5
		light.position = Vector3(cos(angle) * accent_r, sin(angle) * accent_r, 0.0)
		add_child(light)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "GateLabel"
	_label.text = gate_name if gate_name != "" else "JUMP GATE"
	_label.font_size = 64
	_label.modulate = Color(emission_color.r, emission_color.g, emission_color.b, 0.9)
	_label.outline_modulate = Color(0.0, 0.1, 0.2, 0.8)
	_label.outline_size = 8
	_label.position = Vector3(0, 850, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)


func setup(data: Dictionary) -> void:
	target_system_id = data["target_system_id"]
	target_system_name = data.get("target_system_name", "Unknown")
	gate_name = data["name"]
	global_position = Vector3(data["pos_x"], data["pos_y"], data["pos_z"])
	if _label:
		_label.text = gate_name
	_orient_toward_center()


## Setup from typed JumpGateData resource.
func setup_from_data(data: JumpGateData) -> void:
	target_system_id = data.target_system_id
	target_system_name = data.target_system_name
	gate_name = data.gate_name
	global_position = Vector3(data.pos_x, data.pos_y, data.pos_z)
	if _label:
		_label.text = gate_name
	_orient_toward_center()


func _orient_toward_center() -> void:
	# The wider end of the tunnel (model -Z) faces the star at system center.
	# look_at makes -Z point toward the target, which is exactly what we want.
	if global_position.length_squared() > 1.0:
		look_at(Vector3.ZERO, Vector3.UP)


func _process(_delta: float) -> void:
	if _portal_material == null:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = (sin(t * 2.0) + 1.0) * 0.5
	_portal_material.emission_energy_multiplier = 2.0 + pulse * 3.0
	_portal_material.albedo_color.a = 0.15 + pulse * 0.2


func _physics_process(delta: float) -> void:
	if _auto_jump_cooldown > 0.0:
		_auto_jump_cooldown -= delta

	var ship = GameManager.player_ship
	if ship == null:
		return

	var dist_sq: float = global_position.distance_squared_to(ship.global_position)

	# --- Proximity detection (HUD prompt: "SAUT [J]") ---
	var inside: bool = dist_sq <= trigger_radius * trigger_radius
	if inside and not _player_inside:
		_player_inside = true
		player_nearby.emit(target_system_id, target_system_name)
	elif not inside and _player_inside:
		_player_inside = false
		_inside_tunnel = false
		_tunnel_timer = 0.0
		_jump_triggered = false
		player_left.emit()

	# --- Tunnel detection (auto-jump after 3 seconds inside) ---
	if not _player_inside or _jump_triggered or _auto_jump_cooldown > 0.0:
		return

	var rel: Vector3 = ship.global_position - global_position
	var tunnel_axis: Vector3 = -global_transform.basis.z
	var depth: float = rel.dot(tunnel_axis)
	var lateral: Vector3 = rel - tunnel_axis * depth
	var radial_dist: float = lateral.length()

	var in_tunnel: bool = radial_dist < TUNNEL_RADIUS and absf(depth) < TUNNEL_HALF_DEPTH

	if in_tunnel:
		if not _inside_tunnel:
			_inside_tunnel = true
			_tunnel_timer = 0.0
		_tunnel_timer += delta
		if _tunnel_timer >= AUTO_JUMP_TIME:
			_jump_triggered = true
			auto_jump_requested.emit(target_system_id)
	else:
		_inside_tunnel = false
		_tunnel_timer = 0.0
