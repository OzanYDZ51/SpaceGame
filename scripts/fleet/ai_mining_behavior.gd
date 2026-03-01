class_name AIMiningBehavior
extends Node

# =============================================================================
# AI Mining Behavior — Autonomous mining loop for fleet ships
# Mine → Cargo full → Return to station → Dock → Sell → Undock → Depart → Repeat
# States: SEARCHING → SCANNING → ROAMING → NAVIGATING → POSITIONING → EXTRACTING
#         → COOLING → RETURNING → DOCKED → DEPARTING → SEARCHING ...
# Reuses MiningSystem constants, AsteroidFieldManager API, MiningLaserBeam visual.
# Uses physical asteroids only — forces cell loading at ship position via register_interest_position.
# =============================================================================

enum MiningState { SEARCHING, SCANNING, ROAMING, NAVIGATING, POSITIONING, EXTRACTING, COOLING, RETURNING, DOCKED, DEPARTING }

var fleet_index: int = -1
var fleet_ship = null

var _state: MiningState = MiningState.SEARCHING
var _ship = null
var _brain = null
var _pilot = null
var _asteroid_mgr = null

# Physical mining target (real AsteroidData from AsteroidFieldManager)
var _mining_target = null

# Mining stats
var _mining_dps: float = 10.0
var _mining_tick_timer: float = 0.0

# Heat system (same constants as MiningSystem)
var heat: float = 0.0
var is_overheated: bool = false

# Beam visual (only when near player)
var _beam = null
var _beam_visible: bool = false
const BEAM_VISIBILITY_DIST: float = 2000.0

# Scan cooldown (range from ship sensor_range)
var _scan_cooldown: float = 0.0
const SCAN_COOLDOWN: float = 8.0
var _scan_radius: float = 3000.0        # Initialized from ShipData.sensor_range
const SCAN_PULSE_VISIBILITY: float = 5000.0  # Show pulse VFX if player within this range

# Resource filter (empty = mine everything)
var _resource_filter: Array = []

# Timers
var _search_timer: float = 0.0
const SEARCH_INTERVAL: float = 1.0
const SEARCH_RADIUS: float = 1500.0
const NAVIGATE_ARRIVE_DIST: float = 150.0
const POSITIONING_DOT_THRESHOLD: float = 0.9

# Roaming (explore different parts of the belt when no matching resources found)
var _search_fail_count: int = 0
const SEARCH_FAIL_MAX: int = 5          # After N failed search cycles, roam to a new spot
var _roam_target: Vector3 = Vector3.ZERO
const ROAM_ARRIVE_DIST: float = 500.0
var _belt_field: AsteroidFieldData = null

# Autonomous sell loop
var _resource_capacity: int = 50
const CARGO_RETURN_RATIO: float = 0.90  # Return to station at 90% cargo
var _home_station_id: String = ""
var _belt_center_x: float = 0.0
var _belt_center_z: float = 0.0
const STATION_ARRIVE_DIST: float = 150.0
const BELT_ARRIVE_DIST: float = 200.0

# Docking state
var _dock_timer: float = 0.0
const DOCK_SELL_DELAY: float = 3.0    # seconds docked before selling
const DOCK_UNDOCK_DELAY: float = 2.0  # seconds after sell before undock
var _dock_sold: bool = false
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0

# Navigation boost delegated to AINavigation


