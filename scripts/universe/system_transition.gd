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

# Origin tracking: which system we jumped FROM (for gate arrival positioning)
var _origin_system_id: int = -1

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

# Wormhole proximity state
var _active_wormhole: WormholeGate = null
var _wormhole_nearby: bool = false

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
	_origin_system_id = current_system_id

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

	# 5. Resolve system data: override .tres > procedural
	var galaxy_sys: Dictionary = galaxy.get_system(_pending_target_id)
	var override_data := SystemDataRegistry.get_override(_pending_target_id)
	if override_data:
		current_system_data = override_data
	else:
		var connections := _build_connection_list(_pending_target_id)
		current_system_data = SystemGenerator.generate(galaxy_sys["seed"], connections)
		# Override names with galaxy-consistent names
		current_system_data.system_name = galaxy_sys["name"]
		current_system_data.star_name = galaxy_sys["name"]

	current_system_id = _pending_target_id

	# 6. Populate scene
	_populate_system()

	# 7. Position player
	_position_player()

	# 8. Configure environment
	_configure_environment()

	# 9. Register entities
	_register_system_entities()

	# 10. Spawn encounters based on danger level
	_spawn_encounters(galaxy_sys["danger_level"])

	# 11. Notify
	system_loaded.emit(current_system_id)

	# If we were in a fade transition, start fade in
	if _transition_phase == 2:
		_transition_phase = 3
		_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cleanup_current_system() -> void:
	var universe := GameManager.universe_node
	if universe == null:
		return

	# Clean up asteroid fields
	var asteroid_mgr := GameManager.get_node_or_null("AsteroidFieldManager") as AsteroidFieldManager
	if asteroid_mgr:
		asteroid_mgr.clear_all()

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
		if child.name == "LOD2_MultiMesh":
			continue
		child.queue_free()

	# Clear NPCs via encounter manager
	var encounter_mgr := _get_encounter_manager()
	if encounter_mgr:
		encounter_mgr.clear_all_npcs()

	# Clear structure authority
	var struct_auth := GameManager.get_node_or_null("StructureAuthority") as StructureAuthority
	if struct_auth:
		struct_auth.clear_all()

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

	var origin_x: float = sys.get("x", 0.0)
	var origin_y: float = sys.get("y", 0.0)

	for conn_id in sys["connections"]:
		var conn_sys: Dictionary = galaxy.get_system(conn_id)
		if not conn_sys.is_empty():
			connections.append({
				"target_id": conn_id,
				"target_name": conn_sys["name"],
				"origin_x": origin_x,
				"origin_y": origin_y,
				"target_x": conn_sys.get("x", 0.0),
				"target_y": conn_sys.get("y", 0.0),
			})

	return connections


