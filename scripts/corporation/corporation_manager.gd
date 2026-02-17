class_name ClanManager
extends Node

# =============================================================================
# Clan Manager - Runtime API for clan state, signals, and backend integration
# All mutations go through methods that emit signals.
# Requires authentication — no fake/mock data.
# =============================================================================

signal clan_loaded
signal member_joined(member: ClanMember)
signal member_kicked(member: ClanMember)
signal member_promoted(member: ClanMember)
signal member_demoted(member: ClanMember)
signal motd_changed(new_motd: String)
signal treasury_changed(new_balance: float)
signal diplomacy_changed(clan_id: String, relation: String)
signal activity_added(entry: ClanActivity)
signal rank_updated(index: int)
signal recruitment_toggled(is_recruiting: bool)

var clan_data: ClanData = null
var members: Array[ClanMember] = []
var diplomacy: Dictionary = {}  # clan_id -> { "name", "tag", "relation", "since" }
var activity_log: Array[ClanActivity] = []
var transactions: Array[Dictionary] = []  # { "timestamp", "type", "amount", "actor" }
var player_member: ClanMember = null

var _loading: bool = false


func _ready() -> void:
	if AuthManager.is_authenticated:
		_load_from_backend()
	else:
		# Not authenticated — no clan data
		clan_data = null
		clan_loaded.emit()


# =============================================================================
# PUBLIC API
# =============================================================================

func has_clan() -> bool:
	return clan_data != null


func get_player_rank() -> ClanRank:
	if not has_clan() or player_member == null:
		return null
	if player_member.rank_index < clan_data.ranks.size():
		return clan_data.ranks[player_member.rank_index]
	return null


func player_has_permission(perm: int) -> bool:
	var rank := get_player_rank()
	return rank != null and rank.has_permission(perm)


func get_online_count() -> int:
	var count := 0
	for m in members:
		if m.is_online:
			count += 1
	return count


func get_member_by_id(id: String) -> ClanMember:
	for m in members:
		if m.player_id == id:
			return m
	return null


func create_clan(cname: String, tag: String, color: Color, emblem: int) -> bool:
	if has_clan() or not AuthManager.is_authenticated:
		return false

	var body := {
		"clan_name": cname,
		"clan_tag": tag,
		"clan_color": "%s,%s,%s,1.0" % [str(color.r), str(color.g), str(color.b)],
		"emblem_id": emblem,
	}
	var result := await ApiClient.post_async("/api/v1/clans", body)
	if result.get("_status_code", 0) != 201:
		push_warning("ClanManager: create_clan failed — %s" % result.get("error", "unknown"))
		return false
	# Reload from API
	var new_id: String = result.get("id", "")
	if new_id != "":
		await _load_clan_from_api(new_id)
	return has_clan()


func leave_clan() -> bool:
	if not has_clan():
		return false

	if AuthManager.is_authenticated and clan_data.clan_id != "":
		var result := await ApiClient.delete_async(
			"/api/v1/clans/%s/members/%s" % [clan_data.clan_id, AuthManager.player_id]
		)
		var code: int = result.get("_status_code", 0)
		if code != 200 and code != 204:
			push_warning("ClanManager: leave_clan failed (HTTP %d) — %s" % [code, result.get("error", "unknown")])
			return false

	player_member = null
	clan_data = null
	members.clear()
	diplomacy.clear()
	activity_log.clear()
	transactions.clear()
	clan_loaded.emit()
	return true


func invite_member(id: String, dname: String) -> bool:
	if not player_has_permission(ClanRank.PERM_INVITE) or not AuthManager.is_authenticated:
		return false
	if members.size() >= clan_data.max_members:
		return false

	var body := {"player_id": id}
	var result := await ApiClient.post_async("/api/v1/clans/%s/members" % clan_data.clan_id, body)
	if result.get("_status_code", 0) != 201:
		push_warning("ClanManager: invite_member failed — %s" % result.get("error", "unknown"))
		return false

	var m := ClanMember.new()
	m.player_id = id
	m.display_name = dname
	m.rank_index = clan_data.ranks.size() - 1
	m.join_timestamp = int(Time.get_unix_time_from_system())
	m.last_online_timestamp = m.join_timestamp
	m.is_online = true
	members.append(m)
	_log_activity(ClanActivity.EventType.JOIN, dname, "", "A rejoint le clan")
	member_joined.emit(m)
	return true


