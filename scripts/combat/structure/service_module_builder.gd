class_name ServiceModuleBuilder
extends RefCounted

# =============================================================================
# Service Module Builder — Generates visual 3D meshes attached to stations
# to represent their service type (repair arms, antennas, platforms, etc.)
# =============================================================================


static func build_modules(station: Node3D, station_type: int) -> void:
	var root := Node3D.new()
	root.name = "ServiceModules"
	station.add_child(root)

	match station_type:
		0: _build_repair_modules(root)
		1: _build_trade_modules(root)
		2: _build_military_modules(root)
		3: _build_mining_modules(root)


static func _build_repair_modules(root: Node3D) -> void:
	# Mechanical arms: articulated cylinders with yellow emission
	var mat := _create_module_material(Color(0.9, 0.75, 0.1), Color(1.0, 0.85, 0.2))

	# Arm 1 — right side
	var arm1 := _create_cylinder(Vector3(0.2, 0.6, 0.2))
	arm1.position = Vector3(0.4, 0.15, -0.1)
	arm1.rotation_degrees = Vector3(0, 0, -30)
	arm1.material_override = mat
	root.add_child(arm1)

	var forearm1 := _create_cylinder(Vector3(0.12, 0.45, 0.12))
	forearm1.position = Vector3(0, 0.5, 0)
	forearm1.rotation_degrees = Vector3(0, 0, 20)
	forearm1.material_override = mat
	arm1.add_child(forearm1)

	# Arm 2 — left side
	var arm2 := _create_cylinder(Vector3(0.2, 0.6, 0.2))
	arm2.position = Vector3(-0.4, 0.15, 0.1)
	arm2.rotation_degrees = Vector3(0, 0, 30)
	arm2.material_override = mat
	root.add_child(arm2)

	var forearm2 := _create_cylinder(Vector3(0.12, 0.45, 0.12))
	forearm2.position = Vector3(0, 0.5, 0)
	forearm2.rotation_degrees = Vector3(0, 0, -20)
	forearm2.material_override = mat
	arm2.add_child(forearm2)


static func _build_trade_modules(root: Node3D) -> void:
	# Satellite dish: cone + flat disc with green emission
	var mat := _create_module_material(Color(0.2, 0.7, 0.3), Color(0.3, 1.0, 0.4))

	# Dish arm (vertical pole)
	var pole := _create_cylinder(Vector3(0.08, 0.5, 0.08))
	pole.position = Vector3(0.3, 0.25, 0.3)
	pole.material_override = mat
	root.add_child(pole)

	# Dish (flattened sphere)
	var dish_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.08
	sphere.radial_segments = 16
	sphere.rings = 8
	dish_mesh.mesh = sphere
	dish_mesh.position = Vector3(0, 0.52, 0)
	dish_mesh.rotation_degrees = Vector3(30, 0, 0)
	dish_mesh.material_override = mat
	pole.add_child(dish_mesh)

	# Second smaller antenna on opposite side
	var pole2 := _create_cylinder(Vector3(0.06, 0.35, 0.06))
	pole2.position = Vector3(-0.25, 0.2, -0.25)
	pole2.material_override = mat
	root.add_child(pole2)

	var dish2 := MeshInstance3D.new()
	var sphere2 := SphereMesh.new()
	sphere2.radius = 0.15
	sphere2.height = 0.06
	sphere2.radial_segments = 12
	sphere2.rings = 6
	dish2.mesh = sphere2
	dish2.position = Vector3(0, 0.38, 0)
	dish2.rotation_degrees = Vector3(-20, 0, 0)
	dish2.material_override = mat
	pole2.add_child(dish2)


static func _build_military_modules(root: Node3D) -> void:
	# Armored platforms: flat boxes with red emission
	var mat := _create_module_material(Color(0.7, 0.15, 0.1), Color(1.0, 0.2, 0.15))

	# Main platform — top
	var plat1 := _create_box(Vector3(0.5, 0.06, 0.4))
	plat1.position = Vector3(0, 0.32, 0)
	plat1.material_override = mat
	root.add_child(plat1)

	# Side armor plates
	var plate_r := _create_box(Vector3(0.06, 0.25, 0.35))
	plate_r.position = Vector3(0.4, 0.15, 0)
	plate_r.material_override = mat
	root.add_child(plate_r)

	var plate_l := _create_box(Vector3(0.06, 0.25, 0.35))
	plate_l.position = Vector3(-0.4, 0.15, 0)
	plate_l.material_override = mat
	root.add_child(plate_l)

	# Reinforcement struts
	var strut1 := _create_cylinder(Vector3(0.04, 0.3, 0.04))
	strut1.position = Vector3(0.25, 0.15, 0.2)
	strut1.rotation_degrees = Vector3(0, 0, 15)
	strut1.material_override = mat
	root.add_child(strut1)

	var strut2 := _create_cylinder(Vector3(0.04, 0.3, 0.04))
	strut2.position = Vector3(-0.25, 0.15, -0.2)
	strut2.rotation_degrees = Vector3(0, 0, -15)
	strut2.material_override = mat
	root.add_child(strut2)


static func _build_mining_modules(root: Node3D) -> void:
	# Extraction claws: V-shaped cylinders with blue emission
	var mat := _create_module_material(Color(0.15, 0.4, 0.8), Color(0.2, 0.5, 1.0))

	# Claw base
	var base := _create_box(Vector3(0.3, 0.1, 0.15))
	base.position = Vector3(0, -0.2, -0.35)
	base.material_override = mat
	root.add_child(base)

	# Left arm of V
	var claw_l := _create_cylinder(Vector3(0.08, 0.5, 0.08))
	claw_l.position = Vector3(-0.1, 0, 0)
	claw_l.rotation_degrees = Vector3(-40, 0, 15)
	claw_l.material_override = mat
	base.add_child(claw_l)

	# Right arm of V
	var claw_r := _create_cylinder(Vector3(0.08, 0.5, 0.08))
	claw_r.position = Vector3(0.1, 0, 0)
	claw_r.rotation_degrees = Vector3(-40, 0, -15)
	claw_r.material_override = mat
	base.add_child(claw_r)

	# Second smaller claw on opposite side
	var base2 := _create_box(Vector3(0.2, 0.08, 0.12))
	base2.position = Vector3(0, -0.15, 0.3)
	base2.rotation_degrees = Vector3(0, 180, 0)
	base2.material_override = mat
	root.add_child(base2)

	var claw2_l := _create_cylinder(Vector3(0.06, 0.35, 0.06))
	claw2_l.position = Vector3(-0.08, 0, 0)
	claw2_l.rotation_degrees = Vector3(-35, 0, 12)
	claw2_l.material_override = mat
	base2.add_child(claw2_l)

	var claw2_r := _create_cylinder(Vector3(0.06, 0.35, 0.06))
	claw2_r.position = Vector3(0.08, 0, 0)
	claw2_r.rotation_degrees = Vector3(-35, 0, -12)
	claw2_r.material_override = mat
	base2.add_child(claw2_r)


# =============================================================================
# HELPERS
# =============================================================================
static func _create_module_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = 0.8
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.5
	return mat


static func _create_cylinder(size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = size.x * 0.5
	cyl.bottom_radius = size.x * 0.5
	cyl.height = size.y
	cyl.radial_segments = 12
	mi.mesh = cyl
	return mi


static func _create_box(size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	return mi
