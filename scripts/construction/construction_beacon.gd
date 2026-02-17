class_name ConstructionBeacon
extends Node3D

# =============================================================================
# Construction Beacon — Holographic 3D marker for planned construction sites
# Pattern: JumpGate (Area3D trigger, player proximity signals)
# =============================================================================

signal player_nearby(marker_id: int, display_name: String)
signal player_left

var marker_id: int = -1
var display_name: String = ""
var marker_type: StringName = &"station"

var _torus: MeshInstance3D = null
var _pillar: MeshInstance3D = null
var _label: Label3D = null
var _trigger: Area3D = null
var _player_inside: bool = false

const TRIGGER_RADIUS: float = 200.0
const TORUS_INNER: float = 6.0
const TORUS_OUTER: float = 10.0
const PILLAR_HEIGHT: float = 30.0
const BEACON_COLOR := Color(1.0, 0.6, 0.1, 0.7)


func _ready() -> void:
	_build_visuals()
	_build_trigger()


func setup(marker: Dictionary) -> void:
	marker_id = marker.get("id", -1)
	display_name = marker.get("display_name", "Construction")
	marker_type = StringName(marker.get("type", "station"))
	var pos_x: float = marker.get("pos_x", 0.0)
	var pos_z: float = marker.get("pos_z", 0.0)
	global_position = FloatingOrigin.to_local_pos([pos_x, 0.0, pos_z])
	if _label:
		_label.text = display_name + " [CONSTRUCTION]"


func _build_visuals() -> void:
	# Emissive orange material (shared)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BEACON_COLOR
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Torus ring (horizontal holographic ring)
	_torus = MeshInstance3D.new()
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = TORUS_INNER
	torus_mesh.outer_radius = TORUS_OUTER
	torus_mesh.rings = 24
	torus_mesh.ring_segments = 12
	_torus.mesh = torus_mesh
	_torus.material_override = mat
	_torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_torus)

	# Vertical pillar (light beam)
	_pillar = MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 1.5
	cyl_mesh.bottom_radius = 1.5
	cyl_mesh.height = PILLAR_HEIGHT
	_pillar.mesh = cyl_mesh
	var pillar_mat := mat.duplicate() as StandardMaterial3D
	pillar_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.3)
	_pillar.material_override = pillar_mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)

	# Billboard label
	_label = Label3D.new()
	_label.text = "Construction"
	_label.font_size = 48
	_label.pixel_size = 0.02
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.7, 0.2, 0.9)
	_label.position = Vector3(0, PILLAR_HEIGHT * 0.5 + 5.0, 0)
	_label.no_depth_test = true
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_label)


func _build_trigger() -> void:
	_trigger = Area3D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = Constants.LAYER_SHIPS
	_trigger.monitoring = true
	_trigger.monitorable = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	_trigger.add_child(shape)
	add_child(_trigger)

	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.player_ship and not _player_inside:
		_player_inside = true
		player_nearby.emit(marker_id, display_name)


func _on_body_exited(body: Node3D) -> void:
	if body == GameManager.player_ship and _player_inside:
		_player_inside = false
		player_left.emit()


func _process(delta: float) -> void:
	# Torus rotation disabled

	# Emission pulse
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.7 + sin(t * 2.5) * 0.3
	if _torus and _torus.material_override:
		(_torus.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 + pulse
