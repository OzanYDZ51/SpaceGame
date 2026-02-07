class_name ShipLODManager
extends Node

# =============================================================================
# Ship LOD Manager - Central orchestrator for LOD, MultiMesh, and spatial grid.
# Manages all ships (player, NPCs, remote players) across 3 LOD tiers.
# =============================================================================

const LOD0_DISTANCE: float = 400.0
const LOD1_DISTANCE: float = 2000.0
const LOD0_MAX: int = 50
const LOD1_MAX: int = 200
const LOD_EVAL_INTERVAL: float = 0.2
const COMBAT_BRIDGE_RANGE: float = 1500.0
const COMBAT_BRIDGE_INTERVAL: float = 0.2
const MAX_PROMOTIONS_PER_TICK: int = 10

# --- State ---
var _grid: SpatialGrid = null
var _ships: Dictionary = {}  # StringName -> ShipLODData
var _player_id: StringName = &""

# --- MultiMesh ---
var _multimesh: MultiMesh = null
var _multimesh_instance: MultiMeshInstance3D = null
var _ship_mesh: Mesh = null

# --- Timers ---
var _lod_eval_timer: float = 0.0
var _combat_bridge_timer: float = 0.0

# --- References ---
var _universe_node: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_grid = SpatialGrid.new(500.0)
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func initialize(universe: Node3D) -> void:
	_universe_node = universe
	_load_ship_mesh()
	_setup_multimesh()


func _load_ship_mesh() -> void:
	var scene: PackedScene = load("res://assets/models/tie.glb")
	if scene == null:
		push_warning("ShipLODManager: Could not load tie.glb for MultiMesh")
		return
	var instance := scene.instantiate() as Node3D
	# Find the first MeshInstance3D and extract the mesh
	_ship_mesh = _find_first_mesh(instance)
	instance.queue_free()


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _find_first_mesh(child)
		if m:
			return m
	return null


func _setup_multimesh() -> void:
	if _ship_mesh == null:
		return
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = 0
	_multimesh.mesh = _ship_mesh

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "LOD2_MultiMesh"
	_multimesh_instance.multimesh = _multimesh
	# Cast shadows for large groups
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _universe_node:
		_universe_node.add_child(_multimesh_instance)


# =============================================================================
# PUBLIC API
# =============================================================================

func register_ship(id: StringName, data: ShipLODData) -> void:
	# If ship already exists (e.g. from LOD promotion), update node_ref instead
	if _ships.has(id):
		var existing: ShipLODData = _ships[id]
		if existing._is_promoting:
			# Factory re-registered during promotion — just update the node ref
			existing.node_ref = data.node_ref
			return
		# Truly duplicate — overwrite
		_grid.remove(id)
	_ships[id] = data
	_grid.insert(id, data.position, data)


func unregister_ship(id: StringName) -> void:
	if not _ships.has(id):
		return
	var data: ShipLODData = _ships[id]
	# If the ship has a scene node in LOD0/1, free it
	if data.node_ref and is_instance_valid(data.node_ref) and data.current_lod != ShipLODData.LODLevel.LOD2:
		if id != _player_id:
			data.node_ref.queue_free()
	_grid.remove(id)
	_ships.erase(id)


func set_player_id(id: StringName) -> void:
	_player_id = id


func get_ship_data(id: StringName) -> ShipLODData:
	return _ships.get(id) as ShipLODData


func get_ships_in_radius(center: Vector3, radius: float) -> Array[StringName]:
	return _grid.query_radius(center, radius)


func get_nearest_ships(center: Vector3, radius: float, count: int, exclude_id: StringName = &"") -> Array[Dictionary]:
	var results := _grid.query_nearest(center, radius, count + 1)
	# Filter out exclude_id
	if exclude_id != &"":
		var filtered: Array[Dictionary] = []
		for r in results:
			if r["id"] != exclude_id:
				filtered.append(r)
		if filtered.size() > count:
			filtered.resize(count)
		return filtered
	if results.size() > count:
		results.resize(count)
	return results


