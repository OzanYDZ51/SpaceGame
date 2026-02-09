class_name SystemGenerator
extends RefCounted

# =============================================================================
# System Generator - Procedural deterministic generation from a seed
# Now produces Resource types (PlanetData, StationData, etc.) instead of Dicts.
# =============================================================================

const SPECTRAL_TYPES := [
	{ "class": "M", "weight": 76.0, "temp_min": 2400, "temp_max": 3700, "radius_min": 0.1, "radius_max": 0.6, "color": Color(1.0, 0.6, 0.4), "lum_min": 0.001, "lum_max": 0.08 },
	{ "class": "K", "weight": 12.0, "temp_min": 3700, "temp_max": 5200, "radius_min": 0.6, "radius_max": 0.9, "color": Color(1.0, 0.8, 0.5), "lum_min": 0.08, "lum_max": 0.6 },
	{ "class": "G", "weight": 7.5, "temp_min": 5200, "temp_max": 6000, "radius_min": 0.9, "radius_max": 1.15, "color": Color(1.0, 0.95, 0.7), "lum_min": 0.6, "lum_max": 1.5 },
	{ "class": "F", "weight": 3.0, "temp_min": 6000, "temp_max": 7500, "radius_min": 1.15, "radius_max": 1.6, "color": Color(0.95, 0.95, 0.9), "lum_min": 1.5, "lum_max": 5.0 },
	{ "class": "A", "weight": 1.0, "temp_min": 7500, "temp_max": 10000, "radius_min": 1.5, "radius_max": 2.5, "color": Color(0.8, 0.85, 1.0), "lum_min": 5.0, "lum_max": 25.0 },
	{ "class": "B", "weight": 0.13, "temp_min": 10000, "temp_max": 30000, "radius_min": 2.5, "radius_max": 7.0, "color": Color(0.7, 0.8, 1.0), "lum_min": 25.0, "lum_max": 30000.0 },
	{ "class": "O", "weight": 0.003, "temp_min": 30000, "temp_max": 50000, "radius_min": 6.0, "radius_max": 15.0, "color": Color(0.6, 0.7, 1.0), "lum_min": 30000.0, "lum_max": 100000.0 },
]

const ROMAN_NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const GREEK_LETTERS := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa"]
const STAR_SUFFIXES := ["Centauri", "Eridani", "Cygni", "Draconis", "Orionis", "Lyrae", "Tauri", "Aquilae", "Serpentis", "Crucis"]
const STATION_PREFIXES := ["Alpha", "Beta", "Gamma", "Omega", "Nexus", "Haven", "Port", "Dock", "Orbital", "Gateway"]
const STATION_SUFFIXES := ["Station", "Hub", "Outpost", "Terminal", "Platform", "Depot"]
const STATION_TYPES := ["repair", "trade", "military", "mining"]
const GAME_AU: float = 50_000_000.0


