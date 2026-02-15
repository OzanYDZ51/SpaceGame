class_name EquipmentConstants
extends RefCounted

# =============================================================================
# Equipment Screen — Shared Constants, Colors & Static Helpers
# =============================================================================

# --- Layout ---
const VIEWER_RATIO := 0.55
const SIDEBAR_RATIO := 0.45
const CONTENT_TOP := 140.0
const FLEET_STRIP_TOP := 52.0
const FLEET_STRIP_H := 88.0
const FLEET_CARD_W := 156.0
const FLEET_CARD_H := 66.0
const FLEET_CARD_GAP := 6.0
const TAB_H := 30.0
const HP_STRIP_H := 94.0
const COMPARE_H := 170.0
const BTN_W := 140.0
const BTN_H := 38.0
const ARSENAL_ROW_H := 56.0
const SIZE_BADGE_W := 30.0
const SIZE_BADGE_H := 22.0

# --- Tab names ---
const TAB_NAMES: Array[String] = ["ARMEMENT", "MODULES", "BOUCLIERS", "MOTEURS"]
const TAB_NAMES_STATION: Array[String] = ["ARMEMENT", "MODULES", "BOUCLIERS"]

# --- Weapon type colors ---
const TYPE_COLORS := {
	0: Color(0.3, 0.7, 1.0, 0.9),    # LASER
	1: Color(1.0, 0.45, 0.15, 0.9),   # PLASMA
	2: Color(1.0, 0.3, 0.3, 0.9),     # MISSILE
	3: Color(0.85, 0.85, 1.0, 0.9),   # RAILGUN
	4: Color(0.7, 1.0, 0.3, 0.9),     # MINE
	5: Color(1.0, 0.8, 0.3, 0.9),     # TURRET
}
const TYPE_NAMES := ["LASER", "PLASMA", "MISSILE", "RAILGUN", "MINE", "TURRET"]

# --- Equipment type colors ---
const SHIELD_COLOR := Color(0.3, 0.6, 1.0, 0.9)
const ENGINE_COLOR := Color(0.3, 0.8, 1.0, 0.9)
const MODULE_COLORS := {
	0: Color(0.7, 0.5, 0.3, 0.9),   # COQUE
	1: Color(1.0, 0.85, 0.2, 0.9),  # ENERGIE
	2: Color(0.3, 0.6, 1.0, 0.9),   # BOUCLIER
	3: Color(1.0, 0.3, 0.3, 0.9),   # ARME
	4: Color(0.3, 1.0, 0.6, 0.9),   # SCANNER
	5: Color(1.0, 0.6, 0.2, 0.9),   # MOTEUR
}

# --- Orbit camera ---
const ORBIT_PITCH_MIN := -80.0
const ORBIT_PITCH_MAX := 80.0
const ORBIT_SENSITIVITY := 0.3
const AUTO_ROTATE_SPEED := 6.0
const AUTO_ROTATE_DELAY := 3.0


# =============================================================================
# Static Helpers
# =============================================================================
static func get_slot_size_color(s: String) -> Color:
	match s:
		"S": return UITheme.PRIMARY
		"M": return UITheme.WARNING
		"L": return Color(1.0, 0.5, 0.15, 0.9)
	return UITheme.TEXT_DIM


static func get_weapon_type_color(weapon_type: int) -> Color:
	return TYPE_COLORS.get(weapon_type, UITheme.PRIMARY)


static func format_stat(val: float, label: String) -> String:
	match label:
		"CADENCE":
			return "%.1f/s" % val
		"PORTEE":
			if val >= 1000.0:
				return "%.1f km" % (val / 1000.0)
			return "%.0f m" % val
		"ENERGIE", "DELAI":
			return "%.1f" % val
		"ACCELERATION", "VITESSE", "CRUISE", "ROTATION", "CONSO BOOST":
			return "x%.2f" % val
		"INFILTRATION":
			return "%.0f%%" % val
		"REGEN BOUCLIER", "CAP BOUCLIER", "CONSO ARMES", "PORTEE ARMES":
			return "%.0f%%" % val
	if absf(val) >= 100:
		return "%.0f" % val
	return "%.1f" % val


static func get_engine_best_stat(engine: EngineResource) -> String:
	var best := ""
	var best_val := 0.0
	if absf(engine.accel_mult - 1.0) > best_val:
		best_val = absf(engine.accel_mult - 1.0)
		best = "%+.0f%% ACCEL" % ((engine.accel_mult - 1.0) * 100)
	if absf(engine.speed_mult - 1.0) > best_val:
		best_val = absf(engine.speed_mult - 1.0)
		best = "%+.0f%% VITESSE" % ((engine.speed_mult - 1.0) * 100)
	if absf(engine.cruise_mult - 1.0) > best_val:
		best_val = absf(engine.cruise_mult - 1.0)
		best = "%+.0f%% CRUISE" % ((engine.cruise_mult - 1.0) * 100)
	if absf(engine.rotation_mult - 1.0) > best_val:
		best_val = absf(engine.rotation_mult - 1.0)
		best = "%+.0f%% ROTATION" % ((engine.rotation_mult - 1.0) * 100)
	if best == "":
		best = "Standard"
	return best
