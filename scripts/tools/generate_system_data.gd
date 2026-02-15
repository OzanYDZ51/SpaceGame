@tool
extends EditorScript

# =============================================================================
# Generate Star System Data (.tres)
#
# Run from the Godot Script Editor: File > Run (Ctrl+Shift+X)
# Generates a .tres file for every system in the galaxy, saving them to
# res://data/systems/system_{id}.tres
#
# These files are editable in the Godot inspector. Once generated, the game
# loads them via SystemDataRegistry instead of procedural generation.
# =============================================================================

## Galaxy seed — must match Constants.galaxy_seed (default 12345)
const GALAXY_SEED: int = 12345


func _run() -> void:
	print("")
	print("╔══════════════════════════════════════════╗")
	print("║   STAR SYSTEM DATA GENERATOR             ║")
	print("╚══════════════════════════════════════════╝")
	print("")

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute("res://data/systems")

	# Generate galaxy
	var galaxy = GalaxyGenerator.generate(GALAXY_SEED)
	var total: int = galaxy.systems.size()
	print("Galaxy generated with seed %d: %d systems" % [GALAXY_SEED, total])
	print("")

	var count: int = 0
	var errors: int = 0

	for sys in galaxy.systems:
		var system_id: int = sys["id"]
		var sys_seed: int = sys["seed"]
		var sys_name: String = sys["name"]

		# Build connections array for this system
		var connections: Array[Dictionary] = []
		for conn_id in sys["connections"]:
			var conn_sys: Dictionary = galaxy.get_system(conn_id)
			if not conn_sys.is_empty():
				connections.append({
					"target_id": conn_id,
					"target_name": conn_sys["name"],
				})

		# Generate system data from seed
		var data: StarSystemData = SystemGenerator.generate(sys_seed, connections)

		# Replace generator's internal name with the galaxy map name
		var old_name: String = data.system_name
		data.system_name = sys_name
		data.star_name = sys_name

		# Rename all sub-resources to use the galaxy name
		for p in data.planets:
			p.planet_name = p.planet_name.replace(old_name, sys_name)
		for b in data.asteroid_belts:
			b.belt_name = b.belt_name.replace(old_name, sys_name)

		# Save as .tres
		var path: String = "res://data/systems/system_%d.tres" % system_id
		var err =ResourceSaver.save(data, path)
		if err == OK:
			count += 1
			if count % 20 == 0:
				print("  ... %d / %d" % [count, total])
		else:
			errors += 1
			push_error("Failed to save %s: error %d" % [path, err])

	print("")
	print("════════════════════════════════════════════")
	print("  Generated: %d / %d systems" % [count, total])
	if errors > 0:
		print("  Errors:    %d" % errors)
	print("  Output:    res://data/systems/")
	print("════════════════════════════════════════════")
	print("")
	print("You can now open any system_*.tres in the Inspector to customize it.")
	print("The game will use these files instead of procedural generation.")
	print("")

	# Refresh the FileSystem dock so the new files appear
	EditorInterface.get_resource_filesystem().scan()
