class_name NetPlayerEvents
extends RefCounted

# =============================================================================
# NetPlayerEvents — Player lifecycle events: death, respawn, ship change,
# system change, and PvP kill attribution.
# =============================================================================

var _nm: NetworkManagerSystem

# PvP kill attribution: target_pid -> { "attacker_pid": int, "weapon": String, "time": float }
var _pvp_last_attacker: Dictionary = {}


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Track that attacker_pid hit victim_pid (for kill attribution).
func track_pvp_hit(attacker_pid: int, victim_pid: int, weapon_name: String) -> void:
	_pvp_last_attacker[victim_pid] = {"attacker_pid": attacker_pid, "weapon": weapon_name, "time": Time.get_unix_time_from_system()}


## Get the last attacker of victim_pid, or -1 if none / expired.
func get_pvp_attacker(victim_pid: int) -> int:
	if not _pvp_last_attacker.has(victim_pid):
		return -1
	return _pvp_last_attacker[victim_pid].get("attacker_pid", -1)


## Handle player death notification from sender_id.
func handle_death(sender_id: int, death_pos: Array) -> void:
	var state = _nm.peers.get(sender_id)
	if state == null:
		return
	state.is_dead = true
	for pid in _nm.get_peers_in_system(state.system_id):
		if pid == sender_id:
			continue
		_nm._rpc_receive_player_died.rpc_id(pid, sender_id, death_pos)
	_report_pvp_kill(sender_id, state)


## Handle player respawn notification from sender_id.
func handle_respawn(sender_id: int, system_id: int) -> void:
	var state = _nm.peers.get(sender_id)
	if state:
		state.is_dead = false
		state.system_id = system_id
	for pid in _nm.get_peers_in_system(system_id):
		if pid == sender_id:
			continue
		_nm._rpc_receive_player_respawned.rpc_id(pid, sender_id, system_id)


## Handle ship change notification from sender_id.
func handle_ship_change(sender_id: int, new_ship_id_str: String) -> void:
	var new_sid: StringName = StringName(new_ship_id_str)
	var state = _nm.peers.get(sender_id)
	if state:
		state.ship_id = new_sid
		var sdata: ShipData = ShipRegistry.get_ship_data(new_sid)
		state.ship_class = sdata.ship_class if sdata else &"Fighter"
	for pid in _nm.peers:
		if pid == sender_id:
			continue
		_nm._rpc_receive_player_ship_changed.rpc_id(pid, sender_id, new_ship_id_str)


## Handle system change from sender_id (old_system_id -> new_system_id).
func handle_system_change(sender_id: int, old_system_id: int, new_system_id: int) -> void:
	var state = _nm.peers.get(sender_id)
	if state == null:
		return
	state.system_id = new_system_id
	_nm._peer_registry.update_last_system(sender_id, new_system_id)
	# Notify peers in old system: remove puppet
	for pid in _nm.get_peers_in_system(old_system_id):
		if pid == sender_id:
			continue
		_nm._rpc_receive_player_left_system.rpc_id(pid, sender_id)
	# Notify peers in new system: create puppet
	var ship_id_str: String = String(state.ship_id)
	for pid in _nm.get_peers_in_system(new_system_id):
		if pid == sender_id:
			continue
		_nm._rpc_receive_player_entered_system.rpc_id(pid, sender_id, ship_id_str)


# -------------------------------------------------------------------------
# Private helpers
# -------------------------------------------------------------------------

func _report_pvp_kill(victim_pid: int, victim_state) -> void:
	if not _pvp_last_attacker.has(victim_pid):
		return
	var info: Dictionary = _pvp_last_attacker[victim_pid]
	_pvp_last_attacker.erase(victim_pid)
	var elapsed: float = Time.get_unix_time_from_system() - info["time"]
	if elapsed > 15.0:
		return
	var attacker_pid: int = info["attacker_pid"]
	var weapon_name: String = info["weapon"]

	var reporter = GameManager.get_node_or_null("EventReporter")
	if reporter == null:
		return

	var killer_name: String = "Pilote"
	if _nm.peers.has(attacker_pid):
		killer_name = _nm.peers[attacker_pid].player_name
	var victim_name: String = "Pilote"
	if victim_state:
		victim_name = victim_state.player_name

	var weapon_display: String = weapon_name
	if weapon_name != "":
		var w = WeaponRegistry.get_weapon(StringName(weapon_name))
		if w:
			weapon_display = String(w.weapon_name) if w.weapon_name != &"" else weapon_name

	var system_name: String = "Unknown"
	if GameManager._galaxy:
		system_name = GameManager._galaxy.get_system_name(victim_state.system_id)

	print("[PvP] Kill report: %s -> %s (%s) in %s" % [killer_name, victim_name, weapon_display, system_name])
	reporter.report_kill(killer_name, victim_name, weapon_display, system_name, victim_state.system_id)
