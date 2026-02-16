class_name POIGenerator
extends RefCounted

# =============================================================================
# POI Generator - Procedurally generates POIs for a star system
# Deterministic RNG seeded by system_id ensures same POIs every visit.
# =============================================================================

# --- Name pools (user-facing French) ---

const WRECK_SHIP_NAMES: Array = [
	"Prometheus", "Eclipse", "Vanguard", "Tempete", "Horizon",
	"Nemesis", "Titan", "Orion", "Pegasus", "Valkyrie",
	"Centurion", "Corsaire", "Atlas",
]

const WRECK_TEMPLATES: Array = [
	"Epave du %s",
	"Debris de vaisseau %s",
	"Carcasse du %s",
	"Vaisseau fantome %s",
]

const CARGO_NAMES: Array = [
	"Cache de contrebande",
	"Conteneur derivant",
	"Cargaison larguee",
	"Reserve secrete",
	"Caisse abandonnee",
]

const ANOMALY_NAMES: Array = [
	"Anomalie gravitationnelle",
	"Perturbation quantique",
	"Energie residuelle",
	"Fluctuation spatiale",
	"Distorsion temporelle",
]

const DISTRESS_NAMES: Array = [
	"SOS - Vaisseau en detresse",
	"Signal de detresse automatique",
	"Balise de secours",
	"Appel d'urgence",
	"Vaisseau immobilise",
]

const SCANNER_ECHO_NAMES: Array = [
	"Signal faible",
	"Echo radar",
	"Trace energetique",
	"Resonance inconnue",
	"Frequence residuelle",
]

const WRECK_DESCRIPTIONS: Array = [
	"Les restes d'un vaisseau detruit flottent dans le vide.",
	"Un signal faible emane de cette epave a la derive.",
	"Des debris metalliques tourbillonnent lentement.",
]

const CARGO_DESCRIPTIONS: Array = [
	"Un conteneur scelle derive dans l'espace.",
	"Quelqu'un a largue cette cargaison a la hate.",
	"Une cache cachee derriere un champ d'asteroides.",
]

const ANOMALY_DESCRIPTIONS: Array = [
	"Une etrange distorsion de l'espace-temps.",
	"Des lectures energetiques inexplicables.",
	"Un phenomene inconnu qui defie les lois physiques.",
]

const DISTRESS_DESCRIPTIONS: Array = [
	"Un signal de detresse automatique en boucle.",
	"Un appel desespere resonne sur toutes les frequences.",
	"Quelqu'un a besoin d'aide... ou c'est un piege.",
]

const SCANNER_ECHO_DESCRIPTIONS: Array = [
	"Un signal a peine perceptible sur les capteurs.",
	"Vos scanners detectent une trace energetique residuelle.",
	"Un echo faible qui pourrait mener a quelque chose d'interessant.",
]

# --- Weight tables by danger tier ---

# Weights: [WRECK, CARGO_CACHE, ANOMALY, DISTRESS_SIGNAL, SCANNER_ECHO]
const WEIGHTS_LOW: Array = [10, 30, 10, 5, 45]
const WEIGHTS_MID: Array = [20, 25, 20, 15, 20]
const WEIGHTS_HIGH: Array = [30, 15, 25, 25, 5]

# --- Ore types for cargo rewards ---
const ORE_TYPES: Array = [
	&"iron", &"nickel", &"cobalt", &"titanium",
	&"gold", &"platinum", &"uranium", &"iridium",
]

# --- Minimum distance from star center ---
const MIN_STAR_DISTANCE: float = 5000.0

# --- POI position range ---
const MIN_RADIUS: float = 50000.0
const MAX_RADIUS: float = 80000000.0