func _ready() -> void:
	_ship = get_parent()
	if _ship == null:
		return

	await get_tree().process_frame
	_brain = _ship.get_node_or_null("AIController")
	_pilot = _ship.get_node_or_null("AINavigation")

	# Find AsteroidFieldManager (child of GameManager)
	_asteroid_mgr = GameManager.get_node_or_null("AsteroidFieldManager")

	# Read mining DPS from equipped mining laser
	_update_mining_dps()

	# Create beam visual
	_beam = MiningLaserBeam.new()
	_beam.name = "AIMiningBeam"
	add_child(_beam)

	# Read cargo capacity + sensor range from ship data
	if fleet_ship:
		var ship_data =ShipRegistry.get_ship_data(fleet_ship.ship_id)
		if ship_data:
			_resource_capacity = ship_data.cargo_capacity
			_scan_radius = ship_data.sensor_range
		_home_station_id = fleet_ship.docked_station_id

	# Read belt center + resource filter from FleetAICommand sibling
	var bridge = _ship.get_node_or_null("FleetAICommand")
	if bridge:
		_belt_center_x = bridge.command_params.get("center_x", 0.0)
		_belt_center_z = bridge.command_params.get("center_z", 0.0)
		_resource_filter = bridge.command_params.get("resource_filter", [])

	# Fallback: if no docked station, find nearest station to belt center
	if _home_station_id == "":
		_home_station_id = _find_nearest_station(_belt_center_x, _belt_center_z)

	# Identify belt field for roaming within it
	if _asteroid_mgr:
		var target_dist =sqrt(_belt_center_x * _belt_center_x + _belt_center_z * _belt_center_z)
		for f in _asteroid_mgr._fields:
			if absf(target_dist - f.orbital_radius) < f.width * 0.5:
				_belt_field = f
				break

	# Listen to origin shifts for virtual target position correction
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)

	# Restore saved AI state if available (reconnect / save-load)
	if fleet_ship and not fleet_ship.ai_state.is_empty():
		_restore_state(fleet_ship.ai_state)

	# Fallback: if belt center is still (0,0) after restore, use ship's current position
	# This prevents mining ships from flying to the sun after reconnect with stale data
	if absf(_belt_center_x) < 1.0 and absf(_belt_center_z) < 1.0:
		if fleet_ship and fleet_ship.last_known_pos.size() >= 3:
			var lkp_x: float = fleet_ship.last_known_pos[0]
			var lkp_z: float = fleet_ship.last_known_pos[2]
			if absf(lkp_x) > 1.0 or absf(lkp_z) > 1.0:
				_belt_center_x = lkp_x
				_belt_center_z = lkp_z
		elif _ship:
			var upos =FloatingOrigin.to_universe_pos(_ship.global_position)
			if absf(upos[0]) > 1.0 or absf(upos[2]) > 1.0:
				_belt_center_x = upos[0]
				_belt_center_z = upos[2]
		# Re-resolve home station with corrected belt center
		if _home_station_id == "":
			_home_station_id = _find_nearest_station(_belt_center_x, _belt_center_z)

	# Set initial entity destination to belt center for map display
	if _state == MiningState.RETURNING:
		var station_ent =EntityRegistry.get_entity(_home_station_id)
		if not station_ent.is_empty():
			_update_entity_destination(station_ent["pos_x"], station_ent["pos_z"], "returning")
		else:
			_update_entity_destination(_belt_center_x, _belt_center_z, "mining")
	elif _state == MiningState.DOCKED:
		_update_entity_destination(0.0, 0.0, "docked")
		# Re-apply hidden flags for map (reconnect / save-load)
		var fdm2 = GameManager.get_node_or_null("FleetDeploymentManager")
		if fdm2:
			fdm2.update_entity_extra(fleet_index, "hidden", true)
			fdm2.update_entity_extra(fleet_index, "mining_docked", true)
			fdm2.update_entity_extra(fleet_index, "mining_docked_station", _home_station_id)
	else:
		_update_entity_destination(_belt_center_x, _belt_center_z, "mining")


func _exit_tree() -> void:
	if _ship and is_instance_valid(_ship):
		# Restore ship if removed while docked (e.g. player gives another order)
		if _state == MiningState.DOCKED:
			_exit_dock()
		_clear_nav_boost()
	_clear_entity_mining_data()
	if _asteroid_mgr and is_instance_valid(_asteroid_mgr):
		_asteroid_mgr.unregister_interest_position("fleet_%d_mining" % fleet_index)
	if FloatingOrigin.origin_shifted.is_connected(_on_origin_shifted):
		FloatingOrigin.origin_shifted.disconnect(_on_origin_shifted)
	if _beam and _beam._active:
		_beam.deactivate()


