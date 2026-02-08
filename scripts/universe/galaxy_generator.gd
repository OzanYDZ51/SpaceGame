class_name GalaxyGenerator
extends RefCounted

# =============================================================================
# Galaxy Generator - Procedural galaxy from a master seed
# Distributes star systems in 2D, builds jump gate network, assigns factions.
# =============================================================================

# Extended name pools for 120+ unique system names
const PREFIXES := [
	"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
	"Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi",
	"Rho", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega",
	"Nova", "Vega", "Sol", "Rigel", "Sirius", "Altair", "Deneb", "Polaris",
	"Antares", "Castor", "Procyon", "Regulus", "Spica", "Mira", "Capella",
	"Aldebaran", "Betelgeuse", "Fomalhaut", "Arcturus", "Canopus", "Achernar",
]

const SUFFIXES := [
	"Centauri", "Eridani", "Cygni", "Draconis", "Orionis", "Lyrae", "Tauri",
	"Aquilae", "Serpentis", "Crucis", "Leonis", "Ursae", "Persei", "Pegasi",
	"Carinae", "Phoenicis", "Hydrae", "Virginis", "Scorpii", "Pavonis",
]

# Spectral class weights (same distribution as SystemGenerator)
const SPECTRAL_WEIGHTS := [
	{ "class": "M", "weight": 76.0 },
	{ "class": "K", "weight": 12.0 },
	{ "class": "G", "weight": 7.5 },
	{ "class": "F", "weight": 3.0 },
	{ "class": "A", "weight": 1.0 },
	{ "class": "B", "weight": 0.13 },
	{ "class": "O", "weight": 0.003 },
]

const FACTIONS: Array[StringName] = [&"neutral", &"hostile", &"friendly", &"lawless"]


static func generate(master_seed: int) -> GalaxyData:
	var galaxy := GalaxyData.new()
	galaxy.master_seed = master_seed

	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed

	var count: int = Constants.GALAXY_SYSTEM_COUNT
	var radius: float = Constants.GALAXY_RADIUS

	# 1. Distribute systems using rejection sampling with minimum distance
	var positions := _distribute_systems(rng, count, radius)

	# 2. Create system entries
	var used_names: Dictionary = {}
	for i in positions.size():
		var pos: Vector2 = positions[i]
		var sys_seed: int = hash(master_seed + i * 7919)  # Deterministic per-system seed
		var sys_rng := RandomNumberGenerator.new()
		sys_rng.seed = sys_seed

		var sys_name := _generate_unique_name(sys_rng, used_names)
		used_names[sys_name] = true

		var spectral := _pick_spectral_class(sys_rng)
		var dist_from_center: float = pos.length()
		var norm_dist: float = dist_from_center / radius  # 0 = center, 1 = edge

		galaxy.systems.append({
			"id": i,
			"seed": sys_seed,
			"name": sys_name,
			"x": pos.x,
			"y": pos.y,
			"spectral_class": spectral,
			"connections": [],
			"has_station": sys_rng.randf() < (0.7 - norm_dist * 0.3),  # More stations near center
			"faction": &"neutral",  # Assigned later
			"danger_level": 0,      # Assigned later
		})

	# 3. Build jump gate network (MST + range-limited edges)
	_build_connections(galaxy.systems, Constants.JUMP_GATE_RANGE)

	# 4. Assign factions via cluster seeding
	_assign_factions(rng, galaxy.systems, radius)

	# 5. Assign danger levels (higher at edges, lower near center)
	_assign_danger_levels(galaxy.systems, radius)

	# 6. Place wormholes at high-danger edge systems (1-3 per galaxy)
	_place_wormholes(rng, galaxy.systems, radius)

	# 7. Player home: station-bearing system closest to center
	galaxy.player_home_system = _find_home_system(galaxy.systems)

	# Ensure home system is safe
	galaxy.systems[galaxy.player_home_system]["danger_level"] = 0
	galaxy.systems[galaxy.player_home_system]["faction"] = &"neutral"
	galaxy.systems[galaxy.player_home_system]["has_station"] = true

	return galaxy


