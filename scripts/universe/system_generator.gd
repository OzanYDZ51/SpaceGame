class_name SystemGenerator
extends RefCounted

# =============================================================================
# System Generator - Procedural deterministic generation from a seed
# Realistic star types, Titius-Bode orbital spacing, Kepler periods
# =============================================================================

# Star type distribution weights (roughly realistic)
const SPECTRAL_TYPES := [
	{ "class": "M", "weight": 76.0, "temp_min": 2400, "temp_max": 3700, "radius_min": 0.1, "radius_max": 0.6, "color": Color(1.0, 0.6, 0.4), "lum_min": 0.001, "lum_max": 0.08 },
	{ "class": "K", "weight": 12.0, "temp_min": 3700, "temp_max": 5200, "radius_min": 0.6, "radius_max": 0.9, "color": Color(1.0, 0.8, 0.5), "lum_min": 0.08, "lum_max": 0.6 },
	{ "class": "G", "weight": 7.5, "temp_min": 5200, "temp_max": 6000, "radius_min": 0.9, "radius_max": 1.15, "color": Color(1.0, 0.95, 0.7), "lum_min": 0.6, "lum_max": 1.5 },
	{ "class": "F", "weight": 3.0, "temp_min": 6000, "temp_max": 7500, "radius_min": 1.15, "radius_max": 1.6, "color": Color(0.95, 0.95, 0.9), "lum_min": 1.5, "lum_max": 5.0 },
	{ "class": "A", "weight": 1.0, "temp_min": 7500, "temp_max": 10000, "radius_min": 1.5, "radius_max": 2.5, "color": Color(0.8, 0.85, 1.0), "lum_min": 5.0, "lum_max": 25.0 },
	{ "class": "B", "weight": 0.13, "temp_min": 10000, "temp_max": 30000, "radius_min": 2.5, "radius_max": 7.0, "color": Color(0.7, 0.8, 1.0), "lum_min": 25.0, "lum_max": 30000.0 },
	{ "class": "O", "weight": 0.003, "temp_min": 30000, "temp_max": 50000, "radius_min": 6.0, "radius_max": 15.0, "color": Color(0.6, 0.7, 1.0), "lum_min": 30000.0, "lum_max": 100000.0 },
]

const PLANET_TYPES := ["rocky", "gas_giant", "ice", "ocean", "lava"]
const ROMAN_NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

# System names pool (procedural fallback)
const GREEK_LETTERS := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa"]
const STAR_SUFFIXES := ["Centauri", "Eridani", "Cygni", "Draconis", "Orionis", "Lyrae", "Tauri", "Aquilae", "Serpentis", "Crucis"]

# Station name parts
const STATION_PREFIXES := ["Alpha", "Beta", "Gamma", "Omega", "Nexus", "Haven", "Port", "Dock", "Orbital", "Gateway"]
const STATION_SUFFIXES := ["Station", "Hub", "Outpost", "Terminal", "Platform", "Depot"]
const STATION_TYPES := ["repair", "trade", "military", "mining"]

# Scale factor: we compress real AU distances to game-friendly distances
# 1 AU real = ~150 billion meters. In game we use ~50 million meters per AU for playability.
const GAME_AU: float = 50_000_000.0  # 50 Mm per AU in game


