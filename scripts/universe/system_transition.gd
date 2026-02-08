class_name SystemTransition
extends Node

# =============================================================================
# System Transition Manager
# Handles loading/unloading star systems, cleanup, and spawning the player
# at the correct location (gate arrival or system center).
# =============================================================================

signal system_loading(system_id: int)
signal system_loaded(system_id: int)
signal system_unloading(system_id: int)
signal transition_started
signal transition_finished

var current_system_id: int = -1
var current_system_data: StarSystemData = null
var galaxy: GalaxyData = null
var _is_transitioning: bool = false

# Persistence: per-system state (visited, NPC kills, etc.)
var _system_states: Dictionary = {}  # system_id -> Dictionary

# Reference to the transition overlay
var _transition_overlay: ColorRect = null
var _transition_alpha: float = 0.0
var _transition_phase: int = 0  # 0=idle, 1=fade_out, 2=loading, 3=fade_in
var _pending_target_id: int = -1
# Active star impostor (child of main_scene, not Universe)
var _active_star: SystemStar = null

# Gate proximity state (set by JumpGate signals, read by GameManager for J key)
var _active_gate_target_id: int = -1
var _active_gate_target_name: String = ""

const FADE_SPEED: float = 2.0


func _ready() -> void:
	_create_transition_overlay()


func _process(delta: float) -> void:
	if _transition_phase == 0:
		return

	match _transition_phase:
		1:  # Fade out
			_transition_alpha = minf(_transition_alpha + delta * FADE_SPEED, 1.0)
			if _transition_alpha >= 1.0:
				_transition_phase = 2
				_execute_transition()
		3:  # Fade in
			_transition_alpha = maxf(_transition_alpha - delta * FADE_SPEED, 0.0)
			if _transition_alpha <= 0.0:
				_transition_phase = 0
				_is_transitioning = false
				_transition_overlay.visible = false
				transition_finished.emit()

	if _transition_overlay:
		_transition_overlay.modulate.a = _transition_alpha


func _create_transition_overlay() -> void:
	_transition_overlay = ColorRect.new()
	_transition_overlay.name = "TransitionOverlay"
	_transition_overlay.color = Color(0.0, 0.0, 0.02, 1.0)
	_transition_overlay.modulate.a = 0.0
	_transition_overlay.visible = false
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Will be added to UI layer by GameManager


func get_transition_overlay() -> ColorRect:
	return _transition_overlay


## Initiate a jump gate transition to another system.
func initiate_gate_jump(target_system_id: int) -> void:
	if _is_transitioning:
		return
	if galaxy == null:
		push_error("SystemTransition: No galaxy data!")
		return
	if target_system_id < 0 or target_system_id >= galaxy.systems.size():
		push_error("SystemTransition: Invalid target system id %d" % target_system_id)
		return

	_is_transitioning = true
	_pending_target_id = target_system_id

	# Start fade out
	_transition_phase = 1
	_transition_alpha = 0.0
	_transition_overlay.visible = true
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_started.emit()
	system_unloading.emit(current_system_id)


## Direct jump to a system (used for initial load or FTL).
func jump_to_system(target_id: int, _from_system_id: int = -1) -> void:
	if galaxy == null:
		push_error("SystemTransition: No galaxy data!")
		return

	_pending_target_id = target_id
	_execute_transition()


