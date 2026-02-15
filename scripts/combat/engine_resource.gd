class_name EngineResource
extends Resource

# =============================================================================
# Engine Resource - Data for an engine/thruster variant
# =============================================================================

@export var engine_name: StringName = &""
@export var slot_size: int = 0  # 0=S, 1=M, 2=L
@export var accel_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var rotation_mult: float = 1.0
@export var cruise_mult: float = 1.0
@export var boost_drain_mult: float = 1.0
@export var price: int = 0

# --- Commerce ---
@export var sold_at_station_types: Array[StringName] = []
