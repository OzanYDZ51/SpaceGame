class_name NetCombatServer
extends RefCounted

# =============================================================================
# NetCombatServer — PvP hit validation and relay.
# All validation is server-side; results are relayed via NM RPCs.
# =============================================================================

var _nm: NetworkManagerSystem


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Validate and relay a PvP hit claim.
## Returns true if the hit was accepted and damage relayed to the target.
func validate_hit(sender_id: int, target_pid: int, weapon_name: String, damage_val: float, hit_dir: Array) -> bool:
	# Basic bounds check
	if damage_val < 0.0 or damage_val > 500.0:
		return false
	if not _nm.peers.has(target_pid) or not _nm.peers.has(sender_id):
		return false

	var sender_state = _nm.peers[sender_id]
	var target_state = _nm.peers[target_pid]

	# Same system check
	if sender_state.system_id != target_state.system_id:
		return false

	# Reject hits on docked or dead players
	if target_state.is_docked or target_state.is_dead:
		return false

	# Friendly fire protection: reject hits on group members
	var sender_gid: int = _nm._group_mgr._player_group.get(sender_id, 0)
	if sender_gid > 0 and _nm._group_mgr._player_group.get(target_pid, 0) == sender_gid:
		return false

	# Distance validation (float64 arithmetic — Vector3 is float32)
	var dx: float = sender_state.pos_x - target_state.pos_x
	var dy: float = sender_state.pos_y - target_state.pos_y
	var dz: float = sender_state.pos_z - target_state.pos_z
	if dx * dx + dy * dy + dz * dz > 3000.0 * 3000.0:
		return false

	# Weapon damage bounds — reject unknown weapons entirely
	var weapon = WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon == null:
		return false
	if damage_val > weapon.damage_per_hit * 1.5:
		return false

	# Track last attacker for kill attribution
	_nm._player_events.track_pvp_hit(sender_id, target_pid, weapon_name)

	# Relay damage to target player
	_nm._rpc_receive_player_damage.rpc_id(target_pid, sender_id, weapon_name, damage_val, hit_dir)

	# Broadcast hit effect to observers
	var npc_auth = GameManager.get_node_or_null("NpcAuthority") as Node
	if npc_auth:
		var target_label: String = "player_%d" % target_pid
		var peers_in_sys: Array[int] = _nm.get_peers_in_system(sender_state.system_id)
		for pid in peers_in_sys:
			if pid == sender_id or pid == target_pid:
				continue
			_nm._rpc_hit_effect.rpc_id(pid, target_label, hit_dir, false)

	return true


## Validate a structure hit claim from sender_id.
## Emits structure_hit_claimed signal on NM if valid.
func validate_structure_hit(sender_id: int, target_id: String, weapon: String, damage: float, hit_dir: Array) -> bool:
	if not _nm.peers.has(sender_id):
		return false
	if damage < 0.0 or damage > 500.0:
		return false
	var weapon_check = WeaponRegistry.get_weapon(StringName(weapon))
	if weapon_check == null:
		return false
	_nm.structure_hit_claimed.emit(sender_id, target_id, weapon, damage, hit_dir)
	return true