## Generate a star system. connections: Array of { "target_id": int, "target_name": String }
static func generate(seed_val: int, connections: Array[Dictionary] = []) -> StarSystemData:
	var data := StarSystemData.new()
	data.seed_value = seed_val
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# System name
	data.system_name = GREEK_LETTERS[rng.randi() % GREEK_LETTERS.size()] + " " + STAR_SUFFIXES[rng.randi() % STAR_SUFFIXES.size()]

	# Star type (weighted)
	var star_type: Dictionary = _pick_weighted(rng, SPECTRAL_TYPES)
	data.star_spectral_class = star_type["class"]
	data.star_temperature = lerpf(star_type["temp_min"], star_type["temp_max"], rng.randf())
	var radius_solar: float = lerpf(star_type["radius_min"], star_type["radius_max"], rng.randf())
	data.star_radius = radius_solar * 696340.0 * 100.0
	data.star_color = star_type["color"]
	data.star_luminosity = lerpf(star_type["lum_min"], star_type["lum_max"], rng.randf())
	data.star_name = data.system_name

	# Planets
	var max_planets: int = clampi(int(3 + data.star_luminosity * 2.0 + rng.randf() * 3.0), 2, 8)
	var num_planets: int = rng.randi_range(2, max_planets)

	var base_orbit: float = GAME_AU * (0.2 + rng.randf() * 0.3)
	var orbit_spacing_factor: float = 1.4 + rng.randf() * 0.8
	var current_orbit: float = base_orbit
	var habitable_zone_inner: float = GAME_AU * sqrt(data.star_luminosity) * 0.75
	var habitable_zone_outer: float = GAME_AU * sqrt(data.star_luminosity) * 1.5
	var frost_line: float = GAME_AU * sqrt(data.star_luminosity) * 2.7

	for i in num_planets:
		var p := PlanetData.new()
		var roman: String = ROMAN_NUMERALS[i] if i < ROMAN_NUMERALS.size() else str(i + 1)
		p.planet_name = data.system_name + " " + roman
		p.orbital_radius = current_orbit
		var orbit_au: float = current_orbit / GAME_AU
		p.orbital_period = 600.0 * orbit_au * sqrt(orbit_au)
		p.orbital_angle = rng.randf() * TAU

		# Planet type by orbital zone
		if current_orbit < habitable_zone_inner:
			if rng.randf() < 0.3:
				p.type = PlanetData.PlanetType.LAVA
				p.color = Color(1.0, 0.35, 0.15, 0.9)
			else:
				p.type = PlanetData.PlanetType.ROCKY
				p.color = Color(0.55 + rng.randf() * 0.2, 0.4 + rng.randf() * 0.15, 0.25 + rng.randf() * 0.1, 0.9)
		elif current_orbit < habitable_zone_outer:
			if rng.randf() < 0.4:
				p.type = PlanetData.PlanetType.OCEAN
				p.color = Color(0.15 + rng.randf() * 0.1, 0.35 + rng.randf() * 0.15, 0.7 + rng.randf() * 0.15, 0.9)
			else:
				p.type = PlanetData.PlanetType.ROCKY
				p.color = Color(0.45 + rng.randf() * 0.2, 0.55 + rng.randf() * 0.15, 0.35 + rng.randf() * 0.1, 0.9)
		elif current_orbit < frost_line:
			p.type = PlanetData.PlanetType.GAS_GIANT
			p.color = Color(0.75 + rng.randf() * 0.15, 0.6 + rng.randf() * 0.15, 0.25 + rng.randf() * 0.15, 0.9)
			p.has_rings = rng.randf() < 0.4
		else:
			p.type = PlanetData.PlanetType.ICE
			p.color = Color(0.5 + rng.randf() * 0.15, 0.7 + rng.randf() * 0.1, 0.9 + rng.randf() * 0.1, 0.9)

		# Radius based on type
		match p.type:
			PlanetData.PlanetType.LAVA: p.radius = 1500000.0 + rng.randf() * 2000000.0
			PlanetData.PlanetType.ROCKY: p.radius = 2000000.0 + rng.randf() * 5000000.0
			PlanetData.PlanetType.OCEAN: p.radius = 3000000.0 + rng.randf() * 6000000.0
			PlanetData.PlanetType.GAS_GIANT: p.radius = 15000000.0 + rng.randf() * 40000000.0
			PlanetData.PlanetType.ICE: p.radius = 2000000.0 + rng.randf() * 8000000.0

		data.planets.append(p)
		current_orbit *= orbit_spacing_factor

	# Asteroid belts (2-5, between planet orbits)
	_generate_belts(rng, data, num_planets, habitable_zone_inner, frost_line)

	# Stations
	_generate_stations(rng, data)

	# Jump gates
	_generate_jump_gates(rng, data, connections)

	return data