static func _distribute_systems(rng: RandomNumberGenerator, count: int, radius: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var min_dist: float = radius * 2.0 / sqrt(float(count)) * 0.7  # Minimum spacing
	var max_attempts: int = count * 50

	var attempts: int = 0
	while points.size() < count and attempts < max_attempts:
		attempts += 1
		# Random point in circle
		var angle: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius  # sqrt for uniform distribution in circle
		var candidate := Vector2(cos(angle) * r, sin(angle) * r)

		# Check minimum distance to all existing points
		var too_close := false
		for p in points:
			if candidate.distance_to(p) < min_dist:
				too_close = true
				break

		if not too_close:
			points.append(candidate)

	return points


static func _generate_unique_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for _attempt in 50:
		var p: String = PREFIXES[rng.randi() % PREFIXES.size()]
		var s: String = SUFFIXES[rng.randi() % SUFFIXES.size()]
		var sname: String = p + " " + s
		if not used.has(sname):
			return sname

	# Fallback: add a numeric suffix
	var fb_prefix: String = PREFIXES[rng.randi() % PREFIXES.size()]
	var fb_suffix: String = SUFFIXES[rng.randi() % SUFFIXES.size()]
	return fb_prefix + " " + fb_suffix + " " + str(rng.randi_range(2, 99))


static func _pick_spectral_class(rng: RandomNumberGenerator) -> String:
	var total_weight: float = 0.0
	for entry in SPECTRAL_WEIGHTS:
		total_weight += entry["weight"]
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry in SPECTRAL_WEIGHTS:
		cumulative += entry["weight"]
		if roll <= cumulative:
			return entry["class"]
	return "M"


static func _build_connections(systems: Array[Dictionary], max_range: float) -> void:
	var n: int = systems.size()
	if n < 2:
		return

	# Step 1: Compute all pairwise distances and edges within range
	var edges: Array[Dictionary] = []  # { "a": int, "b": int, "dist": float }
	for i in n:
		for j in range(i + 1, n):
			var dx: float = systems[i]["x"] - systems[j]["x"]
			var dy: float = systems[i]["y"] - systems[j]["y"]
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= max_range:
				edges.append({ "a": i, "b": j, "dist": dist })

	# Sort by distance (for MST - Kruskal's algorithm)
	edges.sort_custom(func(a, b): return a["dist"] < b["dist"])

	# Step 2: MST using Union-Find (ensures full connectivity)
	var parent: Array[int] = []
	parent.resize(n)
	for i in n:
		parent[i] = i

	var mst_edges: Array[Dictionary] = []
	for edge in edges:
		var ra: int = _find_root(parent, edge["a"])
		var rb: int = _find_root(parent, edge["b"])
		if ra != rb:
			parent[ra] = rb
			mst_edges.append(edge)
			if mst_edges.size() == n - 1:
				break

	# Apply MST edges (guaranteed connectivity)
	for edge in mst_edges:
		_add_connection(systems, edge["a"], edge["b"])

	# Step 3: Add extra edges within range for richer connectivity (2-4 connections per node)
	for edge in edges:
		var a: int = edge["a"]
		var b: int = edge["b"]
		# Skip if already connected
		if b in systems[a]["connections"]:
			continue
		# Only add if both nodes have fewer than 4 connections
		if systems[a]["connections"].size() < 4 and systems[b]["connections"].size() < 4:
			_add_connection(systems, a, b)


static func _find_root(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]  # Path compression
		x = parent[x]
	return x


static func _add_connection(systems: Array[Dictionary], a: int, b: int) -> void:
	if not (b in systems[a]["connections"]):
		systems[a]["connections"].append(b)
	if not (a in systems[b]["connections"]):
		systems[b]["connections"].append(a)


static func _assign_factions(rng: RandomNumberGenerator, systems: Array[Dictionary], radius: float) -> void:
	# Seed 4-6 faction centers, then assign systems to nearest faction center
	var faction_count: int = rng.randi_range(4, 6)
	var faction_centers: Array[Dictionary] = []  # { "x": float, "y": float, "faction": StringName }

	for i in faction_count:
		var angle: float = rng.randf() * TAU
		var r: float = rng.randf_range(radius * 0.15, radius * 0.75)
		var faction: StringName = FACTIONS[i % FACTIONS.size()]
		faction_centers.append({
			"x": cos(angle) * r,
			"y": sin(angle) * r,
			"faction": faction,
		})

	# Assign each system to nearest faction center
	for sys in systems:
		var best_dist: float = INF
		var best_faction: StringName = &"neutral"
		for fc in faction_centers:
			var dx: float = sys["x"] - fc["x"]
			var dy: float = sys["y"] - fc["y"]
			var dist: float = dx * dx + dy * dy
			if dist < best_dist:
				best_dist = dist
				best_faction = fc["faction"]
		sys["faction"] = best_faction


static func _assign_danger_levels(systems: Array[Dictionary], radius: float) -> void:
	for sys in systems:
		var dist: float = sqrt(sys["x"] * sys["x"] + sys["y"] * sys["y"])
		var norm: float = dist / radius  # 0 = center, 1 = edge

		# Base danger from distance (steeper ramp + baseline)
		var danger: int = int(norm * 5.0) + 1

		# Lawless regions are more dangerous
		if sys["faction"] == &"lawless":
			danger += 1
		# Hostile regions slightly more dangerous
		elif sys["faction"] == &"hostile":
			danger += 1

		# Station systems are slightly safer
		if sys["has_station"]:
			danger -= 1

		sys["danger_level"] = clampi(danger, 1, 5)


static func _place_wormholes(rng: RandomNumberGenerator, systems: Array[Dictionary], radius: float) -> void:
	# Select 1-3 edge systems (high distance from center) as wormhole hosts.
	# Wormhole targets are left empty — filled by the server's routing table at runtime.
	var num_wormholes: int = rng.randi_range(1, 3)

	# Sort systems by distance from center (descending) to find edge systems
	var edge_candidates: Array[Dictionary] = []
	for sys in systems:
		var dist: float = sqrt(sys["x"] * sys["x"] + sys["y"] * sys["y"])
		edge_candidates.append({ "id": sys["id"], "dist": dist })
	edge_candidates.sort_custom(func(a, b): return a["dist"] > b["dist"])

	var placed: int = 0
	for candidate in edge_candidates:
		if placed >= num_wormholes:
			break
		var sys_id: int = candidate["id"]
		# Skip home system candidates (stations near center)
		if candidate["dist"] < radius * 0.5:
			break
		# Mark system as having a wormhole (target info filled by server config)
		systems[sys_id]["wormhole_target"] = {}
		systems[sys_id]["danger_level"] = clampi(systems[sys_id]["danger_level"] + 1, 1, 5)
		placed += 1


static func _find_home_system(systems: Array[Dictionary]) -> int:
	var best_id: int = 0
	var best_dist: float = INF

	for sys in systems:
		if not sys["has_station"]:
			continue
		var dist: float = sys["x"] * sys["x"] + sys["y"] * sys["y"]
		if dist < best_dist:
			best_dist = dist
			best_id = sys["id"]

	return best_id
