class_name FleetAIBridge
extends Node

# =============================================================================
# Fleet AI Bridge — Translates fleet commands to AIBrain states
# Attached as child of deployed fleet NPC (sibling of AIBrain/AIPilot)
#
# Navigation uses AIBrain PATROL exclusively (ShipController autopilot is
# player-only and doesn't work for NPCs).
# Fleet ships on mission ignore threats — they fly to destination without
# getting distracted by enemies.
# =============================================================================

var fleet_index: int = -1
var command: StringName = &""
var command_params: Dictionary = {}

var _ship = null
var _brain = null
var _pilot = null
var _station_id: String = ""
var _returning: bool = false
var _arrived: bool = false
var _attack_target_id: String = ""

const MOVE_ARRIVE_DIST: float = 200.0
const STATION_SAFE_MARGIN: float = 500.0  # Keep move targets outside station zones

# --- Dock approach ---
const DOCK_APPROACH_DIST: float = 1200.0   # Switch from patrol to direct flight

## Cached dock target positions (local coords) — refreshed each frame / origin shift
var _bay_approach_pos: Vector3 = Vector3.ZERO  ## Bay exit (above opening, for long-range nav)
var _bay_dock_pos: Vector3 = Vector3.ZERO      ## Landing pad (inside bay, for final approach)
var _bay_target_valid: bool = false

## Bay entry detection — same system as player (station Area3D)
var _in_bay: bool = false
var _bay_station_node: Node3D = null
var _bay_signal_connected: bool = false

var _initialized: bool = false


func _ready() -> void:
	_ship = get_parent()
	# Use call_deferred: runs at end of current frame, after all sibling _ready()
	# and after deploy_ship() has finished setting process_mode.
	# Safer than await (works even if tree was disabled when added).
	call_deferred("_do_init")


func _exit_tree() -> void:
	if _ship and is_instance_valid(_ship):
		_ship.ai_navigation_active = false
		_ship._gate_approach_speed_cap = 0.0
	if FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.disconnect(_on_origin_shifted)
	_disconnect_bay_signals()


func _do_init() -> void:
	if _initialized:
		return
	_initialized = true
	_brain = _ship.get_node_or_null("AIBrain") if _ship else null
	_pilot = _ship.get_node_or_null("AIPilot") if _ship else null

	if _brain:
		# Fleet ships on mission don't react to enemies (no wasted time fighting)
		_brain.ignore_threats = true
		# Check if ship has combat weapons — disable if unarmed
		var wm = _ship.get_node_or_null("WeaponManager") if _ship else null
		var has_weapons: bool = wm != null and wm.has_combat_weapons_in_group(0)
		if not has_weapons:
			_brain.weapons_enabled = false
		apply_command(command, command_params)

	# Correct waypoints when floating origin shifts (local coords become stale)
	if not FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func _resolve_station_dock_targets() -> void:
	## Resolves both approach (bay exit) and final dock (landing pad) positions.
	## Connects bay entry signals if not already connected.
	_bay_target_valid = false
	if _station_id == "":
		return
	var ent: Dictionary = EntityRegistry.get_entity(_station_id)
	if ent.is_empty():
		return
	var station_node = ent.get("node")
	if station_node and is_instance_valid(station_node):
		# Bay exit = approach target (above the bay opening, visible from space)
		if station_node.has_method("get_bay_exit_global"):
			_bay_approach_pos = station_node.get_bay_exit_global()
		else:
			_bay_approach_pos = station_node.global_position
		# Landing pad = final dock target (inside the bay)
		if station_node.has_method("get_landing_pos_global"):
			_bay_dock_pos = station_node.get_landing_pos_global()
		else:
			_bay_dock_pos = _bay_approach_pos
		_bay_target_valid = true
		# Connect bay entry signals (same detection as player DockingSystem)
		_connect_bay_signals(station_node)
	else:
		# No live node — fallback to entity position
		_bay_approach_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
		_bay_dock_pos = _bay_approach_pos
		_bay_target_valid = true


func _refresh_dock_targets() -> void:
	## Re-resolve dock target positions from live station node (handles orbit/rotation).
	if _station_id == "":
		return
	var ent: Dictionary = EntityRegistry.get_entity(_station_id)
	if ent.is_empty():
		return
	var station_node = ent.get("node")
	if station_node and is_instance_valid(station_node):
		if station_node.has_method("get_bay_exit_global"):
			_bay_approach_pos = station_node.get_bay_exit_global()
		if station_node.has_method("get_landing_pos_global"):
			_bay_dock_pos = station_node.get_landing_pos_global()


