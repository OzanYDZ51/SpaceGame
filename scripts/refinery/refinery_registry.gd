class_name RefineryRegistry
extends RefCounted

# =============================================================================
# Refinery Registry — static cache of all refining recipes (18 total, 3 tiers).
# Pattern follows MiningRegistry / WeaponRegistry.
# =============================================================================

static var _cache: Dictionary = {}
static var _all_ids: Array[StringName] = []
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_register_tier1()
	_register_tier2()
	_register_tier3()


static func get_recipe(id: StringName) -> RefineryRecipe:
	_ensure_init()
	return _cache.get(id) as RefineryRecipe


static func get_all_ids() -> Array[StringName]:
	_ensure_init()
	return _all_ids.duplicate()


static func get_all() -> Array[RefineryRecipe]:
	_ensure_init()
	var result: Array[RefineryRecipe] = []
	for id in _all_ids:
		result.append(_cache[id])
	return result


static func get_by_tier(tier: int) -> Array[RefineryRecipe]:
	_ensure_init()
	var result: Array[RefineryRecipe] = []
	for id in _all_ids:
		var r: RefineryRecipe = _cache[id]
		if r.tier == tier:
			result.append(r)
	return result


static func get_display_name(item_id: StringName) -> String:
	_ensure_init()
	var r: RefineryRecipe = _cache.get(item_id) as RefineryRecipe
	if r:
		return r.display_name
	# Fallback to mining resource names
	var mr := MiningRegistry.get_resource(item_id)
	if mr:
		return mr.display_name
	return str(item_id)


static func get_item_value(item_id: StringName) -> int:
	_ensure_init()
	var r: RefineryRecipe = _cache.get(item_id) as RefineryRecipe
	if r:
		return r.value
	var mr := MiningRegistry.get_resource(item_id)
	if mr:
		return mr.base_value
	return 0


static func get_item_color(item_id: StringName) -> Color:
	_ensure_init()
	var r: RefineryRecipe = _cache.get(item_id) as RefineryRecipe
	if r:
		return r.icon_color
	var mr := MiningRegistry.get_resource(item_id)
	if mr:
		return mr.icon_color
	return Color.WHITE


static func _reg(r: RefineryRecipe) -> void:
	_cache[r.recipe_id] = r
	_all_ids.append(r.recipe_id)


# =========================================================================
# Tier 1 — Refined materials (simple conversion, single input)
# =========================================================================
static func _register_tier1() -> void:
	var r: RefineryRecipe

	r = RefineryRecipe.new()
	r.recipe_id = &"water"
	r.display_name = "Eau Pure"
	r.tier = 1
	r.inputs = [{id = &"ice", qty = 3}]
	r.output_id = &"water"
	r.duration = 30.0
	r.value = 20
	r.icon_color = Color(0.4, 0.7, 1.0)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"steel"
	r.display_name = "Acier"
	r.tier = 1
	r.inputs = [{id = &"iron", qty = 3}]
	r.output_id = &"steel"
	r.duration = 45.0
	r.value = 40
	r.icon_color = Color(0.7, 0.7, 0.75)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"copper_wire"
	r.display_name = "Fils de Cuivre"
	r.tier = 1
	r.inputs = [{id = &"copper", qty = 3}]
	r.output_id = &"copper_wire"
	r.duration = 50.0
	r.value = 90
	r.icon_color = Color(0.9, 0.6, 0.3)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"titanium_alloy"
	r.display_name = "Alliage Titane"
	r.tier = 1
	r.inputs = [{id = &"titanium", qty = 3}]
	r.output_id = &"titanium_alloy"
	r.duration = 60.0
	r.value = 150
	r.icon_color = Color(0.8, 0.85, 0.9)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"gold_ingot"
	r.display_name = "Lingot d'Or"
	r.tier = 1
	r.inputs = [{id = &"gold", qty = 2}]
	r.output_id = &"gold_ingot"
	r.duration = 75.0
	r.value = 250
	r.icon_color = Color(1.0, 0.85, 0.2)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"energy_crystal"
	r.display_name = "Cristal Energetique"
	r.tier = 1
	r.inputs = [{id = &"crystal", qty = 2}]
	r.output_id = &"energy_crystal"
	r.duration = 80.0
	r.value = 380
	r.icon_color = Color(0.6, 0.3, 1.0)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"enriched_uranium"
	r.display_name = "Uranium Enrichi"
	r.tier = 1
	r.inputs = [{id = &"uranium", qty = 2}]
	r.output_id = &"enriched_uranium"
	r.duration = 90.0
	r.value = 500
	r.icon_color = Color(0.2, 1.0, 0.3)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"platinum_catalyst"
	r.display_name = "Catalyseur Platine"
	r.tier = 1
	r.inputs = [{id = &"platinum", qty = 2}]
	r.output_id = &"platinum_catalyst"
	r.duration = 100.0
	r.value = 1200
	r.icon_color = Color(0.9, 0.92, 0.95)
	_reg(r)


