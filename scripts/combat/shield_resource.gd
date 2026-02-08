class_name ShieldResource
extends Resource

# =============================================================================
# Shield Resource - Data for a shield generator variant
# =============================================================================

@export var shield_name: StringName = &""
@export var slot_size: int = 0  # 0=S, 1=M, 2=L (same as WeaponResource.SlotSize)
@export var shield_hp_per_facing: float = 100.0  # HP per face, total = x4
@export var regen_rate: float = 12.0  # HP/s
@export var regen_delay: float = 4.0  # seconds after taking hit
@export var bleedthrough: float = 0.12  # 0.0-1.0, damage passing through shields
@export var price: int = 0