func _connect_bay_signals(station_node: Node3D) -> void:
	if _bay_signal_connected:
		return
	if not station_node.has_signal("ship_entered_bay"):
		return
	station_node.ship_entered_bay.connect(_on_bay_entered)
	station_node.ship_exited_bay.connect(_on_bay_exited)
	_bay_station_node = station_node
	_bay_signal_connected = true


func _disconnect_bay_signals() -> void:
	if not _bay_signal_connected:
		return
	if _bay_station_node and is_instance_valid(_bay_station_node):
		if _bay_station_node.ship_entered_bay.is_connected(_on_bay_entered):
			_bay_station_node.ship_entered_bay.disconnect(_on_bay_entered)
		if _bay_station_node.ship_exited_bay.is_connected(_on_bay_exited):
			_bay_station_node.ship_exited_bay.disconnect(_on_bay_exited)
	_bay_station_node = null
	_bay_signal_connected = false
	_in_bay = false


func _on_bay_entered(ship: Node3D) -> void:
	if ship == _ship:
		_in_bay = true


func _on_bay_exited(ship: Node3D) -> void:
	if ship == _ship:
		_in_bay = false


func apply_command(cmd: StringName, params: Dictionary = {}) -> void:
	command = cmd
	command_params = params
	_returning = false
	_arrived = false
	_attack_target_id = ""
	if _brain == null:
		if _initialized:
			push_warning("FleetAIBridge[%d]: _brain is null, command ignored!" % fleet_index)
		# Not yet initialized — command stored, will be applied in _do_init()
		return

	# All mission commands: ignore threats, focus on destination
	_brain.ignore_threats = (cmd in [&"move_to", &"patrol", &"return_to_station", &"construction", &"mine"])
	_brain.target = null

	match cmd:
		&"move_to":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos =FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			# Push target outside station exclusion zones
			target_pos = _push_target_outside_stations(target_pos)
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > MOVE_ARRIVE_DIST:
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"patrol":
			var center_x: float = params.get("center_x", 0.0)
			var center_z: float = params.get("center_z", 0.0)
			var radius: float = params.get("radius", 500.0)
			var center_pos =FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			_brain.set_patrol_area(center_pos, radius)
			_brain.current_state = AIBrain.State.PATROL
		&"attack":
			_attack_target_id = params.get("target_entity_id", "")
			if _attack_target_id != "":
				var ent =EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					var target_pos =FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					_brain.set_patrol_area(target_pos, 50.0)
					var target_node = ent.get("node", null) if ent.get("node") else null
					if target_node and is_instance_valid(target_node):
						_brain.target = target_node
						_brain.current_state = AIBrain.State.PURSUE
					else:
						_brain.current_state = AIBrain.State.PATROL
		&"construction":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos =FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			target_pos = _push_target_outside_stations(target_pos)
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > MOVE_ARRIVE_DIST:
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				_mark_arrived(target_pos)
		&"mine":
			var center_x: float = params.get("center_x", 0.0)
			var center_z: float = params.get("center_z", 0.0)
			var target_pos =FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > MOVE_ARRIVE_DIST:
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				_brain.current_state = AIBrain.State.MINING
				_arrived = true
		&"return_to_station":
			_returning = true
			_in_bay = false
			# Preserve existing _station_id (set during deployment) if params don't include one
			var new_station: String = params.get("station_id", "")
			if new_station != "":
				_disconnect_bay_signals()  # Station changed, reconnect later
				_station_id = new_station
			# Fallback: find nearest station if _station_id is empty or can't resolve
			if _station_id == "" or EntityRegistry.get_entity(_station_id).is_empty():
				_station_id = _find_nearest_station_id()
			if _station_id != "":
				_resolve_station_dock_targets()
				if _bay_target_valid:
					_brain.set_patrol_area(_bay_approach_pos, 50.0)
					_brain.current_state = AIBrain.State.PATROL