func _update_mining_dps() -> void:
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm == null:
		return
	var mining_hps = wm.get_mining_hardpoints_in_group(0)
	if not mining_hps.is_empty() and mining_hps[0].mounted_weapon:
		_mining_dps = mining_hps[0].mounted_weapon.damage_per_hit


## Called by FleetDeploymentManager when mine order params change (new belt, new filter, etc.)
func update_params(params: Dictionary) -> void:
	# Stop current mining action
	_stop_beam()
	_mining_target = null
	_search_fail_count = 0
	_roam_target = Vector3.ZERO

	# Update belt center
	_belt_center_x = params.get("center_x", _belt_center_x)
	_belt_center_z = params.get("center_z", _belt_center_z)

	# Update resource filter
	_resource_filter = params.get("resource_filter", _resource_filter)

	# Update home station: explicit param > nearest station to new belt > keep old
	var new_station: String = params.get("home_station_id", "")
	if new_station != "":
		_home_station_id = new_station
	else:
		# Auto-find nearest station to new belt center for sell runs
		_home_station_id = _find_nearest_station(_belt_center_x, _belt_center_z)

	# Re-identify belt field for roaming
	_belt_field = null
	if _asteroid_mgr:
		var target_dist =sqrt(_belt_center_x * _belt_center_x + _belt_center_z * _belt_center_z)
		for f in _asteroid_mgr._fields:
			if absf(target_dist - f.orbital_radius) < f.width * 0.5:
				_belt_field = f
				break

	# Reset to searching at new location
	_state = MiningState.SEARCHING
	_scan_cooldown = 0.0


## Ensure asteroid cells are loaded around this ship's position even when the player
## camera is far away. Called before searching so physical asteroids are available.
func _ensure_cells_loaded() -> void:
	if _asteroid_mgr and is_instance_valid(_asteroid_mgr) and _ship:
		_asteroid_mgr.register_interest_position("fleet_%d_mining" % fleet_index, _ship.global_position)


## Find the nearest station (by universe coords) to use as home base for sell runs.
func _find_nearest_station(uni_x: float, uni_z: float) -> String:
	var stations =EntityRegistry.get_by_type(EntityRegistrySystem.EntityType.STATION)
	var best_id: String = ""
	var best_dist_sq: float = INF
	for ent in stations:
		var sx: float = ent.get("pos_x", 0.0)
		var sz: float = ent.get("pos_z", 0.0)
		var dx: float = sx - uni_x
		var dz: float = sz - uni_z
		var d2: float = dx * dx + dz * dz
		if d2 < best_dist_sq:
			best_dist_sq = d2
			best_id = ent.get("id", "")
	return best_id


## Captures runtime AI state for persistence (called by FleetDeploymentManager every 10s).
func save_state() -> Dictionary:
	return {
		"mining_state": _state,
		"home_station_id": _home_station_id,
		"belt_center_x": _belt_center_x,
		"belt_center_z": _belt_center_z,
		"heat": heat,
		"is_overheated": is_overheated,
	}


## Restores AI state from saved data. Called during _ready() if fleet_ship.ai_state exists.
func _restore_state(state: Dictionary) -> void:
	_home_station_id = state.get("home_station_id", _home_station_id)
	_belt_center_x = state.get("belt_center_x", _belt_center_x)
	_belt_center_z = state.get("belt_center_z", _belt_center_z)
	heat = state.get("heat", 0.0)
	is_overheated = state.get("is_overheated", false)

	var saved_state: int = state.get("mining_state", MiningState.SEARCHING)
	var cargo_fill: float = float(_get_total_resources()) / float(maxi(_resource_capacity, 1))

	# Smart state restoration: check cargo + saved state to pick the right phase
	if saved_state == MiningState.DOCKED or saved_state == MiningState.RETURNING:
		# Was selling or heading to station — validate station and resume return
		_validate_home_station()
		if _home_station_id != "":
			_state = MiningState.RETURNING
		else:
			_state = MiningState.SEARCHING
	elif cargo_fill >= CARGO_RETURN_RATIO:
		# Cargo full but wasn't returning — start return now
		_validate_home_station()
		if _home_station_id != "":
			_state = MiningState.RETURNING
		else:
			_state = MiningState.SEARCHING
	elif saved_state == MiningState.DEPARTING:
		_state = MiningState.DEPARTING
	else:
		_state = MiningState.SEARCHING

	print("AIMining[%d]: Restored state=%s home=%s cargo=%.0f%%" % [
		fleet_index, MiningState.keys()[_state], _home_station_id, cargo_fill * 100.0])


