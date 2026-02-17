class_name ShipNetworkSync
extends Node

# =============================================================================
# Ship Network Sync - Sends local player's ship state to the server at 20Hz.
# Attached as a child of the local player's ShipController.
# =============================================================================

var _ship = null
var _send_timer: float = 0.0
var _was_dead: bool = false
var _mining_send_timer: float = 0.0
const MINING_BEAM_SEND_RATE: float = 0.1  # 10Hz


func _ready() -> void:
	_ship = get_parent()
	if _ship == null:
		push_error("ShipNetworkSync: Parent must be ShipController")
		set_process(false)
		set_physics_process(false)
		return

	# Connect weapon fire signal for combat sync
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm:
		wm.weapon_fired.connect(_on_weapon_fired)

	GameManager.player_ship_rebuilt.connect(func(_ship_ref): reconnect_weapon_signal())


## Force an immediate state send (called after undock, respawn, etc.)
func force_send_now() -> void:
	if _ship and NetworkManager.is_connected_to_server():
		_send_state()
		_send_timer = 1.0 / Constants.NET_TICK_RATE


func _physics_process(delta: float) -> void:
	if NetworkManager.is_server():
		return
	if not NetworkManager.is_connected_to_server():
		return

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / Constants.NET_TICK_RATE
		_send_state()

	_mining_send_timer -= delta
	if _mining_send_timer <= 0.0:
		_mining_send_timer = MINING_BEAM_SEND_RATE
		_send_mining_state()


func _send_state() -> void:
	var universe_pos =FloatingOrigin.to_universe_pos(_ship.global_position)

	var state =NetworkState.new()
	state.peer_id = NetworkManager.local_peer_id
	state.pos_x = universe_pos[0]
	state.pos_y = universe_pos[1]
	state.pos_z = universe_pos[2]
	state.velocity = _ship.linear_velocity
	state.rotation_deg = _ship.rotation_degrees
	state.throttle = _ship.throttle_input.length()
	state.timestamp = Time.get_ticks_msec() / 1000.0
	state.ship_id = _ship.ship_data.ship_id if _ship.ship_data else Constants.DEFAULT_SHIP_ID

	# System ID from SystemTransition
	var sys_trans = GameManager._system_transition
	if sys_trans:
		state.system_id = sys_trans.current_system_id

	# Status flags
	state.is_docked = GameManager.current_state == Constants.GameState.DOCKED
	state.is_dead = GameManager.current_state == Constants.GameState.DEAD
	state.is_cruising = _ship.cruise_warp_active

	# Clan tag
	var clan_mgr = GameManager.get_node_or_null("ClanManager")
	if clan_mgr and clan_mgr.has_clan():
		state.clan_tag = clan_mgr.clan_data.clan_tag

	# Reliable death/respawn events (detect transitions)
	if state.is_dead and not _was_dead:
		_was_dead = true
		var death_pos = FloatingOrigin.to_universe_pos(_ship.global_position)
		NetworkManager._rpc_player_died.rpc_id(1, death_pos)
	elif not state.is_dead and _was_dead:
		_was_dead = false
		NetworkManager._rpc_player_respawned.rpc_id(1, state.system_id)

	# Combat state
	var health = _ship.get_node_or_null("HealthSystem")
	if health:
		state.hull_ratio = health.hull_current / health.hull_max if health.hull_max > 0 else 1.0
		var smpf: float = health.shield_max_per_facing
		if smpf > 0.0:
			state.shield_ratios[0] = health.shield_current[0] / smpf
			state.shield_ratios[1] = health.shield_current[1] / smpf
			state.shield_ratios[2] = health.shield_current[2] / smpf
			state.shield_ratios[3] = health.shield_current[3] / smpf

	# Send state to server via RPC
	NetworkManager._rpc_sync_state.rpc_id(1, state.to_dict())


## Called after ship change to rebind to new WeaponManager.
func reconnect_weapon_signal() -> void:
	if _ship == null:
		return
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm and not wm.weapon_fired.is_connected(_on_weapon_fired):
		wm.weapon_fired.connect(_on_weapon_fired)


func _on_weapon_fired(hardpoint_id: int, weapon_name_str: StringName) -> void:
	if NetworkManager.is_server() or not NetworkManager.is_connected_to_server():
		return

	var wm = _ship.get_node_or_null("WeaponManager")
	if wm == null or hardpoint_id >= wm.hardpoints.size():
		return

	var hp: Hardpoint = wm.hardpoints[hardpoint_id]
	var muzzle =hp.get_muzzle_transform()
	var fire_pos =FloatingOrigin.to_universe_pos(muzzle.origin)
	# Use actual aim direction (toward crosshair) matching local fire behavior
	var fire_dir: Vector3
	var aim_to_muzzle = _ship._aim_point - muzzle.origin
	if aim_to_muzzle.length_squared() > 1.0:
		fire_dir = aim_to_muzzle.normalized()
	else:
		fire_dir = (-muzzle.basis.z).normalized()
	var ship_vel = _ship.linear_velocity

	NetworkManager._rpc_fire_event.rpc_id(1,
		String(weapon_name_str), fire_pos,
		[fire_dir.x, fire_dir.y, fire_dir.z, ship_vel.x, ship_vel.y, ship_vel.z])


## Send mining beam state at 10Hz (visual only, no damage).
func _send_mining_state() -> void:
	if _ship == null:
		return
	var mining = _ship.get_node_or_null("MiningSystem")
	if mining == null:
		return

	var beam = mining._beam
	if beam == null:
		return

	var is_active: bool = beam._active
	if not is_active:
		return  # Only send when beam is active (deactivation sent once below)

	# Get beam endpoints
	var source_pos: Array = [0.0, 0.0, 0.0]
	var target_pos: Array = [0.0, 0.0, 0.0]
	if beam._core_mesh and beam._core_mesh.visible:
		# Source = source light position, Target = impact light position
		if beam._source_light:
			source_pos = FloatingOrigin.to_universe_pos(beam._source_light.global_position)
		if beam._impact_light:
			target_pos = FloatingOrigin.to_universe_pos(beam._impact_light.global_position)

	NetworkManager._rpc_mining_beam.rpc_id(1, true, source_pos, target_pos)


var _was_mining: bool = false

func _process(_delta: float) -> void:
	if _ship == null or NetworkManager.is_server() or not NetworkManager.is_connected_to_server():
		return
	# Detect mining stop → send deactivation once
	var mining = _ship.get_node_or_null("MiningSystem")
	if mining == null:
		return
	var beam = mining._beam
	var currently_mining: bool = beam != null and beam._active
	if _was_mining and not currently_mining:
		var empty: Array = [0.0, 0.0, 0.0]
		NetworkManager._rpc_mining_beam.rpc_id(1, false, empty, empty)
	_was_mining = currently_mining