func _populate_system() -> void:
	var universe := GameManager.universe_node
	if universe == null:
		return

	# Spawn stations
	for i in current_system_data.stations.size():
		var sd: StationData = current_system_data.stations[i]
		var station := SpaceStation.new()
		station.name = "Station_%d" % i
		station.station_name = sd.station_name
		station.station_type = sd.station_type  # Configures health preset

		# Load or create station equipment (persistent across system changes)
		var eq_key := "system_%d_station_%d" % [current_system_id, i]
		if GameManager._station_equipments.has(eq_key):
			station.station_equipment = GameManager._station_equipments[eq_key]
		else:
			station.station_equipment = StationEquipment.create_empty(eq_key, sd.station_type)
			GameManager._station_equipments[eq_key] = station.station_equipment

		var orbit_r: float = sd.orbital_radius
		var angle: float = sd.orbital_angle
		station.transform = Transform3D.IDENTITY
		station.position = Vector3(cos(angle) * orbit_r, 0, sin(angle) * orbit_r)
		station.scale = Vector3(100, 100, 100)

		universe.add_child(station)

	# Spawn jump gates
	for i in current_system_data.jump_gates.size():
		var gd: JumpGateData = current_system_data.jump_gates[i]
		var gate := JumpGate.new()
		gate.name = "JumpGate_%d" % i
		gate.player_nearby.connect(_on_gate_player_nearby)
		gate.player_left.connect(_on_gate_player_left)
		universe.add_child(gate)
		gate.setup_from_data(gd)

	# Spawn wormhole gate if this system has one
	_wormhole_nearby = false
	_active_wormhole = null
	var galaxy_sys: Dictionary = galaxy.get_system(current_system_id)
	if not galaxy_sys.is_empty() and galaxy_sys.has("wormhole_target"):
		var wh_data: Dictionary = galaxy_sys["wormhole_target"]
		if wh_data.has("seed"):
			var wormhole := WormholeGate.new()
			wormhole.name = "WormholeGate"
			var sys_angle: float = atan2(galaxy_sys["y"], galaxy_sys["x"]) + PI
			var gate_dist: float = 25_000_000.0
			wormhole.global_position = Vector3(
				cos(sys_angle) * gate_dist,
				0,
				sin(sys_angle) * gate_dist,
			)
			wormhole.setup({
				"target_seed": wh_data.get("seed", 0),
				"target_name": wh_data.get("name", "Unknown Galaxy"),
				"target_url": wh_data.get("url", ""),
				"pos_x": wormhole.global_position.x,
				"pos_y": 0.0,
				"pos_z": wormhole.global_position.z,
			})
			wormhole.player_nearby_wormhole.connect(_on_wormhole_player_nearby.bind(wormhole))
			wormhole.player_left_wormhole.connect(_on_wormhole_player_left)
			universe.add_child(wormhole)

			EntityRegistry.register("wormhole_0", {
				"name": "Wormhole → " + wh_data.get("name", "?"),
				"type": EntityRegistrySystem.EntityType.JUMP_GATE,
				"node": wormhole,
				"pos_x": wormhole.global_position.x,
				"pos_y": 0.0,
				"pos_z": wormhole.global_position.z,
				"radius": 75.0,
				"color": Color(0.7, 0.2, 1.0),
			})

	# Spawn asteroid fields
	var asteroid_mgr := GameManager.get_node_or_null("AsteroidFieldManager") as AsteroidFieldManager
	if asteroid_mgr:
		asteroid_mgr.set_system_seed(current_system_data.seed_value)
		for i in current_system_data.asteroid_belts.size():
			var belt: AsteroidBeltData = current_system_data.asteroid_belts[i]
			var field := _generate_asteroid_field(belt, i)
			asteroid_mgr.populate_field(field)

	# Spawn star impostor (child of main_scene, NOT Universe)
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

	# Try to spawn near the arrival gate (the gate pointing back to origin system)
	var spawned_at_gate: bool = false
	if _origin_system_id >= 0 and current_system_data:
		for gd in current_system_data.jump_gates:
			if gd.target_system_id == _origin_system_id:
				var gate_pos := Vector3(gd.pos_x, gd.pos_y, gd.pos_z)
				# Spawn 500m behind gate (away from system center)
				var dir_from_center := gate_pos.normalized()
				ship.global_position = gate_pos + dir_from_center * 500.0
				# Orient toward system center
				var look_target := Vector3.ZERO
				var forward := (look_target - ship.global_position).normalized()
				if forward.length_squared() > 0.001:
					ship.look_at(look_target, Vector3.UP)
				spawned_at_gate = true
				break

	_origin_system_id = -1  # Clear after use

	# Fallback: spawn near first station
	if not spawned_at_gate:
		if current_system_data.stations.size() > 0:
			var st: StationData = current_system_data.stations[0]
			var orbit_r: float = st.orbital_radius
			var angle: float = st.orbital_angle
			var station_pos := Vector3(cos(angle) * orbit_r, 0, sin(angle) * orbit_r)
			var offset := Vector3(0, 100, 500)
			ship.global_position = station_pos + offset
		else:
			ship.global_position = Vector3(0, 0, 500)

	if ship is RigidBody3D:
		ship.linear_velocity = Vector3.ZERO
		ship.angular_velocity = Vector3.ZERO


func _configure_environment() -> void:
	var main: Node3D = GameManager.main_scene
	if main is SpaceEnvironment:
		main.configure_for_system(current_system_data, current_system_id)