## Checks if home station still exists. If not, finds the nearest alternative.
func _validate_home_station() -> void:
	if _home_station_id == "":
		_home_station_id = _find_nearest_station(_belt_center_x, _belt_center_z)
		return
	var ent =EntityRegistry.get_entity(_home_station_id)
	if not ent.is_empty():
		return  # Station still exists
	# Station gone — find nearest replacement
	var new_id =_find_nearest_station(_belt_center_x, _belt_center_z)
	if new_id != "":
		print("AIMining[%d]: Home station '%s' lost, rerouting to '%s'" % [fleet_index, _home_station_id, new_id])
		_home_station_id = new_id
	else:
		print("AIMining[%d]: Home station '%s' lost, no replacement found!" % [fleet_index, _home_station_id])
		_home_station_id = ""


func _process(delta: float) -> void:
	if _ship == null or _pilot == null:
		return
	if _brain == null or _brain.current_state != AIController.State.MINING:
		_stop_beam()
		return

	# Scan cooldown tick
	if _scan_cooldown > 0.0:
		_scan_cooldown = maxf(0.0, _scan_cooldown - delta)

	# Heat system (always ticks)
	_update_heat(delta)

	match _state:
		MiningState.SEARCHING:
			_tick_searching(delta)
		MiningState.SCANNING:
			_tick_scanning(delta)
		MiningState.ROAMING:
			_tick_roaming()
		MiningState.NAVIGATING:
			_tick_navigating()
		MiningState.POSITIONING:
			_tick_positioning()
		MiningState.EXTRACTING:
			_tick_extracting(delta)
		MiningState.COOLING:
			_tick_cooling()
		MiningState.RETURNING:
			_tick_returning()
		MiningState.DOCKED:
			_tick_docked(delta)
		MiningState.DEPARTING:
			_tick_departing()


# =========================================================================
# State ticks
# =========================================================================

func _tick_searching(delta: float) -> void:
	_search_timer += delta
	if _search_timer < SEARCH_INTERVAL:
		return
	_search_timer = 0.0

	# Force asteroid cell loading around this ship (even when camera/player is far away)
	_ensure_cells_loaded()

	# If scan cooldown is ready, do a scan to reveal nearby asteroids (same as player H key)
	if _scan_cooldown <= 0.0 and _asteroid_mgr:
		_scan_cooldown = SCAN_COOLDOWN
		_asteroid_mgr.reveal_asteroids_in_radius(_ship.global_position, _scan_radius)
		_spawn_scan_pulse()
		_state = MiningState.SCANNING
		_search_timer = 0.0
		return

	# Try physical asteroid (cells are loaded around the ship)
	var asteroid =_find_physical_asteroid()
	if asteroid:
		_mining_target = asteroid
		_search_fail_count = 0
		_state = MiningState.NAVIGATING
		return

	# Nothing found — track failures and roam if stuck too long
	_search_fail_count += 1
	if _search_fail_count >= SEARCH_FAIL_MAX:
		_search_fail_count = 0
		_roam_target = _pick_roam_position()
		_state = MiningState.ROAMING


func _tick_scanning(delta: float) -> void:
	# Brief pause after scan to let reveal settle, then search among scanned asteroids
	_search_timer += delta
	if _search_timer < 0.5:
		return
	_search_timer = 0.0

	# Try physical asteroid (now with revealed scan data)
	var asteroid =_find_physical_asteroid()
	if asteroid:
		_mining_target = asteroid
		_search_fail_count = 0
		_state = MiningState.NAVIGATING
		return

	# Nothing found after scan — track failure and go back to SEARCHING
	_search_fail_count += 1
	if _search_fail_count >= SEARCH_FAIL_MAX:
		_search_fail_count = 0
		_roam_target = _pick_roam_position()
		_state = MiningState.ROAMING
	else:
		_state = MiningState.SEARCHING


