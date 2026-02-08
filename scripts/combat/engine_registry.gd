class_name EngineRegistry
extends RefCounted

# =============================================================================
# Engine Registry - Static database of all engine definitions
# =============================================================================

static var _cache: Dictionary = {}


static func get_engine(engine_name: StringName) -> EngineResource:
	if _cache.has(engine_name):
		return _cache[engine_name]

	var e: EngineResource = null
	match engine_name:
		&"Propulseur Standard Mk1": e = _build_standard_mk1()
		&"Propulseur Standard Mk2": e = _build_standard_mk2()
		&"Propulseur de Combat": e = _build_combat()
		&"Propulseur d'Exploration": e = _build_exploration()
		&"Propulseur de Course": e = _build_course()
		&"Propulseur Militaire": e = _build_militaire()
		&"Propulseur Experimental": e = _build_experimental()
		_:
			push_error("EngineRegistry: Unknown engine '%s'" % engine_name)
			return null

	_cache[engine_name] = e
	return e


static func get_default_engine(ship_class: StringName) -> StringName:
	match ship_class:
		&"Scout", &"Interceptor", &"Fighter":
			return &"Propulseur Standard Mk1"
		&"Bomber", &"Corvette":
			return &"Propulseur de Combat"
		&"Frigate", &"Cruiser":
			return &"Propulseur Militaire"
	return &"Propulseur Standard Mk1"


static func get_all_engine_names() -> Array[StringName]:
	_ensure_all_loaded()
	var result: Array[StringName] = []
	for key in _cache:
		result.append(key)
	result.sort()
	return result


static func _ensure_all_loaded() -> void:
	var all: Array[StringName] = [
		&"Propulseur Standard Mk1", &"Propulseur Standard Mk2", &"Propulseur de Combat",
		&"Propulseur d'Exploration", &"Propulseur de Course", &"Propulseur Militaire",
		&"Propulseur Experimental",
	]
	for n in all:
		if not _cache.has(n):
			get_engine(n)


# === Builders ===

static func _build_standard_mk1() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur Standard Mk1"
	e.slot_size = 0  # S
	e.accel_mult = 1.0
	e.speed_mult = 1.0
	e.rotation_mult = 1.0
	e.cruise_mult = 1.0
	e.boost_drain_mult = 1.0
	return e


static func _build_standard_mk2() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur Standard Mk2"
	e.slot_size = 0  # S
	e.accel_mult = 1.1
	e.speed_mult = 1.05
	e.rotation_mult = 1.05
	e.cruise_mult = 1.05
	e.boost_drain_mult = 1.0
	return e


static func _build_combat() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur de Combat"
	e.slot_size = 1  # M
	e.accel_mult = 1.3
	e.speed_mult = 1.0
	e.rotation_mult = 1.15
	e.cruise_mult = 0.9
	e.boost_drain_mult = 1.0
	return e


static func _build_exploration() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur d'Exploration"
	e.slot_size = 1  # M
	e.accel_mult = 0.9
	e.speed_mult = 1.0
	e.rotation_mult = 1.0
	e.cruise_mult = 1.4
	e.boost_drain_mult = 0.9
	return e


static func _build_course() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur de Course"
	e.slot_size = 1  # M
	e.accel_mult = 1.15
	e.speed_mult = 1.2
	e.rotation_mult = 1.0
	e.cruise_mult = 1.2
	e.boost_drain_mult = 1.2
	return e


static func _build_militaire() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur Militaire"
	e.slot_size = 2  # L
	e.accel_mult = 1.25
	e.speed_mult = 1.15
	e.rotation_mult = 1.1
	e.cruise_mult = 1.1
	e.boost_drain_mult = 1.0
	return e


static func _build_experimental() -> EngineResource:
	var e := EngineResource.new()
	e.engine_name = &"Propulseur Experimental"
	e.slot_size = 2  # L
	e.accel_mult = 1.35
	e.speed_mult = 1.2
	e.rotation_mult = 1.15
	e.cruise_mult = 1.25
	e.boost_drain_mult = 1.3
	return e
