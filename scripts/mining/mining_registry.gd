class_name MiningRegistry
extends RefCounted

# =============================================================================
# Mining Registry - Static database of all minable resources
# Pattern: same as WeaponRegistry (static cache + builder functions)
# =============================================================================

static var _cache: Dictionary = {}


static func get_resource(id: StringName) -> MiningResource:
	if _cache.has(id):
		return _cache[id]

	var r: MiningResource = null
	match id:
		&"ice": r = _build_ice()
		&"iron": r = _build_iron()
		&"copper": r = _build_copper()
		&"titanium": r = _build_titanium()
		&"gold": r = _build_gold()
		&"crystal": r = _build_crystal()
		&"uranium": r = _build_uranium()
		&"platinum": r = _build_platinum()
		_:
			push_error("MiningRegistry: Unknown resource '%s'" % id)
			return null

	_cache[id] = r
	return r


static func get_all_ids() -> Array[StringName]:
	return [&"ice", &"iron", &"copper", &"titanium", &"gold", &"crystal", &"uranium", &"platinum"]


## Returns a resource id weighted by rarity for a given zone.
## zone: "inner" (metals), "mid" (mixed), "outer" (ice/rare)
static func pick_resource_for_zone(rng: RandomNumberGenerator, zone: String) -> StringName:
	var roll: float = rng.randf()
	match zone:
		"inner":
			if roll < 0.35: return &"iron"
			if roll < 0.60: return &"copper"
			if roll < 0.80: return &"titanium"
			if roll < 0.92: return &"gold"
			return &"platinum"
		"outer":
			if roll < 0.40: return &"ice"
			if roll < 0.60: return &"iron"
			if roll < 0.75: return &"crystal"
			if roll < 0.88: return &"uranium"
			return &"platinum"
		_:  # "mid"
			if roll < 0.20: return &"ice"
			if roll < 0.40: return &"iron"
			if roll < 0.55: return &"copper"
			if roll < 0.70: return &"titanium"
			if roll < 0.82: return &"gold"
			if roll < 0.92: return &"crystal"
			if roll < 0.97: return &"uranium"
			return &"platinum"


## Pick a secondary resource different from the dominant one.
static func pick_secondary(rng: RandomNumberGenerator, zone: String, dominant: StringName) -> StringName:
	for _i in 10:
		var pick := pick_resource_for_zone(rng, zone)
		if pick != dominant:
			return pick
	return &"iron"


## Pick a rare resource (RARE or above) different from dominant/secondary.
static func pick_rare(rng: RandomNumberGenerator, dominant: StringName, secondary: StringName) -> StringName:
	var rare_ids: Array[StringName] = [&"gold", &"crystal", &"uranium", &"platinum"]
	for _i in 10:
		var pick: StringName = rare_ids[rng.randi() % rare_ids.size()]
		if pick != dominant and pick != secondary:
			return pick
	return &"crystal"


# === Resource Builders ===

static func _build_ice() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"ice"
	r.resource_name = "Glace"
	r.rarity = MiningResource.Rarity.COMMON
	r.base_value = 5
	r.mining_difficulty = 0.5
	r.color = Color(0.75, 0.85, 1.0)
	r.icon_color = Color(0.6, 0.8, 1.0)
	r.description = "Eau gelée extraite d'astéroïdes. Ressource de base."
	return r


static func _build_iron() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"iron"
	r.resource_name = "Fer"
	r.rarity = MiningResource.Rarity.COMMON
	r.base_value = 10
	r.mining_difficulty = 1.0
	r.color = Color(0.45, 0.42, 0.4)
	r.icon_color = Color(0.6, 0.58, 0.55)
	r.description = "Minerai de fer. Matériau de construction essentiel."
	return r


static func _build_copper() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"copper"
	r.resource_name = "Cuivre"
	r.rarity = MiningResource.Rarity.UNCOMMON
	r.base_value = 25
	r.mining_difficulty = 1.2
	r.color = Color(0.72, 0.45, 0.2)
	r.icon_color = Color(0.85, 0.55, 0.25)
	r.description = "Minerai de cuivre. Utilisé en électronique."
	return r


static func _build_titanium() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"titanium"
	r.resource_name = "Titane"
	r.rarity = MiningResource.Rarity.UNCOMMON
	r.base_value = 40
	r.mining_difficulty = 1.5
	r.color = Color(0.7, 0.75, 0.85)
	r.icon_color = Color(0.75, 0.8, 0.9)
	r.description = "Titane. Alliage léger et résistant pour blindages."
	return r


static func _build_gold() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"gold"
	r.resource_name = "Or"
	r.rarity = MiningResource.Rarity.RARE
	r.base_value = 100
	r.mining_difficulty = 2.0
	r.color = Color(0.85, 0.7, 0.2)
	r.icon_color = Color(1.0, 0.85, 0.3)
	r.description = "Or. Métal précieux à haute conductivité."
	return r


static func _build_crystal() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"crystal"
	r.resource_name = "Cristal"
	r.rarity = MiningResource.Rarity.RARE
	r.base_value = 150
	r.mining_difficulty = 2.5
	r.color = Color(0.6, 0.3, 0.9)
	r.icon_color = Color(0.4, 0.8, 0.9)
	r.description = "Cristal énergétique. Composant de haute technologie."
	return r


static func _build_uranium() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"uranium"
	r.resource_name = "Uranium"
	r.rarity = MiningResource.Rarity.VERY_RARE
	r.base_value = 200
	r.mining_difficulty = 3.0
	r.color = Color(0.2, 0.8, 0.3)
	r.icon_color = Color(0.3, 1.0, 0.4)
	r.description = "Uranium enrichi. Combustible nucléaire."
	return r


static func _build_platinum() -> MiningResource:
	var r := MiningResource.new()
	r.resource_id = &"platinum"
	r.resource_name = "Platine"
	r.rarity = MiningResource.Rarity.LEGENDARY
	r.base_value = 500
	r.mining_difficulty = 4.0
	r.color = Color(0.9, 0.92, 0.95)
	r.icon_color = Color(0.95, 0.95, 1.0)
	r.description = "Platine. Métal noble d'une rareté exceptionnelle."
	return r
