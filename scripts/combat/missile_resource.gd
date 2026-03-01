class_name MissileResource
extends Resource

# =============================================================================
# Missile Resource - Defines stats for a missile type (ammo, not a weapon)
# Missiles are loaded into launcher hardpoints, consumed on fire.
# =============================================================================

enum MissileSize { S, M, L }
enum MissileCategory { GUIDED, DUMBFIRE, TORPEDO }

# --- Identity ---
@export var missile_name: StringName = &""
@export var missile_size: MissileSize = MissileSize.S
@export var missile_category: MissileCategory = MissileCategory.GUIDED

# --- Damage ---
@export var damage_per_hit: float = 100.0
@export var damage_type: StringName = &"explosive"

# --- Projectile ---
@export var projectile_speed: float = 400.0
@export var projectile_lifetime: float = 6.0
@export var projectile_scene_path: String = "res://scenes/weapons/missile_projectile.tscn"

# --- Tracking ---
@export var tracking_strength: float = 0.0  # deg/s
@export var aoe_radius: float = 0.0

# --- Lock ---
@export var lock_time: float = 2.0          # 0 = no lock (dumbfire)
@export var lock_cone_degrees: float = 15.0 # half-angle
@export var missile_hp: float = 30.0        # 0 = indestructible

# --- Visuals ---
@export var missile_model_scene: String = ""
@export var model_scale: float = 2.5
@export var bolt_color: Color = Color(1.0, 0.5, 0.15, 1.0)
@export var fire_sound_path: String = "res://assets/sounds/laser_fire.mp3"

# --- Commerce ---
@export var price: int = 100  # prix unitaire
@export var sold_at_station_types: Array[StringName] = []
