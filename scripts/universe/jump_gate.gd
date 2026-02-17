class_name JumpGate
extends Node3D

# =============================================================================
# Jump Gate - Inter-system portal with blue vortex activation.
# Gate2.0 GLB model: 3 surfaces
#   0: "ScdGate"     — Portal disc (flat, blue emission 15.3)
#   1: "Material"    — Gate body (PBR metallic, textured)
#   2: "Materiau.003" — Light panels (emissive texture)
#
# The portal disc is always partially visible. It intensifies when the player
# approaches. Jumping happens by flying through the gate.
# =============================================================================

signal player_nearby(target_system_id: int, target_system_name: String)
signal player_left()
signal auto_jump_requested(target_system_id: int)

@export var trigger_radius: float = 2000.0
@export var vortex_activation_radius: float = 3000.0
@export var emission_color: Color = Color(0.15, 0.6, 1.0)

const GATE_MODEL_PATH: String = "res://assets/models/gate_new.glb"
const MODEL_SCALE: float = 5.0
# Model center is at (-4.4, 167.7, -113.8) in model space — compensate.
const MODEL_OFFSET: Vector3 = Vector3(4.4, -167.7, 113.8)

# Portal disc is ~196m raw → ~980m at scale 5.
# Tunnel detection volume (world-space units after scale).
const TUNNEL_RADIUS: float = 500.0
const TUNNEL_HALF_DEPTH: float = 400.0
const AUTO_JUMP_TIME: float = 0.3  # Near-instant: portal disc is thin

# Vortex emission levels (portal disc surface)
const VORTEX_BASE_EMISSION: float = 4.0    # Dim but visible blue glow
const VORTEX_ACTIVE_EMISSION: float = 16.0  # Full power (Blender was 15.3)

var target_system_id: int = -1
var target_system_name: String = ""
var gate_name: String = ""

var _model_pivot: Node3D = null
var _label: Label3D = null
var _portal_material: StandardMaterial3D = null  # Surface 0 (ScdGate)
var _player_inside: bool = false
var _inside_tunnel: bool = false
var _tunnel_timer: float = 0.0
var _jump_triggered: bool = false
var _auto_jump_cooldown: float = 4.0  # Prevent re-jump on arrival
var _vortex_active: bool = false
var _vortex_intensity: float = 0.0  # 0 = dim base, 1 = full active
var _vortex_tween: Tween = null


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

	# Find ALL MeshInstance3D nodes
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model, meshes)

	if meshes.is_empty():
		push_warning("JumpGate: No MeshInstance3D found in gate model")
		return

	for mesh_inst in meshes:
		if mesh_inst.mesh == null:
			continue
		var surf_count: int = mesh_inst.mesh.get_surface_count()

		for surf_idx in surf_count:
			var mat = mesh_inst.mesh.surface_get_material(surf_idx)
			if mat == null or not mat is StandardMaterial3D:
				continue

			var sm: StandardMaterial3D = mat as StandardMaterial3D

			# Surface 0 "ScdGate": portal disc — very high emission (15.3)
			if sm.emission_enabled and sm.emission_energy_multiplier > 10.0:
				_setup_portal_surface(mesh_inst, surf_idx, sm)
			# Surface 1 "Material": gate body — has textures, metallic
			elif sm.metallic > 0.5:
				_setup_body_surface(mesh_inst, surf_idx, sm)
			# Surface 2 "Materiau.003": light panels — emissive texture
			# Keep as-is, no override needed


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)


func _setup_portal_surface(mesh_inst: MeshInstance3D, surf_idx: int, mat: StandardMaterial3D) -> void:
	_portal_material = mat.duplicate() as StandardMaterial3D
	# Start at dim base emission — portal always slightly glows
	_portal_material.emission_energy_multiplier = VORTEX_BASE_EMISSION
	mesh_inst.set_surface_override_material(surf_idx, _portal_material)


func _setup_body_surface(mesh_inst: MeshInstance3D, surf_idx: int, mat: StandardMaterial3D) -> void:
	# Add a subtle blue emission accent to the metallic structure
	var sm: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	sm.emission_enabled = true
	sm.emission = Color(emission_color.r * 0.1, emission_color.g * 0.1, emission_color.b * 0.1)
	sm.emission_energy_multiplier = 0.3
	mesh_inst.set_surface_override_material(surf_idx, sm)


func _build_lights() -> void:
	var portal_light := OmniLight3D.new()
	portal_light.name = "PortalLight"
	portal_light.light_color = emission_color
	portal_light.light_energy = 5.0
	portal_light.omni_range = 1500.0
	portal_light.omni_attenuation = 1.5
	portal_light.position = Vector3.ZERO
	add_child(portal_light)

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


func setup_from_data(data: JumpGateData) -> void:
	target_system_id = data.target_system_id
	target_system_name = data.target_system_name
	gate_name = data.gate_name
	global_position = Vector3(data.pos_x, data.pos_y, data.pos_z)
	if _label:
		_label.text = gate_name
	_orient_toward_center()


func _orient_toward_center() -> void:
	if global_position.length_squared() > 1.0:
		look_at(Vector3.ZERO, Vector3.UP)


# --- Vortex activation ---

func _activate_vortex() -> void:
	if _vortex_active or _portal_material == null:
		return
	_vortex_active = true
	if _vortex_tween:
		_vortex_tween.kill()
	_vortex_tween = create_tween()
	_vortex_tween.tween_property(self, "_vortex_intensity", 1.0, 1.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _deactivate_vortex() -> void:
	if not _vortex_active or _portal_material == null:
		return
	_vortex_active = false
	if _vortex_tween:
		_vortex_tween.kill()
	_vortex_tween = create_tween()
	_vortex_tween.tween_property(self, "_vortex_intensity", 0.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


# --- Frame updates ---

func _process(_delta: float) -> void:
	if _portal_material == null:
		return

	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = (sin(t * 2.0) + 1.0) * 0.5

	# Interpolate emission between base (dim) and active (full Blender intensity)
	var emission_e: float = lerpf(VORTEX_BASE_EMISSION, VORTEX_ACTIVE_EMISSION, _vortex_intensity)
	# Add pulse (subtle when dim, strong when active)
	emission_e += pulse * lerpf(0.5, 3.0, _vortex_intensity)
	_portal_material.emission_energy_multiplier = emission_e


func _physics_process(delta: float) -> void:
	if _auto_jump_cooldown > 0.0:
		_auto_jump_cooldown -= delta

	var ship = GameManager.player_ship
	if ship == null:
		return

	var dist_sq: float = global_position.distance_squared_to(ship.global_position)

	# --- Vortex intensifies on approach ---
	if dist_sq <= vortex_activation_radius * vortex_activation_radius:
		_activate_vortex()
	elif _vortex_active:
		_deactivate_vortex()

	# --- Proximity detection (HUD prompt) ---
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

	# --- Tunnel detection (auto-jump when flying through) ---
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
