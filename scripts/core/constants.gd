class_name GameConstants
extends Node

# =============================================================================
# Imperion Online Global Constants
# Tuned for responsive, fluid space flight (Star Citizen / Elite feel)
# =============================================================================

# --- Version ---
const GAME_VERSION: String = "0.1.245"

# --- Default Ship ---
const DEFAULT_SHIP_ID: StringName = &"chasseur_viper"

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

# --- Environment ---
# Change this to force DEV (localhost) or PROD (Railway). AUTO = editor→DEV, export→PROD.
enum Env { AUTO, DEV, PROD }
const ENVIRONMENT: Env = Env.AUTO

var _dev_mode: bool = false

# Production URLs (Railway)
const _BACKEND_URL_PROD: String = "https://backend-production-05a9.up.railway.app"
const _BACKEND_WS_URL_PROD: String = "wss://backend-production-05a9.up.railway.app/ws"
const _GAME_SERVER_URL_PROD: String = "wss://gameserver-production-49ba.up.railway.app"

# Local dev URLs (docker-compose up in backend/)
const _BACKEND_URL_DEV: String = "http://localhost:3000"
const _BACKEND_WS_URL_DEV: String = "ws://localhost:3000/ws"
const _GAME_SERVER_URL_DEV: String = "ws://localhost:7777"

# Dynamic URL properties — auto-switch based on environment
var BACKEND_URL: String:
	get:
		return _BACKEND_URL_DEV if _dev_mode else _BACKEND_URL_PROD

var BACKEND_WS_URL: String:
	get:
		return _BACKEND_WS_URL_DEV if _dev_mode else _BACKEND_WS_URL_PROD

var NET_GAME_SERVER_URL: String:
	get:
		return _GAME_SERVER_URL_DEV if _dev_mode else _GAME_SERVER_URL_PROD

# --- Network (MMORPG) ---
const NET_DEFAULT_PORT: int = 7777
const NET_MAX_PLAYERS: int = 128          # Per system server instance
const NET_TICK_RATE: float = 30.0         # Position updates per second (every 2 physics frames @ 60Hz)
const NET_INTERPOLATION_DELAY: float = 0.05   # 50ms interpolation buffer for players
const NPC_INTERPOLATION_DELAY: float = 0.1    # 100ms interpolation buffer for NPCs (3 broadcast intervals for jitter tolerance)
const NET_SNAP_THRESHOLD: float = 10.0    # Metres: beyond this, teleport instead of lerp

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
const AI_DETECTION_RANGE: float = 5000.0         # NPC threat detection radius
const AI_ENGAGEMENT_RANGE: float = 2000.0        # Preferred combat distance (also used for combat bridge, defend range)
const AI_DISENGAGE_RANGE: float = 6500.0         # Break off combat beyond this distance
const AI_FORMATION_LEASH_DISTANCE: float = 3000.0 # Escorts return to leader if further than this
const AI_MIN_SAFE_DIST: float = 50.0             # Min distance before NPC reverses away
const AI_STATION_EXCLUSION_RADIUS: float = 2000.0  # Station obstacle zone radius for AI
const AI_ALERT_THREAT_VALUE: float = 50.0        # Threat table increment for alert_to_threat()
const AI_LOD_TICK_FAR_DIST: float = 8000.0       # Distance for 10x slower AI tick
const AI_LOD_TICK_MID_DIST: float = 3000.0       # Distance for 3x slower AI tick
const AI_STRUCTURE_HIT_RANGE: float = 5000.0     # Max distance for structure hit validation
const AI_STRUCTURE_MAX_DAMAGE: float = 500.0     # Max single-hit damage for structure validation

# --- AI Attack Runs ---
const AI_ATTACK_RUN_MAX_TIME_LIGHT: float = 3.0   # Max run duration: fighters/interceptors
const AI_ATTACK_RUN_MAX_TIME_HEAVY: float = 5.0   # Max run duration: frigates/cruisers
const AI_BREAK_OFF_DURATION_MIN: float = 1.5
const AI_BREAK_OFF_DURATION_MAX: float = 3.0
const AI_REPOSITION_MAX_TIME: float = 8.0
const AI_PASS_DISTANCE_LIGHT: float = 80.0        # Break-off trigger distance (fighters)
const AI_PASS_DISTANCE_HEAVY: float = 150.0       # Break-off trigger distance (frigates)

