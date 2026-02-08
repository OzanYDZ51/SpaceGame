class_name ModuleResource
extends Resource

# =============================================================================
# Module Resource - Data for a generic ship module
# =============================================================================

enum ModuleType { COQUE, ENERGIE, BOUCLIER, ARME, SCANNER, MOTEUR }

@export var module_name: StringName = &""
@export var slot_size: int = 0  # 0=S, 1=M, 2=L
@export var module_type: ModuleType = ModuleType.COQUE

# Additive bonuses
@export var hull_bonus: float = 0.0
@export var armor_bonus: float = 0.0
@export var energy_cap_bonus: float = 0.0
@export var energy_regen_bonus: float = 0.0

# Multiplicative bonuses (1.0 = no change)
@export var shield_regen_mult: float = 1.0
@export var shield_cap_mult: float = 1.0
@export var weapon_energy_mult: float = 1.0
@export var weapon_range_mult: float = 1.0


func get_bonuses_text() -> Array[String]:
	var lines: Array[String] = []
	if hull_bonus > 0:
		lines.append("+%.0f Coque" % hull_bonus)
	if armor_bonus > 0:
		lines.append("+%.0f Blindage" % armor_bonus)
	if energy_cap_bonus > 0:
		lines.append("+%.0f Energie max" % energy_cap_bonus)
	if energy_regen_bonus > 0:
		lines.append("+%.0f Regen energie" % energy_regen_bonus)
	if shield_regen_mult != 1.0:
		lines.append("%+.0f%% Regen bouclier" % ((shield_regen_mult - 1.0) * 100))
	if shield_cap_mult != 1.0:
		lines.append("%+.0f%% Capacite bouclier" % ((shield_cap_mult - 1.0) * 100))
	if weapon_energy_mult != 1.0:
		lines.append("%+.0f%% Conso armes" % ((weapon_energy_mult - 1.0) * 100))
	if weapon_range_mult != 1.0:
		lines.append("%+.0f%% Portee armes" % ((weapon_range_mult - 1.0) * 100))
	return lines
