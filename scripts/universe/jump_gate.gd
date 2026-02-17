class_name JumpGate
extends Node3D

# =============================================================================
# Jump Gate - Inter-system portal with blue vortex activation.
# New GLB model with integrated vortex mesh. The vortex activates when the
# player approaches, and jumping happens by flying through the gate.
# The wider end of the tunnel always faces the star (system center).
# =============================================================================

signal player_nearby(target_system_id: int, target_system_name: String)
signal player_left()
signal auto_jump_requested(target_system_id: int)

@export var trigger_radius: float = 2000.0
@export var vortex_activation_radius: float = 3000.0
@export var emission_color: Color = Color(0.15, 0.6, 1.0)

const GATE_MODEL_PATH: String = "res://assets/models/gate_new.glb"
const MODEL_SCALE: float = 5.0
const MODEL_OFFSET: Vector3 = Vector3.ZERO

# Tunnel auto-jump detection (world-space units at MODEL_SCALE)
const TUNNEL_RADIUS: float = 800.0
const TUNNEL_HALF_DEPTH: float = 1000.0
const AUTO_JUMP_TIME: float = 1.5

# Vortex intensity levels
const VORTEX_BASE_ALPHA: float = 0.12
const VORTEX_BASE_EMISSION: float = 1.5
const VORTEX_ACTIVE_ALPHA: float = 0.6
const VORTEX_ACTIVE_EMISSION: float = 5.0

var target_system_id: int = -1
var target_system_name: String = ""
var gate_name: String = ""

var _model_pivot: Node3D = null
var _label: Label3D = null
var _vortex_materials: Array[StandardMaterial3D] = []  # All vortex surfaces
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

	# Find ALL MeshInstance3D nodes in the model tree
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model, meshes)

	if meshes.is_empty():
		push_warning("JumpGate: No MeshInstance3D found in gate model")
		return

	print("JumpGate: Found %d mesh instance(s)" % meshes.size())

	# Leave all original materials as-is. Only identify vortex surfaces
	# (those that already have alpha transparency in the GLB) for animation.
	for mesh_inst in meshes:
		if mesh_inst.mesh == null:
			continue
		var surf_count: int = mesh_inst.mesh.get_surface_count()
		print("  Mesh '%s': %d surface(s)" % [mesh_inst.name, surf_count])

		for surf_idx in surf_count:
			var mat = mesh_inst.mesh.surface_get_material(surf_idx)
			if mat == null:
				continue

			var is_vortex: bool = _is_vortex_surface(mat)
			print("    Surface %d: '%s' (%s) transp=%d emit=%s cull=%d -> %s" % [
				surf_idx, mat.resource_name, mat.get_class(),
				mat.transparency if mat is StandardMaterial3D else -1,
				str(mat.emission_energy_multiplier) if mat is StandardMaterial3D and mat.emission_enabled else "off",
				mat.cull_mode if mat is StandardMaterial3D else -1,
				"VORTEX" if is_vortex else "structure"])

			if is_vortex:
				_setup_vortex_surface(mesh_inst, surf_idx, mat)


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)


func _is_vortex_surface(mat: Material) -> bool:
	# Only match surfaces that ALREADY have alpha transparency in the GLB.
	# This avoids turning opaque structure surfaces into transparent ones.
	if mat is StandardMaterial3D:
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH \
				or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			return true
	return false


func _setup_vortex_surface(mesh_inst: MeshInstance3D, surf_idx: int, mat: Material) -> void:
	if not mat is StandardMaterial3D:
		return
	# Duplicate the original material and just hook into emission for animation
	var vm: StandardMaterial3D = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	vm.emission_enabled = true
	vm.emission = emission_color
	vm.emission_energy_multiplier = VORTEX_BASE_EMISSION
	mesh_inst.set_surface_override_material(surf_idx, vm)
	_vortex_materials.append(vm)


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
	if _vortex_active or _vortex_materials.is_empty():
		return
	_vortex_active = true
	if _vortex_tween:
		_vortex_tween.kill()
	_vortex_tween = create_tween()
	_vortex_tween.tween_property(self, "_vortex_intensity", 1.0, 1.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _deactivate_vortex() -> void:
	if not _vortex_active or _vortex_materials.is_empty():
		return
	_vortex_active = false
	if _vortex_tween:
		_vortex_tween.kill()
	_vortex_tween = create_tween()
	_vortex_tween.tween_property(self, "_vortex_intensity", 0.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


# --- Frame updates ---

func _process(_delta: float) -> void:
	if _vortex_materials.is_empty():
		return

	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = (sin(t * 2.0) + 1.0) * 0.5

	# Interpolate between base and active states
	var alpha: float = lerpf(VORTEX_BASE_ALPHA, VORTEX_ACTIVE_ALPHA, _vortex_intensity)
	var emission_e: float = lerpf(VORTEX_BASE_EMISSION, VORTEX_ACTIVE_EMISSION, _vortex_intensity)
	# Add pulse modulation (stronger when active)
	var pulse_strength: float = lerpf(0.3, 2.0, _vortex_intensity)
	emission_e += pulse * pulse_strength

	for vm in _vortex_materials:
		vm.albedo_color.a = alpha + pulse * 0.05 * (1.0 + _vortex_intensity)
		vm.emission_energy_multiplier = emission_e


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

	# Debug: print tunnel detection values every ~1s
	if Engine.get_physics_frames() % 60 == 0:
		print("JumpGate tunnel: dist=%.0f radial=%.0f depth=%.0f inside=%s in_tunnel=%s timer=%.1f cooldown=%.1f" % [
			sqrt(dist_sq), radial_dist, depth, _player_inside, in_tunnel, _tunnel_timer, _auto_jump_cooldown])

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
