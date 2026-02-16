class_name GameConstants
extends Node

# =============================================================================
# Imperion Online Global Constants
# Tuned for responsive, fluid space flight (Star Citizen / Elite feel)
# =============================================================================

# --- Version ---
const GAME_VERSION: String = "0.1.136"

# --- Default Ship ---
const DEFAULT_SHIP_ID: StringName = &"fighter_mk1"

# --- Game State (shared enum, avoids circular deps with GameManager) ---
enum GameState { LOADING, PLAYING, PAUSED, MENU, DEAD, DOCKED }

# --- Floating Origin ---
const ORIGIN_SHIFT_THRESHOLD: float = 5000.0

# --- Ship Flight (direct acceleration model, no force/mass calc) ---
const SHIP_MASS: float = 50000.0

# Acceleration in m/s² (how fast speed changes)
const ACCEL_FORWARD: float = 80.0    # Reach 300 m/s in ~4 sec
const ACCEL_BACKWARD: float = 50.0
const ACCEL_STRAFE: float = 40.0
const ACCEL_VERTICAL: float = 40.0

# Max speeds per mode
const MAX_SPEED_NORMAL: float = 300.0
const MAX_SPEED_BOOST: float = 600.0
const MAX_SPEED_CRUISE: float = 1_000_000.0  # 1000 km/s — reaches gates in ~30-40s

# Rotation speed in degrees/sec (mouse input scales this)
const ROTATION_PITCH_SPEED: float = 24.0    # Heavy capital ship feel
const ROTATION_YAW_SPEED: float = 20.0      # Yaw slower (realistic inertia)
const ROTATION_ROLL_SPEED: float = 45.0     # Roll moderate

# How fast rotation responds (lower = more inertia, heavier feel)
const ROTATION_RESPONSE: float = 2.5

# Flight assist: how fast the ship brakes when no input (higher = faster stop)
const FA_LINEAR_BRAKE: float = 1.0    # Gentle deceleration (space-like glide)
const FA_ANGULAR_BRAKE: float = 5.0
const FA_COUNTER_BRAKE: float = 2.5

# --- Mouse ---
const MOUSE_SENSITIVITY: float = 0.05  # degrees per pixel of mouse movement

# --- Camera ---
const CAM_DISTANCE_DEFAULT: float = 50.0
const CAM_DISTANCE_MIN: float = 20.0
const CAM_DISTANCE_MAX: float = 250.0
const CAM_HEIGHT: float = 24.0            # Elevated: ship appears in lower 1/3 of screen
const CAM_LOOK_AHEAD_Y: float = -2.0      # Look below ship center (tilts camera down)
const CAM_FOLLOW_SPEED: float = 14.0      # Position follow (higher = tighter)
const CAM_ROTATION_SPEED: float = 10.0    # Rotation follow
const CAM_ZOOM_STEP: float = 10.0         # Per scroll tick
const CAM_COCKPIT_OFFSET: Vector3 = Vector3(0.0, 8.0, -25.0)

# Speed-based camera pull (camera pulls back when going fast)
const CAM_SPEED_PULL: float = 0.02   # Extra distance per m/s of speed
const CAM_FOV_BASE: float = 75.0
const CAM_FOV_BOOST: float = 85.0
const CAM_FOV_CRUISE: float = 95.0

# Combat camera
const CAM_COMBAT_PULL: float = -10.0      # Pull closer when target locked
const CAM_COMBAT_FOLLOW: float = 1.25     # Follow speed multiplier in combat
const CAM_TARGET_BIAS: float = 0.08       # Subtle look-toward-target strength
const CAM_SHAKE_FIRE: float = 0.12        # Weapon fire shake intensity
const CAM_SHAKE_DECAY: float = 10.0       # Shake decay speed

