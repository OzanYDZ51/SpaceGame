class_name UIThemeSystem
extends Node

# =============================================================================
# UI Theme - Unified design system autoload
# Orange/amber Elite Dangerous aesthetic with holographic shaders
# Single source of truth for colors, typography, spacing, animations.
# =============================================================================

# --- Primary holographic (orange/amber Elite Dangerous) ---
const PRIMARY := Color(1.0, 0.55, 0.0, 0.9)
const PRIMARY_DIM := Color(0.7, 0.35, 0.0, 0.4)
const PRIMARY_FAINT := Color(0.6, 0.3, 0.0, 0.15)
const HEADER := Color(1.0, 0.65, 0.1, 0.92)

# --- Semantic ---
const ACCENT := Color(0.0, 1.0, 0.6, 0.9)
const WARNING := Color(1.0, 0.85, 0.0, 0.9)
const DANGER := Color(1.0, 0.15, 0.1, 0.9)

# --- Specialized ---
const SHIELD := Color(0.2, 0.6, 1.0, 0.9)
const TARGET := Color(1.0, 0.4, 0.2, 0.9)
const BOOST := Color(1.0, 0.55, 0.1, 0.9)
const CRUISE := Color(0.2, 1.0, 0.5, 0.9)
const LEAD := Color(1.0, 1.0, 0.3, 0.9)

# --- Backgrounds (deep warm tint) ---
const BG := Color(0.03, 0.02, 0.01, 0.55)
const BG_DARK := Color(0.02, 0.01, 0.005, 0.88)
const BG_PANEL := Color(0.04, 0.025, 0.01, 0.88)
const BG_MODAL := Color(0.02, 0.012, 0.005, 0.94)

# --- Borders / decoration (amber) ---
const BORDER := Color(0.55, 0.3, 0.05, 0.4)
const BORDER_ACTIVE := Color(0.9, 0.5, 0.05, 0.7)
const BORDER_HOVER := Color(1.0, 0.6, 0.1, 0.5)
const CORNER := Color(0.7, 0.4, 0.05, 0.6)
const SCANLINE := Color(0.8, 0.5, 0.1, 0.025)

# --- Text (warm white/amber) ---
const TEXT := Color(1.0, 0.88, 0.7, 0.95)
const TEXT_DIM := Color(0.7, 0.5, 0.3, 0.7)
const TEXT_HEADER := Color(1.0, 0.7, 0.3, 0.8)
const LABEL_KEY := Color(0.6, 0.4, 0.2, 0.7)
const LABEL_VALUE := Color(1.0, 0.75, 0.4, 0.9)

# --- Typography (Rajdhani — bumped for readability, x-height is small) ---
const FONT_SIZE_TITLE := 28
const FONT_SIZE_HEADER := 20
const FONT_SIZE_BODY := 15
const FONT_SIZE_LABEL := 14
const FONT_SIZE_SMALL := 13
const FONT_SIZE_TINY := 12

# --- Spacing ---
const MARGIN_SCREEN := 16.0
const MARGIN_PANEL := 14.0
const MARGIN_SECTION := 8.0
const ROW_HEIGHT := 22.0
const CORNER_LENGTH := 12.0

# --- Animation ---
const PULSE_SPEED := 2.0
const SCANLINE_SPEED := 80.0
const BOOT_FADE_DURATION := 0.8
const TRANSITION_SPEED := 0.3

# --- Shared animation state (updated every frame) ---
var pulse_t: float = 0.0
var scanline_y: float = 0.0
var _font_regular: Font = null
var _font_medium: Font = null
var _font_bold: Font = null


func _ready() -> void:
	# Load Rajdhani fonts, fallback to Godot default
	var regular = load("res://assets/fonts/Rajdhani-Regular.ttf")
	var medium = load("res://assets/fonts/Rajdhani-Medium.ttf")
	var bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	_font_regular = regular if regular else ThemeDB.fallback_font
	_font_medium = medium if medium else _font_regular
	_font_bold = bold if bold else _font_regular


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


## Returns the default UI font (Regular weight — backward compatible).
func get_font() -> Font:
	return _font_regular


## Returns the medium weight font.
func get_font_medium() -> Font:
	return _font_medium


## Returns the bold weight font.
func get_font_bold() -> Font:
	return _font_bold
