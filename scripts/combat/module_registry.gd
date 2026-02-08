class_name ModuleRegistry
extends RefCounted

# =============================================================================
# Module Registry - Static database of all module definitions
# =============================================================================

static var _cache: Dictionary = {}


static func get_module(module_name: StringName) -> ModuleResource:
	if _cache.has(module_name):
		return _cache[module_name]

	var m: ModuleResource = null
	match module_name:
		&"Blindage Renforce": m = _build_blindage_renforce()
		&"Condensateur d'Energie": m = _build_condensateur()
		&"Amplificateur de Bouclier": m = _build_amplificateur()
		&"Dissipateur Thermique": m = _build_dissipateur()
		&"Scanner Ameliore": m = _build_scanner()
		&"Blindage Lourd": m = _build_blindage_lourd()
		&"Generateur Auxiliaire": m = _build_generateur()
		&"Systeme de Ciblage": m = _build_ciblage()
		&"Reacteur Auxiliaire": m = _build_reacteur()
		&"Module de Renfort": m = _build_renfort()
		_:
			push_error("ModuleRegistry: Unknown module '%s'" % module_name)
			return null

	_cache[module_name] = m
	return m


static func get_default_modules(ship_class: StringName) -> Array[StringName]:
	match ship_class:
		&"Scout":
			return [&"Blindage Renforce"]
		&"Interceptor":
			return [&"Blindage Renforce", &"Dissipateur Thermique"]
		&"Fighter":
			return [&"Blindage Renforce", &"Condensateur d'Energie"]
		&"Bomber":
			return [&"Blindage Renforce", &"Amplificateur de Bouclier"]
		&"Corvette":
			return [&"Blindage Renforce", &"Condensateur d'Energie", &"Amplificateur de Bouclier"]
		&"Frigate":
			return [&"Blindage Renforce", &"Generateur Auxiliaire", &"Amplificateur de Bouclier", &"Systeme de Ciblage"]
		&"Cruiser":
			return [&"Blindage Renforce", &"Blindage Lourd", &"Generateur Auxiliaire", &"Amplificateur de Bouclier", &"Module de Renfort"]
	return [&"Blindage Renforce"]


static func get_all_module_names() -> Array[StringName]:
	_ensure_all_loaded()
	var result: Array[StringName] = []
	for key in _cache:
		result.append(key)
	result.sort()
	return result


static func _ensure_all_loaded() -> void:
	var all: Array[StringName] = [
		&"Blindage Renforce", &"Condensateur d'Energie", &"Amplificateur de Bouclier",
		&"Dissipateur Thermique", &"Scanner Ameliore", &"Blindage Lourd",
		&"Generateur Auxiliaire", &"Systeme de Ciblage", &"Reacteur Auxiliaire",
		&"Module de Renfort",
	]
	for n in all:
		if not _cache.has(n):
			get_module(n)


# === Builders ===

static func _build_blindage_renforce() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Blindage Renforce"
	m.slot_size = 0  # S
	m.module_type = ModuleResource.ModuleType.COQUE
	m.hull_bonus = 100.0
	m.armor_bonus = 5.0
	m.price = 1500
	return m


static func _build_condensateur() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Condensateur d'Energie"
	m.slot_size = 0  # S
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 20.0
	m.energy_regen_bonus = 5.0
	m.price = 2000
	return m


static func _build_amplificateur() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Amplificateur de Bouclier"
	m.slot_size = 0  # S
	m.module_type = ModuleResource.ModuleType.BOUCLIER
	m.shield_regen_mult = 1.15
	m.price = 2500
	return m


static func _build_dissipateur() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Dissipateur Thermique"
	m.slot_size = 0  # S
	m.module_type = ModuleResource.ModuleType.ARME
	m.weapon_energy_mult = 0.85
	m.price = 3000
	return m


static func _build_scanner() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Scanner Ameliore"
	m.slot_size = 1  # M
	m.module_type = ModuleResource.ModuleType.SCANNER
	# Placeholder — future scanner range bonus
	m.price = 5000
	return m


static func _build_blindage_lourd() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Blindage Lourd"
	m.slot_size = 1  # M
	m.module_type = ModuleResource.ModuleType.COQUE
	m.hull_bonus = 250.0
	m.armor_bonus = 10.0
	m.price = 7000
	return m


static func _build_generateur() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Generateur Auxiliaire"
	m.slot_size = 1  # M
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 50.0
	m.energy_regen_bonus = 15.0
	m.price = 8000
	return m


static func _build_ciblage() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Systeme de Ciblage"
	m.slot_size = 1  # M
	m.module_type = ModuleResource.ModuleType.ARME
	m.weapon_range_mult = 1.2
	m.price = 10000
	return m


static func _build_reacteur() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Reacteur Auxiliaire"
	m.slot_size = 2  # L
	m.module_type = ModuleResource.ModuleType.ENERGIE
	m.energy_cap_bonus = 100.0
	m.energy_regen_bonus = 25.0
	m.price = 20000
	return m


static func _build_renfort() -> ModuleResource:
	var m := ModuleResource.new()
	m.module_name = &"Module de Renfort"
	m.slot_size = 2  # L
	m.module_type = ModuleResource.ModuleType.BOUCLIER
	m.shield_cap_mult = 1.3
	m.price = 25000
	return m