## Generate a star system. Optional connections param adds jump gates.
## connections: Array of { "target_id": int, "target_name": String }
static func generate(seed_val: int, connections: Array[Dictionary] = []) -> StarSystemData:
	var data := StarSystemData.new()
	data.seed_value = seed_val
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Generate system name
	data.system_name = GREEK_LETTERS[rng.randi() % GREEK_LETTERS.size()] + " " + STAR_SUFFIXES[rng.randi() % STAR_SUFFIXES.size()]

	# Pick star type (weighted)
	var star_type: Dictionary = _pick_weighted(rng, SPECTRAL_TYPES)
	data.star_spectral_class = star_type["class"]
	data.star_temperature = lerpf(star_type["temp_min"], star_type["temp_max"], rng.randf())
	var radius_solar: float = lerpf(star_type["radius_min"], star_type["radius_max"], rng.randf())
	data.star_radius = radius_solar * 696340.0 * 100.0  # in game meters (scaled down)
	data.star_color = star_type["color"]
	data.star_luminosity = lerpf(star_type["lum_min"], star_type["lum_max"], rng.randf())
	data.star_name = data.system_name

	# Generate planets (2-8, fewer for dim stars)
	var max_planets: int = clampi(int(3 + data.star_luminosity * 2.0 + rng.randf() * 3.0), 2, 8)
	var num_planets: int = rng.randi_range(2, max_planets)

	# Titius-Bode orbital spacing
	var base_orbit: float = GAME_AU * (0.2 + rng.randf() * 0.3)  # first planet at 0.2-0.5 AU
	var orbit_spacing_factor: float = 1.4 + rng.randf() * 0.8  # 1.4-2.2x between orbits

	var current_orbit: float = base_orbit
	var habitable_zone_inner: float = GAME_AU * sqrt(data.star_luminosity) * 0.75
	var habitable_zone_outer: float = GAME_AU * sqrt(data.star_luminosity) * 1.5
	var frost_line: float = GAME_AU * sqrt(data.star_luminosity) * 2.7

	for i in num_planets:
		var planet: Dictionary = {}
		var roman: String = ROMAN_NUMERALS[i] if i < ROMAN_NUMERALS.size() else str(i + 1)
		planet["name"] = data.system_name + " " + roman

		planet["orbital_radius"] = current_orbit
		# Kepler's third law approximation: T = 2*PI * sqrt(r^3 / (G*M))
		# Simplified: period proportional to r^1.5
		var orbit_au: float = current_orbit / GAME_AU
		planet["orbital_period"] = 600.0 * orbit_au * sqrt(orbit_au)  # Game time: ~10min per AU orbital period
		planet["orbital_angle"] = rng.randf() * TAU

		# Determine planet type based on distance
		if current_orbit < habitable_zone_inner:
			# Inner system: rocky or lava
			if rng.randf() < 0.3:
				planet["type"] = "lava"
				planet["color"] = Color(1.0, 0.35, 0.15, 0.9)
			else:
				planet["type"] = "rocky"
				planet["color"] = Color(0.55 + rng.randf() * 0.2, 0.4 + rng.randf() * 0.15, 0.25 + rng.randf() * 0.1, 0.9)
		elif current_orbit < habitable_zone_outer:
			# Habitable zone: rocky or ocean
			if rng.randf() < 0.4:
				planet["type"] = "ocean"
				planet["color"] = Color(0.15 + rng.randf() * 0.1, 0.35 + rng.randf() * 0.15, 0.7 + rng.randf() * 0.15, 0.9)
			else:
				planet["type"] = "rocky"
				planet["color"] = Color(0.45 + rng.randf() * 0.2, 0.55 + rng.randf() * 0.15, 0.35 + rng.randf() * 0.1, 0.9)
		elif current_orbit < frost_line:
			# Beyond habitable: gas giants
			planet["type"] = "gas_giant"
			planet["color"] = Color(0.75 + rng.randf() * 0.15, 0.6 + rng.randf() * 0.15, 0.25 + rng.randf() * 0.15, 0.9)
			planet["has_rings"] = rng.randf() < 0.4
		else:
			# Outer system: ice
			planet["type"] = "ice"
			planet["color"] = Color(0.5 + rng.randf() * 0.15, 0.7 + rng.randf() * 0.1, 0.9 + rng.randf() * 0.1, 0.9)

		# Radius based on type
		match planet["type"]:
			"lava": planet["radius"] = 1500000.0 + rng.randf() * 2000000.0
			"rocky": planet["radius"] = 2000000.0 + rng.randf() * 5000000.0
			"ocean": planet["radius"] = 3000000.0 + rng.randf() * 6000000.0
			"gas_giant": planet["radius"] = 15000000.0 + rng.randf() * 40000000.0
			"ice": planet["radius"] = 2000000.0 + rng.randf() * 8000000.0
			_: planet["radius"] = 3000000.0

		if not planet.has("has_rings"):
			planet["has_rings"] = false

		data.planets.append(planet)
		current_orbit *= orbit_spacing_factor

	# Asteroid belts (2-5, placed between planet orbits)
	var num_belts: int = rng.randi_range(2, mini(5, num_planets))
	var used_indices: Array[int] = []
	for i in num_belts:
		# Pick a gap between planets (avoid duplicates)
		var belt_index: int = -1
		for _try in 10:
			var candidate: int = rng.randi_range(1, num_planets - 1)
			if candidate not in used_indices and candidate < data.planets.size():
				belt_index = candidate
				used_indices.append(candidate)
				break
		if belt_index < 0:
			continue

		var inner_orbit: float = data.planets[belt_index - 1]["orbital_radius"]
		var outer_orbit: float = data.planets[belt_index]["orbital_radius"]
		var belt_r: float = (inner_orbit + outer_orbit) * 0.5
		var belt_width: float = (outer_orbit - inner_orbit) * 0.2

		# Determine zone based on orbital position relative to frost line
		var zone: String
		if belt_r < habitable_zone_inner:
			zone = "inner"
		elif belt_r < frost_line:
			zone = "mid"
		else:
			zone = "outer"

		# Resource distribution
		var dominant: StringName = MiningRegistry.pick_resource_for_zone(rng, zone)
		var secondary: StringName = MiningRegistry.pick_secondary(rng, zone, dominant)
		var rare: StringName = MiningRegistry.pick_rare(rng, dominant, secondary)

		# Asteroid count scales with belt width
		var asteroid_count: int = rng.randi_range(150, 500)

		data.asteroid_belts.append({
			"name": data.system_name + " Belt " + str(i + 1),
			"field_id": "belt_%d" % i,
			"orbital_radius": belt_r,
			"width": belt_width,
			"dominant_resource": dominant,
			"secondary_resource": secondary,
			"rare_resource": rare,
			"asteroid_count": asteroid_count,
			"zone": zone,
		})

	# Generate stations
	_generate_stations(rng, data)

	# Generate jump gates from connections
	_generate_jump_gates(rng, data, connections)

	return data


