class_name ShipLODManager
extends Node

# =============================================================================
# Ship LOD Manager - Central orchestrator for LOD, MultiMesh, and spatial grid.
# Manages all ships (player, NPCs, remote players) across 4 LOD tiers.
#
# LOD0 (0-1000m):    Full mesh + lights + AI + weapons + collision
# LOD1 (1000-2000m): Mesh visible, no lights, AI + weapons active (tirs visibles!)
# LOD2 (2000-4000m): No mesh, data-only (HUD nav markers show names)
# LOD3 (>4000m):     Data-only (MultiMesh dot), combat bridge, radar only
# =============================================================================

const LOD0_DISTANCE: float = 1000.0
const LOD1_DISTANCE: float = 2000.0
const LOD2_DISTANCE: float = 4000.0
const LOD0_MAX: int = 50
const LOD1_MAX: int = 200
const LOD_EVAL_INTERVAL: float = 0.2
const COMBAT_BRIDGE_INTERVAL: float = 0.2
const MAX_PROMOTIONS_PER_TICK: int = 10

# --- State ---
var _grid: SpatialGrid = null
var _ships: Dictionary = {}  # StringName -> ShipLODData
var _player_id: StringName = &""

# --- Per-LOD ID sets (avoids full-dict iteration in hot loops) ---
var _lod0_ids: Dictionary = {}  # StringName -> true
var _lod1_ids: Dictionary = {}
var _lod2_ids: Dictionary = {}
var _lod3_ids: Dictionary = {}
var _node_ids: Dictionary = {}  # LOD0 + LOD1 (ships with node_ref)

# --- MultiMesh (LOD3 rendering) ---
var _multimesh: MultiMesh = null
var _multimesh_instance: MultiMeshInstance3D = null

# --- Timers ---
var _lod_eval_timer: float = 0.0
var _combat_bridge_timer: float = 0.0
var _ai_tick_timer: float = 0.0
var _multimesh_tick_timer: float = 0.0
const AI_TICK_INTERVAL: float = Constants.AI_TICK_INTERVAL
const MULTIMESH_TICK_INTERVAL: float = 0.05

# --- References ---
var _universe_node: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_grid = SpatialGrid.new(500.0)
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func initialize(universe: Node3D) -> void:
	_universe_node = universe
	_setup_multimesh()


func _setup_multimesh() -> void:
	# Billboard dot mesh — proper per-instance color support for LOD3 distant ships
	var dot_mesh := QuadMesh.new()
	dot_mesh.size = Vector2(8.0, 8.0)  # 8m billboard — visible as a dot at 4km+
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot_mat.vertex_color_use_as_albedo = true
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot_mat.no_depth_test = true
	dot_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	dot_mesh.material = dot_mat

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = 0
	_multimesh.mesh = dot_mesh

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "LOD3_MultiMesh"
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _universe_node:
		_universe_node.add_child(_multimesh_instance)


# =============================================================================
# PUBLIC API
# =============================================================================

func register_ship(id: StringName, data: ShipLODData) -> void:
	if _ships.has(id):
		var existing: ShipLODData = _ships[id]
		if existing.is_promoting:
			existing.node_ref = data.node_ref
			return
		_grid.remove(id)
	_ships[id] = data
	_grid.insert(id, data.position, data)
	_set_lod_set(id, data.current_lod)
	_ensure_entity_registered(id, data)


func unregister_ship(id: StringName) -> void:
	if not _ships.has(id):
		return
	var data: ShipLODData = _ships[id]
	if data.node_ref and is_instance_valid(data.node_ref):
		if id != _player_id:
			data.node_ref.queue_free()
	_grid.remove(id)
	_remove_from_lod_sets(id)
	_ships.erase(id)
	# Clean up EntityRegistry entry (safe to call even if not registered)
	EntityRegistry.unregister(String(id))


func set_player_id(id: StringName) -> void:
	_player_id = id


func get_ship_data(id: StringName) -> ShipLODData:
	return _ships.get(id) as ShipLODData


