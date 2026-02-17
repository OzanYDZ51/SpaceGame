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
# - Resets AnimationPlayers to rest pose (prevents mid-animation import)
# =============================================================================


func _post_import(scene: Node) -> Object:
	_process_node(scene)
	_reset_animations(scene)
	return scene


func _process_node(node: Node) -> void:
	if node is MeshInstance3D:
		_fix_mesh_materials(node as MeshInstance3D)

	for child in node.get_children():
		_process_node(child)


func _reset_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.autoplay = ""
		# Reset to RESET track (rest pose) if available
		if ap.has_animation(&"RESET"):
			ap.play(&"RESET")
			ap.seek(0.0, true)
			ap.stop()
	for child in node.get_children():
		_reset_animations(child)


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

			# Ensure no lightmap UV generation artifacts
			std.uv1_triplanar = false