# --- NPC Authority ---
const NPC_HIT_VALIDATION_RANGE: float = 5000.0   # Max distance for hit validation
const NPC_HIT_DAMAGE_TOLERANCE: float = 0.5      # ±50% damage variance allowed
const NPC_ENCOUNTER_RESPAWN_DELAY: float = 300.0  # 5 min base respawn delay
const NPC_ENCOUNTER_RESPAWN_MAX: float = 1800.0   # 30 min max (escalating anti-farm)
const NPC_DEAD_GUARD_MS: int = 10000              # 10s guard window for dead NPC ghost prevention
const NPC_EXTRAPOLATION_MAX: float = 1.0          # Max extrapolation time (seconds)

func _ready() -> void:
	match ENVIRONMENT:
		Env.DEV:
			_dev_mode = true
		Env.PROD:
			_dev_mode = false
		_: # AUTO: editor = dev, export = prod, --local or env var = dev
			var all_cli_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
			_dev_mode = OS.has_feature("editor") or "--local" in all_cli_args or OS.get_environment("IMPERION_LOCAL") != ""

	var mode_str: String = "DEV (localhost)" if _dev_mode else "PROD (Railway)"
	print("========================================")
	print("  %s" % mode_str)
	print("  Backend:     %s" % BACKEND_URL)
	print("  Game Server: %s" % NET_GAME_SERVER_URL)
	print("========================================")

	# Auto-start local dev stack (Docker + game server) on F5 from editor
	# Skip if running as server (prevents recursive spawn and cmd.exe errors in Docker)
	var all_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if _dev_mode and OS.has_feature("editor") and "--server" not in all_args:
		_start_dev_stack()


# =============================================================================
# DEV STACK — auto-launch Docker + game server on F5
# =============================================================================

func _start_dev_stack() -> void:
	var project_path: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var pid_file: String = project_path + "/.godot/dev_server.pid"

	# 1. Kill previous game server (picks up code changes on every F5)
	#    First by saved PID, then scan port 7777 for orphaned processes.
	if FileAccess.file_exists(pid_file):
		var f: FileAccess = FileAccess.open(pid_file, FileAccess.READ)
		if f:
			var old_pid: int = f.get_as_text().strip_edges().to_int()
			f.close()
			if old_pid > 0:
				print("[DEV] Killing old game server (PID %d)..." % old_pid)
				OS.execute("taskkill", ["/PID", str(old_pid), "/F"], [], false, false)

	# Kill ANY process still holding port 7777 (catches orphans from crashes)
	_kill_process_on_port(7777)

	# Brief wait for OS to release the port
	OS.delay_msec(300)

	# 2. Docker: PostgreSQL + Go backend (idempotent, ~1s if already running)
	var compose_file: String = project_path + "/backend/docker-compose.yml"
	OS.create_process("cmd.exe", ["/c", "docker-compose", "-f", compose_file, "up", "-d"])
	print("[DEV] Docker backend starting (localhost:3000)...")

	# 3. Game server: headless Godot on port 7777 with current code
	#    Redirect stdout/stderr to a log file for debugging crashes.
	var godot_exe: String = OS.get_executable_path()
	var server_log: String = project_path + "/.godot/dev_server.log"
	var cmd: String = '"%s" --headless --path "%s" -- --server --local > "%s" 2>&1' % [godot_exe, project_path, server_log]
	var pid: int = OS.create_process("cmd.exe", ["/c", cmd])
	if pid > 0:
		var f: FileAccess = FileAccess.open(pid_file, FileAccess.WRITE)
		if f:
			f.store_string(str(pid))
			f.close()
		print("[DEV] Game server started (PID %d, port 7777)" % pid)
		print("[DEV] Server log: %s" % server_log)
	else:
		push_warning("[DEV] Failed to start game server")


## Kill any process listening on a given TCP/UDP port (Windows).
func _kill_process_on_port(port: int) -> void:
	var output: Array = []
	OS.execute("cmd.exe", ["/c", "netstat -ano | findstr :%d" % port], output, true, false)
	if output.is_empty() or str(output[0]).strip_edges() == "":
		return
	# Parse netstat lines to extract PIDs
	var killed_pids: Dictionary = {}
	for line_raw in str(output[0]).split("\n"):
		var line: String = line_raw.strip_edges()
		if line == "":
			continue
		# netstat format: "  TCP    0.0.0.0:7777    0.0.0.0:0    LISTENING    12345"
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() < 5:
			continue
		var pid_str: String = parts[parts.size() - 1].strip_edges()
		var pid: int = pid_str.to_int()
		if pid > 0 and not killed_pids.has(pid):
			killed_pids[pid] = true
			print("[DEV] Killing orphan process on port %d (PID %d)" % [port, pid])
			OS.execute("taskkill", ["/PID", str(pid), "/F"], [], false, false)


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