func _process(_delta: float) -> void:
	if _ship == null:
		return
	# Deferred init: tree was disabled when spawned (player was docked)
	if not _initialized:
		_do_init()
		return
	if _brain == null:
		return

	# --- Navigation speed boost: enable 3km/s approach when far from target ---
	_update_navigation_boost()

	# Monitor return_to_station — fly into the bay like a player
	if _returning and _station_id != "" and _bay_target_valid:
		_refresh_dock_targets()

		# Bay entry detection: ship physically entered the bay Area3D → dock when slow
		if _in_bay:
			var speed: float = _ship.linear_velocity.length()
			if speed < DockingSystem.BAY_DOCK_MAX_SPEED:
				var npc_auth = GameManager.get_node_or_null("NpcAuthority")
				if npc_auth and npc_auth._active:
					npc_auth.handle_fleet_npc_self_docked(StringName(_ship.name), fleet_index)
				return
			# Inside bay but too fast — keep decelerating toward landing pad
			if _brain.current_state != AIBrain.State.IDLE:
				_brain.current_state = AIBrain.State.IDLE
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if _pilot:
				_pilot.fly_toward(_bay_dock_pos, 30.0)
			return

		# Not yet in bay — approach it
		var dist_to_approach: float = _ship.global_position.distance_to(_bay_approach_pos)

		if dist_to_approach < DOCK_APPROACH_DIST:
			# --- FINAL APPROACH: fly directly into the bay (target = landing pad) ---
			if _brain.current_state != AIBrain.State.IDLE:
				_brain.current_state = AIBrain.State.IDLE
			if _ship.speed_mode == Constants.SpeedMode.CRUISE:
				_ship._exit_cruise()
			if _pilot:
				_pilot.fly_toward(_bay_dock_pos, 30.0)
			return

		# Long range: keep brain navigating via patrol toward bay entrance
		if _brain.current_state == AIBrain.State.IDLE:
			_brain.set_patrol_area(_bay_approach_pos, 50.0)
			_brain.current_state = AIBrain.State.PATROL
		elif _brain.current_state == AIBrain.State.PATROL:
			# Continuously update patrol target (station may be orbiting)
			_brain.set_patrol_area(_bay_approach_pos, 50.0)

	# Monitor construction arrival (same as move_to)
	if command == &"construction" and not _arrived:
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos =FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		target_pos = _push_target_outside_stations(target_pos)
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)

	# Monitor mine arrival — switch to MINING state when close
	if command == &"mine" and not _arrived:
		var cx: float = command_params.get("center_x", 0.0)
		var cz: float = command_params.get("center_z", 0.0)
		var target_pos =FloatingOrigin.to_local_pos([cx, 0.0, cz])
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_arrived = true
			_brain.current_state = AIBrain.State.MINING

	# Monitor move_to arrival
	if command == &"move_to" and not _arrived:
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos =FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		target_pos = _push_target_outside_stations(target_pos)
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)

	# Monitor attack target
	if command == &"attack" and _attack_target_id != "":
		var ent =EntityRegistry.get_entity(_attack_target_id)
		if ent.is_empty():
			# Target destroyed — stay in patrol zone, keep fighting nearby enemies
			_attack_target_id = ""
		else:
			# Update patrol area to track moving target
			var target_pos =FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			_brain.set_patrol_area(target_pos, 50.0)
			# If target has a node and brain lost its target, re-acquire
			var target_node = ent.get("node", null) if ent.get("node") else null
			if target_node and is_instance_valid(target_node) and _brain.target == null:
				_brain.target = target_node
				_brain.current_state = AIBrain.State.PURSUE


func _mark_arrived(target_pos: Vector3) -> void:
	_arrived = true
	if _ship:
		_ship.ai_navigation_active = false
		_ship.set_throttle(Vector3.ZERO)
		# Speed cap handled by _update_navigation_boost (keeps low cap until settled)
	if _brain:
		_brain.set_patrol_area(target_pos, 30.0)  # Tight holding pattern
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "arrived", true)


## Push target_pos outside any station exclusion zone so the ship doesn't
## endlessly orbit trying to reach an unreachable point inside a station.
func _push_target_outside_stations(target_pos: Vector3) -> Vector3:
	# Use EntityRegistry as authoritative source (always available)
	var stations: Array = EntityRegistry.get_by_type(EntityRegistry.EntityType.STATION)
	for st in stations:
		var st_pos: Vector3 = FloatingOrigin.to_local_pos([st["pos_x"], st["pos_y"], st["pos_z"]])
		var to_target: Vector3 = target_pos - st_pos
		var dist: float = to_target.length()
		if dist < STATION_SAFE_MARGIN:
			if dist < 1.0:
				to_target = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			else:
				to_target = to_target.normalized()
			return st_pos + to_target * STATION_SAFE_MARGIN
	return target_pos


func _find_nearest_station_id() -> String:
	## Finds the nearest station to this ship in the EntityRegistry.
	if _ship == null:
		return ""
	var ship_upos: Array = FloatingOrigin.to_universe_pos(_ship.global_position)
	var best_id: String = ""
	var best_dist_sq: float = INF
	for ent in EntityRegistry.get_all().values():
		if ent.get("type", -1) != EntityRegistrySystem.EntityType.STATION:
			continue
		var dx: float = ent["pos_x"] - ship_upos[0]
		var dz: float = ent["pos_z"] - ship_upos[2]
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = ent.get("id", "")
	return best_id