func _execute_transition() -> void:
	system_loading.emit(_pending_target_id)

	# 1. Save current system state
	if current_system_id >= 0:
		_save_system_state()

	# 2. Clear gate proximity + autopilot (old entities about to be destroyed)
	_active_gate_target_id = -1
	_active_gate_target_name = ""
	var ship := GameManager.player_ship as ShipController
	if ship:
		ship.disengage_autopilot()

	# 3. Cleanup current system
	_cleanup_current_system()

	# 4. Reset floating origin
	FloatingOrigin.reset_origin()

	# 5. Generate new system
	var galaxy_sys: Dictionary = galaxy.get_system(_pending_target_id)
	var connections := _build_connection_list(_pending_target_id)
	current_system_data = SystemGenerator.generate(galaxy_sys["seed"], connections)

	# Override system name with galaxy-generated name (consistent across sessions)
	current_system_data.system_name = galaxy_sys["name"]
	current_system_data.star_name = galaxy_sys["name"]

	current_system_id = _pending_target_id

	# 5. Populate scene
	_populate_system()

	# 6. Position player
	_position_player()

	# 7. Configure environment
	_configure_environment()

	# 8. Register entities
	_register_system_entities()

	# 9. Spawn encounters based on danger level
	_spawn_encounters(galaxy_sys["danger_level"])

	# 10. Notify
	system_loaded.emit(current_system_id)

	# If we were in a fade transition, start fade in
	if _transition_phase == 2:
		_transition_phase = 3
		_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cleanup_current_system() -> void:
	var universe := GameManager.universe_node
	if universe == null:
		return

	# Clean up star impostor (child of main_scene, not Universe)
	if _active_star and is_instance_valid(_active_star):
		_active_star.queue_free()
		_active_star = null

	# Clear LOD system (frees LOD0/1 nodes, clears LOD2 data, resets MultiMesh)
	var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
	if lod_mgr:
		lod_mgr.clear_all()
		# Re-register player in LOD system
		if GameManager.player_ship:
			var player_lod := ShipLODData.new()
			player_lod.id = &"player_ship"
			player_lod.ship_id = &"frigate_mk1"
			player_lod.ship_class = &"Frigate"
			player_lod.faction = &"neutral"
			player_lod.display_name = "Player"
			player_lod.node_ref = GameManager.player_ship
			player_lod.current_lod = ShipLODData.LODLevel.LOD0
			player_lod.position = GameManager.player_ship.global_position
			lod_mgr.register_ship(&"player_ship", player_lod)

	# Remove dynamically spawned children of Universe (stations, etc.)
	for child in universe.get_children():
		# Don't free the MultiMesh instance (child of Universe, managed by LOD manager)
		if child.name == "LOD2_MultiMesh":
			continue
		child.queue_free()

	# Clear NPCs via encounter manager
	var encounter_mgr := _get_encounter_manager()
	if encounter_mgr:
		encounter_mgr.clear_all_npcs()

	# Clear entity registry
	EntityRegistry.clear_all()

	# Re-register player (always persists)
	if GameManager.player_ship:
		EntityRegistry.register("player_ship", {
			"name": "Player Ship",
			"type": EntityRegistrySystem.EntityType.SHIP_PLAYER,
			"node": GameManager.player_ship,
			"radius": 15.0,
			"color": MapColors.PLAYER,
		})


func _build_connection_list(system_id: int) -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	var sys: Dictionary = galaxy.get_system(system_id)
	if sys.is_empty():
		return connections

	for conn_id in sys["connections"]:
		var conn_sys: Dictionary = galaxy.get_system(conn_id)
		if not conn_sys.is_empty():
			connections.append({
				"target_id": conn_id,
				"target_name": conn_sys["name"],
			})

	return connections


func _populate_system() -> void:
	var universe := GameManager.universe_node
	if universe == null:
		return

	# Spawn stations
	for i in current_system_data.stations.size():
		var station_data: Dictionary = current_system_data.stations[i]
		var station := SpaceStation.new()
		station.name = "Station_%d" % i
		station.station_name = station_data["name"]

		# Position station in orbit (use orbital angle for initial position)
		var orbit_r: float = station_data["orbital_radius"]
		var angle: float = station_data.get("orbital_angle", 0.0)
		station.transform = Transform3D.IDENTITY
		station.position = Vector3(cos(angle) * orbit_r, 0, sin(angle) * orbit_r)
		station.scale = Vector3(100, 100, 100)  # Match original AlphaStation scale

		universe.add_child(station)

	# Spawn jump gates
	for i in current_system_data.jump_gates.size():
		var gate_data: Dictionary = current_system_data.jump_gates[i]
		var gate := JumpGate.new()
		gate.name = "JumpGate_%d" % i
		gate.setup(gate_data)
		gate.player_nearby.connect(_on_gate_player_nearby)
		gate.player_left.connect(_on_gate_player_left)
		universe.add_child(gate)

	# Spawn star impostor (child of main_scene, NOT Universe — avoids FloatingOrigin shift)
	_active_star = SystemStar.new()
	_active_star.name = "SystemStar"
	_active_star.setup(
		current_system_data.star_color,
		current_system_data.star_radius,
		current_system_data.star_luminosity
	)
	GameManager.main_scene.add_child(_active_star)


