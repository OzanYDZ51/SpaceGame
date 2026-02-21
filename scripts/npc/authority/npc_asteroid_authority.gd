class_name NpcAsteroidAuthority
extends RefCounted

# =============================================================================
# NPC Asteroid Authority - Server-side asteroid health tracking and mining sync.
# Extracted from NpcAuthority. Runs as a RefCounted sub-object.
# =============================================================================

const ASTEROID_HEALTH_BATCH_INTERVAL: float = 0.5  # 2Hz broadcast
const MINING_MAX_DPS: float = 30.0  # Max reasonable mining DPS (tolerance ×1.5 applied)
const ASTEROID_RESPAWN_TIME_CLEANUP: float = 300.0  # 5min stale entry cleanup

var _asteroid_health_timer: float = 0.0
var _asteroid_health: Dictionary = {}    # system_id -> { asteroid_id -> { hp, hm, t } }
var _peer_mining_dps: Dictionary = {}    # peer_id -> { asteroid_id -> { dmg, t0 } }
var _asteroid_health_cleanup_timer: float = 0.0

var _auth: NpcAuthority = null


func setup(auth: NpcAuthority) -> void:
	_auth = auth


func tick(delta: float) -> void:
	_asteroid_health_timer -= delta
	if _asteroid_health_timer <= 0.0:
		_asteroid_health_timer = ASTEROID_HEALTH_BATCH_INTERVAL
		_broadcast_asteroid_health_batch()

	_asteroid_health_cleanup_timer -= delta
	if _asteroid_health_cleanup_timer <= 0.0:
		_asteroid_health_cleanup_timer = 60.0
		_cleanup_stale_asteroid_health()


