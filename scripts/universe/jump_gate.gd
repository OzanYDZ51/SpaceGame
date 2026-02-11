class_name JumpGate
extends StaticBody3D

# =============================================================================
# Jump Gate - Interactable ring that transports player to another star system.
# Placed at system edge by SystemTransition, oriented toward connected system.
# Uses proximity detection: player enters trigger → HUD prompt → J key to jump.
# =============================================================================

signal player_nearby(target_system_id: int, target_system_name: String)
signal player_left()

@export var ring_inner_radius: float = 45.0
@export var ring_outer_radius: float = 55.0
@export var trigger_radius: float = 80.0
@export var emission_color: Color = Color(0.15, 0.6, 1.0)
@export var spin_speed: float = 10.0

var target_system_id: int = -1
var target_system_name: String = ""
var gate_name: String = ""

var _ring_mesh: MeshInstance3D = null
var _trigger_area: Area3D = null
var _label: Label3D = null
var _material: StandardMaterial3D = null
var _player_inside: bool = false


func _ready() -> void:
	collision_layer = Constants.LAYER_STATIONS
	collision_mask = 0

	_build_ring()
	_build_trigger()
	_build_label()


func _build_ring() -> void:
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "RingMesh"
	var torus := TorusMesh.new()
	torus.inner_radius = ring_inner_radius
	torus.outer_radius = ring_outer_radius
	torus.rings = 32
	torus.ring_segments = 16
	_ring_mesh.mesh = torus

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(emission_color.r, emission_color.g, emission_color.b, 0.8)
	_material.emission_enabled = true
	_material.emission = emission_color
	_material.emission_energy_multiplier = 2.5
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mesh.material_override = _material

	add_child(_ring_mesh)

	# Collision for the ring body (box approximation)
	var col_shape := CollisionShape3D.new()
	col_shape.name = "RingCollision"
	var box := BoxShape3D.new()
	var diameter: float = ring_outer_radius * 2.0
	box.size = Vector3(diameter, 20.0, diameter)
	col_shape.shape = box
	add_child(col_shape)


func _build_trigger() -> void:
	_trigger_area = Area3D.new()
	_trigger_area.name = "GateTrigger"
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = Constants.LAYER_SHIPS

	var trigger_shape := CollisionShape3D.new()
	trigger_shape.name = "TriggerShape"
	var sphere := SphereShape3D.new()
	sphere.radius = trigger_radius
	trigger_shape.shape = sphere
	_trigger_area.add_child(trigger_shape)

	_trigger_area.body_entered.connect(_on_body_entered)
	_trigger_area.body_exited.connect(_on_body_exited)
	add_child(_trigger_area)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "GateLabel"
	_label.text = gate_name if gate_name != "" else "JUMP GATE"
	_label.font_size = 32
	_label.modulate = Color(emission_color.r, emission_color.g, emission_color.b, 0.9)
	_label.outline_modulate = Color(0.0, 0.1, 0.2, 0.8)
	_label.outline_size = 4
	_label.position = Vector3(0, ring_outer_radius + 15, 0)
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


## Setup from typed JumpGateData resource.
func setup_from_data(data: JumpGateData) -> void:
	target_system_id = data.target_system_id
	target_system_name = data.target_system_name
	gate_name = data.gate_name
	global_position = Vector3(data.pos_x, data.pos_y, data.pos_z)

	if _label:
		_label.text = gate_name


func _process(delta: float) -> void:
	if _ring_mesh:
		_ring_mesh.rotate_y(deg_to_rad(spin_speed * delta))

	if _material:
		var pulse: float = (sin(Time.get_ticks_msec() * 0.002) + 1.0) * 0.5
		_material.emission_energy_multiplier = 1.5 + pulse * 2.0


func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.player_ship:
		_player_inside = true
		player_nearby.emit(target_system_id, target_system_name)


func _on_body_exited(body: Node3D) -> void:
	if body == GameManager.player_ship:
		_player_inside = false
		player_left.emit()
