class_name NetGroupManager
extends RefCounted

# =============================================================================
# NetGroupManager — Ephemeral party (group) system, server-side in-memory only.
# Client-side local state (local_group_id, local_group_data) is stored on NM
# and updated by the RPCs that arrive on the client.
# =============================================================================

var _nm: NetworkManagerSystem

# Server-side group data
var _groups: Dictionary = {}          # group_id (int) -> {leader: peer_id, members: [peer_ids]}
var _player_group: Dictionary = {}    # peer_id -> group_id
var _pending_invites: Dictionary = {} # target_peer_id -> {from: peer_id, group_id: int, time: float}
var _next_group_id: int = 1

const MAX_GROUP_SIZE: int = 5
const INVITE_TIMEOUT: float = 30.0

# Client-side local state (mirrors what the server sent us)
var local_group_id: int = 0
var local_group_data: Dictionary = {}


func _init(nm: NetworkManagerSystem) -> void:
	_nm = nm


# -------------------------------------------------------------------------
# Per-frame tick
# -------------------------------------------------------------------------

## Expire stale group invites (server-side only).
func tick(now: float) -> void:
	if _pending_invites.is_empty():
		return
	var expired: Array = []
	for target_pid in _pending_invites:
		if now - _pending_invites[target_pid]["time"] > INVITE_TIMEOUT:
			expired.append(target_pid)
	for target_pid in expired:
		_pending_invites.erase(target_pid)


# -------------------------------------------------------------------------
# Server-side: incoming request handlers
# -------------------------------------------------------------------------

## Handle an invite request from sender_id targeting target_pid.
func handle_invite(sender_id: int, target_pid: int) -> void:
	if not _nm.peers.has(target_pid) or target_pid == sender_id:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Joueur introuvable.")
		return
	if _player_group.has(target_pid) and _player_group[target_pid] > 0:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Ce joueur est déjà dans un groupe.")
		return
	if _pending_invites.has(target_pid):
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Ce joueur a déjà une invitation en attente.")
		return

	var gid: int = _player_group.get(sender_id, 0)
	if gid == 0:
		gid = _next_group_id
		_next_group_id += 1
		_groups[gid] = {"leader": sender_id, "members": [sender_id]}
		_player_group[sender_id] = gid
		if _nm.peers.has(sender_id):
			_nm.peers[sender_id].group_id = gid

	if _groups[gid]["leader"] != sender_id:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Seul le leader peut inviter.")
		return
	if _groups[gid]["members"].size() >= MAX_GROUP_SIZE:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Groupe plein (%d max)." % MAX_GROUP_SIZE)
		return

	_pending_invites[target_pid] = {"from": sender_id, "group_id": gid, "time": Time.get_unix_time_from_system()}
	var inviter_name: String = _nm.peers[sender_id].player_name if _nm.peers.has(sender_id) else "Pilote"
	_nm._rpc_receive_group_invite.rpc_id(target_pid, inviter_name, gid)
	_broadcast_group_update(gid)


## Handle accept/decline response from sender_id. inviter_pid is not used directly
## (we look up the pending invite by sender_id).
func handle_response(sender_id: int, accepted: bool) -> void:
	if not _pending_invites.has(sender_id):
		return
	var invite: Dictionary = _pending_invites[sender_id]
	_pending_invites.erase(sender_id)
	var gid: int = invite["group_id"]

	if not accepted:
		var from_pid: int = invite["from"]
		var decliner_name: String = _nm.peers[sender_id].player_name if _nm.peers.has(sender_id) else "Pilote"
		if _nm.peers.has(from_pid):
			_nm._rpc_receive_group_error.rpc_id(from_pid, "%s a refusé l'invitation." % decliner_name)
		return

	if not _groups.has(gid):
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Le groupe n'existe plus.")
		return
	if _groups[gid]["members"].size() >= MAX_GROUP_SIZE:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Groupe plein.")
		return
	if _player_group.has(sender_id) and _player_group[sender_id] > 0:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Vous êtes déjà dans un groupe.")
		return

	_groups[gid]["members"].append(sender_id)
	_player_group[sender_id] = gid
	if _nm.peers.has(sender_id):
		_nm.peers[sender_id].group_id = gid
	_broadcast_group_update(gid)


## Handle a leave request from sender_id.
func handle_leave(sender_id: int) -> void:
	var gid: int = _player_group.get(sender_id, 0)
	if gid == 0 or not _groups.has(gid):
		return
	if _groups[gid]["leader"] == sender_id:
		_dissolve_group(gid, "Le leader a quitté le groupe.")
	else:
		_remove_member_from_group(gid, sender_id)