func _on_origin_shifted(_delta: Vector3) -> void:
	# Floating origin shifted — local waypoints in AIBrain are now stale.
	# Refresh patrol area using universe coords from command_params.
	if _brain == null or command == &"":
		return
	match command:
		&"move_to", &"construction":
			var tx: float = command_params.get("target_x", 0.0)
			var tz: float = command_params.get("target_z", 0.0)
			_brain.set_patrol_area(FloatingOrigin.to_local_pos([tx, 0.0, tz]), 50.0)
		&"mine":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			_brain.set_patrol_area(FloatingOrigin.to_local_pos([cx, 0.0, cz]), 50.0)
		&"patrol":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			var radius: float = command_params.get("radius", 500.0)
			_brain.set_patrol_area(FloatingOrigin.to_local_pos([cx, 0.0, cz]), radius)
		&"attack":
			if _attack_target_id != "":
				var ent =EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					_brain.set_patrol_area(FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]]), 50.0)
		&"return_to_station":
			# Refresh dock target positions after origin shift
			if _station_id != "" and _bay_target_valid:
				_resolve_station_dock_targets()
				if _brain.current_state == AIBrain.State.PATROL:
					_brain.set_patrol_area(_bay_approach_pos, 50.0)


const NAV_BOOST_MIN_DIST: float = 500.0    # Keep 3 km/s boost until this close
const NAV_APPROACH_RAMP_DIST: float = 5000.0 # Start progressive speed cap at 5 km
const NAV_APPROACH_MIN_SPEED: float = 50.0   # Minimum approach speed near target

func _update_navigation_boost() -> void:
	## Enable 3km/s approach speed when fleet ship is far from its command target.
	## Progressive speed cap over last 5 km prevents overshoot (mirrors player autopilot).
	if command == &"mine" and _arrived:
		# AIMiningBehavior manages nav boost autonomously during travel states
		return
	if _arrived or command == &"":
		_ship.ai_navigation_active = false
		# Keep a low speed cap until ship has settled (prevents coasting past target)
		if _ship.linear_velocity.length() > NAV_APPROACH_MIN_SPEED:
			_ship._gate_approach_speed_cap = NAV_APPROACH_MIN_SPEED
		else:
			_ship._gate_approach_speed_cap = 0.0
		return

	var target_pos: Vector3
	match command:
		&"move_to", &"construction":
			var tx: float = command_params.get("target_x", 0.0)
			var tz: float = command_params.get("target_z", 0.0)
			target_pos = FloatingOrigin.to_local_pos([tx, 0.0, tz])
		&"mine":
			var cx: float = command_params.get("center_x", 0.0)
			var cz: float = command_params.get("center_z", 0.0)
			target_pos = FloatingOrigin.to_local_pos([cx, 0.0, cz])
		&"return_to_station":
			if not _bay_target_valid:
				_ship.ai_navigation_active = false
				_ship._gate_approach_speed_cap = 0.0
				return
			target_pos = _bay_approach_pos
		&"attack":
			if _attack_target_id != "":
				var ent =EntityRegistry.get_entity(_attack_target_id)
				if not ent.is_empty():
					target_pos = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
				else:
					_ship.ai_navigation_active = false
					_ship._gate_approach_speed_cap = 0.0
					return
			else:
				_ship.ai_navigation_active = false
				_ship._gate_approach_speed_cap = 0.0
				return
		_:
			_ship.ai_navigation_active = false
			_ship._gate_approach_speed_cap = 0.0
			return

	var dist: float = _ship.global_position.distance_to(target_pos)

	# Keep navigation boost until close — speed cap handles the deceleration
	_ship.ai_navigation_active = dist > NAV_BOOST_MIN_DIST

	# Progressive speed cap: quadratic ramp from 3000 m/s at 5 km to 50 m/s near target
	# This forces the velocity clamp in _integrate_forces to actively brake the ship
	if dist < NAV_APPROACH_RAMP_DIST:
		var t: float = clampf(dist / NAV_APPROACH_RAMP_DIST, 0.0, 1.0)
		_ship._gate_approach_speed_cap = lerpf(NAV_APPROACH_MIN_SPEED, ShipController.AUTOPILOT_APPROACH_SPEED, t * t)
	else:
		_ship._gate_approach_speed_cap = 0.0
