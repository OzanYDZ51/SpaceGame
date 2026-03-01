class_name NpcCombatValidator
extends RefCounted

# =============================================================================
# NPC Combat Validator - Hit validation, kill processing, loot drops.
# Extracted from NpcAuthority. Runs as a RefCounted sub-object.
# =============================================================================

const HIT_VALIDATION_RANGE: float = Constants.NPC_HIT_VALIDATION_RANGE
const HIT_DAMAGE_TOLERANCE: float = Constants.NPC_HIT_DAMAGE_TOLERANCE

# Effective HP cache: ship_id -> { "shield_total": float, "hull_total": float }
var _effective_hp_cache: Dictionary = {}

# Last player to deal damage: npc_id -> { "pid": int, "time": float (ticks_sec) }
var _last_player_hit: Dictionary = {}

var _auth: NpcAuthority = null


func setup(auth: NpcAuthority) -> void:
	_auth = auth


## Compute effective shield+hull totals for a ship with best-in-slot equipment.
func get_effective_hp(ship_id: StringName) -> Dictionary:
	if _effective_hp_cache.has(ship_id):
		return _effective_hp_cache[ship_id]

	var sd: ShipData = ShipRegistry.get_ship_data(ship_id)
	if sd == null:
		return {"shield_total": 500.0, "hull_total": 1000.0}

	var shield_slot_int: int = _slot_str_to_int(sd.shield_slot_size)
	var best_shield_hp: float = sd.shield_hp / 4.0
	for sname in ShieldRegistry.get_all_shield_names():
		var s: ShieldResource = ShieldRegistry.get_shield(sname)
		if s and s.slot_size <= shield_slot_int and s.shield_hp_per_facing > best_shield_hp:
			best_shield_hp = s.shield_hp_per_facing

	var hull_bonus: float = 0.0
	var shield_cap_mult: float = 1.0
	for slot_str in sd.module_slots:
		var slot_int: int = _slot_str_to_int(slot_str)
		var best_mod: ModuleResource = null
		var best_score: float = 0.0
		for mname in ModuleRegistry.get_all_module_names():
			var m: ModuleResource = ModuleRegistry.get_module(mname)
			if m == null or m.slot_size > slot_int:
				continue
			var score: float = m.hull_bonus + (m.shield_cap_mult - 1.0) * 1000.0
			if score > best_score:
				best_score = score
				best_mod = m
		if best_mod:
			hull_bonus += best_mod.hull_bonus
			shield_cap_mult *= best_mod.shield_cap_mult

	var shield_total: float = best_shield_hp * shield_cap_mult * 4.0
	var hull_total: float = sd.hull_hp + hull_bonus
	var result: Dictionary = {"shield_total": shield_total, "hull_total": hull_total}
	_effective_hp_cache[ship_id] = result
	return result


static func _slot_str_to_int(slot: String) -> int:
	match slot:
		"M": return 1
		"L": return 2
		_: return 0


## Resolve a peer_id to a scene Node3D (RemotePlayerShip or local player ship).
func _resolve_player_node(peer_id: int) -> Node3D:
	var sync_mgr = GameManager.get_node_or_null("NetworkSyncManager")
	if sync_mgr and sync_mgr.remote_players.has(peer_id):
		var node = sync_mgr.remote_players[peer_id]
		if is_instance_valid(node):
			return node
	if peer_id == NetworkManager.local_peer_id:
		var player = GameManager.player_ship
		if player and is_instance_valid(player):
			return player
	return null


