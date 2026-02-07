class_name ShipNetworkSync
extends Node

# =============================================================================
# Ship Network Sync - Sends local player's ship state to the server at 20Hz.
# Attached as a child of the local player's ShipController.
# =============================================================================

var _ship: ShipController = null
var _send_timer: float = 0.0


func _ready() -> void:
	_ship = get_parent() as ShipController
	if _ship == null:
		push_error("ShipNetworkSync: Parent must be ShipController")
		set_process(false)
		set_physics_process(false)


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

	# System ID from SystemTransition
	var gm := GameManager as GameManagerSystem
	if gm and gm._system_transition:
		state.system_id = gm._system_transition.current_system_id

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
