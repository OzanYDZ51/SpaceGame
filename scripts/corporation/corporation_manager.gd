class_name CorporationManager
extends Node

# =============================================================================
# Corporation Manager - Runtime API for corporation state, signals, and backend
# All mutations go through methods that emit signals.
# Requires authentication — no fake/mock data.
# =============================================================================

signal corporation_loaded
signal member_joined(member: CorporationMember)
signal member_kicked(member: CorporationMember)
signal member_promoted(member: CorporationMember)
signal member_demoted(member: CorporationMember)
signal motd_changed(new_motd: String)
signal treasury_changed(new_balance: float)
signal diplomacy_changed(corporation_id: String, relation: String)
signal activity_added(entry: CorporationActivity)
signal rank_updated(index: int)
signal recruitment_toggled(is_recruiting: bool)

var corporation_data: CorporationData = null
var members: Array[CorporationMember] = []
var diplomacy: Dictionary = {}  # corporation_id -> { "name", "tag", "relation", "since" }
var activity_log: Array[CorporationActivity] = []
var transactions: Array[Dictionary] = []  # { "timestamp", "type", "amount", "actor" }
var player_member: CorporationMember = null

var _loading: bool = false


func _ready() -> void:
	if AuthManager.is_authenticated:
		_load_from_backend()
	else:
		corporation_data = null
		corporation_loaded.emit()


# =============================================================================
# PUBLIC API
# =============================================================================

func has_corporation() -> bool:
	return corporation_data != null


func get_player_rank() -> CorporationRank:
	if not has_corporation() or player_member == null:
		return null
	if player_member.rank_index < corporation_data.ranks.size():
		return corporation_data.ranks[player_member.rank_index]
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


func get_member_by_id(id: String) -> CorporationMember:
	for m in members:
		if m.player_id == id:
			return m
	return null


func create_corporation(cname: String, tag: String, color: Color, emblem: int) -> bool:
	if has_corporation() or not AuthManager.is_authenticated:
		return false

	var body := {
		"corporation_name": cname,
		"corporation_tag": tag,
		"corporation_color": "%s,%s,%s,1.0" % [str(color.r), str(color.g), str(color.b)],
		"emblem_id": emblem,
	}
	var result := await ApiClient.post_async("/api/v1/corporations", body)
	if result.get("_status_code", 0) != 201:
		push_warning("CorporationManager: create failed — %s" % result.get("error", "unknown"))
		return false
	var new_id: String = result.get("id", "")
	if new_id != "":
		await _load_corporation_from_api(new_id)
	return has_corporation()


func leave_corporation() -> bool:
	if not has_corporation():
		return false

	if AuthManager.is_authenticated and corporation_data.corporation_id != "":
		var result := await ApiClient.delete_async(
			"/api/v1/corporations/%s/members/%s" % [corporation_data.corporation_id, AuthManager.player_id]
		)
		var code: int = result.get("_status_code", 0)
		if code != 200 and code != 204:
			push_warning("CorporationManager: leave failed (HTTP %d) — %s" % [code, result.get("error", "unknown")])
			return false

	player_member = null
	corporation_data = null
	members.clear()
	diplomacy.clear()
	activity_log.clear()
	transactions.clear()
	corporation_loaded.emit()
	return true


func invite_member(id: String, dname: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_INVITE) or not AuthManager.is_authenticated:
		return false
	if members.size() >= corporation_data.max_members:
		return false

	var body := {"player_id": id}
	var result := await ApiClient.post_async("/api/v1/corporations/%s/members" % corporation_data.corporation_id, body)
	if result.get("_status_code", 0) != 201:
		push_warning("CorporationManager: invite failed — %s" % result.get("error", "unknown"))
		return false

	var m := CorporationMember.new()
	m.player_id = id
	m.display_name = dname
	m.rank_index = corporation_data.ranks.size() - 1
	m.join_timestamp = int(Time.get_unix_time_from_system())
	m.last_online_timestamp = m.join_timestamp
	m.is_online = true
	members.append(m)
	_log_activity(CorporationActivity.EventType.JOIN, dname, "", "A rejoint la corporation")
	member_joined.emit(m)
	return true


func kick_member(id: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_KICK) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m == player_member:
		return false
	if player_member and m.rank_index <= player_member.rank_index:
		return false

	var result := await ApiClient.delete_async("/api/v1/corporations/%s/members/%s" % [corporation_data.corporation_id, id])
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: kick failed — %s" % result.get("error", "unknown"))
		return false

	_log_activity(CorporationActivity.EventType.KICK, player_member.display_name, m.display_name, "A expulse %s" % m.display_name)
	members.erase(m)
	member_kicked.emit(m)
	return true