func _tick_navigating() -> void:
	var target_pos =_get_target_position()
	if target_pos == Vector3.ZERO:
		_state = MiningState.SEARCHING
		return

	var dist = _pilot.get_distance_to(target_pos)
	if dist < NAVIGATE_ARRIVE_DIST:
		_state = MiningState.POSITIONING
		return

	_pilot.fly_toward(target_pos, NAVIGATE_ARRIVE_DIST)


func _tick_positioning() -> void:
	var target_pos =_get_target_position()
	if target_pos == Vector3.ZERO:
		_state = MiningState.SEARCHING
		return

	# Check if physical target got depleted while we were approaching
	if _mining_target and _mining_target.is_depleted:
		_mining_target = null
		_state = MiningState.SEARCHING
		return

	# Face the target
	_pilot.face_target(target_pos)
	# Zero throttle while aligning
	_ship.set_throttle(Vector3.ZERO)

	# Check alignment
	var to_target =(target_pos - _ship.global_position).normalized()
	var forward =-_ship.global_transform.basis.z
	if forward.dot(to_target) > POSITIONING_DOT_THRESHOLD:
		_mining_tick_timer = 0.0
		_state = MiningState.EXTRACTING


func _tick_extracting(delta: float) -> void:
	if is_overheated:
		_stop_beam()
		_state = MiningState.COOLING
		return

	var target_pos =_get_target_position()
	if target_pos == Vector3.ZERO:
		_stop_beam()
		_state = MiningState.SEARCHING
		return

	# Check if physical target got depleted
	if _mining_target and _mining_target.is_depleted:
		_stop_beam()
		_mining_target = null
		_state = MiningState.SEARCHING
		return

	# Keep facing target
	_pilot.face_target(target_pos)
	_ship.set_throttle(Vector3.ZERO)

	# Update beam visual (only if player is nearby)
	_update_beam_visual(target_pos)

	# Mining tick
	_mining_tick_timer += delta
	if _mining_tick_timer >= MiningSystem.MINING_TICK_INTERVAL:
		_mining_tick_timer -= MiningSystem.MINING_TICK_INTERVAL
		_do_mining_tick()


func _tick_cooling() -> void:
	# Wait for heat to drop below threshold
	if not is_overheated:
		_state = MiningState.SEARCHING


func _tick_returning() -> void:
	_validate_home_station()
	if _home_station_id == "":
		# No station available anywhere — keep mining, cargo overflow
		_clear_nav_boost()
		_state = MiningState.SEARCHING
		return
	var ent =EntityRegistry.get_entity(_home_station_id)
	if ent.is_empty():
		# Station registered but entity not loaded yet — wait
		_clear_nav_boost()
		return
	var station_pos =FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
	var dist = _ship.global_position.distance_to(station_pos)
	if dist < STATION_ARRIVE_DIST:
		_enter_dock()
		return
	_update_nav_boost(station_pos)
	_pilot.fly_toward(station_pos, STATION_ARRIVE_DIST)


func _enter_dock() -> void:
	_clear_nav_boost()

	# Stop the ship
	_ship.set_throttle(Vector3.ZERO)
	_ship.linear_velocity = Vector3.ZERO
	_ship.angular_velocity = Vector3.ZERO

	# Hide ship + disable collisions (like a real dock)
	_ship.visible = false
	_saved_collision_layer = _ship.collision_layer
	_saved_collision_mask = _ship.collision_mask
	_ship.collision_layer = 0
	_ship.collision_mask = 0

	_dock_timer = 0.0
	_dock_sold = false
	_state = MiningState.DOCKED
	_update_entity_destination(0.0, 0.0, "docked")

	# Hide from stellar map while docked
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "hidden", true)
		fdm.update_entity_extra(fleet_index, "mining_docked", true)
		fdm.update_entity_extra(fleet_index, "mining_docked_station", _home_station_id)


