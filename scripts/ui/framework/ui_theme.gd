class_name UIThemeSystem
extends Node

# =============================================================================
# UI Theme - Unified design system autoload
# Electric cyan / ice blue sci-fi holographic aesthetic
# Single source of truth for colors, typography, spacing, animations.
# =============================================================================

# --- Primary holographic (electric cyan / ice blue) ---
const PRIMARY := Color(0.0, 0.85, 1.0, 0.9)
const PRIMARY_DIM := Color(0.0, 0.5, 0.7, 0.4)
const PRIMARY_FAINT := Color(0.0, 0.4, 0.6, 0.15)
const HEADER := Color(0.1, 0.75, 1.0, 0.92)

# --- Semantic ---
const ACCENT := Color(0.0, 1.0, 0.6, 0.9)
const WARNING := Color(1.0, 0.85, 0.0, 0.9)
const DANGER := Color(1.0, 0.15, 0.1, 0.9)

# --- Specialized ---
const SHIELD := Color(0.2, 0.6, 1.0, 0.9)
const TARGET := Color(1.0, 0.4, 0.2, 0.9)
const BOOST := Color(0.3, 0.9, 1.0, 0.9)
const CRUISE := Color(0.2, 1.0, 0.5, 0.9)
const LEAD := Color(1.0, 1.0, 0.3, 0.9)

# --- Backgrounds (deep space blue) ---
const BG := Color(0.01, 0.015, 0.04, 0.55)
const BG_DARK := Color(0.005, 0.01, 0.03, 0.88)
const BG_PANEL := Color(0.01, 0.02, 0.05, 0.88)
const BG_MODAL := Color(0.005, 0.012, 0.035, 0.94)

# --- Borders / decoration (steel blue / cyan) ---
const BORDER := Color(0.08, 0.35, 0.55, 0.4)
const BORDER_ACTIVE := Color(0.05, 0.6, 0.9, 0.7)
const BORDER_HOVER := Color(0.1, 0.7, 1.0, 0.5)
const CORNER := Color(0.05, 0.5, 0.7, 0.6)
const SCANLINE := Color(0.1, 0.6, 0.8, 0.025)

# --- Text (cool white / ice — all secondaries boosted for readability) ---
const TEXT := Color(0.9, 0.95, 1.0, 0.95)
const TEXT_DIM := Color(0.55, 0.7, 0.85, 0.85)
const TEXT_HEADER := Color(0.5, 0.8, 1.0, 0.92)
const LABEL_KEY := Color(0.45, 0.65, 0.8, 0.85)
const LABEL_VALUE := Color(0.7, 0.9, 1.0, 0.95)

# --- Typography (Rajdhani Bold — better readability on dark backgrounds) ---
const FONT_SIZE_TITLE := 30
const FONT_SIZE_HEADER := 22
const FONT_SIZE_BODY := 17
const FONT_SIZE_LABEL := 16
const FONT_SIZE_SMALL := 15
const FONT_SIZE_TINY := 14

# --- Spacing ---
const MARGIN_SCREEN := 18.0
const MARGIN_PANEL := 16.0
const MARGIN_SECTION := 10.0
const ROW_HEIGHT := 26.0
const CORNER_LENGTH := 16.0

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
	_font_regular = load("res://assets/fonts/Rajdhani-Regular.ttf")
	_font_medium = load("res://assets/fonts/Rajdhani-Medium.ttf")
	_font_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	if _font_regular == null:
		push_error("UITheme: Rajdhani-Regular.ttf not found! UI text will crash.")
	if _font_medium == null:
		_font_medium = _font_regular
	if _font_bold == null:
		_font_bold = _font_regular

	# Apply Rajdhani Bold as the global default font for ALL Controls
	# (Label, Button, LineEdit, etc.) so nothing falls back to Godot's bitmap font
	# Bold weight chosen for readability on dark holographic backgrounds
	var global_theme := Theme.new()
	global_theme.default_font = _font_bold
	global_theme.default_font_size = FONT_SIZE_BODY
	get_tree().root.theme = global_theme


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


## Returns the default UI font (Bold weight — readable at all sizes on dark backgrounds).
func get_font() -> Font:
	return _font_bold


## Returns the medium weight font.
func get_font_medium() -> Font:
	return _font_medium


## Returns the bold weight font.
func get_font_bold() -> Font:
	return _font_bold
