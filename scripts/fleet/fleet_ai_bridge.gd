class_name FleetAIBridge
extends Node

# =============================================================================
# Fleet AI Bridge — Translates fleet commands to AIBrain states
# Attached as child of deployed fleet NPC (sibling of AIBrain/AIPilot)
#
# For move_to / return_to_station over long distances, uses the ship's built-in
# autopilot (cruise speed ~850k m/s) for visible map movement.
# Once near destination, switches to AIBrain patrol for holding position.
# =============================================================================

var fleet_index: int = -1
var command: StringName = &""
var command_params: Dictionary = {}

var _ship: ShipController = null
var _brain: AIBrain = null
var _home_position: Vector3 = Vector3.ZERO
var _station_id: String = ""
var _returning: bool = false
var _threat_timer: float = 0.0
var _arrived: bool = false
var _autopilot_entity_id: String = ""
var _has_weapons: bool = false
var _threat_cooldown: float = 0.0  # After disengaging, ignore threats for this duration
const THREAT_COOLDOWN_DURATION: float = 10.0  # Seconds to ignore threats after disengaging

const RETURN_ARRIVE_DIST: float = 500.0
const MOVE_ARRIVE_DIST: float = 200.0
const THREAT_TIMEOUT: float = 15.0
const AUTOPILOT_THRESHOLD: float = 1000.0  # Use autopilot+cruise when > 1km away


var _initialized: bool = false


func _ready() -> void:
	_ship = get_parent() as ShipController
	# If tree is disabled (player is docked), defer init until tree is re-enabled.
	# _process will handle deferred initialization when process resumes.
	if _ship and not _ship.can_process():
		return
	await get_tree().process_frame
	_do_init()


func _do_init() -> void:
	if _initialized:
		return
	_initialized = true
	_brain = _ship.get_node_or_null("AIBrain") as AIBrain if _ship else null

	# Check if ship has combat weapons (not mining lasers)
	var wm := _ship.get_node_or_null("WeaponManager") as WeaponManager if _ship else null
	_has_weapons = wm != null and wm.has_combat_weapons_in_group(0)

	# Unarmed ships: disable weapons in brain so they don't try to fight
	if _brain and not _has_weapons:
		_brain.weapons_enabled = false

	if _brain:
		apply_command(command, command_params)