func _exit_dock() -> void:
	# Restore ship visibility + collisions
	_ship.visible = true
	_ship.collision_layer = _saved_collision_layer
	_ship.collision_mask = _saved_collision_mask

	# Unhide from stellar map
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "hidden", false)
		fdm.update_entity_extra(fleet_index, "mining_docked", false)
		fdm.update_entity_extra(fleet_index, "mining_docked_station", "")


func _tick_docked(delta: float) -> void:
	# Keep ship frozen while docked
	_ship.set_throttle(Vector3.ZERO)
	_ship.linear_velocity = Vector3.ZERO
	_ship.angular_velocity = Vector3.ZERO

	# Check if station still exists (destroyed mid-dock → emergency undock)
	_validate_home_station()
	if _home_station_id == "" or EntityRegistry.get_entity(_home_station_id).is_empty():
		_exit_dock()
		_state = MiningState.DEPARTING
		_update_entity_destination(_belt_center_x, _belt_center_z, "departing")
		return

	_dock_timer += delta

	# Phase 1: wait DOCK_SELL_DELAY then sell
	if not _dock_sold and _dock_timer >= DOCK_SELL_DELAY:
		_dock_sold = true
		_do_sell_resources()

	# Phase 2: wait DOCK_UNDOCK_DELAY after sell then undock + depart
	if _dock_sold and _dock_timer >= DOCK_SELL_DELAY + DOCK_UNDOCK_DELAY:
		_exit_dock()
		_state = MiningState.DEPARTING
		_update_entity_destination(_belt_center_x, _belt_center_z, "departing")


func _do_sell_resources() -> void:
	if fleet_ship == null:
		return

	var commerce = GameManager._commerce_manager
	var total_credits: int = 0
	var res_keys: Array = fleet_ship.ship_resources.keys()

	for res_id in res_keys:
		var qty: int = fleet_ship.ship_resources[res_id]
		if qty <= 0:
			continue

		var unit_price =PriceCatalog.get_resource_price(res_id)
		if unit_price > 0 and commerce.sell_resource_from_ship(res_id, qty, fleet_ship):
			total_credits += unit_price * qty

	if total_credits > 0 and GameManager._notif:
		GameManager._notif.fleet.earned(fleet_ship.custom_name, total_credits)


func _tick_roaming() -> void:
	# Fly to a new spot within the belt to search for matching resources
	if _roam_target == Vector3.ZERO:
		_roam_target = _pick_roam_position()
	var dist = _ship.global_position.distance_to(_roam_target)
	if dist < ROAM_ARRIVE_DIST:
		_roam_target = Vector3.ZERO
		_state = MiningState.SEARCHING
		return
	_pilot.fly_toward(_roam_target, ROAM_ARRIVE_DIST)


func _pick_roam_position() -> Vector3:
	# Pick a nearby point along the belt arc (~3-5km away)
	if _belt_field == null:
		# Fallback: random offset from current position
		var angle =randf() * TAU
		var offset =Vector3(cos(angle) * 3000.0, 0.0, sin(angle) * 3000.0)
		return _ship.global_position + offset

	var upos: Array = FloatingOrigin.to_universe_pos(_ship.global_position)
	var current_angle =atan2(float(upos[2]), float(upos[0]))

	# Move 3-5km along the belt arc
	var arc_dist =randf_range(3000.0, 5000.0)
	var angular_offset: float = arc_dist / _belt_field.orbital_radius
	if randf() < 0.5:
		angular_offset = -angular_offset

	var new_angle =current_angle + angular_offset
	var radius_offset =randf_range(-_belt_field.width * 0.25, _belt_field.width * 0.25)
	var new_radius: float = _belt_field.orbital_radius + radius_offset

	var uni_x: float = cos(new_angle) * new_radius
	var uni_z: float = sin(new_angle) * new_radius
	return FloatingOrigin.to_local_pos([uni_x, 0.0, uni_z])


func _tick_departing() -> void:
	var belt_pos =FloatingOrigin.to_local_pos([_belt_center_x, 0.0, _belt_center_z])
	var dist = _ship.global_position.distance_to(belt_pos)
	if dist < BELT_ARRIVE_DIST:
		_clear_nav_boost()
		_update_entity_destination(_belt_center_x, _belt_center_z, "mining")
		_state = MiningState.SEARCHING
		return
	_update_nav_boost(belt_pos)
	_pilot.fly_toward(belt_pos, BELT_ARRIVE_DIST)