## Handle a kick request from sender_id targeting target_pid.
func handle_kick(sender_id: int, target_pid: int) -> void:
	var gid: int = _player_group.get(sender_id, 0)
	if gid == 0 or not _groups.has(gid):
		return
	if _groups[gid]["leader"] != sender_id:
		_nm._rpc_receive_group_error.rpc_id(sender_id, "Seul le leader peut expulser.")
		return
	if target_pid == sender_id:
		return
	if _player_group.get(target_pid, 0) != gid:
		return
	_remove_member_from_group(gid, target_pid)
	_nm._rpc_receive_group_dissolved.rpc_id(target_pid, "Vous avez été expulsé du groupe.")


## Handle a peer disconnecting (clean up invites and group membership).
func handle_peer_disconnect(pid: int) -> void:
	_pending_invites.erase(pid)
	var to_erase: Array = []
	for target_pid in _pending_invites:
		if _pending_invites[target_pid]["from"] == pid:
			to_erase.append(target_pid)
	for target_pid in to_erase:
		_pending_invites.erase(target_pid)

	var gid: int = _player_group.get(pid, 0)
	if gid == 0 or not _groups.has(gid):
		return
	if _groups[gid]["leader"] == pid:
		_dissolve_group(gid, "Le leader s'est déconnecté.")
	else:
		_remove_member_from_group(gid, pid)


# -------------------------------------------------------------------------
# Client-side helpers
# -------------------------------------------------------------------------

## Update client-side local group state (called from _rpc_receive_group_update).
func apply_group_update(gdata: Dictionary) -> void:
	local_group_id = gdata.get("group_id", 0)
	local_group_data = gdata


## Clear client-side local group state (called from _rpc_receive_group_dissolved).
func clear_local_group() -> void:
	local_group_id = 0
	local_group_data = {}


## Check if a peer is in the local player's group (client-side).
func is_peer_in_my_group(peer_id: int) -> bool:
	if local_group_id == 0:
		return false
	for m in local_group_data.get("members", []):
		if m.get("peer_id", -1) == peer_id:
			return true
	return false


## Clear all group state (called on full disconnect).
func clear_all() -> void:
	_groups.clear()
	_player_group.clear()
	_pending_invites.clear()
	local_group_id = 0
	local_group_data = {}


# -------------------------------------------------------------------------
# Private server-side helpers
# -------------------------------------------------------------------------

func _broadcast_group_update(gid: int) -> void:
	if not _groups.has(gid):
		return
	var group: Dictionary = _groups[gid]
	var members_data: Array = []
	for pid in group["members"]:
		var entry: Dictionary = {"peer_id": pid, "name": "Pilote", "hull": 1.0, "system_id": 0, "is_leader": pid == group["leader"]}
		if _nm.peers.has(pid):
			entry["name"] = _nm.peers[pid].player_name
			entry["hull"] = _nm.peers[pid].hull_ratio
			entry["system_id"] = _nm.peers[pid].system_id
		members_data.append(entry)
	var gdata: Dictionary = {"group_id": gid, "leader": group["leader"], "members": members_data}
	for pid in group["members"]:
		_nm._rpc_receive_group_update.rpc_id(pid, gdata)


func _dissolve_group(gid: int, reason: String) -> void:
	if not _groups.has(gid):
		return
	var members: Array = _groups[gid]["members"].duplicate()
	for pid in members:
		_player_group.erase(pid)
		if _nm.peers.has(pid):
			_nm.peers[pid].group_id = 0
		_nm._rpc_receive_group_dissolved.rpc_id(pid, reason)
	var to_erase: Array = []
	for target_pid in _pending_invites:
		if _pending_invites[target_pid]["group_id"] == gid:
			to_erase.append(target_pid)
	for target_pid in to_erase:
		_pending_invites.erase(target_pid)
	_groups.erase(gid)


func _remove_member_from_group(gid: int, pid: int) -> void:
	if not _groups.has(gid):
		return
	var members: Array = _groups[gid]["members"]
	members.erase(pid)
	_player_group.erase(pid)
	if _nm.peers.has(pid):
		_nm.peers[pid].group_id = 0
	if members.size() <= 1:
		_dissolve_group(gid, "Le groupe a été dissous (pas assez de membres).")
		return
	_broadcast_group_update(gid)
