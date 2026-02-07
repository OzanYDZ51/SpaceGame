class_name ShipData
extends Resource

# =============================================================================
# Ship Data - Defines all stats for a ship class
# Used by ShipRegistry to define ship archetypes, by ShipFactory to configure ships.
# =============================================================================

# --- Identity ---
@export var ship_name: StringName = &""
@export var ship_class: StringName = &""

# --- Hull & Shields ---
@export var hull_hp: float = 1000.0
@export var shield_hp: float = 500.0
@export var shield_regen_rate: float = 15.0       # HP/sec per facing
@export var shield_regen_delay: float = 4.0        # seconds after taking hit
@export var shield_damage_bleedthrough: float = 0.1 # 10% damage bleeds through shields to hull
@export var armor_rating: float = 5.0               # flat damage reduction on hull hits

# --- Flight ---
@export var mass: float = 50000.0
@export var accel_forward: float = 80.0
@export var accel_backward: float = 50.0
@export var accel_strafe: float = 40.0
@export var accel_vertical: float = 40.0
@export var max_speed_normal: float = 300.0
@export var max_speed_boost: float = 600.0
@export var max_speed_cruise: float = 3000.0
@export var rotation_pitch_speed: float = 30.0
@export var rotation_yaw_speed: float = 25.0
@export var rotation_roll_speed: float = 50.0
@export var max_speed_lateral: float = 150.0
@export var max_speed_vertical: float = 150.0
@export var rotation_damp_min_factor: float = 0.15

# --- Energy ---
@export var energy_capacity: float = 100.0
@export var energy_regen_rate: float = 20.0
@export var boost_energy_drain: float = 15.0

# --- Hardpoints ---
# Each entry: {id: int, size: "S"/"M"/"L", position: Vector3, direction: Vector3}
@export var hardpoints: Array[Dictionary] = []

# --- Utility ---
@export var utility_slot_count: int = 0