func _get_total_resources() -> int:
	if fleet_ship == null:
		return 0
	var total: int = 0
	for res_id in fleet_ship.ship_resources:
		total += fleet_ship.ship_resources[res_id]
	return total


# =========================================================================
# Mining logic
# =========================================================================

func _do_mining_tick() -> void:
	if _mining_target:
		_do_physical_mining_tick()
	else:
		# No physical target — something changed mid-tick, go back to searching
		_stop_beam()
		_state = MiningState.SEARCHING


func _do_physical_mining_tick() -> void:
	if _mining_target == null or _mining_target.is_depleted:
		_state = MiningState.SEARCHING
		return

	# Safety net: skip sterile asteroids
	if not _mining_target.has_resource:
		_stop_beam()
		_mining_target = null
		_state = MiningState.SEARCHING
		return

	var res =MiningRegistry.get_resource(_mining_target.primary_resource)
	var difficulty: float = res.mining_difficulty if res else 1.0
	var damage: float = _mining_dps * MiningSystem.MINING_TICK_INTERVAL / difficulty

	var yield_data: Dictionary
	if is_instance_valid(_mining_target.node_ref):
		var node = _mining_target.node_ref
		yield_data = node.take_mining_damage(damage)
	else:
		_mining_target.health_current -= damage
		if _mining_target.health_current <= 0.0:
			_mining_target.health_current = 0.0
			_mining_target.is_depleted = true
			_mining_target.respawn_timer = Constants.ASTEROID_RESPAWN_TIME
		yield_data = {
			"resource_id": _mining_target.primary_resource,
			"quantity": _mining_target.get_yield_per_hit(),
		}

	# Update server-side asteroid health tracker (AI mining)
	if NetworkManager.is_server():
		var npc_auth = GameManager.get_node_or_null("NpcAuthority")
		if npc_auth:
			var sys_id: int = GameManager.current_system_id_safe()
			npc_auth.apply_ai_mining_damage(sys_id, String(_mining_target.id), damage, _mining_target.health_max)

	_store_yield(yield_data)
	if _state == MiningState.RETURNING:
		return  # Cargo full — _store_yield already transitioned

	if _mining_target and _mining_target.is_depleted:
		# Broadcast depletion
		if _asteroid_mgr:
			_asteroid_mgr.on_asteroid_depleted(_mining_target.id)
		_stop_beam()
		_mining_target = null
		_state = MiningState.SEARCHING


func _store_yield(yield_data: Dictionary) -> void:
	if yield_data.is_empty() or yield_data.get("quantity", 0) <= 0:
		return
	if fleet_ship == null:
		return
	var resource_id: StringName = yield_data["resource_id"]
	if resource_id == &"":
		return
	var qty: int = yield_data["quantity"]
	fleet_ship.add_resource(resource_id, qty)

	# Check if cargo is near full → start return trip (90% threshold)
	if _home_station_id != "" and _get_total_resources() >= int(_resource_capacity * CARGO_RETURN_RATIO):
		_stop_beam()
		_mining_target = null
		_state = MiningState.RETURNING
		# Update map destination to station
		var station_ent =EntityRegistry.get_entity(_home_station_id)
		if not station_ent.is_empty():
			_update_entity_destination(station_ent["pos_x"], station_ent["pos_z"], "returning")


# =========================================================================
# Heat system (same as MiningSystem)
# =========================================================================

func _update_heat(delta: float) -> void:
	if _state == MiningState.EXTRACTING and not is_overheated:
		heat = minf(heat + MiningSystem.HEAT_RATE * delta, 1.0)
		if heat >= 1.0:
			is_overheated = true
	else:
		heat = maxf(heat - MiningSystem.COOL_RATE * delta, 0.0)
		if is_overheated and heat <= MiningSystem.OVERHEAT_THRESHOLD:
			is_overheated = false


# =========================================================================
# Target finding
# =========================================================================