static func _generate_belts(rng: RandomNumberGenerator, data: StarSystemData, num_planets: int, hab_inner: float, frost_line: float) -> void:
	var num_belts: int = rng.randi_range(2, mini(5, num_planets))
	var used_indices: Array[int] = []

	for i in num_belts:
		var belt_index: int = -1
		for _try in 10:
			var candidate: int = rng.randi_range(1, num_planets - 1)
			if candidate not in used_indices and candidate < data.planets.size():
				belt_index = candidate
				used_indices.append(candidate)
				break
		if belt_index < 0:
			continue

		var inner_orbit: float = data.planets[belt_index - 1].orbital_radius
		var outer_orbit: float = data.planets[belt_index].orbital_radius
		var belt_r: float = (inner_orbit + outer_orbit) * 0.5
		var belt_width: float = (outer_orbit - inner_orbit) * 0.2

		var zone: String
		if belt_r < hab_inner:
			zone = "inner"
		elif belt_r < frost_line:
			zone = "mid"
		else:
			zone = "outer"

		var dominant: StringName = MiningRegistry.pick_resource_for_zone(rng, zone)
		var secondary: StringName = MiningRegistry.pick_secondary(rng, zone, dominant)
		var rare: StringName = MiningRegistry.pick_rare(rng, dominant, secondary)

		var b := AsteroidBeltData.new()
		b.belt_name = data.system_name + " Belt " + str(i + 1)
		b.field_id = StringName("belt_%d" % i)
		b.orbital_radius = belt_r
		b.width = belt_width
		b.dominant_resource = dominant
		b.secondary_resource = secondary
		b.rare_resource = rare
		b.asteroid_count = rng.randi_range(150, 500)
		b.zone = zone
		data.asteroid_belts.append(b)


static func _generate_stations(rng: RandomNumberGenerator, data: StarSystemData) -> void:
	var station_count: int = rng.randi_range(1, 2)
	for i in station_count:
		var planet_idx: int = rng.randi_range(0, mini(2, data.planets.size() - 1))
		var planet: PlanetData = data.planets[planet_idx]
		var station_orbit: float = planet.orbital_radius * 0.95 + rng.randf() * planet.orbital_radius * 0.1

		var prefix: String = STATION_PREFIXES[rng.randi() % STATION_PREFIXES.size()]
		var suffix: String = STATION_SUFFIXES[rng.randi() % STATION_SUFFIXES.size()]

		var s := StationData.new()
		s.station_name = prefix + " " + suffix
		s.station_type = StationData.type_from_string("repair" if i == 0 else STATION_TYPES[rng.randi() % STATION_TYPES.size()])
		s.orbital_radius = station_orbit
		s.orbital_parent = "star_0"
		s.orbital_period = planet.orbital_period * 0.9
		s.orbital_angle = rng.randf() * TAU
		data.stations.append(s)


static func _generate_jump_gates(rng: RandomNumberGenerator, data: StarSystemData, connections: Array[Dictionary]) -> void:
	var max_station_orbit: float = 0.0
	for station in data.stations:
		max_station_orbit = maxf(max_station_orbit, station.orbital_radius)
	var gate_radius: float = max_station_orbit + 3_000_000.0 if max_station_orbit > 0 else 20_000_000.0

	if connections.is_empty():
		return

	for i in connections.size():
		var conn: Dictionary = connections[i]
		# Directional coherence: gate faces toward target system in galaxy space
		var ox: float = conn.get("origin_x", 0.0)
		var oy: float = conn.get("origin_y", 0.0)
		var tx: float = conn.get("target_x", 0.0)
		var ty: float = conn.get("target_y", 0.0)
		var angle: float = atan2(ty - oy, tx - ox)
		# Small jitter (±5°) so gates at the same angle don't overlap
		var jitter_hash: int = hash(data.seed_value + conn["target_id"] * 31)
		angle += (float(jitter_hash % 1000) / 1000.0 - 0.5) * deg_to_rad(10.0)

		var g := JumpGateData.new()
		g.gate_name = "Gate → " + conn["target_name"]
		g.target_system_id = conn["target_id"]
		g.target_system_name = conn["target_name"]
		g.pos_x = cos(angle) * gate_radius
		g.pos_y = (rng.randf() - 0.5) * gate_radius * 0.05
		g.pos_z = sin(angle) * gate_radius
		data.jump_gates.append(g)


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