func _register_system_entities() -> void:
	# Star
	EntityRegistry.register("star_0", {
		"name": current_system_data.star_name,
		"type": EntityRegistrySystem.EntityType.STAR,
		"pos_x": 0.0,
		"pos_y": 0.0,
		"pos_z": 0.0,
		"radius": current_system_data.star_radius,
		"color": current_system_data.star_color,
		"extra": {
			"spectral_class": current_system_data.star_spectral_class,
			"temperature": current_system_data.star_temperature,
			"luminosity": current_system_data.star_luminosity,
		},
	})

	# Planets
	for i in current_system_data.planets.size():
		var pd: PlanetData = current_system_data.planets[i]
		EntityRegistry.register("planet_%d" % i, {
			"name": pd.planet_name,
			"type": EntityRegistrySystem.EntityType.PLANET,
			"orbital_radius": pd.orbital_radius,
			"orbital_period": pd.orbital_period,
			"orbital_angle": pd.orbital_angle,
			"orbital_parent": "star_0",
			"radius": pd.radius,
			"color": pd.color,
			"extra": {
				"planet_type": pd.get_type_string(),
				"has_rings": pd.has_rings,
			},
		})

	# Stations
	var universe := GameManager.universe_node
	var struct_auth := GameManager.get_node_or_null("StructureAuthority") as StructureAuthority
	for i in current_system_data.stations.size():
		var sd: StationData = current_system_data.stations[i]
		var node: Node3D = universe.get_node_or_null("Station_%d" % i) if universe else null
		EntityRegistry.register("station_%d" % i, {
			"name": sd.station_name,
			"type": EntityRegistrySystem.EntityType.STATION,
			"node": node,
			"orbital_radius": sd.orbital_radius,
			"orbital_period": sd.orbital_period,
			"orbital_angle": sd.orbital_angle,
			"orbital_parent": "star_0",
			"radius": 100.0,
			"color": MapColors.STATION_TEAL,
			"extra": {
				"station_type": sd.get_type_string(),
				"station_index": i,
			},
		})
		# Register with StructureAuthority for multiplayer sync
		if struct_auth and node:
			struct_auth.register_structure("Station_%d" % i, current_system_id, sd.station_type, node)

	# Jump gates
	for i in current_system_data.jump_gates.size():
		var gd: JumpGateData = current_system_data.jump_gates[i]
		var gate_node: Node3D = universe.get_node_or_null("JumpGate_%d" % i) if universe else null
		EntityRegistry.register("jump_gate_%d" % i, {
			"name": gd.gate_name,
			"type": EntityRegistrySystem.EntityType.JUMP_GATE,
			"node": gate_node,
			"pos_x": gd.pos_x,
			"pos_y": gd.pos_y,
			"pos_z": gd.pos_z,
			"radius": 55.0,
			"color": MapColors.JUMP_GATE,
			"extra": {
				"target_system_id": gd.target_system_id,
				"target_system_name": gd.target_system_name,
			},
		})

	# Asteroid belts
	for i in current_system_data.asteroid_belts.size():
		var bd: AsteroidBeltData = current_system_data.asteroid_belts[i]
		EntityRegistry.register("asteroid_belt_%d" % i, {
			"name": bd.belt_name,
			"type": EntityRegistrySystem.EntityType.ASTEROID_BELT,
			"orbital_radius": bd.orbital_radius,
			"orbital_parent": "star_0",
			"radius": bd.width,
			"color": MapColors.ASTEROID_BELT,
			"extra": {
				"width": bd.width,
				"dominant_resource": String(bd.dominant_resource),
				"secondary_resource": String(bd.secondary_resource),
				"rare_resource": String(bd.rare_resource),
				"zone": bd.zone,
				"asteroid_count": bd.asteroid_count,
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


# === Gate proximity API ===

func can_gate_jump() -> bool:
	return _active_gate_target_id >= 0 and not _is_transitioning


func get_gate_target_name() -> String:
	return _active_gate_target_name


func get_gate_target_id() -> int:
	return _active_gate_target_id


signal gate_proximity_entered(target_id: int)

func _on_gate_player_nearby(target_id: int, target_name: String) -> void:
	_active_gate_target_id = target_id
	_active_gate_target_name = target_name
	gate_proximity_entered.emit(target_id)


func _on_gate_player_left() -> void:
	_active_gate_target_id = -1
	_active_gate_target_name = ""


# === Wormhole proximity API ===

func can_wormhole_jump() -> bool:
	return _wormhole_nearby and _active_wormhole != null and not _is_transitioning


func get_wormhole_target_name() -> String:
	if _active_wormhole:
		return _active_wormhole.target_galaxy_name
	return ""


func get_active_wormhole() -> WormholeGate:
	return _active_wormhole


func _on_wormhole_player_nearby(_target_name: String, wormhole: WormholeGate) -> void:
	_wormhole_nearby = true
	_active_wormhole = wormhole


func _on_wormhole_player_left() -> void:
	_wormhole_nearby = false
	_active_wormhole = null


# =============================================================================
# ASTEROID FIELD GENERATION
# =============================================================================
func _generate_asteroid_field(belt: AsteroidBeltData, index: int) -> AsteroidFieldData:
	var field := AsteroidFieldData.new()
	field.field_name = belt.belt_name
	field.field_id = belt.field_id if belt.field_id != &"" else StringName("belt_%d" % index)
	field.orbital_radius = belt.orbital_radius
	field.width = belt.width
	field.dominant_resource = belt.dominant_resource
	field.secondary_resource = belt.secondary_resource
	field.rare_resource = belt.rare_resource
	return field