func _find_physical_asteroid() -> AsteroidData:
	if _asteroid_mgr == null:
		return null
	if _resource_filter.is_empty():
		return _asteroid_mgr.get_nearest_minable_asteroid(_ship.global_position, SEARCH_RADIUS)
	# Filtered search: get multiple candidates and pick the first matching the filter
	return _asteroid_mgr.get_nearest_minable_asteroid_filtered(_ship.global_position, SEARCH_RADIUS, _resource_filter)


func _get_target_position() -> Vector3:
	if _mining_target:
		if is_instance_valid(_mining_target.node_ref):
			return _mining_target.node_ref.global_position
		return _mining_target.position
	return Vector3.ZERO


# =========================================================================
# Beam visual
# =========================================================================

func _update_beam_visual(target_pos: Vector3) -> void:
	var player =GameManager.player_ship
	if player == null or not is_instance_valid(player):
		_stop_beam()
		return

	var dist_to_player = _ship.global_position.distance_to(player.global_position)
	if dist_to_player > BEAM_VISIBILITY_DIST:
		_stop_beam()
		return

	# Get beam source position from mining hardpoint
	var source_pos =_get_beam_source()

	if not _beam._active:
		_beam.activate(source_pos, target_pos)
		_beam_visible = true
	_beam.update_beam(source_pos, target_pos)


func _get_beam_source() -> Vector3:
	var wm = _ship.get_node_or_null("WeaponManager")
	if wm:
		var mining_hps = wm.get_mining_hardpoints_in_group(0)
		if not mining_hps.is_empty():
			return mining_hps[0].get_muzzle_transform_stable().origin
	return _ship.global_position


func _stop_beam() -> void:
	if _beam and _beam._active:
		_beam.deactivate()
		_beam_visible = false


func _spawn_scan_pulse() -> void:
	# Broadcast scan pulse to other players via server relay
	if NetworkManager.is_connected_to_server():
		var scan_upos: Array = FloatingOrigin.to_universe_pos(_ship.global_position)
		NetworkManager._rpc_scanner_pulse.rpc_id(1, scan_upos)

	# Same visual effect as player AsteroidScanner — expanding sonar bubble
	# Only spawn if player is nearby (performance)
	var player =GameManager.player_ship
	if player == null or not is_instance_valid(player):
		return
	if _ship.global_position.distance_to(player.global_position) > SCAN_PULSE_VISIBILITY:
		return

	var universe = GameManager.get_node_or_null("Universe")
	if universe == null:
		return

	var pulse =ScannerPulseEffect.new()
	pulse.name = "AIScanPulse_%d" % fleet_index
	pulse.position = _ship.global_position
	universe.add_child(pulse)


# =========================================================================
# Navigation boost (delegated to AINavigation)
# =========================================================================

func _update_nav_boost(target_pos: Vector3) -> void:
	if _pilot:
		_pilot.update_nav_boost(target_pos)


func _clear_nav_boost() -> void:
	if _pilot:
		_pilot.clear_nav_boost()


# =========================================================================
# Entity destination update (for map route lines + status display)
# =========================================================================

func _update_entity_destination(dest_ux: float, dest_uz: float, state_str: String) -> void:
	var fdm = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm == null:
		return
	fdm.update_entity_extra(fleet_index, "mining_state", state_str)
	fdm.update_entity_extra(fleet_index, "active_dest_ux", dest_ux)
	fdm.update_entity_extra(fleet_index, "active_dest_uz", dest_uz)


func _clear_entity_mining_data() -> void:
	if fleet_ship == null or fleet_ship.deployed_npc_id == &"":
		return
	var ent =EntityRegistry.get_entity(String(fleet_ship.deployed_npc_id))
	if not ent.is_empty() and ent.has("extra"):
		ent["extra"].erase("active_dest_ux")
		ent["extra"].erase("active_dest_uz")
		ent["extra"].erase("mining_state")


# =========================================================================
# Floating origin
# =========================================================================

func _on_origin_shifted(shift: Vector3) -> void:
	# Correct roaming target position on origin shift
	if _roam_target != Vector3.ZERO:
		_roam_target -= shift
