class_name SaveManagerSystem
extends Node

# =============================================================================
# Save Manager — auto-saves player state to backend
# Autoload: SaveManager
# =============================================================================

signal save_completed()
signal save_failed(error: String)
signal load_completed(state: Dictionary)
signal load_failed(error: String)

const AUTO_SAVE_INTERVAL: float = 60.0
const MIN_SAVE_INTERVAL: float = 5.0

var _is_dirty: bool = false
var _last_save_time: float = 0.0
var _auto_save_timer: Timer = null
var _saving: bool = false


func _ready() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.name = "AutoSaveTimer"
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.timeout.connect(_on_auto_save)
	add_child(_auto_save_timer)

	# Save immediately on REAL network disconnect (not initial connection failures)
	NetworkManager.server_connection_lost.connect(_on_network_disconnected)


func start_auto_save() -> void:
	_auto_save_timer.start()


func stop_auto_save() -> void:
	_auto_save_timer.stop()


func mark_dirty() -> void:
	_is_dirty = true


# --- Save ---

func save_player_state(force: bool = false) -> bool:
	if not AuthManager.is_authenticated:
		return false
	if _saving:
		return false

	# Debounce
	var now: float = Time.get_ticks_msec() / 1000.0
	if not force and (now - _last_save_time) < MIN_SAVE_INTERVAL:
		return false

	_saving = true
	var state =_collect_state()

	var result =await ApiClient.put_async("/api/v1/player/state", state)
	_saving = false
	_last_save_time = Time.get_ticks_msec() / 1000.0

	if result.get("ok", false) or result.get("_status_code", 0) == 200:
		_is_dirty = false
		save_completed.emit()
		return true
	else:
		var error: String = result.get("error", "save failed")
		save_failed.emit(error)
		push_warning("SaveManager: Save failed — %s" % error)
		return false


# --- Load ---

func load_player_state() -> Dictionary:
	if not AuthManager.is_authenticated:
		load_failed.emit("not authenticated")
		return {}

	var result =await ApiClient.get_async("/api/v1/player/state")
	var status: int = result.get("_status_code", 0)

	if status == 200:
		load_completed.emit(result)
		return result
	else:
		var error: String = result.get("error", "load failed")
		load_failed.emit(error)
		return {}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	print("[SaveMgr] apply_state: starting...")

	# Galaxy re-generation (must happen before PlayerData.apply_save_state)
	var gal_seed: int = int(state.get("galaxy_seed", Constants.galaxy_seed))
	if gal_seed != Constants.galaxy_seed:
		print("[SaveMgr] apply_state: regenerating galaxy (seed %d -> %d)" % [Constants.galaxy_seed, gal_seed])
		Constants.galaxy_seed = gal_seed
		GameManager._galaxy = GalaxyGenerator.generate(gal_seed)
		if GameManager._system_transition:
			GameManager._system_transition.galaxy = GameManager._galaxy

	# Delegate bulk state to PlayerData
	if GameManager.player_data:
		print("[SaveMgr] apply_state: applying player data...")
		GameManager.player_data.apply_save_state(
			state,
			GameManager.player_ship,
			GameManager._system_transition,
			GameManager._galaxy,
			GameManager._fleet_deployment_mgr,
			GameManager._commerce_manager,
			GameManager._squadron_mgr,
		)
		print("[SaveMgr] apply_state: player data applied OK")

	# Gameplay integrator state (factions, missions, economy, POIs)
	if GameManager._gameplay_integrator:
		print("[SaveMgr] apply_state: applying gameplay integrator state...")
		GameManager._gameplay_integrator.apply_save_state(state)
		print("[SaveMgr] apply_state: gameplay integrator state applied OK")

	# Ship change (must happen after fleet is restored by PlayerData)
	# Uses rebuild_ship_for_respawn which bypasses the DOCKED state check —
	# on reconnect the player is in PLAYING state, not DOCKED.
	var ship_id: String = state.get("current_ship_id", String(Constants.DEFAULT_SHIP_ID))
	print("[SaveMgr] apply_state: checking ship change (saved=%s)..." % ship_id)
	var ship = GameManager.player_ship
	if ship and ship_id != "":
		var current_sid: String = str(ship.ship_data.ship_id if ship.ship_data else Constants.DEFAULT_SHIP_ID)
		if current_sid != ship_id and GameManager.player_fleet:
			print("[SaveMgr] apply_state: ship change needed %s -> %s" % [current_sid, ship_id])
			var target_idx: int = GameManager.player_fleet.active_index
			var active_fs = GameManager.player_fleet.get_active()
			if active_fs == null or str(active_fs.ship_id) != ship_id:
				for i in GameManager.player_fleet.ships.size():
					if str(GameManager.player_fleet.ships[i].ship_id) == ship_id:
						target_idx = i
						break
			if GameManager._ship_change_mgr:
				GameManager._ship_change_mgr.rebuild_ship_for_respawn(target_idx)
	print("[SaveMgr] apply_state: DONE")


# --- Collect current state ---

func _collect_state() -> Dictionary:
	if GameManager._fleet_deployment_mgr:
		GameManager._fleet_deployment_mgr.force_sync_positions()
	var state: Dictionary = {}
	if GameManager.player_data:
		state = GameManager.player_data.collect_save_state(
			GameManager.player_ship,
			GameManager._system_transition,
		)
	if GameManager._gameplay_integrator:
		GameManager._gameplay_integrator.collect_save_state(state)
	return state


# --- Triggers ---

func _on_auto_save() -> void:
	# Always save periodically — position changes continuously during flight
	# and there are no event triggers for normal movement.
	save_player_state()


func _on_network_disconnected(_reason: String) -> void:
	if AuthManager.is_authenticated:
		print("[SaveManager] Network disconnected — emergency save")
		mark_dirty()
		save_player_state(true)


func trigger_save(reason: String = "") -> void:
	if reason != "":
		print("[SaveManager] trigger_save: ", reason)
	mark_dirty()
	save_player_state(true)
