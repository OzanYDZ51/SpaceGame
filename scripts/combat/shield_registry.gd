class_name ShieldRegistry
extends RefCounted

# =============================================================================
# Shield Registry - Static database of all shield definitions
# =============================================================================

static var _cache: Dictionary = {}


static func get_shield(shield_name: StringName) -> ShieldResource:
	if _cache.has(shield_name):
		return _cache[shield_name]

	var s: ShieldResource = null
	match shield_name:
		&"Bouclier Basique Mk1": s = _build_basique_mk1()
		&"Bouclier Basique Mk2": s = _build_basique_mk2()
		&"Bouclier Renforce": s = _build_renforce()
		&"Bouclier Prismatique": s = _build_prismatique()
		&"Bouclier de Combat": s = _build_combat()
		&"Bouclier Lourd": s = _build_lourd()
		&"Bouclier Experimental": s = _build_experimental()
		_:
			push_error("ShieldRegistry: Unknown shield '%s'" % shield_name)
			return null

	_cache[shield_name] = s
	return s


static func get_default_shield(ship_class: StringName) -> StringName:
	match ship_class:
		&"Scout", &"Interceptor", &"Fighter":
			return &"Bouclier Basique Mk1"
		&"Bomber", &"Corvette":
			return &"Bouclier Renforce"
		&"Frigate", &"Cruiser":
			return &"Bouclier Lourd"
	return &"Bouclier Basique Mk1"


static func get_all_shield_names() -> Array[StringName]:
	_ensure_all_loaded()
	var result: Array[StringName] = []
	for key in _cache:
		result.append(key)
	result.sort()
	return result


static func _ensure_all_loaded() -> void:
	var all: Array[StringName] = [
		&"Bouclier Basique Mk1", &"Bouclier Basique Mk2", &"Bouclier Renforce",
		&"Bouclier Prismatique", &"Bouclier de Combat", &"Bouclier Lourd",
		&"Bouclier Experimental",
	]
	for n in all:
		if not _cache.has(n):
			get_shield(n)


# === Builders ===

static func _build_basique_mk1() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Basique Mk1"
	s.slot_size = 0  # S
	s.shield_hp_per_facing = 100.0
	s.regen_rate = 12.0
	s.regen_delay = 4.0
	s.bleedthrough = 0.12
	return s


static func _build_basique_mk2() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Basique Mk2"
	s.slot_size = 0  # S
	s.shield_hp_per_facing = 150.0
	s.regen_rate = 15.0
	s.regen_delay = 3.5
	s.bleedthrough = 0.10
	return s


static func _build_renforce() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Renforce"
	s.slot_size = 1  # M
	s.shield_hp_per_facing = 200.0
	s.regen_rate = 18.0
	s.regen_delay = 4.0
	s.bleedthrough = 0.08
	return s


static func _build_prismatique() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Prismatique"
	s.slot_size = 1  # M
	s.shield_hp_per_facing = 150.0
	s.regen_rate = 25.0
	s.regen_delay = 2.5
	s.bleedthrough = 0.15
	return s


static func _build_combat() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier de Combat"
	s.slot_size = 1  # M
	s.shield_hp_per_facing = 250.0
	s.regen_rate = 20.0
	s.regen_delay = 5.0
	s.bleedthrough = 0.05
	return s


static func _build_lourd() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Lourd"
	s.slot_size = 2  # L
	s.shield_hp_per_facing = 375.0
	s.regen_rate = 25.0
	s.regen_delay = 6.0
	s.bleedthrough = 0.03
	return s


static func _build_experimental() -> ShieldResource:
	var s := ShieldResource.new()
	s.shield_name = &"Bouclier Experimental"
	s.slot_size = 2  # L
	s.shield_hp_per_facing = 300.0
	s.regen_rate = 40.0
	s.regen_delay = 2.0
	s.bleedthrough = 0.10
	return s