func apply_command(cmd: StringName, params: Dictionary = {}) -> void:
	command = cmd
	command_params = params
	_returning = false
	_arrived = false
	_threat_timer = 0.0
	_disengage_fleet_autopilot()
	if _brain == null:
		return

	match cmd:
		&"move_to":
			var target_x: float = params.get("target_x", 0.0)
			var target_z: float = params.get("target_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			_home_position = target_pos
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist > AUTOPILOT_THRESHOLD:
				# Long distance — autopilot with cruise speed
				_engage_fleet_autopilot(target_x, 0.0, target_z)
				_brain.current_state = AIBrain.State.IDLE
			elif dist > MOVE_ARRIVE_DIST:
				# Short distance — patrol with obstacle avoidance
				_brain.set_patrol_area(target_pos, 50.0)
				_brain.current_state = AIBrain.State.PATROL
			else:
				# Already at destination
				_mark_arrived(target_pos)
		&"patrol":
			var center_x: float = params.get("center_x", 0.0)
			var center_z: float = params.get("center_z", 0.0)
			var radius: float = params.get("radius", 500.0)
			var center_pos := FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			_home_position = center_pos
			var dist: float = _ship.global_position.distance_to(center_pos)
			if dist > AUTOPILOT_THRESHOLD:
				_engage_fleet_autopilot(center_x, 0.0, center_z)
				_brain.current_state = AIBrain.State.IDLE
			else:
				_brain.set_patrol_area(center_pos, radius)
				_brain.current_state = AIBrain.State.PATROL
		&"return_to_station":
			_returning = true
			_station_id = params.get("station_id", "")
			if _station_id != "":
				var ent := EntityRegistry.get_entity(_station_id)
				if not ent.is_empty():
					var station_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
					var dist: float = _ship.global_position.distance_to(station_pos)
					if dist > RETURN_ARRIVE_DIST:
						# Always use autopilot for return trips
						_ship.autopilot_active = true
						_ship.autopilot_target_id = _station_id
						_ship.autopilot_target_name = "Fleet Return"
						_ship.autopilot_is_gate = false
						_brain.current_state = AIBrain.State.IDLE
					else:
						# Already close — retrieve immediately
						var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
						if fdm:
							fdm.retrieve_ship(fleet_index)


func _process(delta: float) -> void:
	if _ship == null:
		return
	# Deferred init: tree was disabled when spawned (player was docked)
	if not _initialized:
		_do_init()
		return
	if _brain == null:
		return

	# Threat cooldown: after disengaging, ignore new threats briefly
	if _threat_cooldown > 0.0:
		_threat_cooldown -= delta
		# Suppress any threat the brain picks up during cooldown
		if _brain.current_state in [AIBrain.State.PURSUE, AIBrain.State.ATTACK]:
			_brain.target = null
			_brain.current_state = AIBrain.State.PATROL

	# Threat response: if attacked while on non-combat command
	if _brain.current_state in [AIBrain.State.PURSUE, AIBrain.State.ATTACK, AIBrain.State.EVADE]:
		if command in [&"move_to", &"patrol"]:
			if not _has_weapons:
				# Unarmed: immediately disengage and resume mission
				_brain.target = null
				_brain.current_state = AIBrain.State.IDLE
				_threat_cooldown = THREAT_COOLDOWN_DURATION
				apply_command(command, command_params)
				return

			# Armed: fight back briefly, then resume mission
			if _ship.autopilot_active:
				_disengage_fleet_autopilot()
			_threat_timer += delta
			if _threat_timer > THREAT_TIMEOUT or not _brain._is_target_valid():
				# Disengage: clear brain target + cooldown to prevent re-detect loop
				_brain.target = null
				_brain.current_state = AIBrain.State.IDLE
				_threat_timer = 0.0
				_threat_cooldown = THREAT_COOLDOWN_DURATION
				apply_command(command, command_params)
		return

	_threat_timer = 0.0

	# Monitor autopilot completion (move_to or patrol)
	if _autopilot_entity_id != "" and not _ship.autopilot_active:
		# Autopilot arrived at destination — switch to patrol
		_cleanup_autopilot_entity()
		if command == &"move_to":
			var target_x: float = command_params.get("target_x", 0.0)
			var target_z: float = command_params.get("target_z", 0.0)
			var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
			_brain.set_patrol_area(target_pos, 50.0)
			_brain.current_state = AIBrain.State.PATROL
			# Check if close enough to mark arrived
			var dist: float = _ship.global_position.distance_to(target_pos)
			if dist < MOVE_ARRIVE_DIST:
				_mark_arrived(target_pos)
		elif command == &"patrol":
			var center_x: float = command_params.get("center_x", 0.0)
			var center_z: float = command_params.get("center_z", 0.0)
			var radius: float = command_params.get("radius", 500.0)
			var center_pos := FloatingOrigin.to_local_pos([center_x, 0.0, center_z])
			_brain.set_patrol_area(center_pos, radius)
			_brain.current_state = AIBrain.State.PATROL

	# Monitor autopilot completion for return_to_station
	if _returning and _ship.autopilot_active and _ship.autopilot_target_id == _station_id:
		# Still cruising toward station, let autopilot handle it
		pass
	elif _returning and not _ship.autopilot_active and _station_id != "":
		# Autopilot finished or was never engaged — check distance
		var ent := EntityRegistry.get_entity(_station_id)
		if not ent.is_empty():
			var station_pos := FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			var dist: float = _ship.global_position.distance_to(station_pos)
			if dist < RETURN_ARRIVE_DIST:
				# Arrived — request retrieval
				var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
				if fdm:
					fdm.retrieve_ship(fleet_index)
				return
			if dist > AUTOPILOT_THRESHOLD:
				# Still far — re-engage autopilot
				_ship.autopilot_active = true
				_ship.autopilot_target_id = _station_id
				_ship.autopilot_target_name = "Fleet Return"
				_ship.autopilot_is_gate = false
				_brain.current_state = AIBrain.State.IDLE
			else:
				# Close approach — patrol toward station
				_brain.set_patrol_area(station_pos, 50.0)
				if _brain.current_state == AIBrain.State.IDLE:
					_brain.current_state = AIBrain.State.PATROL

	# Move-to arrival check (when not using autopilot)
	if command == &"move_to" and not _arrived and _autopilot_entity_id == "":
		var target_x: float = command_params.get("target_x", 0.0)
		var target_z: float = command_params.get("target_z", 0.0)
		var target_pos := FloatingOrigin.to_local_pos([target_x, 0.0, target_z])
		var dist: float = _ship.global_position.distance_to(target_pos)
		if dist < MOVE_ARRIVE_DIST:
			_mark_arrived(target_pos)


# =============================================================================
# AUTOPILOT HELPERS
# =============================================================================
func _engage_fleet_autopilot(ux: float, uy: float, uz: float) -> void:
	_disengage_fleet_autopilot()
	# Register a temporary waypoint entity in EntityRegistry
	_autopilot_entity_id = "fleet_wp_%d_%d" % [fleet_index, Time.get_ticks_msec()]
	EntityRegistry.register(_autopilot_entity_id, {
		"name": "Fleet Waypoint",
		"type": EntityRegistrySystem.EntityType.SHIP_FLEET,
		"pos_x": ux,
		"pos_y": uy,
		"pos_z": uz,
		"node": null,
		"radius": 0.0,
		"color": Color.TRANSPARENT,
		"extra": {"hidden": true},
	})
	# Engage autopilot (avoid calling engage_autopilot() which touches GUI)
	_ship.autopilot_active = true
	_ship.autopilot_target_id = _autopilot_entity_id
	_ship.autopilot_target_name = "Fleet Destination"
	_ship.autopilot_is_gate = false


func _disengage_fleet_autopilot() -> void:
	if _ship and _ship.autopilot_active:
		_ship.disengage_autopilot()
	_cleanup_autopilot_entity()


func _cleanup_autopilot_entity() -> void:
	if _autopilot_entity_id != "":
		EntityRegistry.unregister(_autopilot_entity_id)
		_autopilot_entity_id = ""


func _mark_arrived(target_pos: Vector3) -> void:
	_arrived = true
	_brain.set_patrol_area(target_pos, 50.0)
	var fdm: FleetDeploymentManager = GameManager.get_node_or_null("FleetDeploymentManager")
	if fdm:
		fdm.update_entity_extra(fleet_index, "arrived", true)


func _exit_tree() -> void:
	_disengage_fleet_autopilot()