## Server validates a hit claim from a client.
func validate_hit_claim(sender_pid: int, target_npc: String, weapon_name: String, claimed_damage: float, hit_dir: Array) -> void:
	var npc_id = StringName(target_npc)

	if not _auth._npcs.has(npc_id):
		return

	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id) if lod_mgr else null

	if lod_data == null or lod_data.is_dead:
		return

	# Friendly-fire check: don't let players damage their own fleet NPCs
	if _auth._fleet and _auth._fleet.is_fleet_npc(npc_id):
		if _auth._fleet.get_fleet_npc_owner(npc_id) == sender_pid:
			return

	# Distance check
	var sender_state = NetworkManager.peers.get(sender_pid)
	if sender_state == null:
		return
	var peer_pos = FloatingOrigin.to_local_pos([sender_state.pos_x, sender_state.pos_y, sender_state.pos_z])
	var dist = peer_pos.distance_to(lod_data.position)
	if dist > HIT_VALIDATION_RANGE:
		print("NpcAuthority: Hit rejected — peer %d too far (%.0fm)" % [sender_pid, dist])
		return

	# Damage bounds check
	var weapon = WeaponRegistry.get_weapon(StringName(weapon_name))
	if weapon:
		var expected_dmg: float = weapon.damage_per_hit
		if claimed_damage > expected_dmg * (1.0 + HIT_DAMAGE_TOLERANCE) or claimed_damage < 0.0:
			print("NpcAuthority: Hit rejected — damage %.1f out of bounds for %s" % [claimed_damage, weapon_name])
			return

	# Apply damage on the server's NPC
	var hit_dir_vec = Vector3(hit_dir[0] if hit_dir.size() > 0 else 0.0,
		hit_dir[1] if hit_dir.size() > 1 else 0.0,
		hit_dir[2] if hit_dir.size() > 2 else 0.0)

	var attacker_node: Node3D = _resolve_player_node(sender_pid)
	var shield_absorbed: bool = false

	# Capture death position BEFORE apply_damage — the ship_destroyed signal handler
	# in ShipFactory unregisters LOD data synchronously, so it's gone by the time
	# _on_npc_killed tries to read it.
	var pre_death_pos: Array = FloatingOrigin.to_universe_pos(lod_data.position)

	if is_instance_valid(lod_data.node_ref):
		# Full node exists (LOD0/1) — apply damage via HealthSystem
		var health = lod_data.node_ref.get_node_or_null("HealthSystem")
		if health:
			_auth._npcs[npc_id]["_player_killing"] = true
			var hit_result = health.apply_damage(claimed_damage, &"thermal", hit_dir_vec, attacker_node)
			shield_absorbed = hit_result.get("shield_absorbed", false)
			lod_data.hull_ratio = health.get_hull_ratio()
			lod_data.shield_ratio = health.get_total_shield_ratio()
			_last_player_hit[npc_id] = { "pid": sender_pid, "time": Time.get_ticks_msec() / 1000.0 }
			if health.is_dead():
				lod_data.is_dead = true
				_on_npc_killed(npc_id, sender_pid, weapon_name, "", pre_death_pos)
			elif _auth._npcs.has(npc_id):
				_auth._npcs[npc_id].erase("_player_killing")
	else:
		# Node LOD-demoted (LOD2/3) — apply damage via lod_data ratios directly
		var info: Dictionary = _auth._npcs[npc_id]
		var hp: Dictionary = get_effective_hp(StringName(info.get("ship_id", "")))
		var shield_hp: float = lod_data.shield_ratio * hp["shield_total"]
		var remaining_dmg: float = claimed_damage
		if shield_hp > 0.0:
			var absorbed: float = minf(remaining_dmg, shield_hp)
			shield_hp -= absorbed
			remaining_dmg -= absorbed
			shield_absorbed = true
			lod_data.shield_ratio = shield_hp / maxf(hp["shield_total"], 1.0)
		if remaining_dmg > 0.0:
			var hull_hp: float = lod_data.hull_ratio * hp["hull_total"]
			hull_hp -= remaining_dmg
			lod_data.hull_ratio = maxf(hull_hp / maxf(hp["hull_total"], 1.0), 0.0)
		_last_player_hit[npc_id] = { "pid": sender_pid, "time": Time.get_ticks_msec() / 1000.0 }
		if lod_data.hull_ratio <= 0.0:
			lod_data.is_dead = true
			_on_npc_killed(npc_id, sender_pid, weapon_name, "", pre_death_pos)

	# Broadcast hit effect
	_auth._broadcaster.broadcast_hit_effect(target_npc, sender_pid, hit_dir, shield_absorbed, sender_state.system_id)