func kick_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_KICK) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m == player_member:
		return false
	if player_member and m.rank_index <= player_member.rank_index:
		return false

	var result := await ApiClient.delete_async("/api/v1/clans/%s/members/%s" % [clan_data.clan_id, id])
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: kick_member failed — %s" % result.get("error", "unknown"))
		return false

	_log_activity(ClanActivity.EventType.KICK, player_member.display_name, m.display_name, "A expulse %s" % m.display_name)
	members.erase(m)
	member_kicked.emit(m)
	return true


func promote_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_PROMOTE) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index <= 0:
		return false
	if player_member and m.rank_index - 1 <= player_member.rank_index:
		return false

	var new_rank_idx: int = m.rank_index - 1
	var new_priority: int = clan_data.ranks[new_rank_idx].priority if new_rank_idx < clan_data.ranks.size() else 0
	var result := await ApiClient.put_async("/api/v1/clans/%s/members/%s/rank" % [clan_data.clan_id, id], {"rank_priority": new_priority})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: promote_member failed — %s" % result.get("error", "unknown"))
		return false

	var old_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	m.rank_index = new_rank_idx
	var new_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	_log_activity(ClanActivity.EventType.PROMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_promoted.emit(m)
	return true


func demote_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_DEMOTE) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index >= clan_data.ranks.size() - 1:
		return false
	if player_member and m.rank_index <= player_member.rank_index:
		return false

	var new_rank_idx: int = m.rank_index + 1
	var new_priority: int = clan_data.ranks[new_rank_idx].priority if new_rank_idx < clan_data.ranks.size() else 0
	var result := await ApiClient.put_async("/api/v1/clans/%s/members/%s/rank" % [clan_data.clan_id, id], {"rank_priority": new_priority})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: demote_member failed — %s" % result.get("error", "unknown"))
		return false

	var old_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	m.rank_index = new_rank_idx
	var new_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	_log_activity(ClanActivity.EventType.DEMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_demoted.emit(m)
	return true


func set_motd(text: String) -> bool:
	if not player_has_permission(ClanRank.PERM_EDIT_MOTD) or not AuthManager.is_authenticated:
		return false

	var result := await ApiClient.put_async("/api/v1/clans/%s" % clan_data.clan_id, {"motd": text})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: set_motd failed — %s" % result.get("error", "unknown"))
		return false

	clan_data.motd = text
	_log_activity(ClanActivity.EventType.MOTD_CHANGE, player_member.display_name, "", "MOTD mis a jour")
	motd_changed.emit(text)
	return true


func deposit_funds(amount: float) -> bool:
	if amount <= 0 or not has_clan() or not AuthManager.is_authenticated:
		return false

	var result := await ApiClient.post_async("/api/v1/clans/%s/treasury/deposit" % clan_data.clan_id, {"amount": int(amount)})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: deposit_funds failed — %s" % result.get("error", "unknown"))
		return false
	clan_data.treasury_balance = float(result.get("treasury", clan_data.treasury_balance + amount))

	if player_member:
		player_member.contribution_total += amount
	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Depot", "amount": amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(ClanActivity.EventType.DEPOSIT, player_member.display_name if player_member else "?", "", "Depot de %s credits" % _format_number(amount))
	treasury_changed.emit(clan_data.treasury_balance)
	return true


func withdraw_funds(amount: float) -> bool:
	if amount <= 0 or not player_has_permission(ClanRank.PERM_WITHDRAW) or not AuthManager.is_authenticated:
		return false
	if amount > clan_data.treasury_balance:
		return false

	var result := await ApiClient.post_async("/api/v1/clans/%s/treasury/withdraw" % clan_data.clan_id, {"amount": int(amount)})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: withdraw_funds failed — %s" % result.get("error", "unknown"))
		return false
	clan_data.treasury_balance = float(result.get("treasury", clan_data.treasury_balance - amount))

	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Retrait", "amount": -amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(ClanActivity.EventType.WITHDRAW, player_member.display_name if player_member else "?", "", "Retrait de %s credits" % _format_number(amount))
	treasury_changed.emit(clan_data.treasury_balance)
	return true


func set_diplomacy_relation(target_clan_id: String, relation: String) -> bool:
	if not player_has_permission(ClanRank.PERM_DIPLOMACY) or not AuthManager.is_authenticated:
		return false
	if not diplomacy.has(target_clan_id):
		return false

	var result := await ApiClient.put_async("/api/v1/clans/%s/diplomacy" % clan_data.clan_id, {"target_clan_id": target_clan_id, "relation": relation})
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: set_diplomacy failed — %s" % result.get("error", "unknown"))
		return false

	var old_rel: String = diplomacy[target_clan_id].get("relation", "NEUTRE")
	diplomacy[target_clan_id]["relation"] = relation
	diplomacy[target_clan_id]["since"] = int(Time.get_unix_time_from_system())
	var cname: String = diplomacy[target_clan_id].get("name", target_clan_id)
	_log_activity(ClanActivity.EventType.DIPLOMACY, player_member.display_name if player_member else "?", cname, "%s: %s -> %s" % [cname, old_rel, relation])
	diplomacy_changed.emit(target_clan_id, relation)
	return true


func toggle_recruitment() -> void:
	if not has_clan():
		return
	clan_data.is_recruiting = not clan_data.is_recruiting
	if AuthManager.is_authenticated and clan_data.clan_id != "":
		ApiClient.put_async("/api/v1/clans/%s" % clan_data.clan_id, {"is_recruiting": clan_data.is_recruiting})
	recruitment_toggled.emit(clan_data.is_recruiting)


func update_rank(index: int, rname: String, perms: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false
	if index < 0 or index >= clan_data.ranks.size() or index == 0:
		return false

	if clan_data.ranks[index].db_id >= 0:
		var body := {"rank_name": rname, "permissions": perms}
		var result := await ApiClient.put_async(
			"/api/v1/clans/%s/ranks/%d" % [clan_data.clan_id, clan_data.ranks[index].db_id], body)
		if result.get("_status_code", 0) != 200:
			push_warning("ClanManager: update_rank failed — %s" % result.get("error", "unknown"))
			return false

	clan_data.ranks[index].rank_name = rname
	clan_data.ranks[index].permissions = perms
	_log_activity(ClanActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Rang modifie: %s" % rname)
	rank_updated.emit(index)
	return true


func add_rank(rname: String, perms: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false

	# New rank gets lowest priority
	var new_priority: int = 0
	if not clan_data.ranks.is_empty():
		var min_p: int = clan_data.ranks[0].priority
		for r in clan_data.ranks:
			if r.priority < min_p:
				min_p = r.priority
		new_priority = maxi(min_p - 1, 0)
		if min_p == 0:
			new_priority = 0
			for r in clan_data.ranks:
				r.priority += 1

	var r := ClanRank.new()
	r.rank_name = rname
	r.priority = new_priority
	r.permissions = perms

	var body := {"rank_name": rname, "priority": new_priority, "permissions": perms}
	var result := await ApiClient.post_async("/api/v1/clans/%s/ranks" % clan_data.clan_id, body)
	if result.get("_status_code", 0) != 201:
		push_warning("ClanManager: add_rank failed — %s" % result.get("error", "unknown"))
		return false
	r.db_id = int(result.get("id", -1))

	clan_data.ranks.append(r)
	_log_activity(ClanActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Nouveau rang: %s" % rname)
	rank_updated.emit(clan_data.ranks.size() - 1)
	return true


func remove_rank(index: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false
	if index <= 0 or index >= clan_data.ranks.size():
		return false

	if clan_data.ranks[index].db_id >= 0:
		var result := await ApiClient.delete_async(
			"/api/v1/clans/%s/ranks/%d" % [clan_data.clan_id, clan_data.ranks[index].db_id])
		var code: int = result.get("_status_code", 0)
		if code != 200 and code != 204:
			push_warning("ClanManager: remove_rank failed — %s" % result.get("error", "unknown"))
			return false

	for m in members:
		if m.rank_index == index:
			m.rank_index = mini(index, clan_data.ranks.size() - 2)
		elif m.rank_index > index:
			m.rank_index -= 1
	var rname: String = clan_data.ranks[index].rank_name
	clan_data.ranks.remove_at(index)
	_log_activity(ClanActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Rang supprime: %s" % rname)
	rank_updated.emit(-1)
	return true


## Refresh all clan data from the backend (called after login or manually).
func refresh_from_backend() -> void:
	if not AuthManager.is_authenticated:
		return
	if has_clan():
		await _load_clan_from_api(clan_data.clan_id)
	else:
		await _load_from_backend()


## Search for clans by name/tag. Returns array of { id, name, tag, members, is_recruiting }.
func search_clans(query: String) -> Array:
	if not AuthManager.is_authenticated:
		return []

	var result := await ApiClient.get_async("/api/v1/clans/search?q=%s" % query.uri_encode())
	if result.get("_status_code", 0) != 200:
		push_warning("ClanManager: search_clans failed — %s" % result.get("error", "unknown"))
		return []

	var clans: Array = []
	var arr: Array = _extract_array(result, "clans")
	for c in arr:
		if c is Dictionary:
			clans.append({
				"id": str(c.get("id", "")),
				"name": str(c.get("clan_name", "")),
				"tag": str(c.get("clan_tag", "")),
				"members": int(c.get("member_count", 0)),
				"is_recruiting": bool(c.get("is_recruiting", false)),
			})
	return clans


## Join an existing clan by ID. Returns true on success.
func join_clan(cid: String) -> bool:
	if has_clan() or not AuthManager.is_authenticated:
		return false

	var body := {"player_id": AuthManager.player_id}
	var result := await ApiClient.post_async("/api/v1/clans/%s/members" % cid, body)
	if result.get("_status_code", 0) != 201:
		push_warning("ClanManager: join_clan failed — %s" % result.get("error", "unknown"))
		return false
	await _load_clan_from_api(cid)
	return has_clan()


# =============================================================================
# BACKEND LOADING
# =============================================================================

func _load_from_backend() -> void:
	if _loading:
		return
	_loading = true

	# Get player's clan_id from their profile
	var profile := await ApiClient.get_async("/api/v1/player/profile/%s" % AuthManager.player_id)
	var pid_clan_id: String = ""
	if profile.get("_status_code", 0) == 200:
		pid_clan_id = str(profile.get("clan_id", ""))

	if pid_clan_id == "" or pid_clan_id == "<null>" or pid_clan_id == "null":
		# Player has no clan
		_loading = false
		clan_data = null
		clan_loaded.emit()
		return

	await _load_clan_from_api(pid_clan_id)
	_loading = false


func _load_clan_from_api(cid: String) -> void:
	# 1. Clan identity
	var clan_result := await ApiClient.get_async("/api/v1/clans/%s" % cid)
	if clan_result.get("_status_code", 0) != 200:
		push_warning("ClanManager: Failed to load clan %s — %s" % [cid, clan_result.get("error", "?")])
		clan_data = null
		clan_loaded.emit()
		return

	clan_data = ClanData.new()
	clan_data.clan_id = str(clan_result.get("id", cid))
	clan_data.clan_name = str(clan_result.get("clan_name", ""))
	clan_data.clan_tag = str(clan_result.get("clan_tag", ""))
	clan_data.description = str(clan_result.get("description", ""))
	clan_data.motto = str(clan_result.get("motto", ""))
	clan_data.motd = str(clan_result.get("motd", ""))
	clan_data.emblem_id = int(clan_result.get("emblem_id", 0))
	clan_data.treasury_balance = float(clan_result.get("treasury", 0))
	clan_data.reputation_score = int(clan_result.get("reputation", 0))
	clan_data.max_members = int(clan_result.get("max_members", 50))
	clan_data.is_recruiting = bool(clan_result.get("is_recruiting", true))

	# Parse clan_color "r,g,b,a" string
	var color_str: String = str(clan_result.get("clan_color", "0.15,0.85,1.0,1.0"))
	var color_parts := color_str.split(",")
	if color_parts.size() >= 3:
		clan_data.clan_color = Color(
			color_parts[0].to_float(),
			color_parts[1].to_float(),
			color_parts[2].to_float(),
			color_parts[3].to_float() if color_parts.size() >= 4 else 1.0,
		)

	var created_str: String = str(clan_result.get("created_at", ""))
	if created_str != "":
		clan_data.creation_timestamp = _parse_iso_timestamp(created_str)

	# 2. Ranks — fetch from dedicated endpoint
	clan_data.ranks.clear()
	var ranks_result := await ApiClient.get_async("/api/v1/clans/%s/ranks" % cid)
	if ranks_result.get("_status_code", 0) == 200:
		var ranks_arr: Array = _extract_array(ranks_result, "ranks")
		# Sort by priority descending so index 0 = highest priority = Leader
		ranks_arr.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		for rd in ranks_arr:
			if not rd is Dictionary:
				continue
			var r := ClanRank.new()
			r.db_id = int(rd.get("id", -1))
			r.rank_name = str(rd.get("rank_name", ""))
			r.priority = int(rd.get("priority", 0))
			r.permissions = int(rd.get("permissions", 0))
			clan_data.ranks.append(r)

	# Fallback defaults if no ranks fetched
	if clan_data.ranks.is_empty():
		var leader := ClanRank.new()
		leader.rank_name = "Chef"
		leader.priority = 4
		leader.permissions = ClanRank.ALL_PERMISSIONS
		clan_data.ranks.append(leader)
		var recruit := ClanRank.new()
		recruit.rank_name = "Recrue"
		recruit.priority = 0
		recruit.permissions = 0
		clan_data.ranks.append(recruit)

	# 3. Members
	members.clear()
	player_member = null
	var members_result := await ApiClient.get_async("/api/v1/clans/%s/members" % cid)
	if members_result.get("_status_code", 0) == 200:
		var members_arr: Array = _extract_array(members_result, "members")

		for md in members_arr:
			if not md is Dictionary:
				continue
			var m := ClanMember.new()
			m.player_id = str(md.get("player_id", ""))
			m.display_name = str(md.get("username", ""))
			m.contribution_total = float(md.get("contribution", 0))
			m.is_online = bool(md.get("is_online", false))

			# Map rank_priority to rank_index (ranks sorted by priority desc)
			var member_priority: int = int(md.get("rank_priority", 0))
			m.rank_index = clan_data.ranks.size() - 1  # default to lowest
			for ri in clan_data.ranks.size():
				if clan_data.ranks[ri].priority == member_priority:
					m.rank_index = ri
					break

			var joined_str: String = str(md.get("joined_at", ""))
			if joined_str != "":
				m.join_timestamp = _parse_iso_timestamp(joined_str)
			# Backend doesn't track last_online yet — use join_timestamp as fallback
			m.last_online_timestamp = m.join_timestamp

			members.append(m)
			if m.player_id == AuthManager.player_id:
				player_member = m

	# 4. Diplomacy
	diplomacy.clear()
	var diplo_result := await ApiClient.get_async("/api/v1/clans/%s/diplomacy" % cid)
	if diplo_result.get("_status_code", 0) == 200:
		var diplo_arr: Array = _extract_array(diplo_result, "diplomacy")
		for dd in diplo_arr:
			if not dd is Dictionary:
				continue
			var target_id: String = str(dd.get("target_clan_id", ""))
			if target_id == "":
				continue
			var since_str: String = str(dd.get("since", ""))
			diplomacy[target_id] = {
				"name": str(dd.get("target_name", target_id)),
				"tag": str(dd.get("target_tag", "")),
				"relation": str(dd.get("relation", "NEUTRE")).to_upper(),
				"since": _parse_iso_timestamp(since_str) if since_str != "" else 0,
			}

	# 5. Activity log
	activity_log.clear()
	var activity_result := await ApiClient.get_async("/api/v1/clans/%s/activity?limit=50" % cid)
	if activity_result.get("_status_code", 0) == 200:
		var act_arr: Array = _extract_array(activity_result, "activity")
		for ad in act_arr:
			if not ad is Dictionary:
				continue
			var a := ClanActivity.new()
			a.event_type = int(ad.get("event_type", 0)) as ClanActivity.EventType
			a.actor_name = str(ad.get("actor_name", ""))
			a.target_name = str(ad.get("target_name", ""))
			a.details = str(ad.get("details", ""))
			var ts_str: String = str(ad.get("created_at", ""))
			a.timestamp = _parse_iso_timestamp(ts_str) if ts_str != "" else 0
			activity_log.append(a)

	print("ClanManager: Loaded clan '%s' [%s] — %d members, %d diplo, %d activities" % [
		clan_data.clan_name, clan_data.clan_tag, members.size(), diplomacy.size(), activity_log.size()])
	clan_loaded.emit()


# =============================================================================
# HELPERS
# =============================================================================

## Extract an array from an API response Dictionary.
## Tries named key first, then "data" (ApiClient wraps bare arrays there), then any Array value.
func _extract_array(result: Dictionary, preferred_key: String = "") -> Array:
	if preferred_key != "" and result.has(preferred_key) and result[preferred_key] is Array:
		return result[preferred_key]
	if result.has("data") and result["data"] is Array:
		return result["data"]
	for key in result:
		if key != "_status_code" and result[key] is Array:
			return result[key]
	return []


func _log_activity(etype: ClanActivity.EventType, actor: String, target: String, detail: String) -> void:
	var entry := ClanActivity.new()
	entry.timestamp = int(Time.get_unix_time_from_system())
	entry.event_type = etype
	entry.actor_name = actor
	entry.target_name = target
	entry.details = detail
	activity_log.insert(0, entry)
	activity_added.emit(entry)


func _format_number(val: float) -> String:
	var i := int(val)
	var s := str(i)
	var result := ""
	var count := 0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[idx] + result
		count += 1
	return result


## Parse an ISO 8601 timestamp string to Unix timestamp (approximate).
func _parse_iso_timestamp(iso: String) -> int:
	# Expected: "2025-01-15T12:34:56Z" or "2025-01-15T12:34:56.000Z"
	if iso.is_empty():
		return 0
	# Strip timezone suffix for parsing
	var clean := iso.replace("Z", "").replace("+00:00", "")
	if "T" in clean:
		var parts := clean.split("T")
		if parts.size() == 2:
			var date_parts := parts[0].split("-")
			var time_str := parts[1].split(".")[0]  # Strip milliseconds
			var time_parts := time_str.split(":")
			if date_parts.size() >= 3 and time_parts.size() >= 3:
				var dt := {
					"year": date_parts[0].to_int(),
					"month": date_parts[1].to_int(),
					"day": date_parts[2].to_int(),
					"hour": time_parts[0].to_int(),
					"minute": time_parts[1].to_int(),
					"second": time_parts[2].to_int(),
				}
				return int(Time.get_unix_time_from_datetime_dict(dt))
	return 0
