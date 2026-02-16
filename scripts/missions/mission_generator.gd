class_name MissionGenerator
extends RefCounted

# =============================================================================
# Mission Generator - Procedural mission factory
# Generates random missions appropriate for a station/system context.
# Deterministic seeding ensures missions refresh daily but stay consistent.
# =============================================================================

# --- Kill Mission Templates (French) ---
const KILL_TITLES: PackedStringArray = PackedStringArray([
	"Chasse aux pirates",
	"Elimination de menaces",
	"Nettoyage de secteur",
	"Prime de combat",
	"Contrat d'extermination",
	"Purge du systeme",
	"Offensive tactique",
	"Assaut preventif",
])

const KILL_DESCRIPTIONS: PackedStringArray = PackedStringArray([
	"Des vaisseaux hostiles ont ete reperes dans le secteur. Eliminez-les pour securiser la zone.",
	"La faction locale offre une prime pour la destruction de menaces hostiles.",
	"Un groupe de pirates menace les routes commerciales. Detruisez-les.",
	"Les scanners detectent une activite ennemie. Neutralisez les cibles designees.",
	"Des raiders perturbent les operations dans ce systeme. Intervenez.",
	"La securite du secteur est compromise. Une intervention armee est requise.",
	"Les patrouilles signalent des contacts hostiles. Eliminaton prioritaire.",
	"Un contrat de nettoyage est disponible. Recompense a la cle.",
])

# Base reward per danger level (credits)
const BASE_REWARD_CREDITS: int = 5000
# Reputation reward multiplier
const BASE_REWARD_REP: float = 2.0


## Generate a batch of missions for a given station context.
## Uses deterministic seeding so missions refresh daily but are consistent.
static func generate_missions(
		system_id: int,
		station_type: int,
		danger_level: int,
		faction_id: StringName,
		count: int = 4
) -> Array[MissionData]:
	# Deterministic seed: day-of-year ensures daily refresh
	var day_of_year: int = _get_day_of_year()
	var base_seed: int = system_id * 10000 + station_type * 1000 + day_of_year
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed

	var missions: Array[MissionData] = []
	var clamped_danger: int = clampi(danger_level, 1, 5)

	for i in count:
		# Reseed per mission for variety while staying deterministic
		rng.seed = base_seed + i * 7919  # prime offset

		var m := _generate_kill_mission(rng, system_id, clamped_danger, faction_id, i)
		missions.append(m)

	return missions


## Generate a single kill mission.
static func _generate_kill_mission(
		rng: RandomNumberGenerator,
		system_id: int,
		danger_level: int,
		faction_id: StringName,
		index: int
) -> MissionData:
	var m := MissionData.new()

	# Unique ID
	var day: int = _get_day_of_year()
	m.mission_id = "mission_%d_%d_%d" % [system_id, day, index]
	m.mission_type = &"kill"
	m.faction_id = faction_id
	m.system_id = system_id
	m.danger_level = danger_level

	# Title + description from templates
	var title_idx: int = rng.randi_range(0, KILL_TITLES.size() - 1)
	var desc_idx: int = rng.randi_range(0, KILL_DESCRIPTIONS.size() - 1)
	m.title = KILL_TITLES[title_idx]
	m.description = KILL_DESCRIPTIONS[desc_idx]

	# Target count scales with danger
	var target_count: int = danger_level + rng.randi_range(1, 3)

	# Determine target faction based on system danger
	var target_faction: StringName = &"hostile"

	# Build objective
	var label: String = "Detruire %d hostiles" % target_count
	m.objectives.append({
		"type": "kill",
		"target_faction": String(target_faction),
		"count": target_count,
		"current": 0,
		"label": label,
	})

	# Rewards scale with danger and target count
	var base: int = BASE_REWARD_CREDITS * danger_level
	var randomized: float = float(base) * (0.8 + rng.randf() * 0.4)  # +/- 20%
	m.reward_credits = int(randomized) + target_count * 500
	m.reward_reputation = BASE_REWARD_REP * float(danger_level)

	# Timed missions for high danger (optional)
	if danger_level >= 4 and rng.randf() < 0.4:
		m.time_limit = 600.0  # 10 minutes
		m.time_remaining = 600.0

	return m


## Returns the day-of-year (1-366) for deterministic daily seeding.
static func _get_day_of_year() -> int:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var month: int = dt.get("month", 1)
	var day: int = dt.get("day", 1)
	# Approximate day-of-year (close enough for seeding)
	var days_per_month: PackedInt32Array = PackedInt32Array([0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334])
	var month_idx: int = clampi(month - 1, 0, 11)
	return days_per_month[month_idx] + day