# --- Weapons ---
const LASER_SPEED: float = 800.0          # m/s bolt speed
const LASER_LIFETIME: float = 3.0         # seconds before despawn
const LASER_FIRE_RATE: float = 6.0        # shots per second
const LASER_BOLT_LENGTH: float = 4.0      # visual length of the bolt
const LASER_BOLT_RADIUS: float = 0.12     # visual thickness
const LASER_COLOR: Color = Color(0.3, 0.7, 1.0)        # cyan-blue
const LASER_COLOR_ALT: Color = Color(1.0, 0.4, 0.15)   # orange (for later)
const LASER_LIGHT_ENERGY: float = 2.0
const LASER_LIGHT_RANGE: float = 15.0
const MUZZLE_OFFSET_LEFT: Vector3 = Vector3(-17.5, -1.5, -35.0)
const MUZZLE_OFFSET_RIGHT: Vector3 = Vector3(17.5, -1.5, -35.0)

# --- Combat/Targeting ---
const TARGET_LOCK_RANGE: float = 5000.0
const LEAD_INDICATOR_MIN_SPEED: float = 50.0

# --- Universe Scale ---
const AU_IN_METERS: float = 149_597_870_700.0
const SYSTEM_RADIUS: float = 100_000_000.0

# --- Galaxy Scale ---
var galaxy_seed: int = 12345
const GALAXY_SYSTEM_COUNT: int = 120
const GALAXY_RADIUS: float = 500.0       # Galaxy map units (abstract, not meters)
const JUMP_GATE_RANGE: float = 120.0     # Max distance between connected systems (galaxy units)
const FTL_FUEL_PER_UNIT: float = 1.0
const FTL_CHARGE_TIME: float = 10.0      # Seconds to spool FTL drive
const JUMP_GATE_TRANSIT_TIME: float = 5.0 # Seconds for gate transition

# --- Backend (Go + PostgreSQL) ---
const BACKEND_URL_DEV: String = "http://localhost:3000"
const BACKEND_URL_PROD: String = "https://backend-production-05a9.up.railway.app"
const BACKEND_WS_DEV: String = "ws://localhost:3000/ws"
const BACKEND_WS_PROD: String = "wss://backend-production-05a9.up.railway.app/ws"

# --- Network (MMORPG) ---
const NET_DEFAULT_PORT: int = 7777
const NET_MAX_PLAYERS: int = 128          # Per system server instance
const NET_TICK_RATE: float = 20.0         # Position updates per second
const NET_INTERPOLATION_DELAY: float = 0.1  # 100ms buffer for smooth interpolation
const NET_SNAP_THRESHOLD: float = 10.0    # Metres: beyond this, teleport instead of lerp
const NET_PUBLIC_IP: String = "92.184.140.5"  # Host's public IPv4 (dev, friend's machine)
const NET_GAME_SERVER_URL: String = "wss://gameserver-production-49ba.up.railway.app"

# --- Discord Rich Presence ---
const DISCORD_RPC_PORT: int = 27150

# --- Mining ---
const MINING_RANGE: float = 300.0
const MINING_SCAN_RANGE: float = 500.0
const MINING_BASE_EXTRACTION_RATE: float = 10.0
const ASTEROID_RESPAWN_TIME: float = 300.0

# --- Physics Layers ---
const LAYER_SHIPS: int = 1
const LAYER_STATIONS: int = 2
const LAYER_ASTEROIDS: int = 4
const LAYER_PROJECTILES: int = 8
const LAYER_TERRAIN: int = 16

# --- AI ---
const AI_TICK_INTERVAL: float = 0.1              # 10Hz — base AI tick rate
const AI_DETECTION_RANGE: float = 3000.0         # NPC threat detection radius
const AI_ENGAGEMENT_RANGE: float = 1500.0        # Preferred combat distance (also used for combat bridge, defend range)
const AI_DISENGAGE_RANGE: float = 4000.0         # Break off combat beyond this distance

# --- Speed Modes ---
enum SpeedMode { NORMAL, BOOST, CRUISE }

func get_max_speed(mode: SpeedMode) -> float:
	match mode:
		SpeedMode.NORMAL: return MAX_SPEED_NORMAL
		SpeedMode.BOOST: return MAX_SPEED_BOOST
		SpeedMode.CRUISE: return MAX_SPEED_CRUISE
	return MAX_SPEED_NORMAL

func get_target_fov(mode: SpeedMode) -> float:
	match mode:
		SpeedMode.NORMAL: return CAM_FOV_BASE
		SpeedMode.BOOST: return CAM_FOV_BOOST
		SpeedMode.CRUISE: return CAM_FOV_CRUISE
	return CAM_FOV_BASE
