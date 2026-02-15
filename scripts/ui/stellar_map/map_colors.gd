class_name MapColors
extends RefCounted

# =============================================================================
# Stellar Map Color Palette
# Holographic cyan/blue theme, consistent with FlightHUD
# =============================================================================

# --- Background ---
const BG := Color(0.0, 0.01, 0.03, 1.0)
const BG_PANEL := Color(0.0, 0.02, 0.05, 0.85)

# --- Grid ---
const GRID_MINOR := Color(0.05, 0.2, 0.35, 0.12)
const GRID_MAJOR := Color(0.08, 0.35, 0.55, 0.25)
const GRID_LABEL := Color(0.3, 0.55, 0.7, 0.4)

# --- Primary holographic ---
const PRIMARY := Color(0.15, 0.85, 1.0, 0.9)
const PRIMARY_DIM := Color(0.1, 0.5, 0.7, 0.4)
const PRIMARY_FAINT := Color(0.1, 0.4, 0.6, 0.15)

# --- Text ---
const TEXT := Color(0.7, 0.92, 1.0, 0.95)
const TEXT_DIM := Color(0.4, 0.6, 0.7, 0.6)
const TEXT_HEADER := Color(0.5, 0.85, 1.0, 0.8)

# --- Entity type colors ---
const STAR_GOLD := Color(1.0, 0.9, 0.4, 1.0)
const STAR_HALO := Color(1.0, 0.85, 0.3, 0.15)

const PLANET_ROCKY := Color(0.65, 0.45, 0.3, 0.9)
const PLANET_GAS := Color(0.85, 0.7, 0.3, 0.9)
const PLANET_ICE := Color(0.5, 0.75, 1.0, 0.9)
const PLANET_OCEAN := Color(0.2, 0.45, 0.85, 0.9)
const PLANET_LAVA := Color(1.0, 0.35, 0.15, 0.9)

const STATION_TEAL := Color(0.1, 0.9, 0.6, 0.9)
const PLAYER := Color(0.15, 0.85, 1.0, 1.0)
const REMOTE_PLAYER := Color(0.3, 1.0, 0.85, 0.9)  # Cyan-green for other players
# NPC factions
const NPC_HOSTILE := Color(1.0, 0.3, 0.3, 0.9)
const NPC_FRIENDLY := Color(0.3, 1.0, 0.45, 0.9)
const NPC_NEUTRAL := Color(0.7, 0.55, 1.0, 0.8)
const NPC_SHIP := Color(0.6, 0.6, 0.7, 0.7)  # fallback
const FLEET_SHIP := Color(0.4, 0.65, 1.0, 0.95)  # Blue for player fleet

# --- Squadron ---
const SQUADRON_LINE := Color(0.5, 0.7, 1.0, 0.35)
const SQUADRON_HEADER := Color(0.6, 0.8, 1.0, 0.85)
const SQUADRON_BADGE_FOLLOW := Color(0.4, 0.65, 1.0, 0.9)
const SQUADRON_BADGE_ATTACK := Color(1.0, 0.4, 0.3, 0.9)
const SQUADRON_BADGE_DEFEND := Color(0.3, 1.0, 0.5, 0.9)
const SQUADRON_BADGE_INTERCEPT := Color(1.0, 0.7, 0.2, 0.9)
const SQUADRON_BADGE_MIMIC := Color(0.7, 0.55, 1.0, 0.9)

# --- Fleet panel (left side) ---
const FLEET_PANEL_BG := Color(0.0, 0.02, 0.05, 0.9)
const FLEET_STATUS_ACTIVE := Color(0.2, 1.0, 0.5, 0.9)
const FLEET_STATUS_DOCKED := Color(0.5, 0.6, 0.7, 0.7)
const FLEET_STATUS_DEPLOYED := Color(0.4, 0.7, 1.0, 0.9)
const FLEET_STATUS_DESTROYED := Color(1.0, 0.3, 0.2, 0.8)

# --- Station detail panel (right side) ---
const STATION_DETAIL_BG := Color(0.0, 0.03, 0.06, 0.9)
const ACTION_BUTTON := Color(0.1, 0.5, 0.9, 0.9)
const ACTION_BUTTON_HOVER := Color(0.2, 0.6, 1.0, 1.0)
const ACTION_BUTTON_DANGER := Color(0.8, 0.3, 0.1, 0.9)

# Filter indicator
const FILTER_ACTIVE := Color(0.15, 0.85, 1.0, 0.7)
const FILTER_INACTIVE := Color(0.4, 0.4, 0.5, 0.3)

const ASTEROID_BELT := Color(0.7, 0.55, 0.35, 0.5)
const JUMP_GATE := Color(0.15, 0.6, 1.0, 0.9)

# --- Orbit lines ---
const ORBIT_LINE := Color(0.1, 0.3, 0.5, 0.15)
const ORBIT_LINE_SELECTED := Color(0.15, 0.55, 0.8, 0.35)

# --- Selection ---
const SELECTION_RING := Color(0.2, 0.9, 1.0, 0.8)
const SELECTION_LINE := Color(0.15, 0.7, 0.9, 0.3)

# --- Scale bar ---
const SCALE_BAR := Color(0.3, 0.6, 0.8, 0.5)

# --- Border/decoration ---
const BORDER := Color(0.08, 0.35, 0.55, 0.5)
const CORNER := Color(0.1, 0.5, 0.7, 0.6)
const SCANLINE := Color(0.1, 0.6, 0.8, 0.025)

# --- Info panel ---
const PANEL_BORDER := Color(0.08, 0.4, 0.6, 0.6)
const PANEL_HEADER := Color(0.1, 0.6, 0.8, 0.7)
const LABEL_KEY := Color(0.3, 0.55, 0.7, 0.7)
const LABEL_VALUE := Color(0.6, 0.9, 1.0, 0.9)

# --- Construction markers ---
const CONSTRUCTION_STATION := Color(0.2, 0.8, 1.0, 0.9)
const CONSTRUCTION_GHOST := Color(0.2, 0.8, 1.0, 0.3)
const CONSTRUCTION_HEADER := Color(0.3, 0.85, 1.0, 0.85)
