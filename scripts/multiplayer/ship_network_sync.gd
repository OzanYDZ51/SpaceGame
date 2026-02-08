class_name ShipNetworkSync
extends Node

# =============================================================================
# Ship Network Sync - Sends local player's ship state to the server at 20Hz.
# Attached as a child of the local player's ShipController.
# =============================================================================

var _ship: ShipController = null
var _send_timer: float = 0.0
var _was_dead: bool = false


func _ready() -> void:
	_ship = get_parent() as ShipController
	if _ship == null:
		push_error("ShipNetworkSync: Parent must be ShipController")
		set_process(false)
		set_physics_process(false)
		return

	# Connect weapon fire signal for combat sync
	var wm := _ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm:
		wm.weapon_fired.connect(_on_weapon_fired)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_connected_to_server():
		return

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / Constants.NET_TICK_RATE
		_send_state()


func _send_state() -> void:
	var universe_pos := FloatingOrigin.to_universe_pos(_ship.global_position)

	var state := NetworkState.new()
	state.peer_id = NetworkManager.local_peer_id
	state.pos_x = universe_pos[0]
	state.pos_y = universe_pos[1]
	state.pos_z = universe_pos[2]
	state.velocity = _ship.linear_velocity
	state.rotation_deg = _ship.rotation_degrees
	state.throttle = _ship.throttle_input.length()
	state.timestamp = Time.get_ticks_msec() / 1000.0
	state.ship_id = _ship.ship_data.ship_id if _ship.ship_data else &"fighter_mk1"

	# System ID from SystemTransition
	var gm := GameManager as GameManagerSystem
	if gm and gm._system_transition:
		state.system_id = gm._system_transition.current_system_id

	# Status flags
	if gm:
		state.is_docked = gm.current_state == GameManagerSystem.GameState.DOCKED
		state.is_dead = gm.current_state == GameManagerSystem.GameState.DEAD
	state.is_cruising = _ship.cruise_warp_active

	# Reliable death/respawn events (detect transitions)
	if state.is_dead and not _was_dead:
		_was_dead = true
		var death_pos := FloatingOrigin.to_universe_pos(_ship.global_position)
		if NetworkManager.is_host:
			var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
			if npc_auth:
				# Host: relay death directly to peers in same system
				for pid in NetworkManager.get_peers_in_system(state.system_id):
					if pid == 1:
						continue
					NetworkManager._rpc_receive_player_died.rpc_id(pid, 1, death_pos)
		else:
			NetworkManager._rpc_player_died.rpc_id(1, death_pos)
	elif not state.is_dead and _was_dead:
		_was_dead = false
		if NetworkManager.is_host:
			for pid in NetworkManager.get_peers_in_system(state.system_id):
				if pid == 1:
					continue
				NetworkManager._rpc_receive_player_respawned.rpc_id(pid, 1, state.system_id)
		else:
			NetworkManager._rpc_player_respawned.rpc_id(1, state.system_id)

	# Combat state
	var health := _ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		state.hull_ratio = health.hull_current / health.hull_max if health.hull_max > 0 else 1.0
		state.shield_ratios = [
			health.shield_current[0] / health.shield_max_per_facing if health.shield_max_per_facing > 0 else 1.0,
			health.shield_current[1] / health.shield_max_per_facing if health.shield_max_per_facing > 0 else 1.0,
			health.shield_current[2] / health.shield_max_per_facing if health.shield_max_per_facing > 0 else 1.0,
			health.shield_current[3] / health.shield_max_per_facing if health.shield_max_per_facing > 0 else 1.0,
		]

	if NetworkManager.is_host:
		# Host: update our own state directly in the peers dict
		# (ServerAuthority will broadcast it to other clients)
		if NetworkManager.peers.has(1):
			var my_state: NetworkState = NetworkManager.peers[1]
			my_state.from_dict(state.to_dict())
			my_state.peer_id = 1
	else:
		# Client: send to server via RPC
		NetworkManager._rpc_sync_state.rpc_id(1, state.to_dict())


## Called after ship change to rebind to new WeaponManager.
func reconnect_weapon_signal() -> void:
	if _ship == null:
		return
	var wm := _ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm and not wm.weapon_fired.is_connected(_on_weapon_fired):
		wm.weapon_fired.connect(_on_weapon_fired)


func _on_weapon_fired(hardpoint_id: int, weapon_name_str: StringName) -> void:
	if not NetworkManager.is_connected_to_server():
		return

	var wm := _ship.get_node_or_null("WeaponManager") as WeaponManager
	if wm == null or hardpoint_id >= wm.hardpoints.size():
		return

	var hp: Hardpoint = wm.hardpoints[hardpoint_id]
	var muzzle := hp.get_muzzle_transform()
	var fire_pos := FloatingOrigin.to_universe_pos(muzzle.origin)
	# Use actual aim direction (toward crosshair) matching local fire behavior
	var fire_dir: Vector3
	var aim_to_muzzle := _ship._aim_point - muzzle.origin
	if aim_to_muzzle.length_squared() > 1.0:
		fire_dir = aim_to_muzzle.normalized()
	else:
		fire_dir = (-muzzle.basis.z).normalized()
	var ship_vel := _ship.linear_velocity

	if NetworkManager.is_host:
		# Host: relay directly via NpcAuthority
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			npc_auth.relay_fire_event(1, String(weapon_name_str), fire_pos,
				[fire_dir.x, fire_dir.y, fire_dir.z, ship_vel.x, ship_vel.y, ship_vel.z])
	else:
		NetworkManager._rpc_fire_event.rpc_id(1,
			String(weapon_name_str), fire_pos,
			[fire_dir.x, fire_dir.y, fire_dir.z, ship_vel.x, ship_vel.y, ship_vel.z])
