class_name WormholeGate
extends StaticBody3D

# =============================================================================
# Wormhole Gate - Interstellar portal to another galaxy (different server).
# Same pattern as JumpGate but with distinct purple/magenta visual and
# different destination: a different galaxy seed + server IP.
# =============================================================================

signal player_nearby_wormhole(target_name: String)
signal player_left_wormhole()

@export var ring_inner_radius: float = 60.0
@export var ring_outer_radius: float = 75.0
@export var trigger_radius: float = 50.0
@export var emission_color: Color = Color(0.7, 0.2, 1.0)  # Purple/magenta
@export var spin_speed: float = 15.0

@export var target_galaxy_seed: int = 0
@export var target_galaxy_name: String = ""
@export var target_server_url: String = ""

var gate_name: String = ""
var _ring_mesh: MeshInstance3D = null
var _inner_glow: MeshInstance3D = null
var _trigger_area: Area3D = null
var _label: Label3D = null
var _material: StandardMaterial3D = null
var _glow_material: StandardMaterial3D = null
var _player_inside: bool = false


func _ready() -> void:
	collision_layer = Constants.LAYER_STATIONS
	collision_mask = 0

	_build_ring()
	_build_inner_glow()
	_build_trigger()
	_build_label()


func _build_ring() -> void:
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "WormholeRing"
	var torus := TorusMesh.new()
	torus.inner_radius = ring_inner_radius
	torus.outer_radius = ring_outer_radius
	torus.rings = 48
	torus.ring_segments = 24
	_ring_mesh.mesh = torus

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(emission_color.r, emission_color.g, emission_color.b, 0.85)
	_material.emission_enabled = true
	_material.emission = emission_color
	_material.emission_energy_multiplier = 3.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mesh.material_override = _material

	add_child(_ring_mesh)

	# Collision for the ring body
	var col_shape := CollisionShape3D.new()
	col_shape.name = "RingCollision"
	var box := BoxShape3D.new()
	var diameter: float = ring_outer_radius * 2.0
	box.size = Vector3(diameter, 25.0, diameter)
	col_shape.shape = box
	add_child(col_shape)


func _build_inner_glow() -> void:
	# Central swirling glow disc inside the ring
	_inner_glow = MeshInstance3D.new()
	_inner_glow.name = "InnerGlow"
	var disc := PlaneMesh.new()
	disc.size = Vector2(ring_inner_radius * 1.6, ring_inner_radius * 1.6)
	_inner_glow.mesh = disc

	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.albedo_color = Color(0.5, 0.1, 0.8, 0.3)
	_glow_material.emission_enabled = true
	_glow_material.emission = Color(0.6, 0.15, 0.9)
	_glow_material.emission_energy_multiplier = 2.0
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_inner_glow.material_override = _glow_material

	add_child(_inner_glow)


func _build_trigger() -> void:
	_trigger_area = Area3D.new()
	_trigger_area.name = "WormholeTrigger"
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
	_label.name = "WormholeLabel"
	_label.text = gate_name if gate_name != "" else "WORMHOLE"
	_label.font_size = 36
	_label.modulate = Color(emission_color.r, emission_color.g, emission_color.b, 0.9)
	_label.outline_modulate = Color(0.1, 0.0, 0.15, 0.8)
	_label.outline_size = 4
	_label.position = Vector3(0, ring_outer_radius + 20, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)


func setup(data: Dictionary) -> void:
	target_galaxy_seed = data.get("target_seed", 0)
	target_galaxy_name = data.get("target_name", "Unknown Galaxy")
	target_server_url = data.get("target_url", "")
	gate_name = "Wormhole → " + target_galaxy_name
	global_position = Vector3(data.get("pos_x", 0.0), data.get("pos_y", 0.0), data.get("pos_z", 0.0))

	if _label:
		_label.text = gate_name


func _process(_delta: float) -> void:
	# Ring rotation disabled

	# Pulsing emission
	if _material:
		var pulse: float = (sin(Time.get_ticks_msec() * 0.003) + 1.0) * 0.5
		_material.emission_energy_multiplier = 2.0 + pulse * 3.0

	if _glow_material:
		var glow_pulse: float = (sin(Time.get_ticks_msec() * 0.002 + 1.0) + 1.0) * 0.5
		_glow_material.albedo_color.a = 0.15 + glow_pulse * 0.25


func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.player_ship:
		_player_inside = true
		player_nearby_wormhole.emit(target_galaxy_name)


func _on_body_exited(body: Node3D) -> void:
	if body == GameManager.player_ship:
		_player_inside = false
		player_left_wormhole.emit()
