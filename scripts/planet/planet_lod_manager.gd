class_name PlanetLODManager
extends Node

# =============================================================================
# Planet LOD Manager — Decides when to show impostor vs full planet body
# Spawns/despawns PlanetBody based on distance. Crossfades between them.
# =============================================================================

const BODY_SPAWN_DISTANCE: float = 100_000.0     # 100 km — spawn PlanetBody
const BODY_DESPAWN_DISTANCE: float = 120_000.0    # 120 km — despawn (hysteresis)
const FADE_DURATION: float = 2.0                  # Seconds for crossfade (after body is ready)
const BODY_READY_WAIT: float = 3.0                # Max time to wait for body chunks before fading

var _planets: Array[Dictionary] = []
# Each: { "data": PlanetData, "index": int, "entity_id": String,
#          "impostor": PlanetImpostor, "body": PlanetBody, "state": int,
#          "fade_t": float, "wait_t": float, "system_seed": int }

enum State { IMPOSTOR, WAITING_BODY, FADING_IN, BODY_ACTIVE, DESPAWNING_BODY }

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5  # Check distances every 0.5s


func register_planet(pd: PlanetData, index: int, entity_id: String, impostor: PlanetImpostor, system_seed: int) -> void:
	_planets.append({
		"data": pd,
		"index": index,
		"entity_id": entity_id,
		"impostor": impostor,
		"body": null,
		"state": State.IMPOSTOR,
		"fade_t": 0.0,
		"wait_t": 0.0,
		"system_seed": system_seed,
	})


func clear_all() -> void:
	for planet in _planets:
		if planet["body"] and is_instance_valid(planet["body"]):
			(planet["body"] as PlanetBody).cleanup()
			planet["body"].queue_free()
	_planets.clear()


func _process(delta: float) -> void:
	if _planets.is_empty():
		return

	# Distance checks (throttled)
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_check_distances()

	# Update fades
	_update_fades(delta)


func _check_distances() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	var cam_universe_x: float = float(FloatingOrigin.origin_offset_x) + cam_pos.x
	var cam_universe_y: float = float(FloatingOrigin.origin_offset_y) + cam_pos.y
	var cam_universe_z: float = float(FloatingOrigin.origin_offset_z) + cam_pos.z

	for planet in _planets:
		# Read current orbital position from EntityRegistry (single source of truth)
		var pos: Array = EntityRegistry.get_position(planet["entity_id"])
		var px: float = pos[0]
		var py: float = pos[1]
		var pz: float = pos[2]

		var dx: float = cam_universe_x - px
		var dy: float = cam_universe_y - py
		var dz: float = cam_universe_z - pz
		var dist: float = sqrt(dx * dx + dy * dy + dz * dz)

		var render_radius: float = (planet["data"] as PlanetData).get_render_radius()
		var spawn_dist: float = maxf(BODY_SPAWN_DISTANCE, render_radius * 3.0)
		var despawn_dist: float = spawn_dist * 1.2

		match planet["state"]:
			State.IMPOSTOR:
				if dist < spawn_dist:
					_spawn_body(planet)
					planet["state"] = State.WAITING_BODY
					planet["wait_t"] = 0.0
					planet["fade_t"] = 0.0
			State.BODY_ACTIVE:
				if dist > despawn_dist:
					_despawn_body(planet)
					planet["state"] = State.DESPAWNING_BODY
					planet["fade_t"] = 0.0


