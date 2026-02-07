class_name ClanManager
extends Node

# =============================================================================
# Clan Manager - Runtime API for clan state, signals, and mock data
# Multiplayer-ready: all mutations go through methods that emit signals.
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


func _ready() -> void:
	_generate_mock_data()


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
	if has_clan():
		return false
	clan_data = ClanData.new()
	clan_data.clan_id = "clan_" + str(randi())
	clan_data.clan_name = cname
	clan_data.clan_tag = tag
	clan_data.clan_color = color
	clan_data.emblem_id = emblem
	clan_data.creation_timestamp = int(Time.get_unix_time_from_system())
	# Default ranks
	var leader := ClanRank.new()
	leader.rank_name = "Chef"
	leader.priority = 0
	leader.permissions = ClanRank.ALL_PERMISSIONS
	clan_data.ranks.append(leader)
	var recruit := ClanRank.new()
	recruit.rank_name = "Recrue"
	recruit.priority = 1
	recruit.permissions = 0
	clan_data.ranks.append(recruit)
	_log_activity(ClanActivity.EventType.CREATED, "Systeme", "", "Clan cree: %s [%s]" % [cname, tag])
	clan_loaded.emit()
	return true


func leave_clan() -> void:
	if not has_clan() or player_member == null:
		return
	_log_activity(ClanActivity.EventType.LEAVE, player_member.display_name, "", "A quitte le clan")
	members.erase(player_member)
	player_member = null


func invite_member(id: String, dname: String) -> bool:
	if not player_has_permission(ClanRank.PERM_INVITE):
		return false
	if members.size() >= clan_data.max_members:
		return false
	var m := ClanMember.new()
	m.player_id = id
	m.display_name = dname
	m.rank_index = clan_data.ranks.size() - 1  # lowest rank
	m.join_timestamp = int(Time.get_unix_time_from_system())
	m.last_online_timestamp = m.join_timestamp
	m.is_online = true
	members.append(m)
	_log_activity(ClanActivity.EventType.JOIN, dname, "", "A rejoint le clan")
	member_joined.emit(m)
	return true


func kick_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_KICK):
		return false
	var m := get_member_by_id(id)
	if m == null or m == player_member:
		return false
	# Can't kick someone of equal or higher rank
	if player_member and m.rank_index <= player_member.rank_index:
		return false
	_log_activity(ClanActivity.EventType.KICK, player_member.display_name, m.display_name, "A expulse %s" % m.display_name)
	members.erase(m)
	member_kicked.emit(m)
	return true