func get_ship_position(id: StringName) -> Vector3:
	if _ships.has(id):
		var data: ShipLODData = _ships[id]
		if data.node_ref and is_instance_valid(data.node_ref):
			return data.node_ref.global_position
		return data.position
	return Vector3.ZERO


func get_ship_faction(id: StringName) -> StringName:
	if _ships.has(id):
		return (_ships[id] as ShipLODData).faction
	return &""


func is_ship_alive(id: StringName) -> bool:
	if _ships.has(id):
		return not (_ships[id] as ShipLODData).is_dead
	return false


func get_all_ship_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _ships:
		result.append(id)
	return result


func get_ship_count() -> int:
	return _ships.size()


func clear_all() -> void:
	# Free LOD0/1 nodes that aren't the player
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if id == _player_id:
			continue
		if data.node_ref and is_instance_valid(data.node_ref):
			data.node_ref.queue_free()
	_ships.clear()
	_grid.clear()
	# Update multimesh to show nothing
	if _multimesh:
		_multimesh.instance_count = 0


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return

	# Sync LOD0/1 node positions into grid + data
	_sync_node_positions()

	# LOD evaluation (every 0.2s)
	_lod_eval_timer -= delta
	if _lod_eval_timer <= 0.0:
		_lod_eval_timer = LOD_EVAL_INTERVAL
		_evaluate_lod_levels()

	# Tick LOD2 simple AI (every frame, cheap)
	_tick_lod2_ai(delta)

	# Update MultiMesh (every frame)
	_update_multimesh()


func _physics_process(delta: float) -> void:
	# Combat bridge for LOD2 vs LOD2 (every 0.2s)
	_combat_bridge_timer -= delta
	if _combat_bridge_timer <= 0.0:
		_combat_bridge_timer = COMBAT_BRIDGE_INTERVAL
		_tick_combat_bridge()


# =============================================================================
# LOD EVALUATION
# =============================================================================

func _sync_node_positions() -> void:
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if data.node_ref and is_instance_valid(data.node_ref):
			data.position = data.node_ref.global_position
			_grid.update_position(id, data.position)
		elif data.current_lod == ShipLODData.LODLevel.LOD2:
			# LOD2: position updated by tick_simple_ai, just sync grid
			_grid.update_position(id, data.position)


func _evaluate_lod_levels() -> void:
	if _camera == null:
		return
	var cam_pos := _camera.global_position

	# Calculate distances for all ships
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		data.distance_to_camera = cam_pos.distance_to(data.position)

	# Sort ships by distance (closest first)
	var sorted_ids: Array[StringName] = []
	for id: StringName in _ships:
		sorted_ids.append(id)
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _ships[a].distance_to_camera < _ships[b].distance_to_camera)

	# Assign LOD levels based on distance + budget
	var lod0_count: int = 0
	var lod1_count: int = 0
	var promotions_this_tick: int = 0

	for id in sorted_ids:
		var data: ShipLODData = _ships[id]

		# Player is always LOD0
		if id == _player_id:
			if data.current_lod != ShipLODData.LODLevel.LOD0:
				_promote_to_lod0(id, data)
			continue

		# Determine target LOD
		var target_lod: ShipLODData.LODLevel
		if data.distance_to_camera < LOD0_DISTANCE and lod0_count < LOD0_MAX:
			target_lod = ShipLODData.LODLevel.LOD0
		elif data.distance_to_camera < LOD1_DISTANCE and lod1_count < LOD1_MAX:
			target_lod = ShipLODData.LODLevel.LOD1
		else:
			target_lod = ShipLODData.LODLevel.LOD2

		# Apply transition (throttle promotions to avoid frame spike)
		if target_lod != data.current_lod:
			var is_promotion := target_lod < data.current_lod
			if is_promotion and promotions_this_tick >= MAX_PROMOTIONS_PER_TICK:
				pass  # Defer to next tick
			else:
				_transition_lod(id, data, target_lod)
				if is_promotion:
					promotions_this_tick += 1

		# Count after potential transition
		match data.current_lod:
			ShipLODData.LODLevel.LOD0: lod0_count += 1
			ShipLODData.LODLevel.LOD1: lod1_count += 1