func _update_fades(delta: float) -> void:
	for planet in _planets:
		match planet["state"]:
			State.WAITING_BODY:
				# Body is spawned but building terrain chunks in the background.
				# Keep impostor fully visible. Wait until body has some chunks
				# or BODY_READY_WAIT expires, then start fading.
				planet["wait_t"] = planet["wait_t"] + delta
				var body: PlanetBody = planet["body"]
				var body_ready: bool = planet["wait_t"] >= BODY_READY_WAIT
				if body and is_instance_valid(body):
					# Check if body has built at least a few chunks
					var chunk_count: int = 0
					for face in body._faces:
						chunk_count += face.get_chunk_count()
					if chunk_count >= 6:
						body_ready = true
				if body_ready:
					# Body ready: hide body initially for the crossfade
					if body and is_instance_valid(body):
						body.visible = true
					planet["state"] = State.FADING_IN
					planet["fade_t"] = 0.0

			State.FADING_IN:
				planet["fade_t"] = minf(planet["fade_t"] + delta / FADE_DURATION, 1.0)
				# Fade out impostor → reveal body underneath
				if planet["impostor"] and is_instance_valid(planet["impostor"]):
					planet["impostor"].fade_alpha = 1.0 - planet["fade_t"]
				if planet["fade_t"] >= 1.0:
					planet["state"] = State.BODY_ACTIVE
					if planet["impostor"] and is_instance_valid(planet["impostor"]):
						planet["impostor"].visible = false

			State.DESPAWNING_BODY:
				planet["fade_t"] = minf(planet["fade_t"] + delta / FADE_DURATION, 1.0)
				# Fade in impostor, fade out body
				if planet["impostor"] and is_instance_valid(planet["impostor"]):
					planet["impostor"].fade_alpha = planet["fade_t"]
					planet["impostor"].visible = true
				if planet["fade_t"] >= 1.0:
					planet["state"] = State.IMPOSTOR
					if planet["body"] and is_instance_valid(planet["body"]):
						(planet["body"] as PlanetBody).cleanup()
						planet["body"].queue_free()
						planet["body"] = null


func _spawn_body(planet: Dictionary) -> void:
	var pd: PlanetData = planet["data"]
	var pos: Array = EntityRegistry.get_position(planet["entity_id"])
	var body := PlanetBody.new()
	body.name = "PlanetBody_%d" % planet["index"]
	body.entity_id = planet["entity_id"]
	body.setup(pd, planet["index"], pos[0], pos[1], pos[2], planet["system_seed"])

	# Add to Universe node (gets shifted by FloatingOrigin)
	var universe := GameManager.universe_node
	if universe:
		universe.add_child(body)
	else:
		add_child(body)

	# CRITICAL: Set correct position IMMEDIATELY after add_child, before any
	# _process or _physics_process runs. Without this, the body sits at (0,0,0)
	# for 1 frame which triggers the ship's emergency planet-pushout.
	body.global_position = Vector3(
		float(pos[0]) - float(FloatingOrigin.origin_offset_x),
		float(pos[1]) - float(FloatingOrigin.origin_offset_y),
		float(pos[2]) - float(FloatingOrigin.origin_offset_z)
	)
	# Start HIDDEN — LOD manager will make it visible when terrain chunks are ready
	body._is_active = true
	body.visible = false

	planet["body"] = body
	print("[PlanetLOD] Spawned PlanetBody_%d (radius=%.0fkm)" % [planet["index"], pd.get_render_radius() / 1000.0])


func _despawn_body(planet: Dictionary) -> void:
	print("[PlanetLOD] Despawning PlanetBody_%d" % planet["index"])
	if planet["body"] and is_instance_valid(planet["body"]):
		# Soft deactivate: stop processing but KEEP VISIBLE while impostor fades in.
		# Full cleanup happens when fade completes (in _update_fades → DESPAWNING_BODY).
		(planet["body"] as PlanetBody).deactivate_soft()


## Get the nearest active PlanetBody (or null if none spawned).
func get_nearest_body(world_pos: Vector3) -> PlanetBody:
	var best: PlanetBody = null
	var best_dist: float = INF

	for planet in _planets:
		if planet["state"] == State.IMPOSTOR or planet["state"] == State.DESPAWNING_BODY:
			continue
		var body: PlanetBody = planet["body"]
		if body == null or not is_instance_valid(body):
			continue
		var dist: float = world_pos.distance_to(body.global_position)
		if dist < best_dist:
			best_dist = dist
			best = body

	return best


## Get all active planet bodies.
func get_active_bodies() -> Array[PlanetBody]:
	var result: Array[PlanetBody] = []
	for planet in _planets:
		if planet["body"] and is_instance_valid(planet["body"]):
			result.append(planet["body"])
	return result