func get_ships_in_radius(center: Vector3, radius: float) -> Array[StringName]:
	return _grid.query_radius(center, radius)


func get_nearest_ships(center: Vector3, radius: float, count: int, exclude_id: StringName = &"") -> Array[Dictionary]:
	var results := _grid.query_nearest(center, radius, count + 1)
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
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		if id == _player_id:
			continue
		if data.node_ref and is_instance_valid(data.node_ref):
			data.node_ref.queue_free()
	_ships.clear()
	_grid.clear()
	_lod0_ids.clear()
	_lod1_ids.clear()
	_lod2_ids.clear()
	_lod3_ids.clear()
	_node_ids.clear()
	if _multimesh:
		_multimesh.instance_count = 0


func _set_lod_set(id: StringName, lod: ShipLODData.LODLevel) -> void:
	_lod0_ids.erase(id)
	_lod1_ids.erase(id)
	_lod2_ids.erase(id)
	_lod3_ids.erase(id)
	match lod:
		ShipLODData.LODLevel.LOD0:
			_lod0_ids[id] = true
			_node_ids[id] = true
		ShipLODData.LODLevel.LOD1:
			_lod1_ids[id] = true
			_node_ids[id] = true
		ShipLODData.LODLevel.LOD2:
			_lod2_ids[id] = true
			_node_ids.erase(id)
		ShipLODData.LODLevel.LOD3:
			_lod3_ids[id] = true
			_node_ids.erase(id)


func _remove_from_lod_sets(id: StringName) -> void:
	_lod0_ids.erase(id)
	_lod1_ids.erase(id)
	_lod2_ids.erase(id)
	_lod3_ids.erase(id)
	_node_ids.erase(id)


func _ensure_entity_registered(id: StringName, data: ShipLODData) -> void:
	if id == _player_id:
		return
	var sid := String(id)
	if not EntityRegistry.get_entity(sid).is_empty():
		return
	var ent_type: int = EntityRegistrySystem.EntityType.SHIP_NPC
	if data.is_remote_player:
		ent_type = EntityRegistrySystem.EntityType.SHIP_PLAYER
	var upos: Array = FloatingOrigin.to_universe_pos(data.position)
	EntityRegistry.register(sid, {
		"name": data.display_name,
		"type": ent_type,
		"node": data.node_ref,
		"pos_x": upos[0],
		"pos_y": upos[1],
		"pos_z": upos[2],
		"vel_x": float(data.velocity.x),
		"vel_y": float(data.velocity.y),
		"vel_z": float(data.velocity.z),
		"radius": 10.0,
		"color": ShipFactory._get_faction_map_color(data.faction),
		"extra": {
			"faction": String(data.faction),
			"ship_class": String(data.ship_class),
		},
	})


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	_sync_node_positions()

	_lod_eval_timer -= delta
	if _lod_eval_timer <= 0.0:
		_lod_eval_timer = LOD_EVAL_INTERVAL
		_evaluate_lod_levels()

	_ai_tick_timer -= delta
	if _ai_tick_timer <= 0.0:
		_ai_tick_timer = AI_TICK_INTERVAL
		_tick_data_only_ai(AI_TICK_INTERVAL)

	_multimesh_tick_timer -= delta
	if _multimesh_tick_timer <= 0.0:
		_multimesh_tick_timer = MULTIMESH_TICK_INTERVAL
		_update_multimesh()


func _physics_process(delta: float) -> void:
	_combat_bridge_timer -= delta
	if _combat_bridge_timer <= 0.0:
		_combat_bridge_timer = COMBAT_BRIDGE_INTERVAL
		_tick_combat_bridge()


# =============================================================================
# LOD EVALUATION
# =============================================================================

func _sync_node_positions() -> void:
	for id: StringName in _node_ids:
		var data: ShipLODData = _ships[id]
		if data.node_ref and is_instance_valid(data.node_ref):
			data.position = data.node_ref.global_position
			_grid.update_position(id, data.position)


var _sorted_ids: Array[StringName] = []