func _on_npc_killed(npc_id: StringName, killer_pid: int, weapon_name: String = "", killer_npc_id: String = "", cached_death_pos: Array = []) -> void:
	if not _auth._npcs.has(npc_id):
		return

	var info: Dictionary = _auth._npcs[npc_id]
	var system_id: int = info.get("system_id", -1)

	# Get death position (use cached if provided — LOD data may already be gone)
	var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
	var death_pos: Array = cached_death_pos if cached_death_pos.size() >= 3 else [0.0, 0.0, 0.0]
	if death_pos == [0.0, 0.0, 0.0] and lod_mgr:
		var lod_data: ShipLODData = lod_mgr.get_ship_data(npc_id)
		if lod_data:
			death_pos = FloatingOrigin.to_universe_pos(lod_data.position)

	# Roll loot
	var ship_data = ShipRegistry.get_ship_data(StringName(info.get("ship_id", "")))
	var loot: Array = []
	if ship_data:
		loot = LootTable.roll_drops_for_ship(ship_data)

	# Add fleet ship cargo to loot
	if _auth._fleet.is_fleet_npc(npc_id):
		var fleet_info: Dictionary = _auth._fleet._fleet_npcs[npc_id]
		for item in fleet_info.get("cargo", []):
			var item_type: String = str(item.get("item_type", ""))
			var qty: int = int(item.get("quantity", 1))
			if qty > 0:
				loot.append({
					"name": str(item.get("item_name", item_type)),
					"type": item_type,
					"quantity": qty,
					"icon_color": LootTable.TYPE_COLORS.get(item_type, Color.WHITE),
				})
		for res_id in fleet_info.get("ship_resources", {}):
			var qty: int = int(fleet_info["ship_resources"][res_id])
			if qty > 0:
				var res_str: String = String(res_id)
				loot.append({
					"name": res_str.replace("_", " ").capitalize(),
					"type": res_str,
					"quantity": qty,
					"icon_color": LootTable.TYPE_COLORS.get(res_str, Color.WHITE),
				})

	# Report kill to Discord
	var victim_faction: StringName = StringName(info.get("faction", ""))
	_report_kill_event(killer_pid, ship_data, victim_faction, weapon_name, system_id, killer_npc_id)

	# Record encounter NPC death for respawn tracking (escalating delay anti-farm)
	var encounter_key: String = info.get("encounter_key", "")
	if encounter_key != "":
		var prev: Dictionary = _auth._destroyed_encounter_npcs.get(encounter_key, {})
		var kills: int = prev.get("kills", 0) + 1
		var delay: float = minf(_auth.ENCOUNTER_RESPAWN_DELAY * kills, _auth.ENCOUNTER_RESPAWN_MAX_DELAY)
		_auth._destroyed_encounter_npcs[encounter_key] = {
			"time": Time.get_unix_time_from_system() + delay,
			"kills": kills,
		}

	# Broadcast death
	_broadcast_npc_death(npc_id, killer_pid, death_pos, loot, system_id)

	# Notify local systems
	_auth.npc_killed.emit(npc_id, killer_pid)

	# Unregister
	_auth.unregister_npc(npc_id)
	if lod_mgr:
		lod_mgr.unregister_ship(npc_id)


