class_name WeaponRegistry
extends RefCounted

# =============================================================================
# Weapon Registry - Static database of all weapon definitions
# Only weapons with real 3D models are registered here.
# Add new weapons one by one as proper models are created.
# =============================================================================

static var _cache: Dictionary = {}


static func get_weapon(weapon_name: StringName) -> WeaponResource:
	if _cache.has(weapon_name):
		return _cache[weapon_name]

	var w: WeaponResource = null
	match weapon_name:
		&"Laser Mk1": w = _build_laser_mk1()
		&"Turret Mk1": w = _build_turret_mk1()
		&"Mining Laser Mk1": w = _build_mining_laser_mk1()
		&"Mining Laser Mk2": w = _build_mining_laser_mk2()
		_:
			push_error("WeaponRegistry: Unknown weapon '%s'" % weapon_name)
			return null

	_cache[weapon_name] = w
	return w


## DEPRECATED: Default loadouts are now stored in ShipData.default_loadout.
## Kept for backward compatibility — delegates to ShipData if ship_id is passed.
static func get_default_loadout(ship_id: StringName) -> Array[StringName]:
	var data := ShipRegistry.get_ship_data(ship_id)
	if data and not data.default_loadout.is_empty():
		return data.default_loadout
	return []


# === Weapon Builders ===

static func _build_laser_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Laser Mk1"
	w.weapon_type = WeaponResource.WeaponType.LASER
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 25.0
	w.damage_type = &"thermal"
	w.fire_rate = 6.0
	w.energy_cost_per_shot = 4.0
	w.projectile_speed = 800.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(0.3, 0.7, 1.0)
	w.bolt_length = 4.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	w.weapon_model_scene = "res://scenes/weapons/models/laser_mk1.tscn"
	w.price = 500
	return w


static func _build_turret_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Turret Mk1"
	w.weapon_type = WeaponResource.WeaponType.TURRET
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 25.0
	w.damage_type = &"kinetic"
	w.fire_rate = 4.0
	w.energy_cost_per_shot = 4.0
	w.projectile_speed = 1000.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(1.0, 0.6, 0.2)
	w.bolt_length = 3.5
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	w.weapon_model_scene = "res://scenes/weapons/models/turret_mk1.tscn"
	w.price = 6000
	return w


static func _build_mining_laser_mk1() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Mining Laser Mk1"
	w.weapon_type = WeaponResource.WeaponType.MINING_LASER
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 10.0
	w.damage_type = &"thermal"
	w.fire_rate = 2.0  # ticks per second (continuous beam)
	w.energy_cost_per_shot = 4.0  # energy per second
	w.projectile_speed = 0.0
	w.projectile_lifetime = 0.0
	w.bolt_color = Color(0.2, 1.0, 0.5)
	w.bolt_length = 0.0
	w.weapon_model_scene = "res://scenes/weapons/models/mining_laser_mk1.tscn"
	w.price = 1000
	return w


static func _build_mining_laser_mk2() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Mining Laser Mk2"
	w.weapon_type = WeaponResource.WeaponType.MINING_LASER
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 20.0
	w.damage_type = &"thermal"
	w.fire_rate = 2.0
	w.energy_cost_per_shot = 6.0
	w.projectile_speed = 0.0
	w.projectile_lifetime = 0.0
	w.bolt_color = Color(0.15, 0.9, 0.6)
	w.bolt_length = 0.0
	w.weapon_model_scene = "res://scenes/weapons/models/mining_laser_mk2.tscn"
	w.price = 4000
	return w
