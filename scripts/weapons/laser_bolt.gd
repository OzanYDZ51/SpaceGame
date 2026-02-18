class_name LaserBolt
extends BaseProjectile

# =============================================================================
# Laser Bolt - Fast-moving energy projectile with glow
# Extends BaseProjectile for damage/collision.
# Supports per-weapon bolt_color from WeaponResource.
# Materials are duplicated per instance so pooled bolts can have unique colors.
# =============================================================================

var _bolt_mat: StandardMaterial3D = null
var _core_mat: StandardMaterial3D = null


func _ready() -> void:
	super._ready()
	# Duplicate materials so each pooled bolt can have its own color
	var bolt_mesh: MeshInstance3D = get_node_or_null("BoltMesh")
	if bolt_mesh and bolt_mesh.material_override:
		_bolt_mat = bolt_mesh.material_override.duplicate() as StandardMaterial3D
		# Add emission for bloom/glow
		_bolt_mat.emission_enabled = true
		_bolt_mat.emission = _bolt_mat.albedo_color
		_bolt_mat.emission_energy_multiplier = 2.0
		bolt_mesh.material_override = _bolt_mat

	var core_mesh: MeshInstance3D = get_node_or_null("CoreMesh")
	if core_mesh and core_mesh.material_override:
		_core_mat = core_mesh.material_override.duplicate() as StandardMaterial3D
		# Core gets stronger emission (bright center)
		_core_mat.emission_enabled = true
		_core_mat.emission = _core_mat.albedo_color
		_core_mat.emission_energy_multiplier = 3.5
		core_mesh.material_override = _core_mat


## Called by Hardpoint.try_fire() to apply the weapon's visual config.
func apply_visual_config(color: Color) -> void:
	if _bolt_mat:
		var bolt_col := Color(color.r, color.g, color.b, 0.7)
		_bolt_mat.albedo_color = bolt_col
		_bolt_mat.emission = Color(color.r, color.g, color.b, 1.0)

	if _core_mat:
		# Core is a brighter/whiter version of the bolt color
		var core_col := Color(
			lerpf(color.r, 1.0, 0.7),
			lerpf(color.g, 1.0, 0.7),
			lerpf(color.b, 1.0, 0.7),
			1.0
		)
		_core_mat.albedo_color = core_col
		_core_mat.emission = core_col
