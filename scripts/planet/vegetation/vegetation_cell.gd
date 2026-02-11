class_name VegetationCell
extends Node3D

# =============================================================================
# Vegetation Cell — One 500m cell of vegetation on a planet surface.
# Contains MultiMeshInstance3D children per vegetation type with LOD ranges.
# Positioned at the cell's surface center, relative to PlanetBody origin.
# =============================================================================

const VIS_HI_END: float = 600.0
const VIS_LO_BEGIN: float = 500.0
const VIS_LO_END: float = 2500.0
const VIS_GRASS_END: float = 250.0

var cell_key: Vector2i = Vector2i.ZERO


## Build MultiMesh instances for each vegetation type in this cell.
## instances: { VegType(int) -> Array[Transform3D] }
func populate(instances: Dictionary) -> void:
	for vtype: int in instances:
		var xforms: Array = instances[vtype]
		if xforms.is_empty():
			continue
		var mat := VegetationMeshLib.get_material(vtype)
		# HIGH LOD
		var mesh_hi := VegetationMeshLib.get_mesh(vtype, VegetationMeshLib.LOD.HIGH)
		var hi_end := VIS_GRASS_END if vtype == VegetationMeshLib.VegType.GRASS else VIS_HI_END
		_add_mmi("H%d" % vtype, mesh_hi, mat, xforms, 0.0, hi_end)
		# LOW LOD (skip grass — too small to see far)
		if vtype != VegetationMeshLib.VegType.GRASS:
			var mesh_lo := VegetationMeshLib.get_mesh(vtype, VegetationMeshLib.LOD.LOW)
			_add_mmi("L%d" % vtype, mesh_lo, mat, xforms, VIS_LO_BEGIN, VIS_LO_END)


func _add_mmi(n: String, mesh: ArrayMesh, mat: StandardMaterial3D,
		xforms: Array, vis_begin: float, vis_end: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = xforms.size()
	mm.mesh = mesh
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, Color.WHITE)
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_begin = vis_begin
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