func _evaluate_lod_levels() -> void:
	if _camera == null:
		return
	var cam_pos := _camera.global_position

	_sorted_ids.resize(_ships.size())
	var idx: int = 0
	for id: StringName in _ships:
		var data: ShipLODData = _ships[id]
		data.distance_to_camera = cam_pos.distance_to(data.position)
		_sorted_ids[idx] = id
		idx += 1
	if idx < _sorted_ids.size():
		_sorted_ids.resize(idx)

	var ships_ref := _ships
	_sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return ships_ref[a].distance_to_camera < ships_ref[b].distance_to_camera)

	var lod0_count: int = 0
	var lod1_count: int = 0
	var promotions_this_tick: int = 0

	for id in _sorted_ids:
		var data: ShipLODData = _ships[id]

		if id == _player_id:
			if data.current_lod != ShipLODData.LODLevel.LOD0:
				_promote_to_lod0(id, data)
			continue

		var target_lod: ShipLODData.LODLevel
		if data.distance_to_camera < LOD0_DISTANCE and lod0_count < LOD0_MAX:
			target_lod = ShipLODData.LODLevel.LOD0
		elif data.distance_to_camera < LOD1_DISTANCE and lod1_count < LOD1_MAX:
			target_lod = ShipLODData.LODLevel.LOD1
		elif data.distance_to_camera < LOD2_DISTANCE:
			target_lod = ShipLODData.LODLevel.LOD2
		else:
			target_lod = ShipLODData.LODLevel.LOD3

		# Fleet ships: never demote below LOD1 — they need full AI (cruise, FleetAIBridge)
		if data.fleet_index >= 0 and target_lod > ShipLODData.LODLevel.LOD1:
			target_lod = ShipLODData.LODLevel.LOD1

		if target_lod != data.current_lod:
			var is_promotion := target_lod < data.current_lod
			if is_promotion and promotions_this_tick >= MAX_PROMOTIONS_PER_TICK:
				pass
			else:
				_transition_lod(id, data, target_lod)
				if is_promotion:
					promotions_this_tick += 1

		match data.current_lod:
			ShipLODData.LODLevel.LOD0: lod0_count += 1
			ShipLODData.LODLevel.LOD1: lod1_count += 1


func _transition_lod(id: StringName, data: ShipLODData, target: ShipLODData.LODLevel) -> void:
	var cur := data.current_lod
	var tgt := target

	if cur < tgt:
		while cur < tgt:
			match cur:
				ShipLODData.LODLevel.LOD0:
					_demote_lod0_to_lod1(id, data)
					cur = ShipLODData.LODLevel.LOD1
				ShipLODData.LODLevel.LOD1:
					_demote_lod1_to_lod2(id, data)
					cur = ShipLODData.LODLevel.LOD2
				ShipLODData.LODLevel.LOD2:
					_demote_lod2_to_lod3(id, data)
					cur = ShipLODData.LODLevel.LOD3
	else:
		while cur > tgt:
			match cur:
				ShipLODData.LODLevel.LOD3:
					_promote_lod3_to_lod2(id, data)
					cur = ShipLODData.LODLevel.LOD2
				ShipLODData.LODLevel.LOD2:
					_promote_lod2_to_lod1(id, data)
					cur = ShipLODData.LODLevel.LOD1
				ShipLODData.LODLevel.LOD1:
					_promote_to_lod0(id, data)
					cur = ShipLODData.LODLevel.LOD0


# =============================================================================
# LOD TRANSITIONS
# =============================================================================