func _position_player() -> void:
	var ship := GameManager.player_ship
	if ship == null:
		return

	# Spawn near first station or at origin
	if current_system_data.stations.size() > 0:
		var st: Dictionary = current_system_data.stations[0]
		var orbit_r: float = st["orbital_radius"]
		var angle: float = st.get("orbital_angle", 0.0)
		var station_pos := Vector3(cos(angle) * orbit_r, 0, sin(angle) * orbit_r)
		var offset := Vector3(0, 100, 500)  # Offset from station (clear of model)
		ship.global_position = station_pos + offset
	else:
		ship.global_position = Vector3(0, 0, 500)

	# Reset velocity
	if ship is RigidBody3D:
		ship.linear_velocity = Vector3.ZERO
		ship.angular_velocity = Vector3.ZERO


func _configure_environment() -> void:
	# Find the SpaceEnvironment (root of main scene has the script)
	var main: Node3D = GameManager.main_scene
	if main is SpaceEnvironment:
		main.configure_for_system(current_system_data)


func _register_system_entities() -> void:
	# Star (with node reference to impostor)
	EntityRegistry.register("star_0", {
		"name": current_system_data.star_name,
		"type": EntityRegistrySystem.EntityType.STAR,
		"pos_x": 0.0,
		"pos_y": 0.0,
		"pos_z": 0.0,
		"node": _active_star,
		"radius": current_system_data.star_radius,
		"color": current_system_data.star_color,
		"extra": {
			"spectral_class": current_system_data.star_spectral_class,
			"temperature": current_system_data.star_temperature,
			"luminosity": current_system_data.star_luminosity,
		},
	})

	# Stations
	var universe := GameManager.universe_node
	for i in current_system_data.stations.size():
		var station_data: Dictionary = current_system_data.stations[i]
		var node: Node3D = universe.get_node_or_null("Station_%d" % i) if universe else null
		EntityRegistry.register("station_%d" % i, {
			"name": station_data["name"],
			"type": EntityRegistrySystem.EntityType.STATION,
			"node": node,
			"orbital_radius": station_data["orbital_radius"],
			"orbital_period": station_data["orbital_period"],
			"orbital_angle": station_data.get("orbital_angle", 0.0),
			"orbital_parent": "star_0",
			"radius": 100.0,
			"color": MapColors.STATION_TEAL,
		})

	# Jump gates
	for i in current_system_data.jump_gates.size():
		var gate_data: Dictionary = current_system_data.jump_gates[i]
		var gate_node: Node3D = universe.get_node_or_null("JumpGate_%d" % i) if universe else null
		EntityRegistry.register("jump_gate_%d" % i, {
			"name": gate_data["name"],
			"type": EntityRegistrySystem.EntityType.JUMP_GATE,
			"node": gate_node,
			"pos_x": gate_data["pos_x"],
			"pos_y": gate_data["pos_y"],
			"pos_z": gate_data["pos_z"],
			"radius": 55.0,
			"color": MapColors.JUMP_GATE,
			"extra": {
				"target_system_id": gate_data["target_system_id"],
				"target_system_name": gate_data["target_system_name"],
			},
		})


func _spawn_encounters(danger_level: int) -> void:
	var encounter_mgr := _get_encounter_manager()
	if encounter_mgr == null:
		return
	encounter_mgr.spawn_system_encounters(danger_level, current_system_data)


func _get_encounter_manager() -> EncounterManager:
	var mgr := GameManager.get_node_or_null("EncounterManager")
	if mgr is EncounterManager:
		return mgr as EncounterManager
	return null


func _save_system_state() -> void:
	if current_system_id < 0:
		return
	_system_states[current_system_id] = {
		"visited": true,
	}


func has_visited(system_id: int) -> bool:
	return _system_states.has(system_id) and _system_states[system_id].get("visited", false)


# === Gate proximity API (used by GameManager for J key, FlightHUD for prompt) ===

func can_gate_jump() -> bool:
	return _active_gate_target_id >= 0 and not _is_transitioning


func get_gate_target_name() -> String:
	return _active_gate_target_name


func get_gate_target_id() -> int:
	return _active_gate_target_id


func _on_gate_player_nearby(target_id: int, target_name: String) -> void:
	_active_gate_target_id = target_id
	_active_gate_target_name = target_name


func _on_gate_player_left() -> void:
	_active_gate_target_id = -1
	_active_gate_target_name = ""
