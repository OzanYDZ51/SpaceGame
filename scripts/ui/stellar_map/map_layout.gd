class_name MapLayout
extends RefCounted

# =============================================================================
# Map Layout - Shared constants for 3-column map layout
# Left: Fleet panel | Center: Viewport | Right: Info panel
# =============================================================================

# --- Panel widths ---
const FLEET_PANEL_W: float = 240.0
const INFO_PANEL_W: float = 260.0
const INFO_PANEL_MARGIN: float = 16.0

# --- Viewport zone (computed from screen size) ---
static func viewport_left() -> float:
	return FLEET_PANEL_W + 16.0  # 256px

static func viewport_right(screen_w: float) -> float:
	return screen_w - INFO_PANEL_W - INFO_PANEL_MARGIN - 8.0

static func viewport_width(screen_w: float) -> float:
	return viewport_right(screen_w) - viewport_left()

# --- Header positioning (inside viewport zone) ---
const HEADER_Y: float = 28.0
const TOOLBAR_Y: float = 52.0
const TOOLBAR_H: float = 24.0

# --- Scale bar (bottom-right of viewport zone) ---
static func scale_bar_right(screen_w: float) -> float:
	return viewport_right(screen_w) - 16.0