func _demote_lod0_to_lod1(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node == null or not is_instance_valid(node):
		data.current_lod = ShipLODData.LODLevel.LOD1
		_set_lod_set(id, ShipLODData.LODLevel.LOD1)
		return

	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = false

	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS
		rb.collision_mask = 0

	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.weapons_enabled = true

	data.current_lod = ShipLODData.LODLevel.LOD1
	_set_lod_set(id, ShipLODData.LODLevel.LOD1)


func _demote_lod1_to_lod2(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node and is_instance_valid(node):
		data.capture_from_node(node)
		# Keep EntityRegistry entry (map needs it for all ship types), just null the node ref
		var ent := EntityRegistry.get_entity(String(node.name))
		if not ent.is_empty():
			ent["node"] = null
		node.queue_free()
	data.node_ref = null
	data.current_lod = ShipLODData.LODLevel.LOD2
	_set_lod_set(id, ShipLODData.LODLevel.LOD2)


func _demote_lod2_to_lod3(id: StringName, data: ShipLODData) -> void:
	data.current_lod = ShipLODData.LODLevel.LOD3
	_set_lod_set(id, ShipLODData.LODLevel.LOD3)


func _promote_lod3_to_lod2(id: StringName, data: ShipLODData) -> void:
	data.current_lod = ShipLODData.LODLevel.LOD2
	_set_lod_set(id, ShipLODData.LODLevel.LOD2)


func _promote_lod2_to_lod1(id: StringName, data: ShipLODData) -> void:
	if data.is_dead:
		return

	data.is_promoting = true

	var node: Node3D = null
	if data.is_remote_player:
		var remote := RemotePlayerShip.new()
		remote.peer_id = data.peer_id
		remote.set_player_name(data.display_name)
		remote.name = String(id)
		node = remote
	elif data.is_server_npc:
		var remote_npc := RemoteNPCShip.new()
		remote_npc.npc_id = id
		remote_npc.ship_id = data.ship_id
		remote_npc.faction = data.faction
		remote_npc.name = String(id)
		node = remote_npc
	else:
		var parent := _universe_node if _universe_node else get_tree().current_scene
		var spawn_id: StringName = data.ship_id if data.ship_id != &"" else data.ship_class
		var is_fleet: bool = data.fleet_index >= 0
		node = ShipFactory.spawn_npc_ship(
			spawn_id, data.behavior_name, data.position, parent, data.faction, true, is_fleet
		)
		if node == null:
			data.is_promoting = false
			return
		node.name = String(id)
		# Fleet ships: re-equip custom loadout + always process
		if is_fleet:
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			_reequip_fleet_ship(node, data.fleet_index)

	if (data.is_remote_player or data.is_server_npc) and _universe_node:
		_universe_node.add_child(node)

	node.global_position = data.position
	if node is RigidBody3D:
		(node as RigidBody3D).linear_velocity = data.velocity

	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS
		rb.collision_mask = 0

	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = false

	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.weapons_enabled = true
		brain.set_patrol_area(data.ai_patrol_center, data.ai_patrol_radius)

	data.node_ref = node
	data.current_lod = ShipLODData.LODLevel.LOD1
	_set_lod_set(id, ShipLODData.LODLevel.LOD1)
	data.is_promoting = false

	# Connect NPC fire relay on server when promoted to full node
	if not data.is_remote_player and not data.is_server_npc and NetworkManager.is_server():
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			npc_auth.connect_npc_fire_relay(id, node)

	# Restore EntityRegistry node ref (entity was kept during demotion)
	var ent := EntityRegistry.get_entity(String(id))
	if not ent.is_empty():
		ent["node"] = node
		# Restore fleet entity type (spawn_npc_ship re-registered as SHIP_NPC)
		if data.fleet_index >= 0:
			ent["type"] = EntityRegistrySystem.EntityType.SHIP_FLEET
			ent["extra"]["fleet_index"] = data.fleet_index
			ent["extra"]["owner_name"] = "Player"
			if GameManager.player_data and GameManager.player_data.fleet:
				var fleet := GameManager.player_data.fleet
				if data.fleet_index < fleet.ships.size():
					var fs := fleet.ships[data.fleet_index]
					ent["extra"]["command"] = String(fs.deployed_command)
					ent["extra"]["arrived"] = false
					ent["name"] = fs.custom_name if fs.custom_name != "" else data.display_name


func _promote_to_lod0(id: StringName, data: ShipLODData) -> void:
	var node := data.node_ref
	if node == null or not is_instance_valid(node):
		return

	var model := node.get_node_or_null("ShipModel") as ShipModel
	if model:
		for light: OmniLight3D in model._engine_lights:
			light.visible = true

	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.collision_layer = Constants.LAYER_SHIPS
		rb.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS

	var brain := node.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.set_process(true)
		brain.weapons_enabled = true

	data.current_lod = ShipLODData.LODLevel.LOD0
	_set_lod_set(id, ShipLODData.LODLevel.LOD0)


# =============================================================================
# MULTIMESH (LOD3 rendering — distant dots)
# =============================================================================

func _update_multimesh() -> void:
	if _multimesh == null:
		return

	var count: int = 0
	# First pass: count alive LOD3
	for id: StringName in _lod3_ids:
		var data: ShipLODData = _ships[id]
		if not data.is_dead:
			count += 1

	if _multimesh.instance_count < count:
		_multimesh.instance_count = count + 128
	_multimesh.visible_instance_count = count

	var idx: int = 0
	for id: StringName in _lod3_ids:
		var data: ShipLODData = _ships[id]
		if data.is_dead:
			continue
		# Billboard dot — position only, no rotation/scale needed
		var xform := Transform3D(Basis.IDENTITY, data.position)
		_multimesh.set_instance_transform(idx, xform)
		_multimesh.set_instance_color(idx, data.color_tint)
		idx += 1


# =============================================================================
# LOD2+LOD3 SIMPLE AI (data-only ships)
# =============================================================================

func _tick_data_only_ai(delta: float) -> void:
	for id: StringName in _lod2_ids:
		var data: ShipLODData = _ships[id]
		if not data.is_remote_player and not data.is_server_npc:
			data.tick_simple_ai(delta)
		_grid.update_position(id, data.position)
		_sync_entity_registry_position(id, data)
	for id: StringName in _lod3_ids:
		var data: ShipLODData = _ships[id]
		if not data.is_remote_player and not data.is_server_npc:
			data.tick_simple_ai(delta)
		_grid.update_position(id, data.position)
		_sync_entity_registry_position(id, data)


func _sync_entity_registry_position(id: StringName, data: ShipLODData) -> void:
	var ent := EntityRegistry.get_entity(String(id))
	if ent.is_empty():
		return
	var upos: Array = FloatingOrigin.to_universe_pos(data.position)
	ent["pos_x"] = upos[0]
	ent["pos_y"] = upos[1]
	ent["pos_z"] = upos[2]
	ent["vel_x"] = float(data.velocity.x)
	ent["vel_y"] = float(data.velocity.y)
	ent["vel_z"] = float(data.velocity.z)


# =============================================================================
# COMBAT BRIDGE (LOD1+LOD2+LOD3 statistical combat)
# =============================================================================

func _tick_combat_bridge() -> void:
	var class_dps := {
		&"Fighter": 18.0,
		&"Frigate": 65.0,
	}

	var dead_ids: Array[StringName] = []

	# Collect combatant IDs from LOD1+LOD2+LOD3 (skip LOD0 - handled by real AI)
	var combatant_ids: Array[StringName] = []
	for id: StringName in _lod1_ids:
		combatant_ids.append(id)
	for id: StringName in _lod2_ids:
		combatant_ids.append(id)
	for id: StringName in _lod3_ids:
		combatant_ids.append(id)

	for id: StringName in combatant_ids:
		var data: ShipLODData = _ships.get(id)
		if data == null:
			continue
		if data.is_dead or data.is_remote_player or data.is_server_npc:
			continue

		var nearby := _grid.query_radius(data.position, data.engagement_range)
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

		var target_data: ShipLODData = _ships.get(best_id)
		if target_data == null:
			continue

		var to_target := target_data.position - data.position
		if to_target.length_squared() > 100.0:
			data.velocity = data.velocity.lerp(to_target.normalized() * 60.0, COMBAT_BRIDGE_INTERVAL * 0.5)

		if target_data.current_lod == ShipLODData.LODLevel.LOD0 or target_data.current_lod == ShipLODData.LODLevel.LOD1:
			continue

		var dps: float = class_dps.get(data.ship_class, 15.0)
		var damage_this_tick := dps * COMBAT_BRIDGE_INTERVAL
		if target_data.shield_ratio > 0.0:
			target_data.shield_ratio = maxf(target_data.shield_ratio - damage_this_tick * 0.008, 0.0)
		else:
			target_data.hull_ratio = maxf(target_data.hull_ratio - damage_this_tick * 0.012, 0.0)

		if target_data.hull_ratio <= 0.0:
			target_data.is_dead = true
			if not dead_ids.has(best_id):
				dead_ids.append(best_id)

	for dead_id in dead_ids:
		unregister_ship(dead_id)


# =============================================================================
# FLEET SHIP RE-EQUIPMENT (after LOD re-promotion)
# =============================================================================

func _reequip_fleet_ship(npc: ShipController, fleet_index: int) -> void:
	var fleet: PlayerFleet = GameManager.player_data.fleet if GameManager.player_data else null
	if fleet == null or fleet_index < 0 or fleet_index >= fleet.ships.size():
		return
	var fs: FleetShip = fleet.ships[fleet_index]

	# Weapons
	var wm := npc.get_node_or_null("WeaponManager") as WeaponManager
	if wm:
		wm.equip_weapons(fs.weapons)

	# Shield / Engine / Modules
	var em := npc.get_node_or_null("EquipmentManager") as EquipmentManager
	if em == null:
		em = EquipmentManager.new()
		em.name = "EquipmentManager"
		npc.add_child(em)
		em.setup(npc.ship_data)
	if fs.shield_name != &"":
		var shield_res := ShieldRegistry.get_shield(fs.shield_name)
		if shield_res:
			em.equip_shield(shield_res)
	if fs.engine_name != &"":
		var engine_res := EngineRegistry.get_engine(fs.engine_name)
		if engine_res:
			em.equip_engine(engine_res)
	for i in fs.modules.size():
		if fs.modules[i] != &"":
			var mod_res := ModuleRegistry.get_module(fs.modules[i])
			if mod_res:
				em.equip_module(i, mod_res)

	# Re-attach FleetAIBridge + AIMiningBehavior
	if npc.get_node_or_null("FleetAIBridge") == null:
		var bridge := FleetAIBridge.new()
		bridge.name = "FleetAIBridge"
		bridge.fleet_index = fleet_index
		bridge.command = fs.deployed_command
		bridge.command_params = fs.deployed_command_params
		bridge._station_id = fs.docked_station_id
		npc.add_child(bridge)

	if fs.deployed_command == &"mine" and npc.get_node_or_null("AIMiningBehavior") == null:
		var mining_behavior := AIMiningBehavior.new()
		mining_behavior.name = "AIMiningBehavior"
		mining_behavior.fleet_index = fleet_index
		mining_behavior.fleet_ship = fs
		npc.add_child(mining_behavior)

	# Re-connect death signal
	var health := npc.get_node_or_null("HealthSystem") as HealthSystem
	var fdm := GameManager.get_node_or_null("FleetDeploymentManager") as FleetDeploymentManager
	if health and fdm:
		if not health.ship_destroyed.is_connected(fdm._on_fleet_npc_died):
			health.ship_destroyed.connect(fdm._on_fleet_npc_died.bind(fleet_index, npc))

	# Update deployed_ships ref
	if fdm:
		fdm._deployed_ships[fleet_index] = npc


# =============================================================================
# FLOATING ORIGIN
# =============================================================================

func _on_origin_shifted(shift: Vector3) -> void:
	for id: StringName in _lod2_ids:
		var data: ShipLODData = _ships[id]
		data.position -= shift
		data.ai_patrol_center -= shift
	for id: StringName in _lod3_ids:
		var data: ShipLODData = _ships[id]
		data.position -= shift
		data.ai_patrol_center -= shift

	_grid.apply_origin_shift(shift)