func promote_member(id: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_PROMOTE) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index <= 0:
		return false
	if player_member and m.rank_index - 1 <= player_member.rank_index:
		return false

	var new_rank_idx: int = m.rank_index - 1
	var new_priority: int = corporation_data.ranks[new_rank_idx].priority if new_rank_idx < corporation_data.ranks.size() else 0
	var result := await ApiClient.put_async("/api/v1/corporations/%s/members/%s/rank" % [corporation_data.corporation_id, id], {"rank_priority": new_priority})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: promote failed — %s" % result.get("error", "unknown"))
		return false

	var old_rank: String = corporation_data.ranks[m.rank_index].rank_name if m.rank_index < corporation_data.ranks.size() else "?"
	m.rank_index = new_rank_idx
	var new_rank: String = corporation_data.ranks[m.rank_index].rank_name if m.rank_index < corporation_data.ranks.size() else "?"
	_log_activity(CorporationActivity.EventType.PROMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_promoted.emit(m)
	return true


func demote_member(id: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_DEMOTE) or not AuthManager.is_authenticated:
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index >= corporation_data.ranks.size() - 1:
		return false
	if player_member and m.rank_index <= player_member.rank_index:
		return false

	var new_rank_idx: int = m.rank_index + 1
	var new_priority: int = corporation_data.ranks[new_rank_idx].priority if new_rank_idx < corporation_data.ranks.size() else 0
	var result := await ApiClient.put_async("/api/v1/corporations/%s/members/%s/rank" % [corporation_data.corporation_id, id], {"rank_priority": new_priority})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: demote failed — %s" % result.get("error", "unknown"))
		return false

	var old_rank: String = corporation_data.ranks[m.rank_index].rank_name if m.rank_index < corporation_data.ranks.size() else "?"
	m.rank_index = new_rank_idx
	var new_rank: String = corporation_data.ranks[m.rank_index].rank_name if m.rank_index < corporation_data.ranks.size() else "?"
	_log_activity(CorporationActivity.EventType.DEMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_demoted.emit(m)
	return true


func set_motd(text: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_EDIT_MOTD) or not AuthManager.is_authenticated:
		return false

	var result := await ApiClient.put_async("/api/v1/corporations/%s" % corporation_data.corporation_id, {"motd": text})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: set_motd failed — %s" % result.get("error", "unknown"))
		return false

	corporation_data.motd = text
	_log_activity(CorporationActivity.EventType.MOTD_CHANGE, player_member.display_name, "", "MOTD mis a jour")
	motd_changed.emit(text)
	return true


func deposit_funds(amount: float) -> bool:
	if amount <= 0 or not has_corporation() or not AuthManager.is_authenticated:
		return false

	var result := await ApiClient.post_async("/api/v1/corporations/%s/treasury/deposit" % corporation_data.corporation_id, {"amount": int(amount)})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: deposit failed — %s" % result.get("error", "unknown"))
		return false
	corporation_data.treasury_balance = float(result.get("treasury", corporation_data.treasury_balance + amount))

	if player_member:
		player_member.contribution_total += amount
	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Depot", "amount": amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(CorporationActivity.EventType.DEPOSIT, player_member.display_name if player_member else "?", "", "Depot de %s credits" % _format_number(amount))
	treasury_changed.emit(corporation_data.treasury_balance)
	return true


func withdraw_funds(amount: float) -> bool:
	if amount <= 0 or not player_has_permission(CorporationRank.PERM_WITHDRAW) or not AuthManager.is_authenticated:
		return false
	if amount > corporation_data.treasury_balance:
		return false

	var result := await ApiClient.post_async("/api/v1/corporations/%s/treasury/withdraw" % corporation_data.corporation_id, {"amount": int(amount)})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: withdraw failed — %s" % result.get("error", "unknown"))
		return false
	corporation_data.treasury_balance = float(result.get("treasury", corporation_data.treasury_balance - amount))

	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Retrait", "amount": -amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(CorporationActivity.EventType.WITHDRAW, player_member.display_name if player_member else "?", "", "Retrait de %s credits" % _format_number(amount))
	treasury_changed.emit(corporation_data.treasury_balance)
	return true


func set_diplomacy_relation(target_corporation_id: String, relation: String) -> bool:
	if not player_has_permission(CorporationRank.PERM_DIPLOMACY) or not AuthManager.is_authenticated:
		return false
	if not diplomacy.has(target_corporation_id):
		return false

	var result := await ApiClient.put_async("/api/v1/corporations/%s/diplomacy" % corporation_data.corporation_id, {"target_corporation_id": target_corporation_id, "relation": relation})
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: set_diplomacy failed — %s" % result.get("error", "unknown"))
		return false

	var old_rel: String = diplomacy[target_corporation_id].get("relation", "NEUTRE")
	diplomacy[target_corporation_id]["relation"] = relation
	diplomacy[target_corporation_id]["since"] = int(Time.get_unix_time_from_system())
	var cname: String = diplomacy[target_corporation_id].get("name", target_corporation_id)
	_log_activity(CorporationActivity.EventType.DIPLOMACY, player_member.display_name if player_member else "?", cname, "%s: %s -> %s" % [cname, old_rel, relation])
	diplomacy_changed.emit(target_corporation_id, relation)
	return true


func toggle_recruitment() -> void:
	if not has_corporation():
		return
	corporation_data.is_recruiting = not corporation_data.is_recruiting
	if AuthManager.is_authenticated and corporation_data.corporation_id != "":
		ApiClient.put_async("/api/v1/corporations/%s" % corporation_data.corporation_id, {"is_recruiting": corporation_data.is_recruiting})
	recruitment_toggled.emit(corporation_data.is_recruiting)


func update_rank(index: int, rname: String, perms: int) -> bool:
	if not player_has_permission(CorporationRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false
	if index < 0 or index >= corporation_data.ranks.size() or index == 0:
		return false

	if corporation_data.ranks[index].db_id >= 0:
		var body := {"rank_name": rname, "permissions": perms}
		var result := await ApiClient.put_async(
			"/api/v1/corporations/%s/ranks/%d" % [corporation_data.corporation_id, corporation_data.ranks[index].db_id], body)
		if result.get("_status_code", 0) != 200:
			push_warning("CorporationManager: update_rank failed — %s" % result.get("error", "unknown"))
			return false

	corporation_data.ranks[index].rank_name = rname
	corporation_data.ranks[index].permissions = perms
	_log_activity(CorporationActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Rang modifie: %s" % rname)
	rank_updated.emit(index)
	return true


func add_rank(rname: String, perms: int) -> bool:
	if not player_has_permission(CorporationRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false

	var new_priority: int = 0
	if not corporation_data.ranks.is_empty():
		var min_p: int = corporation_data.ranks[0].priority
		for r in corporation_data.ranks:
			if r.priority < min_p:
				min_p = r.priority
		new_priority = maxi(min_p - 1, 0)
		if min_p == 0:
			new_priority = 0
			for r in corporation_data.ranks:
				r.priority += 1

	var r := CorporationRank.new()
	r.rank_name = rname
	r.priority = new_priority
	r.permissions = perms

	var body := {"rank_name": rname, "priority": new_priority, "permissions": perms}
	var result := await ApiClient.post_async("/api/v1/corporations/%s/ranks" % corporation_data.corporation_id, body)
	if result.get("_status_code", 0) != 201:
		push_warning("CorporationManager: add_rank failed — %s" % result.get("error", "unknown"))
		return false
	r.db_id = int(result.get("id", -1))

	corporation_data.ranks.append(r)
	_log_activity(CorporationActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Nouveau rang: %s" % rname)
	rank_updated.emit(corporation_data.ranks.size() - 1)
	return true


func remove_rank(index: int) -> bool:
	if not player_has_permission(CorporationRank.PERM_MANAGE_RANKS) or not AuthManager.is_authenticated:
		return false
	if index <= 0 or index >= corporation_data.ranks.size():
		return false

	if corporation_data.ranks[index].db_id >= 0:
		var result := await ApiClient.delete_async(
			"/api/v1/corporations/%s/ranks/%d" % [corporation_data.corporation_id, corporation_data.ranks[index].db_id])
		var code: int = result.get("_status_code", 0)
		if code != 200 and code != 204:
			push_warning("CorporationManager: remove_rank failed — %s" % result.get("error", "unknown"))
			return false

	for m in members:
		if m.rank_index == index:
			m.rank_index = mini(index, corporation_data.ranks.size() - 2)
		elif m.rank_index > index:
			m.rank_index -= 1
	var rname: String = corporation_data.ranks[index].rank_name
	corporation_data.ranks.remove_at(index)
	_log_activity(CorporationActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Rang supprime: %s" % rname)
	rank_updated.emit(-1)
	return true


func refresh_from_backend() -> void:
	if not AuthManager.is_authenticated:
		return
	if has_corporation():
		await _load_corporation_from_api(corporation_data.corporation_id)
	else:
		await _load_from_backend()


func search_corporations(query: String) -> Array:
	if not AuthManager.is_authenticated:
		return []

	var result := await ApiClient.get_async("/api/v1/corporations/search?q=%s" % query.uri_encode())
	if result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: search failed — %s" % result.get("error", "unknown"))
		return []

	var corps: Array = []
	var arr: Array = _extract_array(result, "corporations")
	for c in arr:
		if c is Dictionary:
			corps.append({
				"id": str(c.get("id", "")),
				"name": str(c.get("corporation_name", "")),
				"tag": str(c.get("corporation_tag", "")),
				"members": int(c.get("member_count", 0)),
				"is_recruiting": bool(c.get("is_recruiting", false)),
			})
	return corps


func join_corporation(cid: String) -> bool:
	if has_corporation() or not AuthManager.is_authenticated:
		return false

	var body := {"player_id": AuthManager.player_id}
	var result := await ApiClient.post_async("/api/v1/corporations/%s/members" % cid, body)
	if result.get("_status_code", 0) != 201:
		push_warning("CorporationManager: join failed — %s" % result.get("error", "unknown"))
		return false
	await _load_corporation_from_api(cid)
	return has_corporation()


# =============================================================================
# BACKEND LOADING
# =============================================================================

func _load_from_backend() -> void:
	if _loading:
		return
	_loading = true

	var profile := await ApiClient.get_async("/api/v1/player/profile/%s" % AuthManager.player_id)
	var pid_corp_id: String = ""
	if profile.get("_status_code", 0) == 200:
		pid_corp_id = str(profile.get("corporation_id", ""))

	if pid_corp_id == "" or pid_corp_id == "<null>" or pid_corp_id == "null":
		_loading = false
		corporation_data = null
		corporation_loaded.emit()
		return

	await _load_corporation_from_api(pid_corp_id)
	_loading = false


func _load_corporation_from_api(cid: String) -> void:
	var corp_result := await ApiClient.get_async("/api/v1/corporations/%s" % cid)
	if corp_result.get("_status_code", 0) != 200:
		push_warning("CorporationManager: Failed to load %s — %s" % [cid, corp_result.get("error", "?")])
		corporation_data = null
		corporation_loaded.emit()
		return

	corporation_data = CorporationData.new()
	corporation_data.corporation_id = str(corp_result.get("id", cid))
	corporation_data.corporation_name = str(corp_result.get("corporation_name", ""))
	corporation_data.corporation_tag = str(corp_result.get("corporation_tag", ""))
	corporation_data.description = str(corp_result.get("description", ""))
	corporation_data.motto = str(corp_result.get("motto", ""))
	corporation_data.motd = str(corp_result.get("motd", ""))
	corporation_data.emblem_id = int(corp_result.get("emblem_id", 0))
	corporation_data.treasury_balance = float(corp_result.get("treasury", 0))
	corporation_data.reputation_score = int(corp_result.get("reputation", 0))
	corporation_data.max_members = int(corp_result.get("max_members", 50))
	corporation_data.is_recruiting = bool(corp_result.get("is_recruiting", true))

	var color_str: String = str(corp_result.get("corporation_color", "0.15,0.85,1.0,1.0"))
	var color_parts := color_str.split(",")
	if color_parts.size() >= 3:
		corporation_data.corporation_color = Color(
			color_parts[0].to_float(),
			color_parts[1].to_float(),
			color_parts[2].to_float(),
			color_parts[3].to_float() if color_parts.size() >= 4 else 1.0,
		)

	var created_str: String = str(corp_result.get("created_at", ""))
	if created_str != "":
		corporation_data.creation_timestamp = _parse_iso_timestamp(created_str)

	# Ranks
	corporation_data.ranks.clear()
	var ranks_result := await ApiClient.get_async("/api/v1/corporations/%s/ranks" % cid)
	if ranks_result.get("_status_code", 0) == 200:
		var ranks_arr: Array = _extract_array(ranks_result, "ranks")
		ranks_arr.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		for rd in ranks_arr:
			if not rd is Dictionary:
				continue
			var r := CorporationRank.new()
			r.db_id = int(rd.get("id", -1))
			r.rank_name = str(rd.get("rank_name", ""))
			r.priority = int(rd.get("priority", 0))
			r.permissions = int(rd.get("permissions", 0))
			corporation_data.ranks.append(r)

	if corporation_data.ranks.is_empty():
		var leader := CorporationRank.new()
		leader.rank_name = "Directeur"
		leader.priority = 4
		leader.permissions = CorporationRank.ALL_PERMISSIONS
		corporation_data.ranks.append(leader)
		var recruit := CorporationRank.new()
		recruit.rank_name = "Recrue"
		recruit.priority = 0
		recruit.permissions = 0
		corporation_data.ranks.append(recruit)

	# Members
	members.clear()
	player_member = null
	var members_result := await ApiClient.get_async("/api/v1/corporations/%s/members" % cid)
	if members_result.get("_status_code", 0) == 200:
		var members_arr: Array = _extract_array(members_result, "members")
		for md in members_arr:
			if not md is Dictionary:
				continue
			var m := CorporationMember.new()
			m.player_id = str(md.get("player_id", ""))
			m.display_name = str(md.get("username", ""))
			m.contribution_total = float(md.get("contribution", 0))
			m.is_online = bool(md.get("is_online", false))
			var member_priority: int = int(md.get("rank_priority", 0))
			m.rank_index = corporation_data.ranks.size() - 1
			for ri in corporation_data.ranks.size():
				if corporation_data.ranks[ri].priority == member_priority:
					m.rank_index = ri
					break
			var joined_str: String = str(md.get("joined_at", ""))
			if joined_str != "":
				m.join_timestamp = _parse_iso_timestamp(joined_str)
			m.last_online_timestamp = m.join_timestamp
			members.append(m)
			if m.player_id == AuthManager.player_id:
				player_member = m

	# Diplomacy
	diplomacy.clear()
	var diplo_result := await ApiClient.get_async("/api/v1/corporations/%s/diplomacy" % cid)
	if diplo_result.get("_status_code", 0) == 200:
		var diplo_arr: Array = _extract_array(diplo_result, "diplomacy")
		for dd in diplo_arr:
			if not dd is Dictionary:
				continue
			var target_id: String = str(dd.get("target_corporation_id", ""))
			if target_id == "":
				continue
			var since_str: String = str(dd.get("since", ""))
			diplomacy[target_id] = {
				"name": str(dd.get("target_name", target_id)),
				"tag": str(dd.get("target_tag", "")),
				"relation": str(dd.get("relation", "NEUTRE")).to_upper(),
				"since": _parse_iso_timestamp(since_str) if since_str != "" else 0,
			}

	# Activity
	activity_log.clear()
	var activity_result := await ApiClient.get_async("/api/v1/corporations/%s/activity?limit=50" % cid)
	if activity_result.get("_status_code", 0) == 200:
		var act_arr: Array = _extract_array(activity_result, "activity")
		for ad in act_arr:
			if not ad is Dictionary:
				continue
			var a := CorporationActivity.new()
			a.event_type = int(ad.get("event_type", 0)) as CorporationActivity.EventType
			a.actor_name = str(ad.get("actor_name", ""))
			a.target_name = str(ad.get("target_name", ""))
			a.details = str(ad.get("details", ""))
			var ts_str: String = str(ad.get("created_at", ""))
			a.timestamp = _parse_iso_timestamp(ts_str) if ts_str != "" else 0
			activity_log.append(a)

	print("CorporationManager: Loaded '%s' [%s] — %d members, %d diplo, %d activities" % [
		corporation_data.corporation_name, corporation_data.corporation_tag, members.size(), diplomacy.size(), activity_log.size()])
	corporation_loaded.emit()


# =============================================================================
# HELPERS
# =============================================================================

func _extract_array(result: Dictionary, preferred_key: String = "") -> Array:
	if preferred_key != "" and result.has(preferred_key) and result[preferred_key] is Array:
		return result[preferred_key]
	if result.has("data") and result["data"] is Array:
		return result["data"]
	for key in result:
		if key != "_status_code" and result[key] is Array:
			return result[key]
	return []


func _log_activity(etype: CorporationActivity.EventType, actor: String, target: String, detail: String) -> void:
	var entry := CorporationActivity.new()
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


func _parse_iso_timestamp(iso: String) -> int:
	if iso.is_empty():
		return 0
	var clean := iso.replace("Z", "").replace("+00:00", "")
	if "T" in clean:
		var parts := clean.split("T")
		if parts.size() == 2:
			var date_parts := parts[0].split("-")
			var time_str := parts[1].split(".")[0]
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
