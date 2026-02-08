class_name WeaponResource
extends Resource

# =============================================================================
# Weapon Resource - Defines all stats for a weapon type
# =============================================================================

enum WeaponType { LASER, PLASMA, MISSILE, RAILGUN, MINE, TURRET, MINING_LASER }
enum SlotSize { S, M, L }
enum AmmoType { ENERGY, AMMO }

# --- Identity ---
@export var weapon_name: StringName = &""
@export var weapon_type: WeaponType = WeaponType.LASER
@export var slot_size: SlotSize = SlotSize.S
@export var ammo_type: AmmoType = AmmoType.ENERGY

# --- Damage ---
@export var damage_per_hit: float = 25.0
@export var damage_type: StringName = &"thermal"  # kinetic, thermal, explosive, em

# --- Firing ---
@export var fire_rate: float = 6.0             # shots per second
@export var energy_cost_per_shot: float = 5.0
@export var projectile_speed: float = 800.0
@export var projectile_lifetime: float = 3.0
@export var projectile_scene_path: String = "res://scenes/weapons/laser_bolt.tscn"

# --- Special ---
@export var charge_time: float = 0.0           # railgun charge-up
@export var tracking_strength: float = 0.0     # missile tracking (deg/s)
@export var aoe_radius: float = 0.0            # mine/torpedo explosion radius

# --- Visuals ---
@export var bolt_color: Color = Color(0.3, 0.7, 1.0)
@export var bolt_length: float = 4.0
@export var fire_sound_path: String = "res://assets/sounds/laser_fire.mp3"
@export var weapon_model_scene: String = ""  # Path to 3D mesh scene for weapon visual
