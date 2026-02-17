@tool
class_name HullLightPoint
extends Marker3D

# =============================================================================
# Hull Light Point - Editor-visible hull lighting mount point (@tool).
# Place as child of a ship scene to define hull accent light positions visually.
# The position of this Marker3D is where the OmniLight3D will be created at runtime.
#
# Usage:
#   1. Add a HullLightPoint as a child of your ship .tscn root
#   2. Name it HullLight_Dorsal, HullLight_Ventral, etc.
#   3. Position it in the 3D viewport where you want the light
#   4. Tweak color/energy/range in the inspector
#   5. ShipFactory will pick it up automatically
# =============================================================================

@export var light_color: Color = Color(0.95, 0.95, 1.0) ## OmniLight3D color
@export var light_energy: float = 0.5 ## OmniLight3D energy
@export var light_range: float = 15.0 ## OmniLight3D range (meters, before model_scale)
@export var attenuation: float = 1.8 ## OmniLight3D attenuation curve (higher = sharper falloff)

var _gizmo_mesh: MeshInstance3D = null
var _label: Label3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_create_gizmo()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _gizmo_mesh:
		_gizmo_mesh.material_override.albedo_color = light_color
		_gizmo_mesh.material_override.emission = light_color
		_gizmo_mesh.material_override.emission_energy_multiplier = light_energy * 0.5


## Extracts runtime config from this editor node.
func get_config() -> Dictionary:
	return {
		"position": position,
		"color": light_color,
		"energy": light_energy,
		"range": light_range,
		"attenuation": attenuation,
	}


# =============================================================================
# EDITOR GIZMO — small glowing sphere + label
# =============================================================================

func _create_gizmo() -> void:
	_gizmo_mesh = MeshInstance3D.new()
	_gizmo_mesh.name = "_HullLightGizmo"
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 8
	sphere.rings = 4
	_gizmo_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = light_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = light_color
	mat.emission_energy_multiplier = light_energy * 0.5
	mat.no_depth_test = true
	_gizmo_mesh.material_override = mat
	add_child(_gizmo_mesh)

	_label = Label3D.new()
	_label.name = "_HullLightLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = false
	_label.pixel_size = 0.002
	_label.font_size = 24
	_label.outline_size = 4
	_label.modulate = light_color
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.no_depth_test = true
	_label.position.y = 0.3
	_label.text = name
	add_child(_label)