func _report_kill_event(killer_pid: int, ship_data: ShipData, victim_faction: StringName, weapon_name: String, system_id: int, killer_npc_id: String = "") -> void:
	var reporter = GameManager.get_node_or_null("EventReporter")
	if reporter == null:
		return

	# --- Killer name ---
	var killer_name: String = ""
	if killer_pid > 0 and NetworkManager.peers.has(killer_pid):
		killer_name = NetworkManager.peers[killer_pid].player_name
	elif killer_npc_id != "":
		# NPC killer — build name from faction + ship type
		killer_name = _build_npc_display_name(StringName(killer_npc_id))
	if killer_name == "":
		killer_name = "NPC inconnu"

	# --- Victim name ---
	var victim_name: String = _build_npc_display_name_from_data(ship_data, victim_faction)

	# --- Weapon ---
	var weapon_display: String = weapon_name
	if weapon_name != "":
		var w = WeaponRegistry.get_weapon(StringName(weapon_name))
		if w:
			weapon_display = String(w.weapon_name) if w.weapon_name != &"" else weapon_name

	# --- System ---
	var system_name: String = "Inconnu"
	if GameManager._galaxy:
		system_name = GameManager._galaxy.get_system_name(system_id)

	print("[NpcAuthority] Kill: %s -> %s (%s) in %s" % [killer_name, victim_name, weapon_display, system_name])
	reporter.report_kill(killer_name, victim_name, weapon_display, system_name, system_id)


## Build a display name for an NPC from its registered info: "Faction (ShipType)"
func _build_npc_display_name(npc_id: StringName) -> String:
	if not _auth._npcs.has(npc_id):
		return "NPC"
	var info: Dictionary = _auth._npcs[npc_id]
	var sd: ShipData = ShipRegistry.get_ship_data(StringName(info.get("ship_id", "")))
	var faction_id: StringName = StringName(info.get("faction", ""))
	return _build_npc_display_name_from_data(sd, faction_id)


func _build_npc_display_name_from_data(sd: ShipData, faction_id) -> String:
	var ship_type: String = String(sd.ship_name) if sd else "NPC"

	var faction_label: String = ""
	if faction_id != null and faction_id != &"" and faction_id != &"neutral":
		var fm = GameManager.get_node_or_null("GameplayIntegrator")
		if fm:
			var faction_mgr = fm.get_node_or_null("FactionManager")
			if faction_mgr:
				var fres = faction_mgr.get_faction(faction_id)
				if fres:
					faction_label = fres.faction_name

	if faction_label != "":
		return "%s (%s)" % [faction_label, ship_type]
	return ship_type


func _broadcast_npc_death(npc_id: StringName, killer_pid: int, death_pos: Array, loot: Array, system_id: int = -1) -> void:
	if system_id < 0 and _auth._npcs.has(npc_id):
		system_id = _auth._npcs[npc_id].get("system_id", -1)

	# Attribute kill to last player who dealt damage (30s window) if AI delivered killing blow
	var effective_killer_pid: int = killer_pid
	if effective_killer_pid == 0 and _last_player_hit.has(npc_id):
		var last_hit: Dictionary = _last_player_hit[npc_id]
		if Time.get_ticks_msec() / 1000.0 - last_hit.get("time", 0.0) < 30.0:
			effective_killer_pid = last_hit.get("pid", 0)
	_last_player_hit.erase(npc_id)

	var peers_in_sys = NetworkManager.get_peers_in_system(system_id)
	for pid in peers_in_sys:
		NetworkManager._rpc_npc_died.rpc_id(pid, String(npc_id), effective_killer_pid, death_pos, loot)

	# Handle fleet NPC death tracking
	_auth._fleet.on_fleet_npc_killed(npc_id)


## Clean up stale last-hit entries older than 60 seconds.
func cleanup_stale_hits() -> void:
	var now_ticks: float = Time.get_ticks_msec() / 1000.0
	var stale_hits: Array = []
	for npc_id in _last_player_hit:
		if now_ticks - _last_player_hit[npc_id].get("time", 0.0) > 60.0:
			stale_hits.append(npc_id)
	for npc_id in stale_hits:
		_last_player_hit.erase(npc_id)
