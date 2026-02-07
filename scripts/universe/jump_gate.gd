class_name JumpGate
extends StaticBody3D

# =============================================================================
# Jump Gate - Interactable ring that transports player to another star system.
# Placed at system edge by SystemTransition, oriented toward connected system.
# =============================================================================

signal gate_entered(target_system_id: int)

var target_system_id: int = -1
var target_system_name: String = ""
var gate_name: String = ""

var _ring_mesh: MeshInstance3D = null
var _trigger_area: Area3D = null
var _label: Label3D = null
var _material: StandardMaterial3D = null
var _spin_speed: float = 10.0  # degrees/sec


func _ready() -> void:
	collision_layer = Constants.LAYER_STATIONS
	collision_mask = 0

	_build_ring()
	_build_trigger()
	_build_label()


func _build_ring() -> void:
	# Outer ring (torus)
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "RingMesh"
	var torus := TorusMesh.new()
	torus.inner_radius = 45.0
	torus.outer_radius = 55.0
	torus.rings = 32
	torus.ring_segments = 16
	_ring_mesh.mesh = torus

	# Emissive material (holographic blue)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.1, 0.5, 0.9, 0.8)
	_material.emission_enabled = true
	_material.emission = Color(0.15, 0.6, 1.0)
	_material.emission_energy_multiplier = 2.5
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mesh.material_override = _material

	add_child(_ring_mesh)

	# Collision for the ring body (box approximation)
	var col_shape := CollisionShape3D.new()
	col_shape.name = "RingCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(110.0, 20.0, 110.0)
	col_shape.shape = box
	add_child(col_shape)


func _build_trigger() -> void:
	# Inner trigger zone - player enters this to initiate jump
	_trigger_area = Area3D.new()
	_trigger_area.name = "GateTrigger"
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = Constants.LAYER_SHIPS

	var trigger_shape := CollisionShape3D.new()
	trigger_shape.name = "TriggerShape"
	var sphere := SphereShape3D.new()
	sphere.radius = 40.0
	trigger_shape.shape = sphere
	_trigger_area.add_child(trigger_shape)

	_trigger_area.body_entered.connect(_on_body_entered)
	add_child(_trigger_area)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "GateLabel"
	_label.text = gate_name if gate_name != "" else "JUMP GATE"
	_label.font_size = 32
	_label.modulate = Color(0.3, 0.85, 1.0, 0.9)
	_label.outline_modulate = Color(0.0, 0.1, 0.2, 0.8)
	_label.outline_size = 4
	_label.position = Vector3(0, 70, 0)
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


func _process(delta: float) -> void:
	# Slow spin animation
	if _ring_mesh:
		_ring_mesh.rotate_y(deg_to_rad(_spin_speed * delta))

	# Pulse emission
	if _material:
		var pulse: float = (sin(Time.get_ticks_msec() * 0.002) + 1.0) * 0.5
		_material.emission_energy_multiplier = 1.5 + pulse * 2.0


func _on_body_entered(body: Node3D) -> void:
	# Only the player ship triggers the gate
	if body == GameManager.player_ship:
		gate_entered.emit(target_system_id)
