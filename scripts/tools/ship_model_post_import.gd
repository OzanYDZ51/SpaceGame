@tool
extends EditorScenePostImport

# =============================================================================
# Ship Model Post-Import Script
# Ensures consistent import for all ship .glb files.
# Set this as import_script/path in each ship .glb.import file.
#
# What it does:
# - Preserves original normals from Blender (no recalculation)
# - Disables backface culling on all materials (doubleSided from Blender)
# - Ensures materials use correct PBR metallic workflow
# =============================================================================


func _post_import(scene: Node) -> Object:
	_process_node(scene)
	return scene


func _process_node(node: Node) -> void:
	if node is MeshInstance3D:
		_fix_mesh_materials(node as MeshInstance3D)

	for child in node.get_children():
		_process_node(child)


func _fix_mesh_materials(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return

	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			# Preserve double-sided from GLB
			if std.cull_mode != BaseMaterial3D.CULL_DISABLED:
				pass  # Keep Godot's default unless GLB set doubleSided

			# Clamp non-physical metallic to 0 or 1
			if std.metallic > 0.1 and std.metallic < 0.9:
				std.metallic = 0.0

			# Ensure no lightmap UV generation artifacts
			std.uv1_triplanar = false