func promote_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_PROMOTE):
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index <= 0:
		return false
	# Can't promote to own rank or above
	if player_member and m.rank_index - 1 <= player_member.rank_index:
		return false
	var old_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	m.rank_index -= 1
	var new_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	_log_activity(ClanActivity.EventType.PROMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_promoted.emit(m)
	return true


func demote_member(id: String) -> bool:
	if not player_has_permission(ClanRank.PERM_DEMOTE):
		return false
	var m := get_member_by_id(id)
	if m == null or m.rank_index >= clan_data.ranks.size() - 1:
		return false
	# Can't demote someone of equal or higher rank
	if player_member and m.rank_index <= player_member.rank_index:
		return false
	var old_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	m.rank_index += 1
	var new_rank: String = clan_data.ranks[m.rank_index].rank_name if m.rank_index < clan_data.ranks.size() else "?"
	_log_activity(ClanActivity.EventType.DEMOTE, player_member.display_name, m.display_name, "%s: %s -> %s" % [m.display_name, old_rank, new_rank])
	member_demoted.emit(m)
	return true


func set_motd(text: String) -> bool:
	if not player_has_permission(ClanRank.PERM_EDIT_MOTD):
		return false
	clan_data.motd = text
	_log_activity(ClanActivity.EventType.MOTD_CHANGE, player_member.display_name, "", "MOTD mis a jour")
	motd_changed.emit(text)
	return true


func deposit_funds(amount: float) -> bool:
	if amount <= 0:
		return false
	clan_data.treasury_balance += amount
	if player_member:
		player_member.contribution_total += amount
	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Depot", "amount": amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(ClanActivity.EventType.DEPOSIT, player_member.display_name if player_member else "?", "", "Depot de %s credits" % _format_number(amount))
	treasury_changed.emit(clan_data.treasury_balance)
	return true


func withdraw_funds(amount: float) -> bool:
	if amount <= 0 or not player_has_permission(ClanRank.PERM_WITHDRAW):
		return false
	if amount > clan_data.treasury_balance:
		return false
	clan_data.treasury_balance -= amount
	var t := { "timestamp": int(Time.get_unix_time_from_system()), "type": "Retrait", "amount": -amount, "actor": player_member.display_name if player_member else "?" }
	transactions.append(t)
	_log_activity(ClanActivity.EventType.WITHDRAW, player_member.display_name if player_member else "?", "", "Retrait de %s credits" % _format_number(amount))
	treasury_changed.emit(clan_data.treasury_balance)
	return true


func set_diplomacy_relation(target_clan_id: String, relation: String) -> bool:
	if not player_has_permission(ClanRank.PERM_DIPLOMACY):
		return false
	if not diplomacy.has(target_clan_id):
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
	recruitment_toggled.emit(clan_data.is_recruiting)


func update_rank(index: int, rname: String, perms: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS):
		return false
	if index < 0 or index >= clan_data.ranks.size() or index == 0:
		return false
	clan_data.ranks[index].rank_name = rname
	clan_data.ranks[index].permissions = perms
	_log_activity(ClanActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Rang modifie: %s" % rname)
	rank_updated.emit(index)
	return true


func add_rank(rname: String, perms: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS):
		return false
	var r := ClanRank.new()
	r.rank_name = rname
	r.priority = clan_data.ranks.size()
	r.permissions = perms
	clan_data.ranks.append(r)
	_log_activity(ClanActivity.EventType.RANK_CHANGE, player_member.display_name if player_member else "?", "", "Nouveau rang: %s" % rname)
	rank_updated.emit(clan_data.ranks.size() - 1)
	return true


func remove_rank(index: int) -> bool:
	if not player_has_permission(ClanRank.PERM_MANAGE_RANKS):
		return false
	if index <= 0 or index >= clan_data.ranks.size():
		return false
	# Move members on this rank to the next lower rank
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


# =============================================================================
# HELPERS
# =============================================================================

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


# =============================================================================
# MOCK DATA
# =============================================================================

func _generate_mock_data() -> void:
	var now := int(Time.get_unix_time_from_system())

	# Clan identity
	clan_data = ClanData.new()
	clan_data.clan_id = "clan_void_reapers"
	clan_data.clan_name = "Void Reapers"
	clan_data.clan_tag = "VR"
	clan_data.description = "Un clan de pilotes d'elite specialises dans les operations de frappe rapide et la reconnaissance en territoire hostile."
	clan_data.motto = "Per aspera ad astra"
	clan_data.motd = "Operation Tempete Noire ce soir 21h. Tous les pilotes de rang Veteran+ sont convoques au point de ralliement secteur BC-7."
	clan_data.clan_color = Color(0.15, 0.85, 1.0)
	clan_data.emblem_id = 7
	clan_data.creation_timestamp = now - 86400 * 30
	clan_data.treasury_balance = 125000.0
	clan_data.reputation_score = 2450
	clan_data.is_recruiting = true

	# 5 ranks
	var r_chef := ClanRank.new()
	r_chef.rank_name = "Chef"
	r_chef.priority = 0
	r_chef.permissions = ClanRank.ALL_PERMISSIONS
	clan_data.ranks.append(r_chef)

	var r_admiral := ClanRank.new()
	r_admiral.rank_name = "Admiral"
	r_admiral.priority = 1
	r_admiral.permissions = ClanRank.PERM_INVITE | ClanRank.PERM_KICK | ClanRank.PERM_PROMOTE | ClanRank.PERM_DEMOTE | ClanRank.PERM_EDIT_MOTD | ClanRank.PERM_DIPLOMACY
	clan_data.ranks.append(r_admiral)

	var r_officier := ClanRank.new()
	r_officier.rank_name = "Officier"
	r_officier.priority = 2
	r_officier.permissions = ClanRank.PERM_INVITE | ClanRank.PERM_KICK | ClanRank.PERM_EDIT_MOTD
	clan_data.ranks.append(r_officier)

	var r_veteran := ClanRank.new()
	r_veteran.rank_name = "Veteran"
	r_veteran.priority = 3
	r_veteran.permissions = ClanRank.PERM_INVITE
	clan_data.ranks.append(r_veteran)

	var r_recrue := ClanRank.new()
	r_recrue.rank_name = "Recrue"
	r_recrue.priority = 4
	r_recrue.permissions = 0
	clan_data.ranks.append(r_recrue)

	# 15 members
	var member_defs := [
		["p_starpilot", "StarPilot_X", 0, true, 52000.0, 412, 98],
		["p_voidcmdr", "VoidCmdr", 1, true, 45200.0, 324, 87],
		["p_novahunter", "NovaHunter", 2, true, 32100.0, 287, 102],
		["p_shadowfleet", "ShadowFleet", 2, true, 28500.0, 198, 76],
		["p_ironviper", "IronViper", 2, true, 21300.0, 245, 89],
		["p_cosmicdust", "CosmicDust", 3, true, 18700.0, 156, 64],
		["p_astroknight", "AstroKnight", 3, true, 15800.0, 178, 71],
		["p_nebulafox", "NebulaFox", 3, false, 12400.0, 134, 58],
		["p_ghostrider", "GhostRider77", 3, false, 9800.0, 112, 45],
		["p_zerograv", "ZeroGrav", 4, true, 6200.0, 67, 34],
		["p_darkmatter", "DarkMatter99", 4, false, 4100.0, 45, 28],
		["p_pulsarace", "PulsarAce", 4, true, 3500.0, 38, 22],
		["p_orionblade", "OrionBlade", 4, false, 2800.0, 29, 19],
		["p_warpdrive", "WarpDriveX", 4, false, 1900.0, 18, 15],
		["p_quantumfist", "QuantumFist", 4, false, 800.0, 8, 6],
	]

	for def in member_defs:
		var m := ClanMember.new()
		m.player_id = def[0]
		m.display_name = def[1]
		m.rank_index = def[2]
		m.is_online = def[3]
		m.contribution_total = def[4]
		m.kills = def[5]
		m.deaths = def[6]
		m.join_timestamp = now - randi_range(86400, 86400 * 28)
		m.last_online_timestamp = now - (0 if m.is_online else randi_range(3600, 86400 * 3))
		members.append(m)
		if m.player_id == "p_voidcmdr":
			player_member = m

	# 4 diplomatic relations
	diplomacy = {
		"clan_iron_wolves": { "name": "Iron Wolves", "tag": "IW", "relation": "ALLIE", "since": now - 86400 * 3 },
		"clan_blood_corsairs": { "name": "Blood Corsairs", "tag": "BC", "relation": "ENNEMI", "since": now - 86400 * 7 },
		"clan_crimson_fleet": { "name": "Crimson Fleet", "tag": "CF", "relation": "ENNEMI", "since": now - 86400 * 5 },
		"clan_star_merchants": { "name": "Star Merchants Guild", "tag": "SM", "relation": "NEUTRE", "since": now - 86400 * 14 },
	}

	# 30 activity log entries
	_generate_mock_activities(now)

	# 15 mock transactions
	_generate_mock_transactions(now)

	clan_loaded.emit()


func _generate_mock_activities(now: int) -> void:
	var entries: Array[Dictionary] = [
		{ "t": now - 1800, "type": ClanActivity.EventType.DEPOSIT, "actor": "VoidCmdr", "target": "", "detail": "Depot de 5 000 credits" },
		{ "t": now - 3600, "type": ClanActivity.EventType.PROMOTE, "actor": "VoidCmdr", "target": "NovaHunter", "detail": "NovaHunter: Veteran -> Officier" },
		{ "t": now - 5400, "type": ClanActivity.EventType.JOIN, "actor": "QuantumFist", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 7200, "type": ClanActivity.EventType.KICK, "actor": "StarPilot_X", "target": "DarkMatter99", "detail": "A expulse VoidRunner (inactivite)" },
		{ "t": now - 10800, "type": ClanActivity.EventType.DEPOSIT, "actor": "NovaHunter", "target": "", "detail": "Depot de 3 200 credits" },
		{ "t": now - 14400, "type": ClanActivity.EventType.MOTD_CHANGE, "actor": "VoidCmdr", "target": "", "detail": "MOTD mis a jour" },
		{ "t": now - 18000, "type": ClanActivity.EventType.DIPLOMACY, "actor": "VoidCmdr", "target": "Blood Corsairs", "detail": "Blood Corsairs: NEUTRE -> ENNEMI" },
		{ "t": now - 21600, "type": ClanActivity.EventType.DEPOSIT, "actor": "ShadowFleet", "target": "", "detail": "Depot de 8 000 credits" },
		{ "t": now - 28800, "type": ClanActivity.EventType.PROMOTE, "actor": "StarPilot_X", "target": "IronViper", "detail": "IronViper: Veteran -> Officier" },
		{ "t": now - 36000, "type": ClanActivity.EventType.WITHDRAW, "actor": "StarPilot_X", "target": "", "detail": "Retrait de 2 000 credits" },
		{ "t": now - 43200, "type": ClanActivity.EventType.JOIN, "actor": "WarpDriveX", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 86400, "type": ClanActivity.EventType.DEPOSIT, "actor": "AstroKnight", "target": "", "detail": "Depot de 4 500 credits" },
		{ "t": now - 86400, "type": ClanActivity.EventType.DEMOTE, "actor": "StarPilot_X", "target": "CosmicDust", "detail": "CosmicDust: Officier -> Veteran" },
		{ "t": now - 90000, "type": ClanActivity.EventType.DEPOSIT, "actor": "CosmicDust", "target": "", "detail": "Depot de 2 000 credits" },
		{ "t": now - 100800, "type": ClanActivity.EventType.JOIN, "actor": "OrionBlade", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 129600, "type": ClanActivity.EventType.DIPLOMACY, "actor": "StarPilot_X", "target": "Iron Wolves", "detail": "Iron Wolves: NEUTRE -> ALLIE" },
		{ "t": now - 172800, "type": ClanActivity.EventType.DEPOSIT, "actor": "IronViper", "target": "", "detail": "Depot de 6 000 credits" },
		{ "t": now - 172800, "type": ClanActivity.EventType.WITHDRAW, "actor": "VoidCmdr", "target": "", "detail": "Retrait de 1 500 credits" },
		{ "t": now - 216000, "type": ClanActivity.EventType.JOIN, "actor": "PulsarAce", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 259200, "type": ClanActivity.EventType.PROMOTE, "actor": "StarPilot_X", "target": "ShadowFleet", "detail": "ShadowFleet: Veteran -> Officier" },
		{ "t": now - 259200, "type": ClanActivity.EventType.DEPOSIT, "actor": "NebulaFox", "target": "", "detail": "Depot de 1 800 credits" },
		{ "t": now - 302400, "type": ClanActivity.EventType.KICK, "actor": "VoidCmdr", "target": "PhantomX", "detail": "A expulse PhantomX (trahison)" },
		{ "t": now - 345600, "type": ClanActivity.EventType.DIPLOMACY, "actor": "StarPilot_X", "target": "Crimson Fleet", "detail": "Crimson Fleet: NEUTRE -> ENNEMI" },
		{ "t": now - 345600, "type": ClanActivity.EventType.DEPOSIT, "actor": "GhostRider77", "target": "", "detail": "Depot de 3 000 credits" },
		{ "t": now - 432000, "type": ClanActivity.EventType.JOIN, "actor": "ZeroGrav", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 432000, "type": ClanActivity.EventType.JOIN, "actor": "DarkMatter99", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 518400, "type": ClanActivity.EventType.MOTD_CHANGE, "actor": "StarPilot_X", "target": "", "detail": "MOTD mis a jour" },
		{ "t": now - 518400, "type": ClanActivity.EventType.DEPOSIT, "actor": "StarPilot_X", "target": "", "detail": "Depot de 15 000 credits" },
		{ "t": now - 604800, "type": ClanActivity.EventType.JOIN, "actor": "GhostRider77", "target": "", "detail": "A rejoint le clan" },
		{ "t": now - 604800, "type": ClanActivity.EventType.CREATED, "actor": "StarPilot_X", "target": "", "detail": "Clan cree: Void Reapers [VR]" },
	]

	for e in entries:
		var a := ClanActivity.new()
		a.timestamp = e["t"]
		a.event_type = e["type"]
		a.actor_name = e["actor"]
		a.target_name = e["target"]
		a.details = e["detail"]
		activity_log.append(a)


func _generate_mock_transactions(now: int) -> void:
	transactions = [
		{ "timestamp": now - 1800, "type": "Depot", "amount": 5000.0, "actor": "VoidCmdr" },
		{ "timestamp": now - 10800, "type": "Depot", "amount": 3200.0, "actor": "NovaHunter" },
		{ "timestamp": now - 21600, "type": "Depot", "amount": 8000.0, "actor": "ShadowFleet" },
		{ "timestamp": now - 36000, "type": "Retrait", "amount": -2000.0, "actor": "StarPilot_X" },
		{ "timestamp": now - 86400, "type": "Depot", "amount": 4500.0, "actor": "AstroKnight" },
		{ "timestamp": now - 90000, "type": "Depot", "amount": 2000.0, "actor": "CosmicDust" },
		{ "timestamp": now - 172800, "type": "Depot", "amount": 6000.0, "actor": "IronViper" },
		{ "timestamp": now - 172800, "type": "Retrait", "amount": -1500.0, "actor": "VoidCmdr" },
		{ "timestamp": now - 259200, "type": "Depot", "amount": 1800.0, "actor": "NebulaFox" },
		{ "timestamp": now - 345600, "type": "Depot", "amount": 3000.0, "actor": "GhostRider77" },
		{ "timestamp": now - 432000, "type": "Depot", "amount": 2500.0, "actor": "ZeroGrav" },
		{ "timestamp": now - 432000, "type": "Depot", "amount": 1200.0, "actor": "DarkMatter99" },
		{ "timestamp": now - 518400, "type": "Depot", "amount": 15000.0, "actor": "StarPilot_X" },
		{ "timestamp": now - 518400, "type": "Retrait", "amount": -5000.0, "actor": "StarPilot_X" },
		{ "timestamp": now - 604800, "type": "Depot", "amount": 10000.0, "actor": "StarPilot_X" },
	]
