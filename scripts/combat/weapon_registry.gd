class_name WeaponRegistry
extends RefCounted

# =============================================================================
# Weapon Registry - Static database of all weapon definitions
# =============================================================================

static var _cache: Dictionary = {}


static func get_weapon(weapon_name: StringName) -> WeaponResource:
	if _cache.has(weapon_name):
		return _cache[weapon_name]

	var w: WeaponResource = null
	match weapon_name:
		&"Laser Mk1": w = _build_laser_mk1()
		&"Laser Mk2": w = _build_laser_mk2()
		&"Plasma Cannon": w = _build_plasma_cannon()
		&"Heavy Plasma": w = _build_heavy_plasma()
		&"Missile Pod": w = _build_missile_pod()
		&"Torpedo": w = _build_torpedo()
		&"Railgun": w = _build_railgun()
		&"Mine Layer": w = _build_mine_layer()
		&"Auto Cannon": w = _build_auto_cannon()
		&"Point Defense": w = _build_point_defense()
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
	return w


static func _build_laser_mk2() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Laser Mk2"
	w.weapon_type = WeaponResource.WeaponType.LASER
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 45.0
	w.damage_type = &"thermal"
	w.fire_rate = 4.5
	w.energy_cost_per_shot = 7.0
	w.projectile_speed = 900.0
	w.projectile_lifetime = 3.5
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(0.2, 0.5, 1.0)
	w.bolt_length = 5.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_plasma_cannon() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Plasma Cannon"
	w.weapon_type = WeaponResource.WeaponType.PLASMA
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 65.0
	w.damage_type = &"thermal"
	w.fire_rate = 3.0
	w.energy_cost_per_shot = 12.0
	w.projectile_speed = 600.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/plasma_bolt.tscn"
	w.bolt_color = Color(1.0, 0.4, 0.15)
	w.bolt_length = 3.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_heavy_plasma() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Heavy Plasma"
	w.weapon_type = WeaponResource.WeaponType.PLASMA
	w.slot_size = WeaponResource.SlotSize.L
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 120.0
	w.damage_type = &"thermal"
	w.fire_rate = 1.5
	w.energy_cost_per_shot = 25.0
	w.projectile_speed = 500.0
	w.projectile_lifetime = 3.5
	w.projectile_scene_path = "res://scenes/weapons/plasma_bolt.tscn"
	w.bolt_color = Color(1.0, 0.3, 0.05)
	w.bolt_length = 5.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_missile_pod() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Missile Pod"
	w.weapon_type = WeaponResource.WeaponType.MISSILE
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.AMMO
	w.damage_per_hit = 150.0
	w.damage_type = &"explosive"
	w.fire_rate = 1.0
	w.energy_cost_per_shot = 8.0
	w.projectile_speed = 350.0
	w.projectile_lifetime = 6.0
	w.projectile_scene_path = "res://scenes/weapons/missile.tscn"
	w.tracking_strength = 90.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_torpedo() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Torpedo"
	w.weapon_type = WeaponResource.WeaponType.MISSILE
	w.slot_size = WeaponResource.SlotSize.L
	w.ammo_type = WeaponResource.AmmoType.AMMO
	w.damage_per_hit = 400.0
	w.damage_type = &"explosive"
	w.fire_rate = 0.3
	w.energy_cost_per_shot = 15.0
	w.projectile_speed = 250.0
	w.projectile_lifetime = 8.0
	w.projectile_scene_path = "res://scenes/weapons/missile.tscn"
	w.tracking_strength = 45.0
	w.aoe_radius = 30.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_railgun() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Railgun"
	w.weapon_type = WeaponResource.WeaponType.RAILGUN
	w.slot_size = WeaponResource.SlotSize.L
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 300.0
	w.damage_type = &"kinetic"
	w.fire_rate = 0.5
	w.energy_cost_per_shot = 40.0
	w.projectile_speed = 2000.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/railgun_slug.tscn"
	w.charge_time = 1.0
	w.bolt_color = Color(1.0, 1.0, 1.0)
	w.bolt_length = 8.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_mine_layer() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Mine Layer"
	w.weapon_type = WeaponResource.WeaponType.MINE
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.AMMO
	w.damage_per_hit = 200.0
	w.damage_type = &"explosive"
	w.fire_rate = 0.5
	w.energy_cost_per_shot = 5.0
	w.projectile_speed = 0.0
	w.projectile_lifetime = 30.0
	w.aoe_radius = 50.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_auto_cannon() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Auto Cannon"
	w.weapon_type = WeaponResource.WeaponType.TURRET
	w.slot_size = WeaponResource.SlotSize.M
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 18.0
	w.damage_type = &"kinetic"
	w.fire_rate = 8.0
	w.energy_cost_per_shot = 3.0
	w.projectile_speed = 900.0
	w.projectile_lifetime = 3.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(1.0, 0.8, 0.3)
	w.bolt_length = 3.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
	return w


static func _build_point_defense() -> WeaponResource:
	var w := WeaponResource.new()
	w.weapon_name = &"Point Defense"
	w.weapon_type = WeaponResource.WeaponType.TURRET
	w.slot_size = WeaponResource.SlotSize.S
	w.ammo_type = WeaponResource.AmmoType.ENERGY
	w.damage_per_hit = 8.0
	w.damage_type = &"thermal"
	w.fire_rate = 12.0
	w.energy_cost_per_shot = 2.0
	w.projectile_speed = 1200.0
	w.projectile_lifetime = 2.0
	w.projectile_scene_path = "res://scenes/weapons/laser_bolt.tscn"
	w.bolt_color = Color(0.8, 0.3, 0.3)
	w.bolt_length = 2.0
	w.fire_sound_path = "res://assets/sounds/laser_fire.mp3"
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
	return w