## Relay a mining beam state to all peers in the sender's system.
func relay_mining_beam(sender_pid: int, is_active: bool, source_pos: Array, target_pos: Array) -> void:
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peers_in_sys = NetworkManager.get_peers_in_system(sender_state.system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_remote_mining_beam.rpc_id(pid, sender_pid, is_active, source_pos, target_pos)


## Broadcast asteroid depletion to all peers in the system.
func broadcast_asteroid_depleted(asteroid_id: String, system_id: int, sender_pid: int) -> void:
	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		if pid == sender_pid:
			continue
		NetworkManager._rpc_receive_asteroid_depleted.rpc_id(pid, asteroid_id)


## Server receives batched mining damage claims from a client.
func handle_mining_damage_claims(sender_pid: int, claims: Array) -> void:
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	if sender_state.is_docked or sender_state.is_dead:
		return

	var system_id: int = sender_state.system_id
	var now: float = Time.get_ticks_msec() / 1000.0

	for claim in claims:
		if not claim is Dictionary:
			continue
		var asteroid_id: String = claim.get("aid", "")
		var damage: float = claim.get("dmg", 0.0)
		var health_max: float = claim.get("hm", 100.0)

		if asteroid_id == "" or damage <= 0.0:
			continue

		# DPS validation
		if not _peer_mining_dps.has(sender_pid):
			_peer_mining_dps[sender_pid] = {}
		var peer_tracking: Dictionary = _peer_mining_dps[sender_pid]
		if not peer_tracking.has(asteroid_id):
			peer_tracking[asteroid_id] = { "dmg": 0.0, "t0": now }
		var track: Dictionary = peer_tracking[asteroid_id]

		var elapsed: float = now - track["t0"]
		if elapsed > 2.0:
			track["dmg"] = damage
			track["t0"] = now
		else:
			track["dmg"] += damage

		var window_dps: float = track["dmg"] / maxf(elapsed, 0.1)
		if window_dps > MINING_MAX_DPS * 1.5:
			continue

		_apply_asteroid_damage(system_id, asteroid_id, damage, now, health_max)


## Apply validated mining damage to server-side asteroid health tracker.
func _apply_asteroid_damage(system_id: int, asteroid_id: String, damage: float, timestamp: float, health_max_hint: float) -> void:
	if not _asteroid_health.has(system_id):
		# Cap tracked systems to prevent unbounded memory growth
		if _asteroid_health.size() >= 50:
			var oldest_sys: int = -1
			var oldest_time: float = INF
			for sid in _asteroid_health:
				var sys_h: Dictionary = _asteroid_health[sid]
				for aid in sys_h:
					var t: float = sys_h[aid].get("t", 0.0)
					if t < oldest_time:
						oldest_time = t
						oldest_sys = sid
					break
			if oldest_sys >= 0:
				_asteroid_health.erase(oldest_sys)
		_asteroid_health[system_id] = {}
	var sys_health: Dictionary = _asteroid_health[system_id]

	if not sys_health.has(asteroid_id):
		var hm: float = clampf(health_max_hint, 50.0, 800.0)
		sys_health[asteroid_id] = { "hp": hm, "hm": hm, "t": timestamp }

	var entry: Dictionary = sys_health[asteroid_id]
	entry["hp"] = maxf(entry["hp"] - damage, 0.0)
	entry["t"] = timestamp

	if entry["hp"] <= 0.0:
		broadcast_asteroid_depleted(asteroid_id, system_id, -1)


func _broadcast_asteroid_health_batch() -> void:
	if _asteroid_health.is_empty():
		return

	var peers_by_sys: Dictionary = {}
	for pid in NetworkManager.peers:
		var pstate = NetworkManager.peers[pid]
		if not peers_by_sys.has(pstate.system_id):
			peers_by_sys[pstate.system_id] = []
		peers_by_sys[pstate.system_id].append(pid)

	for system_id in _asteroid_health:
		if not peers_by_sys.has(system_id):
			continue
		var sys_health: Dictionary = _asteroid_health[system_id]
		if sys_health.is_empty():
			continue

		var batch: Array = []
		for asteroid_id in sys_health:
			var entry: Dictionary = sys_health[asteroid_id]
			var hm: float = entry["hm"]
			if hm <= 0.0:
				continue
			var ratio: float = entry["hp"] / hm
			if ratio >= 1.0:
				continue
			batch.append({ "aid": asteroid_id, "hp": ratio })

		if batch.is_empty():
			continue

		var peer_ids: Array = peers_by_sys[system_id]
		for pid in peer_ids:
			NetworkManager._rpc_asteroid_health_batch.rpc_id(pid, batch)


## Send current asteroid health state to a newly joined peer.
func send_asteroid_health_to_peer(peer_id: int, system_id: int) -> void:
	if not _asteroid_health.has(system_id):
		return
	var sys_health: Dictionary = _asteroid_health[system_id]
	if sys_health.is_empty():
		return

	var batch: Array = []
	for asteroid_id in sys_health:
		var entry: Dictionary = sys_health[asteroid_id]
		var hm: float = entry["hm"]
		if hm <= 0.0:
			continue
		var ratio: float = entry["hp"] / hm
		if ratio >= 1.0:
			continue
		batch.append({ "aid": asteroid_id, "hp": ratio })

	if batch.is_empty():
		return

	NetworkManager._rpc_asteroid_health_batch.rpc_id(peer_id, batch)


## Clear asteroid health data when a system unloads.
func clear_system_asteroid_health(system_id: int) -> void:
	_asteroid_health.erase(system_id)


## Clean up DPS tracking when a peer disconnects.
func clean_peer_mining_tracking(peer_id: int) -> void:
	_peer_mining_dps.erase(peer_id)


## AI fleet mining damage: update server tracker.
func apply_ai_mining_damage(system_id: int, asteroid_id: String, damage: float, health_max: float) -> void:
	_apply_asteroid_damage(system_id, asteroid_id, damage, Time.get_ticks_msec() / 1000.0, health_max)


func _cleanup_stale_asteroid_health() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for system_id in _asteroid_health.keys():
		var sys_health: Dictionary = _asteroid_health[system_id]
		var expired: Array = []
		for asteroid_id in sys_health:
			var entry: Dictionary = sys_health[asteroid_id]
			if now - entry["t"] > ASTEROID_RESPAWN_TIME_CLEANUP:
				expired.append(asteroid_id)
		for asteroid_id in expired:
			sys_health.erase(asteroid_id)
		if sys_health.is_empty():
			_asteroid_health.erase(system_id)