static func generate_pois(system_id: int, danger_level: int) -> Array[POIData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = system_id * 73856 + 12345

	var danger_clamped: int = clampi(danger_level, 0, 5)
	var poi_count: int = 2 + danger_clamped + rng.randi_range(0, 2)

	# Select weight table based on danger tier
	var weights: Array
	if danger_clamped <= 1:
		weights = WEIGHTS_LOW
	elif danger_clamped <= 3:
		weights = WEIGHTS_MID
	else:
		weights = WEIGHTS_HIGH

	var danger_mult: float = 1.0 + danger_clamped * 0.5

	var pois: Array[POIData] = []
	var scanner_echo_indices: Array[int] = []

	for i in poi_count:
		var poi := POIData.new()
		poi.poi_id = "poi_sys%d_%d" % [system_id, i]
		poi.system_id = system_id
		poi.danger_level = danger_clamped

		# Pick type using weighted random
		poi.poi_type = _pick_weighted_type(rng, weights)

		# Generate position (random within system radius, avoiding star)
		var angle: float = rng.randf() * TAU
		var dist: float = lerpf(MIN_RADIUS, MAX_RADIUS, rng.randf())
		if dist < MIN_STAR_DISTANCE:
			dist = MIN_STAR_DISTANCE + rng.randf() * 10000.0
		poi.pos_x = cos(angle) * dist
		poi.pos_z = sin(angle) * dist

		# Generate name, description, rewards based on type
		match poi.poi_type:
			POIData.Type.WRECK:
				var ship_name: String = WRECK_SHIP_NAMES[rng.randi() % WRECK_SHIP_NAMES.size()]
				var template: String = WRECK_TEMPLATES[rng.randi() % WRECK_TEMPLATES.size()]
				poi.display_name = template % ship_name
				poi.description = WRECK_DESCRIPTIONS[rng.randi() % WRECK_DESCRIPTIONS.size()]
				poi.rewards = _generate_wreck_rewards(rng, danger_mult)
				poi.discovery_range = 2000.0
				poi.interaction_range = 200.0

			POIData.Type.CARGO_CACHE:
				poi.display_name = CARGO_NAMES[rng.randi() % CARGO_NAMES.size()]
				poi.description = CARGO_DESCRIPTIONS[rng.randi() % CARGO_DESCRIPTIONS.size()]
				poi.rewards = _generate_cargo_rewards(rng, danger_mult)
				poi.discovery_range = 1500.0
				poi.interaction_range = 150.0

			POIData.Type.ANOMALY:
				poi.display_name = ANOMALY_NAMES[rng.randi() % ANOMALY_NAMES.size()]
				poi.description = ANOMALY_DESCRIPTIONS[rng.randi() % ANOMALY_DESCRIPTIONS.size()]
				poi.rewards = _generate_anomaly_rewards(rng, danger_clamped)
				poi.discovery_range = 3000.0
				poi.interaction_range = 300.0

			POIData.Type.DISTRESS_SIGNAL:
				poi.display_name = DISTRESS_NAMES[rng.randi() % DISTRESS_NAMES.size()]
				poi.description = DISTRESS_DESCRIPTIONS[rng.randi() % DISTRESS_DESCRIPTIONS.size()]
				poi.rewards = _generate_distress_rewards(rng, danger_mult)
				poi.discovery_range = 5000.0
				poi.interaction_range = 500.0

			POIData.Type.SCANNER_ECHO:
				poi.display_name = SCANNER_ECHO_NAMES[rng.randi() % SCANNER_ECHO_NAMES.size()]
				poi.description = SCANNER_ECHO_DESCRIPTIONS[rng.randi() % SCANNER_ECHO_DESCRIPTIONS.size()]
				poi.rewards = {}
				poi.discovery_range = 1000.0
				poi.interaction_range = 100.0
				scanner_echo_indices.append(i)

		pois.append(poi)

	# Link scanner echoes to a richer non-echo POI in the same system
	_link_scanner_echoes(pois, scanner_echo_indices)

	return pois


static func _pick_weighted_type(rng: RandomNumberGenerator, weights: Array) -> int:
	var total: int = 0
	for w in weights:
		total += w
	var roll: int = rng.randi_range(0, total - 1)
	var cumulative: int = 0
	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return 0


static func _generate_wreck_rewards(rng: RandomNumberGenerator, danger_mult: float) -> Dictionary:
	var rewards: Dictionary = {}
	rewards["credits"] = int(rng.randi_range(2000, 10000) * danger_mult)

	# 1-2 ore types
	var ore_count: int = rng.randi_range(1, 2)
	for _i in ore_count:
		var ore: StringName = ORE_TYPES[rng.randi() % ORE_TYPES.size()]
		var amount: int = rng.randi_range(10, 50)
		rewards[String(ore)] = rewards.get(String(ore), 0) + amount

	# Chance for data_chip (scales with danger)
	if rng.randf() < 0.2 * danger_mult:
		rewards["data_chip"] = rng.randi_range(1, int(ceilf(danger_mult)))

	return rewards


static func _generate_cargo_rewards(rng: RandomNumberGenerator, danger_mult: float) -> Dictionary:
	var rewards: Dictionary = {}

	# Resources: 1-3 ore types with higher amounts
	var ore_count: int = rng.randi_range(1, 3)
	for _i in ore_count:
		var ore: StringName = ORE_TYPES[rng.randi() % ORE_TYPES.size()]
		var amount: int = int(rng.randi_range(20, 100) * danger_mult)
		rewards[String(ore)] = rewards.get(String(ore), 0) + amount

	# Small credit bonus
	if rng.randf() < 0.5:
		rewards["credits"] = int(rng.randi_range(1000, 5000) * danger_mult)

	return rewards


static func _generate_anomaly_rewards(rng: RandomNumberGenerator, danger_clamped: int) -> Dictionary:
	# Anomalies give effects, not direct loot.
	# Store the effect type in rewards for the manager to interpret.
	var effects: Array = ["shield_boost", "energy_recharge", "damage", "speed_boost"]
	var effect: String = effects[rng.randi() % effects.size()]

	# Higher danger = more chance of negative effects
	if danger_clamped >= 3 and rng.randf() < 0.4:
		effect = "damage"

	var intensity: float = 0.5 + rng.randf() * 0.5  # 0.5 - 1.0 multiplier

	return {
		"effect": effect,
		"intensity": intensity,
		"duration": rng.randf_range(5.0, 15.0),
	}


static func _generate_distress_rewards(rng: RandomNumberGenerator, danger_mult: float) -> Dictionary:
	var rewards: Dictionary = {}
	rewards["credits"] = int(rng.randi_range(10000, 50000) * danger_mult)

	# Chance for rare materials
	if rng.randf() < 0.3:
		rewards["data_chip"] = rng.randi_range(2, 5)

	# Encounter sub-type for future mission system
	var encounter_types: Array = ["defend_freighter", "ambush_trap", "rescue_mission"]
	rewards["encounter_type"] = encounter_types[rng.randi() % encounter_types.size()]

	return rewards


static func _link_scanner_echoes(pois: Array[POIData], echo_indices: Array[int]) -> void:
	# Collect indices of non-echo POIs
	var target_indices: Array[int] = []
	for i in pois.size():
		if pois[i].poi_type != POIData.Type.SCANNER_ECHO:
			target_indices.append(i)

	if target_indices.is_empty():
		return

	# Link each echo to the nearest non-echo POI
	for echo_idx in echo_indices:
		var echo: POIData = pois[echo_idx]
		var best_idx: int = target_indices[0]
		var best_dist: float = INF

		for t_idx in target_indices:
			var target: POIData = pois[t_idx]
			var dx: float = echo.pos_x - target.pos_x
			var dz: float = echo.pos_z - target.pos_z
			var dist: float = dx * dx + dz * dz
			if dist < best_dist:
				best_dist = dist
				best_idx = t_idx

		echo.linked_poi_id = pois[best_idx].poi_id
