class_name UIThemeSystem
extends Node

# =============================================================================
# UI Theme - Unified design system autoload
# Holographic cyan AAA aesthetic (Star Citizen / Elite Dangerous style)
# Single source of truth for colors, typography, spacing, animations.
# =============================================================================

# --- Primary holographic ---
const PRIMARY := Color(0.15, 0.85, 1.0, 0.9)
const PRIMARY_DIM := Color(0.1, 0.5, 0.7, 0.4)
const PRIMARY_FAINT := Color(0.1, 0.4, 0.6, 0.15)
const HEADER := Color(0.3, 0.88, 1.0, 0.92)

# --- Semantic ---
const ACCENT := Color(0.0, 1.0, 0.6, 0.9)
const WARNING := Color(1.0, 0.7, 0.1, 0.9)
const DANGER := Color(1.0, 0.2, 0.15, 0.9)

# --- Specialized ---
const SHIELD := Color(0.2, 0.6, 1.0, 0.9)
const TARGET := Color(1.0, 0.4, 0.2, 0.9)
const BOOST := Color(1.0, 0.55, 0.1, 0.9)
const CRUISE := Color(0.2, 1.0, 0.5, 0.9)
const LEAD := Color(1.0, 1.0, 0.3, 0.9)

# --- Backgrounds ---
const BG := Color(0.0, 0.02, 0.06, 0.45)
const BG_DARK := Color(0.0, 0.01, 0.03, 0.85)
const BG_PANEL := Color(0.0, 0.02, 0.05, 0.85)
const BG_MODAL := Color(0.0, 0.01, 0.02, 0.92)

# --- Borders / decoration ---
const BORDER := Color(0.08, 0.35, 0.55, 0.4)
const BORDER_ACTIVE := Color(0.1, 0.6, 0.9, 0.7)
const BORDER_HOVER := Color(0.12, 0.7, 1.0, 0.5)
const CORNER := Color(0.1, 0.5, 0.7, 0.6)
const SCANLINE := Color(0.1, 0.6, 0.8, 0.025)

# --- Text ---
const TEXT := Color(0.78, 0.95, 1.0, 0.95)
const TEXT_DIM := Color(0.45, 0.65, 0.78, 0.7)
const TEXT_HEADER := Color(0.5, 0.85, 1.0, 0.8)
const LABEL_KEY := Color(0.3, 0.55, 0.7, 0.7)
const LABEL_VALUE := Color(0.6, 0.9, 1.0, 0.9)

# --- Typography ---
const FONT_SIZE_TITLE := 24
const FONT_SIZE_HEADER := 16
const FONT_SIZE_BODY := 12
const FONT_SIZE_LABEL := 11
const FONT_SIZE_SMALL := 10
const FONT_SIZE_TINY := 9

# --- Spacing ---
const MARGIN_SCREEN := 16.0
const MARGIN_PANEL := 14.0
const MARGIN_SECTION := 8.0
const ROW_HEIGHT := 18.0
const CORNER_LENGTH := 12.0

# --- Animation ---
const PULSE_SPEED := 2.0
const SCANLINE_SPEED := 80.0
const BOOT_FADE_DURATION := 0.8
const TRANSITION_SPEED := 0.3

# --- Shared animation state (updated every frame) ---
var pulse_t: float = 0.0
var scanline_y: float = 0.0
var _default_font: Font = null


func _ready() -> void:
	_default_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	pulse_t += delta
	scanline_y += SCANLINE_SPEED * delta
	# Wrap scanline at a generous height to avoid overflow
	if scanline_y > 4000.0:
		scanline_y -= 4000.0


## Returns a breathing pulse value (0.0 to 1.0) for animations.
func get_pulse(speed_mult: float = 1.0) -> float:
	return (sin(pulse_t * PULSE_SPEED * speed_mult * TAU) + 1.0) * 0.5


## Returns color interpolated from ACCENT → WARNING → DANGER based on ratio (1.0 = good, 0.0 = bad).
func ratio_color(ratio: float) -> Color:
	if ratio > 0.5:
		return ACCENT.lerp(WARNING, 1.0 - (ratio - 0.5) * 2.0)
	return WARNING.lerp(DANGER, 1.0 - ratio * 2.0)


## Returns the default UI font.
func get_font() -> Font:
	return _default_font