# =========================================================================
# Tier 2 — Components (multi-input)
# =========================================================================
static func _register_tier2() -> void:
	var r: RefineryRecipe

	r = RefineryRecipe.new()
	r.recipe_id = &"hull_plating"
	r.display_name = "Plaque de Coque"
	r.tier = 2
	r.inputs = [{id = &"steel", qty = 3}, {id = &"titanium_alloy", qty = 1}]
	r.output_id = &"hull_plating"
	r.duration = 120.0
	r.value = 500
	r.icon_color = Color(0.6, 0.65, 0.7)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"circuit_board"
	r.display_name = "Circuit Imprime"
	r.tier = 2
	r.inputs = [{id = &"copper_wire", qty = 2}, {id = &"gold_ingot", qty = 1}]
	r.output_id = &"circuit_board"
	r.duration = 150.0
	r.value = 800
	r.icon_color = Color(0.3, 0.8, 0.3)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"plasma_conduit"
	r.display_name = "Conduit Plasma"
	r.tier = 2
	r.inputs = [{id = &"energy_crystal", qty = 2}, {id = &"platinum_catalyst", qty = 1}]
	r.output_id = &"plasma_conduit"
	r.duration = 180.0
	r.value = 2000
	r.icon_color = Color(0.8, 0.3, 1.0)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"fuel_cell"
	r.display_name = "Cellule Energetique"
	r.tier = 2
	r.inputs = [{id = &"water", qty = 5}, {id = &"enriched_uranium", qty = 1}]
	r.output_id = &"fuel_cell"
	r.duration = 100.0
	r.value = 700
	r.icon_color = Color(0.3, 0.9, 0.9)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"structural_frame"
	r.display_name = "Chassis Structurel"
	r.tier = 2
	r.inputs = [{id = &"steel", qty = 5}, {id = &"titanium_alloy", qty = 2}]
	r.output_id = &"structural_frame"
	r.duration = 160.0
	r.value = 900
	r.icon_color = Color(0.5, 0.55, 0.6)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"sensor_lens"
	r.display_name = "Lentille Sensorielle"
	r.tier = 2
	r.inputs = [{id = &"energy_crystal", qty = 1}, {id = &"gold_ingot", qty = 2}]
	r.output_id = &"sensor_lens"
	r.duration = 140.0
	r.value = 1100
	r.icon_color = Color(1.0, 0.9, 0.4)
	_reg(r)


# =========================================================================
# Tier 3 — Advanced parts (complex, multi-component)
# =========================================================================
static func _register_tier3() -> void:
	var r: RefineryRecipe

	r = RefineryRecipe.new()
	r.recipe_id = &"weapon_core"
	r.display_name = "Noyau d'Arme"
	r.tier = 3
	r.inputs = [{id = &"plasma_conduit", qty = 2}, {id = &"circuit_board", qty = 2}]
	r.output_id = &"weapon_core"
	r.duration = 300.0
	r.value = 5000
	r.icon_color = Color(1.0, 0.3, 0.2)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"shield_gen"
	r.display_name = "Generateur Bouclier"
	r.tier = 3
	r.inputs = [{id = &"plasma_conduit", qty = 1}, {id = &"circuit_board", qty = 1}, {id = &"hull_plating", qty = 2}]
	r.output_id = &"shield_gen"
	r.duration = 360.0
	r.value = 5500
	r.icon_color = Color(0.3, 0.5, 1.0)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"engine_assembly"
	r.display_name = "Bloc Propulseur"
	r.tier = 3
	r.inputs = [{id = &"fuel_cell", qty = 3}, {id = &"structural_frame", qty = 2}]
	r.output_id = &"engine_assembly"
	r.duration = 280.0
	r.value = 4200
	r.icon_color = Color(1.0, 0.6, 0.1)
	_reg(r)

	r = RefineryRecipe.new()
	r.recipe_id = &"nav_computer"
	r.display_name = "Ordinateur de Nav"
	r.tier = 3
	r.inputs = [{id = &"circuit_board", qty = 3}, {id = &"sensor_lens", qty = 2}]
	r.output_id = &"nav_computer"
	r.duration = 400.0
	r.value = 6000
	r.icon_color = Color(0.4, 0.9, 1.0)
	_reg(r)