func _transition_lod(id: StringName, data: ShipLODData, target: ShipLODData.LODLevel) -> void:
	var current := data.current_lod
	if current == ShipLODData.LODLevel.LOD0 and target == ShipLODData.LODLevel.LOD1:
		_demote_lod0_to_lod1(id, data)
	elif current == ShipLODData.LODLevel.LOD0 and target == ShipLODData.LODLevel.LOD2:
		_demote_lod0_to_lod1(id, data)
		_demote_lod1_to_lod2(id, data)
	elif current == ShipLODData.LODLevel.LOD1 and target == ShipLODData.LODLevel.LOD0:
		_promote_to_lod0(id, data)
	elif current == ShipLODData.LODLevel.LOD1 and target == ShipLODData.LODLevel.LOD2:
		_demote_lod1_to_lod2(id, data)
	elif current == ShipLODData.LODLevel.LOD2 and target == ShipLODData.LODLevel.LOD1:
		_promote_lod2_to_lod1(id, data)
	elif current == ShipLODData.LODLevel.LOD2 and target == ShipLODData.LODLevel.LOD0:
		_promote_lod2_to_lod1(id, data)
		_promote_to_lod0(id, data)


# =============================================================================
# LOD TRANSITIONS
# =============================================================================

func _demote_lod0_to_lod1(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node == null or not is_instance_valid(node):
		data.current_lod = ShipLODData.LODLevel.LOD1
		return

	# Hide lights (GPU savings)
	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = false

	# Keep physics active but reduce collision (can be hit, doesn't push)
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS  # Projectiles can hit me
		rb.collision_mask = 0  # I don't collide with anything

	# Keep AI active for movement, disable weapons
	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.weapons_enabled = false

	data.current_lod = ShipLODData.LODLevel.LOD1


func _demote_lod1_to_lod2(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node and is_instance_valid(node):
		# Capture latest state before removing
		data.capture_from_node(node)
		# Unregister from EntityRegistry BEFORE freeing (prevents freed ref access)
		EntityRegistry.unregister(String(node.name))
		node.queue_free()
	data.node_ref = null
	data.current_lod = ShipLODData.LODLevel.LOD2


func _promote_lod2_to_lod1(id: StringName, data: ShipLODData) -> void:
	if data.is_dead:
		return

	# Mark as promoting to prevent duplicate registration
	data._is_promoting = true

	var node: Node3D = null
	if data.is_remote_player:
		# Recreate RemotePlayerShip
		var remote := RemotePlayerShip.new()
		remote.peer_id = data.peer_id
		remote.set_player_name(data.display_name)
		remote.name = String(id)
		node = remote
	else:
		# Recreate NPC ship via factory (skip LOD/EntityRegistry — we manage it)
		var parent := _universe_node if _universe_node else get_tree().current_scene
		node = ShipFactory.spawn_npc_ship(
			data.ship_class, data.behavior_name, data.position, parent, data.faction, true
		)
		if node == null:
			data._is_promoting = false
			return
		# Override factory name to match our LOD tracking id
		node.name = String(id)

	if data.is_remote_player and _universe_node:
		_universe_node.add_child(node)

	# Restore state
	node.global_position = data.position
	if node is RigidBody3D:
		(node as RigidBody3D).linear_velocity = data.velocity

	# Apply LOD1 restrictions (move + evade, no weapons or lights)
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS  # Projectiles can hit me
		rb.collision_mask = 0  # I don't collide with anything

	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = false

	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.weapons_enabled = false  # Move but don't fire
		brain.set_patrol_area(data.ai_patrol_center, data.ai_patrol_radius)

	data.node_ref = node
	data.current_lod = ShipLODData.LODLevel.LOD1
	data._is_promoting = false


func _promote_to_lod0(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node == null or not is_instance_valid(node):
		return

	# Re-enable lights
	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = true

	# Full collision
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS
		rb.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS

	# Full AI with weapons
	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.set_process(true)
		brain.weapons_enabled = true

	data.current_lod = ShipLODData.LODLevel.LOD0


# =============================================================================
# MULTIMESH (LOD2 rendering)
# =============================================================================

func _update_multimesh() -> void:
	if _multimesh == null:
		return

	# Gather LOD2 ships
	var lod2_ships: Array[ShipLODData] = []
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if data.current_lod == ShipLODData.LODLevel.LOD2 and not data.is_dead:
			lod2_ships.append(data)

	var count := lod2_ships.size()
	# Grow buffer with headroom to avoid constant reallocation as ships die
	if _multimesh.instance_count < count:
		_multimesh.instance_count = count + 128
	_multimesh.visible_instance_count = count

	for i in count:
		var data: ShipLODData = lod2_ships[i]
		var xform := Transform3D(data.rotation_basis, data.position)
		xform = xform.scaled_local(Vector3.ONE * data.model_scale)
		_multimesh.set_instance_transform(i, xform)
		_multimesh.set_instance_color(i, data.color_tint)


# =============================================================================
# LOD2 SIMPLE AI
# =============================================================================

func _tick_lod2_ai(delta: float) -> void:
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if data.current_lod == ShipLODData.LODLevel.LOD2 and not data.is_remote_player:
			data.tick_simple_ai(delta)


# =============================================================================
# COMBAT BRIDGE (LOD2 statistical combat)
# =============================================================================

func _tick_combat_bridge() -> void:
	# DPS lookup by ship class
	var class_dps := {
		&"Scout": 8.0,
		&"Interceptor": 12.0,
		&"Fighter": 18.0,
		&"Bomber": 25.0,
		&"Corvette": 40.0,
		&"Frigate": 65.0,
		&"Cruiser": 100.0,
	}

	var dead_ids: Array[StringName] = []

	for id: StringName in _ships.duplicate():
		var data: ShipLODData = _ships.get(id)
		if data == null:
			continue
		if data.current_lod == ShipLODData.LODLevel.LOD0:
			continue  # LOD0 ships fight with real AI + projectiles
		if data.is_dead or data.is_remote_player:
			continue

		# Find NEAREST enemy only (not all — prevents N² damage explosion)
		var nearby := _grid.query_radius(data.position, COMBAT_BRIDGE_RANGE)
		var best_id: StringName = &""
		var best_dist_sq: float = INF
		for other_id in nearby:
			if other_id == id or other_id == _player_id:
				continue
			var other: ShipLODData = _ships.get(other_id)
			if other == null or other.is_dead:
				continue
			if other.faction == data.faction:
				continue
			var d_sq := data.position.distance_squared_to(other.position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_id = other_id

		if best_id == &"":
			continue

		var target: ShipLODData = _ships.get(best_id)
		if target == null:
			continue

		# Steer toward target (LOD2 ships converge visually on radar)
		var to_target := target.position - data.position
		if to_target.length_squared() > 100.0:
			data.velocity = data.velocity.lerp(to_target.normalized() * 60.0, COMBAT_BRIDGE_INTERVAL * 0.5)

		# Apply statistical damage (single target, ~13s to kill with 2 attackers)
		var dps: float = class_dps.get(data.ship_class, 15.0)
		var damage_this_tick := dps * COMBAT_BRIDGE_INTERVAL
		if target.shield_ratio > 0.0:
			target.shield_ratio = maxf(target.shield_ratio - damage_this_tick * 0.008, 0.0)
		else:
			target.hull_ratio = maxf(target.hull_ratio - damage_this_tick * 0.012, 0.0)

		if target.hull_ratio <= 0.0:
			target.is_dead = true
			if not dead_ids.has(best_id):
				dead_ids.append(best_id)

	for dead_id in dead_ids:
		unregister_ship(dead_id)


# =============================================================================
# FLOATING ORIGIN
# =============================================================================

func _on_origin_shifted(shift: Vector3) -> void:
	# LOD0/LOD1 nodes are shifted automatically (children of Universe)
	# LOD2 data-only ships need manual position shift
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if data.current_lod == ShipLODData.LODLevel.LOD2:
			data.position -= shift
			data.ai_patrol_center -= shift

	# Rebuild grid spatial indexing
	_grid.apply_origin_shift(shift)
