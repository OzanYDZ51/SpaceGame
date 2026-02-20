class_name ShipData
extends Resource

# =============================================================================
# Ship Data - Defines all stats for a specific ship variant.
# ship_id is the unique key (e.g. "chasseur_viper", "frigate_mk1").
# ship_class is the role/category (e.g. "Fighter", "Frigate") — used for loot, display.
# =============================================================================

# --- Identity ---
@export var ship_id: StringName = &""
@export var ship_name: StringName = &""
@export var ship_class: StringName = &""

# --- Model ---
@export var model_path: String = "res://assets/models/tie.glb"
@export var model_scale: float = 2.0
@export var exhaust_scale: float = 1.0  ## Visual scale of engine exhaust (independent of model_scale)
@export var ship_scene_path: String = ""  # Path to .tscn with model + HardpointSlots + CollisionShape3D

# --- Default Loadout ---
@export var default_loadout: Array[StringName] = []

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
@export var max_speed_cruise: float = 1_000_000.0
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

# --- Collision ---
@export var collision_size: Vector3 = Vector3(28, 12, 36)

# --- Hardpoints ---
@export var hardpoints: Array[Dictionary] = []

# --- Equipment Slots ---
@export var shield_slot_size: String = "S"
@export var engine_slot_size: String = "S"
@export var module_slots: Array[String] = []  # e.g. ["S", "S"]

# --- Price ---
@export var price: int = 0

# --- Cargo ---
@export var cargo_capacity: int = 50

# --- AI / Sensor ---
@export var sensor_range: float = 3000.0          # Threat detection radius
@export var engagement_range: float = 1500.0      # Preferred max combat distance
@export var disengage_range: float = 4000.0       # Break off combat beyond this

# --- Utility ---
@export var utility_slot_count: int = 0

# --- Default Equipment (data-driven defaults, replaces registry lookups) ---
@export_group("Defaults")
@export var default_shield: StringName = &""
@export var default_engine: StringName = &""
@export var default_modules: Array[StringName] = []

# --- Loot (data-driven drops, replaces LootTable match) ---
@export_group("Loot")
@export var loot_credits_min: int = 100
@export var loot_credits_max: int = 300
@export var loot_mat_count_min: int = 1
@export var loot_mat_count_max: int = 1
@export var loot_weapon_part_chance: float = 0.0

# --- LOD Combat (data-driven DPS, replaces ShipLODManager dict) ---
@export_group("LOD")
@export var lod_combat_dps: float = 15.0

# --- NPC Encounters (tier for danger-level composition) ---
@export_group("NPC")
@export var npc_tier: int = 0  # 0=low, 1=mid, 2=high

# --- Commerce (which station types sell this ship) ---
@export_group("Commerce")
@export var sold_at_station_types: Array[StringName] = []
@export var resource_cost: Dictionary = {}  # StringName -> int (e.g. { &"iron": 50 })