static func _generate_stations(rng: RandomNumberGenerator, data: StarSystemData) -> void:
	# At least 1 station per system, placed in orbit around an inner planet
	var station_count: int = rng.randi_range(1, 2)
	for i in station_count:
		var planet_idx: int = rng.randi_range(0, mini(2, data.planets.size() - 1))
		var planet: Dictionary = data.planets[planet_idx]
		var station_orbit: float = planet["orbital_radius"] * 0.95 + rng.randf() * planet["orbital_radius"] * 0.1

		var prefix: String = STATION_PREFIXES[rng.randi() % STATION_PREFIXES.size()]
		var suffix: String = STATION_SUFFIXES[rng.randi() % STATION_SUFFIXES.size()]

		# First station in every system is always "repair" type
		var station_type: String
		if i == 0:
			station_type = "repair"
		else:
			station_type = STATION_TYPES[rng.randi() % STATION_TYPES.size()]

		data.stations.append({
			"name": prefix + " " + suffix,
			"station_type": station_type,
			"orbital_radius": station_orbit,
			"orbital_parent": "star_0",
			"orbital_period": planet["orbital_period"] * 0.9,
			"orbital_angle": rng.randf() * TAU,
		})


static func _generate_jump_gates(rng: RandomNumberGenerator, data: StarSystemData, connections: Array[Dictionary]) -> void:
	# Place gates beyond the outermost station orbit (reachable in ~30s at cruise speed)
	var max_station_orbit: float = 0.0
	for station in data.stations:
		max_station_orbit = maxf(max_station_orbit, station["orbital_radius"])
	# Gate radius = outermost station orbit + 3 Mm buffer (fallback to 20 Mm if no stations)
	var gate_radius: float = max_station_orbit + 3_000_000.0 if max_station_orbit > 0 else 20_000_000.0
	var gate_count: int = connections.size()
	if gate_count == 0:
		return

	for i in gate_count:
		var conn: Dictionary = connections[i]
		# Angle based on deterministic hash of connection pair
		var pair_hash: int = hash(data.seed_value + conn["target_id"] * 31)
		var angle: float = float(pair_hash % 10000) / 10000.0 * TAU

		# Ensure gates are spaced apart (offset by index if overlapping)
		angle += float(i) * TAU / float(gate_count) * 0.1

		var gx: float = cos(angle) * gate_radius
		var gz: float = sin(angle) * gate_radius
		var gy: float = (rng.randf() - 0.5) * gate_radius * 0.05  # Slight vertical offset

		data.jump_gates.append({
			"name": "Gate → " + conn["target_name"],
			"target_system_id": conn["target_id"],
			"target_system_name": conn["target_name"],
			"pos_x": gx,
			"pos_y": gy,
			"pos_z": gz,
		})


static func _pick_weighted(rng: RandomNumberGenerator, items: Array) -> Dictionary:
	var total_weight: float = 0.0
	for item in items:
		total_weight += item["weight"]
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for item in items:
		cumulative += item["weight"]
		if roll <= cumulative:
			return item
	return items[items.size() - 1]
